from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

from app.core.confg import settings
from app.services.mac_service import normalize_mac

# El archivo se creará en la raíz del proyecto
# Se usar SQLite para el desarrollo al momento de subir a 
# produccion si es necesario cambiar de gestor sera muy facil
SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    # `timeout` es el busy_timeout de SQLite en segundos: cuando una conexión
    # encuentra la base bloqueada por otra escritura, espera en lugar de fallar
    # con `database is locked`. Se refuerza con el PRAGMA del listener `connect`.
    connect_args={"check_same_thread": False, "timeout": 30},
)

# Nombre del índice único que garantiza la unicidad de la MAC (RF-01, RF-07).
INDICE_UNICO_MAC_NORMALIZADA = "ux_dispensers_mac_normalized"

# Índice único parcial que impide dos órdenes pendientes para el mismo
# dispensador (RNF-3). SQLite no bloquea filas, así que la base es la última red
# ante dos entregas simultáneas. Es parcial (`WHERE status = 'pending'`) para que
# las órdenes cerradas no cuenten.
INDICE_UNICO_ORDEN_PENDIENTE = "ux_dispensing_orders_pending_dispenser"

# Bases ya migradas en este proceso. La migración se ejecuta una sola vez por
# archivo y proceso: el listener `connect` corre en cada conexión nueva y repetir
# DDL con varias conexiones simultáneas puede provocar `database is locked`.
BASES_MIGRADAS: set[str] = set()


def olvidar_migraciones(ruta: str | None = None) -> None:
    """Olvida las migraciones hechas para simular un arranque nuevo.

    Lo usan las pruebas que alteran el esquema por fuera de SQLAlchemy (por
    ejemplo, borrando un índice) y necesitan que la siguiente conexión vuelva a
    comprobarlo, como haría un proceso nuevo.
    """
    if ruta is None:
        BASES_MIGRADAS.clear()
    else:
        BASES_MIGRADAS.discard(ruta)


def _ruta_de_la_conexion(cursor) -> str:
    """Ruta del archivo de la base de la conexión; vacía si es en memoria."""
    fila = cursor.execute("PRAGMA database_list").fetchone()
    return fila[2] if fila and fila[2] else ""

# El esquema final de `logs` está definido en `app/models/models.py` (plan §6.1).
# La migración reconstruye la tabla cuando le falta cualquiera de estas columnas,
# cuando sobrevive alguna de la implementación parcial descartada o cuando
# `pet_id` conserva la FK anulable del esquema legado.
COLUMNAS_LOGS = (
    "id",
    "user_id",
    "pet_id",
    "pet_name",
    "dispenser_id",
    "dispenser_mac_masked",
    "event_type",
    "outcome",
    "cause",
    "description",
    "context",
    "order_id",
    "requested_grams",
    "measured_grams",
    "discounted_grams",
    "resulting_stock",
    "retry_count",
    "created_at",
)

COLUMNAS_PARCIALES_DESCARTADAS = (
    "resultado",
    "stock_solicitado",
    "stock_medido",
    "stock_resultante",
    "descripcion_contexto",
    "dispensador_mac_parcial",
    "reintentos",
)

# Índices del esquema final, con los mismos nombres que genera SQLAlchemy para
# no dejar diferencias entre una base creada desde cero y una migrada. El
# segundo elemento es la lista de columnas: el índice compuesto sostiene la
# consulta por usuario y orden (RF-26, RNF-2).
INDICES_LOGS = (
    ("ix_logs_id", "id"),
    ("ix_logs_pet_id", "pet_id"),
    ("ix_logs_dispenser_id", "dispenser_id"),
    ("ix_logs_event_type", "event_type"),
    ("ix_logs_outcome", "outcome"),
    ("ix_logs_order_id", "order_id"),
    ("ix_logs_created_at", "created_at"),
    ("ix_logs_user_id_created_at", "user_id, created_at"),
)

# Texto con el que un registro sin descripción recuperable queda como «Sin
# clasificar» (RF-41).
DESCRIPCION_HISTORICA = "Registro histórico"


def _verificar_mac_normalizada_sin_colisiones(cursor) -> None:
    """Aborta si dos filas equivalen a la misma MAC una vez normalizada.

    Se prefiere un fallo explícito al borrar datos: la migración nunca destruye
    información para resolver un conflicto.
    """
    por_valor = {}
    for id_dispenser, mac_normalizada in cursor.execute(
        "SELECT id, mac_normalized FROM dispensers WHERE mac_normalized IS NOT NULL"
    ):
        por_valor.setdefault(mac_normalizada, []).append(id_dispenser)

    colisiones = {valor: ids for valor, ids in por_valor.items() if len(ids) > 1}
    if colisiones:
        raise RuntimeError(
            "No se puede aplicar la unicidad de 'dispensers.mac_normalized' porque "
            "estas direcciones MAC son equivalentes tras normalizar "
            f"{colisiones}. Corrige o elimina los registros en conflicto de forma "
            "manual; la migración no ha borrado ningún dato."
        )


