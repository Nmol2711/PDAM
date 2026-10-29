"""Pruebas unitarias puras del dominio de la spec 014 (T3).

Cubren catálogos cerrados y errores de negocio (RF-3, RF-14, RF-17, RF-21,
RNF-1, RNF-7), MAC parcial (RF-3, RNF-1), instantes con desplazamiento
(RF-30, RF-31), plazo con tolerancia (RF-19, RF-20) y descuento acotado
(RF-15, RF-22). No tocan base de datos, FastAPI ni SQLAlchemy: son funciones
puras con el instante y el stock como parámetros.

El registro del dispensado y sus campos (RF-24) no se cubren aquí: dependen del
cierre de la orden y se prueban con la base de datos en
`api/tests/test_orders_dispensing.py` (T4).
"""

import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from app.domain import catalogos, consulta, stock, tiempo
from app.domain.catalogos import ErrorDominio
from app.services.mac_service import es_mac_parcial, mask_mac


# --- Tablas de la spec (fuente de verdad de los catálogos) ---------------------

# 9 tipos de evento con su etiqueta visible.
TIPOS_EVENTO_ESPERADOS = {
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

# 2 resultados con su etiqueta visible.
RESULTADOS_ESPERADOS = {
    "success": "Éxito",
    "failure": "Fallo",
}

# 12 causas con etiqueta, resultado asociado y origen.
CAUSAS_ESPERADAS = {
    "objetivo_alcanzado": ("Objetivo alcanzado", "success", "reporte"),
    "objetivo_no_alcanzado": ("Objetivo no alcanzado", "failure", "reporte"),
    "atasco_no_resuelto": ("Atasco no resuelto", "failure", "reporte"),
    "sensor_no_disponible": ("Sensor no disponible", "failure", "reporte"),
    "fallo_sensor_dispensacion": (
        "Fallo del sensor durante la dispensación",
        "failure",
        "reporte",
    ),
    "orden_invalida": ("Orden inválida", "failure", "reporte"),
    "entrega_incompleta": ("Entrega incompleta", "failure", "servidor"),
    "sin_reporte": ("Sin reporte", "failure", "servidor"),
    "orden_cerrada": ("Orden cerrada", "failure", "servidor"),
    "orden_desconocida": ("Orden desconocida", "failure", "servidor"),
    "supera_capacidad": ("Supera la capacidad", "failure", "servidor"),
    "cantidad_invalida": ("Cantidad inválida", "failure", "servidor"),
}

# Subconjunto de causas que un dispositivo puede declarar como motivo.
MOTIVOS_REPORTE_ESPERADOS = {
    "objetivo_alcanzado",
    "objetivo_no_alcanzado",
    "atasco_no_resuelto",
    "sensor_no_disponible",
    "fallo_sensor_dispensacion",
    "orden_invalida",
}

# Tabla del catálogo de errores de la spec, con el mensaje visible exacto.
# La tabla de `spec.md` tiene 11 filas, aunque `plan.md` y `tasks.md` digan «12»;
# la spec es la fuente de verdad y su prueba transversal exige que ninguna fila
# quede sin uso en un RF, por lo que no se añaden códigos inventados.
ERRORES_ESPERADOS = {
    "cantidad_invalida": "La cantidad debe ser un número mayor que cero.",
    "supera_capacidad": (
        "La cantidad supera la capacidad máxima de 5000 g del dispensador."
    ),
    "tipo_evento_invalido": "El tipo de evento no pertenece al catálogo.",
    "resultado_invalido": "El resultado no pertenece al catálogo.",
    "rango_fechas_invalido": (
        "El rango de fechas no es válido: revise el orden de los límites y el "
        "desplazamiento horario."
    ),
    "pagina_invalida": "El número de página debe ser 1 o mayor.",
    "tamano_pagina_invalido": "El tamaño de página debe estar entre 1 y 100.",
    "motivo_invalido": "El motivo del reporte no pertenece al catálogo.",
    "mac_no_registrada": "El dispensador no está registrado.",
    "orden_desconocida": (
        "La orden indicada no existe para el dispensador que reporta."
    ),
    "stock_fuera_de_rango": (
        "El stock resultante quedaría fuera del intervalo de 0 a 5000 g."
    ),
}

# Valores que no pueden colarse como código de ningún catálogo cerrado.
VALORES_LIBRES = [
    "",
    " ",
    None,
    123,
    ["pet_created"],
    "sin_clasificar",
    "Sin clasificar",
    "PET_CREATED",
    "pet_created ",
    " pet_created",
    "feeding",
    "objetivo_alcanzado_extra",
]


class TestCatalogoDeTiposEvento(unittest.TestCase):
    """RF-3, RNF-7: 9 tipos con etiqueta exacta y ningún valor libre."""

    def test_contiene_exactamente_los_nueve_tipos_con_su_etiqueta(self):
        self.assertEqual(catalogos.TIPOS_EVENTO, TIPOS_EVENTO_ESPERADOS)
        self.assertEqual(len(catalogos.TIPOS_EVENTO), 9)

    def test_etiqueta_de_cada_tipo_coincide_con_la_spec(self):
        for codigo, etiqueta in TIPOS_EVENTO_ESPERADOS.items():
            with self.subTest(codigo=codigo):
                self.assertEqual(catalogos.etiqueta_tipo_evento(codigo), etiqueta)
                self.assertTrue(catalogos.es_tipo_valido(codigo))

    def test_ningun_valor_libre_se_acepta_como_tipo(self):
        for valor in VALORES_LIBRES:
            with self.subTest(valor=repr(valor)):
                self.assertFalse(catalogos.es_tipo_valido(valor))

    def test_sin_clasificar_no_es_un_tipo_del_catalogo(self):
        self.assertNotIn("sin_clasificar", catalogos.TIPOS_EVENTO)
        self.assertNotIn("Sin clasificar", catalogos.TIPOS_EVENTO.values())
        self.assertEqual(catalogos.ETIQUETA_SIN_CLASIFICAR, "Sin clasificar")
        # Un registro histórico sin tipo se presenta como «Sin clasificar» y no
        # es filtrable por tipo (RF-41).
        self.assertEqual(
            catalogos.etiqueta_tipo_evento(None), catalogos.ETIQUETA_SIN_CLASIFICAR
        )


class TestCatalogoDeResultados(unittest.TestCase):
    """RF-3, RNF-7: solo éxito y fallo, con su etiqueta."""

    def test_contiene_exactamente_los_dos_resultados(self):
        self.assertEqual(catalogos.RESULTADOS, RESULTADOS_ESPERADOS)
        self.assertEqual(len(catalogos.RESULTADOS), 2)

    def test_solo_los_dos_codigos_del_catalogo_son_validos(self):
        for codigo, etiqueta in RESULTADOS_ESPERADOS.items():
            with self.subTest(codigo=codigo):
                self.assertTrue(catalogos.es_resultado_valido(codigo))
                self.assertEqual(catalogos.etiqueta_resultado(codigo), etiqueta)

        for valor in VALORES_LIBRES + ["Success", "ok", "exito"]:
            with self.subTest(valor=repr(valor)):
                self.assertFalse(catalogos.es_resultado_valido(valor))

    def test_un_registro_sin_clasificar_no_tiene_resultado(self):
        self.assertIsNone(catalogos.etiqueta_resultado(None))


class TestCatalogoDeCausas(unittest.TestCase):
    """RF-3, RF-17, RF-24, RNF-7: 12 causas con resultado y origen."""

    def test_contiene_exactamente_las_doce_causas(self):
        self.assertEqual(set(catalogos.CAUSAS), set(CAUSAS_ESPERADAS))
        self.assertEqual(len(catalogos.CAUSAS), 12)

    def test_etiqueta_resultado_y_origen_de_cada_causa(self):
        for codigo, (etiqueta, resultado, origen) in CAUSAS_ESPERADAS.items():
            with self.subTest(causa=codigo):
                causa = catalogos.CAUSAS[codigo]
                self.assertEqual(causa.etiqueta, etiqueta)
                self.assertEqual(causa.resultado, resultado)
                self.assertEqual(causa.origen, origen)
                self.assertTrue(catalogos.es_causa_valida(codigo))

    def test_el_resultado_de_cada_causa_pertenece_al_catalogo(self):
        for codigo, causa in catalogos.CAUSAS.items():
            with self.subTest(causa=codigo):
                self.assertIn(causa.resultado, catalogos.RESULTADOS)

    def test_seis_causas_son_de_reporte_y_seis_del_servidor(self):
        de_reporte = {
            codigo
            for codigo, causa in catalogos.CAUSAS.items()
            if causa.origen == "reporte"
        }
        del_servidor = {
            codigo
            for codigo, causa in catalogos.CAUSAS.items()
            if causa.origen == "servidor"
        }
        self.assertEqual(de_reporte, MOTIVOS_REPORTE_ESPERADOS)
        self.assertEqual(len(de_reporte), 6)
        self.assertEqual(len(del_servidor), 6)

    def test_ningun_valor_libre_se_acepta_como_causa(self):
        for valor in VALORES_LIBRES + ["sin_reporte ", "entrega_incompleta "]:
            with self.subTest(valor=repr(valor)):
                self.assertFalse(catalogos.es_causa_valida(valor))


class TestMotivosDeReporte(unittest.TestCase):
    """RF-14, RF-17, RF-21: motivos admitidos y mapeo a resultado y causa."""

    def test_solo_se_admiten_los_seis_motivos_de_la_spec(self):
        self.assertEqual(set(catalogos.MOTIVOS_REPORTE), MOTIVOS_REPORTE_ESPERADOS)
        for motivo in MOTIVOS_REPORTE_ESPERADOS:
            with self.subTest(motivo=motivo):
                self.assertTrue(catalogos.es_causa_de_reporte(motivo))

    def test_las_causas_asignadas_por_el_servidor_no_son_motivo_de_reporte(self):
        causas_del_servidor = [
            codigo
            for codigo, causa in catalogos.CAUSAS.items()
            if causa.origen == "servidor"
        ]
        self.assertEqual(len(causas_del_servidor), 6)

        for motivo in causas_del_servidor:
            with self.subTest(motivo=motivo):
                self.assertFalse(catalogos.es_causa_de_reporte(motivo))
                with self.assertRaises(ErrorDominio) as contexto:
                    catalogos.resultado_para_motivo(motivo)
                self.assertEqual(contexto.exception.code, "motivo_invalido")

    def test_ningun_valor_libre_se_acepta_como_motivo(self):
        for valor in VALORES_LIBRES + ["sin_reporte", "orden_cerrada"]:
            with self.subTest(valor=repr(valor)):
                self.assertFalse(catalogos.es_causa_de_reporte(valor))

    def test_objetivo_alcanzado_con_medidos_suficientes_produce_exito(self):
        for medidos, solicitados in ((50.0, 50.0), (50.4, 50.0), (51.0, 50.0)):
            with self.subTest(medidos=medidos, solicitados=solicitados):
                self.assertEqual(
                    catalogos.resultado_para_motivo(
                        "objetivo_alcanzado", medidos=medidos, solicitados=solicitados
                    ),
                    ("success", "objetivo_alcanzado"),
                )

    def test_objetivo_alcanzado_con_medidos_menores_produce_entrega_incompleta(self):
        for medidos in (49.9, 25.0, 0.0):
            with self.subTest(medidos=medidos):
                self.assertEqual(
                    catalogos.resultado_para_motivo(
                        "objetivo_alcanzado", medidos=medidos, solicitados=50.0
                    ),
                    ("failure", "entrega_incompleta"),
                )

    def test_objetivo_alcanzado_sin_medidos_no_acredita_el_objetivo(self):
        # RF-16: sin medidos no se puede acreditar el objetivo.
        self.assertEqual(
            catalogos.resultado_para_motivo(
                "objetivo_alcanzado", medidos=None, solicitados=50.0
            ),
            ("failure", "entrega_incompleta"),
        )

    def test_cada_motivo_de_fallo_produce_la_causa_homonima_sin_exito(self):
        for motivo in MOTIVOS_REPORTE_ESPERADOS - {"objetivo_alcanzado"}:
            with self.subTest(motivo=motivo):
                resultado, causa = catalogos.resultado_para_motivo(
                    motivo, medidos=10.0, solicitados=50.0
                )
                self.assertEqual(resultado, "failure")
                self.assertEqual(causa, motivo)

    def test_toda_causa_resultante_pertenece_al_catalogo_y_es_coherente(self):
        for motivo in MOTIVOS_REPORTE_ESPERADOS:
            for medidos, solicitados in (
                (50.0, 50.0),
                (10.0, 50.0),
                (None, 50.0),
            ):
                with self.subTest(motivo=motivo, medidos=medidos):
                    resultado, causa = catalogos.resultado_para_motivo(
                        motivo, medidos=medidos, solicitados=solicitados
                    )
                    self.assertIn(causa, catalogos.CAUSAS)
                    self.assertEqual(catalogos.CAUSAS[causa].resultado, resultado)

    def test_un_motivo_fuera_del_catalogo_se_rechaza_con_motivo_invalido(self):
        for valor in ("", "otro", "SIN_REPORTE", None):
            with self.subTest(valor=repr(valor)):
                with self.assertRaises(ErrorDominio) as contexto:
                    catalogos.resultado_para_motivo(valor)
                self.assertEqual(contexto.exception.code, "motivo_invalido")
                self.assertEqual(
                    contexto.exception.message,
                    ERRORES_ESPERADOS["motivo_invalido"],
                )


class TestCatalogoDeErrores(unittest.TestCase):
    """RF-2, RF-12, RF-21, RF-31, RF-32, RF-39, RNF-7: códigos y mensajes."""

    def test_cada_codigo_tiene_el_mensaje_exacto_de_la_spec(self):
        self.assertEqual(catalogos.MENSAJES_ERROR, ERRORES_ESPERADOS)

    def test_error_de_dominio_expone_code_y_message_del_catalogo(self):
        for codigo, mensaje in ERRORES_ESPERADOS.items():
            with self.subTest(codigo=codigo):
                error = ErrorDominio(codigo)
                self.assertIsInstance(error, Exception)
                self.assertEqual(error.code, codigo)
                self.assertEqual(error.message, mensaje)
                self.assertEqual(str(error), mensaje)
                # Forma que el endpoint devuelve en `detail` (HTTP 400).
                self.assertEqual(error.detail, {"code": codigo, "message": mensaje})

    def test_un_codigo_fuera_del_catalogo_no_se_puede_construir(self):
        # Un código desconocido es un error de programación, no de negocio.
        for codigo in ("error_inventado", "", None):
            with self.subTest(codigo=repr(codigo)):
                with self.assertRaises(ValueError):
                    ErrorDominio(codigo)

    def test_ningun_mensaje_esta_vacio_ni_lleva_emoji(self):
        for codigo, mensaje in ERRORES_ESPERADOS.items():
            with self.subTest(codigo=codigo):
                self.assertTrue(mensaje.strip())
                self.assertFalse(
                    any(orden >= 0x1F300 for orden in map(ord, mensaje)),
                    f"{codigo}: el mensaje no debe contener emojis (RNF-1).",
                )


class TestMaskMac(unittest.TestCase):
    """RF-3, RNF-1: `**` literal y los dos últimos octetos en mayúsculas."""

    def test_cualquier_formato_equivalente_produce_la_misma_mac_parcial(self):
        formatos = [
            "AA:BB:CC:DD:AB:1F",  # dos puntos y mayúsculas
            "aa:bb:cc:dd:ab:1f",  # minúsculas
            "AA-BB-CC-DD-AB-1F",  # guiones
            "aa bb cc dd ab 1f",  # espacios
            "aa.bb.cc.dd.ab.1f",  # puntos
            "AABBCCDDAB1F",       # sin separadores
            "Aa:bB-cC dD.aB:1f",  # mezcla de separadores y de caja
        ]
        for formato in formatos:
            with self.subTest(formato=formato):
                self.assertEqual(mask_mac(formato), "**:AB:1F")

    def test_el_prefijo_es_siempre_dos_asteriscos_aunque_la_mac_tenga_mas_octetos(self):
        # La spec exige el mismo prefijo literal sin importar cuántos octetos
        # tenga la dirección original.
        for formato in (
            "AA:BB:CC:DD:EE:FF:AB:1F",
            "AA-BB-CC-DD-EE-FF-AB-1F",
            "aabbccddeeffab1f",
        ):
            with self.subTest(formato=formato):
                parcial = mask_mac(formato)
                self.assertEqual(parcial, "**:AB:1F")
                self.assertEqual(parcial.count("*"), 2)

    def test_la_mac_parcial_nunca_contiene_la_direccion_completa(self):
        completa = "AA:BB:CC:DD:AB:1F"
        parcial = mask_mac(completa)
        self.assertEqual(len(parcial), len("**:AB:1F"))
        self.assertTrue(parcial.startswith("**:"))
        self.assertNotIn("AA", parcial)
        self.assertNotIn("BB", parcial)
        self.assertNotIn("CC", parcial)
        self.assertNotIn("DD", parcial)

    def test_una_mac_ausente_no_produce_una_direccion_parcial(self):
        for valor in (None, "", "   ", "GG:BB"):
            with self.subTest(valor=repr(valor)):
                self.assertEqual(mask_mac(valor), "**")

    def test_una_mac_ya_enmascarada_se_conserva_tal_cual(self):
        # Enmascarar es idempotente: una instantánea que ya guarda la MAC parcial
        # (por ejemplo la de una orden cuyo dispensador se eliminó) no puede
        # acabar como el prefijo suelto `**` al volver a pasar por `mask_mac`
        # (RF-3, RNF-1).
        for valor in ("**:AB:1F", " **:AB:1F ", "**:ab:1f"):
            with self.subTest(valor=repr(valor)):
                self.assertEqual(mask_mac(valor), "**:AB:1F")
                self.assertTrue(es_mac_parcial(valor))

        # El prefijo suelto tampoco se pierde al reprocesarlo.
        self.assertEqual(mask_mac("**"), "**")
        self.assertTrue(es_mac_parcial("**"))

    def test_una_mac_completa_no_se_confunde_con_una_parcial(self):
        for valor in ("AA:BB:CC:DD:AB:1F", "AABBCCDDAB1F", "", None):
            with self.subTest(valor=repr(valor)):
                self.assertFalse(es_mac_parcial(valor))


class TestParseoDeInstantes(unittest.TestCase):
    """RF-30, RF-31, RNF-8: ISO 8601 con desplazamiento explícito a UTC."""

    def test_acepta_el_sufijo_z_como_utc(self):
        instante = tiempo.parsear_instante_explicito("2026-10-01T00:00:00Z")
        self.assertEqual(instante, datetime(2026, 10, 1, tzinfo=timezone.utc))
        self.assertEqual(instante.utcoffset(), timedelta(0))

    def test_el_sufijo_z_y_el_desplazamiento_cero_son_el_mismo_instante(self):
        con_z = tiempo.parsear_instante_explicito("2026-10-01T00:00:00Z")
        con_offset = tiempo.parsear_instante_explicito("2026-10-01T00:00:00+00:00")
        self.assertEqual(con_z, con_offset)

    def test_acepta_desplazamientos_positivos_y_negativos(self):
        casos = {
            "2026-10-01T00:00:00-05:00": datetime(2026, 10, 1, 5, tzinfo=timezone.utc),
            "2026-10-01T00:00:00+05:00": datetime(2026, 9, 30, 19, tzinfo=timezone.utc),
            "2026-10-01T00:00:00+05:30": datetime(2026, 9, 30, 18, 30, tzinfo=timezone.utc),
        }
        for texto, esperado in casos.items():
            with self.subTest(texto=texto):
                self.assertEqual(tiempo.parsear_instante_explicito(texto), esperado)

    def test_acepta_fracciones_de_segundo(self):
        casos = {
            "2026-10-01T00:00:00.250Z": 250000,
            "2026-10-01T00:00:00.250250-05:00": 250250,
            "2026-10-01T12:34:56.5Z": 500000,
        }
        for texto, microsegundos in casos.items():
            with self.subTest(texto=texto):
                self.assertEqual(
                    tiempo.parsear_instante_explicito(texto).microsecond, microsegundos
                )

    def test_rechaza_un_instante_sin_desplazamiento(self):
        for texto in (
            "2026-10-01T00:00:00",
            "2026-10-01T00:00:00.250",
            "2026-10-01",
            "2026-10-01 00:00:00",
        ):
            with self.subTest(texto=texto):
                with self.assertRaises(ErrorDominio) as contexto:
                    tiempo.parsear_instante_explicito(texto)
                self.assertEqual(contexto.exception.code, "rango_fechas_invalido")

    def test_rechaza_textos_invalidos_o_ausentes(self):
        for texto in (
            "",
            "   ",
            None,
            "no-es-una-fecha",
            "2026-13-01T00:00:00Z",
            "2026-10-01T25:00:00Z",
            "2026-10-01T00:00:00+99:00",
            "01/10/2026T00:00:00Z",
            123,
        ):
            with self.subTest(texto=repr(texto)):
                with self.assertRaises(ErrorDominio) as contexto:
                    tiempo.parsear_instante_explicito(texto)
                self.assertEqual(contexto.exception.code, "rango_fechas_invalido")

    def test_a_utc_naive_normaliza_sin_conservar_la_zona(self):
        self.assertEqual(
            tiempo.a_utc_naive(datetime(2026, 10, 1, 0, tzinfo=timezone.utc)),
            datetime(2026, 10, 1, 0),
        )
        self.assertEqual(
            tiempo.a_utc_naive(datetime(2026, 10, 1, 0, tzinfo=timezone(timedelta(hours=-5)))),
            datetime(2026, 10, 1, 5),
        )
        # Un instante naive ya se interpreta como UTC del servidor (RNF-8).
        self.assertEqual(
            tiempo.a_utc_naive(datetime(2026, 10, 1, 5)), datetime(2026, 10, 1, 5)
        )


class TestTextoUtc(unittest.TestCase):
    """RNF-8 y plan §5.3: la consulta devuelve la fecha en UTC con sufijo `Z`."""

    def test_devuelve_iso_en_utc_con_sufijo_z(self):
        self.assertEqual(
            tiempo.a_texto_utc(datetime(2026, 10, 1, 12, 0, 0)),
            "2026-10-01T12:00:00Z",
        )

    def test_convierte_a_utc_los_instantes_con_desplazamiento(self):
        self.assertEqual(
            tiempo.a_texto_utc(
                datetime(2026, 10, 1, 7, 0, 0, tzinfo=timezone(timedelta(hours=-5)))
            ),
            "2026-10-01T12:00:00Z",
        )

    def test_conserva_las_fracciones_de_segundo(self):
        self.assertEqual(
            tiempo.a_texto_utc(datetime(2026, 10, 1, 12, 0, 0, 123456)),
            "2026-10-01T12:00:00.123456Z",
        )


class TestPlazoDeOrden(unittest.TestCase):
    """RF-19, RF-20, RNF-3: 5 minutos más 1 segundo de tolerancia inclusiva."""

    def test_las_constantes_coinciden_con_la_spec(self):
        self.assertEqual(tiempo.PLAZO_ORDEN, timedelta(minutes=5))
        self.assertEqual(tiempo.TOLERANCIA, timedelta(seconds=1))
        self.assertEqual(tiempo.INTERVALO_BARRIDO, timedelta(seconds=30))

    def test_antes_del_limite_esta_dentro_del_plazo(self):
        entregada = datetime(2026, 10, 1, 12, 0, 0)
        ahora = entregada + timedelta(minutes=5, seconds=1) - timedelta(milliseconds=1)
        self.assertTrue(tiempo.dentro_del_plazo(entregada, ahora))
        self.assertFalse(tiempo.plazo_vencido(entregada, ahora))

    def test_en_el_limite_exacto_sigue_dentro_del_plazo(self):
        # Tolerancia inclusiva: entregada + 5 min + 1 s todavía está en plazo.
        entregada = datetime(2026, 10, 1, 12, 0, 0)
        ahora = entregada + timedelta(minutes=5, seconds=1)
        self.assertTrue(tiempo.dentro_del_plazo(entregada, ahora))
        self.assertFalse(tiempo.plazo_vencido(entregada, ahora))

    def test_un_milisegundo_despues_el_plazo_esta_vencido(self):
        entregada = datetime(2026, 10, 1, 12, 0, 0)
        ahora = entregada + timedelta(minutes=5, seconds=1, milliseconds=1)
        self.assertFalse(tiempo.dentro_del_plazo(entregada, ahora))
        self.assertTrue(tiempo.plazo_vencido(entregada, ahora))

    def test_dentro_del_plazo_y_vencido_son_complementarios(self):
        entregada = datetime(2026, 10, 1, 12, 0, 0)
        limite = entregada + timedelta(minutes=5, seconds=1)
        for delta in (
            timedelta(0),
            timedelta(minutes=4, seconds=59),
            timedelta(minutes=5),
            timedelta(minutes=5, seconds=1),
            timedelta(minutes=5, seconds=1, milliseconds=1),
            timedelta(minutes=6),
        ):
            with self.subTest(delta=delta):
                ahora = entregada + delta
                self.assertNotEqual(
                    tiempo.dentro_del_plazo(entregada, ahora),
                    tiempo.plazo_vencido(entregada, ahora),
                )

    def test_el_limite_del_plazo_es_entregada_mas_cinco_minutos_mas_un_segundo(self):
        entregada = datetime(2026, 10, 1, 12, 0, 0)
        self.assertEqual(
            tiempo.limite_del_plazo(entregada),
            datetime(2026, 10, 1, 12, 5, 1),
        )

    def test_compara_instantes_con_y_sin_zona_horaria(self):
        # La entrega se guarda en UTC naive y `ahora` puede venir con zona.
        entregada = datetime(2026, 10, 1, 12, 0, 0)
        ahora = datetime(2026, 10, 1, 12, 5, 1, tzinfo=timezone.utc)
        self.assertTrue(tiempo.dentro_del_plazo(entregada, ahora))
        self.assertTrue(
            tiempo.plazo_vencido(entregada, ahora + timedelta(seconds=2))
        )


class TestDescuentoAcotado(unittest.TestCase):
    """RF-15, RF-22: descuento entre 0 y el stock disponible, con faltante."""

    def test_tabla_de_descuentos(self):
        casos = [
            # (medidos, stock, descontados, faltante)
            (50.4, 1000.0, 50.4, 0.0),   # medidos menores que el stock
            (100.0, 100.0, 100.0, 0.0),  # medidos iguales al stock
            (150.0, 100.0, 100.0, 50.0), # medidos mayores que el stock
            (50.0, 0.0, 0.0, 50.0),      # stock en cero
            (0.0, 100.0, 0.0, 0.0),      # medidos en cero
            (-5.0, 100.0, 0.0, 0.0),     # medidos negativos
            (None, 100.0, 0.0, 0.0),     # medidos no disponibles
        ]
        for medidos, stock_disponible, descontados, faltante in casos:
            with self.subTest(medidos=medidos, stock=stock_disponible):
                self.assertEqual(
                    stock.calcular_descuento(medidos, stock_disponible),
                    (descontados, faltante),
                )

    def test_el_stock_resultante_nunca_sale_del_intervalo_permitido(self):
        for medidos in (-10.0, 0.0, 25.0, 100.0, 500.0):
            for stock_disponible in (0.0, 100.0, 5000.0):
                with self.subTest(medidos=medidos, stock=stock_disponible):
                    descontados, faltante = stock.calcular_descuento(
                        medidos, stock_disponible
                    )
                    self.assertGreaterEqual(descontados, 0.0)
                    self.assertGreaterEqual(faltante, 0.0)
                    resultante = stock_disponible - descontados
                    self.assertGreaterEqual(resultante, 0.0)
                    self.assertLessEqual(resultante, stock.CAPACIDAD_MAXIMA_GRAMOS)


class TestPaginacion(unittest.TestCase):
    """RF-32: página y tamaño sin recortes silenciosos, y total de páginas."""

    def test_valores_por_defecto(self):
        self.assertEqual(consulta.normalizar_paginacion(None, None), (1, 50))
        self.assertEqual(consulta.PAGINA_POR_DEFECTO, 1)
        self.assertEqual(consulta.TAMANO_POR_DEFECTO, 50)
        self.assertEqual(consulta.TAMANO_MAXIMO, 100)

    def test_acepta_pagina_y_tamano_como_texto_del_parametro_de_consulta(self):
        self.assertEqual(consulta.normalizar_paginacion("3", "25"), (3, 25))

    def test_rechaza_pagina_menor_que_uno(self):
        for pagina in (0, -1, "-7", "0", "cero", "1.5"):
            with self.subTest(pagina=pagina):
                with self.assertRaises(ErrorDominio) as contexto:
                    consulta.normalizar_paginacion(pagina, 50)
                self.assertEqual(contexto.exception.code, "pagina_invalida")

    def test_acepta_los_limites_del_tamano_y_rechaza_los_de_fuera(self):
        for tamano in (1, 50, 100):
            with self.subTest(tamano=tamano):
                self.assertEqual(consulta.normalizar_paginacion(1, tamano), (1, tamano))

        for tamano in (0, -1, 101, "101", "0", "cien", "50.5"):
            with self.subTest(tamano=tamano):
                with self.assertRaises(ErrorDominio) as contexto:
                    consulta.normalizar_paginacion(1, tamano)
                self.assertEqual(contexto.exception.code, "tamano_pagina_invalido")

    def test_no_recorta_los_valores_validos(self):
        # Una página alta es válida: devolverá una lista vacía, no un 400.
        self.assertEqual(consulta.normalizar_paginacion(500, 100), (500, 100))

    def test_total_de_paginas_para_cada_total_de_items(self):
        casos = {
            0: 1,
            1: 1,
            49: 1,
            50: 1,
            51: 2,
            100: 2,
            101: 3,
            1000: 20,
        }
        for total, esperado in casos.items():
            with self.subTest(total=total):
                self.assertEqual(consulta.total_paginas(total, 50), esperado)

    def test_total_de_paginas_con_cero_resultados_es_una(self):
        self.assertEqual(consulta.total_paginas(0, 50), 1)
        self.assertEqual(consulta.total_paginas(0, 100), 1)

    def test_el_orden_estable_es_por_fecha_descendente_y_por_id_descendente(self):
        self.assertEqual(consulta.orden_estable(), "created_at DESC, id DESC")


class TestValidacionDeConsulta(unittest.TestCase):
    """RF-30, RF-31, RF-32: filtros, precedencia de rechazo y paginación."""

    def test_sin_filtros_devuelve_los_valores_por_defecto(self):
        self.assertEqual(
            consulta.validar_consulta(), (None, None, None, None, 1, 50)
        )

    def test_convierte_los_limites_a_utc_naive(self):
        validada = consulta.validar_consulta(
            desde="2026-10-01T00:00:00-05:00",
            hasta="2026-10-01T23:59:59.999Z",
        )
        self.assertEqual(validada.desde, datetime(2026, 10, 1, 5, 0, 0))
        self.assertEqual(validada.hasta, datetime(2026, 10, 1, 23, 59, 59, 999000))

    def test_z_y_desplazamiento_cero_producen_el_mismo_limite(self):
        con_z = consulta.validar_filtros(desde="2026-10-01T00:00:00Z")
        con_offset = consulta.validar_filtros(desde="2026-10-01T00:00:00+00:00")
        self.assertEqual(con_z, con_offset)

    def test_acepta_filtros_y_paginacion_validos(self):
        validada = consulta.validar_consulta(
            tipo_evento="feeding_dispensed",
            resultado="failure",
            desde="2026-10-01T00:00:00Z",
            hasta="2026-10-02T00:00:00Z",
            pagina=2,
            tamano=10,
        )
        self.assertEqual(validada.tipo_evento, "feeding_dispensed")
        self.assertEqual(validada.resultado, "failure")
        self.assertEqual(validada.pagina, 2)
        self.assertEqual(validada.tamano, 10)

    def test_acepta_un_rango_de_un_solo_instante(self):
        # Ambos extremos son inclusivos, así que desde == hasta es válido.
        validada = consulta.validar_consulta(
            desde="2026-10-01T00:00:00Z", hasta="2026-10-01T00:00:00Z"
        )
        self.assertEqual(validada.desde, validada.hasta)

    def test_rechaza_la_fecha_final_anterior_a_la_inicial(self):
        with self.assertRaises(ErrorDominio) as contexto:
            consulta.validar_consulta(
                desde="2026-10-02T00:00:00Z", hasta="2026-10-01T00:00:00Z"
            )
        self.assertEqual(contexto.exception.code, "rango_fechas_invalido")
        self.assertEqual(
            contexto.exception.message, ERRORES_ESPERADOS["rango_fechas_invalido"]
        )

    def test_rechaza_un_limite_sin_z_ni_desplazamiento(self):
        for desde, hasta in (
            ("2026-10-01T00:00:00", "2026-10-02T00:00:00Z"),
            ("2026-10-01T00:00:00Z", "2026-10-02T00:00:00"),
            ("2026-10-01", "2026-10-02T00:00:00Z"),
        ):
            with self.subTest(desde=desde, hasta=hasta):
                with self.assertRaises(ErrorDominio) as contexto:
                    consulta.validar_filtros(desde=desde, hasta=hasta)
                self.assertEqual(contexto.exception.code, "rango_fechas_invalido")

    def test_rechaza_un_instante_invalido(self):
        for valor in ("no-es-fecha", "", "2026-99-01T00:00:00Z"):
            with self.subTest(valor=repr(valor)):
                with self.assertRaises(ErrorDominio) as contexto:
                    consulta.validar_filtros(desde=valor)
                self.assertEqual(contexto.exception.code, "rango_fechas_invalido")

    def test_rechaza_un_datetime_naive_recibido_programaticamente(self):
        with self.assertRaises(ErrorDominio) as contexto:
            consulta.validar_filtros(desde=datetime(2026, 10, 1, 0, 0, 0))
        self.assertEqual(contexto.exception.code, "rango_fechas_invalido")

    def test_rechaza_un_tipo_fuera_del_catalogo(self):
        for tipo in ("sin_clasificar", "pet", "", "PET_CREATED", 123):
            with self.subTest(tipo=repr(tipo)):
                with self.assertRaises(ErrorDominio) as contexto:
                    consulta.validar_filtros(tipo_evento=tipo)
                self.assertEqual(contexto.exception.code, "tipo_evento_invalido")

    def test_rechaza_un_resultado_fuera_del_catalogo(self):
        for resultado in ("ok", "exito", "", "SUCCESS", 123):
            with self.subTest(resultado=repr(resultado)):
                with self.assertRaises(ErrorDominio) as contexto:
                    consulta.validar_filtros(resultado=resultado)
                self.assertEqual(contexto.exception.code, "resultado_invalido")

    def test_precedencia_de_rechazo(self):
        # Plan §5.3: rango_fechas_invalido → tipo_evento_invalido →
        # resultado_invalido → pagina_invalida → tamano_pagina_invalido.
        casos = [
            (
                "rango_fechas_invalido",
                dict(
                    desde="sin-zona",
                    tipo_evento="inventado",
                    resultado="inventado",
                    pagina=0,
                    tamano=0,
                ),
            ),
            (
                "tipo_evento_invalido",
                dict(
                    desde="2026-10-01T00:00:00Z",
                    tipo_evento="inventado",
                    resultado="inventado",
                    pagina=0,
                    tamano=0,
                ),
            ),
            (
                "resultado_invalido",
                dict(
                    desde="2026-10-01T00:00:00Z",
                    tipo_evento="pet_created",
                    resultado="inventado",
                    pagina=0,
                    tamano=0,
                ),
            ),
            (
                "pagina_invalida",
                dict(
                    desde="2026-10-01T00:00:00Z",
                    tipo_evento="pet_created",
                    resultado="success",
                    pagina=0,
                    tamano=0,
                ),
            ),
            (
                "tamano_pagina_invalido",
                dict(
                    desde="2026-10-01T00:00:00Z",
                    tipo_evento="pet_created",
                    resultado="success",
                    pagina=1,
                    tamano=0,
                ),
            ),
        ]
        for codigo_esperado, argumentos in casos:
            with self.subTest(codigo=codigo_esperado):
                with self.assertRaises(ErrorDominio) as contexto:
                    consulta.validar_consulta(**argumentos)
                self.assertEqual(contexto.exception.code, codigo_esperado)
                self.assertEqual(
                    contexto.exception.message, ERRORES_ESPERADOS[codigo_esperado]
                )

    def test_la_validacion_de_filtros_no_depende_de_la_paginacion(self):
        self.assertEqual(
            consulta.validar_filtros(
                tipo_evento="pet_updated", resultado="success"
            ),
            (None, None),
        )


if __name__ == "__main__":
    unittest.main()
