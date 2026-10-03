import unittest
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.schemas.sync_schema import SyncItem, SyncBatchRequest, resolve_conflict
from app.services.sync_service import process_sync_batch
from unittest.mock import MagicMock


class TestSyncSchemaAndConflictResolution(unittest.TestCase):
    def test_sync_item_pydantic_validation(self):
        item_data = {
            "id": "pet-123",
            "updated_at": 1710000000000.0,
            "data": {"name": "Firulais", "weight": 10.5}
        }
        sync_item = SyncItem(**item_data)
        self.assertEqual(sync_item.id, "pet-123")
        self.assertEqual(sync_item.updated_at, 1710000000000.0)
        self.assertEqual(sync_item.data["name"], "Firulais")

    def test_sync_batch_request_validation(self):
        batch = {
            "last_sync_timestamp": 1709990000000.0,
            "items": [
                {
                    "id": "pet-123",
                    "updated_at": 1710000000000.0,
                    "data": {"name": "Firulais"}
                }
            ]
        }
        req = SyncBatchRequest(**batch)
        self.assertEqual(req.last_sync_timestamp, 1709990000000.0)
        self.assertEqual(len(req.items), 1)

    def test_resolve_conflict_within_threshold_local_newer(self):
        # Drift de 2 minutos (120,000 ms) -> Local es más nuevo dentro del umbral (5 min)
        local = {"id": "1", "updated_at": 1710000120000.0, "version": "local"}
        remote = {"id": "1", "updated_at": 1710000000000.0, "version": "remote"}
        winner = resolve_conflict(local, remote, clock_drift_threshold_ms=300000)
        self.assertEqual(winner["version"], "local")

    def test_resolve_conflict_within_threshold_remote_newer(self):
        # Drift de 2 minutos (120,000 ms) -> Remoto es más nuevo dentro del umbral
        local = {"id": "1", "updated_at": 1710000000000.0, "version": "local"}
        remote = {"id": "1", "updated_at": 1710000120000.0, "version": "remote"}
        winner = resolve_conflict(local, remote, clock_drift_threshold_ms=300000)
        self.assertEqual(winner["version"], "remote")

    def test_resolve_conflict_exceeds_threshold_prioritizes_remote(self):
        # Drift de 10 minutos (600,000 ms) > 5 min -> Prioridad al servidor (remoto) aunque local sea más nuevo
        local = {"id": "1", "updated_at": 1710006000000.0, "version": "local"}
        remote = {"id": "1", "updated_at": 1710000000000.0, "version": "remote"}
        winner = resolve_conflict(local, remote, clock_drift_threshold_ms=300000)
        self.assertEqual(winner["version"], "remote")

    def test_process_sync_batch_service(self):
        db_mock = MagicMock()
        batch = SyncBatchRequest(
            last_sync_timestamp=1709990000000.0,
            items=[
                SyncItem(
                    id="pet-1",
                    updated_at=1710000000000.0,
                    data={"name": "Firulais"}
                )
            ]
        )
        response = process_sync_batch(db=db_mock, user_id=1, batch_request=batch)
        self.assertIsNotNone(response.server_timestamp)
        self.assertEqual(len(response.synced_items), 1)
        self.assertEqual(response.synced_items[0].id, "pet-1")
        self.assertEqual(response.synced_items[0].data["name"], "Firulais")


class TestSyncEndpoint(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from app.main import app
        cls.client = TestClient(app)

    def test_sync_endpoint_requires_auth(self):
        response = self.client.post("/sync/", json={"last_sync_timestamp": 0, "items": []})
        self.assertEqual(response.status_code, 401)

    def test_sync_endpoint_success_with_mocked_auth(self):
        from app.main import app
        from app.api.deps import get_current_user
        from app.models import models

        mock_user = models.User(id=1, email="test@test.com", hashed_password="xxx", is_active=True)
        payload = {
            "last_sync_timestamp": 1709990000000.0,
            "items": [
                {
                    "id": "pet-99",
                    "updated_at": 1710000000000.0,
                    "data": {"name": "Max"}
                }
            ]
        }

        app.dependency_overrides[get_current_user] = lambda: mock_user
        try:
            response = self.client.post("/sync/", json=payload)
        finally:
            app.dependency_overrides.clear()

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("server_timestamp", data)
        self.assertEqual(len(data["synced_items"]), 1)
        self.assertEqual(data["synced_items"][0]["id"], "pet-99")
        self.assertEqual(data["synced_items"][0]["data"]["name"], "Max")
