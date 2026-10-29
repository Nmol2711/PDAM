#include <unity.h>

#include <cstdio>
#include <cstring>

#include "config/report_utils.h"

// Pruebas nativas del reporte de fin de ciclo (spec 014, RF-36, RF-37, RF-39).
// La cabecera no depende de Arduino, así que se ejecuta sin hardware.

void setUp(void) {}

void tearDown(void) {}

namespace {

dispensing::DispenseResult resultado(dispensing::DispenseReason reason,
                                     float solicitados, bool medidosDisponibles,
                                     float medidos, unsigned reintentos) {
  dispensing::DispenseResult result{};
  result.requestedGrams = solicitados;
  result.reason = reason;
  result.baselineAvailable = true;
  result.baselineGrams = 100.0f;
  result.finalAvailable = true;
  result.finalGrams = 100.0f + medidos;
  result.incrementAvailable = medidosDisponibles;
  result.incrementGrams = medidosDisponibles ? medidos : 0.0f;
  result.retryCount = reintentos;
  return result;
}

reporting::ReporteCiclo reporteCompleto() {
  reporting::ReporteCiclo reporte{};
  reporte.orderIdAvailable = true;
  reporte.orderId = 12;
  reporte.motivo = dispensing::DispenseReason::COMPLETED;
  reporte.solicitadosAvailable = true;
  reporte.solicitados = 50.0f;
  reporte.medidosAvailable = true;
  reporte.medidos = 50.4f;
  reporte.reintentos = 0;
  return reporte;
}

} // namespace

// --- Motivo por cada fin de ciclo (RF-36) ---

void test_cada_motivo_tiene_su_codigo_del_catalogo() {
  TEST_ASSERT_EQUAL_STRING(
      "objetivo_alcanzado",
      reporting::motivoPara(dispensing::DispenseReason::COMPLETED));
  TEST_ASSERT_EQUAL_STRING(
      "objetivo_no_alcanzado",
      reporting::motivoPara(dispensing::DispenseReason::NOT_REACHED));
  TEST_ASSERT_EQUAL_STRING(
      "sensor_no_disponible",
      reporting::motivoPara(dispensing::DispenseReason::SENSOR_UNAVAILABLE));
  TEST_ASSERT_EQUAL_STRING(
      "fallo_sensor_dispensacion",
      reporting::motivoPara(dispensing::DispenseReason::SENSOR_FAILURE));
  TEST_ASSERT_EQUAL_STRING(
      "atasco_no_resuelto",
      reporting::motivoPara(dispensing::DispenseReason::STALL_UNRESOLVED));
}

void test_los_cierres_sin_dispensado_reportan_orden_invalida() {
  TEST_ASSERT_EQUAL_STRING(
      "orden_invalida",
      reporting::motivoPara(dispensing::DispenseReason::INVALID_CONFIG));
  TEST_ASSERT_EQUAL_STRING(
      "orden_invalida",
      reporting::motivoPara(dispensing::DispenseReason::INVALID_AMOUNT));
}

// --- JSON del reporte (RF-36) ---

void test_json_completo_con_todos_los_campos() {
  char json[256];
  const reporting::ReporteCiclo reporte = reporteCompleto();

  TEST_ASSERT_TRUE(
      reporting::construirReporteJson("AA:BB:CC:DD:AB:1F", reporte, json,
                                      sizeof(json)));
  TEST_ASSERT_EQUAL_STRING(
      "{\"mac\":\"AA:BB:CC:DD:AB:1F\",\"order_id\":12,"
      "\"motivo\":\"objetivo_alcanzado\",\"gramos_solicitados\":50.00,"
      "\"gramos_medidos\":50.40,\"reintentos\":0}",
      json);
}

void test_json_omite_los_solicitados_ausentes() {
  char json[256];
  reporting::ReporteCiclo reporte = reporteCompleto();
  reporte.motivo = dispensing::DispenseReason::INVALID_AMOUNT;
  reporte.solicitadosAvailable = false;

  TEST_ASSERT_TRUE(
      reporting::construirReporteJson("AA:BB:CC:DD:AB:1F", reporte, json,
                                      sizeof(json)));
  TEST_ASSERT_EQUAL_STRING(
      "{\"mac\":\"AA:BB:CC:DD:AB:1F\",\"order_id\":12,"
      "\"motivo\":\"orden_invalida\",\"gramos_medidos\":50.40,"
      "\"reintentos\":0}",
      json);
}

