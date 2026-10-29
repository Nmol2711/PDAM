"""Rechazos de la consulta del historial (T7).

Todo valor inválido de `GET /logs/` responde HTTP 400 con
`detail={code,message}` del catálogo de errores y **nunca** un 422: los
parámetros se declaran como texto y se validan en el servicio (RF-30, RF-31,
RF-32, RNF-7). La precedencia es la del plan §5.3:

`rango_fechas_invalido` → `tipo_evento_invalido` → `resultado_invalido` →
`pagina_invalida` → `tamano_pagina_invalido`.

Ningún rechazo devuelve resultados parciales, recorta un valor ni escribe un
registro (RF-2). El módulo incluye además la tabla de correspondencia RF→prueba
que pide el plan §9.5 y la comprueba de forma mecánica.
"""

import os
import sys
import unittest
from datetime import datetime
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from app.api.deps import get_current_user
from app.main import app

import test_logs_performance
import test_logs_query
from test_logs_query import BaseLogsQueryTests

# Mensajes exactos del catálogo de errores de la spec (§Catálogo de errores).
MENSAJES_ESPERADOS = {
    "tipo_evento_invalido": "El tipo de evento no pertenece al catálogo.",
    "resultado_invalido": "El resultado no pertenece al catálogo.",
    "rango_fechas_invalido": (
        "El rango de fechas no es válido: revise el orden de los límites y el "
        "desplazamiento horario."
    ),
    "pagina_invalida": "El número de página debe ser 1 o mayor.",
    "tamano_pagina_invalido": "El tamaño de página debe estar entre 1 y 100.",
}


