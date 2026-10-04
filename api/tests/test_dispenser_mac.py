import os
import sys
import unittest
from datetime import date
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("DATABASE_URL", "sqlite:///./test.db")

from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.api.deps import get_current_user
from app.core.confg import settings
from app.db.database import SessionLocal
from app.main import app
from app.models import models
from app.services.mac_service import (
    is_valid_normalized_mac,
    normalize_mac,
    validate_mac_or_raise,
)


# Forma canónica de la dirección: 12 dígitos hexadecimales en mayúsculas y sin separadores.
MAC_CANONICA = "AABBCCDDEEFF"

# Formatos equivalentes de una misma dirección (CL-1, CL-2, CL-3).
# Esta tabla es la que debe replicar lib/utils/mac_normalizer.dart (paridad Python/Dart).
FORMATOS_EQUIVALENTES = [
    "AA:BB:CC:DD:EE:FF",   # dos puntos, mayúsculas
    "aa:bb:cc:dd:ee:ff",   # dos puntos, minúsculas
    "AABBCCDDEEFF",        # sin separadores, mayúsculas
    "aabbccddeeff",        # sin separadores, minúsculas
    "aa-bb-cc-dd-ee-ff",   # guiones
    "aa bb cc dd ee ff",   # espacios
    "aa.bb.cc.dd.ee.ff",   # puntos
    "Aa:bB-cC dD.eE:fF",   # mezcla de separadores y de mayúsculas con minúsculas
]

# Formatos con separadores: no son la forma normalizada, aunque representen una MAC válida.
FORMATOS_CON_SEPARADORES = [
    "AA:BB:CC:DD:EE:FF",
    "aa:bb:cc:dd:ee:ff",
    "aa-bb-cc-dd-ee-ff",
    "aa bb cc dd ee ff",
    "aa.bb.cc.dd.ee.ff",
]

# Valores que no son una dirección MAC válida una vez normalizados (CL-7).
VALORES_INVALIDOS = [
    "AABBCCDDEE",             # 11 dígitos hexadecimales
    "AA:BB:CC:DD:EE",         # 11 dígitos hexadecimales con separadores
    "AABBCCDDEEFFA",          # 13 dígitos hexadecimales
    "AA:BB:CC:DD:EE:FF:00",   # 14 dígitos hexadecimales con separadores
    "GG:BB:CC:DD:EE:FF",      # carácter no hexadecimal en la primera posición
    "aa:bb:cc:gg:ee:ff",      # carácter no hexadecimal en la mitad
    "aa:bb:cc:dd:ee:fg",      # carácter no hexadecimal al final
    "",                       # cadena vacía
    "  :  -  .  ",            # solo separadores: al normalizar queda vacía
    None,                     # dirección ausente
]