void test_json_omite_los_medidos_ausentes() {
  char json[256];
  reporting::ReporteCiclo reporte = reporteCompleto();
  reporte.motivo = dispensing::DispenseReason::SENSOR_UNAVAILABLE;
  reporte.medidosAvailable = false;

  TEST_ASSERT_TRUE(
      reporting::construirReporteJson("AA:BB:CC:DD:AB:1F", reporte, json,
                                      sizeof(json)));
  TEST_ASSERT_EQUAL_STRING(
      "{\"mac\":\"AA:BB:CC:DD:AB:1F\",\"order_id\":12,"
      "\"motivo\":\"sensor_no_disponible\",\"gramos_solicitados\":50.00,"
      "\"reintentos\":0}",
      json);
}

void test_json_sin_solicitados_ni_medidos() {
  char json[256];
  reporting::ReporteCiclo reporte{};
  reporte.motivo = dispensing::DispenseReason::INVALID_AMOUNT;
  reporte.reintentos = 0;

  TEST_ASSERT_TRUE(
      reporting::construirReporteJson("AA:BB:CC:DD:AB:1F", reporte, json,
                                      sizeof(json)));
  TEST_ASSERT_EQUAL_STRING(
      "{\"mac\":\"AA:BB:CC:DD:AB:1F\",\"motivo\":\"orden_invalida\","
      "\"reintentos\":0}",
      json);
}

void test_json_omite_la_orden_desconocida_por_el_dispositivo() {
  char json[256];
  reporting::ReporteCiclo reporte{};
  reporte.motivo = dispensing::DispenseReason::INVALID_AMOUNT;

  TEST_ASSERT_TRUE(
      reporting::construirReporteJson("AA:BB:CC:DD:AB:1F", reporte, json,
                                      sizeof(json)));
  TEST_ASSERT_NULL(std::strstr(json, "order_id"));
}

void test_json_conserva_el_contador_de_reintentos_del_ciclo() {
  char json[256];
  reporting::ReporteCiclo reporte = reporteCompleto();
  reporte.motivo = dispensing::DispenseReason::STALL_UNRESOLVED;
  reporte.reintentos = 3;

  TEST_ASSERT_TRUE(
      reporting::construirReporteJson("AA:BB:CC:DD:AB:1F", reporte, json,
                                      sizeof(json)));
  TEST_ASSERT_EQUAL_STRING(
      "{\"mac\":\"AA:BB:CC:DD:AB:1F\",\"order_id\":12,"
      "\"motivo\":\"atasco_no_resuelto\",\"gramos_solicitados\":50.00,"
      "\"gramos_medidos\":50.40,\"reintentos\":3}",
      json);
}

void test_json_rechaza_buffers_y_mac_no_usables() {
  char json[256];
  const reporting::ReporteCiclo reporte = reporteCompleto();

  TEST_ASSERT_FALSE(
      reporting::construirReporteJson(nullptr, reporte, json, sizeof(json)));
  TEST_ASSERT_FALSE(
      reporting::construirReporteJson("AA:BB:CC:DD:AB:1F", reporte, nullptr,
                                      sizeof(json)));
  TEST_ASSERT_FALSE(
      reporting::construirReporteJson("AA:BB:CC:DD:AB:1F", reporte, json, 0));
  TEST_ASSERT_FALSE(
      reporting::construirReporteJson("", reporte, json, sizeof(json)));
  TEST_ASSERT_FALSE(
      reporting::construirReporteJson(nullptr, reporte, json, sizeof(json)));
}

void test_un_buffer_corto_no_escribe_un_json_parcial() {
  char json[16];
  std::memset(json, 'X', sizeof(json));
  const reporting::ReporteCiclo reporte = reporteCompleto();

  TEST_ASSERT_FALSE(
      reporting::construirReporteJson("AA:BB:CC:DD:AB:1F", reporte, json,
                                      sizeof(json)));
  // Solo se acepta como resultado un JSON completo.
  TEST_ASSERT_TRUE(std::strlen(json) < sizeof(json));
}

// --- Reporte derivado del ciclo (RF-36) ---

