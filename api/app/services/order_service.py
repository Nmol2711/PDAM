"""Entrega, reporte, cierre y cola de órdenes de dispensación (spec 014).

Responsabilidades de esta capa:

- `entregar_orden`: crea la orden pendiente que el dispositivo va a ejecutar, con
  la hora del servidor, sin modificar el stock (RF-13). La comida que estaba en
  espera se entrega aquí, nunca creando la orden por adelantado: el dispositivo
  solo recibe órdenes cuando consulta (RF-25).
- `procesar_reporte`: valida MAC, motivo y orden en ese orden, cierra la orden con
  el resultado que decide `domain/cierre.py`, descuenta lo medido acotado y
  escribe el registro **en la misma transacción** (RF-1, RF-14 a RF-24).
- `cerrar_vencidas`: cierra como `sin_reporte` las órdenes cuyo plazo más la
  tolerancia de 1 s ya venció, sin descuento y sin exigir reporte (RF-19, RF-40).
- `encolar_comida`: guarda en `dispensing_queue` cada ocurrencia programada una
  sola vez, aunque el dispensador esté ocupado o desactivado (RF-25).

La transición de la orden se hace siempre con `UPDATE ... WHERE status='pending'`
y `rowcount`, porque SQLite no bloquea filas: la escritura condicional deja un
único ganador entre dos reportes o entre un reporte y el barrido (RNF-3). La
misma condición se usa para reclamar una ocurrencia de la cola y para consumir
la bandera heredada, de modo que dos consultas simultáneas del dispositivo no
sirven dos veces la misma comida.

La hora de los horarios de comida se interpreta en la zona local del servidor;
las órdenes, los plazos y los registros se guardan y comparan en UTC (RNF-8).

La bandera heredada `dispensers.pending_dispensing` ya no es fuente de verdad ni
se acepta en `PUT /dispensers/{id}`: el planificador no la escribe y la cola no
la consulta. Solo se consume una vez si ya estaba puesta, como compatibilidad
con datos anteriores a esta spec.
"""

import math
from datetime import datetime, time, timedelta, tzinfo
from typing import Any, Optional

from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.domain import catalogos, cierre, stock, tiempo
from app.domain.catalogos import ErrorDominio
from app.models import models
from app.services import activity_service
from app.services.activity_service import NO_DISPONIBLE
from app.services.mac_service import mask_mac, normalize_mac

EVENTO_DISPENSADO = "feeding_dispensed"
ESTADO_PENDIENTE = "pending"
ESTADO_CERRADA = "closed"
CAUSA_SIN_REPORTE = "sin_reporte"

DESCRIPCION_EXITO = "Comida dispensada"
DESCRIPCION_FALLO = "Comida dispensada con fallo"
DESCRIPCION_SIN_REPORTE = "Comida dispensada sin reporte del dispositivo"
DESCRIPCION_ORDEN_DESCONOCIDA = "Reporte de una orden desconocida"

MENSAJE_ERROR_ESCRITURA = "Error interno al cerrar la orden de dispensación."
MENSAJE_ERROR_ENTREGA = "Error interno al entregar la orden de dispensación."
MENSAJE_DISPENSADOR_NO_REGISTRADO = "Dispositivo hardware no registrado."

# Intentos de una actualización relativa de stock cuando otra transacción cambia
# el valor entre la lectura y la escritura.
INTENTOS_ACTUALIZACION_STOCK = 5

# Respuesta de reposo: el dispositivo no tiene nada que dispensar.
REPOSO = {"serve": False, "amount": 0}


# --- Utilidades de conversión ------------------------------------------------


def _numero(valor: Any) -> Optional[float]:
    """Convierte un campo numérico permisivo del reporte en `float` o `None`.

    El esquema admite cualquier tipo para que el rechazo sea de negocio y nunca
    un 422; aquí se decide qué es un número. Acepta texto numérico porque el
    firmware puede serializar los gramos con comillas.

    Solo se admite un número finito: `NaN`, los infinitos y los desbordamientos
    de texto (`"1e999"`) no son medidas reales, así que se tratan como ausentes y
    se registran como «no disponible» (RF-24).
    """
    if valor is None or isinstance(valor, bool):
        return None

    if isinstance(valor, (int, float)):
        numero = float(valor)
    elif isinstance(valor, str):
        try:
            numero = float(valor.strip())
        except ValueError:
            return None
    else:
        return None

    return numero if math.isfinite(numero) else None