class TestNormalizadorMac(unittest.TestCase):
    """Pruebas unitarias de `app.services.mac_service`.

    Cubren RF-02 (comparación por forma normalizada), RF-06 (rechazo del formato
    inválido distinguible del conflicto) y RNF-08 (equivalencia demostrada de
    los formatos de CL-1, CL-2 y CL-3).
    """

    # --- Normalización (RF-02, RF-08 · CL-1, CL-2, CL-3) ---

    def test_formatos_equivalentes_normalizan_a_la_forma_canonica(self):
        for formato in FORMATOS_EQUIVALENTES:
            with self.subTest(formato=formato):
                self.assertEqual(normalize_mac(formato), MAC_CANONICA)

    def test_formatos_equivalentes_producen_una_unica_forma_normalizada(self):
        # RNF-08: todos los formatos equivalentes colapsan en la misma forma,
        # sin falsos positivos ni falsos negativos.
        formas = {normalize_mac(formato) for formato in FORMATOS_EQUIVALENTES}
        self.assertEqual(formas, {MAC_CANONICA})

    def test_normalizacion_es_idempotente(self):
        for formato in FORMATOS_EQUIVALENTES:
            with self.subTest(formato=formato):
                normalizada = normalize_mac(formato)
                self.assertEqual(normalize_mac(normalizada), normalizada)

    # --- Validez de la forma normalizada (RF-06 · CL-7) ---

    def test_forma_normalizada_de_cada_formato_es_valida(self):
        for formato in FORMATOS_EQUIVALENTES:
            with self.subTest(formato=formato):
                self.assertTrue(is_valid_normalized_mac(normalize_mac(formato)))

    def test_rechaza_mac_incompleta_de_once_digitos_hexadecimales(self):
        self.assertFalse(is_valid_normalized_mac("AABBCCDDEE"))
        self.assertFalse(is_valid_normalized_mac(normalize_mac("AA:BB:CC:DD:EE")))

    def test_rechaza_mac_extendida_de_trece_digitos_hexadecimales(self):
        self.assertFalse(is_valid_normalized_mac("AABBCCDDEEFFA"))
        self.assertFalse(is_valid_normalized_mac(normalize_mac("AA:BB:CC:DD:EE:FF:0A")))

    def test_rechaza_caracter_no_hexadecimal_en_cualquier_posicion(self):
        for posicion in range(len(MAC_CANONICA)):
            for caracter in ("G", "g"):
                candidato = MAC_CANONICA[:posicion] + caracter + MAC_CANONICA[posicion + 1:]
                with self.subTest(posicion=posicion, caracter=caracter):
                    self.assertFalse(is_valid_normalized_mac(candidato))

    def test_rechaza_cadena_vacia(self):
        self.assertFalse(is_valid_normalized_mac(""))
        self.assertFalse(is_valid_normalized_mac(normalize_mac("")))

    def test_rechaza_mac_ausente(self):
        # CL-7: una dirección ausente se rechaza como formato inválido, nunca como conflicto.
        self.assertFalse(is_valid_normalized_mac(None))

    def test_rechaza_forma_no_normalizada_porque_exige_la_forma_canonica(self):
        # `is_valid_normalized_mac` no normaliza: exige 12 hexadecimales mayúsculas
        # sin separadores, por eso hay que normalizar antes de validar.
        for formato in FORMATOS_CON_SEPARADORES:
            with self.subTest(formato=formato):
                self.assertFalse(is_valid_normalized_mac(formato))

    # --- Validación con error estructurado (RF-06 · AC-2) ---

    def test_validate_devuelve_la_forma_normalizada_de_cada_formato_valido(self):
        for formato in FORMATOS_EQUIVALENTES:
            with self.subTest(formato=formato):
                self.assertEqual(validate_mac_or_raise(formato), MAC_CANONICA)

    def test_validate_rechaza_formatos_invalidos_con_400_y_codigo_mac_invalid_format(self):
        for valor in VALORES_INVALIDOS:
            with self.subTest(valor=repr(valor)):
                with self.assertRaises(HTTPException) as contexto:
                    validate_mac_or_raise(valor)

                excepcion = contexto.exception
                self.assertEqual(excepcion.status_code, 400)
                self.assertEqual(excepcion.detail["code"], "mac_invalid_format")
                self.assertTrue(excepcion.detail["message"].strip())


# --- Integración de los endpoints de dispensador -------------------------------

# Rutas efectivas registradas por la aplicación. El endpoint que sí llega al
# servicio `check_pending_task` se declaró sin barra inicial, de modo que su ruta
# real es `/dispenserscheck-taks-test/...`; se usa tal cual porque el firmware y
# la app móvil ya apuntan a esa ruta. No se modifica en esta tarea.
RUTA_CHECK_TAKS_TEST = "/dispenserscheck-taks-test/{mac}"

# Direcciones del escenario base de las pruebas de integración.
MAC_REGISTRADA = "AA:BB:CC:DD:EE:FF"
MAC_REGISTRADA_NORMALIZADA = "AABBCCDDEEFF"
MAC_EN_USO = "11:22:33:44:55:66"
MAC_EN_USO_NORMALIZADA = "112233445566"
# Dirección libre en el escenario base. Se escribe con dos puntos porque es un formato
# válido que el validador actual también acepta, de modo que el rechazo observado sea
# el del motivo que se está probando y no un fallo previo de formato.
MAC_DISPONIBLE = "0A:1B:2C:3D:4E:5F"
MAC_DISPONIBLE_NORMALIZADA = "0A1B2C3D4E5F"

# Datos del propietario en conflicto que no pueden aparecer en la respuesta (CL-14).
NOMBRE_MASCOTA = "RayoSecreto"
EMAIL_DUENO = "dueno.secreto@pdam.test"
EMAIL_SEGUNDO_DUENO = "otro.dueno@pdam.test"
# Identificador del dispensador en conflicto, fijado de forma explícita para poder
# comprobar que la respuesta no lo filtra (CL-14) sin depender del autoincremento.
ID_DISPENSADOR_EN_CONFLICTO = 7777

# Formatos equivalentes con los que el hardware puede pedir su tarea pendiente
# (RF-08). Todos son la misma dirección que `MAC_EN_USO`.
FORMATOS_DESDE_HARDWARE = [
    "11:22:33:44:55:66",
    "112233445566",
    "11-22-33-44-55-66",
    "11 22 33 44 55 66",
    "11.22.33.44.55.66",
    "11:22:33:44:55:66".lower(),
    "11-22-33-44-55-66".lower(),
    "11 22 33 44 55 66".lower(),
    "11.22.33.44.55.66".lower(),
    "112233445566".lower(),
]