def _migrar_mac_normalizada(dbapi_connection, cursor) -> None:
    """Añade `dispensers.mac_normalized`, la rellena y crea su índice único.

    Sigue el mismo patrón que la migración de `logs.pet_id`: DDL directo sobre la
    conexión SQLite al abrirla, sin framework de migraciones. `mac_address` no se
    modifica, así que el formato visible de los datos existentes se conserva.
    """
    tabla_existe = cursor.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'dispensers'"
    ).fetchone()
    if not tabla_existe:
        # Base recién creada: `Base.metadata.create_all` ya incluye la columna.
        return

    columnas = [row[1] for row in cursor.execute("PRAGMA table_info(dispensers)")]
    if "mac_normalized" not in columnas:
        cursor.execute("ALTER TABLE dispensers ADD COLUMN mac_normalized VARCHAR")

    # Backfill: solo se rellenan las filas aún vacías, sin tocar el resto.
    for id_dispenser, mac_address in cursor.execute(
        "SELECT id, mac_address FROM dispensers WHERE mac_normalized IS NULL"
    ).fetchall():
        cursor.execute(
            "UPDATE dispensers SET mac_normalized = ? WHERE id = ?",
            (normalize_mac(mac_address), id_dispenser),
        )

    _verificar_mac_normalizada_sin_colisiones(cursor)

    cursor.execute(
        f"CREATE UNIQUE INDEX IF NOT EXISTS {INDICE_UNICO_MAC_NORMALIZADA} "
        "ON dispensers (mac_normalized)"
    )
    dbapi_connection.commit()


def _tabla_existe(cursor, nombre: str) -> bool:
    return (
        cursor.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (nombre,)
        ).fetchone()
        is not None
    )


def _columnas_de_tabla(cursor, nombre: str):
    return [fila[1] for fila in cursor.execute(f"PRAGMA table_info({nombre})")]


def _expresion_columna(columnas, nombre: str, respaldo: str = "NULL") -> str:
    return f"l.{nombre}" if nombre in columnas else respaldo


def _pet_id_tiene_fk_anulable(cursor) -> bool:
    """Indica si `logs.pet_id` conserva una FK `ON DELETE SET NULL`.

    Una base puede tener ya todas las columnas finales y seguir anulando la
    referencia al borrar la mascota (RF-6). SQLite expone la acción de borrado en
    la columna `on_delete` de `PRAGMA foreign_key_list`, así que el caso se
    detecta sin reconstruir la tabla.
    """
    return any(
        tabla == "pets"
        and origen == "pet_id"
        and (accion_borrado or "").upper() == "SET NULL"
        for _, _, tabla, origen, _, _, accion_borrado, _ in cursor.execute(
            "PRAGMA foreign_key_list(logs)"
        )
    )


def _crear_tabla_logs_nueva(cursor) -> None:
    """Crea `logs_nueva` con el esquema final (plan §6.1).

    `pet_id` y `dispenser_id` no llevan clave foránea: son instantáneas que deben
    sobrevivir al borrado de la mascota o del dispensador (RF-6, RF-27).
    """
    cursor.execute(
        """
        CREATE TABLE logs_nueva (
            id INTEGER NOT NULL PRIMARY KEY,
            user_id INTEGER,
            pet_id INTEGER,
            pet_name VARCHAR,
            dispenser_id INTEGER,
            dispenser_mac_masked VARCHAR,
            event_type VARCHAR,
            outcome VARCHAR,
            cause VARCHAR,
            description VARCHAR NOT NULL,
            context TEXT,
            order_id INTEGER,
            requested_grams FLOAT,
            measured_grams FLOAT,
            discounted_grams FLOAT,
            resulting_stock FLOAT,
            retry_count INTEGER,
            created_at DATETIME NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users (id)
        )
        """
    )


def _crear_indices_logs(cursor) -> None:
    """Crea los índices de `logs` que falten (idempotente, RNF-2).

    Se ejecuta también sobre una base que ya tiene el esquema final, para añadir
    los índices que se incorporen después sin reconstruir la tabla.
    """
    for nombre, columnas in INDICES_LOGS:
        cursor.execute(f"CREATE INDEX IF NOT EXISTS {nombre} ON logs ({columnas})")


