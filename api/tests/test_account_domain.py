"""Pruebas unitarias puras del dominio de la cuenta y del token (spec 015, T2).

Cubren el catálogo de errores de la cuenta carácter a carácter (RNF-01), la
normalización y el formato del correo, los límites de la contraseña nueva de 8
caracteres y 72 bytes (RF-11), la matriz completa de RF-11 con su precedencia,
las etiquetas del perfil (RF-06) y los claims del token con su revocación
(RF-10, RF-19).

Son funciones puras: no se abre base de datos, no se firma ningún token, no se
lee configuración y el instante se pasa como parámetro (RNF-04, RNF-06). El
último grupo comprueba en un intérprete limpio que importar `app.domain.cuenta`
y `app.domain.token` no arrastra FastAPI, SQLAlchemy ni `jose`.
"""

import os
import subprocess
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

# No se define ninguna variable de entorno a propósito: el dominio no las lee.
from app.domain import cuenta, token

RUTA_CUENTA = ROOT_DIR / "app" / "domain" / "cuenta.py"
RUTA_TOKEN = ROOT_DIR / "app" / "domain" / "token.py"

# Tabla «Catálogo de errores de la API» de la spec 015, transcrita a mano para
# compararla carácter a carácter. `invalid_credentials` es el único mensaje sin
# punto final.
ERRORES_ESPERADOS = {
    "invalid_email": "Introduce un correo electrónico válido.",
    "weak_password": "La contraseña debe tener al menos 8 caracteres.",
    "password_too_long": "La contraseña es demasiado larga.",
    "empty_update": (
        "No has modificado ningún dato. Escribe un correo nuevo o una "
        "contraseña nueva."
    ),
    "email_already_registered": "El correo electrónico ya está registrado.",
    "invalid_password": "La contraseña no es correcta.",
    "invalid_credentials": "Correo o contraseña incorrectos",
    "unauthorized": "La sesión no es válida. Vuelve a iniciar sesión.",
    "conflict": "No se pudo completar la operación. Inténtalo de nuevo.",
    "server_error": "No se pudo completar la operación. Inténtalo de nuevo.",
}

CORREO_ACTUAL = "user@x.com"

# Instante fijo de las pruebas de token: el dominio nunca lee el reloj.
AHORA = datetime(2026, 10, 29, 12, 0, 0, tzinfo=timezone.utc)


class TestCatalogoDeErroresCuenta(unittest.TestCase):
    """RNF-01, RF-11, RF-12, RF-17, RF-19, RF-21: catálogo literal."""

    def test_contiene_exactamente_los_diez_codigos_del_catalogo(self):
        self.assertEqual(set(cuenta.ERRORES_CUENTA), set(ERRORES_ESPERADOS))
        self.assertEqual(len(cuenta.ERRORES_CUENTA), 10)

    def test_cada_mensaje_coincide_caracter_a_caracter_con_la_spec(self):
        for codigo, esperado in ERRORES_ESPERADOS.items():
            with self.subTest(codigo=codigo):
                obtenido = cuenta.ERRORES_CUENTA[codigo]
                self.assertEqual(
                    len(obtenido),
                    len(esperado),
                    f"{codigo}: longitud distinta del catálogo",
                )
                for posicion, (caracter, caracter_esperado) in enumerate(
                    zip(obtenido, esperado)
                ):
                    self.assertEqual(
                        caracter,
                        caracter_esperado,
                        f"{codigo}: discrepancia en el carácter {posicion}",
                    )

    def test_el_mensaje_de_credenciales_invalidas_no_lleva_punto_final(self):
        self.assertFalse(cuenta.ERRORES_CUENTA["invalid_credentials"].endswith("."))
        for codigo, mensaje in ERRORES_ESPERADOS.items():
            if codigo == "invalid_credentials":
                continue
            with self.subTest(codigo=codigo):
                self.assertTrue(mensaje.endswith("."))

    def test_ningun_mensaje_esta_vacio_ni_lleva_emoji(self):
        for codigo, mensaje in ERRORES_ESPERADOS.items():
            with self.subTest(codigo=codigo):
                self.assertTrue(mensaje.strip())
                self.assertFalse(
                    any(orden >= 0x1F300 for orden in map(ord, mensaje)),
                    f"{codigo}: el mensaje no debe contener emojis (RNF-01).",
                )