# Direcciones que no son válidas una vez normalizadas (CL-7). La dirección ausente
# no se incluye aquí: `mac_address` es obligatoria en el esquema, así que FastAPI
# respondería con un 422 de esquema y no con el 400 de formato; ese caso ya está
# cubierto por las pruebas unitarias de `mac_service` de la clase anterior.
FORMATOS_INVALIDOS = [
    "AABBCCDDEE",             # 11 dígitos hexadecimales
    "AABBCCDDEEFFA",          # 13 dígitos hexadecimales
    "AA:BB:CC:DD:EE:FF:00",   # 14 dígitos hexadecimales con separadores
    "GG:BB:CC:DD:EE:FF",      # carácter no hexadecimal
    "aa:bb:cc:gg:ee:ff",      # carácter no hexadecimal en la mitad
    "  :  -  .  ",            # solo separadores
    "",                       # cadena vacía
]


class BaseDispenserApiTests(unittest.TestCase):
    """Base de las pruebas de integración: base de datos aislada y usuario autenticado.

    Cada prueba parte del mismo escenario: un usuario con dos mascotas y un
    dispensador ya registrado en la primera. Los identificadores del dispensador en
    conflicto se siembran directamente en la base de datos porque la API no
    permite fijarlos y CL-14 necesita comprobar que no se filtran.
    """

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        app.dependency_overrides.clear()
        self.sesion = SessionLocal()
        self._preparar_escenario_base()

    def tearDown(self):
        app.dependency_overrides.clear()
        self.sesion.close()
        self._limpiar_base_de_datos()

    # --- Utilidades de escenario ---

    def _limpiar_base_de_datos(self):
        """Deja las tablas del escenario vacías.

        `test.db` es la base exclusiva de las pruebas y no contiene datos reales, así
        que se vacían las tablas que usa esta especificación. El orden respeta las
        claves foráneas, que están activas (`PRAGMA foreign_keys=ON`).
        """
        sesion = SessionLocal()
        try:
            for modelo in (
                models.Dispenser,
                models.Schedule,
                models.ActivityLog,
                models.Pet,
                models.User,
            ):
                sesion.query(modelo).delete()
            sesion.commit()
        finally:
            sesion.close()

    def _preparar_escenario_base(self):
        """Recrea el escenario base: usuario, dos mascotas y un dispensador registrado."""
        self.sesion.rollback()
        self.sesion.expunge_all()
        self._limpiar_base_de_datos()

        self.usuario = self._crear_usuario(EMAIL_DUENO)
        self.mascota_con_dispensador = self._crear_mascota(self.usuario, NOMBRE_MASCOTA)
        self.mascota_libre = self._crear_mascota(self.usuario, "NinaLibre", "gato")
        self.dispensador = self._crear_dispensador(
            mascota=self.mascota_con_dispensador,
            mac_address=MAC_REGISTRADA,
            mac_normalizada=MAC_REGISTRADA_NORMALIZADA,
            id_dispensador=ID_DISPENSADOR_EN_CONFLICTO,
        )
        self._autenticar_como(self.usuario)

    def _crear_usuario(self, email):
        usuario = models.User(email=email, hashed_password="hash-de-prueba", is_active=True)
        self.sesion.add(usuario)
        self.sesion.commit()
        self.sesion.refresh(usuario)
        return usuario

    def _crear_mascota(self, usuario, nombre, especie="perro"):
        mascota = models.Pet(
            name=nombre,
            species=especie,
            birth_date=date(2023, 1, 1),
            weight=5.5,
            reproductive_status=False,
            user_id=usuario.id,
        )
        self.sesion.add(mascota)
        self.sesion.commit()
        self.sesion.refresh(mascota)
        return mascota

    def _crear_dispensador(
        self,
        mascota,
        mac_address,
        mac_normalizada=None,
        id_dispensador=None,
        activo=True,
        pendiente=False,
    ):
        """Inserta un dispensador saltándose la API.

        Permite fijar identificador y forma normalizada para provocar conflictos y
        comprobar después la fila resultante (RF-01, RF-07).
        """
        dispensador = models.Dispenser(
            id=id_dispensador,
            mac_address=mac_address,
            mac_normalized=(
                mac_normalizada if mac_normalizada is not None else normalize_mac(mac_address)
            ),
            pet_id=mascota.id,
            is_active=activo,
            pending_dispensing=pendiente,
        )
        self.sesion.add(dispensador)
        self.sesion.commit()
        self.sesion.refresh(dispensador)
        return dispensador

    def _crear_horario(self, mascota, cantidad=50.0, hora="08:00"):
        horario = models.Schedule(time=hora, amount=cantidad, pet_id=mascota.id)
        self.sesion.add(horario)
        self.sesion.commit()
        self.sesion.refresh(horario)
        return horario

    def _autenticar_como(self, usuario):
        """Inyecta el usuario autenticado en los endpoints protegidos.

        Se inyecta una copia transitoria con el mismo `id`: al reiniciar el escenario
        los objetos de la sesión quedan invalidados y los endpoints solo necesitan
        leer el `id` del usuario propietario.
        """
        usuario_autenticado = models.User(
            id=usuario.id,
            email=usuario.email,
            hashed_password="hash-de-prueba",
            is_active=True,
        )
        app.dependency_overrides[get_current_user] = lambda usuario=usuario_autenticado: usuario

    # --- Utilidades de petición y aserción ---

    def _payload_alta(self, mascota, mac_address):
        return {
            "pet_id": mascota.id,
            "mac_address": mac_address,
            "secret_key_qr": settings.MASTER_HARDWARE_KEY,
        }

    def _alta(self, mascota, mac_address):
        return self.client.post("/dispensers/", json=self._payload_alta(mascota, mac_address))

    def _dispensers_en_base_de_datos(self):
        """Filas de `dispensers` en una sesión nueva, para no leer caché de SQLAlchemy."""
        sesion = SessionLocal()
        try:
            return [
                {
                    "id": dispensador.id,
                    "mac_address": dispensador.mac_address,
                    "mac_normalized": dispensador.mac_normalized,
                    "pet_id": dispensador.pet_id,
                }
                for dispensador in sesion.query(models.Dispenser)
                .order_by(models.Dispenser.id)
                .all()
            ]
        finally:
            sesion.close()

    def _dispensers_con_esta_mac(self, mac_normalizada):
        return [
            fila
            for fila in self._dispensers_en_base_de_datos()
            if fila["mac_normalized"] == mac_normalizada
        ]

    def _assert_error_estructurado(self, response, codigo_http, codigo_detalle, contexto=""):
        """Comprueba el contrato de error de DO-5 y AC-4: `detail` es `{code, message}`.

        `contexto` identifica el caso que falla (formato, valor, intento) para que el
        mensaje sea útil al recorrer una tabla de entradas.
        """
        prefijo = f"{contexto}: " if contexto else ""

        self.assertEqual(
            response.status_code,
            codigo_http,
            f"{prefijo}se esperaba HTTP {codigo_http} con detail.code == '{codigo_detalle}', "
            f"pero se recibió {response.status_code}. Cuerpo: {response.text}",
        )

        cuerpo = response.json()
        self.assertIn("detail", cuerpo, f"La respuesta de error debe traer 'detail'. Cuerpo: {cuerpo}")

        detalle = cuerpo["detail"]
        self.assertIsInstance(
            detalle,
            dict,
            f"{prefijo}AC-4: el detalle debe ser un objeto {{'code', 'message'}} clasificable "
            f"por el cliente, no texto plano. Se recibió: {detalle!r}",
        )
        self.assertEqual(
            detalle.get("code"),
            codigo_detalle,
            f"{prefijo}DO-5: este motivo debe responder con detail.code == '{codigo_detalle}'. "
            f"Se recibió: {detalle!r}",
        )
        self.assertIsInstance(
            detalle.get("message"), str, f"{prefijo}el mensaje debe ser texto: {detalle!r}"
        )
        self.assertTrue(
            detalle["message"].strip(),
            f"{prefijo}el mensaje en español no puede estar vacío: {detalle!r}",
        )
        return detalle

    # --- Peticiones de la tabla de códigos de DO-5 ---

    def _peticion_mac_ya_registrada(self):
        """Alta de la misma dirección con otro formato para otra mascota."""
        return self._alta(self.mascota_libre, "aa-bb-cc-dd-ee-ff")

    def _peticion_mac_en_uso(self):
        """Cambio de la MAC de un dispensador a la de otro ya registrado."""
        self._crear_dispensador(
            mascota=self.mascota_libre,
            mac_address=MAC_EN_USO,
            mac_normalizada=MAC_EN_USO_NORMALIZADA,
        )
        return self.client.put(
            f"/dispensers/{self.dispensador.id}",
            json={
                "pet_id": self.mascota_con_dispensador.id,
                "mac_address": MAC_EN_USO,
            },
        )

    def _peticion_mac_invalida(self):
        """Alta con una dirección que no es una MAC válida."""
        return self._alta(self.mascota_libre, "AABBCCDDEE")

    def _peticion_mascota_con_dispensador(self):
        """Alta de otra dirección para una mascota que ya tiene dispensador."""
        return self._alta(self.mascota_con_dispensador, MAC_DISPONIBLE)