def _crear_indice_orden_pendiente(cursor) -> None:
    """Crea el índice único parcial de una orden pendiente por dispensador.

    Es idempotente (`IF NOT EXISTS`) y se ejecuta también sobre una base que ya
    tiene la tabla, porque `create_all` no añade índices a tablas existentes. Si
    hubiera órdenes pendientes duplicadas de una versión anterior, se aborta el
    arranque con un mensaje claro en lugar de dejar la base sin la garantía
    (RNF-3): no se cierra ni se borra ninguna orden de forma automática.
    """
    if not _tabla_existe(cursor, "dispensing_orders"):
        return

    duplicadas = cursor.execute(
        "SELECT dispenser_id, COUNT(*) FROM dispensing_orders "
        "WHERE status = 'pending' GROUP BY dispenser_id HAVING COUNT(*) > 1"
    ).fetchall()
    if duplicadas:
        raise RuntimeError(
            "No se puede crear el índice único de órdenes pendientes porque hay "
            f"dispensadores con más de una orden pendiente: {duplicadas}. Ciérralas "
            "de forma manual; la migración no ha modificado ninguna orden."
        )

    cursor.execute(
        f"CREATE UNIQUE INDEX IF NOT EXISTS {INDICE_UNICO_ORDEN_PENDIENTE} "
        "ON dispensing_orders (dispenser_id) WHERE status = 'pending'"
    )


def _copiar_filas_logs(cursor) -> int:
    """Copia las filas existentes a `logs_nueva` y devuelve cuántas quedaron.

    Se conservan `id`, `user_id`, `pet_id`, `description` (o `event` en el
    esquema legado), `created_at` (o `timestamp`) y, si existen, `dispenser_id` y
    `dispenser_mac_masked`. El resto de campos tipados y las métricas quedan en
    `NULL` para que el registro se muestre como «Sin clasificar» (RF-41).
    """
    columnas = _columnas_de_tabla(cursor, "logs")

    if "description" in columnas and "event" in columnas:
        descripcion = "COALESCE(l.description, l.event, ?)"
    elif "description" in columnas:
        descripcion = "COALESCE(l.description, ?)"
    elif "event" in columnas:
        descripcion = "COALESCE(l.event, ?)"
    else:
        descripcion = "?"

    if "created_at" in columnas and "timestamp" in columnas:
        creado = "COALESCE(l.created_at, l.timestamp, CURRENT_TIMESTAMP)"
    elif "created_at" in columnas:
        creado = "COALESCE(l.created_at, CURRENT_TIMESTAMP)"
    elif "timestamp" in columnas:
        creado = "COALESCE(l.timestamp, CURRENT_TIMESTAMP)"
    else:
        creado = "CURRENT_TIMESTAMP"

    if "pet_id" in columnas and _tabla_existe(cursor, "pets"):
        origen = "logs l LEFT JOIN pets p ON p.id = l.pet_id"
        # Si el registro ya trae su instantánea (`pet_name`), se prefiere a la del
        # catálogo actual para no perderla al reconstruir una base completa.
        nombre_mascota = (
            "COALESCE(l.pet_name, p.name)" if "pet_name" in columnas else "p.name"
        )
    else:
        origen = "logs l"
        nombre_mascota = _expresion_columna(columnas, "pet_name")

    cursor.execute(
        f"""
        INSERT INTO logs_nueva (
            id, user_id, pet_id, pet_name, dispenser_id, dispenser_mac_masked,
            event_type, outcome, cause, description, context, order_id,
            requested_grams, measured_grams, discounted_grams, resulting_stock,
            retry_count, created_at
        )
        SELECT
            {_expresion_columna(columnas, "id")},
            {_expresion_columna(columnas, "user_id")},
            {_expresion_columna(columnas, "pet_id")},
            {nombre_mascota},
            {_expresion_columna(columnas, "dispenser_id")},
            {_expresion_columna(columnas, "dispenser_mac_masked")},
            NULL, NULL, NULL,
            {descripcion},
            NULL, NULL, NULL, NULL, NULL, NULL, NULL,
            {creado}
        FROM {origen}
        """,
        (DESCRIPCION_HISTORICA,),
    )
    return cursor.execute("SELECT COUNT(*) FROM logs_nueva").fetchone()[0]