class TestRechazosDeLaConsulta(BaseLogsQueryTests):
    """RF-30, RF-31, RF-32: 400 del catálogo, sin 422 y sin recortes."""

    def _rechazo(self, **params):
        respuesta = self._get(**params)
        self.assertNotEqual(
            respuesta.status_code, 422, f"No se admite un 422: {respuesta.text}"
        )
        self.assertEqual(respuesta.status_code, 400, respuesta.text)
        cuerpo = respuesta.json()["detail"]
        self.assertIn(cuerpo["code"], MENSAJES_ESPERADOS)
        self.assertEqual(cuerpo["message"], MENSAJES_ESPERADOS[cuerpo["code"]])
        return cuerpo["code"]

    # --- Filtros de catálogo ------------------------------------------------

    def test_un_tipo_fuera_del_catalogo_responde_tipo_evento_invalido(self):
        for valor in ("pet_revived", "PET_CREATED", "", " "):
            with self.subTest(valor=valor):
                self.assertEqual(
                    self._rechazo(event_type=valor), "tipo_evento_invalido"
                )

    def test_un_tipo_historico_no_es_un_tipo_filtrable(self):
        # «Sin clasificar» no es un tipo del catálogo (RF-41).
        self.assertEqual(
            self._rechazo(event_type="sin_clasificar"), "tipo_evento_invalido"
        )

    def test_un_resultado_fuera_del_catalogo_responde_resultado_invalido(self):
        for valor in ("ok", "SUCCESS", "pending", ""):
            with self.subTest(valor=valor):
                self.assertEqual(self._rechazo(outcome=valor), "resultado_invalido")

    # --- Fechas -------------------------------------------------------------

    def test_un_limite_sin_desplazamiento_responde_rango_fechas_invalido(self):
        for valor in (
            "2026-10-01T00:00:00",
            "2026-10-01",
            "2026-10-01T00:00:00.123456",
        ):
            with self.subTest(valor=valor):
                self.assertEqual(
                    self._rechazo(**{"from": valor}), "rango_fechas_invalido"
                )
                self.assertEqual(
                    self._rechazo(**{"to": valor}), "rango_fechas_invalido"
                )

    def test_un_instante_invalido_responde_rango_fechas_invalido(self):
        for valor in ("ayer", "2026-13-01T00:00:00Z", "2026-10-01T25:00:00Z", ""):
            with self.subTest(valor=valor):
                self.assertEqual(
                    self._rechazo(**{"from": valor}), "rango_fechas_invalido"
                )

    def test_una_fecha_final_anterior_a_la_inicial_es_invalida(self):
        self.assertEqual(
            self._rechazo(
                **{
                    "from": "2026-10-02T00:00:00Z",
                    "to": "2026-10-01T00:00:00Z",
                }
            ),
            "rango_fechas_invalido",
        )

    def test_el_sufijo_z_no_produce_rechazo(self):
        respuesta = self._get(**{"from": "2026-10-01T00:00:00Z"})

        self.assertEqual(respuesta.status_code, 200, respuesta.text)

    # --- Paginación ---------------------------------------------------------

    def test_una_pagina_menor_que_uno_responde_pagina_invalida(self):
        for valor in ("0", "-1", "-50", ""):
            with self.subTest(valor=valor):
                self.assertEqual(self._rechazo(page=valor), "pagina_invalida")

    def test_una_pagina_no_numerica_responde_pagina_invalida(self):
        for valor in ("abc", "1.5", "2,0", "uno"):
            with self.subTest(valor=valor):
                self.assertEqual(self._rechazo(page=valor), "pagina_invalida")

    def test_un_tamano_de_pagina_fuera_del_intervalo_es_invalido(self):
        for valor in ("0", "-1", "101", "1000", "abc", "50.5", ""):
            with self.subTest(valor=valor):
                self.assertEqual(
                    self._rechazo(page_size=valor), "tamano_pagina_invalido"
                )

    def test_los_extremos_del_intervalo_de_pagina_se_aceptan(self):
        for valor in ("1", "100"):
            with self.subTest(valor=valor):
                respuesta = self._get(page_size=valor)
                self.assertEqual(respuesta.status_code, 200, respuesta.text)
                self.assertEqual(respuesta.json()["page_size"], int(valor))

    def test_un_tamano_demasiado_grande_no_se_recorta_en_silencio(self):
        # Si se recortara, la respuesta sería 200 con page_size 100.
        self._rechazo(page_size="1000")

    # --- Precedencia --------------------------------------------------------

    def test_la_precedencia_de_rechazo_es_la_del_plan(self):
        # Cada caso añade un parámetro inválido más que el anterior: gana
        # siempre el primero por la izquierda.
        casos = [
            (
                {
                    **{"from": "2026-10-01"},
                    "event_type": "inventado",
                    "outcome": "ok",
                    "page": "0",
                    "page_size": "0",
                },
                "rango_fechas_invalido",
            ),
            (
                {
                    "event_type": "inventado",
                    "outcome": "ok",
                    "page": "0",
                    "page_size": "0",
                },
                "tipo_evento_invalido",
            ),
            (
                {"outcome": "ok", "page": "0", "page_size": "0"},
                "resultado_invalido",
            ),
            ({"page": "0", "page_size": "0"}, "pagina_invalida"),
            ({"page_size": "0"}, "tamano_pagina_invalido"),
        ]

        for params, esperado in casos:
            with self.subTest(esperado=esperado):
                self.assertEqual(self._rechazo(**params), esperado)

    # --- Efectos ------------------------------------------------------------

    def test_un_rechazo_no_devuelve_resultados_ni_escribe_registros(self):
        self._crear_log()

        for params in (
            {"event_type": "inventado"},
            {"outcome": "ok"},
            {"page": "0"},
            {"page_size": "101"},
            {**{"from": "2026-10-02T00:00:00Z", "to": "2026-10-01T00:00:00Z"}},
        ):
            with self.subTest(params=params):
                respuesta = self._get(**params)
                self.assertEqual(respuesta.status_code, 400, respuesta.text)
                self.assertNotIn("items", respuesta.json())

        self.assertEqual(self._pagina()["total"], 1, "El historial no cambia")

    def test_el_catalogo_exige_autenticacion(self):
        app.dependency_overrides.clear()

        respuesta = self.client.get("/logs/catalog")

        self.assertEqual(respuesta.status_code, 401)
        self.assertIn("detail", respuesta.json())

    def test_la_consulta_exige_autenticacion(self):
        app.dependency_overrides.clear()

        respuesta = self.client.get("/logs/")

        self.assertEqual(respuesta.status_code, 401)


