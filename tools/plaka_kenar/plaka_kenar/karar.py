"""Yerel izin listesi (SQLite, sunucudan delta senkron) + karar motoru.

Senkron verisi A1 sozlesmesindendir (GET /edge/plate/v1/sync): vehicles / guest_permits / blacklist bolumleri
(`rev` ile "degismedi" denetimi), apartments (park yeri + iceride sayisi) ve presence (iceride farki).

Kural ozeti (plan 5):
- dogrulanmamis okuma (kalibrasyon modu)  -> ASLA acma
- listede olmayan plaka                   -> 'tanimsiz' (acilmaz; mevcut SmartKeyPass yollari geri-dusus)
- kara liste                              -> 'kara_liste': ASLA acma (ayar `kara_liste_cikis_acilir` acik degilse CIKIS dahil)
- suresi dolmus / henuz baslamamis izin   -> 'red' (giris)
- sakin araci                             -> 'ac'
- misafir araci (giris)                   -> park kurali: park_yeri>=1 VE (tum_yerler_bos: iceride==0 |
                                             en_az_bir_yer_bos: iceride<park_yeri)
- CIKIS: listede bilinen plaka cikabilir (izin suresi dolmasi iceri hapsetmez); kara liste yukaridaki kurala tabidir
"""
from __future__ import annotations

import sqlite3
import threading
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

_SEMA = """
CREATE TABLE IF NOT EXISTS s_arac(plaka TEXT PRIMARY KEY, daire_id TEXT, etiket TEXT, kisi TEXT);
CREATE TABLE IF NOT EXISTS s_izin(plaka TEXT PRIMARY KEY, daire_id TEXT, baslangic REAL, bitis REAL, etiket TEXT);
CREATE TABLE IF NOT EXISTS s_kara(plaka TEXT PRIMARY KEY);
CREATE TABLE IF NOT EXISTS s_iceride(plaka TEXT PRIMARY KEY, daire_id TEXT, tur TEXT, zaman REAL);
CREATE TABLE IF NOT EXISTS daireler(
  daire_id TEXT PRIMARY KEY, park_yeri INTEGER NOT NULL DEFAULT 0, iceride INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
"""

# Sunucu misafir kurali -> kenar ayar adi (docs sozlesmesi: tum_bos | en_az_bir_bos).
KURAL_ESLEME = {"tum_bos": "tum_yerler_bos", "en_az_bir_bos": "en_az_bir_yer_bos"}


def _epoch(v):
    if v in (None, ""):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    return datetime.fromisoformat(str(v).replace("Z", "+00:00")).timestamp()


def _kanonik(plaka) -> str:
    return "".join(ch for ch in str(plaka).upper() if ch.isalnum())


def _id(v):
    return None if v is None else str(v)


def _metin(v, en_cok: int = 60):
    """Sunucudan gelen gorunum etiketi: kirpilir, bos ise None (kisisel veri yalniz yerel gorunum icin saklanir)."""
    t = " ".join(str(v).split())[:en_cok] if v not in (None, "") else ""
    return t or None


def kimlik_etiketi(tur: str, daire_etiketi: str | None, kisi: str | None) -> str:
    """Mozaik karosu / olay seridi satiri. sakin: "Daire A - 5 · Ali Y." ; misafir: "Misafir — Daire A - 5".
    Etiket yoksa yalniz bilinen kisimlar yazilir (tanimsiz plakada hic kimlik satiri uretilmez: cagiran None alir)."""
    daire = f"Daire {daire_etiketi}" if daire_etiketi else ""
    if tur == "misafir":
        return f"Misafir — {daire}" if daire else "Misafir"
    parcalar = [p for p in (daire, kisi or "") if p]
    return " · ".join(parcalar) if parcalar else "Kayıtlı araç"


