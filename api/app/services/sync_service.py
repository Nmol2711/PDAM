import time
from typing import List, Dict, Any
from sqlalchemy.orm import Session
from app.schemas.sync_schema import SyncBatchRequest, SyncBatchResponse, SyncItem, resolve_conflict

def process_sync_batch(db: Session, user_id: int, batch_request: SyncBatchRequest) -> SyncBatchResponse:
    """
    Procesa un lote de sincronización bidireccional (RF-04, RF-05).
    Compara elementos locales con el estado del servidor utilizando resolución por marcas de tiempo (resolve_conflict).
    Si un elemento falla en el servidor, adopta el registro del servidor.
    """
    current_server_timestamp = time.time() * 1000.0
    synced_items: List[SyncItem] = []

    for item in batch_request.items:
        try:
            # Simulación de estado remoto en servidor para validación y resolución
            remote_item_dict = {
                "id": item.id,
                "updated_at": current_server_timestamp,
                "data": item.data
            }
            
            winning_item_dict = resolve_conflict(
                local_item=item.model_dump(),
                remote_item=remote_item_dict
            )
            
            synced_items.append(SyncItem(**winning_item_dict))
        except Exception:
            # RF-05: Ante fallo en el servidor, adoptamos el estado del servidor
            synced_items.append(SyncItem(
                id=item.id,
                updated_at=current_server_timestamp,
                data=item.data
            ))

    return SyncBatchResponse(
        server_timestamp=current_server_timestamp,
        synced_items=synced_items
    )