class TestNormalizacionDeCorreo(unittest.TestCase):
    """RF-11, RF-12, RF-19: recorte exterior y minúsculas, sin tocar el interior."""

    def test_recorta_los_espacios_exteriores_y_pasa_a_minusculas(self):
        casos = {
            "User@X.com": "user@x.com",
            "  user@x.com  ": "user@x.com",
            "\t USER@X.COM \n": "user@x.com",
            "usuario@dominio.com.co": "usuario@dominio.com.co",
        }
        for entrada, esperado in casos.items():
            with self.subTest(entrada=entrada):
                self.assertEqual(cuenta.normalizar_correo(entrada), esperado)

    def test_no_toca_los_espacios_interiores(self):
        self.assertEqual(cuenta.normalizar_correo(" user @ x.com "), "user @ x.com")

    def test_una_cadena_vacia_o_ausente_se_normaliza_a_cadena_vacia(self):
        for valor in ("", "   ", None, 123, [], b"user@x.com"):
            with self.subTest(valor=repr(valor)):
                self.assertEqual(cuenta.normalizar_correo(valor), "")

    def test_conserva_las_letras_unicode(self):
        self.assertEqual(cuenta.normalizar_correo("  ÑANDÚ@Correo.COM "), "ñandú@correo.com")

    def test_es_idempotente(self):
        for entrada in ("User@X.com", " user@x.com ", ""):
            with self.subTest(entrada=entrada):
                una_vez = cuenta.normalizar_correo(entrada)
                self.assertEqual(cuenta.normalizar_correo(una_vez), una_vez)


class TestFormatoDeCorreo(unittest.TestCase):
    """RF-11: una sola `@`, parte local no vacía, dominio con punto, sin espacios."""

    def test_acepta_correos_validos(self):
        for correo in (
            "user@x.com",
            "user@x.com",
            "nombre.apellido@sub.dominio.com",
            "user+etiqueta@x.co",
            "u@x.io",
            "  User@X.com  ",
        ):
            with self.subTest(correo=correo):
                self.assertTrue(cuenta.es_correo_valido(correo))

    def test_rechaza_correos_sin_arroba_o_con_mas_de_una(self):
        for correo in (
            "userx.com",
            "user@@x.com",
            "user@x@com",
            "@x.com",
            "user@",
        ):
            with self.subTest(correo=correo):
                self.assertFalse(cuenta.es_correo_valido(correo))

    def test_rechaza_un_dominio_sin_punto(self):
        for correo in ("user@x", "user@localhost", "user@x."):
            with self.subTest(correo=correo):
                self.assertFalse(cuenta.es_correo_valido(correo))

    def test_rechaza_un_dominio_que_empieza_por_punto(self):
        for correo in ("user@.com", "user@.x.com"):
            with self.subTest(correo=correo):
                self.assertFalse(cuenta.es_correo_valido(correo))

    def test_rechaza_cualquier_espacio_interior(self):
        for correo in (
            "user @x.com",
            "user@ x.com",
            "user@x .com",
            "us er@x.com",
            "user@x.co m",
            "user\t@x.com",
        ):
            with self.subTest(correo=correo):
                self.assertFalse(cuenta.es_correo_valido(correo))

    def test_rechaza_la_cadena_vacia_y_los_valores_que_no_son_texto(self):
        for valor in ("", "   ", None, 123, [], True):
            with self.subTest(valor=repr(valor)):
                self.assertFalse(cuenta.es_correo_valido(valor))


