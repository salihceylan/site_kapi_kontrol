"""Test yardimcilari: A1 sozlesmesi bicimli sunucu yanitlari."""
from datetime import datetime, timezone

SIMDI = 1_800_000_000.0


def iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat()


def sync_yaniti(**ek) -> dict:
    """GET /edge/plate/v1/sync yaniti (docs/PLATFORM_PLAKA_KENAR_SOZLESMESI.md)."""
    y = {
        "schema_version": 2, "server_time": "2026-10-29T12:00:00.000Z", "full": True,
        "config": {"settings": {"guest_rule": "tum_bos", "heartbeat_interval_seconds": 45, "sync_interval_seconds": 90}, "gates": []},
        "vehicles": {"rev": "v1", "items": [
            {"plate": "34SAK111", "vehicle_id": 1, "apartment_id": 1},
            {"plate": "34KAR444", "vehicle_id": 2, "apartment_id": 1},
        ]},
        "guest_permits": {"rev": "p1", "items": [
            {"id": 1, "plate": "34MIS222", "apartment_id": 1, "valid_from": iso(SIMDI - 60), "valid_until": iso(SIMDI + 3600)},
            {"id": 2, "plate": "34BIT333", "apartment_id": 1, "valid_from": iso(SIMDI - 7200), "valid_until": iso(SIMDI - 1)},
            {"id": 3, "plate": "34MIS555", "apartment_id": 0, "valid_from": iso(SIMDI - 60), "valid_until": iso(SIMDI + 3600)},
            {"id": 4, "plate": "34GEL666", "apartment_id": 1, "valid_from": iso(SIMDI + 600), "valid_until": iso(SIMDI + 3600)},
        ]},
        "blacklist": {"rev": "b1", "items": [{"plate": "34KAR444"}, {"plate": "06KAR000"}]},
        "apartments": [{"id": 1, "parking_slots": 2, "inside_count": 0}, {"id": 0, "parking_slots": 0, "inside_count": 0}],
        "presence": {"full": True, "items": []},
    }
    y.update(ek)
    return y
