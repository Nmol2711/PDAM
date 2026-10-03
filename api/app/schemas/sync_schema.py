from pydantic import BaseModel
from typing import Optional, Any, Dict, List

class SyncItem(BaseModel):
    id: str
    updated_at: float  # Timestamp en milisegundos
    data: Dict[str, Any]

class SyncBatchRequest(BaseModel):
    last_sync_timestamp: float
    items: List[SyncItem]

class SyncBatchResponse(BaseModel):
    server_timestamp: float
    synced_items: List[SyncItem]


def resolve_conflict(
    local_item: Dict[str, Any], 
    remote_item: Dict[str, Any], 
    clock_drift_threshold_ms: int = 300000
) -> Dict[str, Any]:
    """
    Función pura que resuelve conflictos entre un registro local y uno remoto basándose en marcas de tiempo (timestamp en milisegundos).
    Regla (RF-04):
    - Si la discrepancia (clock drift) es menor o igual al umbral (5 min = 300,000 ms), se aplica el registro más reciente.
    - Si supera los 5 minutos o hay colisión exacta, se prioriza el registro del servidor (remoto).
    """
    local_time = local_item.get("updated_at", 0.0)
    remote_time = remote_item.get("updated_at", 0.0)
    
    drift = abs(local_time - remote_time)
    
    if drift <= clock_drift_threshold_ms:
        if local_time > remote_time:
            return local_item
        else:
            return remote_item
    else:
        return remote_item