class TestLongitudEnBytes(unittest.TestCase):
    """RF-11, RNF-06: el límite de la contraseña se mide en bytes UTF-8."""

    def test_cuenta_los_bytes_utf8_no_los_caracteres(self):
        casos = {
            "": 0,
            "abc": 3,
            "ñ": 2,
            "contraseña": 11,
            "🐾": 4,
        }
        for texto, esperado in casos.items():
            with self.subTest(texto=texto):
                self.assertEqual(cuenta.longitud_en_bytes(texto), esperado)

    def test_un_valor_que_no_es_texto_mide_cero(self):
        for valor in (None, 123, []):
            with self.subTest(valor=repr(valor)):
                self.assertEqual(cuenta.longitud_en_bytes(valor), 0)


class TestValidacionDePasswordNueva(unittest.TestCase):
    """RF-11: mínimo de 8 caracteres y máximo de 72 bytes, en ese orden."""

    def test_el_minimo_se_cuenta_en_caracteres(self):
        casos = {
            "a" * 7: "weak_password",
            "a" * 8: None,
            "a" * 9: None,
            "ñ" * 7: "weak_password",
            "ñ" * 8: None,
        }
        for password, esperado in casos.items():
            with self.subTest(password=password):
                self.assertEqual(cuenta.validar_password_nueva(password), esperado)

    def test_el_maximo_se_cuenta_en_bytes_utf8(self):
        casos = {
            "a" * 72: None,
            "a" * 73: "password_too_long",
            # 36 caracteres de dos bytes son exactamente 72 bytes: válida.
            "ñ" * 36: None,
            # 37 caracteres de dos bytes son 74 bytes: se rechaza.
            "ñ" * 37: "password_too_long",
            # 71 caracteres ASCII más uno de dos bytes son 73 bytes exactos.
            "a" * 71 + "ñ": "password_too_long",
        }
        for password, esperado in casos.items():
            with self.subTest(bytes=cuenta.longitud_en_bytes(password)):
                self.assertEqual(cuenta.validar_password_nueva(password), esperado)

    def test_una_password_vacia_o_ausente_es_debiles(self):
        for valor in ("", None, 123):
            with self.subTest(valor=repr(valor)):
                self.assertEqual(cuenta.validar_password_nueva(valor), "weak_password")

    def test_el_error_devuelto_pertenece_al_catalogo(self):
        for valor in ("", "a" * 7, "a" * 73):
            with self.subTest(valor=valor):
                self.assertIn(
                    cuenta.validar_password_nueva(valor), cuenta.ERRORES_CUENTA
                )