void test_el_reporte_usa_el_incremento_medido_del_ciclo() {
  const auto result = resultado(dispensing::DispenseReason::COMPLETED, 50.0f,
                                true, 50.4f, 1);
  const reporting::ReporteCiclo reporte =
      reporting::reporteDesdeResultado(result, true, 12);

  TEST_ASSERT_TRUE(reporte.orderIdAvailable);
  TEST_ASSERT_EQUAL_INT(12, reporte.orderId);
  TEST_ASSERT_TRUE(reporte.solicitadosAvailable);
  TEST_ASSERT_EQUAL_FLOAT(50.0f, reporte.solicitados);
  TEST_ASSERT_TRUE(reporte.medidosAvailable);
  TEST_ASSERT_EQUAL_FLOAT(50.4f, reporte.medidos);
  TEST_ASSERT_EQUAL_UINT(1, reporte.reintentos);
}

void test_sin_incremento_disponible_no_hay_medidos() {
  const auto result = resultado(dispensing::DispenseReason::SENSOR_UNAVAILABLE,
                                50.0f, false, 0.0f, 0);
  const reporting::ReporteCiclo reporte =
      reporting::reporteDesdeResultado(result, true, 12);

  TEST_ASSERT_FALSE(reporte.medidosAvailable);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, reporte.medidos);
  TEST_ASSERT_EQUAL_STRING("sensor_no_disponible",
                           reporting::motivoPara(reporte.motivo));
}

void test_sin_identificador_de_orden_el_reporte_lo_declara_ausente() {
  const auto result =
      resultado(dispensing::DispenseReason::COMPLETED, 50.0f, true, 50.0f, 0);
  const reporting::ReporteCiclo reporte =
      reporting::reporteDesdeResultado(result, false, 0);

  TEST_ASSERT_FALSE(reporte.orderIdAvailable);
}

// --- Clasificación de la respuesta (RF-39) ---

void test_un_200_descarta_el_reporte() {
  TEST_ASSERT_TRUE(reporting::clasificarRespuestaReporte(200, nullptr) ==
                   reporting::ReporteAccion::DESCARTAR);
}

void test_los_tres_400_enumerados_se_descartan() {
  TEST_ASSERT_TRUE(reporting::clasificarRespuestaReporte(
                       400, "orden_desconocida") ==
                   reporting::ReporteAccion::DESCARTAR);
  TEST_ASSERT_TRUE(reporting::clasificarRespuestaReporte(
                       400, "motivo_invalido") ==
                   reporting::ReporteAccion::DESCARTAR);
  TEST_ASSERT_TRUE(reporting::clasificarRespuestaReporte(
                       400, "mac_no_registrada") ==
                   reporting::ReporteAccion::DESCARTAR);
}

void test_un_400_no_enumerado_tambien_se_descarta() {
  // Decisión defensiva: reintentar un rechazo de negocio produciría un bucle.
  TEST_ASSERT_TRUE(reporting::clasificarRespuestaReporte(400, "otro_codigo") ==
                   reporting::ReporteAccion::DESCARTAR);
  TEST_ASSERT_TRUE(reporting::clasificarRespuestaReporte(400, nullptr) ==
                   reporting::ReporteAccion::DESCARTAR);
}

void test_los_5xx_y_los_errores_de_red_se_reintentan() {
  TEST_ASSERT_TRUE(reporting::clasificarRespuestaReporte(500, nullptr) ==
                   reporting::ReporteAccion::REINTENTAR);
  TEST_ASSERT_TRUE(reporting::clasificarRespuestaReporte(503, nullptr) ==
                   reporting::ReporteAccion::REINTENTAR);
  TEST_ASSERT_TRUE(reporting::clasificarRespuestaReporte(-1, nullptr) ==
                   reporting::ReporteAccion::REINTENTAR);
  TEST_ASSERT_TRUE(reporting::clasificarRespuestaReporte(0, nullptr) ==
                   reporting::ReporteAccion::REINTENTAR);
}

