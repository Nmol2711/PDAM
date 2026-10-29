"""Dispensadores: vínculo, cambios, WiFi y reabastecimiento (specs 005, 012 y 014).

Cada operación confirmada escribe su registro de actividad en la **misma
transacción** que el cambio de estado (RF-2, RF-7 a RF-12): si el registro no se
puede escribir, la operación se revierte y el cliente recibe un error, de modo que
no queda un cambio sin trazabilidad.

Los registros de modificación guardan solo los **nombres** de los campos
modificados, la MAC siempre en su forma parcial y nunca SSID, credenciales,
tokens ni la MAC completa (RF-8, RF-10, RNF-1).

El reabastecimiento es la única operación que suma stock: lo hace en el servidor,
dentro de 0..5000 g (RF-22, RF-23), es idempotente por `(user_id, operation_id)`
(RF-11) y escribe el rechazo en una transacción aparte para que persista aunque
la operación no se confirme (RF-12).
"""

import math
from datetime import datetime
from typing import Any, Optional

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from fastapi import HTTPException, status

from app.domain import catalogos, stock as stock_domain, tiempo
from app.domain.catalogos import ErrorDominio
from app.models import models
from app.schemas import schemas
from app.services import activity_service, order_service, pet_service
from app.services.activity_service import NO_DISPONIBLE
from app.services.mac_service import (
    CODE_MAC_ALREADY_REGISTERED,
    CODE_MAC_IN_USE,
    CODE_PET_ALREADY_HAS_DISPENSER,
    MENSAJE_MAC_ALREADY_REGISTERED,
    MENSAJE_MAC_IN_USE,
    MENSAJE_PET_ALREADY_HAS_DISPENSER,
    mask_mac,
    normalize_mac,
    validate_mac_or_raise,
)

# Capacidad del depósito, en gramos. Se conserva el nombre público anterior para
# no romper a los llamadores existentes.
CAPACIDAD_MAXIMA_GRAMOS = stock_domain.CAPACIDAD_MAXIMA_GRAMOS

# Intentos de una actualización relativa de stock cuando otra transacción cambia
# el valor entre la lectura y la escritura.
INTENTOS_ACTUALIZACION_STOCK = 5

EVENTO_VINCULADO = "dispenser_linked"
EVENTO_ACTUALIZADO = "dispenser_updated"
EVENTO_DESVINCULADO = "dispenser_unlinked"
EVENTO_WIFI_REINICIADO = "dispenser_wifi_reset"
EVENTO_REABASTECIDO = "dispenser_refilled"

DESCRIPCION_VINCULADO = "Dispensador vinculado"
DESCRIPCION_ACTUALIZADO = "Dispensador modificado"
DESCRIPCION_DESVINCULADO = "Dispensador desvinculado"
DESCRIPCION_WIFI_REINICIADO = "WiFi del dispensador reiniciado"
DESCRIPCION_REABASTECIDO = "Dispensador reabastecido"
DESCRIPCION_REABASTECIMIENTO_RECHAZADO = "Reabastecimiento de dispensador rechazado"

# Campos del dispensador que se pueden modificar, en orden estable para el
# contexto del registro. `current_food_grams` no está: el stock solo lo calcula
# el servidor y el valor del cliente se ignora (RF-23).
CAMPOS_MODIFICABLES = ("pet_id", "mac_address", "is_active")

# Origen del reabastecimiento: los dos valores del catálogo de la spec 014. No
# existe un código de error para un origen desconocido, así que se normaliza al
# valor por defecto en lugar de inventar un rechazo (RNF-7).
ORIGEN_SERVIDOR = "servidor"
ORIGEN_SINCRONIZACION = "sincronizacion_sin_conexion"
ORIGENES = (ORIGEN_SERVIDOR, ORIGEN_SINCRONIZACION)

MENSAJE_ERROR_REABASTECIMIENTO = "Error interno al reabastecer el dispensador."


def _detalle(codigo: str, mensaje: str) -> dict:
    """Contrato de error de DO-5 y AC-4: `detail` es un objeto clasificable.

    El cliente decide por `code`; el `message` es la copia en español y es genérico,
    sin datos de la mascota, del usuario ni del dispensador en conflicto (RF-16).
    """
    return {"code": codigo, "message": mensaje}


def _error_de_negocio(error: ErrorDominio) -> HTTPException:
    """Convierte un rechazo de dominio en el 400 del catálogo de errores."""
    return HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error.detail)