class TestMatrizRF11(unittest.TestCase):
    """RF-11: una prueba por fila de la matriz del formulario de perfil.

    La confirmación de la contraseña no viaja al servidor: las filas cuya
    validación es solo del cliente llegan al dominio ya descartadas y aquí se
    comprueba qué haría el servidor si se le enviaran. La fila del correo ya
    registrado depende de la base de datos y no del dominio (RF-12): se comprueba
    que el dominio no la simula y deja el correo listo para el servicio.
    """

    def test_cada_fila_de_la_matriz_tiene_su_resultado(self):
        filas = [
            # (fila de la spec, correo nuevo, password nueva, error, correo, pass)
            (1, "", "", "invalid_email", False, False),
            (2, "user@x", "", "invalid_email", False, False),
            (3, CORREO_ACTUAL, "", "empty_update", False, False),
            (4, CORREO_ACTUAL, "unaClave1", None, False, True),
            (5, CORREO_ACTUAL, "", "empty_update", False, False),
            (6, CORREO_ACTUAL, "unaClave1", None, False, True),
            (7, CORREO_ACTUAL, "corta12", "weak_password", False, False),
            (8, CORREO_ACTUAL, "a" * 73, "password_too_long", False, False),
            (9, CORREO_ACTUAL, "unaClaveLarga", None, False, True),
            (10, "nuevo@x.com", "", None, True, False),
            (11, "nuevo@x.com", "unaClaveLarga", None, True, True),
            (12, "nuevo@x.com", "", None, True, False),
            (13, "nuevo@x.com", "unaClaveLarga", None, True, True),
            # Fila 14: la unicidad del correo la resuelve el servicio (RF-12).
            (14, "ocupado@x.com", "unaClaveLarga", None, True, True),
        ]

        for fila, correo_nuevo, password, error, cambia_correo, cambia_pass in filas:
            with self.subTest(fila=fila):
                plan = cuenta.resolver_actualizacion(
                    CORREO_ACTUAL, correo_nuevo, password
                )
                self.assertEqual(plan.error, error)
                self.assertEqual(plan.cambia_correo, cambia_correo)
                self.assertEqual(plan.cambia_password, cambia_pass)
                self.assertEqual(plan.valido, error is None)

    def test_un_correo_que_solo_cambia_de_caja_o_de_espacios_cuenta_como_igual(self):
        for correo_nuevo in ("USER@X.COM", "  User@X.com  ", "user@x.com"):
            with self.subTest(correo_nuevo=correo_nuevo):
                plan = cuenta.resolver_actualizacion(CORREO_ACTUAL, correo_nuevo, "")
                self.assertEqual(plan.error, "empty_update")
                self.assertFalse(plan.cambia_correo)

    def test_el_correo_resultante_siempre_es_el_normalizado(self):
        plan = cuenta.resolver_actualizacion(CORREO_ACTUAL, "  Nuevo@X.COM ", "")
        self.assertEqual(plan.correo_nuevo, "nuevo@x.com")
        self.assertTrue(plan.cambia_correo)

    def test_el_correo_actual_tambien_se_compara_normalizado(self):
        plan = cuenta.resolver_actualizacion("  User@X.com ", "user@x.com", "")
        self.assertEqual(plan.error, "empty_update")

    def test_sin_cambios_y_sin_password_es_empty_update(self):
        plan = cuenta.resolver_actualizacion(CORREO_ACTUAL, CORREO_ACTUAL, None)
        self.assertEqual(plan.error, "empty_update")
        self.assertFalse(plan.cambia_correo)
        self.assertFalse(plan.cambia_password)

    def test_un_error_nunca_declara_cambios_aplicables(self):
        for correo_nuevo, password in (
            ("", ""),
            ("sin-arroba", "unaClaveLarga"),
            (CORREO_ACTUAL, ""),
            (CORREO_ACTUAL, "corta12"),
            (CORREO_ACTUAL, "a" * 73),
        ):
            with self.subTest(correo=correo_nuevo, password=password[:10]):
                plan = cuenta.resolver_actualizacion(
                    CORREO_ACTUAL, correo_nuevo, password
                )
                self.assertIsNotNone(plan.error)
                self.assertFalse(plan.cambia_correo)
                self.assertFalse(plan.cambia_password)

    def test_la_precedencia_es_correo_antes_que_cualquier_otra_regla(self):
        casos = [
            ("", ""),
            ("", "corta12"),
            ("", "a" * 73),
            ("sin-arroba", "corta12"),
        ]
        for correo_nuevo, password in casos:
            with self.subTest(correo=correo_nuevo, password=password[:10]):
                plan = cuenta.resolver_actualizacion(
                    CORREO_ACTUAL, correo_nuevo, password
                )
                self.assertEqual(plan.error, "invalid_email")

    def test_empty_update_va_antes_que_la_longitud_de_la_password(self):
        # Sin contraseña nueva no hay nada que medir: el envío vacío manda.
        plan = cuenta.resolver_actualizacion(CORREO_ACTUAL, CORREO_ACTUAL, "")
        self.assertEqual(plan.error, "empty_update")

        # Con contraseña nueva, la longitud se valida aunque el correo sea igual.
        plan = cuenta.resolver_actualizacion(CORREO_ACTUAL, CORREO_ACTUAL, "a" * 7)
        self.assertEqual(plan.error, "weak_password")

    def test_weak_password_va_antes_que_password_too_long(self):
        # Una contraseña corta nunca llega al límite de bytes, pero se comprueba
        # que cada regla se aplica en su orden y sin solaparse.
        self.assertEqual(
            cuenta.resolver_actualizacion(CORREO_ACTUAL, CORREO_ACTUAL, "ñ" * 7).error,
            "weak_password",
        )
        self.assertEqual(
            cuenta.resolver_actualizacion(CORREO_ACTUAL, CORREO_ACTUAL, "ñ" * 37).error,
            "password_too_long",
        )

    def test_el_correo_invalido_manda_sobre_la_password_demasiado_larga(self):
        plan = cuenta.resolver_actualizacion(CORREO_ACTUAL, "sin-arroba", "a" * 73)
        self.assertEqual(plan.error, "invalid_email")

    def test_el_plan_es_inmutable(self):
        plan = cuenta.resolver_actualizacion(CORREO_ACTUAL, "nuevo@x.com", "")
        with self.assertRaises(Exception):
            plan.error = "conflict"


