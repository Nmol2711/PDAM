"""Trazabilidad RF → prueba de la spec 014 (RNF-6, T10).

Una sola tabla declara, para cada uno de los 41 requisitos funcionales, al menos
una prueba automatizada que falla si el requisito se incumple. La prueba final
comprueba que:

1. La tabla cubre exactamente los RF declarados en `spec.md`.
2. Cada referencia de la API (`modulo.Clase.test_...`) existe en la suite.
3. Cada referencia de Flutter y del firmware aparece literalmente en su archivo.
4. Los RF con efecto físico o visual tienen además su procedimiento manual
   documentado en `tasks.md`.

Las referencias de Flutter y del firmware se guardan como
`(ruta_relativa, texto_del_caso)`: no se ejecutan desde pytest, pero se verifica
que el caso sigue existiendo con ese nombre.
"""

import importlib
import re
import sys
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
TESTS_API = Path(__file__).resolve().parent
FLUTTER = RAIZ / "app" / "app_movil_pdam"
FIRMWARE = RAIZ / "DispensadorESP32"
TAREAS = RAIZ / "specs" / "014-logs-y-validacion-dispensado" / "tasks.md"
SPEC = RAIZ / "specs" / "014-logs-y-validacion-dispensado" / "spec.md"

# Módulos de la API cuyos identificadores de prueba se validan.
MODULOS_API = (
    "test_activity_logs_crud",
    "test_dispenser_food",
    "test_feeding_queue",
    "test_logs_domain",
    "test_logs_errors",
    "test_logs_migration",
    "test_logs_performance",
    "test_logs_query",
    "test_orders_concurrency",
    "test_orders_dispensing",
    "test_orders_expiry",
    "test_refill_logs",
)

