from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.api.deps import CurrentUser
from app.schemas.sync_schema import SyncBatchRequest, SyncBatchResponse
from app.services import sync_service

router = APIRouter()

@router.post("/", response_model=SyncBatchResponse)
def sincronizar_datos(
    current_user: CurrentUser,
    batch_request: SyncBatchRequest,
    db: Session = Depends(get_db)
):
    """
    Endpoint para procesamiento de lotes de sincronización offline-first (RF-04, RF-05).
    """
    return sync_service.process_sync_batch(db=db, user_id=current_user.id, batch_request=batch_request)
