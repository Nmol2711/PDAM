"""Concurrencia del cierre de órdenes (spec 014, T4; RNF-3).

Comprueba que la transición `UPDATE ... WHERE status='pending'` con `rowcount`
deja un único ganador: dos reportes de la misma orden, cada uno en su propia
sesión, producen un único cierre, un único registro y un único descuento de
stock. La prueba se hace con hilos reales y con dos sesiones que leyeron la
orden como pendiente antes de que la otra cerrara.

Las pruebas de stock (`TestStockConcurrente`) no se fían del planificador: usan
`PausaAntesDeEscribirStock`, que detiene un hilo justo después de leer el stock y
antes de escribirlo. Así la ventana de lectura→escritura deja de medir
microsegundos y el intercalado que debe detectar un `lost update` es fijo.
"""

import os
import re
import sys
import threading
import unittest
from datetime import date, datetime, timezone
from pathlib import Path

from sqlalchemy import event

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from app.db.database import SessionLocal, engine
from app.models import models
from app.schemas.dispenser import DispenserRefillRequest
from app.schemas.reports import DispenserReportRequest
from app.services import dispenser_service, order_service

MAC = "AA:BB:CC:DD:AB:1F"
AHORA = datetime(2026, 10, 1, 12, 0, 0, tzinfo=timezone.utc)
SOLICITADOS = 50.0
STOCK_INICIAL = 1000.0

# Segundos que se espera a que un hilo armado llegue a la pausa o a que la
# libere. Es un tope de seguridad: el intercalado no depende de este valor.
PAUSA_TIMEOUT = 15.0

HILO_CIERRE = "cierre"
HILO_REABASTECIMIENTO = "reabastecimiento"


class _Pausa:
    """Estado de un hilo detenido en el punto de control.

    `alcanzada` avisa de que el hilo ya leyó el stock y espera para escribirlo;
    `liberar` es el permiso de la prueba para que continúe. `sentencias_previas`
    guarda las sentencias de ese hilo que tocaron el stock antes de la pausa: es
    la evidencia de que la lectura obsoleta ya ocurrió y la prueba no es vacía.
    """

    def __init__(self):
        self.alcanzada = threading.Event()
        self.liberar = threading.Event()
        self.sentencias_previas: list[str] = []

    def esperar(self, timeout: float = PAUSA_TIMEOUT) -> bool:
        return self.alcanzada.wait(timeout)

    def continuar(self) -> None:
        self.liberar.set()

    def leyo_el_stock(self) -> bool:
        return any(
            sentencia.upper().startswith("SELECT") for sentencia in self.sentencias_previas
        )


class PausaAntesDeEscribirStock:
    """Punto de pausa controlado antes de escribir `dispensers.current_food_grams`.

    Se engancha al evento `before_cursor_execute` de SQLAlchemy, sin tocar el
    código de producción: cuando un hilo armado va a ejecutar el `UPDATE` del
    stock, el evento lo bloquea hasta que la prueba lo libere. El `SELECT` del
    stock ya se emitió, así que la pausa cae justo en la ventana lectura→escritura
    donde aparece un `lost update` (RNF-3, RF-15).

    Cualquier implementación que lea el stock y después escriba un valor absoluto
    se detiene en el mismo punto, de modo que la prueba distingue la escritura
    relativa de la absoluta sin depender de tiempos ni del número de sentencias.
    """

    PATRON_ESCRITURA = re.compile(
        r"^\s*UPDATE\s+dispensers\s+SET\s+current_food_grams\s*=", re.IGNORECASE
    )

    def __init__(self):
        self._pausas: dict[str, _Pausa] = {}
        self._sentencias: dict[str, list[str]] = {}
        self._candado = threading.Lock()

    def __enter__(self):
        event.listen(engine, "before_cursor_execute", self._al_ejecutar)
        return self

    def __exit__(self, *_):
        event.remove(engine, "before_cursor_execute", self._al_ejecutar)
        # Si la prueba falla antes de liberar, ningún hilo queda bloqueado.
        with self._candado:
            pausas = list(self._pausas.values())
            self._pausas.clear()
        for pausa in pausas:
            pausa.continuar()
        return False

    def armar(self, nombre_hilo: str) -> _Pausa:
        """Arma la pausa para el hilo `nombre_hilo`, que debe existir todavía."""
        pausa = _Pausa()
        with self._candado:
            self._pausas[nombre_hilo] = pausa
            self._sentencias.setdefault(nombre_hilo, [])
        return pausa

    def _al_ejecutar(self, _conexion, _cursor, sentencia, _parametros, _contexto, _muchas):
        if "current_food_grams" not in sentencia:
            return

        nombre = threading.current_thread().name
        pausa = None
        with self._candado:
            if nombre not in self._pausas:
                return
            self._sentencias[nombre].append(sentencia.strip().splitlines()[0])
            if self.PATRON_ESCRITURA.match(sentencia):
                pausa = self._pausas.pop(nombre)
                pausa.sentencias_previas = list(self._sentencias[nombre])

        if pausa is None:
            return

        pausa.alcanzada.set()
        if not pausa.liberar.wait(timeout=PAUSA_TIMEOUT):
            raise RuntimeError(
                f"La pausa del hilo '{nombre}' no se liberó en {PAUSA_TIMEOUT} s"
            )