void test_codigos_definitivos_del_catalogo() {
  TEST_ASSERT_TRUE(reporting::esCodigoDescartable("orden_desconocida"));
  TEST_ASSERT_TRUE(reporting::esCodigoDescartable("motivo_invalido"));
  TEST_ASSERT_TRUE(reporting::esCodigoDescartable("mac_no_registrada"));
  TEST_ASSERT_FALSE(reporting::esCodigoDescartable("cantidad_invalida"));
  TEST_ASSERT_FALSE(reporting::esCodigoDescartable(""));
  TEST_ASSERT_FALSE(reporting::esCodigoDescartable(nullptr));
}

// --- Resumen del monitor serie (RF-36) ---

void test_el_resumen_muestra_la_orden_y_el_motivo_del_ciclo() {
  const reporting::ReporteCiclo reporte = reporteCompleto();
  char resumen[160];
  reporting::formatearResumenCiclo(reporte, 118, resumen, sizeof(resumen));
  TEST_ASSERT_EQUAL_STRING("Reporte a enviar: order_id=12, "
                           "motivo=objetivo_alcanzado, longitud=118 bytes",
                           resumen);
}

void test_el_resumen_sin_identificador_de_orden_lo_declara_no_disponible() {
  const reporting::ReporteCiclo reporte = reporting::reporteVacio(
      dispensing::DispenseReason::SENSOR_UNAVAILABLE);
  char resumen[160];
  reporting::formatearResumenCiclo(reporte, 60, resumen, sizeof(resumen));
  TEST_ASSERT_EQUAL_STRING("Reporte a enviar: order_id=no disponible, "
                           "motivo=sensor_no_disponible, longitud=60 bytes",
                           resumen);
}

void test_el_resumen_no_repite_la_mac_ni_el_cuerpo() {
  reporting::ReporteCiclo reporte = reporteCompleto();
  reporte.motivo = dispensing::DispenseReason::STALL_UNRESOLVED;
  char json[256];
  TEST_ASSERT_TRUE(reporting::construirReporteJson("AA:BB:CC:DD:EE:FF", reporte,
                                                   json, sizeof(json)));

  char resumen[160];
  reporting::formatearResumenCiclo(reporte, std::strlen(json), resumen,
                                   sizeof(resumen));
  TEST_ASSERT_NOT_NULL(std::strstr(resumen, "order_id=12"));
  TEST_ASSERT_NOT_NULL(std::strstr(resumen, "motivo=atasco_no_resuelto"));
  char longitud[32];
  std::snprintf(longitud, sizeof(longitud), "longitud=%lu bytes",
                static_cast<unsigned long>(std::strlen(json)));
  TEST_ASSERT_NOT_NULL(std::strstr(resumen, longitud));
  TEST_ASSERT_NULL(std::strstr(resumen, "AA:BB:CC"));
  TEST_ASSERT_NULL(std::strstr(resumen, "gramos_medidos"));
}

void test_el_resumen_de_un_pendiente_recupera_orden_y_motivo() {
  reporting::ReporteCiclo reporte = reporteCompleto();
  reporte.motivo = dispensing::DispenseReason::SENSOR_FAILURE;
  char json[256];
  TEST_ASSERT_TRUE(reporting::construirReporteJson("AA:BB:CC:DD:EE:FF", reporte,
                                                   json, sizeof(json)));

  long orden = -1;
  bool ordenDisponible = true;
  char motivo[32];
  TEST_ASSERT_TRUE(reporting::extraerResumenReporte(
      json, &orden, &ordenDisponible, motivo, sizeof(motivo)));
  TEST_ASSERT_TRUE(ordenDisponible);
  TEST_ASSERT_EQUAL_INT(12, static_cast<int>(orden));
  TEST_ASSERT_EQUAL_STRING("fallo_sensor_dispensacion", motivo);

  char resumen[160];
  reporting::formatearResumenReporte(orden, ordenDisponible, motivo,
                                     std::strlen(json), resumen,
                                     sizeof(resumen));
  TEST_ASSERT_NOT_NULL(std::strstr(
      resumen, "order_id=12, motivo=fallo_sensor_dispensacion"));
  TEST_ASSERT_NOT_NULL(std::strstr(resumen, "longitud="));
}