class IzinDeposu:
    def __init__(self, yol: Path | str = ":memory:"):
        if yol != ":memory:":
            Path(yol).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(yol), check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.kilit = threading.RLock()
        with self.kilit:
            self.db.executescript(_SEMA)
            self._sema_gecis()

    def _sema_gecis(self) -> None:
        """Eski (v2) yerel dosyalar: kimlik etiketi sutunlari eksikse eklenir ve bolum 'rev'leri sifirlanir (sonraki senkron tam bolumu ister)."""
        gerekli = {"s_arac": ("etiket", "kisi"), "s_izin": ("etiket",)}
        eklendi = False
        for tablo, sutunlar in gerekli.items():
            mevcut = {r["name"] for r in self.db.execute(f"PRAGMA table_info({tablo})")}
            for sutun in sutunlar:
                if sutun not in mevcut:
                    self.db.execute(f"ALTER TABLE {tablo} ADD COLUMN {sutun} TEXT")
                    eklendi = True
        if eklendi:
            self.db.execute("DELETE FROM meta WHERE k IN ('rev_vehicles', 'rev_permits')")
            self.db.commit()

    # --- senkron -------------------------------------------------------------------
    def _meta(self, k: str, varsayilan: str = "") -> str:
        with self.kilit:
            r = self.db.execute("SELECT v FROM meta WHERE k=?", (k,)).fetchone()
        return r["v"] if r else varsayilan

    def imlec(self) -> str:
        """Sonraki senkronun `updated_since` degeri (onceki basarili yanittaki server_time); bos = tam senkron."""
        return self._meta("server_time")

    def revler(self) -> dict:
        return {ad: self._meta(f"rev_{ad}") for ad in ("vehicles", "permits", "blacklist")}

    def sunucu_kurali(self) -> str:
        """Sunucudaki site ayari (kenar ayar adiyla) ya da bos."""
        return self._meta("misafir_kurali")

    def delta_uygula(self, cevap: dict, iceride_uygula: bool = True) -> int:
        """GET sync yaniti. Her bolum {rev, items} ya da {rev, unchanged:true} (unchanged: yerel kopya gecerli).
        iceride_uygula=False: yerel gonderilmemis olaylar varken sunucunun "iceride" gorunumu (apartments/presence) UYGULANMAZ ve
        imlec ilerletilmez (sonraki senkron ayni farki yeniden ister). Doner: yazilan oge sayisi."""
        n = 0
        with self.kilit, self.db:
            kural = ((cevap.get("config") or {}).get("settings") or {}).get("guest_rule")
            if kural in KURAL_ESLEME:
                self._yaz_meta("misafir_kurali", KURAL_ESLEME[kural])
            v = cevap.get("vehicles") or {}
            if "items" in v:
                self.db.execute("DELETE FROM s_arac")
                self.db.executemany("INSERT OR REPLACE INTO s_arac(plaka,daire_id,etiket,kisi) VALUES(?,?,?,?)",
                                    [(_kanonik(x["plate"]), _id(x.get("apartment_id")), _metin(x.get("apartment_label")),
                                      _metin(x.get("person_label"))) for x in v["items"]])
                n += len(v["items"])
                self._yaz_meta("rev_vehicles", v.get("rev", ""))
            p = cevap.get("guest_permits") or {}
            if "items" in p:
                self.db.execute("DELETE FROM s_izin")
                for x in p["items"]:  # ayni plakaya birden cok izin: en gec biten kazanir
                    plaka, bitis = _kanonik(x["plate"]), _epoch(x.get("valid_until"))
                    eski = self.db.execute("SELECT bitis FROM s_izin WHERE plaka=?", (plaka,)).fetchone()
                    if eski is None or (bitis or 0) > (eski["bitis"] or 0):
                        self.db.execute("INSERT OR REPLACE INTO s_izin(plaka,daire_id,baslangic,bitis,etiket) VALUES(?,?,?,?,?)",
                                        (plaka, _id(x.get("apartment_id")), _epoch(x.get("valid_from")), bitis,
                                         _metin(x.get("apartment_label"))))
                n += len(p["items"])
                self._yaz_meta("rev_permits", p.get("rev", ""))
            b = cevap.get("blacklist") or {}
            if "items" in b:
                self.db.execute("DELETE FROM s_kara")
                self.db.executemany("INSERT OR REPLACE INTO s_kara(plaka) VALUES(?)", [(_kanonik(x["plate"]),) for x in b["items"]])
                n += len(b["items"])
                self._yaz_meta("rev_blacklist", b.get("rev", ""))
            if iceride_uygula:
                if "apartments" in cevap:
                    self.db.execute("DELETE FROM daireler")
                    self.db.executemany("INSERT OR REPLACE INTO daireler(daire_id,park_yeri,iceride) VALUES(?,?,?)",
                                        [(str(d["id"]), int(d.get("parking_slots", 0)), int(d.get("inside_count", 0)))
                                         for d in cevap["apartments"]])
                    n += len(cevap["apartments"])
                pr = cevap.get("presence")
                if pr is not None:
                    if pr.get("full"):
                        self.db.execute("DELETE FROM s_iceride")
                    for x in pr.get("items", []):
                        plaka = _kanonik(x["plate"])
                        if x.get("inside"):
                            self.db.execute("INSERT OR REPLACE INTO s_iceride(plaka,daire_id,tur,zaman) VALUES(?,?,?,?)",
                                            (plaka, _id(x.get("apartment_id")), x.get("kind", "other"), _epoch(x.get("since_at"))))
                        else:
                            self.db.execute("DELETE FROM s_iceride WHERE plaka=?", (plaka,))
                        n += 1
                if cevap.get("server_time"):
                    self._yaz_meta("server_time", str(cevap["server_time"]))
        return n

    def _yaz_meta(self, k: str, v) -> None:
        self.db.execute("INSERT OR REPLACE INTO meta(k,v) VALUES(?,?)", (k, str(v)))

    # --- sorgu / yerel durum ----------------------------------------------------------
    def arac(self, plaka: str):
        """Birlesik kayit {plaka, daire_id, tur: sakin|misafir|kara, gecerli_baslangic, gecerli_bitis, kara_liste, iceride}
        ya da listelerin hicbirinde yoksa None. Sakin kaydi misafir iznine ustundur (sunucu da once araca bakar)."""
        with self.kilit:
            a = self.db.execute("SELECT daire_id FROM s_arac WHERE plaka=?", (plaka,)).fetchone()
            i = self.db.execute("SELECT daire_id,baslangic,bitis FROM s_izin WHERE plaka=?", (plaka,)).fetchone()
            k = self.db.execute("SELECT 1 FROM s_kara WHERE plaka=?", (plaka,)).fetchone()
            c = self.db.execute("SELECT 1 FROM s_iceride WHERE plaka=?", (plaka,)).fetchone()
        if a is None and i is None and k is None:
            return None
        sakin = a is not None
        return {"plaka": plaka, "daire_id": a["daire_id"] if sakin else (i["daire_id"] if i else None),
                "tur": "sakin" if sakin else ("misafir" if i else "kara"),
                "gecerli_baslangic": None if sakin or not i else i["baslangic"],
                "gecerli_bitis": None if sakin or not i else i["bitis"],
                "kara_liste": int(k is not None), "iceride": int(c is not None)}

    def kimlik(self, plaka: str):
        """Kimlik baglama (v3): {tur: sakin|misafir, daire_id, etiket} ya da None (tanimsiz / yalniz kara liste). Sakin kaydi misafir iznine ustundur."""
        with self.kilit:
            a = self.db.execute("SELECT daire_id,etiket,kisi FROM s_arac WHERE plaka=?", (plaka,)).fetchone()
            i = None if a is not None else self.db.execute("SELECT daire_id,etiket FROM s_izin WHERE plaka=?", (plaka,)).fetchone()
        if a is not None:
            return {"tur": "sakin", "daire_id": a["daire_id"], "etiket": kimlik_etiketi("sakin", a["etiket"], a["kisi"])}
        if i is not None:
            return {"tur": "misafir", "daire_id": i["daire_id"], "etiket": kimlik_etiketi("misafir", i["etiket"], None)}
        return None

    def daire(self, daire_id):
        with self.kilit:
            r = self.db.execute("SELECT * FROM daireler WHERE daire_id=?", (daire_id,)).fetchone()
        return dict(r) if r else {"daire_id": daire_id, "park_yeri": 0, "iceride": 0}

    def iceride_ayarla(self, plaka: str, iceride: bool) -> None:
        """Acma basarili olunca yerel durumu iyimser gunceller (cevrimdisi ikinci misafiri de dogru keser);
        sunucu bir sonraki senkronda gercek degeri getirir (gonderilmemis olay yokken)."""
        with self.kilit, self.db:
            a = self.arac(plaka)
            if not a or a["tur"] == "kara" or bool(a["iceride"]) == iceride:
                return
            if iceride:
                self.db.execute("INSERT OR REPLACE INTO s_iceride(plaka,daire_id,tur,zaman) VALUES(?,?,?,?)",
                                (plaka, a["daire_id"], "resident" if a["tur"] == "sakin" else "guest", time.time()))
            else:
                self.db.execute("DELETE FROM s_iceride WHERE plaka=?", (plaka,))
            if a["daire_id"]:
                self.db.execute(
                    "INSERT INTO daireler(daire_id,park_yeri,iceride) VALUES(?,0,?) "
                    "ON CONFLICT(daire_id) DO UPDATE SET iceride=MAX(0, iceride+?)",
                    (a["daire_id"], 1 if iceride else 0, 1 if iceride else -1))

    def sayilar(self) -> dict:
        with self.kilit:
            return {"arac": self.db.execute("SELECT COUNT(*) FROM s_arac").fetchone()[0],
                    "izin": self.db.execute("SELECT COUNT(*) FROM s_izin").fetchone()[0],
                    "kara_liste": self.db.execute("SELECT COUNT(*) FROM s_kara").fetchone()[0],
                    "daire": self.db.execute("SELECT COUNT(*) FROM daireler").fetchone()[0]}