class BaseConcurrenciaTests(unittest.TestCase):
    def setUp(self):
        self._limpiar_base_de_datos()
        self.usuario = self._guardar(
            models.User(email="dueno@concurrencia.test", hashed_password="hash", is_active=True)
        )
        self.mascota = self._guardar(
            models.Pet(
                name="Milo",
                species="perro",
                birth_date=date(2023, 1, 1),
                weight=5.5,
                reproductive_status=False,
                user_id=self.usuario.id,
            )
        )
        self.dispensador = self._guardar(
            models.Dispenser(
                mac_address=MAC,
                mac_normalized="AABBCCDDAB1F",
                pet_id=self.mascota.id,
                is_active=True,
                pending_dispensing=True,
                pending_wifi_reset=False,
                current_food_grams=STOCK_INICIAL,
            )
        )
        self.horario = self._guardar(
            models.Schedule(time="08:00", amount=SOLICITADOS, pet_id=self.mascota.id)
        )
        self.order_id = self._entregar()

    def tearDown(self):
        self._limpiar_base_de_datos()

    def _guardar(self, entidad):
        sesion = SessionLocal()
        try:
            sesion.add(entidad)
            sesion.commit()
            sesion.refresh(entidad)
            return entidad
        finally:
            sesion.close()

    def _limpiar_base_de_datos(self):
        sesion = SessionLocal()
        try:
            for modelo in (
                models.DispensingQueue,
                models.DispensingOrder,
                models.RefillOperation,
                models.ActivityLog,
                models.Dispenser,
                models.Schedule,
                models.Pet,
                models.User,
            ):
                sesion.query(modelo).delete()
            sesion.commit()
        finally:
            sesion.close()

    def _entregar(self):
        sesion = SessionLocal()
        try:
            return order_service.entregar_orden(sesion, MAC, ahora=AHORA)["order_id"]
        finally:
            sesion.close()

    def _reporte(self, medidos=50.0):
        return DispenserReportRequest(
            mac=MAC,
            order_id=self.order_id,
            motivo="objetivo_alcanzado",
            gramos_solicitados=SOLICITADOS,
            gramos_medidos=medidos,
            reintentos=0,
        )

    # --- Estado tras la prueba ---------------------------------------------

    def _stock(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.Dispenser).filter(
                models.Dispenser.id == self.dispensador.id
            ).first().current_food_grams
        finally:
            sesion.close()

    def _orden(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.DispensingOrder).filter(
                models.DispensingOrder.id == self.order_id
            ).first()
        finally:
            sesion.close()

    def _logs(self):
        sesion = SessionLocal()
        try:
            return sesion.query(models.ActivityLog).filter(
                models.ActivityLog.order_id == self.order_id
            ).all()
        finally:
            sesion.close()