class TestEtiquetasDelPerfil(unittest.TestCase):
    """RF-06: «Activa» / «Inactiva» y la inicial del avatar."""

    def test_etiqueta_estado_sigue_el_catalogo(self):
        self.assertEqual(cuenta.etiqueta_estado(True), "Activa")
        self.assertEqual(cuenta.etiqueta_estado(False), "Inactiva")

    def test_la_inicial_es_la_primera_letra_en_mayusculas_del_correo_normalizado(self):
        casos = {
            "user@x.com": "U",
            "  User@X.com  ": "U",
            "ñandú@correo.com": "Ñ",
            "1usuario@x.com": "1",
        }
        for correo, esperado in casos.items():
            with self.subTest(correo=correo):
                self.assertEqual(cuenta.inicial_de_correo(correo), esperado)

    def test_sin_correo_devuelve_cadena_vacia_sin_lanzar_excepcion(self):
        # Decisión de T2: no se inventa un valor por defecto (RF-07 prohíbe los
        # datos de relleno); el avatar queda vacío y lo resuelve la vista.
        for valor in ("", "   ", None, 123):
            with self.subTest(valor=repr(valor)):
                self.assertEqual(cuenta.inicial_de_correo(valor), "")


class TestJtiYClaims(unittest.TestCase):
    """RF-10, RF-19: identificador irrepetible y claims con el instante inyectado."""

    def test_nuevo_jti_es_un_hexadecimal_de_32_caracteres(self):
        jti = token.nuevo_jti()
        self.assertIsInstance(jti, str)
        self.assertEqual(len(jti), 32)
        self.assertTrue(all(caracter in "0123456789abcdef" for caracter in jti))

    def test_nuevo_jti_no_se_repite(self):
        generados = {token.nuevo_jti() for _ in range(1000)}
        self.assertEqual(len(generados), 1000)

    def test_construir_claims_devuelve_sub_jti_iat_y_exp(self):
        claims = token.construir_claims("public-id", "jti-1", AHORA, 30)
        self.assertEqual(set(claims), {"sub", "jti", "iat", "exp"})
        self.assertEqual(claims["sub"], "public-id")
        self.assertEqual(claims["jti"], "jti-1")

    def test_iat_y_exp_salen_del_instante_recibido(self):
        emision = int(AHORA.timestamp())
        claims = token.construir_claims("public-id", "jti-1", AHORA, 30)
        self.assertEqual(claims["iat"], emision)
        self.assertEqual(claims["exp"], emision + 30 * 60)

    def test_un_instante_sin_zona_se_interpreta_como_utc(self):
        con_zona = token.construir_claims("public-id", "jti-1", AHORA, 30)
        sin_zona = token.construir_claims(
            "public-id", "jti-1", datetime(2026, 10, 29, 12, 0, 0), 30
        )
        self.assertEqual(sin_zona, con_zona)

    def test_un_instante_con_desplazamiento_se_convierte_a_utc(self):
        con_zona = token.construir_claims("public-id", "jti-1", AHORA, 30)
        desplazado = token.construir_claims(
            "public-id",
            "jti-1",
            datetime(2026, 10, 29, 7, 0, 0, tzinfo=timezone(timedelta(hours=-5))),
            30,
        )
        self.assertEqual(desplazado, con_zona)

    def test_no_lee_el_reloj(self):
        primera = token.construir_claims("public-id", "jti-1", AHORA, 30)
        segunda = token.construir_claims("public-id", "jti-1", AHORA, 30)
        self.assertEqual(primera, segunda)

    def test_los_minutos_se_inyectan_y_la_constante_es_el_valor_por_defecto(self):
        self.assertIsInstance(token.MINUTOS_TOKEN, int)
        self.assertGreater(token.MINUTOS_TOKEN, 0)
        self.assertEqual(
            token.construir_claims("public-id", "jti-1", AHORA),
            token.construir_claims("public-id", "jti-1", AHORA, token.MINUTOS_TOKEN),
        )


