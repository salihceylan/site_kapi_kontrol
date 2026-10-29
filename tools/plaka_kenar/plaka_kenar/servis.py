"""Orkestra: kameralar -> boru hatti -> yerel karar -> SmartKeyPass 'ac' -> olay kuyrugu -> sunucu.
KVKK: kareler yalniz bellekte; diske yalniz (acik ayarla) TANIMSIZ arac karesi yazilir ve suresi dolunca silinir.
Gunluge plaka disinda kisisel veri yazilmaz."""
from __future__ import annotations

import logging
import re
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import cv2

from . import ayarlar as ayarmod, boru as borumod, kapi as kapimod, karar as kararmod, yakalama
from .kuyruk import OlayKuyrugu
from .sunucu import SunucuHatasi, SunucuIstemcisi

log = logging.getLogger("plaka_kenar")

# Yerel karar sonucu -> sunucu sozlesmesi karar turu (docs/PLATFORM_PLAKA_KENAR_SOZLESMESI.md). None: sunucuya GITMEZ.
# 'dogrulanmamis' (kalibrasyon) sozlesmede yoktur ve cikis seridinde "tanimsiz" gibi iceri-disari durumunu bozabilir: asla gonderilmez.
SUNUCU_KARARI = {"acildi": "acildi", "red": "red", "tanimsiz": "tanimsiz", "kara_liste": "kara_liste",
                 "acma_basarisiz": "red", "dogrulanmamis": None}
_NEDEN_RE = re.compile(r"^[a-z0-9_]{1,40}$")


def _tam_sayi(v):
    try:
        n = int(v)
    except (TypeError, ValueError):
        return None
    return n if n > 0 else None


def _iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat()