class TestReportesSimultaneos(BaseConcurrenciaTests):
    """RNF-3, RF-18: dos reportes simultáneos, un único cierre y descuento."""

    def test_dos_reportes_simultaneos_en_sesiones_distintas(self):
        resultados = []
        errores = []
        barrera = threading.Barrier(2)

        def reportar():
            sesion = SessionLocal()
            try:
                # Las dos sesiones empiezan a la vez para que ambas lean la orden
                # como pendiente antes de que ninguna confirme.
                barrera.wait(timeout=10)
                resultados.append(
                    order_service.procesar_reporte(sesion, self._reporte(), ahora=AHORA)
                )
            except Exception as error:  # pragma: no cover - se informa en el assert
                errores.append(error)
            finally:
                sesion.close()

        hilos = [threading.Thread(target=reportar) for _ in range(2)]
        for hilo in hilos:
            hilo.start()
        for hilo in hilos:
            hilo.join(timeout=20)

        self.assertEqual(errores, [], f"Los reportes simultáneos no deben fallar: {errores}")
        self.assertEqual(len(resultados), 2)

        ganadores = [r for r in resultados if not r["ya_cerrada"]]
        perdedores = [r for r in resultados if r["ya_cerrada"]]
        self.assertEqual(len(ganadores), 1, "Un único reporte cierra la orden")
        self.assertEqual(len(perdedores), 1, "El otro se resuelve como duplicado")
        self.assertEqual(ganadores[0]["outcome"], "success")
        self.assertEqual(perdedores[0]["outcome"], "success")

        # Un único registro y un único descuento.
        self.assertEqual(len(self._logs()), 1)
        self.assertAlmostEqual(self._stock(), STOCK_INICIAL - 50.0)
        self.assertEqual(self._orden().status, "closed")

    def test_una_sesion_que_leyo_la_orden_pendiente_no_duplica_el_cierre(self):
        sesion_lenta = SessionLocal()
        try:
            # La sesión lenta carga la orden como pendiente y no vuelve a leerla.
            orden_vista = sesion_lenta.query(models.DispensingOrder).filter(
                models.DispensingOrder.id == self.order_id
            ).first()
            self.assertEqual(orden_vista.status, "pending")

            ganador = self._procesar_en_sesion_nueva()

            # Su `UPDATE ... WHERE status='pending'` no afecta filas: la orden ya
            # está cerrada y el resultado que devuelve es el ya registrado.
            perdedor = order_service.procesar_reporte(
                sesion_lenta, self._reporte(medidos=999.0), ahora=AHORA
            )
        finally:
            sesion_lenta.close()

        self.assertFalse(ganador["ya_cerrada"])
        self.assertTrue(perdedor["ya_cerrada"])
        self.assertEqual(perdedor["measured_grams"], 50.0, "Prevalece el primer cierre")
        self.assertEqual(len(self._logs()), 1)
        self.assertAlmostEqual(self._stock(), STOCK_INICIAL - 50.0)

    def _procesar_en_sesion_nueva(self):
        sesion = SessionLocal()
        try:
            return order_service.procesar_reporte(sesion, self._reporte(), ahora=AHORA)
        finally:
            sesion.close()