class TestAltaDeDispensadorUnicidadMac(BaseDispenserApiTests):
    """Integración de `POST /dispensers/`: unicidad y formato de la MAC.

    Cubre RF-01, RF-03, RF-06, RF-07, RF-16 y RNF-08 con los casos límite CL-1,
    CL-2, CL-3, CL-6, CL-7, CL-12 y CL-14, y las aclaraciones AC-1, AC-2, AC-3 y AC-4.
    """

    def test_alta_correcta_guarda_el_texto_original_y_la_forma_normalizada(self):
        # DO-2: `mac_address` conserva el texto tal como lo introdujo el usuario y
        # `mac_normalized` guarda la forma canónica usada para comparar (RF-02).
        # La dirección enviada es `MAC_DISPONIBLE` en minúsculas y con guiones: una
        # dirección libre y en un formato que no es el canónico, para que las dos
        # columnas sean comparables.
        response = self._alta(self.mascota_libre, "0a-1b-2c-3d-4e-5f")

        self.assertIn(
            response.status_code,
            (200, 201),
            f"El alta válida debe aceptarse. Cuerpo: {response.text}",
        )
        self.assertEqual(response.json()["mac_address"], "0a-1b-2c-3d-4e-5f")

        filas = self._dispensers_con_esta_mac(MAC_DISPONIBLE_NORMALIZADA)
        self.assertEqual(len(filas), 1, "El alta correcta debe guardar la forma normalizada.")
        self.assertEqual(filas[0]["mac_address"], "0a-1b-2c-3d-4e-5f")
        self.assertEqual(filas[0]["pet_id"], self.mascota_libre.id)

    def test_alta_con_equivalente_en_otro_formato_responde_409(self):
        # CL-1, CL-2, CL-3 y RF-03: cualquier formato equivalente de una MAC ya
        # registrada es un conflicto, no un dispensador nuevo.
        for formato in FORMATOS_EQUIVALENTES:
            response = self._alta(self.mascota_libre, formato)

            self._assert_error_estructurado(
                response,
                409,
                "mac_already_registered",
                contexto=f"alta con el formato equivalente {formato!r}",
            )

            filas = self._dispensers_con_esta_mac(MAC_REGISTRADA_NORMALIZADA)
            self.assertEqual(
                len(filas),
                1,
                f"alta con el formato equivalente {formato!r}: no debe crearse una "
                "segunda fila para la misma dirección normalizada.",
            )
            self.assertEqual(filas[0]["pet_id"], self.mascota_con_dispensador.id)

    def test_alta_con_formato_invalido_responde_400_mac_invalid_format(self):
        # CL-7, RF-06 y AC-2: una dirección mal escrita es un 400 identificable y
        # nunca el mensaje de conflicto.
        for valor in FORMATOS_INVALIDOS:
            response = self._alta(self.mascota_libre, valor)

            self._assert_error_estructurado(
                response,
                400,
                "mac_invalid_format",
                contexto=f"alta con la dirección inválida {valor!r}",
            )
            self.assertEqual(
                len(self._dispensers_en_base_de_datos()),
                1,
                f"alta con la dirección inválida {valor!r}: no debe crear ninguna fila.",
            )

    def test_alta_de_mascota_que_ya_tiene_dispensador_responde_400(self):
        # AC-3: la regla 1-a-1 se mantiene, ahora con su propio código de error.
        response = self._alta(self.mascota_con_dispensador, MAC_DISPONIBLE)

        self._assert_error_estructurado(response, 400, "pet_already_has_dispenser")
        self.assertEqual(
            len(self._dispensers_en_base_de_datos()),
            1,
            "La mascota ya tiene un dispensador: no debe crearse otro.",
        )

    def test_dos_usuarios_con_la_misma_mac_solo_una_queda_persistida(self):
        # CL-6, RF-01 y RF-07: uno registra y el otro recibe el conflicto, con una
        # sola fila para esa dirección en toda la base de datos.
        segundo_usuario = self._crear_usuario(EMAIL_SEGUNDO_DUENO)
        mascota_del_segundo = self._crear_mascota(segundo_usuario, "Pelota", "gato")

        primera_alta = self._alta(self.mascota_libre, MAC_DISPONIBLE)
        self.assertIn(
            primera_alta.status_code,
            (200, 201),
            f"El primer registro debe aceptarse. Cuerpo: {primera_alta.text}",
        )

        self._autenticar_como(segundo_usuario)
        segunda_alta = self._alta(mascota_del_segundo, "0a-1b-2c-3d-4e-5f")
        self._assert_error_estructurado(segunda_alta, 409, "mac_already_registered")

        filas = self._dispensers_con_esta_mac(MAC_DISPONIBLE_NORMALIZADA)
        self.assertEqual(
            len(filas),
            1,
            "Solo uno de los dos usuarios puede quedar vinculado a la misma dirección.",
        )
        self.assertEqual(filas[0]["pet_id"], self.mascota_libre.id)
        self.assertNotIn(
            mascota_del_segundo.id,
            [fila["pet_id"] for fila in self._dispensers_en_base_de_datos()],
            "La mascota del segundo usuario no debe quedar con dispensador.",
        )

    def test_mensaje_de_conflicto_no_revela_datos_del_propietario(self):
        # CL-14 y RF-16: la respuesta de conflicto describe el problema, nunca los
        # datos de la mascota, del usuario ni del dispensador en conflicto.
        response = self._alta(self.mascota_libre, "aa-bb-cc-dd-ee-ff")

        self._assert_error_estructurado(response, 409, "mac_already_registered")

        cuerpo = response.text
        for dato_prohibido in (
            NOMBRE_MASCOTA,
            EMAIL_DUENO,
            str(ID_DISPENSADOR_EN_CONFLICTO),
        ):
            self.assertNotIn(
                dato_prohibido,
                cuerpo,
                f"CL-14: la respuesta de conflicto no puede filtrar el dato '{dato_prohibido}'. "
                f"Cuerpo: {cuerpo}",
            )

    def test_reintento_tras_conflicto_de_alta_responde_el_mismo_codigo(self):
        # CL-12: repetir la misma operación vuelve a dar el conflicto y no deja
        # filas duplicadas ni parciales.
        for intento in (1, 2):
            response = self._alta(self.mascota_libre, "aa-bb-cc-dd-ee-ff")

            self._assert_error_estructurado(
                response,
                409,
                "mac_already_registered",
                contexto=f"intento {intento} tras el conflicto de alta",
            )
            self.assertEqual(
                len(self._dispensers_en_base_de_datos()),
                1,
                f"intento {intento} tras el conflicto de alta: no debe crear filas parciales.",
            )