def _entero(valor: Any) -> Optional[int]:
    """Convierte un identificador o un contador en `int` o `None`."""
    numero = _numero(valor)
    if numero is None or numero != int(numero):
        return None
    return int(numero)


def _o_no_disponible(valor: Any) -> Any:
    """Devuelve el dato o el texto «no disponible» si falta (RF-24)."""
    return NO_DISPONIBLE if valor is None else valor


# --- Consultas auxiliares ----------------------------------------------------


def _dispensador_por_mac(db: Session, mac: Any) -> Optional[models.Dispenser]:
    """Busca el dispensador por la forma normalizada de la MAC recibida."""
    mac_normalizada = normalize_mac(mac)
    if not mac_normalizada:
        return None
    return (
        db.query(models.Dispenser)
        .filter(models.Dispenser.mac_normalized == mac_normalizada)
        .first()
    )


def _datos_de_la_mascota(db: Session, pet_id: Optional[int]) -> tuple[Optional[str], Optional[int]]:
    """Devuelve `(pet_name, user_id)` de la mascota, si todavía existe."""
    if pet_id is None:
        return None, None

    mascota = db.query(models.Pet).filter(models.Pet.id == pet_id).first()
    if mascota is None:
        return None, None
    return mascota.name, mascota.user_id


def _respuesta(orden: models.DispensingOrder, ya_cerrada: bool) -> dict:
    """Cuerpo de §5.2 con el resultado guardado en la orden."""
    return {
        "order_id": orden.id,
        "outcome": orden.outcome,
        "cause": orden.cause,
        "requested_grams": float(orden.requested_grams or 0.0),
        "measured_grams": orden.measured_grams,
        "discounted_grams": float(orden.discounted_grams or 0.0),
        "resulting_stock": float(orden.resulting_stock or 0.0),
        "ya_cerrada": ya_cerrada,
    }


def _ordenes_pendientes(db: Session, dispenser_id: int) -> list[models.DispensingOrder]:
    """Órdenes todavía pendientes del dispensador (con o sin plazo vencido)."""
    return (
        db.query(models.DispensingOrder)
        .filter(
            models.DispensingOrder.dispenser_id == dispenser_id,
            models.DispensingOrder.status == ESTADO_PENDIENTE,
        )
        .order_by(models.DispensingOrder.delivered_at, models.DispensingOrder.id)
        .all()
    )


def _crear_orden_pendiente(
    db: Session,
    dispensador: models.Dispenser,
    gramos: float,
    instante: datetime,
    pet_id: Optional[int] = None,
) -> models.DispensingOrder:
    """Instancia la orden pendiente con las instantáneas del dispensador (RF-13)."""
    pet_id = dispensador.pet_id if pet_id is None else pet_id
    nombre_mascota, user_id = _datos_de_la_mascota(db, pet_id)

    orden = models.DispensingOrder(
        user_id=user_id,
        pet_id=pet_id,
        pet_name=nombre_mascota,
        dispenser_id=dispensador.id,
        dispenser_mac_masked=mask_mac(dispensador.mac_address),
        requested_grams=gramos,
        delivered_at=instante,
        status=ESTADO_PENDIENTE,
    )
    db.add(orden)
    return orden


# --- Entrega de la orden -----------------------------------------------------