class TestStockConcurrente(BaseConcurrenciaTests):
    """RNF-3, RF-15, RF-11: descuento y reabastecimiento no se pisan.

    Cada prueba fija el intercalado: un hilo queda detenido antes de escribir el
    stock y la otra operación se confirma entera durante la pausa. No se usa
    `threading.Barrier` ni se depende del orden en que el planificador despierta a
    los hilos, así que la pérdida de actualización se detecta siempre y no «de vez
    en cuando».
    """

    # --- Operaciones en su propio hilo -------------------------------------

    def _cerrar_en_su_hilo(self, nombre, resultados, errores):
        sesion = SessionLocal()
        try:
            resultados[nombre] = order_service.procesar_reporte(
                sesion, self._reporte(medidos=50.0), ahora=AHORA
            )
        except Exception as error:  # pragma: no cover - se informa en el assert
            errores.append(error)
        finally:
            sesion.close()

    def _reabastecer_en_su_hilo(self, nombre, resultados, errores):
        sesion = SessionLocal()
        try:
            resultados[nombre] = self._reabastecer(200.0)
        except Exception as error:  # pragma: no cover - se informa en el assert
            errores.append(error)
        finally:
            sesion.close()

    def _descontar_en_su_hilo(self, nombre, resultados, errores):
        """Ejecuta la escritura de stock del cierre en una sesión propia."""
        sesion = SessionLocal()
        try:
            resultados[nombre] = order_service._descontar_stock_atomico(
                sesion, self.dispensador.id, 50.0
            )
            sesion.commit()
        except Exception as error:  # pragma: no cover - se informa en el assert
            errores.append(error)
        finally:
            sesion.close()

    # --- Operaciones en el hilo de la prueba --------------------------------

    def _reabastecer(self, gramos=200.0, operation_id="refill-concurrente"):
        sesion = SessionLocal()
        try:
            return dispenser_service.refill_dispenser(
                sesion,
                self.dispensador.id,
                DispenserRefillRequest(
                    amount=gramos, unit="g", operation_id=operation_id
                ),
                ahora=AHORA,
            )
        finally:
            sesion.close()

    def _cerrar(self):
        sesion = SessionLocal()
        try:
            return order_service.procesar_reporte(
                sesion, self._reporte(medidos=50.0), ahora=AHORA
            )
        finally:
            sesion.close()

    def _eventos_del_dispensador(self):
        sesion = SessionLocal()
        try:
            return [
                log.event_type
                for log in sesion.query(models.ActivityLog)
                .filter(models.ActivityLog.dispenser_id == self.dispensador.id)
                .order_by(models.ActivityLog.id)
                .all()
            ]
        finally:
            sesion.close()

    # --- Casos -------------------------------------------------------------

    def test_un_reabastecimiento_confirmado_no_se_pierde_al_cerrar_la_orden(self):
        """El cierre leyó 1000 g; el reabastecimiento confirma 1200 antes de que escriba."""
        resultados, errores = {}, []

        with PausaAntesDeEscribirStock() as pausa:
            detenido = pausa.armar(HILO_CIERRE)
            hilo = threading.Thread(
                target=self._cerrar_en_su_hilo,
                args=(HILO_CIERRE, resultados, errores),
                name=HILO_CIERRE,
            )
            hilo.start()
            try:
                self.assertTrue(
                    detenido.esperar(),
                    "El cierre no llegó a escribir el stock: la prueba no intercaló nada",
                )
                # El cierre ya leyó los 1000 g y está detenido antes de escribir.
                self.assertTrue(
                    detenido.leyo_el_stock(),
                    "La pausa debía caer después de leer el stock, no antes: "
                    f"{detenido.sentencias_previas}",
                )
                # Mientras el cierre espera, el reabastecimiento se confirma entero.
                respuesta = self._reabastecer(200.0)
                self.assertAlmostEqual(respuesta.current_food_grams, 1200.0)
                self.assertAlmostEqual(self._stock(), 1200.0)
            finally:
                detenido.continuar()
            hilo.join(timeout=PAUSA_TIMEOUT)
            self.assertFalse(hilo.is_alive(), "El cierre no terminó tras liberar la pausa")

        self.assertEqual(errores, [], f"El cierre no debe fallar: {errores}")
        cierre = resultados[HILO_CIERRE]
        self.assertFalse(cierre["ya_cerrada"])
        self.assertEqual(cierre["outcome"], "success")

        # 1000 - 50 + 200: la escritura relativa del cierre parte de 1200 y no
        # repone el valor obsoleto que leyó antes de la pausa.
        self.assertAlmostEqual(self._stock(), 1150.0)
        self.assertEqual(self._orden().status, "closed")

        eventos = self._eventos_del_dispensador()
        self.assertEqual(eventos.count("feeding_dispensed"), 1)
        self.assertEqual(eventos.count("dispenser_refilled"), 1)

    def test_un_descuento_confirmado_no_se_pierde_al_reabastecer(self):
        """Caso espejo del anterior: el reabastecimiento espera y el cierre escribe."""
        resultados, errores = {}, []

        with PausaAntesDeEscribirStock() as pausa:
            detenido = pausa.armar(HILO_REABASTECIMIENTO)
            hilo = threading.Thread(
                target=self._reabastecer_en_su_hilo,
                args=(HILO_REABASTECIMIENTO, resultados, errores),
                name=HILO_REABASTECIMIENTO,
            )
            hilo.start()
            try:
                self.assertTrue(
                    detenido.esperar(),
                    "El reabastecimiento no llegó a escribir el stock",
                )
                # El cierre se confirma entero mientras el reabastecimiento espera.
                cierre = self._cerrar()
                self.assertFalse(cierre["ya_cerrada"])
                self.assertAlmostEqual(self._stock(), 950.0)
            finally:
                detenido.continuar()
            hilo.join(timeout=PAUSA_TIMEOUT)
            self.assertFalse(
                hilo.is_alive(), "El reabastecimiento no terminó tras liberar la pausa"
            )

        self.assertEqual(errores, [], f"El reabastecimiento no debe fallar: {errores}")
        # 1000 - 50 + 200: el reabastecimiento suma sobre 950 y no sobre 1000.
        self.assertAlmostEqual(self._stock(), 1150.0)
        self.assertEqual(self._orden().status, "closed")
        self.assertEqual(self._eventos_del_dispensador().count("dispenser_refilled"), 1)

    def test_dos_descuentos_simultaneos_no_pierden_gramos(self):
        """Caso simétrico: dos escrituras de descuento sobre la misma fila.

        La regla de una única orden pendiente por dispensador impide que dos
        cierres se solapen a través de `procesar_reporte`, así que el solapamiento
        real -dos descuentos sobre el mismo stock- se ejerce sobre
        `_descontar_stock_atomico`, que es la escritura que hace el cierre.
        """
        nombres = ("descuento-1", "descuento-2")
        resultados, errores = {}, []

        with PausaAntesDeEscribirStock() as pausa:
            detenidas = [pausa.armar(nombre) for nombre in nombres]
            hilos = [
                threading.Thread(
                    target=self._descontar_en_su_hilo,
                    args=(nombre, resultados, errores),
                    name=nombre,
                )
                for nombre in nombres
            ]
            for hilo in hilos:
                hilo.start()
            try:
                # Los dos descuentos leen 1000 g antes de que el otro escriba:
                # ninguno ve el descuento del otro.
                for nombre, detenida in zip(nombres, detenidas):
                    self.assertTrue(
                        detenida.esperar(),
                        f"{nombre} no llegó a escribir el stock",
                    )
                    self.assertTrue(
                        detenida.leyo_el_stock(),
                        f"{nombre} debía leer el stock antes de la pausa: "
                        f"{detenida.sentencias_previas}",
                    )
            finally:
                for detenida in detenidas:
                    detenida.continuar()
            for hilo in hilos:
                hilo.join(timeout=PAUSA_TIMEOUT)
            self.assertFalse(
                any(hilo.is_alive() for hilo in hilos),
                "Algún descuento no terminó tras liberar la pausa",
            )

        self.assertEqual(errores, [], f"Los descuentos no deben fallar: {errores}")
        self.assertEqual(sorted(resultados), sorted(nombres))
        for nombre in nombres:
            descontados, faltante, _ = resultados[nombre]
            self.assertAlmostEqual(descontados, 50.0)
            self.assertAlmostEqual(faltante, 0.0)

        # 1000 - 50 - 50: cada descuento resta sobre el stock vigente.
        self.assertAlmostEqual(self._stock(), 900.0)