class TestModificacionDeDispensadorMac(BaseDispenserApiTests):
    """Integración de `PUT /dispensers/{id}`: RF-04, RF-05 y casos CL-4, CL-5 y CL-12."""

    def _sembrar_segundo_dispensador(self):
        return self._crear_dispensador(
            mascota=self.mascota_libre,
            mac_address=MAC_EN_USO,
            mac_normalizada=MAC_EN_USO_NORMALIZADA,
        )

    def test_cambio_a_mac_en_uso_responde_409_mac_in_use_sin_alterar_la_fila(self):
        # CL-5 y RF-04: la dirección nueva está en uso, así que el cambio se rechaza
        # y el dispensador conserva todos sus datos.
        self._sembrar_segundo_dispensador()

        response = self.client.put(
            f"/dispensers/{self.dispensador.id}",
            json={
                "pet_id": self.mascota_con_dispensador.id,
                "mac_address": MAC_EN_USO,
            },
        )

        self._assert_error_estructurado(response, 409, "mac_in_use")

        filas = self._dispensers_en_base_de_datos()
        self.assertEqual(len(filas), 2, "El rechazo no debe crear filas.")
        fila_modificada = next(fila for fila in filas if fila["id"] == self.dispensador.id)
        self.assertEqual(fila_modificada["mac_address"], MAC_REGISTRADA)
        self.assertEqual(fila_modificada["mac_normalized"], MAC_REGISTRADA_NORMALIZADA)
        self.assertEqual(fila_modificada["pet_id"], self.mascota_con_dispensador.id)

    def test_cambio_a_la_misma_mac_con_otro_formato_no_altera_la_fila(self):
        # CL-4 y RF-05: cambiar mayúsculas, guiones o espacios no es cambiar de
        # dirección, así que la operación se acepta sin tocar los datos guardados.
        for formato in ("aa-bb-cc-dd-ee-ff", "AA:BB:CC:DD:EE:FF", "aa bb cc dd ee ff"):
            response = self.client.put(
                f"/dispensers/{self.dispensador.id}",
                json={
                    "pet_id": self.mascota_con_dispensador.id,
                    "mac_address": formato,
                },
            )

            self.assertEqual(
                response.status_code,
                200,
                f"La misma dirección con el formato {formato!r} debe aceptarse. "
                f"Cuerpo: {response.text}",
            )

            fila = next(
                fila
                for fila in self._dispensers_en_base_de_datos()
                if fila["id"] == self.dispensador.id
            )
            self.assertEqual(
                fila["mac_address"],
                MAC_REGISTRADA,
                f"El formato {formato!r} no es un cambio de dirección: el texto guardado no cambia.",
            )
            self.assertEqual(
                fila["mac_normalized"],
                MAC_REGISTRADA_NORMALIZADA,
                f"El formato {formato!r} no es un cambio de dirección: la forma normalizada no cambia.",
            )

    def test_cambio_con_formato_invalido_responde_400_mac_invalid_format(self):
        # RF-06 también aplica a la modificación: una dirección mal escrita no debe
        # llegar a guardarse.
        for valor in ("AABBCCDDEE", "GG:BB:CC:DD:EE:FF"):
            response = self.client.put(
                f"/dispensers/{self.dispensador.id}",
                json={
                    "pet_id": self.mascota_con_dispensador.id,
                    "mac_address": valor,
                },
            )

            self._assert_error_estructurado(
                response,
                400,
                "mac_invalid_format",
                contexto=f"cambio a la dirección inválida {valor!r}",
            )

            fila = next(
                fila
                for fila in self._dispensers_en_base_de_datos()
                if fila["id"] == self.dispensador.id
            )
            self.assertEqual(
                fila["mac_address"],
                MAC_REGISTRADA,
                f"cambio a la dirección inválida {valor!r}: la fila conserva su dirección.",
            )
            self.assertEqual(
                fila["mac_normalized"],
                MAC_REGISTRADA_NORMALIZADA,
                f"cambio a la dirección inválida {valor!r}: la fila conserva su forma normalizada.",
            )

    def test_reintento_tras_conflicto_de_cambio_responde_el_mismo_codigo(self):
        # CL-12: el reintento vuelve a dar `mac_in_use` y no deja filas parciales.
        self._sembrar_segundo_dispensador()

        for intento in (1, 2):
            response = self.client.put(
                f"/dispensers/{self.dispensador.id}",
                json={
                    "pet_id": self.mascota_con_dispensador.id,
                    "mac_address": MAC_EN_USO,
                },
            )

            self._assert_error_estructurado(
                response,
                409,
                "mac_in_use",
                contexto=f"intento {intento} tras el conflicto de cambio de MAC",
            )
            self.assertEqual(
                len(self._dispensers_en_base_de_datos()),
                2,
                f"intento {intento} tras el conflicto de cambio: no debe crear filas parciales.",
            )