def entregar_orden(
    db: Session,
    mac_address: Any,
    ahora: Optional[datetime] = None,
    simular: bool = False,
) -> dict:
    """Entrega al dispositivo la orden pendiente, sin tocar el stock (RF-13).

    Devuelve `{serve, amount, order_id}` o el reposo `{serve: False, amount: 0}`.
    El reseteo de WiFi conserva prioridad absoluta y no crea orden. Un
    dispensador no registrado responde 404 sin escribir ningún registro (RF-2).

    Orden de comprobación de RF-25:
    1. una orden pendiente dentro de su plazo bloquea la entrega y **no** consume
       la comida en espera;
    2. una orden pendiente con el plazo vencido se cierra en esta misma consulta y
       la cola sigue esperando: la comida se entrega en la consulta siguiente;
    3. un dispensador desactivado no dispensa y tampoco consume la cola;
    4. si no hay bloqueo, se entrega la comida en espera más antigua.

    `simular=True` es el modo del endpoint de diagnóstico: responde lo mismo que
    la entrega real pero no escribe nada (ni orden, ni cierre, ni banderas).
    """
    instante = tiempo.a_utc_naive(ahora or tiempo.ahora_utc())

    dispensador = _dispensador_por_mac(db, mac_address)
    if dispensador is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=MENSAJE_DISPENSADOR_NO_REGISTRADO,
        )

    # Prioridad absoluta: el reseteo de credenciales se atiende antes que
    # cualquier dispensación y aunque el equipo esté desactivado.
    if dispensador.pending_wifi_reset:
        if not simular:
            dispensador.pending_wifi_reset = False
            db.commit()
        return {"serve": False, "amount": 0, "reset_wifi": True}

    pendientes = _ordenes_pendientes(db, dispensador.id)

    # RF-25: la orden pendiente dentro de su plazo bloquea la nueva entrega y la
    # comida programada sigue en la cola, sin consumirse.
    if any(
        tiempo.dentro_del_plazo(orden.delivered_at, instante) for orden in pendientes
    ):
        return dict(REPOSO)

    if pendientes:
        # Plazo vencido: el cierre libera el bloqueo, pero la comida en espera se
        # entrega en la consulta siguiente para no adelantar la dispensación.
        if simular:
            return dict(REPOSO)
        if cerrar_vencidas(db, instante, dispenser_id=dispensador.id):
            return dict(REPOSO)

    if not dispensador.is_active:
        # RF-25: desactivado no dispensa ni consume la cola; espera la reactivación.
        return dict(REPOSO)

    entrega = entregar_comida_en_espera(db, dispensador, instante, simular=simular)
    if entrega is not None:
        return entrega

    return _entregar_bandera_heredada(db, dispensador, instante, simular)


def _entregar_bandera_heredada(
    db: Session,
    dispensador: models.Dispenser,
    instante: datetime,
    simular: bool,
) -> dict:
    """Compatibilidad con la bandera `pending_dispensing` de datos anteriores.

    Ya no es fuente de verdad ni se acepta en `PUT /dispensers/{id}` (T5): el
    planificador no la escribe y la cola no la consulta. Se consume una sola vez
    si ya estaba puesta, como solicitud puntual para no romper una base que
    conserva la bandera de una versión anterior. La orden que crea es la misma
    entidad con plazo, reporte y cierre que las de la cola.
    """
    if not dispensador.pending_dispensing:
        return dict(REPOSO)

    horario = (
        db.query(models.Schedule)
        .filter(models.Schedule.pet_id == dispensador.pet_id)
        .first()
    )
    if horario is None:
        # Sin horario no hay cantidad que servir y la bandera no se consume.
        return dict(REPOSO)

    if simular:
        return {"serve": True, "amount": horario.amount}

    try:
        # Consumo atómico: dos consultas simultáneas no pueden servir la misma
        # bandera; la que pierde responde reposo (T5).
        filas = (
            db.query(models.Dispenser)
            .filter(
                models.Dispenser.id == dispensador.id,
                models.Dispenser.pending_dispensing.is_(True),
            )
            .update(
                {models.Dispenser.pending_dispensing: False},
                synchronize_session=False,
            )
        )
        if not filas:
            db.rollback()
            return dict(REPOSO)

        # La bandera se consume en la misma transacción que crea la orden para no
        # entregar dos veces la misma comida. Se refleja también en la instancia
        # para que la sesión no siga viéndola activa.
        dispensador.pending_dispensing = False
        orden = _crear_orden_pendiente(db, dispensador, horario.amount, instante)
        db.commit()
        db.refresh(orden)
    except IntegrityError:
        # Otra entrega creó antes la orden pendiente: el índice único parcial la
        # rechaza y la bandera vuelve a su estado anterior con el `rollback`.
        db.rollback()
        return dict(REPOSO)
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=MENSAJE_ERROR_ENTREGA,
        )

    return {
        "serve": True,
        "amount": horario.amount,
        "order_id": orden.id,
    }