class TestEntregasSimultaneas(BaseConcurrenciaTests):
    """RNF-3: dos entregas a la vez no dejan dos órdenes pendientes."""

    def _preparar_dos_comidas(self):
        """Deja la cola con dos ocurrencias y sin ninguna orden pendiente."""
        sesion = SessionLocal()
        try:
            sesion.query(models.DispensingOrder).delete()
            sesion.query(models.DispensingQueue).delete()
            dispensador = (
                sesion.query(models.Dispenser)
                .filter(models.Dispenser.id == self.dispensador.id)
                .first()
            )
            dispensador.pending_dispensing = False
            sesion.flush()

            for hora in ("09:00", "10:00"):
                horario = models.Schedule(
                    time=hora, amount=SOLICITADOS, pet_id=self.mascota.id
                )
                sesion.add(horario)
                sesion.flush()
                sesion.add(
                    models.DispensingQueue(
                        dispenser_id=dispensador.id,
                        pet_id=self.mascota.id,
                        schedule_id=horario.id,
                        amount=SOLICITADOS,
                        scheduled_for=AHORA.replace(tzinfo=None),
                    )
                )
            sesion.commit()
        finally:
            sesion.close()

    def test_dos_entregas_simultaneas_no_dejan_dos_ordenes_pendientes(self):
        self._preparar_dos_comidas()

        resultados = []
        errores = []
        barrera = threading.Barrier(2)

        def entregar():
            sesion = SessionLocal()
            try:
                barrera.wait(timeout=10)
                resultados.append(
                    order_service.entregar_orden(sesion, MAC, ahora=AHORA)
                )
            except Exception as error:  # pragma: no cover - se informa en el assert
                errores.append(error)
            finally:
                sesion.close()

        hilos = [threading.Thread(target=entregar) for _ in range(2)]
        for hilo in hilos:
            hilo.start()
        for hilo in hilos:
            hilo.join(timeout=30)

        self.assertEqual(
            errores, [], f"Las entregas simultáneas no deben fallar: {errores}"
        )
        self.assertEqual(len(resultados), 2)

        servidas = [r for r in resultados if r.get("serve")]
        self.assertEqual(len(servidas), 1, "Un único ganador crea la orden")

        sesion = SessionLocal()
        try:
            pendientes = (
                sesion.query(models.DispensingOrder)
                .filter(
                    models.DispensingOrder.dispenser_id == self.dispensador.id,
                    models.DispensingOrder.status == "pending",
                )
                .all()
            )
            consumidas = (
                sesion.query(models.DispensingQueue)
                .filter(
                    models.DispensingQueue.dispenser_id == self.dispensador.id,
                    models.DispensingQueue.consumed_at.is_not(None),
                )
                .count()
            )
        finally:
            sesion.close()

        self.assertEqual(len(pendientes), 1, "No puede haber dos órdenes pendientes")
        self.assertEqual(
            consumidas, 1, "La ocurrencia que perdió la carrera vuelve a la cola"
        )


if __name__ == "__main__":
    unittest.main()