class Servis:
    def __init__(self, ayar: dict | None = None, taban: Path | None = None, boru=None, kapi_surucu=None,
                 sunucu=None, depo=None, kuyruk=None):
        self.ayar = ayar or ayarmod.yukle()
        self.taban = taban
        v = self.ayar["veri"]
        self.depo = depo or kararmod.IzinDeposu(ayarmod.yol_coz(v["izin_db"], taban))
        self.kuyruk = kuyruk or OlayKuyrugu(ayarmod.yol_coz(v["olay_db"], taban))
        self.motor = kararmod.KararMotoru(self.depo, self.ayar["karar"]["misafir_kurali"],
                                          self.ayar["karar"].get("kara_liste_cikis_acilir", False))
        self.motor.sunucu_kuralini_al()  # onceki senkrondan kalan site ayari (varsa) yerel ayari ezer
        self.boru = boru or borumod.Boru(self.ayar, taban)
        self.kapi_surucu = kapi_surucu or kapimod.olustur(self.ayar)
        self.sunucu = sunucu or SunucuIstemcisi(self.ayar["sunucu"])
        self.dinleyiciler: list = []
        self.kam_durum: dict = {}  # id -> {durum, son_kare, son_okuma}
        self.kapi_durum: dict = {}
        self.son_kare: dict = {}  # id -> (kare, zaman)
        self._akislar: list = []
        self._dur = threading.Event()
        self._kayitli = False
        self._arka = None
        self.son_hata = ""
        self._uyarilan: set = set()

    # --- yardimcilar ---------------------------------------------------------------
    def kapilar(self) -> dict:
        return {k["id"]: k for k in self.ayar["kapilar"]}

    def kameralar(self) -> dict:
        return {k["id"]: k for k in self.ayar["kameralar"]}

    def _bildir(self, olay: dict) -> None:
        for d in list(self.dinleyiciler):
            try:
                d(olay)
            except Exception:  # noqa: BLE001 - arayuz hatasi akisi durdurmasin
                log.exception("dinleyici hatasi")

    # --- kare isleme ------------------------------------------------------------------
    def kare_isle(self, kam: dict, kare, t: float) -> None:
        d = self.kam_durum.setdefault(kam["id"], {"durum": "bagli", "son_kare": 0, "son_okuma": 0})
        d["son_kare"] = t
        self.son_kare[kam["id"]] = (kare, t)  # canli izleme sekmesi (yalniz en son kare, diske yazilmaz)
        for okuma in self.boru.isle(kam, kare, t):
            d["son_okuma"] = t
            self.okuma_isle(okuma, kam, kare)

    def okuma_isle(self, okuma, kam: dict, kare=None) -> dict:
        kapi = self.kapilar().get(kam.get("kapi_id", ""))
        yon_modu = kapi["yon_modu"] if kapi else "cift"
        karar = self.motor.karar(okuma.kanonik, yon_modu, kam.get("yon", ""), okuma.dogrulanmis, okuma.zaman)
        sonuc, neden = karar.sonuc, karar.neden
        if karar.ac:
            if not kapi:
                sonuc, neden = "acma_basarisiz", "kapi_tanimsiz"
            else:
                r = self.kapi_surucu.ac(kapi)
                self.kapi_durum[kapi["id"]] = {"basarili": r.basarili, "neden": r.neden, "zaman": okuma.zaman}
                if r.basarili:
                    sonuc = "acildi"
                    self.depo.iceride_ayarla(okuma.kanonik, karar.yon == "giris")
                else:
                    sonuc, neden = "acma_basarisiz", r.neden or "bilinmeyen"
        olay = {  # yerel (arayuz olay seridi); sunucuya giden govde sunucu_olayi()
            "schema_version": self.ayar["sunucu"]["schema_version"], "event_id": uuid.uuid4().hex,
            "zaman": _iso(okuma.zaman), "kamera_id": okuma.kamera_id,
            "kapi_id": kam.get("kapi_id", ""), "yon": karar.yon, "plaka": okuma.plaka,
            "guven": round(okuma.guven, 3), "karar": sonuc, "neden": neden,
            "dogrulanmis": okuma.dogrulanmis, "arac_tur": karar.arac_tur, "kaynak": okuma.kaynak,
        }
        if self.sunucu.uc_etkin("olay"):
            govde = self.sunucu_olayi(olay, okuma, kam, kapi)
            if govde is not None:
                self.kuyruk.ekle(govde)
        log.info("okuma kamera=%s plaka=%s karar=%s neden=%s", okuma.kamera_id, okuma.plaka, sonuc, neden)
        k = self.ayar["karar"]
        if sonuc == "tanimsiz" and k["tanimsiz_kare_sakla"] and kare is not None:
            self._kare_yaz(k["tanimsiz_kare_dizini"], olay["zaman"], okuma.kamera_id, kare, ".jpg")
        if self.boru.kalibrasyon_modu and k["kalibrasyon_kare_kaydet"] and okuma.plaka_goruntu is not None:
            self._kare_yaz(k["kalibrasyon_dizini"], olay["zaman"], okuma.kamera_id, okuma.plaka_goruntu, ".png")
        self._bildir(olay)
        return olay

    def sunucu_olayi(self, olay: dict, okuma, kam: dict, kapi: dict | None) -> dict | None:
        """POST events govdesi (sozlesme): event_id olay basina SABIT (kuyruktan yeniden gonderimde ayni kimlik).
        Gonderilemeyecek olay (dogrulanmamis okuma / sunucu_id'siz kamera) None doner."""
        decision = SUNUCU_KARARI.get(olay["karar"])
        camera_id = _tam_sayi(kam.get("sunucu_id"))
        if decision is None:
            return None
        if camera_id is None:
            if kam["id"] not in self._uyarilan:
                self._uyarilan.add(kam["id"])
                log.warning("kamera %s: 'sunucu_id' tanimsiz, olaylari sunucuya gonderilemez", kam["id"])
            return None
        govde = {"schema_version": self.ayar["sunucu"]["schema_version"], "event_id": olay["event_id"],
                 "camera_id": camera_id, "plate": okuma.kanonik, "decision": decision, "seen_at": olay["zaman"],
                 "direction": olay["yon"] if olay["yon"] in ("giris", "cikis") else None,
                 "confidence": max(0.0, min(1.0, float(olay["guven"])))}
        gate_id = _tam_sayi(kapi.get("sunucu_id")) if kapi else None
        if gate_id is not None:
            govde["gate_id"] = gate_id
        neden = str(olay["neden"] or "").lower()
        if _NEDEN_RE.match(neden):
            govde["reason"] = neden
        elif olay["karar"] == "acma_basarisiz":
            govde["reason"] = "acma_basarisiz"
        return {k: v for k, v in govde.items() if v is not None}

    def _kare_yaz(self, dizin: str, zaman: str, kamera: str, goruntu, uzanti: str) -> None:
        try:
            d = ayarmod.yol_coz(dizin, self.taban)
            d.mkdir(parents=True, exist_ok=True)
            ad = zaman.replace(":", "").replace("+", "_").replace(".", "_") + f"_{kamera}{uzanti}"
            ok, buf = cv2.imencode(uzanti, goruntu)
            if ok:
                (d / ad).write_bytes(buf.tobytes())
        except OSError:
            log.warning("kare yazilamadi")

    def kare_temizle(self) -> int:
        """Tanimsiz kare saklama suresi (gun) dolanlari siler."""
        k, n = self.ayar["karar"], 0
        d = ayarmod.yol_coz(k["tanimsiz_kare_dizini"], self.taban)
        if d.is_dir():
            sinir = time.time() - float(k["tanimsiz_kare_gun"]) * 86400
            for f in d.glob("*.jpg"):
                if f.stat().st_mtime < sinir:
                    f.unlink(missing_ok=True)
                    n += 1
        return n

    # --- yasam dongusu ----------------------------------------------------------------
    def baslat(self) -> None:
        self._dur.clear()
        for kam in self.ayar["kameralar"]:
            if not kam.get("etkin", True):
                continue
            self.kam_durum.setdefault(kam["id"], {"durum": "bekliyor", "son_kare": 0, "son_okuma": 0})
            if kam.get("mod", "akis") == "akis":
                a = yakalama.AkisKaynagi(kam, self.ayar["yakalama"], self._kare_cb, self._durum_cb)
                self._akislar.append(a)
                a.start()
        self._arka = threading.Thread(target=self._arka_dongu, daemon=True, name="arka")
        self._arka.start()

    def durdur(self) -> None:
        self._dur.set()
        for a in self._akislar:
            a.dur.set()
        self._akislar.clear()

    def _kare_cb(self, kam, kare, t) -> None:
        try:
            self.kare_isle(kam, kare, t)
        except Exception:  # noqa: BLE001 - tek kare hatasi akisi oldurmesin
            log.exception("kare isleme hatasi")

    def _durum_cb(self, kid: str, durum: str) -> None:
        self.kam_durum.setdefault(kid, {"son_kare": 0, "son_okuma": 0})["durum"] = durum

    def tetikle(self, kamera_id: str) -> int:
        """Tetikli mod: kisa aralikla N kare alip boru hattindan gecirir; uretilen olay sayisi doner."""
        kam = self.kameralar().get(kamera_id)
        if not kam:
            return 0
        y, sayi = self.ayar["yakalama"], 0
        for _ in range(int(y["tetik_kare_sayisi"])):
            kare, hata = yakalama.tek_kare(kam["url"], y)
            if kare is None:
                self._durum_cb(kamera_id, f"hata:{hata}")
                break
            self._durum_cb(kamera_id, "bagli")
            t = time.time()
            self.kam_durum[kamera_id]["son_kare"] = t
            for o in self.boru.isle(kam, kare, t):
                self.okuma_isle(o, kam, kare)
                sayi += 1
            time.sleep(float(y["tetik_aralik_sn"]))
        return sayi

    # --- sunucu dongusu -------------------------------------------------------------
    def _arka_dongu(self) -> None:
        s = self.ayar["sunucu"]
        sonraki = {"senkron": 0.0, "olay": 0.0, "kalp": 0.0, "temizle": 0.0}
        while not self._dur.wait(1.0):
            t = time.monotonic()
            if t >= sonraki["senkron"]:
                sonraki["senkron"] = t + s["senkron_aralik_sn"]
                self.senkronla()
            if t >= sonraki["olay"]:
                sonraki["olay"] = t + s["olay_gonderim_aralik_sn"]
                self.olay_gonder()
            if t >= sonraki["kalp"]:
                sonraki["kalp"] = t + s["kalp_atisi_aralik_sn"]
                self.kalp_atisi()
            if t >= sonraki["temizle"]:
                sonraki["temizle"] = t + 3600
                self.kuyruk.temizle(s["olay_saklama_gun"])
                self.kare_temizle()

    def _dene(self, ad: str, f):
        if not self.sunucu.uc_etkin(ad):
            return None
        try:
            r = f()
            self.son_hata = ""
            return r
        except SunucuHatasi as e:
            self.son_hata = f"{ad}: {e}"
            log.warning("sunucu %s: %s", ad, e)
            return None

    def _araliklar(self, aralik: dict | None) -> None:
        """Sunucudaki site ayari (claim/heartbeat `intervals`, sync `config.settings`) bellekteki aralik ayarini ezer."""
        s = self.ayar["sunucu"]
        for anahtar, ayar_adi in (("heartbeat_seconds", "kalp_atisi_aralik_sn"), ("heartbeat_interval_seconds", "kalp_atisi_aralik_sn"),
                                  ("sync_seconds", "senkron_aralik_sn"), ("sync_interval_seconds", "senkron_aralik_sn")):
            n = _tam_sayi((aralik or {}).get(anahtar))
            if n is not None:
                s[ayar_adi] = n

    def senkronla(self) -> int:
        """claim (bir kez) -> kuyrugu bosalt -> GET sync (delta). Gonderilmemis yerel olay varken sunucunun "iceride" gorunumu
        uygulanmaz (yerel iyimser durumu geri almasin); bolum rev'leri ve kara liste her durumda uygulanir."""
        if not self._kayitli:
            r = self._dene("kayit", lambda: self.sunucu.kayit(ayarmod.SURUM))
            if r is not None:
                self._araliklar(r.govde.get("intervals"))
            self._kayitli = r is not None or not self.sunucu.uc_etkin("kayit")
        self.olay_gonder()
        bekleyen = self.kuyruk.sayim()["bekleyen"] > 0
        r = self._dene("senkron", lambda: self.sunucu.senkron(self.depo.imlec(), self.depo.revler()))
        if r is None:
            return 0
        n = self.depo.delta_uygula(r.govde, iceride_uygula=not bekleyen)
        self.motor.sunucu_kuralini_al()
        self._araliklar((r.govde.get("config") or {}).get("settings"))
        return n

    def olay_gonder(self) -> int:
        """Kuyruktaki olaylari TEK TEK gonderir (sozlesme: POST events tek olay). Ag/5xx/401/403: kalanlar sonraki tura kalir;
        kalici 4xx: o olay 'hatali' isaretlenir ve digerlerine devam edilir."""
        liste = self.kuyruk.bekleyenler(int(self.ayar["sunucu"]["olay_toplu_adet"]))
        if not liste or not self.sunucu.uc_etkin("olay"):
            return 0
        gonderilen = 0
        for o in liste:
            try:
                self.sunucu.olay(o)
            except SunucuHatasi as e:
                self.son_hata = f"olay: {e}"
                self.kuyruk.basarisiz([o["event_id"]], kalici=e.kalici)
                if e.kalici:
                    continue
                break
            self.kuyruk.gonderildi([o["event_id"]])
            gonderilen += 1
        if gonderilen:
            self.son_hata = ""
        return gonderilen

    def kalp_atisi_govdesi(self) -> dict:
        """POST heartbeat govdesi: kamera basina son kare / son okuma (sunucu_id'si olan kameralar)."""
        kameralar = []
        for k in self.ayar["kameralar"]:
            cid = _tam_sayi(k.get("sunucu_id"))
            if cid is None or not k.get("etkin", True):
                continue
            d = self.kam_durum.get(k["id"], {})
            item = {"camera_id": cid}
            if d.get("son_kare"):
                item["last_frame_at"] = _iso(d["son_kare"])
            if d.get("son_okuma"):
                item["last_read_at"] = _iso(d["son_okuma"])
            kameralar.append(item)
        return {"app_version": ayarmod.SURUM, "queue_depth": self.kuyruk.sayim()["bekleyen"], "cameras": kameralar}

    def kalp_atisi(self) -> None:
        r = self._dene("kalp_atisi", lambda: self.sunucu.kalp_atisi(self.kalp_atisi_govdesi()))
        if r is not None:
            self._araliklar(r.govde.get("intervals"))

    def durum(self) -> dict:
        return {
            "istemci_surum": ayarmod.SURUM, "zaman": datetime.now(timezone.utc).isoformat(),
            "kalibrasyon_modu": self.boru.kalibrasyon_modu, "tanima": self.boru.tanima.aciklama,
            "kameralar": [{"id": i, **d} for i, d in self.kam_durum.items()],
            "kapilar": [{"id": i, **d} for i, d in self.kapi_durum.items()],
            "kuyruk": self.kuyruk.sayim(), "izin": self.depo.sayilar(), "boru": dict(self.boru.istatistik),
        }

    # --- Sina (ayar penceresi) -----------------------------------------------------------
    def sina(self) -> list:
        """[(ad, basarili, mesaj)] - her kameradan tek kare + sunucu erisimi + kapi bilgisi."""
        sonuc = []
        for kam in self.ayar["kameralar"]:
            kare, hata = yakalama.tek_kare(kam["url"], self.ayar["yakalama"]) if kam.get("url") else (None, "url_bos")
            sonuc.append((f"Kamera {kam.get('ad') or kam['id']}", kare is not None,
                          f"kare {kare.shape[1]}x{kare.shape[0]}" if kare is not None else hata))
        ok, mesaj = self.sunucu.sina()
        sonuc.append(("Sunucu", ok, mesaj))
        for u in ayarmod.dogrula(self.ayar):
            sonuc.append(("Ayar uyarisi", False, u))
        sonuc.append(("Tanima motoru", not self.boru.kalibrasyon_modu, self.boru.tanima.aciklama))
        return sonuc
