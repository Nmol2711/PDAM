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
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)

# Nombre del índice único que garantiza la unicidad de la MAC (RF-01, RF-07).
INDICE_UNICO_MAC_NORMALIZADA = "ux_dispensers_mac_normalized"


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


# Esto asegura que SQLite verifique las llaves foráneas
@event.listens_for(Engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    try:
        cursor.execute("PRAGMA foreign_keys=ON")
        try:
            cursor.execute("PRAGMA table_info(logs)")
            columns = [row[1] for row in cursor.fetchall()]
            if columns and 'pet_id' not in columns:
                cursor.execute("ALTER TABLE logs ADD COLUMN pet_id INTEGER")
                dbapi_connection.commit()
        except Exception:
            pass

        # A diferencia de la migración de `logs`, aquí los errores no se silencian:
        # una colisión de MAC debe detener el arranque en lugar de dejar la base
        # de datos sin la garantía de unicidad.
        _migrar_mac_normalizada(dbapi_connection, cursor)
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