def _migrar_logs(dbapi_connection, cursor) -> bool:
    """Reconstruye `logs` con el esquema final de la spec 014 (RF-3, RF-6, RF-41).

    Actúa una única vez: si la tabla no existe (base nueva), la crea
    `Base.metadata.create_all`; si ya tiene las 18 columnas del plan §6.1, sin
    columnas descartadas y sin FK anulable en `pet_id`, no hace nada. La
    reconstrucción no destruye datos: si el recuento de filas copiadas no
    coincide, se conserva la tabla original y se aborta el arranque.

    Devuelve `True` cuando reconstruyó la tabla y `False` cuando no hacía falta.
    """
    if not _tabla_existe(cursor, "logs"):
        return False

    columnas = _columnas_de_tabla(cursor, "logs")
    faltantes = [nombre for nombre in COLUMNAS_LOGS if nombre not in columnas]
    sobrantes = [
        nombre for nombre in COLUMNAS_PARCIALES_DESCARTADAS if nombre in columnas
    ]
    if not faltantes and not sobrantes and not _pet_id_tiene_fk_anulable(cursor):
        # La tabla ya está en el esquema final: solo se completan los índices
        # que falten, como el compuesto de usuario y fecha (RNF-2).
        _crear_indices_logs(cursor)
        dbapi_connection.commit()
        return False

    filas_antes = cursor.execute("SELECT COUNT(*) FROM logs").fetchone()[0]

    try:
        cursor.execute("DROP TABLE IF EXISTS logs_nueva")
        _crear_tabla_logs_nueva(cursor)
        filas_copiadas = _copiar_filas_logs(cursor)
        if filas_copiadas != filas_antes:
            raise RuntimeError(
                "No se puede reconstruir 'logs': se copiaron "
                f"{filas_copiadas} de {filas_antes} filas. Se conserva la tabla "
                "original y no se ha borrado ningún dato."
            )
        cursor.execute("DROP TABLE logs")
        cursor.execute("ALTER TABLE logs_nueva RENAME TO logs")
        _crear_indices_logs(cursor)
    except Exception:
        dbapi_connection.rollback()
        try:
            cursor.execute("DROP TABLE IF EXISTS logs_nueva")
        except Exception:
            pass
        raise

    dbapi_connection.commit()
    return True


# Esto asegura que SQLite verifique las llaves foráneas
@event.listens_for(Engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    try:
        cursor.execute("PRAGMA foreign_keys=ON")
        # Espera de 30 s (en milisegundos) antes de fallar con
        # `database is locked`. Es la misma espera que declara el motor.
        cursor.execute("PRAGMA busy_timeout=30000")

        # Las migraciones se ejecutan una sola vez por archivo y proceso: el
        # listener corre en cada conexión nueva del pool y repetir el DDL con
        # conexiones simultáneas provoca bloqueos. Las bases en memoria (ruta
        # vacía) no se cachean porque cada conexión es una base distinta.
        ruta = _ruta_de_la_conexion(cursor)
        if ruta and ruta in BASES_MIGRADAS:
            return

        try:
            cursor.execute("PRAGMA table_info(logs)")
            columns = [row[1] for row in cursor.fetchall()]
            if columns and 'pet_id' not in columns:
                cursor.execute("ALTER TABLE logs ADD COLUMN pet_id INTEGER")
                dbapi_connection.commit()
        except Exception:
            pass

        try:
            cursor.execute("PRAGMA table_info(dispensers)")
            dispenser_cols = [row[1] for row in cursor.fetchall()]
            if dispenser_cols and 'pending_wifi_reset' not in dispenser_cols:
                cursor.execute("ALTER TABLE dispensers ADD COLUMN pending_wifi_reset BOOLEAN DEFAULT 0")
                dbapi_connection.commit()
        except Exception:
            pass

        try:
            cursor.execute("PRAGMA table_info(dispensers)")
            dispenser_cols = [row[1] for row in cursor.fetchall()]
            if dispenser_cols and 'current_food_grams' not in dispenser_cols:
                cursor.execute("ALTER TABLE dispensers ADD COLUMN current_food_grams FLOAT DEFAULT 5000.0")
                dbapi_connection.commit()
        except Exception:
            pass

        # A diferencia de la migración de `logs`, aquí los errores no se silencian:
        # una colisión de MAC debe detener el arranque en lugar de dejar la base
        # de datos sin la garantía de unicidad.
        _migrar_mac_normalizada(dbapi_connection, cursor)

        # Reconstrucción de `logs` con el esquema de la spec 014 (RF-3, RF-6,
        # RF-41). Se ejecuta antes de `Base.metadata.create_all` (que vive en
        # `main.py`) y también debe abortar el arranque si no puede conservar las
        # filas.
        _migrar_logs(dbapi_connection, cursor)

        # Índice único parcial de la orden pendiente (RNF-3). Se crea aquí porque
        # `create_all` no añade índices a una tabla que ya existe.
        _crear_indice_orden_pendiente(cursor)
        dbapi_connection.commit()

        if ruta:
            BASES_MIGRADAS.add(ruta)
    finally:
        cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

# Dependencia para obtener la DB en las rutas
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()