def _contexto_del_dispensador(
    nombre_mascota: Optional[str], mac_address: Optional[str]
) -> dict:
    """Contexto común de los registros del dispensador, con la MAC parcial."""
    return {"mascota": nombre_mascota, "mac": mask_mac(mac_address)}


def _propietario(
    db: Session, pet_id: Optional[int], user_id: Optional[int] = None
) -> Optional[int]:
    """Propietario de la mascota del dispensador; el `user_id` es el respaldo."""
    _, dueno = pet_service.nombre_y_propietario(db, pet_id)
    return dueno if dueno is not None else user_id


def create_new_dispenser(
    db: Session,
    new_dispenser: schemas.DispenserCreate,
    user_id: Optional[int] = None,
):
    """Vincula un dispensador nuevo y registra `dispenser_linked` (RF-7)."""
    # 1. Validar el formato antes de tocar la base de datos. La comparación posterior
    # se hace siempre con la forma canónica devuelta (RF-02, RF-06).
    mac_normalizada = validate_mac_or_raise(new_dispenser.mac_address)

    # 2. Validar si el hardware ya existe por su forma normalizada, de modo que
    # cualquier formato equivalente cuenta como la misma MAC (RF-03).
    if exist_dispensar(db=db, mac_normalizada=mac_normalizada):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=_detalle(CODE_MAC_ALREADY_REGISTERED, MENSAJE_MAC_ALREADY_REGISTERED),
        )

    # 3. Validar la relación 1-a-1 (regla existente, solo cambia su código de error)
    if has_pet_dispenser(db=db, pet_id=new_dispenser.pet_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=_detalle(CODE_PET_ALREADY_HAS_DISPENSER, MENSAJE_PET_ALREADY_HAS_DISPENSER),
        )

    nombre_mascota, dueno = pet_service.nombre_y_propietario(db, new_dispenser.pet_id)

    # 4. Creación del registro si todo está OK. `mac_address` conserva el texto tal
    # como lo introdujo el usuario y `mac_normalized` la forma comparable (DO-2).
    dispenser_db = models.Dispenser(
        mac_address=new_dispenser.mac_address,
        mac_normalized=mac_normalizada,
        pet_id=new_dispenser.pet_id,
        is_active=True,
        current_food_grams=5000.0,
    )

    try:
        db.add(dispenser_db)
        db.flush()
        activity_service.registrar(
            db,
            event_type=EVENTO_VINCULADO,
            outcome=catalogos.EXITO,
            description=DESCRIPCION_VINCULADO,
            user_id=dueno if dueno is not None else user_id,
            pet_id=new_dispenser.pet_id,
            pet_name=nombre_mascota,
            dispenser_id=dispenser_db.id,
            dispenser_mac=dispenser_db.mac_address,
            context=_contexto_del_dispensador(nombre_mascota, dispenser_db.mac_address),
        )
        db.commit()
        db.refresh(dispenser_db)
        return schemas.Dispenser.model_validate(dispenser_db)
    except IntegrityError:
        # RF-07: la comprobación previa no cubre la carrera entre dos altas simultáneas.
        # El índice único de `mac_normalized` es la garantía real de unicidad.
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=_detalle(CODE_MAC_ALREADY_REGISTERED, MENSAJE_MAC_ALREADY_REGISTERED),
        )
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error interno del servidor al vincular el dispensador.",
        )


def has_pet_dispenser(db: Session, pet_id: int):
    try:
        result = db.query(models.Dispenser).filter(models.Dispenser.pet_id == pet_id).first()
        if result:
            return schemas.Dispenser.model_validate(result)
        else:
            return None

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error interno del servidor en la validación: {str(e)}",
        )


def exist_dispensar(db: Session, mac_normalizada: str, excluir_id: int | None = None) -> bool:
    """Indica si la forma canónica ya está registrada.

    Solo compara `mac_normalized`, nunca el texto: así todos los formatos
    equivalentes de una misma dirección se consideran el mismo hardware (RF-02).
    `excluir_id` permite ignorar el propio dispensador en una modificación (RF-05).
    """
    try:
        consulta = db.query(models.Dispenser).filter(models.Dispenser.mac_normalized == mac_normalizada)
        if excluir_id is not None:
            consulta = consulta.filter(models.Dispenser.id != excluir_id)
        return consulta.first() is not None

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error interno del servidor en la validación: {str(e)}",
        )