# --- Reporte y cierre --------------------------------------------------------


def _registrar_orden_desconocida(
    db: Session,
    dispensador: models.Dispenser,
    reporte: Any,
    medidos: Optional[float],
    solicitados_reporte: Optional[float],
    reintentos: Optional[int],
    ahora: datetime,
) -> None:
    """Registra el fallo `orden_desconocida` en una sesión independiente (RF-21)."""
    pet_id = dispensador.pet_id
    nombre_mascota, user_id = _datos_de_la_mascota(db, pet_id)

    activity_service.registrar_rechazo(
        event_type=EVENTO_DISPENSADO,
        outcome=catalogos.FALLO,
        cause="orden_desconocida",
        description=DESCRIPCION_ORDEN_DESCONOCIDA,
        user_id=user_id,
        pet_id=pet_id,
        pet_name=nombre_mascota,
        dispenser_id=dispensador.id,
        dispenser_mac=dispensador.mac_address,
        context={
            "motivo": _o_no_disponible(reporte.motivo),
            "orden_reportada": _o_no_disponible(_entero(reporte.order_id)),
            "solicitados_reporte": _o_no_disponible(solicitados_reporte),
            "medidos": _o_no_disponible(medidos),
            "reintentos": _o_no_disponible(reintentos),
            "faltante": NO_DISPONIBLE,
        },
        requested_grams=None,
        measured_grams=medidos,
        discounted_grams=None,
        resulting_stock=None,
        retry_count=reintentos,
        created_at=ahora,
    )


def _descontar_stock_atomico(
    db: Session, dispenser_id: int, medidos: Optional[float]
) -> tuple[float, float, float]:
    """Descuenta lo medido con una actualización relativa y condicional.

    Devuelve `(descontados, faltante, stock_resultante)`. La escritura es
    `UPDATE ... SET stock = stock - :d WHERE id = :id AND stock - :d >= 0` y se
    comprueba `rowcount`: nunca escribe un valor absoluto calculado con una
    lectura previa, así que un reabastecimiento o un cierre simultáneo no se
    pisan (RNF-3). Si otra transacción cambió el stock entre la lectura y la
    escritura, se relee y se reintenta con el valor vigente; si no se consigue,
    se rechaza con `stock_fuera_de_rango`, el único código del catálogo para el
    stock.
    """
    for _ in range(INTENTOS_ACTUALIZACION_STOCK):
        actual = (
            db.query(models.Dispenser.current_food_grams)
            .filter(models.Dispenser.id == dispenser_id)
            .scalar()
        )
        if actual is None:
            raise ErrorDominio("stock_fuera_de_rango")

        # Valida el intervalo (RF-22) y acota el descuento al stock vigente.
        descontados, faltante, _ = stock.aplicar_descuento_acotado(actual, medidos)

        filas = (
            db.query(models.Dispenser)
            .filter(
                models.Dispenser.id == dispenser_id,
                models.Dispenser.current_food_grams - descontados >= 0,
            )
            .update(
                {
                    models.Dispenser.current_food_grams: (
                        models.Dispenser.current_food_grams - descontados
                    )
                },
                synchronize_session=False,
            )
        )
        if filas:
            resultante = (
                db.query(models.Dispenser.current_food_grams)
                .filter(models.Dispenser.id == dispenser_id)
                .scalar()
            )
            return descontados, faltante, float(resultante or 0.0)

        # La condición no se cumplió: otra transacción dejó el stock por debajo
        # de lo leído. La siguiente iteración relee el valor vigente.

    raise ErrorDominio("stock_fuera_de_rango")


