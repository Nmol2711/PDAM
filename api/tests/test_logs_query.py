"""Consulta del historial: propiedad, orden, filtros y sobre paginado (T7).

Cubre RF-26 a RF-32 y RF-41 sobre la API completa: `GET /logs/` devuelve solo los
registros del usuario autenticado, ordenados por `created_at DESC, id DESC`, con
el sobre `{items,total,page,page_size}`; los cuatro filtros se aplican en
conjunción y con ambos extremos inclusivos; los históricos sin tipo se muestran
como «Sin clasificar» sin filtros y quedan excluidos al filtrar por tipo o
resultado. `GET /logs/catalog` publica los tipos y resultados con sus etiquetas
en español para que la app no duplique el catálogo cerrado (RNF-7).

Las comprobaciones de estado se hacen con sesiones nuevas y se siembran filas
directamente en `logs` para controlar `created_at` y no depender de otros
servicios.
"""

import json
import os
import sys
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi.testclient import TestClient

from app.api.deps import get_current_user
from app.db.database import SessionLocal
from app.main import app
from app.models import models

EMAIL = "dueno@logs.test"
EMAIL_AJENO = "ajeno@logs.test"
SECRETO = "clave-de-prueba-que-no-debe-registrarse"

MAC_ENMASCARADA = "**:AB:1F"

# Instante base en UTC naive, tal como se guarda en `logs` (RNF-8).
BASE = datetime(2026, 10, 1, 12, 0, 0)