class TestConsultaYEliminacionDeDispensadorMac(BaseDispenserApiTests):
    """Integración de la consulta del hardware y del borrado: RF-08 y CL-11."""

    def test_check_taks_test_encuentra_el_dispensador_con_guiones_o_minusculas(self):
        # RF-08: el ESP32 envía la dirección con su propio formato y el servidor debe
        # aplicar la misma forma normalizada que en el alta y la modificación.
        mascota_hardware = self._crear_mascota(self.usuario, "NinaHardware")
        self._crear_dispensador(
            mascota=mascota_hardware,
            mac_address=MAC_EN_USO,
            mac_normalizada=MAC_EN_USO_NORMALIZADA,
            pendiente=True,
        )
        self._crear_horario(mascota_hardware, cantidad=50.0)

        for formato in FORMATOS_DESDE_HARDWARE:
            response = self.client.get(RUTA_CHECK_TAKS_TEST.format(mac=formato))

            self.assertEqual(
                response.status_code,
                200,
                f"El hardware debe encontrar el dispensador con '{formato}'. Cuerpo: {response.text}",
            )
            cuerpo = response.json()
            self.assertTrue(
                cuerpo["serve"],
                f"Con '{formato}' debe haber una tarea pendiente para el dispensador.",
            )
            self.assertEqual(cuerpo["amount"], 50.0, f"Con '{formato}' cambia la cantidad servida.")

    def test_borrar_libera_la_mac_para_otro_usuario(self):
        # CL-11: al eliminar el dispensador, su dirección vuelve a estar disponible.
        borrado = self.client.delete(f"/dispensers/{self.mascota_con_dispensador.id}")
        self.assertIn(
            borrado.status_code,
            (200, 204),
            f"El borrado debe aceptarse. Cuerpo: {borrado.text}",
        )
        self.assertEqual(
            self._dispensers_con_esta_mac(MAC_REGISTRADA_NORMALIZADA),
            [],
            "El dispensador eliminado no debe seguir en la base de datos.",
        )

        segundo_usuario = self._crear_usuario(EMAIL_SEGUNDO_DUENO)
        mascota_del_segundo = self._crear_mascota(segundo_usuario, "Pelota", "gato")
        self._autenticar_como(segundo_usuario)

        alta = self._alta(mascota_del_segundo, "aa:bb:cc:dd:ee:ff")
        self.assertIn(
            alta.status_code,
            (200, 201),
            f"La dirección liberada debe poder registrarse de nuevo. Cuerpo: {alta.text}",
        )

        filas = self._dispensers_con_esta_mac(MAC_REGISTRADA_NORMALIZADA)
        self.assertEqual(len(filas), 1)
        self.assertEqual(filas[0]["pet_id"], mascota_del_segundo.id)