def procesar_reporte(
    db: Session,
    reporte: Any,
    ahora: Optional[datetime] = None,
) -> dict:
    """Cierra la orden con el reporte del dispositivo y descuenta lo medido.

    Orden de comprobación (RF-21): MAC registrada → motivo del catálogo → orden
    del dispensador. Los dos primeros rechazos no escriben registro; el tercero
    sí, con causa `orden_desconocida`, en una transacción independiente.

    Un fallo de escritura revierte el cierre y el descuento y responde 5xx para
    que el dispositivo reintente (RF-1).
    """
    instante = tiempo.a_utc_naive(ahora or tiempo.ahora_utc())

    dispensador = _dispensador_por_mac(db, reporte.mac)
    if dispensador is None:
        raise ErrorDominio("mac_no_registrada")

    motivo = reporte.motivo
    if not catalogos.es_causa_de_reporte(motivo):
        raise ErrorDominio("motivo_invalido")

    medidos = _numero(reporte.gramos_medidos)
    solicitados_reporte = _numero(reporte.gramos_solicitados)
    reintentos = _entero(reporte.reintentos)
    order_id = _entero(reporte.order_id)

    orden = None
    if order_id is not None:
        orden = (
            db.query(models.DispensingOrder)
            .filter(
                models.DispensingOrder.id == order_id,
                models.DispensingOrder.dispenser_id == dispensador.id,
            )
            .first()
        )

    if orden is None:
        _registrar_orden_desconocida(
            db,
            dispensador,
            reporte,
            medidos,
            solicitados_reporte,
            reintentos,
            instante,
        )
        raise ErrorDominio("orden_desconocida")

    # RF-18: una orden cerrada no cambia de estado ni de resultado.
    if orden.status == ESTADO_CERRADA:
        db.rollback()
        return _respuesta(orden, ya_cerrada=True)

    stock_actual = float(dispensador.current_food_grams or 0.0)

    outcome, cause, tardio = cierre.resolver_cierre_por_reporte(
        motivo, orden.requested_grams, medidos, instante, orden.delivered_at
    )

    if outcome == catalogos.EXITO:
        # Validación previa sin escribir: un stock de partida fuera de rango se
        # rechaza con `stock_fuera_de_rango` (RF-22).
        stock.aplicar_descuento_acotado(stock_actual, medidos)

    descontados, faltante, stock_resultante = 0.0, 0.0, stock_actual

    contexto = {
        "motivo": motivo,
        "solicitados_reporte": _o_no_disponible(solicitados_reporte),
        "medidos": _o_no_disponible(medidos),
        "reintentos": _o_no_disponible(reintentos),
        "faltante": _o_no_disponible(faltante if outcome == catalogos.EXITO else None),
    }

    try:
        if outcome == catalogos.EXITO:
            # El descuento es una escritura relativa y condicional con `rowcount`
            # (RNF-3): dos cierres o un reabastecimiento simultáneo no pierden
            # gramos. Se ejecuta antes del registro para guardar el stock
            # resultante real; si la transición de la orden no gana, el
            # `rollback` revierte también este descuento.
            descontados, faltante, stock_resultante = _descontar_stock_atomico(
                db, dispensador.id, medidos
            )
            contexto["faltante"] = _o_no_disponible(faltante)

        # El registro se escribe primero para poder guardar su identificador en
        # la orden; si la transición no gana, el `rollback` lo descarta.
        registro = activity_service.registrar(
            db,
            event_type=EVENTO_DISPENSADO,
            outcome=outcome,
            cause=cause,
            description=(
                DESCRIPCION_EXITO if outcome == catalogos.EXITO else DESCRIPCION_FALLO
            ),
            user_id=orden.user_id,
            pet_id=orden.pet_id,
            pet_name=orden.pet_name,
            dispenser_id=orden.dispenser_id,
            dispenser_mac=dispensador.mac_address,
            context=contexto,
            order_id=orden.id,
            requested_grams=orden.requested_grams,
            measured_grams=medidos,
            discounted_grams=descontados if outcome == catalogos.EXITO else None,
            resulting_stock=stock_resultante,
            retry_count=reintentos,
            created_at=instante,
        )

        # Transición condicional: solo una transacción pasa de pendiente a
        # cerrada; las demás reciben `rowcount == 0` (RNF-3).
        filas = (
            db.query(models.DispensingOrder)
            .filter(
                models.DispensingOrder.id == orden.id,
                models.DispensingOrder.status == ESTADO_PENDIENTE,
            )
            .update(
                {
                    models.DispensingOrder.status: ESTADO_CERRADA,
                    models.DispensingOrder.closed_at: instante,
                    models.DispensingOrder.outcome: outcome,
                    models.DispensingOrder.cause: cause,
                    models.DispensingOrder.measured_grams: medidos,
                    models.DispensingOrder.discounted_grams: (
                        descontados if outcome == catalogos.EXITO else None
                    ),
                    models.DispensingOrder.resulting_stock: stock_resultante,
                    models.DispensingOrder.retry_count: reintentos,
                    models.DispensingOrder.log_id: registro.id,
                },
                synchronize_session=False,
            )
        )

        if not filas:
            # Otro reporte o el barrido cerraron la orden mientras se procesaba
            # este reporte: no hay segundo registro ni segundo descuento.
            db.rollback()
            actual = (
                db.query(models.DispensingOrder)
                .filter(models.DispensingOrder.id == orden.id)
                .first()
            )
            return _respuesta(actual, ya_cerrada=True)

        db.commit()
    except (ErrorDominio, HTTPException):
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=MENSAJE_ERROR_ESCRITURA,
        )

    return _respuesta(orden, ya_cerrada=tardio)


