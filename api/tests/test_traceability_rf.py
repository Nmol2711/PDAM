"""Trazabilidad RF → prueba de las specs 014 y 015 (RNF-05, RNF-6, T10).

Para cada spec, una tabla declara, para cada requisito funcional y no funcional,
al menos una prueba automatizada que falla si el requisito se incumple. Las
pruebas comprueban que:

1. La tabla cubre exactamente los RF (y RNF, en la 015) declarados en `spec.md`.
2. Cada referencia de la API (`modulo.Clase.test_...`) existe en la suite.
3. Cada referencia de Flutter y del firmware aparece literalmente en su archivo.
4. Los RF con efecto físico o visual tienen además su procedimiento manual
   documentado en `tasks.md`.
5. En la 015, las tablas de `tasks.md` citan archivo y nombre de prueba reales,
   de modo que no se pueda declarar una prueba inventada.

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

# --- Spec 015: gestión de usuario y menú de configuración -------------------

SPEC_015 = RAIZ / "specs" / "015-gestion-usuario-configuracion" / "spec.md"
TAREAS_015 = RAIZ / "specs" / "015-gestion-usuario-configuracion" / "tasks.md"
TRAZABILIDAD = Path(__file__).resolve().parent / "test_traceability_rf.py"

MODULOS_API_015 = (
    "test_traceability_rf",
    "test_auth",
    "test_account_deletion",
    "test_account_domain",
    "test_account_errors",
    "test_account_identity",
    "test_account_migration",
    "test_account_profile_api",
    "test_account_update",
)

# RF → pruebas automatizadas de la 015. `api` son identificadores de pytest;
# `flutter` son pares (archivo relativo a la app, fragmento del nombre del caso).
COBERTURA_015 = {
    "RF-01": {
        "flutter": (
            (
                "test/core/presentation/settings_entry_visibility_test.dart",
                "por debajo de 600 solo se muestra en la cabecera de la pantalla",
            ),
            (
                "test/core/presentation/settings_entry_visibility_test.dart",
                "desde 600 solo se muestra en la barra del contenedor",
            ),
            (
                "test/core/presentation/settings_entry_visibility_test.dart",
                "nunca hay dos ubicaciones visibles para el mismo ancho",
            ),
            (
                "test/core/presentation/settings_entry_visibility_test.dart",
                "a 320 hay una entrada en la cabecera y ninguna en el",
            ),
            (
                "test/features/pets/presentation/views/pets_view_test.dart",
                "a 320 la cabecera real dibuja exactamente una entrada",
            ),
            (
                "test/features/pets/presentation/views/pets_view_test.dart",
                "a 600 y 840 la cabecera real no dibuja la entrada",
            ),
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "a 320 la cabecera dibuja exactamente una entrada",
            ),
            (
                "test/features/logs/presentation/views/logs_view_test.dart",
                "a 600 y 840 la cabecera no dibuja la entrada",
            ),
            (
                "test/features/dispenser/presentation/views/dispensers_page_test.dart",
                "a 600 y 840 la cabecera real no dibuja la entrada y a 320 sí",
            ),
            (
                "test/features/dashboard/presentation/views/"
                "dashboard_nutrition_entry_test.dart",
                "a 600 y 840 la cabecera real del panel no dibuja la entrada y",
            ),
        ),
    },
    "RF-02": {
        "api": (
            "test_traceability_rf.TestValidacionGlobal015"
            ".test_rf02_el_menu_no_depende_del_estado_de_la_cuenta",
        ),
        "flutter": (
            (
                "test/features/settings/settings_view_test.dart",
                "muestra el título y las cuatro filas en el orden de RF-02",
            ),
            (
                "test/features/settings/settings_view_test.dart",
                "no despliega las tres opciones de apariencia como filas",
            ),
        ),
    },
    "RF-03": {
        "flutter": (
            (
                "test/features/settings/settings_view_test.dart",
                "la primera fila abre Perfil y al volver el menú conserva las",
            ),
            (
                "test/features/settings/settings_view_test.dart",
                "RF-03: la segunda fila abre Actualización de perfil y al",
            ),
            (
                "test/features/settings/settings_view_test.dart",
                "RF-03: la tercera fila abre la Eliminación de cuenta",
            ),
            (
                "test/features/settings/settings_view_test.dart",
                "la cuarta fila indica el modo activo y se actualiza al volver",
            ),
            (
                "test/features/settings/settings_view_test.dart",
                "RF-24: la cuarta fila abre el diálogo, marca el modo activo y",
            ),
        ),
    },
    "RF-04": {
        "flutter": (
            (
                "test/features/dashboard/presentation/views/"
                "dashboard_nutrition_entry_test.dart",
                "la cabecera conserva saludo, cierre de sesión y la entrada al",
            ),
        ),
    },
    "RF-05": {
        "flutter": (
            (
                "test/core/router/app_router_test.dart",
                "sin sesión, forzar /settings redirige a /login sin mostrar el",
            ),
            (
                "test/core/router/app_router_test.dart",
                "si la sesión termina con el menú abierto se cierra y se va a",
            ),
            (
                "test/core/network/auth_interceptor_test.dart",
                "un 401 de una petición autenticada con code unauthorized emite el",
            ),
            (
                "test/core/network/auth_interceptor_test.dart",
                "un 401 de la baja de la cuenta no emite el aviso ni borra el token:",
            ),
            (
                "test/features/auth/presentation/views/login_view_test.dart",
                "una sesión expirada muestra el texto del catálogo al volver al",
            ),
        ),
    },
    "RF-06": {
        "api": (
            "test_auth.TestLoginConCuentaInactiva"
            ".test_una_cuenta_inactiva_inicia_sesion_y_usa_el_token",
            "test_auth.TestLoginConCuentaInactiva"
            ".test_desactivar_la_cuenta_no_bloquea_el_login",
        ),
        "flutter": (
            (
                "test/features/settings/profile_view_test.dart",
                "muestra correo normalizado, estado y avatar con la inicial",
            ),
            (
                "test/features/settings/profile_view_test.dart",
                "una cuenta inactiva muestra la etiqueta",
            ),
            (
                "test/features/account/domain/account_validators_test.dart",
                "el estado activo se muestra como Activa y el inactivo como Inactiva",
            ),
        ),
    },
    "RF-07": {
        "flutter": (
            (
                "test/features/settings/profile_view_test.dart",
                "sin conexión muestra el perfil cacheado real con su aviso",
            ),
            (
                "test/features/settings/profile_view_test.dart",
                "un 401 unauthorized no muestra el perfil cacheado",
            ),
            (
                "test/features/account/data/account_repository_impl_test.dart",
                "la caché solo guarda respuestas del servidor",
            ),
            (
                "test/features/account/data/account_repository_impl_test.dart",
                "un 401 unauthorized no devuelve la caché",
            ),
        ),
    },
    "RF-08": {
        "flutter": (
            (
                "test/features/settings/profile_view_test.dart",
                "sin perfil cacheado muestra el mensaje de RF-08 y Reintentar",
            ),
            (
                "test/features/account/data/account_repository_impl_test.dart",
                "sin red y sin caché devuelve NoCachedProfileFailure",
            ),
        ),
    },
    "RF-09": {
        "flutter": (
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-09: precarga el correo del servidor y deja las contraseñas",
            ),
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-09: sin conexión precarga el correo del perfil cacheado real",
            ),
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-09: sin perfil cacheado el correo queda vacío y sin relleno",
            ),
        ),
    },
    "RF-10": {
        "api": (
            "test_account_update.TestActualizacionSoloCorreo"
            ".test_solo_correo_devuelve_token_nuevo_y_normaliza",
            "test_account_update.TestActualizacionSoloCorreo"
            ".test_el_token_usado_en_la_peticion_deja_de_valer",
            "test_account_update.TestActualizacionSoloCorreo"
            ".test_otro_token_de_la_misma_cuenta_sigue_valido",
        ),
        "flutter": (
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-10 y RF-14: el éxito guarda el token nuevo, refresca la",
            ),
        ),
    },
    "RF-11": {
        "api": (
            "test_account_domain.TestMatrizRF11"
            ".test_cada_fila_de_la_matriz_tiene_su_resultado",
            "test_account_update.TestRechazosDeActualizacion"
            ".test_correo_vacio_explicito_es_invalid_email",
            "test_account_update.TestRechazosDeActualizacion"
            ".test_password_corta_es_weak_password",
            "test_account_update.TestRechazosDeActualizacion"
            ".test_password_de_mas_de_72_bytes_es_password_too_long",
            "test_account_errors.TestNingunRechazoResponde422"
            ".test_los_rechazos_de_negocio_no_son_422",
        ),
        "flutter": (
            (
                "test/features/account/domain/account_validators_test.dart",
                "fila 1: correo vacío muestra la obligatoriedad",
            ),
            (
                "test/features/account/domain/account_validators_test.dart",
                "fila 14: un correo válido distinto no se comprueba en el cliente",
            ),
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-11 fila 1: correo vacío muestra el error junto al campo y no",
            ),
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-11 fila 14: el correo ya registrado lo decide el servidor y",
            ),
            (
                "test/features/account/domain/account_validators_test.dart",
                "el orden de precedencia es correo, envío sin cambios, "
                "confirmación,",
            ),
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-11: muestra a la vez todos los errores aplicables junto a su",
            ),
        ),
    },
    "RF-12": {
        "api": (
            "test_account_update.TestRechazosDeActualizacion"
            ".test_correo_duplicado_normalizado_no_aplica_ningun_cambio",
            "test_account_identity.TestRegistroNormalizado"
            ".test_el_duplicado_normalizado_responde_email_already_registered",
        ),
        "flutter": (
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-11 fila 14: el correo ya registrado lo decide el servidor y",
            ),
            (
                "test/features/account/data/account_repository_impl_test.dart",
                "un correo ya registrado no aplica ni escribe nada",
            ),
        ),
    },
    "RF-13": {
        "flutter": (
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-13: sin conexión no aplica nada, conserva lo escrito y",
            ),
            (
                "test/features/account/data/account_repository_impl_test.dart",
                "sin conexión no escribe nada, no encola y avisa",
            ),
            (
                "test/features/account/presentation/account_bloc_test.dart",
                "sin conexión no aplica nada y avisa",
            ),
        ),
    },
    "RF-14": {
        "api": (
            "test_account_update.TestActualizacionSoloPassword"
            ".test_la_password_anterior_ya_no_inicia_sesion_y_la_nueva_si",
        ),
        "flutter": (
            (
                "test/features/account/data/account_repository_impl_test.dart",
                "RF-14: al cambiar el correo actualiza las credenciales cifradas y",
            ),
            (
                "test/features/account/data/account_repository_impl_test.dart",
                "RF-14: al cambiar solo la contraseña conserva el correo cifrado",
            ),
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-10 y RF-14: el éxito guarda el token nuevo, refresca la",
            ),
        ),
    },
    "RF-15": {
        "flutter": (
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-15: cancelar no aplica nada y vuelve al menú",
            ),
        ),
    },
    "RF-16": {
        "flutter": (
            (
                "test/features/settings/delete_account_view_test.dart",
                "RF-16: muestra la advertencia, el listado literal y la acción",
            ),
            (
                "test/features/settings/delete_account_view_test.dart",
                "RF-16: el diálogo muestra los textos, el campo y la acción",
            ),
        ),
    },
    "RF-17": {
        "api": (
            "test_account_deletion.TestBajaRechazos"
            ".test_contrasena_incorrecta_no_borra_nada_y_conserva_la_sesion",
        ),
        "flutter": (
            (
                "test/features/settings/delete_account_view_test.dart",
                "RF-17: invalid_password se muestra junto al campo y no cierra",
            ),
            (
                "test/features/settings/delete_account_view_test.dart",
                "RF-17: cancelar deja la cuenta, los datos y la sesión intactos",
            ),
        ),
    },
    "RF-18": {
        "api": (
            "test_account_deletion.TestBajaCorrecta"
            ".test_borra_la_cuenta_y_las_siete_tablas_afectadas",
            "test_account_deletion.TestBajaCorrecta"
            ".test_la_mac_borrada_ya_no_esta_registrada",
            "test_account_deletion.TestBajaCorrecta"
            ".test_el_correo_queda_libre_y_el_registro_nuevo_nace_vacio",
            "test_account_deletion.TestBajaIdempotente"
            ".test_cuenta_inexistente_responde_200_sin_verificar_contrasena",
            "test_account_deletion.TestBajaIdempotente"
            ".test_el_token_de_la_cuenta_eliminada_solo_sirve_para_la_baja",
            "test_account_deletion.TestContarHuerfanos"
            ".test_devuelve_cero_tras_la_baja",
        ),
        "flutter": (
            (
                "test/features/settings/delete_account_view_test.dart",
                "RF-18: el éxito limpia, cierra la sesión y lleva al login con",
            ),
            (
                "test/core/services/account_local_cleaner_test.dart",
                "escribe la marca antes, limpia todo y la borra al terminar",
            ),
        ),
    },
    "RF-19": {
        "api": (
            "test_account_deletion.TestBajaCorrecta"
            ".test_el_correo_queda_libre_y_el_registro_nuevo_nace_vacio",
            "test_account_identity.TestIdentidadYUsuarioActual"
            ".test_un_jti_revocado_no_permite_la_peticion",
            "test_account_identity.TestIdentidadYUsuarioActual"
            ".test_get_current_user_rechaza_una_cuenta_inexistente",
        ),
        "flutter": (
            (
                "test/core/network/auth_interceptor_test.dart",
                "un 401 de una petición autenticada con code unauthorized emite el",
            ),
            (
                "test/features/auth/presentation/bloc/auth_bloc_test.dart",
                "RF-19: el 401 limpia la sesión antes de emitir AuthSessionExpired",
            ),
            (
                "test/core/services/account_local_cleaner_test.dart",
                "RF-19: la limpieza de un 401 borra token, credenciales y perfil y",
            ),
            (
                "test/core/services/account_local_cleaner_test.dart",
                "RF-19: tras un 401 el login sin conexión con las credenciales",
            ),
            (
                "test/core/services/account_local_cleaner_test.dart",
                "el borrado se acota a la cuenta y no barre filas de otra cuenta",
            ),
            (
                "test/core/services/account_local_cleaner_test.dart",
                "el reintento sin perfil cacheado limpia la cuenta y no barre filas",
            ),
        ),
    },
    "RF-20": {
        "flutter": (
            (
                "test/features/settings/delete_account_view_test.dart",
                "RF-20: sin conexión avisa, cierra el diálogo y no cambia nada",
            ),
            (
                "test/features/account/data/account_repository_impl_test.dart",
                "sin conexión no elimina nada, no encola y avisa",
            ),
            (
                "test/features/account/presentation/account_bloc_test.dart",
                "sin conexión no elimina nada ni inicia la limpieza",
            ),
        ),
    },
    "RF-21": {
        "api": (
            "test_account_deletion.TestBajaIdempotente"
            ".test_dos_bajas_simultaneas_responden_ambas_200",
            "test_account_deletion.TestBajaAtomica"
            ".test_fallo_inyectado_revierte_toda_la_transaccion",
            "test_account_update.TestRechazosDeActualizacion"
            ".test_escritura_condicional_fallida_es_conflict_sin_cambios",
        ),
        "flutter": (
            (
                "test/features/settings/delete_account_view_test.dart",
                "RF-21: el error del servidor ofrece un reintento real",
            ),
        ),
    },
    "RF-22": {
        "flutter": (
            (
                "test/features/settings/appearance_mode_dialog_test.dart",
                "RF-22: elegir aplica el cambio al instante en toda la",
            ),
            (
                "test/features/settings/appearance_mode_dialog_test.dart",
                "RF-22 y RF-23: Automático sigue el brillo oscuro del sistema",
            ),
            (
                "test/features/settings/appearance_mode_dialog_test.dart",
                "RF-22: cerrar sin elegir no cambia el modo",
            ),
        ),
    },
    "RF-23": {
        "flutter": (
            (
                "test/core/theme/theme_cubit_test.dart",
                "un cubit nuevo con user_theme_mode=dark restaura Oscuro tras",
            ),
            (
                "test/core/theme/theme_cubit_test.dart",
                "la clave no depende de ningún dato de la cuenta",
            ),
            (
                "test/core/services/account_local_cleaner_test.dart",
                "escribe la marca antes, limpia todo y la borra al terminar",
            ),
        ),
    },
    "RF-24": {
        "flutter": (
            (
                "test/features/settings/appearance_mode_dialog_test.dart",
                "RF-24: muestra el título y exactamente tres opciones",
            ),
            (
                "test/features/settings/appearance_mode_dialog_test.dart",
                "RF-24: marca el modo activo del dispositivo",
            ),
            (
                "test/features/settings/settings_view_test.dart",
                "RF-24: la cuarta fila abre el diálogo, marca el modo activo y",
            ),
        ),
    },
    "RF-25": {
        "flutter": (
            (
                "test/features/settings/settings_contrast_test.dart",
                "RF-25: el tema claro cumple el contraste mínimo",
            ),
            (
                "test/features/settings/settings_contrast_test.dart",
                "RF-25: el tema oscuro cumple el contraste mínimo",
            ),
        ),
    },
}

# RNF → pruebas automatizadas de la 015.
COBERTURA_RNF_015 = {
    "RNF-01": {
        "flutter": (
            (
                "test/features/settings/settings_texts_test.dart",
                "recorre el menú, el perfil, la actualización y la baja sin "
                "emojis y en",
            ),
            (
                "test/features/settings/settings_texts_test.dart",
                "cada mensaje de error nombra el campo y la acción",
            ),
        ),
    },
    "RNF-02": {
        "flutter": (
            (
                "test/features/settings/settings_responsive_test.dart",
                "RNF-02: ${entrada.key} con escalado 1.3",
            ),
            (
                "test/features/settings/update_profile_view_test.dart",
                "RNF-02: a 320 puntos con texto al 130 % no hay desbordamientos",
            ),
            (
                "test/features/settings/update_profile_view_test.dart",
                "RNF-02: a 600 puntos con texto al 130 % no hay desbordamientos",
            ),
            (
                "test/features/settings/update_profile_view_test.dart",
                "RNF-02: a 840 puntos en horizontal no hay desbordamientos",
            ),
            (
                "test/features/settings/appearance_mode_dialog_test.dart",
                "RNF-02: a 320 puntos con texto al 130 % no hay desbordamientos",
            ),
            (
                "test/features/settings/delete_account_view_test.dart",
                "RNF-02: a 320 puntos con texto al 130 % no hay desbordamientos",
            ),
        ),
    },
    "RNF-03": {
        "api": (
            "test_traceability_rf.TestValidacionGlobal015"
            ".test_rnf03_las_vistas_nuevas_no_contienen_logica_de_negocio",
        ),
        "flutter": (
            (
                "test/features/settings/update_profile_view_test.dart",
                "RNF-03: la precarga no muestra el spinner de Guardar",
            ),
            (
                "test/features/settings/delete_account_view_test.dart",
                "RNF-03: la precarga del perfil no deshabilita la confirmación ni",
            ),
            (
                "test/features/account/presentation/account_bloc_test.dart",
                "los errores de cliente se muestran todos y no se envía la",
            ),
        ),
    },
    "RNF-04": {
        "api": (
            "test_account_domain.TestPurezaDelDominio"
            ".test_importar_el_dominio_no_arrastra_framework_red_ni_entorno",
            "test_traceability_rf.TestValidacionGlobal015"
            ".test_rnf04_el_dominio_de_cuenta_no_depende_de_flutter_red_ni_"
            "almacenamiento",
        ),
    },
    "RNF-05": {
        "api": (
            "test_traceability_rf.TestTrazabilidad015"
            ".test_cada_rf_y_rnf_de_la_015_tiene_prueba_que_existe",
            "test_traceability_rf.TestTrazabilidad015"
            ".test_las_tres_operaciones_de_cuenta_tienen_prueba_de_api_y_de_"
            "interfaz",
        ),
    },
    "RNF-06": {
        "flutter": (
            (
                "test/core/network/dio_client_log_test.dart",
                "el PATCH con contraseña nueva no vuelca el cuerpo en el log",
            ),
            (
                "test/core/network/dio_client_log_test.dart",
                "el DELETE con contraseña no vuelca el cuerpo en el log",
            ),
            (
                "test/core/network/dio_client_log_test.dart",
                "el token de Authorization no aparece en el log",
            ),
            (
                "test/features/settings/delete_account_view_test.dart",
                "RNF-06: al cerrar el diálogo la contraseña reingresada se",
            ),
        ),
    },
    "RNF-07": {
        "api": (
            "test_traceability_rf.TestValidacionGlobal015"
            ".test_rnf07_las_dependencias_declaradas_no_cambian",
        ),
    },
    "RNF-08": {
        # La verificación real de RNF-08 es la ejecución completa de las suites
        # de 001–014 (evidencia en T10), no un test unitario. Estas pruebas
        # fallan si la trazabilidad anterior se recorta: un RF sin prueba
        # automatizada o una prueba citada que ya no existe.
        "api": (
            "test_traceability_rf.TestTrazabilidadGlobal"
            ".test_la_spec_declara_cuarenta_y_un_rf",
            "test_traceability_rf.TestTrazabilidadGlobal"
            ".test_cada_rf_tiene_una_prueba_automatizada_que_existe",
        ),
    },
    "RNF-09": {
        "api": (
            "test_account_deletion.TestBajaAtomica"
            ".test_fallo_inyectado_revierte_toda_la_transaccion",
            "test_account_update.TestRechazosDeActualizacion"
            ".test_escritura_condicional_fallida_es_conflict_sin_cambios",
            "test_account_update.TestRechazosDeActualizacion"
            ".test_fallo_de_escritura_es_server_error_y_revierte",
        ),
    },
    "RNF-10": {
        "flutter": (
            (
                "test/core/services/account_local_cleaner_test.dart",
                "escribe la marca antes, limpia todo y la borra al terminar",
            ),
            (
                "test/core/services/account_local_cleaner_test.dart",
                "si falla el borrado del token, la marca sobrevive y no borra el",
            ),
            (
                "test/core/services/account_local_cleaner_test.dart",
                "limpiarSiPendiente reintenta y completa la limpieza al reiniciar",
            ),
            (
                "test/features/settings/delete_account_view_test.dart",
                "RNF-10: si la limpieza falla, la marca sobrevive y la sesión se",
            ),
            (
                "test/core/services/pending_deletion_store_test.dart",
                "marca la baja pendiente en la clave reservada",
            ),
        ),
    },
}

# RNF-05: las tres operaciones de cuenta exigen prueba de API y de interfaz.
OPERACIONES_CUENTA = {
    "consulta (GET /users/me)": {
        "api": (
            "test_account_profile_api.TestPerfilConToken"
            ".test_token_vigente_devuelve_el_perfil_con_el_correo_normalizado",
        ),
        "flutter": (
            (
                "test/features/settings/profile_view_test.dart",
                "muestra correo normalizado, estado y avatar con la inicial",
            ),
        ),
    },
    "actualización (PATCH /users/me)": {
        "api": (
            "test_account_update.TestActualizacionSoloCorreo"
            ".test_solo_correo_devuelve_token_nuevo_y_normaliza",
        ),
        "flutter": (
            (
                "test/features/settings/update_profile_view_test.dart",
                "RF-10 y RF-14: el éxito guarda el token nuevo, refresca la",
            ),
        ),
    },
    "eliminación (DELETE /users/me)": {
        "api": (
            "test_account_deletion.TestBajaCorrecta"
            ".test_borra_la_cuenta_y_las_siete_tablas_afectadas",
        ),
        "flutter": (
            (
                "test/features/settings/delete_account_view_test.dart",
                "RF-18: el éxito limpia, cierra la sesión y lleva al login con",
            ),
        ),
    },
}

# Dependencias declaradas al cerrar la 015 (RNF-07). Si una spec futura añade
# una, debe actualizar esta instantánea de forma consciente.
REQUISITOS_BASE = frozenset(
    {
        "annotated-doc",
        "annotated-types",
        "anyio",
        "apscheduler",
        "bcrypt",
        "cffi",
        "click",
        "cryptography",
        "ecdsa",
        "fastapi",
        "greenlet",
        "h11",
        "idna",
        "passlib",
        "pyasn1",
        "pycparser",
        "pydantic",
        "pydantic_core",
        "python-dotenv",
        "python-jose",
        "python-multipart",
        "rsa",
        "six",
        "sqlalchemy",
        "starlette",
        "typing-inspection",
        "typing_extensions",
        "uvicorn",
    }
)

PUBSPEC_BASE = frozenset(
    {
        "flutter",
        "flutter_localizations",
        "dartz",
        "dio",
        "flutter_secure_storage",
        "auto_size_text",
        "bloc",
        "flutter_bloc",
        "equatable",
        "get_it",
        "go_router",
        "image_picker",
        "mobile_scanner",
        "permission_handler",
        "fl_chart",
        "isar",
        "isar_flutter_libs",
        "path_provider",
        "connectivity_plus",
        "flutter_blue_plus",
        "flutter_test",
        "flutter_lints",
        "build_runner",
        "isar_generator",
        "flutter_launcher_icons",
        "flutter_mcp_server",
    }
)


def _ids_de_api(modulos):
    """Identificadores `modulo.Clase.test_...` de los módulos indicados."""
    identificadores = set()
    for nombre in modulos:
        modulo = importlib.import_module(nombre)
        for prueba in unittest.defaultTestLoader.loadTestsFromModule(modulo):
            identificadores |= _recorrer(prueba)
    return identificadores


def _seccion_de_tareas(titulo):
    """Texto de una sección `## ...` de `tasks.md`, sin la siguiente sección."""
    texto = TAREAS_015.read_text(encoding="utf-8")
    inicio = texto.find(titulo)
    if inicio == -1:
        raise AssertionError(f"tasks.md no contiene la sección «{titulo}»")
    resto = texto[inicio + len(titulo) :]
    fin = resto.find("\n## ")
    return resto if fin == -1 else resto[:fin]


def _filas_de_trazabilidad(titulo, prefijo):
    """Mapa requisito → línea de tabla de una sección de trazabilidad."""
    filas = {}
    patron = re.compile(r"^\|\s*(%s-\d{2})\s*\|" % prefijo)
    for linea in _seccion_de_tareas(titulo).splitlines():
        coincidencia = patron.match(linea)
        if coincidencia:
            filas[coincidencia.group(1)] = linea
    return filas


def _dependencias_de_pubspec(texto):
    """Nombres declarados en `dependencies` y `dev_dependencies`."""
    seccion = None
    dependencias = set()
    for linea in texto.splitlines():
        if re.match(r"^\S", linea):
            seccion = linea.rstrip(":")
            continue
        if seccion not in ("dependencies", "dev_dependencies"):
            continue
        coincidencia = re.match(r"^  ([A-Za-z0-9_]+):", linea)
        if coincidencia:
            dependencias.add(coincidencia.group(1))
    return dependencias


class TestTrazabilidad015(unittest.TestCase):
    """RNF-05: cada RF y RNF de la 015 tiene prueba y las citas existen."""

    @classmethod
    def setUpClass(cls):
        if str(TESTS_API) not in sys.path:
            sys.path.insert(0, str(TESTS_API))

    def _verificar_referencias(self, requisito, referencias, ids_api):
        automatizadas = [
            referencia
            for clave in ("api", "flutter", "pio")
            for referencia in referencias.get(clave, ())
        ]
        self.assertTrue(automatizadas, f"{requisito} no tiene prueba automatizada")

        for identificador in referencias.get("api", ()):
            self.assertIn(
                identificador,
                ids_api,
                f"{requisito}: la prueba {identificador} no existe o cambió de nombre",
            )

        for archivo, caso in referencias.get("flutter", ()):
            ruta = FLUTTER / archivo
            self.assertTrue(ruta.is_file(), f"{requisito}: falta {archivo}")
            self.assertIn(
                caso,
                ruta.read_text(encoding="utf-8"),
                f"{requisito}: el caso «{caso}» ya no está en {archivo}",
            )

    def test_la_spec_015_declara_25_rf_y_10_rnf(self):
        texto = SPEC_015.read_text(encoding="utf-8")
        rf = set(re.findall(r"\*\*(RF-\d{2}):\*\*", texto))
        rnf = set(re.findall(r"\*\*(RNF-\d{2}):\*\*", texto))

        self.assertEqual(len(rf), 25, sorted(rf))
        self.assertEqual(len(rnf), 10, sorted(rnf))
        self.assertEqual(
            rf,
            set(COBERTURA_015),
            "La tabla debe cubrir exactamente los RF de la spec 015",
        )
        self.assertEqual(
            rnf,
            set(COBERTURA_RNF_015),
            "La tabla debe cubrir exactamente los RNF de la spec 015",
        )

    def test_cada_rf_y_rnf_de_la_015_tiene_prueba_que_existe(self):
        ids_api = _ids_de_api(MODULOS_API_015)
        referencias = {**COBERTURA_015, **COBERTURA_RNF_015}

        for requisito, pruebas in referencias.items():
            with self.subTest(requisito=requisito):
                self._verificar_referencias(requisito, pruebas, ids_api)

    def test_las_tablas_de_trazabilidad_citan_pruebas_que_existen(self):
        secciones = (
            (
                "## Trazabilidad RF → prueba (spec 015)",
                "RF",
                set(COBERTURA_015),
            ),
            (
                "## Trazabilidad RNF → prueba (spec 015)",
                "RNF",
                set(COBERTURA_RNF_015),
            ),
        )

        for titulo, prefijo, esperados in secciones:
            with self.subTest(seccion=titulo):
                filas = _filas_de_trazabilidad(titulo, prefijo)
                self.assertEqual(set(filas), esperados, sorted(filas))
                for requisito, linea in filas.items():
                    pares = re.findall(
                        r"`([^`]+\.(?:py|dart))`\s*·\s*«([^»]+)»", linea
                    )
                    self.assertTrue(
                        pares,
                        f"{requisito}: la fila no cita archivo y nombre de prueba",
                    )
                    for archivo, caso in pares:
                        ruta = RAIZ / archivo
                        self.assertTrue(
                            ruta.is_file(),
                            f"{requisito}: la tabla cita un archivo inexistente: "
                            f"{archivo}",
                        )
                        self.assertIn(
                            caso,
                            ruta.read_text(encoding="utf-8"),
                            f"{requisito}: la tabla cita «{caso}», que no está "
                            f"en {archivo}",
                        )

    def test_las_tres_operaciones_de_cuenta_tienen_prueba_de_api_y_de_interfaz(
        self,
    ):
        ids_api = _ids_de_api(MODULOS_API_015)

        self.assertEqual(len(OPERACIONES_CUENTA), 3)
        for operacion, referencias in OPERACIONES_CUENTA.items():
            with self.subTest(operacion=operacion):
                self.assertTrue(referencias.get("api"), "falta la prueba de API")
                self.assertTrue(
                    referencias.get("flutter"), "falta la prueba de interfaz"
                )
                self._verificar_referencias(operacion, referencias, ids_api)

    def test_la_declaracion_de_register_view_esta_en_la_trazabilidad(self):
        tareas = TAREAS_015.read_text(encoding="utf-8")
        self.assertIn("| RF-03, RF-12 | T3 (declarado en T10) |", tareas)
        self.assertIn(
            "register_view.dart`: normalización del correo y validadores del "
            "dominio",
            tareas,
        )

        vista = (
            FLUTTER
            / "lib"
            / "features"
            / "auth"
            / "presentation"
            / "views"
            / "register_view.dart"
        )
        self.assertTrue(vista.is_file())
        codigo = vista.read_text(encoding="utf-8")
        for fragmento in (
            "normalizarCorreo(",
            "esCorreoValido(",
            "validarPasswordRegistro",
            "MensajesCuenta.passwordsNoCoinciden",
            "class _CampoPassword",
        ):
            self.assertIn(fragmento, codigo)

        prueba = (
            FLUTTER
            / "test"
            / "features"
            / "auth"
            / "presentation"
            / "views"
            / "register_view_test.dart"
        )
        self.assertTrue(prueba.is_file())


class TestValidacionGlobal015(unittest.TestCase):
    """Comprobaciones globales de RF-02, RNF-03, RNF-04 y RNF-07."""

    def test_rf02_el_menu_no_depende_del_estado_de_la_cuenta(self):
        # RF-02: una cuenta inactiva muestra las cuatro filas porque el menú no
        # lee el estado de la cuenta. La prueba de widget comprueba las cuatro
        # filas; esta comprobación demuestra que no hay una rama que las oculte.
        vista = (
            FLUTTER
            / "lib"
            / "features"
            / "settings"
            / "presentation"
            / "views"
            / "settings_view.dart"
        )
        self.assertTrue(vista.is_file())
        codigo = vista.read_text(encoding="utf-8")
        # Se buscan identificadores reales, no la subcadena «estado»: un
        # comentario en español que la contenga no incumple RF-02.
        for prohibido in ("AccountBloc", "UserProfile", "isActive"):
            self.assertNotIn(
                prohibido,
                codigo,
                f"El menú no puede depender del estado de la cuenta: {prohibido}",
            )
        self.assertIsNone(
            re.search(r"\.\s*estado\b", codigo),
            "El menú no puede leer el campo `estado` del perfil",
        )

    def test_rnf03_las_vistas_nuevas_no_contienen_logica_de_negocio(self):
        vistas = sorted(
            (FLUTTER / "lib" / "features" / "settings" / "presentation").rglob(
                "*.dart"
            )
        )
        self.assertTrue(vistas, "no se encontraron las vistas de configuración")

        importaciones_prohibidas = (
            "features/account/data/",
            "features/account/domain/repository",
            "features/account/domain/usecase",
            "package:dio/",
            "package:isar/",
        )
        llamadas_prohibidas = (
            "validarFormularioPerfil(",
            "normalizarCorreo(",
            "esCorreoValido(",
        )

        for ruta in vistas:
            codigo = ruta.read_text(encoding="utf-8")
            for prohibido in importaciones_prohibidas:
                self.assertNotIn(
                    prohibido,
                    codigo,
                    f"{ruta.name} importa la capa de datos o de red: {prohibido}",
                )
            for llamada in llamadas_prohibidas:
                self.assertNotIn(
                    llamada,
                    codigo,
                    f"{ruta.name} contiene lógica de validación: {llamada}",
                )

    def test_rnf04_el_dominio_de_cuenta_no_depende_de_flutter_red_ni_almacenamiento(
        self,
    ):
        dominio = sorted(
            (FLUTTER / "lib" / "features" / "account" / "domain").rglob("*.dart")
        )
        self.assertTrue(dominio, "no se encontró el dominio de la cuenta")

        importaciones_prohibidas = (
            "package:flutter/",
            "package:flutter_bloc/",
            "package:dio/",
            "package:isar/",
            "package:get_it/",
            "package:go_router/",
            "features/account/data/",
            "core/network/",
            "core/offline/",
        )

        for ruta in dominio:
            codigo = ruta.read_text(encoding="utf-8")
            for prohibido in importaciones_prohibidas:
                self.assertNotIn(
                    prohibido,
                    codigo,
                    f"{ruta.name} depende de {prohibido} y el dominio debe ser puro",
                )

    def test_rnf07_las_dependencias_declaradas_no_cambian(self):
        archivo_requisitos = RAIZ / "api" / "requirements.txt"
        lineas = archivo_requisitos.read_text(encoding="utf-8").splitlines()
        requisitos = {
            linea.split("==")[0].strip().lower()
            for linea in lineas
            if linea.strip() and not linea.startswith("#")
        }
        self.assertEqual(
            requisitos,
            REQUISITOS_BASE,
            "requirements.txt declara dependencias distintas de la línea base",
        )

        pubspec = _dependencias_de_pubspec(
            (FLUTTER / "pubspec.yaml").read_text(encoding="utf-8")
        )
        self.assertEqual(
            pubspec,
            PUBSPEC_BASE,
            "pubspec.yaml declara dependencias distintas de la línea base",
        )


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