# RF → pruebas automatizadas. `api` son identificadores de pytest; `flutter` y
# `pio` son pares (archivo, nombre del caso).
COBERTURA = {
    "RF-1": {
        "api": (
            "test_orders_dispensing.TestAtomicidadDelCierre"
            ".test_fallo_al_escribir_el_log_revierte_y_devuelve_500",
            "test_orders_dispensing.TestAtomicidadDelCierre"
            ".test_el_reintento_tras_el_500_cierra_una_sola_vez",
        ),
    },
    "RF-2": {
        "api": (
            "test_activity_logs_crud.TestRegistrosDeMascotas"
            ".test_una_modificacion_rechazada_no_registra",
            "test_orders_dispensing.TestRechazosDelReporte"
            ".test_mac_no_registrada_responde_400_sin_registro",
            "test_orders_dispensing.TestRechazosDelReporte"
            ".test_motivo_invalido_responde_400_sin_registro_y_la_orden_sigue_pendiente",
            "test_refill_logs.TestRechazosDelReabastecimiento"
            ".test_el_registro_de_fallo_persiste_en_una_sesion_independiente",
        ),
    },
    "RF-3": {
        "api": (
            "test_activity_logs_crud.TestRegistrosDeMascotas"
            ".test_crear_mascota_escribe_pet_created",
            "test_activity_logs_crud.TestRegistrosDeDispensadores"
            ".test_vincular_dispensador_escribe_dispenser_linked",
            "test_logs_domain.TestMaskMac"
            ".test_la_mac_parcial_nunca_contiene_la_direccion_completa",
            "test_logs_query.TestHistoricosYEtiquetas"
            ".test_created_at_se_devuelve_en_utc_con_sufijo_z",
        ),
    },
    "RF-4": {
        "api": (
            "test_activity_logs_crud.TestRegistrosDeMascotas"
            ".test_crear_mascota_escribe_pet_created",
        ),
    },
    "RF-5": {
        "api": (
            "test_activity_logs_crud.TestRegistrosDeMascotas"
            ".test_modificar_mascota_escribe_solo_los_nombres_de_los_campos",
            "test_activity_logs_crud.TestRegistrosDeMascotas"
            ".test_modificar_un_solo_campo_registra_un_unico_nombre",
        ),
    },
    "RF-6": {
        "api": (
            "test_activity_logs_crud.TestRegistrosDeMascotas"
            ".test_eliminar_mascota_conserva_la_referencia_de_los_historicos",
            "test_activity_logs_crud.TestBorradoDeMascotaPorApi"
            ".test_borrar_una_mascota_con_dispensador_responde_conflicto",
            "test_logs_migration.TestBaseLegada"
            ".test_borrar_la_mascota_no_anula_pet_id_ni_dispenser_id",
        ),
    },
    "RF-7": {
        "api": (
            "test_activity_logs_crud.TestRegistrosDeDispensadores"
            ".test_vincular_dispensador_escribe_dispenser_linked",
        ),
    },
    "RF-8": {
        "api": (
            "test_activity_logs_crud.TestRegistrosDeDispensadores"
            ".test_modificar_dispensador_escribe_solo_los_nombres_de_los_campos",
            "test_activity_logs_crud.TestRegistrosDeDispensadores"
            ".test_cambiar_la_mac_registra_el_nombre_del_campo_y_no_la_direccion",
        ),
    },
    "RF-9": {
        "api": (
            "test_activity_logs_crud.TestRegistrosDeDispensadores"
            ".test_desvincular_dispensador_escribe_dispenser_unlinked",
        ),
    },
    "RF-10": {
        "api": (
            "test_activity_logs_crud.TestRegistrosDeDispensadores"
            ".test_reset_wifi_escribe_dispenser_wifi_reset_sin_ssid_ni_credenciales",
        ),
    },
    "RF-11": {
        "api": (
            "test_refill_logs.TestReabastecimientoAceptado"
            ".test_reabastecimiento_con_conexion_registra_origen_servidor",
            "test_refill_logs.TestReabastecimientoAceptado"
            ".test_reabastecimiento_sincronizado_usa_la_hora_de_la_sincronizacion",
            "test_refill_logs.TestIdempotenciaDelReabastecimiento"
            ".test_el_doble_operation_id_no_duplica_ni_registra_dos_veces",
        ),
        "flutter": (
            (
                "test/features/dispenser/data/datasource/remote/"
                "dispenser_remote_datasource_test.dart",
                "un reintento del reabastecimiento reenvía el mismo operation_id",
            ),
        ),
    },
    "RF-12": {
        "api": (
            "test_refill_logs.TestRechazosDelReabastecimiento"
            ".test_cantidad_cero_responde_400_cantidad_invalida",
            "test_refill_logs.TestRechazosDelReabastecimiento"
            ".test_cantidad_no_numerica_responde_400_cantidad_invalida",
            "test_refill_logs.TestRechazosDelReabastecimiento"
            ".test_superar_la_capacidad_responde_400_supera_capacidad",
            "test_refill_logs.TestRechazosDelReabastecimiento"
            ".test_los_rechazos_nunca_responden_422",
        ),
        "flutter": (
            (
                "test/features/dispenser/data/datasource/remote/"
                "dispenser_remote_datasource_test.dart",
                "el POST envía solo amount, unit, operation_id y origen",
            ),
        ),
    },
    "RF-13": {
        "api": (
            "test_orders_dispensing.TestEntregaDeOrden"
            ".test_entrega_crea_la_orden_pendiente_sin_descontar_stock",
            "test_orders_dispensing.TestEntregaDeOrden"
            ".test_check_taks_entrega_order_id_y_no_descuenta",
        ),
    },
    "RF-14": {
        "api": (
            "test_orders_dispensing.TestRechazosDelReporte"
            ".test_la_mac_se_normaliza_antes_de_buscarla",
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_orden_invalida_sin_gramos_solicitados_ni_medidos",
            "test_orders_dispensing.TestAjustesDeCierreDeT4"
            ".test_reintentos_ausente_se_registra_como_no_disponible",
            "test_orders_dispensing.TestRechazosDelReporte"
            ".test_ningun_reporte_de_negocio_responde_422",
        ),
        "pio": (
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_json_omite_los_medidos_ausentes",
            ),
        ),
    },
    "RF-15": {
        "api": (
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_exito_descuenta_lo_medido_y_guarda_medidos_y_descontados",
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_medidos_mayores_que_los_solicitados_descuentan_lo_medido",
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_los_solicitados_del_reporte_no_se_usan_para_comparar",
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_medidos_mayores_que_el_stock_descuentan_todo_el_disponible",
        ),
    },
    "RF-16": {
        "api": (
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_medidos_menores_que_los_solicitados_cierra_entrega_incompleta",
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_objetivo_alcanzado_sin_medidos_no_acredita_el_objetivo",
        ),
    },
    "RF-17": {
        "api": (
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_cada_motivo_de_fallo_cierra_con_su_causa_y_sin_descuento",
            "test_logs_domain.TestMotivosDeReporte"
            ".test_cada_motivo_de_fallo_produce_la_causa_homonima_sin_exito",
        ),
    },
    "RF-18": {
        "api": (
            "test_orders_dispensing.TestIdempotenciaYTardanza"
            ".test_un_segundo_reporte_devuelve_ya_cerrada_sin_nuevo_log_ni_descuento",
            "test_orders_dispensing.TestIdempotenciaYTardanza"
            ".test_duplicado_identico_del_mismo_reporte",
        ),
    },
    "RF-19": {
        "api": (
            "test_orders_expiry.TestFronterasDelVencimiento"
            ".test_no_cierra_una_orden_cuyo_plazo_mas_1_s_no_ha_vencido",
            "test_orders_expiry.TestFronterasDelVencimiento"
            ".test_el_cierre_ocurre_dentro_de_60_s_con_el_barrido_de_30_s",
            "test_orders_expiry.TestAlcanceDelBarrido"
            ".test_solo_cierra_las_ordenes_vencidas",
            "test_orders_expiry.TestBarridoProgramado"
            ".test_el_arranque_programa_un_unico_job_cada_30_s",
        ),
    },
    "RF-20": {
        "api": (
            "test_orders_dispensing.TestIdempotenciaYTardanza"
            ".test_reporte_en_el_limite_exacto_del_plazo_sigue_dentro",
            "test_orders_dispensing.TestIdempotenciaYTardanza"
            ".test_reporte_tardio_cierra_orden_cerrada_sin_descuento",
            "test_orders_expiry.TestExclusionMutuaConElReporte"
            ".test_el_barrido_cierra_y_el_reporte_tardio_devuelve_ya_cerrada",
        ),
    },
    "RF-21": {
        "api": (
            "test_orders_dispensing.TestRechazosDelReporte"
            ".test_orden_desconocida_responde_400_con_registro_de_fallo",
            "test_orders_dispensing.TestRechazosDelReporte"
            ".test_motivo_invalido_responde_400_sin_registro_y_la_orden_sigue_pendiente",
            "test_orders_dispensing.TestRechazosDelReporte"
            ".test_mac_no_registrada_responde_400_sin_registro",
        ),
    },
    "RF-22": {
        "api": (
            "test_logs_domain.TestDescuentoAcotado"
            ".test_el_stock_resultante_nunca_sale_del_intervalo_permitido",
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_un_stock_de_partida_fuera_de_rango_rechaza_el_cierre_sin_cambios",
            "test_refill_logs.TestReabastecimientoAceptado"
            ".test_el_limite_de_capacidad_exacto_se_acepta",
        ),
    },
    "RF-23": {
        "api": (
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_el_stock_no_se_toma_del_reporte",
            "test_activity_logs_crud.TestRegistrosDeDispensadores"
            ".test_un_stock_enviado_por_el_cliente_se_ignora_sin_error",
        ),
    },
    "RF-24": {
        "api": (
            "test_orders_dispensing.TestCierrePorReporte"
            ".test_el_registro_guarda_orden_solicitados_medidos_stock_y_reintentos",
            "test_orders_dispensing.TestAjustesDeCierreDeT4"
            ".test_reintentos_ausente_se_registra_como_no_disponible",
        ),
    },
    "RF-25": {
        "api": (
            "test_feeding_queue.TestEntregaDeLaComidaEnEspera"
            ".test_con_orden_pendiente_en_plazo_no_entrega_y_conserva_la_cola",
            "test_feeding_queue.TestEntregaDeLaComidaEnEspera"
            ".test_al_vencer_la_consulta_cierra_la_orden_y_la_cola_sigue_esperando",
            "test_feeding_queue.TestEntregaDeLaComidaEnEspera"
            ".test_un_dispensador_desactivado_no_dispensa_al_vencer_su_orden_pendiente",
            "test_feeding_queue.TestEntregaDeLaComidaEnEspera"
            ".test_al_reactivarse_se_entrega_la_comida_en_espera",
            "test_feeding_queue.TestHoraLocalDelServidor"
            ".test_la_hora_local_del_servidor_acepta_cualquier_desplazamiento",
        ),
    },
    "RF-26": {
        "api": (
            "test_logs_query.TestPropiedadYOrden"
            ".test_devuelve_solo_los_registros_del_usuario_autenticado",
            "test_logs_query.TestPropiedadYOrden"
            ".test_ordena_del_mas_reciente_al_mas_antiguo_y_desempata_por_id",
        ),
    },
    "RF-27": {
        "api": (
            "test_logs_query.TestFiltros.test_filtra_por_mascota",
            "test_logs_query.TestFiltros"
            ".test_filtra_por_mascota_eliminada_cuyo_identificador_se_conserva",
        ),
    },
    "RF-28": {
        "api": (
            "test_logs_query.TestFiltros.test_filtra_por_tipo_de_evento",
            "test_logs_query.TestHistoricosYEtiquetas"
            ".test_los_historicos_quedan_excluidos_al_filtrar_por_tipo",
        ),
    },
    "RF-29": {
        "api": (
            "test_logs_query.TestFiltros.test_filtra_por_resultado",
            "test_logs_query.TestHistoricosYEtiquetas"
            ".test_los_historicos_quedan_excluidos_al_filtrar_por_resultado",
        ),
    },
    "RF-30": {
        "api": (
            "test_logs_query.TestFiltros.test_el_rango_de_fechas_incluye_ambos_extremos",
            "test_logs_query.TestFiltros"
            ".test_los_limites_con_desplazamiento_se_convierten_a_utc",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_un_limite_sin_desplazamiento_responde_rango_fechas_invalido",
        ),
        "flutter": (
            (
                "test/features/logs/domain/log_filters_test.dart",
                "el 29/03/2026 el fin del día usa +02:00 y no el +01:00 de medianoche",
            ),
            (
                "test/features/logs/domain/log_filters_test.dart",
                "el 25/10/2026 el fin del día usa +01:00 y no el +02:00 de medianoche",
            ),
        ),
    },
    "RF-31": {
        "api": (
            "test_logs_query.TestFiltros.test_aplica_los_cuatro_filtros_en_conjuncion",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_un_tipo_fuera_del_catalogo_responde_tipo_evento_invalido",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_un_resultado_fuera_del_catalogo_responde_resultado_invalido",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_la_precedencia_de_rechazo_es_la_del_plan",
        ),
        "flutter": (
            (
                "test/features/logs/data/datasource/remote/log_remote_datasource_test.dart",
                "omite los filtros vacíos o ausentes",
            ),
        ),
    },
    "RF-32": {
        "api": (
            "test_logs_query.TestPropiedadYOrden"
            ".test_el_sobre_tiene_items_total_pagina_y_tamano",
            "test_logs_query.TestPropiedadYOrden"
            ".test_cincuenta_items_por_defecto_y_total_completo",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_una_pagina_menor_que_uno_responde_pagina_invalida",
            "test_logs_errors.TestRechazosDeLaConsulta"
            ".test_un_tamano_de_pagina_fuera_del_intervalo_es_invalido",
        ),
        "flutter": (
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "muestra la página, el total de páginas y los registros",
            ),
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "la página siguiente pide la página 2",
            ),
        ),
    },
    "RF-33": {
        "flutter": (
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "muestra fecha, hora, etiquetas, mascota, MAC y gramos",
            ),
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "muestra los cuatro filtros y el botón de limpiar",
            ),
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "limpiar filtros restablece la primera página sin filtros",
            ),
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "vacío muestra el texto exacto",
            ),
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "un error muestra el mensaje y el reintento vuelve a consultar",
            ),
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "se pinta sin desbordamientos en 360 dp con texto al 130 %",
            ),
        ),
        "manual": "P-T8-A",
    },
    "RF-34": {
        "flutter": (
            (
                "test/features/logs/data/repositories/log_repository_impl_test.dart",
                "si falla la red devuelve la caché con los mismos filtros y página",
            ),
            (
                "test/features/logs/data/datasource/local/local_log_datasource_test.dart",
                "pagina y calcula el total sobre la caché",
            ),
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "offline muestra los datos locales y su aviso",
            ),
        ),
    },
    "RF-35": {
        "flutter": (
            (
                "test/features/logs/data/datasource/local/local_log_datasource_test.dart",
                "hace upsert por remoteId sin duplicar (RF-35)",
            ),
            (
                "test/features/logs/data/datasource/local/local_log_datasource_test.dart",
                "cacheLogs no borra los registros ya cacheados",
            ),
        ),
    },
    "RF-36": {
        "pio": (
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_json_completo_con_todos_los_campos",
            ),
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_json_omite_los_solicitados_ausentes",
            ),
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_json_omite_los_medidos_ausentes",
            ),
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_cada_motivo_tiene_su_codigo_del_catalogo",
            ),
        ),
        "manual": "P-T9-A",
    },
    "RF-37": {
        "pio": (
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_la_politica_conserva_timeout_y_esperas",
            ),
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_se_reintenta_solo_mientras_queden_intentos",
            ),
        ),
        "manual": "P-T9-B",
    },
    "RF-38": {
        "pio": (
            (
                "test/test_dispensing_cycle/test_dispensing_cycle.cpp",
                "test_cycle_limits_default_to_approved_constants",
            ),
            (
                "test/test_dispensing_utils/test_dispensing_utils.cpp",
                "test_verification_window_is_exactly_two_seconds",
            ),
            (
                "test/test_dispensing_utils/test_dispensing_utils.cpp",
                "test_is_check_due_waits_the_full_interval",
            ),
        ),
    },
    "RF-39": {
        "pio": (
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_un_200_descarta_el_reporte",
            ),
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_los_tres_400_enumerados_se_descartan",
            ),
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_un_400_no_enumerado_tambien_se_descarta",
            ),
            (
                "test/test_report_utils/test_report_utils.cpp",
                "test_los_5xx_y_los_errores_de_red_se_reintentan",
            ),
        ),
        "manual": "P-T9-C",
    },
    "RF-40": {
        "api": (
            "test_orders_expiry.TestAlcanceDelBarrido"
            ".test_firmware_antiguo_cierra_por_plazo_sin_reporte_ni_descuento",
        ),
        "manual": "P-T9-D",
    },
    "RF-41": {
        "api": (
            "test_logs_query.TestHistoricosYEtiquetas"
            ".test_los_historicos_se_muestran_como_sin_clasificar_sin_filtros",
            "test_logs_query.TestHistoricosYEtiquetas"
            ".test_los_historicos_quedan_excluidos_al_filtrar_por_tipo",
            "test_logs_query.TestHistoricosYEtiquetas"
            ".test_los_historicos_quedan_excluidos_al_filtrar_por_resultado",
        ),
        "flutter": (
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "un registro histórico se muestra como «Sin clasificar»",
            ),
        ),
    },
}