# --- Vencimiento del plazo ---------------------------------------------------


def cerrar_vencidas(
    db: Session,
    ahora: Optional[datetime] = None,
    dispenser_id: Optional[int] = None,
) -> list[int]:
    """Cierra las órdenes pendientes cuyo plazo más la tolerancia ya venció.

    Devuelve los identificadores efectivamente cerrados. Nunca cierra una orden
    en el límite exacto ni antes (RF-19), no modifica el stock y no exige ningún
    reporte, así que el firmware antiguo también queda cubierto (RF-40).

    Cada orden se resuelve en su propia transacción con la transición
    condicional `UPDATE ... WHERE status='pending'`, de modo que el barrido y un
    reporte simultáneo dejan un único ganador (RNF-3). Si una orden falla al
    escribirse, se revierte solo esa y el barrido continúa; el siguiente ciclo lo
    reintenta.
    """
    instante = tiempo.a_utc_naive(ahora or tiempo.ahora_utc())

    consulta = db.query(models.DispensingOrder).filter(
        models.DispensingOrder.status == ESTADO_PENDIENTE
    )
    if dispenser_id is not None:
        consulta = consulta.filter(
            models.DispensingOrder.dispenser_id == dispenser_id
        )

    # El filtro exacto lo decide `plazo_vencido`: el límite es inclusivo.
    candidatas = [
        orden.id
        for orden in consulta.all()
        if tiempo.plazo_vencido(orden.delivered_at, instante)
    ]

    cerradas: list[int] = []
    for order_id in candidatas:
        if _cerrar_vencida(db, order_id, instante):
            cerradas.append(order_id)
    return cerradas


