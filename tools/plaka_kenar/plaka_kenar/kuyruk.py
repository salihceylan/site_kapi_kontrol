"""SQLite olay kuyrugu (cevrimdisi dayanikli; event_id ile sunucuda idempotent)."""
from __future__ import annotations

import json
import sqlite3
import threading
import time
import uuid
from pathlib import Path

_SEMA = """
CREATE TABLE IF NOT EXISTS olaylar(
  event_id TEXT PRIMARY KEY, yuk TEXT NOT NULL, olusma REAL NOT NULL,
  deneme INTEGER NOT NULL DEFAULT 0, sonraki REAL NOT NULL DEFAULT 0,
  durum INTEGER NOT NULL DEFAULT 0);  -- 0 bekliyor, 1 gonderildi, 2 kalici hata
CREATE INDEX IF NOT EXISTS ix_olay_durum ON olaylar(durum, sonraki);
"""


class OlayKuyrugu:
    def __init__(self, yol: Path | str = ":memory:", azami_deneme: int = 20):
        if yol != ":memory:":
            Path(yol).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(yol), check_same_thread=False)
        self.kilit = threading.RLock()
        self.azami = azami_deneme
        with self.kilit:
            self.db.executescript(_SEMA)

    def ekle(self, olay: dict) -> str:
        eid = olay.setdefault("event_id", uuid.uuid4().hex)
        with self.kilit, self.db:
            self.db.execute("INSERT OR IGNORE INTO olaylar(event_id,yuk,olusma) VALUES(?,?,?)",
                            (eid, json.dumps(olay, ensure_ascii=False), time.time()))
        return eid

    def bekleyenler(self, adet: int = 50, simdi: float | None = None) -> list:
        simdi = time.time() if simdi is None else simdi
        with self.kilit:
            satir = self.db.execute(
                "SELECT yuk FROM olaylar WHERE durum=0 AND sonraki<=? ORDER BY olusma LIMIT ?",
                (simdi, adet)).fetchall()
        return [json.loads(r[0]) for r in satir]

    def gonderildi(self, idler: list) -> None:
        with self.kilit, self.db:
            self.db.executemany("UPDATE olaylar SET durum=1 WHERE event_id=?", [(i,) for i in idler])

    def basarisiz(self, idler: list, kalici: bool = False, simdi: float | None = None) -> None:
        simdi = time.time() if simdi is None else simdi
        with self.kilit, self.db:
            for i in idler:
                self.db.execute(
                    "UPDATE olaylar SET deneme=deneme+1, sonraki=? + MIN(300, 5*(deneme+1)*(deneme+1)),"
                    " durum=CASE WHEN ? OR deneme+1>=? THEN 2 ELSE 0 END WHERE event_id=?",
                    (simdi, int(kalici), self.azami, i))

    def temizle(self, gun: float, simdi: float | None = None) -> int:
        """Gonderilmis/olu olaylari saklama suresinden sonra siler (KVKK: olay saklama suresi ayardan)."""
        simdi = time.time() if simdi is None else simdi
        with self.kilit, self.db:
            return self.db.execute("DELETE FROM olaylar WHERE durum>0 AND olusma<?", (simdi - gun * 86400,)).rowcount

    def sayim(self) -> dict:
        with self.kilit:
            r = dict(self.db.execute("SELECT durum, COUNT(*) FROM olaylar GROUP BY durum").fetchall())
        return {"bekleyen": r.get(0, 0), "gonderilen": r.get(1, 0), "hatali": r.get(2, 0)}
