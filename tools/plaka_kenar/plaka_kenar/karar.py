"""Yerel izin listesi (SQLite, sunucudan delta senkron) + karar motoru.

Kural ozeti (plan 5):
- dogrulanmamis okuma (kalibrasyon modu)  -> ASLA acma
- listede olmayan plaka                   -> 'tanimsiz' (acilmaz; mevcut SmartKeyPass yollari geri-dusus)
- kara liste / suresi dolmus izin (giris) -> 'red'
- sakin araci                             -> 'ac'
- misafir araci (giris)                   -> park kurali: park_yeri>=1 VE (tum_yerler_bos: iceride==0 |
                                             en_az_bir_yer_bos: iceride<park_yeri)
- CIKIS: listede bilinen her plaka cikabilir (kara liste/sure dolmasi iceri hapsetmez)
"""
from __future__ import annotations

import sqlite3
import threading
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

_SEMA = """
CREATE TABLE IF NOT EXISTS araclar(
  plaka TEXT PRIMARY KEY, daire_id TEXT, tur TEXT NOT NULL DEFAULT 'sakin',
  gecerli_bitis REAL, kara_liste INTEGER NOT NULL DEFAULT 0, iceride INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS daireler(
  daire_id TEXT PRIMARY KEY, park_yeri INTEGER NOT NULL DEFAULT 0, iceride INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
"""


def _epoch(v):
    if v in (None, ""):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    return datetime.fromisoformat(str(v).replace("Z", "+00:00")).timestamp()


class IzinDeposu:
    def __init__(self, yol: Path | str = ":memory:"):
        if yol != ":memory:":
            Path(yol).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(yol), check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.kilit = threading.RLock()
        with self.kilit:
            self.db.executescript(_SEMA)

    # --- senkron -------------------------------------------------------------------
    def imlec(self) -> str:
        with self.kilit:
            r = self.db.execute("SELECT v FROM meta WHERE k='imlec'").fetchone()
        return r["v"] if r else ""

    def delta_uygula(self, cevap: dict) -> int:
        """cevap: {"imlec", "araclar":[{plaka,daire_id,tur,gecerli_bitis,kara_liste,iceride,silindi}],
        "daireler":[{daire_id,park_yeri,iceride}]}  (schema_version 1; A1 ile uzlasilacak)."""
        n = 0
        with self.kilit, self.db:
            for a in cevap.get("araclar", []):
                plaka = "".join(ch for ch in str(a["plaka"]).upper() if ch.isalnum())
                if a.get("silindi"):
                    self.db.execute("DELETE FROM araclar WHERE plaka=?", (plaka,))
                else:
                    self.db.execute(
                        "INSERT OR REPLACE INTO araclar(plaka,daire_id,tur,gecerli_bitis,kara_liste,iceride) "
                        "VALUES(?,?,?,?,?,?)",
                        (plaka, a.get("daire_id"), a.get("tur", "sakin"), _epoch(a.get("gecerli_bitis")),
                         int(bool(a.get("kara_liste"))), int(bool(a.get("iceride")))))
                n += 1
            for d in cevap.get("daireler", []):
                self.db.execute("INSERT OR REPLACE INTO daireler(daire_id,park_yeri,iceride) VALUES(?,?,?)",
                                (d["daire_id"], int(d.get("park_yeri", 0)), int(d.get("iceride", 0))))
                n += 1
            if cevap.get("imlec") is not None:
                self.db.execute("INSERT OR REPLACE INTO meta(k,v) VALUES('imlec',?)", (str(cevap["imlec"]),))
        return n

    # --- sorgu / yerel durum ----------------------------------------------------------
    def arac(self, plaka: str):
        with self.kilit:
            r = self.db.execute("SELECT * FROM araclar WHERE plaka=?", (plaka,)).fetchone()
        return dict(r) if r else None

    def daire(self, daire_id):
        with self.kilit:
            r = self.db.execute("SELECT * FROM daireler WHERE daire_id=?", (daire_id,)).fetchone()
        return dict(r) if r else {"daire_id": daire_id, "park_yeri": 0, "iceride": 0}

    def iceride_ayarla(self, plaka: str, iceride: bool) -> None:
        """Acma basarili olunca yerel durumu iyimser gunceller (cevrimdisi ikinci misafiri de dogru keser);
        sunucu bir sonraki delta'da gercek degeri getirir."""
        with self.kilit, self.db:
            a = self.arac(plaka)
            if not a or bool(a["iceride"]) == iceride:
                return
            self.db.execute("UPDATE araclar SET iceride=? WHERE plaka=?", (int(iceride), plaka))
            if a["daire_id"]:
                self.db.execute(
                    "UPDATE daireler SET iceride=MAX(0, iceride+?) WHERE daire_id=?",
                    (1 if iceride else -1, a["daire_id"]))

    def sayilar(self) -> dict:
        with self.kilit:
            return {"arac": self.db.execute("SELECT COUNT(*) FROM araclar").fetchone()[0],
                    "daire": self.db.execute("SELECT COUNT(*) FROM daireler").fetchone()[0]}


@dataclass
class Karar:
    sonuc: str  # ac | red | tanimsiz | dogrulanmamis
    neden: str = ""
    yon: str = "giris"
    daire_id: str | None = None
    arac_tur: str | None = None

    @property
    def ac(self) -> bool:
        return self.sonuc == "ac"


class KararMotoru:
    def __init__(self, depo: IzinDeposu, misafir_kurali: str = "tum_yerler_bos"):
        if misafir_kurali not in ("tum_yerler_bos", "en_az_bir_yer_bos"):
            raise ValueError("misafir_kurali gecersiz")
        self.depo, self.kural = depo, misafir_kurali

    def yon_bul(self, kapi_yon_modu: str, kamera_yon: str, arac) -> str:
        if kamera_yon in ("giris", "cikis"):
            return kamera_yon
        if kapi_yon_modu in ("giris", "cikis"):
            return kapi_yon_modu
        return "cikis" if arac and arac["iceride"] else "giris"  # cift yon: durumdan cikar

    def karar(self, plaka: str, kapi_yon_modu: str = "cift", kamera_yon: str = "", dogrulanmis: bool = True,
              simdi: float | None = None) -> Karar:
        simdi = time.time() if simdi is None else simdi
        arac = self.depo.arac(plaka)
        yon = self.yon_bul(kapi_yon_modu, kamera_yon, arac)
        if not dogrulanmis:
            return Karar("dogrulanmamis", "kalibrasyon_modu", yon)
        if not arac:
            return Karar("tanimsiz", "listede_yok", yon)
        k = Karar("ac", "", yon, arac["daire_id"], arac["tur"])
        if yon == "cikis":
            k.neden = "cikis"
            return k
        if arac["kara_liste"]:
            return Karar("red", "kara_liste", yon, arac["daire_id"], arac["tur"])
        if arac["gecerli_bitis"] is not None and arac["gecerli_bitis"] < simdi:
            return Karar("red", "izin_suresi_doldu", yon, arac["daire_id"], arac["tur"])
        if arac["tur"] == "misafir":
            d = self.depo.daire(arac["daire_id"])
            if d["park_yeri"] < 1:
                return Karar("red", "misafir_park_yeri_yok", yon, arac["daire_id"], "misafir")
            dolu = d["iceride"] >= d["park_yeri"] if self.kural == "en_az_bir_yer_bos" else d["iceride"] > 0
            if dolu:
                return Karar("red", "misafir_park_dolu", yon, arac["daire_id"], "misafir")
            k.neden = "misafir_kabul"
        else:
            k.neden = "kayitli_arac"
        return k