def _cerrar_vencida(db: Session, order_id: int, instante: datetime) -> bool:
    """Cierra una única orden por vencimiento; `False` si otro la cerró antes."""
    orden = (
        db.query(models.DispensingOrder)
        .filter(models.DispensingOrder.id == order_id)
        .first()
    )
    if orden is None or orden.status != ESTADO_PENDIENTE:
        return False
    if not tiempo.plazo_vencido(orden.delivered_at, instante):
        return False

    dispensador = (
        db.query(models.Dispenser)
        .filter(models.Dispenser.id == orden.dispenser_id)
        .first()
    )
    stock_actual = (
        float(dispensador.current_food_grams or 0.0) if dispensador is not None else None
    )

    # Sin reporte no hay motivo, medidos ni reintentos: todo se registra como
    # «no disponible» en lugar de omitirse (RF-24).
    contexto = {
        "motivo": NO_DISPONIBLE,
        "solicitados_reporte": NO_DISPONIBLE,
        "medidos": NO_DISPONIBLE,
        "reintentos": NO_DISPONIBLE,
        "faltante": NO_DISPONIBLE,
    }

    try:
        registro = activity_service.registrar(
            db,
            event_type=EVENTO_DISPENSADO,
            outcome=catalogos.FALLO,
            cause=CAUSA_SIN_REPORTE,
            description=DESCRIPCION_SIN_REPORTE,
            user_id=orden.user_id,
            pet_id=orden.pet_id,
            pet_name=orden.pet_name,
            dispenser_id=orden.dispenser_id,
            # El dispensador puede haberse eliminado: en ese caso se conserva la
            # instantánea ya enmascarada de la propia orden.
            dispenser_mac=(
                dispensador.mac_address
                if dispensador is not None
                else orden.dispenser_mac_masked
            ),
            context=contexto,
            order_id=orden.id,
            requested_grams=orden.requested_grams,
            measured_grams=None,
            discounted_grams=None,
            resulting_stock=stock_actual,
            retry_count=None,
            created_at=instante,
        )

        filas = (
            db.query(models.DispensingOrder)
            .filter(
                models.DispensingOrder.id == orden.id,
                models.DispensingOrder.status == ESTADO_PENDIENTE,
            )
            .update(
                {
                    models.DispensingOrder.status: ESTADO_CERRADA,
                    models.DispensingOrder.closed_at: instante,
                    models.DispensingOrder.outcome: catalogos.FALLO,
                    models.DispensingOrder.cause: CAUSA_SIN_REPORTE,
                    models.DispensingOrder.measured_grams: None,
                    models.DispensingOrder.discounted_grams: None,
                    models.DispensingOrder.resulting_stock: stock_actual,
                    models.DispensingOrder.retry_count: None,
                    models.DispensingOrder.log_id: registro.id,
                },
                synchronize_session=False,
            )
        )

        if not filas:
            # Un reporte ganó la transición: se descarta el registro del barrido.
            db.rollback()
            return False

        # RF-19: el vencimiento no descuenta stock.
        db.commit()
        return True
    except Exception:
        db.rollback()
        return False


# --- Cola de comidas en espera ----------------------------------------------


def _ocurrencias_del_horario(texto: Any, instante_local: datetime) -> list[datetime]:
    """Ocurrencias de un horario `HH:MM` dentro de la ventana del barrido.

    `instante_local` es la hora local del servidor y la ocurrencia se guarda con
    esa misma forma (hora de pared sin zona): así el horario se interpreta en la
    zona local vigente y un cambio de zona no convierte las programaciones ya
    existentes. Se acepta la ocurrencia del día en curso y la del día anterior
    para cubrir la ventana que cruza medianoche.
    """
    try:
        hora, minuto = (int(parte) for parte in str(texto).split(":")[:2])
        hora_base = time(hour=hora, minute=minuto)
    except (TypeError, ValueError):
        return []

    ocurrencias = []
    for dia in (instante_local.date(), instante_local.date() - timedelta(days=1)):
        ocurrencia = datetime.combine(dia, hora_base)
        if instante_local - tiempo.VENTANA_OCURRENCIA < ocurrencia <= instante_local:
            ocurrencias.append(ocurrencia)
    return ocurrencias