void test_el_resumen_de_un_pendiente_sin_orden_no_inventa_un_numero() {
  const reporting::ReporteCiclo reporte = reporting::reporteVacio(
      dispensing::DispenseReason::INVALID_AMOUNT);
  char json[256];
  TEST_ASSERT_TRUE(reporting::construirReporteJson("AA:BB:CC:DD:EE:FF", reporte,
                                                   json, sizeof(json)));

  long orden = 7;
  bool ordenDisponible = true;
  char motivo[32];
  TEST_ASSERT_TRUE(reporting::extraerResumenReporte(
      json, &orden, &ordenDisponible, motivo, sizeof(motivo)));
  TEST_ASSERT_FALSE(ordenDisponible);
  TEST_ASSERT_EQUAL_STRING("orden_invalida", motivo);
}

void test_el_resumen_ignora_un_cuerpo_inexistente() {
  long orden = 7;
  bool ordenDisponible = true;
  char motivo[16] = "x";
  TEST_ASSERT_FALSE(reporting::extraerResumenReporte(
      nullptr, &orden, &ordenDisponible, motivo, sizeof(motivo)));
  TEST_ASSERT_FALSE(ordenDisponible);
  TEST_ASSERT_EQUAL_STRING("", motivo);
}

// --- Política de reintentos (RF-37) ---

void test_la_politica_conserva_timeout_y_esperas() {
  TEST_ASSERT_EQUAL_UINT32(10000, reporting::kReportTimeoutMs);
  TEST_ASSERT_EQUAL_UINT32(5000, reporting::kReportRetryDelaysMs[0]);
  TEST_ASSERT_EQUAL_UINT32(15000, reporting::kReportRetryDelaysMs[1]);
  TEST_ASSERT_EQUAL_UINT(3, reporting::kReportMaxAttempts);
}

void test_se_reintenta_solo_mientras_queden_intentos() {
  TEST_ASSERT_TRUE(reporting::hayReintentoDisponible(0));
  TEST_ASSERT_TRUE(reporting::hayReintentoDisponible(1));
  TEST_ASSERT_TRUE(reporting::hayReintentoDisponible(2));
  TEST_ASSERT_FALSE(reporting::hayReintentoDisponible(3));
}

int main(int argc, char **argv) {
  UNITY_BEGIN();
  RUN_TEST(test_cada_motivo_tiene_su_codigo_del_catalogo);
  RUN_TEST(test_los_cierres_sin_dispensado_reportan_orden_invalida);
  RUN_TEST(test_json_completo_con_todos_los_campos);
  RUN_TEST(test_json_omite_los_solicitados_ausentes);
  RUN_TEST(test_json_omite_los_medidos_ausentes);
  RUN_TEST(test_json_sin_solicitados_ni_medidos);
  RUN_TEST(test_json_omite_la_orden_desconocida_por_el_dispositivo);
  RUN_TEST(test_json_conserva_el_contador_de_reintentos_del_ciclo);
  RUN_TEST(test_json_rechaza_buffers_y_mac_no_usables);
  RUN_TEST(test_un_buffer_corto_no_escribe_un_json_parcial);
  RUN_TEST(test_el_reporte_usa_el_incremento_medido_del_ciclo);
  RUN_TEST(test_sin_incremento_disponible_no_hay_medidos);
  RUN_TEST(test_sin_identificador_de_orden_el_reporte_lo_declara_ausente);
  RUN_TEST(test_un_200_descarta_el_reporte);
  RUN_TEST(test_los_tres_400_enumerados_se_descartan);
  RUN_TEST(test_un_400_no_enumerado_tambien_se_descarta);
  RUN_TEST(test_los_5xx_y_los_errores_de_red_se_reintentan);
  RUN_TEST(test_codigos_definitivos_del_catalogo);
  RUN_TEST(test_el_resumen_muestra_la_orden_y_el_motivo_del_ciclo);
  RUN_TEST(test_el_resumen_sin_identificador_de_orden_lo_declara_no_disponible);
  RUN_TEST(test_el_resumen_no_repite_la_mac_ni_el_cuerpo);
  RUN_TEST(test_el_resumen_de_un_pendiente_recupera_orden_y_motivo);
  RUN_TEST(test_el_resumen_de_un_pendiente_sin_orden_no_inventa_un_numero);
  RUN_TEST(test_el_resumen_ignora_un_cuerpo_inexistente);
  RUN_TEST(test_la_politica_conserva_timeout_y_esperas);
  RUN_TEST(test_se_reintenta_solo_mientras_queden_intentos);
  return UNITY_END();
}