@dataclass
class Karar:
    sonuc: str  # ac | red | kara_liste | tanimsiz | dogrulanmamis
    neden: str = ""
    yon: str = "giris"
    daire_id: str | None = None
    arac_tur: str | None = None

    @property
    def ac(self) -> bool:
        return self.sonuc == "ac"


class KararMotoru:
    def __init__(self, depo: IzinDeposu, misafir_kurali: str = "tum_yerler_bos", kara_liste_cikis_acilir: bool = False):
        if misafir_kurali not in ("tum_yerler_bos", "en_az_bir_yer_bos"):
            raise ValueError("misafir_kurali gecersiz")
        self.depo, self.kural, self.kara_cikis = depo, misafir_kurali, bool(kara_liste_cikis_acilir)

    def sunucu_kuralini_al(self) -> None:
        """Sunucudaki site ayari (senkronla gelir) yerel ayari ezer."""
        k = self.depo.sunucu_kurali()
        if k in KURAL_ESLEME.values():
            self.kural = k

    def yon_bul(self, kapi_yon_modu: str, kamera_yon: str, arac) -> str:
        """Olay yonu KAMERANIN yonunden gelir (cift yonlu kapida biri giris biri cikis kamerasi). Kapinin yon modu
        yalniz yonu secilmemis ESKI kamera satirlarinda geri-dusustur (o da cift ise icerideki durumdan cikarilir)."""
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
        if arac["kara_liste"] and not (yon == "cikis" and self.kara_cikis):
            return Karar("kara_liste", "kara_liste", yon, arac["daire_id"], arac["tur"])
        k = Karar("ac", "", yon, arac["daire_id"], arac["tur"])
        if yon == "cikis":
            k.neden = "cikis"
            return k
        if arac["tur"] == "misafir":
            if arac["gecerli_baslangic"] is not None and arac["gecerli_baslangic"] > simdi:
                return Karar("red", "izin_henuz_baslamadi", yon, arac["daire_id"], "misafir")
            if arac["gecerli_bitis"] is not None and arac["gecerli_bitis"] < simdi:
                return Karar("red", "izin_suresi_doldu", yon, arac["daire_id"], "misafir")
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