class TestSincronizacionNoRegistraDispensadores(BaseDispenserApiTests):
    """Integración de `POST /sync/`: un huérfano local no puede volverse dispensador.

    Cubre RF-15 y RF-19: el alta de un dispensador solo existe en `POST /dispensers`,
    que exige la clave del QR y devuelve un conflicto accionable. Por eso el canal de
    sincronización omite los ítems `type == 'dispenser'` y nunca los persiste.
    """

    def _lote_con_un_dispensador_huerfano(self):
        return {
            "last_sync_timestamp": 1709990000000.0,
            "items": [
                {
                    "id": "pet-1",
                    "updated_at": 1710000000000.0,
                    "data": {"type": "pet", "name": self.mascota_libre.name},
                },
                {
                    "id": "dispenser-huerfano-1",
                    "updated_at": 1710000000000.0,
                    "data": {
                        "type": "dispenser",
                        "remoteId": None,
                        "isSynced": False,
                        "macAddress": MAC_DISPONIBLE,
                        "petId": self.mascota_libre.id,
                    },
                },
            ],
        }

    def test_sync_omite_los_items_de_dispensador_y_no_crea_filas(self):
        response = self.client.post("/sync/", json=self._lote_con_un_dispensador_huerfano())

        self.assertEqual(
            response.status_code,
            200,
            f"El lote debe aceptarse. Cuerpo: {response.text}",
        )

        ids_sincronizados = [item["id"] for item in response.json()["synced_items"]]
        self.assertNotIn(
            "dispenser-huerfano-1",
            ids_sincronizados,
            "RF-15: el servidor no registra dispensadores por lote, así que el ítem se omite.",
        )
        self.assertIn(
            "pet-1",
            ids_sincronizados,
            "El resto del lote debe seguir sincronizándose con normalidad.",
        )

        self.assertEqual(
            self._dispensers_con_esta_mac(MAC_DISPONIBLE_NORMALIZADA),
            [],
            "Un huérfano enviado por el canal de sincronización no puede crear un dispensador.",
        )
        self.assertEqual(
            len(self._dispensers_en_base_de_datos()),
            1,
            "El lote solo puede contener el dispensador del escenario base.",
        )