class BaseLogsQueryTests(unittest.TestCase):
    """Un usuario con dos mascotas, otro usuario ajeno y su historial."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()
        self.usuario = self._crear_usuario(EMAIL)
        self.ajeno = self._crear_usuario(EMAIL_AJENO)
        self.milo = self._crear_mascota(self.usuario, "Milo")
        self.nina = self._crear_mascota(self.usuario, "Nina")
        self.mascota_ajena = self._crear_mascota(self.ajeno, "Pelota")

    def tearDown(self):
        app.dependency_overrides.clear()
        self._limpiar_base_de_datos()

    # --- Escenario ----------------------------------------------------------

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

    def _crear_usuario(self, email):
        return self._guardar(
            models.User(email=email, hashed_password=SECRETO, is_active=True)
        )

    def _crear_mascota(self, usuario, nombre):
        return self._guardar(
            models.Pet(
                name=nombre,
                species="perro",
                birth_date=date(2023, 1, 1),
                weight=5.5,
                reproductive_status=False,
                user_id=usuario.id,
            )
        )

    def _crear_log(
        self,
        *,
        usuario=None,
        mascota=None,
        tipo="feeding_dispensed",
        resultado="success",
        causa="objetivo_alcanzado",
        descripcion="Comida dispensada",
        creado=BASE,
        contexto=None,
        **extra,
    ):
        """Inserta un registro de historial con los campos indicados."""
        usuario = usuario or self.usuario
        mascota = self.mascota_por_defecto(mascota)
        return self._guardar(
            models.ActivityLog(
                user_id=usuario.id,
                pet_id=None if mascota is None else mascota.id,
                pet_name=None if mascota is None else mascota.name,
                dispenser_id=extra.pop("dispenser_id", None),
                dispenser_mac_masked=extra.pop("dispenser_mac_masked", MAC_ENMASCARADA),
                event_type=tipo,
                outcome=resultado,
                cause=causa,
                description=descripcion,
                context=None if contexto is None else json.dumps(contexto, ensure_ascii=False),
                created_at=creado,
                **extra,
            )
        )

    def mascota_por_defecto(self, mascota):
        """`False` permite crear un registro sin mascota; `None` usa Milo."""
        if mascota is False:
            return None
        return self.milo if mascota is None else mascota

    # --- Peticiones ---------------------------------------------------------

    def _get(self, usuario=None, **params):
        app.dependency_overrides[get_current_user] = lambda: usuario or self.usuario
        return self.client.get("/logs/", params=params)

    def _get_catalogo(self, usuario=None):
        app.dependency_overrides[get_current_user] = lambda: usuario or self.usuario
        return self.client.get("/logs/catalog")

    def _pagina(self, **params):
        """Consulta correcta: devuelve el JSON del sobre y exige 200."""
        respuesta = self._get(**params)
        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        return respuesta.json()

    def _ids(self, **params):
        return [item["id"] for item in self._pagina(**params)["items"]]

    def assert_catalogo_de_error(self, respuesta, codigo):
        """Contrato de error: 400 con `detail={code,message}` (§5.6)."""
        self.assertEqual(respuesta.status_code, 400, respuesta.text)
        cuerpo = respuesta.json()["detail"]
        self.assertEqual(cuerpo["code"], codigo)
        self.assertTrue(cuerpo["message"].strip())
        return cuerpo


class TestPropiedadYOrden(BaseLogsQueryTests):
    """RF-26, RF-32: solo lo propio, del más reciente al más antiguo, paginado."""

    def test_devuelve_solo_los_registros_del_usuario_autenticado(self):
        propio = self._crear_log(mascota=self.milo)
        self._crear_log(usuario=self.ajeno, mascota=self.mascota_ajena)

        pagina = self._pagina()

        self.assertEqual(pagina["total"], 1)
        self.assertEqual([item["id"] for item in pagina["items"]], [propio.id])
        self.assertEqual(pagina["items"][0]["pet_name"], "Milo")

    def test_el_sobre_tiene_items_total_pagina_y_tamano(self):
        self._crear_log()
        self._crear_log(creado=BASE + timedelta(minutes=1))

        pagina = self._pagina()

        self.assertEqual(set(pagina.keys()), {"items", "total", "page", "page_size"})
        self.assertEqual(pagina["total"], 2)
        self.assertEqual(pagina["page"], 1)
        self.assertEqual(pagina["page_size"], 50)
        self.assertEqual(len(pagina["items"]), 2)

    def test_ordena_del_mas_reciente_al_mas_antiguo_y_desempata_por_id(self):
        antiguo = self._crear_log(creado=BASE)
        # Mismo instante: el desempate es por identificador descendente.
        primero = self._crear_log(creado=BASE + timedelta(minutes=5))
        segundo = self._crear_log(creado=BASE + timedelta(minutes=5))
        reciente = self._crear_log(creado=BASE + timedelta(minutes=9))

        self.assertEqual(
            self._ids(),
            [reciente.id, segundo.id, primero.id, antiguo.id],
        )

    def test_cincuenta_items_por_defecto_y_total_completo(self):
        for minuto in range(60):
            self._crear_log(creado=BASE + timedelta(minutes=minuto))

        pagina = self._pagina()

        self.assertEqual(pagina["page_size"], 50)
        self.assertEqual(len(pagina["items"]), 50)
        self.assertEqual(pagina["total"], 60)
        # La primera página son los 50 más recientes, en orden descendente.
        fechas = [item["created_at"] for item in pagina["items"]]
        self.assertEqual(fechas, sorted(fechas, reverse=True))

    def test_la_segunda_pagina_devuelve_los_siguientes_y_repite_el_total(self):
        for minuto in range(5):
            self._crear_log(creado=BASE + timedelta(minutes=minuto))

        primera = self._pagina(page="1", page_size="2")
        segunda = self._pagina(page="2", page_size="2")
        tercera = self._pagina(page="3", page_size="2")

        self.assertEqual(primera["total"], 5)
        self.assertEqual(segunda["total"], 5)
        self.assertEqual(tercera["total"], 5)
        self.assertEqual(len(primera["items"]), 2)
        self.assertEqual(len(segunda["items"]), 2)
        self.assertEqual(len(tercera["items"]), 1)
        ids = (
            [item["id"] for item in primera["items"]]
            + [item["id"] for item in segunda["items"]]
            + [item["id"] for item in tercera["items"]]
        )
        self.assertEqual(len(set(ids)), 5, "Las páginas no repiten registros")
        self.assertEqual(ids, sorted(ids, reverse=True))

    def test_una_pagina_fuera_del_total_devuelve_lista_vacia_y_el_total(self):
        self._crear_log()

        pagina = self._pagina(page="9", page_size="10")

        self.assertEqual(pagina["items"], [])
        self.assertEqual(pagina["total"], 1)
        self.assertEqual(pagina["page"], 9)

    def test_la_consulta_sin_resultados_devuelve_lista_vacia_y_total_cero(self):
        pagina = self._pagina()

        self.assertEqual(
            pagina, {"items": [], "total": 0, "page": 1, "page_size": 50}
        )

    def test_el_tamano_maximo_aceptado_es_cien(self):
        for minuto in range(105):
            self._crear_log(creado=BASE + timedelta(minutes=minuto))

        pagina = self._pagina(page_size="100")

        self.assertEqual(pagina["page_size"], 100)
        self.assertEqual(len(pagina["items"]), 100)
        self.assertEqual(pagina["total"], 105)


class TestFiltros(BaseLogsQueryTests):
    """RF-27 a RF-31: filtros en conjunción, extremos inclusivos y `Z`."""

    def test_filtra_por_mascota(self):
        de_milo = self._crear_log(mascota=self.milo)
        self._crear_log(mascota=self.nina)

        self.assertEqual(self._ids(pet_id=str(self.milo.id)), [de_milo.id])

    def test_filtra_por_mascota_eliminada_cuyo_identificador_se_conserva(self):
        de_milo = self._crear_log(mascota=self.milo)

        sesion = SessionLocal()
        try:
            mascota = sesion.query(models.Pet).filter(models.Pet.id == self.milo.id).first()
            sesion.delete(mascota)
            sesion.commit()
        finally:
            sesion.close()

        self.assertEqual(self._ids(pet_id=str(self.milo.id)), [de_milo.id])

    def test_filtra_por_tipo_de_evento(self):
        refill = self._crear_log(tipo="dispenser_refilled", causa=None)
        self._crear_log(tipo="feeding_dispensed")

        self.assertEqual(self._ids(event_type="dispenser_refilled"), [refill.id])

    def test_filtra_por_resultado(self):
        fallo = self._crear_log(
            resultado="failure", causa="entrega_incompleta"
        )
        self._crear_log(resultado="success")

        self.assertEqual(self._ids(outcome="failure"), [fallo.id])

    def test_aplica_los_cuatro_filtros_en_conjuncion(self):
        objetivo = self._crear_log(
            mascota=self.milo,
            creado=datetime(2026, 10, 2, 15, 0, 0),
        )
        # Cada fila incumple exactamente un filtro.
        self._crear_log(mascota=self.nina, creado=datetime(2026, 10, 2, 15, 0, 0))
        self._crear_log(
            mascota=self.milo,
            resultado="failure",
            causa="entrega_incompleta",
            creado=datetime(2026, 10, 2, 15, 0, 0),
        )
        self._crear_log(
            mascota=self.milo,
            tipo="dispenser_refilled",
            causa=None,
            creado=datetime(2026, 10, 2, 15, 0, 0),
        )
        self._crear_log(
            mascota=self.milo, creado=datetime(2026, 10, 20, 15, 0, 0)
        )

        pagina = self._pagina(
            pet_id=str(self.milo.id),
            event_type="feeding_dispensed",
            outcome="success",
            **{
                "from": "2026-10-02T00:00:00Z",
                "to": "2026-10-03T00:00:00Z",
            },
        )

        self.assertEqual(pagina["total"], 1)
        self.assertEqual([item["id"] for item in pagina["items"]], [objetivo.id])

    def test_el_rango_de_fechas_incluye_ambos_extremos(self):
        desde = datetime(2026, 10, 2, 0, 0, 0)
        hasta = datetime(2026, 10, 2, 23, 59, 59)
        self._crear_log(creado=desde)
        self._crear_log(creado=hasta)
        self._crear_log(creado=desde - timedelta(seconds=1))
        self._crear_log(creado=hasta + timedelta(seconds=1))

        pagina = self._pagina(
            **{
                "from": "2026-10-02T00:00:00Z",
                "to": "2026-10-02T23:59:59Z",
            }
        )

        self.assertEqual(pagina["total"], 2)

    def test_el_sufijo_z_y_el_desplazamiento_cero_son_el_mismo_instante(self):
        en_z = self._crear_log(creado=datetime(2026, 10, 2, 5, 0, 0))

        con_z = self._pagina(**{"from": "2026-10-02T05:00:00Z", "to": "2026-10-02T05:00:00Z"})
        con_offset = self._pagina(
            **{"from": "2026-10-02T05:00:00+00:00", "to": "2026-10-02T05:00:00+00:00"}
        )

        self.assertEqual([item["id"] for item in con_z["items"]], [en_z.id])
        self.assertEqual(con_z, con_offset)

    def test_los_limites_con_desplazamiento_se_convierten_a_utc(self):
        # 2026-10-01T19:00:00-05:00 es 2026-10-02T00:00:00Z.
        dentro = self._crear_log(creado=datetime(2026, 10, 2, 0, 30, 0))
        self._crear_log(creado=datetime(2026, 10, 1, 23, 30, 0))

        pagina = self._pagina(
            **{
                "from": "2026-10-01T19:00:00-05:00",
                "to": "2026-10-01T20:00:00-05:00",
            }
        )

        self.assertEqual([item["id"] for item in pagina["items"]], [dentro.id])

    def test_filtrar_por_mascota_ajena_no_devuelve_nada(self):
        self._crear_log(usuario=self.ajeno, mascota=self.mascota_ajena)

        pagina = self._pagina(pet_id=str(self.mascota_ajena.id))

        self.assertEqual(pagina["total"], 0)
        self.assertEqual(pagina["items"], [])

    def test_un_pet_id_no_numerico_no_corresponde_a_ninguna_mascota(self):
        # No hay código de error para este filtro y no se inventa uno: un valor
        # que no puede ser un identificador devuelve una página vacía, sin
        # ignorar el filtro en silencio y sin 422.
        self._crear_log()

        pagina = self._pagina(pet_id="abc")

        self.assertEqual(pagina["total"], 0)
        self.assertEqual(pagina["items"], [])
        self.assertEqual(pagina["page"], 1)
        self.assertEqual(pagina["page_size"], 50)

    def test_un_pet_id_vacio_se_trata_como_ausente(self):
        # Un filtro sin valor es el estado inicial de la pantalla, no un id.
        self._crear_log()

        self.assertEqual(self._pagina(pet_id="")["total"], 1)


class TestHistoricosYEtiquetas(BaseLogsQueryTests):
    """RF-41, RF-3 y RNF-8: «Sin clasificar», etiquetas y fechas con `Z`."""

    def _crear_historico(self, creado=BASE - timedelta(days=30)):
        return self._crear_log(
            tipo=None,
            resultado=None,
            causa=None,
            descripcion="Registro histórico",
            contexto=None,
            creado=creado,
        )

    def test_los_historicos_se_muestran_como_sin_clasificar_sin_filtros(self):
        historico = self._crear_historico()
        clasificado = self._crear_log()

        pagina = self._pagina()

        self.assertEqual(pagina["total"], 2)
        por_id = {item["id"]: item for item in pagina["items"]}
        self.assertEqual(por_id[historico.id]["event_label"], "Sin clasificar")
        self.assertIsNone(por_id[historico.id]["event_type"])
        self.assertIsNone(por_id[historico.id]["outcome"])
        self.assertIsNone(por_id[historico.id]["outcome_label"])
        self.assertIsNone(por_id[historico.id]["cause"])
        self.assertIsNone(por_id[historico.id]["cause_label"])
        self.assertEqual(por_id[historico.id]["description"], "Registro histórico")
        self.assertEqual(
            por_id[clasificado.id]["event_label"], "Comida dispensada"
        )

    def test_los_historicos_quedan_excluidos_al_filtrar_por_tipo(self):
        self._crear_historico()
        clasificado = self._crear_log(tipo="dispenser_refilled", causa=None)

        self.assertEqual(
            self._ids(event_type="dispenser_refilled"), [clasificado.id]
        )

    def test_los_historicos_quedan_excluidos_al_filtrar_por_resultado(self):
        self._crear_historico()
        exito = self._crear_log()
        fallo = self._crear_log(resultado="failure", causa="sin_reporte")

        self.assertEqual(self._ids(outcome="success"), [exito.id])
        self.assertEqual(self._ids(outcome="failure"), [fallo.id])

    def test_las_etiquetas_se_resuelven_en_el_servidor(self):
        registro = self._crear_log(
            contexto={"motivo": "objetivo_alcanzado", "faltante": 0.0},
            requested_grams=50.0,
            measured_grams=50.4,
            discounted_grams=50.4,
            resulting_stock=1149.6,
            retry_count=0,
        )

        item = self._pagina()["items"][0]

        self.assertEqual(item["id"], registro.id)
        self.assertEqual(item["event_type"], "feeding_dispensed")
        self.assertEqual(item["event_label"], "Comida dispensada")
        self.assertEqual(item["outcome"], "success")
        self.assertEqual(item["outcome_label"], "Éxito")
        self.assertEqual(item["cause"], "objetivo_alcanzado")
        self.assertEqual(item["cause_label"], "Objetivo alcanzado")
        self.assertEqual(item["description"], "Comida dispensada")
        self.assertEqual(item["pet_id"], self.milo.id)
        self.assertEqual(item["pet_name"], "Milo")
        self.assertEqual(item["dispenser_mac_masked"], MAC_ENMASCARADA)
        self.assertEqual(item["requested_grams"], 50.0)
        self.assertEqual(item["measured_grams"], 50.4)
        self.assertEqual(item["discounted_grams"], 50.4)
        self.assertEqual(item["resulting_stock"], 1149.6)
        self.assertEqual(item["retry_count"], 0)
        self.assertEqual(
            item["context"], {"motivo": "objetivo_alcanzado", "faltante": 0.0}
        )

    def test_created_at_se_devuelve_en_utc_con_sufijo_z(self):
        self._crear_log(creado=datetime(2026, 10, 1, 12, 0, 0))

        item = self._pagina()["items"][0]

        self.assertEqual(item["created_at"], "2026-10-01T12:00:00Z")
        instante = datetime.fromisoformat(item["created_at"].replace("Z", "+00:00"))
        self.assertEqual(instante.utcoffset(), timedelta(0))
        self.assertEqual(
            instante, datetime(2026, 10, 1, 12, 0, tzinfo=timezone.utc)
        )

    def test_un_registro_sin_contexto_lo_devuelve_como_nulo(self):
        self._crear_historico()

        self.assertIsNone(self._pagina()["items"][0]["context"])


class TestCatalogo(BaseLogsQueryTests):
    """RF-31, RNF-7 y plan §5.4: tipos y resultados con etiquetas, sin causas."""

    TIPOS_ESPERADOS = {
        "pet_created": "Mascota creada",
        "pet_updated": "Mascota modificada",
        "pet_deleted": "Mascota eliminada",
        "dispenser_linked": "Dispensador vinculado",
        "dispenser_updated": "Dispensador modificado",
        "dispenser_unlinked": "Dispensador desvinculado",
        "dispenser_wifi_reset": "WiFi del dispensador reiniciado",
        "feeding_dispensed": "Comida dispensada",
        "dispenser_refilled": "Dispensador reabastecido",
    }

    RESULTADOS_ESPERADOS = {"success": "Éxito", "failure": "Fallo"}

    def test_el_catalogo_devuelve_los_nueve_tipos_con_etiqueta(self):
        respuesta = self._get_catalogo()

        self.assertEqual(respuesta.status_code, 200, respuesta.text)
        tipos = {entrada["code"]: entrada["label"] for entrada in respuesta.json()["event_types"]}
        self.assertEqual(tipos, self.TIPOS_ESPERADOS)

    def test_el_catalogo_devuelve_los_dos_resultados_con_etiqueta(self):
        respuesta = self._get_catalogo()

        resultados = {
            entrada["code"]: entrada["label"] for entrada in respuesta.json()["outcomes"]
        }
        self.assertEqual(resultados, self.RESULTADOS_ESPERADOS)

    def test_el_catalogo_no_incluye_las_causas(self):
        # La causa se muestra desde la etiqueta de cada ítem; el catálogo de
        # filtros solo publica tipos y resultados (plan §5.4).
        cuerpo = self._get_catalogo().json()

        self.assertEqual(set(cuerpo.keys()), {"event_types", "outcomes"})

    def test_el_catalogo_no_depende_del_historial_del_usuario(self):
        # Es un catálogo cerrado, no una lista de valores observados.
        self.assertEqual(self._pagina()["total"], 0)

        self.assertEqual(
            len(self._get_catalogo().json()["event_types"]), 9
        )


if __name__ == "__main__":
    unittest.main()