def update_dispenser(
    db: Session,
    dispenser_id: int,
    dispenser_update: schemas.DispenserUpdate,
    user_id: Optional[int] = None,
):
    """Modifica el dispensador y registra solo los nombres de los campos (RF-8).

    El stock no es modificable por esta vía: `current_food_grams` se acepta pero
    se ignora y la respuesta lleva el valor del servidor (RF-23).
    """

    # 1. Verificar si el dispensador que se quiere actualizar realmente existe
    dispenser_db = db.query(models.Dispenser).filter(models.Dispenser.id == dispenser_id).first()
    if not dispenser_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró ningún dispensador con el ID {dispenser_id}.",
        )

    campos: list[str] = []

    # 2. Si se intenta actualizar la dirección MAC, se compara por forma normalizada:
    # cambiar mayúsculas, guiones o espacios no es cambiar de dirección (CL-4, RF-05).
    if dispenser_update.mac_address is not None:
        mac_normalizada = validate_mac_or_raise(dispenser_update.mac_address)
        # Las filas anteriores a `mac_normalized` pueden tenerlo vacío: se normaliza su
        # texto para no confundir un formato distinto con una dirección nueva.
        actual_normalizada = dispenser_db.mac_normalized or normalize_mac(dispenser_db.mac_address)

        if mac_normalizada != actual_normalizada:
            if exist_dispensar(db=db, mac_normalizada=mac_normalizada, excluir_id=dispenser_db.id):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=_detalle(CODE_MAC_IN_USE, MENSAJE_MAC_IN_USE),
                )

            dispenser_db.mac_normalized = mac_normalizada
            dispenser_db.mac_address = dispenser_update.mac_address
            campos.append("mac_address")

    # 3. Si se intenta cambiar o asignar una mascota, validar las reglas relacionales
    if dispenser_update.pet_id is not None and dispenser_update.pet_id != dispenser_db.pet_id:
        # Validar la relación 1-a-1 (Que la nueva mascota no tenga ya otro equipo asignado)
        if has_pet_dispenser(db=db, pet_id=dispenser_update.pet_id):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=_detalle(CODE_PET_ALREADY_HAS_DISPENSER, MENSAJE_PET_ALREADY_HAS_DISPENSER),
            )
        dispenser_db.pet_id = dispenser_update.pet_id
        campos.append("pet_id")

    # 4. Aplicar los cambios. `pending_dispensing` no se actualiza: la comida
    # programada vive en la cola del servidor (spec 014, T5) y la bandera solo se
    # consume si ya estaba puesta por una versión anterior.
    if dispenser_update.is_active is not None and dispenser_update.is_active != dispenser_db.is_active:
        dispenser_db.is_active = dispenser_update.is_active
        campos.append("is_active")

    # 5. `current_food_grams` se sigue aceptando por compatibilidad, pero se
    # ignora: el stock solo lo calcula el servidor con los descuentos y los
    # reabastecimientos confirmados (RF-23). El cliente recibe el stock del
    # servidor en la respuesta y el campo no cuenta como modificado.

    nombre_mascota, dueno = pet_service.nombre_y_propietario(db, dispenser_db.pet_id)
    contexto = _contexto_del_dispensador(nombre_mascota, dispenser_db.mac_address)
    contexto["campos_modificados"] = [
        campo for campo in CAMPOS_MODIFICABLES if campo in campos
    ]

    try:
        db.flush()
        activity_service.registrar(
            db,
            event_type=EVENTO_ACTUALIZADO,
            outcome=catalogos.EXITO,
            description=DESCRIPCION_ACTUALIZADO,
            user_id=dueno if dueno is not None else user_id,
            pet_id=dispenser_db.pet_id,
            pet_name=nombre_mascota,
            dispenser_id=dispenser_db.id,
            dispenser_mac=dispenser_db.mac_address,
            context=contexto,
        )
        db.commit()
        db.refresh(dispenser_db)
        return schemas.Dispenser.model_validate(dispenser_db)

    except IntegrityError:
        # RF-07: si otra fila toma la forma normalizada entre la comprobación y el
        # commit, manda el índice único y el cambio se rechaza como conflicto.
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=_detalle(CODE_MAC_IN_USE, MENSAJE_MAC_IN_USE),
        )
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error interno del servidor al actualizar el dispensador.",
        )