class TestContratoDeErroresYCodigosHttp(BaseDispenserApiTests):
    """Integración del contrato de error de DO-5 y de la restricción de base de datos."""

    def test_codigos_http_por_motivo(self):
        # DO-5, AC-1, AC-2 y AC-3: cada motivo de rechazo con su propio código HTTP
        # y su propio `detail.code`, sin depender del texto del mensaje.
        casos = (
            ("mac_already_registered", 409, self._peticion_mac_ya_registrada),
            ("mac_in_use", 409, self._peticion_mac_en_uso),
            ("mac_invalid_format", 400, self._peticion_mac_invalida),
            ("pet_already_has_dispenser", 400, self._peticion_mascota_con_dispensador),
        )

        for codigo_detalle, codigo_http, preparar_peticion in casos:
            # Cada motivo parte del mismo escenario base, con un solo cambio.
            self._preparar_escenario_base()
            response = preparar_peticion()

            self._assert_error_estructurado(
                response,
                codigo_http,
                codigo_detalle,
                contexto=f"motivo de rechazo {codigo_detalle!r} de la tabla de DO-5",
            )

    def test_indice_unico_mac_normalizada_rechaza_insercion_directa(self):
        # RF-07: la unicidad no depende solo de la comprobación previa; una inserción
        # directa que repite la forma normalizada viola el índice único de la tabla.
        sesion = SessionLocal()
        try:
            duplicado = models.Dispenser(
                # Texto distinto del almacenado, para que solo choca la forma normalizada.
                mac_address="aa-bb-cc-dd-ee-ff",
                mac_normalized=MAC_REGISTRADA_NORMALIZADA,
                pet_id=self.mascota_libre.id,
                is_active=True,
                pending_dispensing=False,
            )
            sesion.add(duplicado)

            with self.assertRaises(IntegrityError) as contexto:
                sesion.commit()

            self.assertIn(
                "mac_normalized",
                str(contexto.exception),
                "La restricción violada debe ser la del índice único de la forma normalizada.",
            )
        finally:
            sesion.rollback()
            sesion.close()

        self.assertEqual(
            len(self._dispensers_en_base_de_datos()),
            1,
            "La inserción rechazada no debe dejar filas en la base de datos.",
        )


if __name__ == "__main__":
    unittest.main()