# RF cuyo efecto observable es físico o visual: además de la prueba automatizada
# exigen una comprobación manual o física documentada (RNF-6).
MANUALES = {
    "RF-33": "P-T8-A",
    "RF-36": "P-T9-A",
    "RF-37": "P-T9-B",
    "RF-39": "P-T9-C",
    "RF-40": "P-T9-D",
}


class TestTrazabilidadGlobal(unittest.TestCase):
    """RNF-6: cada RF de la spec tiene su prueba y las referencias existen."""

    @classmethod
    def setUpClass(cls):
        # El directorio de pruebas puede no estar en `sys.path` al ejecutar el
        # módulo de forma aislada.
        if str(TESTS_API) not in sys.path:
            sys.path.insert(0, str(TESTS_API))

    def _ids_de_api(self):
        identificadores = set()
        for nombre in MODULOS_API:
            modulo = importlib.import_module(nombre)
            for prueba in unittest.defaultTestLoader.loadTestsFromModule(modulo):
                identificadores |= _recorrer(prueba)
        return identificadores

    def test_la_spec_declara_cuarenta_y_un_rf(self):
        texto = SPEC.read_text(encoding="utf-8")
        declarados = set(re.findall(r"\*\*(RF-\d+):\*\*", texto))

        self.assertEqual(len(declarados), 41, sorted(declarados))
        self.assertEqual(
            declarados,
            set(COBERTURA),
            "La tabla de trazabilidad debe cubrir exactamente los RF de la spec",
        )

    def test_cada_rf_tiene_una_prueba_automatizada_que_existe(self):
        ids_api = self._ids_de_api()

        for rf, referencias in COBERTURA.items():
            with self.subTest(rf=rf):
                automatizadas = [
                    referencia
                    for clave in ("api", "flutter", "pio")
                    for referencia in referencias.get(clave, ())
                ]
                self.assertTrue(
                    automatizadas, f"{rf} no tiene ninguna prueba automatizada"
                )

                for identificador in referencias.get("api", ()):
                    self.assertIn(
                        identificador,
                        ids_api,
                        f"{rf}: la prueba {identificador} no existe o cambió de nombre",
                    )

                for archivo, caso in referencias.get("flutter", ()):
                    ruta = FLUTTER / archivo
                    self.assertTrue(ruta.is_file(), f"{rf}: falta {archivo}")
                    self.assertTrue(
                        caso in ruta.read_text(encoding="utf-8"),
                        f"{rf}: el caso «{caso}» ya no está en {archivo}",
                    )

                for archivo, caso in referencias.get("pio", ()):
                    ruta = FIRMWARE / archivo
                    self.assertTrue(ruta.is_file(), f"{rf}: falta {archivo}")
                    self.assertTrue(
                        caso in ruta.read_text(encoding="utf-8"),
                        f"{rf}: el caso «{caso}» ya no está en {archivo}",
                    )

    def test_los_rf_fisicos_o_visuales_tienen_procedimiento_manual(self):
        tareas = TAREAS.read_text(encoding="utf-8")

        self.assertEqual(
            set(MANUALES), {"RF-33", "RF-36", "RF-37", "RF-39", "RF-40"}
        )
        for rf, ancla in MANUALES.items():
            with self.subTest(rf=rf):
                self.assertEqual(
                    COBERTURA[rf].get("manual"),
                    ancla,
                    f"{rf} declara un procedimiento manual distinto",
                )
                self.assertIn(
                    ancla,
                    tareas,
                    f"{rf}: el procedimiento {ancla} no está documentado en tasks.md",
                )

    def test_ningun_rf_queda_solo_con_prueba_manual(self):
        # RNF-6: la prueba manual nunca sustituye a la automatizada.
        for rf in MANUALES:
            with self.subTest(rf=rf):
                self.assertTrue(
                    any(COBERTURA[rf].get(clave) for clave in ("api", "flutter", "pio")),
                    f"{rf} no puede depender solo de una prueba manual",
                )


def _recorrer(prueba):
    if isinstance(prueba, unittest.TestSuite):
        identificadores = set()
        for hija in prueba:
            identificadores |= _recorrer(hija)
        return identificadores
    return {prueba.id()}


if __name__ == "__main__":
    unittest.main()