def check_pending_task(db: Session, mac_address: str, test: bool = False) -> dict:
    """Entrega al hardware su tarea pendiente sin modificar el stock (RF-13).

    La lógica vive en `order_service.entregar_orden`: crea la orden de
    dispensación con la hora del servidor y devuelve su `order_id` para que el
    dispositivo pueda reportar el resultado del ciclo. `test=True` es el modo de
    diagnóstico del endpoint `check-taks-test`: responde sin escribir nada.
    """
    return order_service.entregar_orden(db, mac_address, simular=test)


# --- Reabastecimiento --------------------------------------------------------


def _numero_de_cantidad(valor: Any) -> Optional[float]:
    """Interpreta la cantidad recibida como número finito, sin exigir que sea válida.

    Devuelve `None` cuando no hay número que auditar (texto no numérico, objeto,
    booleano o valor no finito), para registrarlo como «no disponible» en el
    contexto del rechazo (RF-12, RF-24).
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


def _cantidad_intentada(amount: Any, unit: Any) -> Any:
    """Cantidad del rechazo en gramos si es convertible, o el número tal cual."""
    try:
        return stock_domain.normalizar_gramos(amount, unit)
    except ErrorDominio:
        numero = _numero_de_cantidad(amount)
        return NO_DISPONIBLE if numero is None else numero


def _origen_normalizado(origen: Any) -> str:
    """Origen del reabastecimiento dentro de los dos valores del catálogo."""
    if isinstance(origen, str) and origen.strip() in ORIGENES:
        return origen.strip()
    return ORIGEN_SERVIDOR


def _operation_id(valor: Any) -> Optional[str]:
    """Identificador de la operación de la app, o `None` si no lo envió."""
    if isinstance(valor, str) and valor.strip():
        return valor.strip()
    return None


def _operacion_ya_aplicada(
    db: Session, user_id: Optional[int], operation_id: str
) -> bool:
    """Indica si el usuario ya aplicó esa operación de reabastecimiento (RF-11)."""
    if user_id is None:
        return False

    return (
        db.query(models.RefillOperation)
        .filter(
            models.RefillOperation.user_id == user_id,
            models.RefillOperation.operation_id == operation_id,
        )
        .first()
        is not None
    )


def _stock_vigente(db: Session, dispenser_id: int) -> Optional[float]:
    """Lee el stock actual de la base, sin la caché de la sesión."""
    valor = (
        db.query(models.Dispenser.current_food_grams)
        .filter(models.Dispenser.id == dispenser_id)
        .scalar()
    )
    return None if valor is None else float(valor)


def _sumar_stock_atomico(db: Session, dispenser_id: int, gramos: float) -> float:
    """Suma el reabastecimiento con `UPDATE ... WHERE stock + :g <= 5000`.

    Devuelve el stock resultante releído. La capacidad se comprueba en la misma
    escritura y se mira `rowcount`: si otra transacción cambió el stock entre la
    lectura y la escritura, se reintenta con el valor vigente. Un fallo repetido
    se traduce a `supera_capacidad`, el código del catálogo (RF-12, RF-22).
    """
    for _ in range(INTENTOS_ACTUALIZACION_STOCK):
        filas = (
            db.query(models.Dispenser)
            .filter(
                models.Dispenser.id == dispenser_id,
                models.Dispenser.current_food_grams + gramos
                <= stock_domain.CAPACIDAD_MAXIMA_GRAMOS,
            )
            .update(
                {
                    models.Dispenser.current_food_grams: (
                        models.Dispenser.current_food_grams + gramos
                    )
                },
                synchronize_session=False,
            )
        )
        if filas:
            return _stock_vigente(db, dispenser_id) or 0.0

        # Si la condición no se cumple con el valor vigente, la capacidad está
        # superada de verdad: no tiene sentido seguir intentando.
        vigente = _stock_vigente(db, dispenser_id)
        if vigente is not None:
            stock_domain.aplicar_reabastecimiento(vigente, gramos, "g")

    raise ErrorDominio("supera_capacidad")


def _registrar_rechazo_de_reabastecimiento(
    db: Session,
    dispensador: models.Dispenser,
    codigo: str,
    cantidad_intentada: Any,
    origen: str,
    stock_actual: float,
    user_id: Optional[int],
    instante: datetime,
) -> None:
    """Escribe el registro de fallo en una transacción independiente (RF-12).

    La operación rechazada no se confirma, así que el registro se escribe en su
    propia sesión: de otro modo el `rollback` del llamador lo borraría. No guarda
    credenciales ni la MAC completa, solo la MAC parcial y la cantidad intentada.
    """
    nombre_mascota, dueno = pet_service.nombre_y_propietario(db, dispensador.pet_id)

    activity_service.registrar_rechazo(
        event_type=EVENTO_REABASTECIDO,
        outcome=catalogos.FALLO,
        cause=codigo,
        description=DESCRIPCION_REABASTECIMIENTO_RECHAZADO,
        user_id=dueno if dueno is not None else user_id,
        pet_id=dispensador.pet_id,
        pet_name=nombre_mascota,
        dispenser_id=dispensador.id,
        dispenser_mac=dispensador.mac_address,
        context={
            "origen": origen,
            "cantidad_intentada": cantidad_intentada,
            "stock_resultante": stock_actual,
        },
        resulting_stock=stock_actual,
        created_at=instante,
    )


def refill_dispenser(
    db: Session,
    dispenser_id: int,
    refill_data: schemas.DispenserRefillRequest,
    user_id: Optional[int] = None,
    ahora: Optional[datetime] = None,
):
    """Reabastece el dispensador con idempotencia, origen y registro (RF-11, RF-12).

    Orden de comprobación: dispensador existente (404 sin registro) → operación ya
    aplicada (devuelve el stock actual sin sumar ni registrar) → cantidad válida
    (400 `cantidad_invalida`) → capacidad (400 `supera_capacidad`). Los dos
    rechazos dejan el stock intacto y escriben su registro de fallo en una sesión
    independiente. La hora del registro es la del servidor en el momento de la
    operación: para un reabastecimiento sincronizado, la de la sincronización.
    """
    instante = tiempo.a_utc_naive(ahora or tiempo.ahora_utc())

    dispenser_db = db.query(models.Dispenser).filter(models.Dispenser.id == dispenser_id).first()
    if not dispenser_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró ningún dispensador con el ID {dispenser_id}.",
        )

    propietario = _propietario(db, dispenser_db.pet_id, user_id)
    origen = _origen_normalizado(refill_data.origen)
    operation_id = _operation_id(refill_data.operation_id)

    # RF-11: un reintento de la app no vuelve a sumar ni a registrar. El cliente
    # recibe el stock autoritativo del servidor (RF-23).
    if operation_id is not None and _operacion_ya_aplicada(db, propietario, operation_id):
        db.refresh(dispenser_db)
        return schemas.Dispenser.model_validate(dispenser_db)

    stock_actual = max(0.0, float(dispenser_db.current_food_grams or 0.0))

    try:
        gramos = stock_domain.normalizar_gramos(refill_data.amount, refill_data.unit)
    except ErrorDominio as error:
        _registrar_rechazo_de_reabastecimiento(
            db,
            dispenser_db,
            error.code,
            _cantidad_intentada(refill_data.amount, refill_data.unit),
            origen,
            stock_actual,
            user_id,
            instante,
        )
        raise _error_de_negocio(error)

    nombre_mascota, _ = pet_service.nombre_y_propietario(db, dispenser_db.pet_id)

    try:
        # El incremento es relativo y condicional con `rowcount` (RNF-3): se suma
        # al stock vigente y la capacidad se comprueba en la misma escritura, de
        # modo que dos reabastecimientos o un cierre simultáneo no se pisan.
        nuevo_stock = _sumar_stock_atomico(db, dispenser_db.id, gramos)

        # El registro se escribe antes de confirmar para poder guardar su
        # identificador en la operación idempotente; el mismo `commit` confirma el
        # incremento, el registro y la operación (RF-11).
        registro = activity_service.registrar(
            db,
            event_type=EVENTO_REABASTECIDO,
            outcome=catalogos.EXITO,
            description=DESCRIPCION_REABASTECIDO,
            user_id=propietario,
            pet_id=dispenser_db.pet_id,
            pet_name=nombre_mascota,
            dispenser_id=dispenser_db.id,
            dispenser_mac=dispenser_db.mac_address,
            context={
                "origen": origen,
                "gramos_anadidos": gramos,
                "stock_resultante": nuevo_stock,
            },
            resulting_stock=nuevo_stock,
            created_at=instante,
        )

        if operation_id is not None and propietario is not None:
            db.add(
                models.RefillOperation(
                    user_id=propietario,
                    operation_id=operation_id,
                    dispenser_id=dispenser_db.id,
                    grams=gramos,
                    applied_at=instante,
                    log_id=registro.id,
                )
            )

        db.commit()
        db.refresh(dispenser_db)
        return schemas.Dispenser.model_validate(dispenser_db)
    except ErrorDominio as error:
        # Capacidad superada: se revierte cualquier escritura, se relee el stock
        # vigente (sin cambios) y el rechazo se registra en una sesión aparte
        # (RF-12).
        db.rollback()
        stock_vigente = _stock_vigente(db, dispenser_id) or stock_actual
        _registrar_rechazo_de_reabastecimiento(
            db,
            dispenser_db,
            error.code,
            _cantidad_intentada(refill_data.amount, refill_data.unit),
            origen,
            stock_vigente,
            user_id,
            instante,
        )
        raise _error_de_negocio(error)
    except IntegrityError:
        # Otra petición con el mismo `operation_id` ganó la clave única: no hay
        # doble incremento ni segundo registro.
        db.rollback()
        actual = (
            db.query(models.Dispenser)
            .filter(models.Dispenser.id == dispenser_id)
            .first()
        )
        return schemas.Dispenser.model_validate(actual)
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=MENSAJE_ERROR_REABASTECIMIENTO,
        )


def delete_dispenser(db: Session, pet_id: int, user_id: Optional[int] = None) -> bool:
    """Desvincula el dispensador de la mascota y registra `dispenser_unlinked`."""
    try:
        dispenser = db.query(models.Dispenser).filter(models.Dispenser.pet_id == pet_id).first()

        if dispenser is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="La mascota no tiene ningun dispensador asignado.",
            )

        nombre_mascota, dueno = pet_service.nombre_y_propietario(db, pet_id)

        activity_service.registrar(
            db,
            event_type=EVENTO_DESVINCULADO,
            outcome=catalogos.EXITO,
            description=DESCRIPCION_DESVINCULADO,
            user_id=dueno if dueno is not None else user_id,
            pet_id=pet_id,
            pet_name=nombre_mascota,
            dispenser_id=dispenser.id,
            dispenser_mac=dispenser.mac_address,
            context=_contexto_del_dispensador(nombre_mascota, dispenser.mac_address),
        )
        db.delete(dispenser)
        db.commit()
        return True
    except HTTPException:
        # Un dispensador inexistente no es un fallo de escritura: se propaga el 404
        # sin dejar registro (RF-2).
        db.rollback()
        raise
    except Exception:
        # Si el registro no se puede escribir no se confirma el borrado: no queda
        # una desvinculación sin trazabilidad.
        db.rollback()
        return False


def reset_wifi_credentials(
    db: Session,
    dispenser_id: int,
    user_id: Optional[int] = None,
):
    """Pide el reseteo de WiFi y registra el evento sin SSID ni credenciales (RF-10)."""
    dispenser_db = db.query(models.Dispenser).filter(models.Dispenser.id == dispenser_id).first()
    if not dispenser_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No se encontró ningún dispensador con el ID {dispenser_id}.",
        )

    nombre_mascota, dueno = pet_service.nombre_y_propietario(db, dispenser_db.pet_id)

    dispenser_db.pending_wifi_reset = True
    try:
        db.flush()
        activity_service.registrar(
            db,
            event_type=EVENTO_WIFI_REINICIADO,
            outcome=catalogos.EXITO,
            description=DESCRIPCION_WIFI_REINICIADO,
            user_id=dueno if dueno is not None else user_id,
            pet_id=dispenser_db.pet_id,
            pet_name=nombre_mascota,
            dispenser_id=dispenser_db.id,
            dispenser_mac=dispenser_db.mac_address,
            context=_contexto_del_dispensador(nombre_mascota, dispenser_db.mac_address),
        )
        db.commit()
        db.refresh(dispenser_db)
        return schemas.DispenserWiFiResetResponse(
            success=True,
            message="Orden de reseteo de credenciales WiFi enviada exitosamente al dispensador.",
            dispenser_id=dispenser_db.id,
            mac_address=dispenser_db.mac_address,
        )
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error interno al procesar el reseteo de WiFi.",
        )