def encolar_comida(
    db: Session,
    ahora: Optional[datetime] = None,
    zona: Optional[tzinfo] = None,
) -> list[int]:
    """Encola cada ocurrencia programada una sola vez (RF-25).

    La hora del horario se interpreta en la zona local del servidor; `ahora`
    puede venir en UTC (aware o naive) y aquí se convierte a esa hora local.
    `zona` inyecta el desplazamiento en las pruebas y por defecto es la zona
    local vigente. La clave única `(dispenser_id, schedule_id, scheduled_for)`
    impide duplicar la misma ocurrencia aunque el barrido se repita. La comida se
    encola aunque el dispensador esté ocupado o desactivado: no se pierde, se
    entrega al cerrar o vencer la orden anterior y al reactivarse el dispensador.

    Devuelve los identificadores de los elementos insertados.
    """
    instante_local = tiempo.a_local_naive(ahora or tiempo.ahora_utc(), zona)

    horarios = (
        db.query(models.Schedule, models.Dispenser)
        .join(models.Dispenser, models.Dispenser.pet_id == models.Schedule.pet_id)
        .all()
    )

    encoladas: list[int] = []
    for horario, dispensador in horarios:
        for ocurrencia in _ocurrencias_del_horario(horario.time, instante_local):
            ya_encolada = (
                db.query(models.DispensingQueue.id)
                .filter(
                    models.DispensingQueue.dispenser_id == dispensador.id,
                    models.DispensingQueue.schedule_id == horario.id,
                    models.DispensingQueue.scheduled_for == ocurrencia,
                )
                .first()
            )
            if ya_encolada is not None:
                continue

            try:
                # Punto de guardado por ocurrencia: una carrera con la clave
                # única descarta solo esta fila, no el lote completo.
                with db.begin_nested():
                    item = models.DispensingQueue(
                        dispenser_id=dispensador.id,
                        pet_id=horario.pet_id,
                        schedule_id=horario.id,
                        amount=horario.amount,
                        scheduled_for=ocurrencia,
                    )
                    db.add(item)
                    db.flush()
                    encoladas.append(item.id)
            except IntegrityError:
                continue

    db.commit()
    return encoladas


def entregar_comida_en_espera(
    db: Session,
    dispensador: models.Dispenser,
    ahora: Optional[datetime] = None,
    simular: bool = False,
) -> Optional[dict]:
    """Entrega la comida en espera más antigua del dispensador (RF-25).

    Devuelve `None` cuando no hay nada que entregar, de modo que el llamador
    pueda resolver el reposo. La ocurrencia se reclama con
    `UPDATE ... SET consumed_at = :ahora WHERE id = :id AND consumed_at IS NULL`
    y `rowcount`: si otra consulta ganó la reclamación, se descarta esa fila y se
    prueba la siguiente ocurrencia disponible. La reclamación y la creación de la
    orden se confirman en la misma transacción, así que una comida en espera se
    entrega exactamente una vez y sin tocar el stock (RF-13).

    El llamador comprueba antes que no hay una orden pendiente dentro de su plazo
    y que el dispensador está activo; esas dos condiciones son las que impiden
    reclamar la cola.
    """
    instante = tiempo.a_utc_naive(ahora or tiempo.ahora_utc())

    while True:
        item = (
            db.query(models.DispensingQueue)
            .filter(
                models.DispensingQueue.dispenser_id == dispensador.id,
                models.DispensingQueue.consumed_at.is_(None),
            )
            .order_by(
                models.DispensingQueue.scheduled_for, models.DispensingQueue.id
            )
            .first()
        )
        if item is None:
            return None

        # Se copian los datos antes de cualquier `rollback`: la instancia puede
        # quedar expirada cuando la reclamación la pierde otra transacción.
        item_id = item.id
        amount = item.amount
        pet_id = item.pet_id

        if simular:
            return {"serve": True, "amount": amount}

        try:
            # Reclamación atómica de la ocurrencia. SQLite no bloquea filas, así
            # que la condición `consumed_at IS NULL` y el `rowcount` son los que
            # dejan un único ganador entre dos consultas simultáneas (T5).
            filas = (
                db.query(models.DispensingQueue)
                .filter(
                    models.DispensingQueue.id == item_id,
                    models.DispensingQueue.consumed_at.is_(None),
                )
                .update(
                    {models.DispensingQueue.consumed_at: instante},
                    synchronize_session=False,
                )
            )
            if not filas:
                # Otra consulta ya sirvió esta ocurrencia: se libera la
                # transacción y se intenta con la siguiente disponible.
                db.rollback()
                continue

            orden = _crear_orden_pendiente(
                db, dispensador, amount, instante, pet_id=pet_id
            )
            db.commit()
            db.refresh(orden)
        except IntegrityError:
            # El índice único parcial impidió una segunda orden pendiente para el
            # mismo dispensador (RNF-3): otra entrega ganó. El `rollback` devuelve
            # la ocurrencia reclamada a la cola para la consulta siguiente.
            db.rollback()
            return dict(REPOSO)
        except Exception:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=MENSAJE_ERROR_ENTREGA,
            )

        return {"serve": True, "amount": amount, "order_id": orden.id}