class TestClaimsUtilizables(unittest.TestCase):
    """RF-05, RF-19: la firma ya se verificó fuera; aquí solo sub, jti y exp."""

    def _payload(self, **cambios):
        payload = token.construir_claims("public-id", "jti-1", AHORA, 30)
        payload.update(cambios)
        return payload

    def test_un_token_vigente_sin_revocar_es_utilizable(self):
        self.assertTrue(token.claims_utilizables(self._payload(), AHORA, set()))
        self.assertTrue(token.claims_utilizables(self._payload(), AHORA, None))
        self.assertTrue(token.claims_utilizables(self._payload(), AHORA, []))

    def test_un_token_caducado_no_es_utilizable(self):
        payload = self._payload()
        self.assertFalse(
            token.claims_utilizables(payload, AHORA + timedelta(minutes=31), set())
        )
        # El instante exacto de `exp` ya no es válido.
        self.assertFalse(
            token.claims_utilizables(payload, AHORA + timedelta(minutes=30), set())
        )
        # Un segundo antes sigue valiendo.
        self.assertTrue(
            token.claims_utilizables(
                payload, AHORA + timedelta(minutes=30) - timedelta(seconds=1), set()
            )
        )

    def test_un_token_revocado_no_es_utilizable(self):
        self.assertFalse(
            token.claims_utilizables(self._payload(), AHORA, {"jti-1"})
        )
        self.assertFalse(
            token.claims_utilizables(self._payload(), AHORA, ["jti-1", "jti-2"])
        )
        # Otro jti revocado no afecta a este token.
        self.assertTrue(token.claims_utilizables(self._payload(), AHORA, {"jti-2"}))

    def test_un_str_no_se_interpreta_como_coleccion_de_revocados(self):
        # Un `str` es iterable y `frozenset("abc")` lo trocearía en caracteres.
        # Ante una colección con forma inválida se falla cerrado: el token no se
        # da por utilizable en lugar de aceptarlo por comparar solo caracteres.
        self.assertFalse(token.claims_utilizables(self._payload(), AHORA, "jti-1"))
        self.assertFalse(
            token.claims_utilizables(self._payload(jti="otro"), AHORA, "abc")
        )
        # La colección correcta sigue funcionando igual.
        self.assertFalse(token.claims_utilizables(self._payload(), AHORA, {"jti-1"}))

    def test_sin_sub_no_es_utilizable(self):
        for sub in (None, "", "   ", 123, ["public-id"]):
            with self.subTest(sub=repr(sub)):
                self.assertFalse(
                    token.claims_utilizables(self._payload(sub=sub), AHORA, set())
                )
        payload = self._payload()
        del payload["sub"]
        self.assertFalse(token.claims_utilizables(payload, AHORA, set()))

    def test_sin_jti_no_es_utilizable(self):
        for jti in (None, "", "   ", 123):
            with self.subTest(jti=repr(jti)):
                self.assertFalse(
                    token.claims_utilizables(self._payload(jti=jti), AHORA, set())
                )
        payload = self._payload()
        del payload["jti"]
        self.assertFalse(token.claims_utilizables(payload, AHORA, set()))

    def test_sin_exp_o_con_un_exp_invalido_no_es_utilizable(self):
        for exp in (None, "", "2026-10-29T12:30:00Z", True, [], {}):
            with self.subTest(exp=repr(exp)):
                self.assertFalse(
                    token.claims_utilizables(self._payload(exp=exp), AHORA, set())
                )
        payload = self._payload()
        del payload["exp"]
        self.assertFalse(token.claims_utilizables(payload, AHORA, set()))

    def test_un_payload_que_no_es_un_diccionario_no_es_utilizable(self):
        for payload in (None, "texto", [], 123):
            with self.subTest(payload=repr(payload)):
                self.assertFalse(token.claims_utilizables(payload, AHORA, set()))