class TestTrazabilidadRF(unittest.TestCase):
    """RNF-6 y plan §9.5: cada RF de la consulta tiene su prueba automatizada."""

    # Correspondencia RF → pruebas que fallan si el requisito se incumple. Las
    # tres primeras columnas citan pruebas de este módulo y de los otros dos de
    # la consulta, y la prueba final comprueba que todas existen.
    COBERTURA = {
        "RF-26": (
            "test_logs_query.TestPropiedadYOrden"
            ".test_devuelve_solo_los_registros_del_usuario_autenticado",
            "test_logs_query.TestPropiedadYOrden"
            ".test_ordena_del_mas_reciente_al_mas_antiguo_y_desempata_por_id",
            "test_logs_query.TestPropiedadYOrden.test_cincuenta_items_por_defecto_y_total_completo",
        ),
        "RF-27": (
            "test_logs_query.TestFiltros.test_filtra_por_mascota",
            "test_logs_query.TestFiltros"
            ".test_filtra_por_mascota_eliminada_cuyo_identificador_se_conserva",
            "test_logs_query.TestFiltros.test_filtrar_por_mascota_ajena_no_devuelve_nada",
        ),
        "RF-28": (
            "test_logs_query.TestFiltros.test_filtra_por_tipo_de_evento",
            "test_logs_query.TestHistoricosYEtiquetas"
            ".test_los_historicos_quedan_excluidos_al_filtrar_por_tipo",
        ),
        "RF-29": (
            "test_logs_query.TestFiltros.test_filtra_por_resultado",
            "test_logs_query.TestHistoricosYEtiquetas"
            ".test_los_historicos_quedan_excluidos_al_filtrar_por_resultado",
        ),
        "RF-30": (
            "test_logs_query.TestFiltros.test_el_rango_de_fechas_incluye_ambos_extremos",
            "test_logs_query.TestFiltros"
            ".test_los_limites_con_desplazamiento_se_convierten_a_utc",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_un_limite_sin_desplazamiento_responde_rango_fechas_invalido",
            "test_logs_errors.TestRechazosDeLaConsulta.test_el_sufijo_z_no_produce_rechazo",
        ),
        "RF-31": (
            "test_logs_query.TestFiltros.test_aplica_los_cuatro_filtros_en_conjuncion",
            "test_logs_errors.TestRechazosDeLaConsulta.test_la_precedencia_de_rechazo_es_la_del_plan",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_un_tipo_fuera_del_catalogo_responde_tipo_evento_invalido",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_un_resultado_fuera_del_catalogo_responde_resultado_invalido",
        ),
        "RF-32": (
            "test_logs_query.TestPropiedadYOrden.test_el_sobre_tiene_items_total_pagina_y_tamano",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_una_pagina_menor_que_uno_responde_pagina_invalida",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_un_tamano_de_pagina_fuera_del_intervalo_es_invalido",
            "test_logs_errors.TestRechazosDeLaConsulta.test_un_tamano_demasiado_grande_no_se_recorta_en_silencio",
        ),
        "RF-41": (
            "test_logs_query.TestHistoricosYEtiquetas"
            ".test_los_historicos_se_muestran_como_sin_clasificar_sin_filtros",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_un_tipo_historico_no_es_un_tipo_filtrable",
        ),
        "RNF-2": (
            "test_logs_performance.TestRendimientoDeLaConsulta"
            ".test_la_consulta_con_cuatro_filtros_cumple_el_p95",
            "test_logs_performance.TestRendimientoDeLaConsulta"
            ".test_existe_el_indice_compuesto_de_usuario_y_fecha",
        ),
    }

    def test_cada_rf_de_la_consulta_tiene_sus_pruebas_y_existen(self):
        ids = set()
        for modulo in (test_logs_query, test_logs_performance, sys.modules[__name__]):
            ids |= _ids_de_prueba(modulo)

        for rf, referencias in self.COBERTURA.items():
            with self.subTest(rf=rf):
                self.assertTrue(referencias, f"{rf} no tiene pruebas asociadas")
                for referencia in referencias:
                    self.assertIn(
                        referencia,
                        ids,
                        f"{rf}: la prueba {referencia} no existe o cambió de nombre",
                    )


def _ids_de_prueba(modulo):
    """Identificadores de todas las pruebas de un módulo, incluidas las anidadas."""
    identificadores = set()

    def recorrer(suite):
        for prueba in suite:
            if isinstance(prueba, unittest.TestSuite):
                recorrer(prueba)
            else:
                identificadores.add(prueba.id())

    recorrer(unittest.defaultTestLoader.loadTestsFromModule(modulo))
    return identificadores


if __name__ == "__main__":
    unittest.main()