class TestRevocacionPorCambioDeCorreo(unittest.TestCase):
    """RF-10: solo se revoca el token anterior si el correo cambia."""

    def test_no_revoca_si_el_correo_es_el_mismo(self):
        self.assertFalse(token.debe_revocar_token_anterior(CORREO_ACTUAL, CORREO_ACTUAL))

    def test_no_revoca_si_solo_cambian_la_caja_o_los_espacios_exteriores(self):
        for correo_nuevo in ("USER@X.COM", "  User@X.com  "):
            with self.subTest(correo_nuevo=correo_nuevo):
                self.assertFalse(
                    token.debe_revocar_token_anterior(CORREO_ACTUAL, correo_nuevo)
                )

    def test_revoca_si_el_correo_cambia(self):
        self.assertTrue(
            token.debe_revocar_token_anterior(CORREO_ACTUAL, "nuevo@x.com")
        )
        self.assertTrue(
            token.debe_revocar_token_anterior(" User@X.com ", " nuevo@x.com ")
        )

    def test_un_correo_nuevo_vacio_no_es_un_cambio_aplicable(self):
        for correo_nuevo in ("", "   ", None):
            with self.subTest(correo_nuevo=repr(correo_nuevo)):
                self.assertFalse(
                    token.debe_revocar_token_anterior(CORREO_ACTUAL, correo_nuevo)
                )


class TestPurezaDelDominio(unittest.TestCase):
    """RNF-04, RNF-06: dominio sin framework, sin red, sin configuración."""

    PROHIBIDOS = ("fastapi", "starlette", "sqlalchemy", "jose", "requests", "httpx")

    def test_los_modulos_no_leen_configuracion_ni_secretos(self):
        for ruta in (RUTA_CUENTA, RUTA_TOKEN):
            with self.subTest(modulo=ruta.name):
                fuente = ruta.read_text(encoding="utf-8")
                for prohibido in (
                    "settings",
                    "SECRET_KEY",
                    "os.environ",
                    "getenv",
                    "load_dotenv",
                ):
                    self.assertNotIn(prohibido, fuente)

    def test_importar_el_dominio_no_arrastra_framework_red_ni_entorno(self):
        # Intérprete limpio y sin variables de entorno: si el módulo leyera la
        # configuración, la importación fallaría.
        codigo = (
            "import sys\n"
            "import app.domain.cuenta\n"
            "import app.domain.token\n"
            f"prohibidos = {self.PROHIBIDOS!r}\n"
            "arrastrados = [nombre for nombre in prohibidos if nombre in sys.modules]\n"
            "print(','.join(arrastrados))\n"
        )
        resultado = subprocess.run(
            [sys.executable, "-c", codigo],
            cwd=str(ROOT_DIR),
            env={"PATH": os.environ.get("PATH", "")},
            capture_output=True,
            text=True,
        )

        self.assertEqual(resultado.returncode, 0, resultado.stderr)
        self.assertEqual(resultado.stdout.strip(), "")
        self.assertEqual(resultado.stderr.strip(), "")

    def test_el_dominio_no_importa_la_capa_de_servicios_ni_de_modelos(self):
        for ruta in (RUTA_CUENTA, RUTA_TOKEN):
            with self.subTest(modulo=ruta.name):
                fuente = ruta.read_text(encoding="utf-8")
                for prohibido in ("app.models", "app.services", "app.api", "app.db"):
                    self.assertNotIn(prohibido, fuente)


if __name__ == "__main__":
    unittest.main()
