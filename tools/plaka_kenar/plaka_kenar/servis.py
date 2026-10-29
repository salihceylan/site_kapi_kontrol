"""Orkestra: kameralar -> boru hatti -> yerel karar -> SmartKeyPass 'ac' -> olay kuyrugu -> sunucu.
KVKK: kareler yalniz bellekte; diske yalniz (acik ayarla) TANIMSIZ arac karesi yazilir ve suresi dolunca silinir.
Gunluge plaka disinda kisisel veri yazilmaz."""
from __future__ import annotations

import logging
import socket
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


class Servis:
    def __init__(self, ayar: dict | None = None, taban: Path | None = None, boru=None, kapi_surucu=None,
                 sunucu=None, depo=None, kuyruk=None):
        self.ayar = ayar or ayarmod.yukle()
        self.taban = taban
        v = self.ayar["veri"]
        self.depo = depo or kararmod.IzinDeposu(ayarmod.yol_coz(v["izin_db"], taban))
        self.kuyruk = kuyruk or OlayKuyrugu(ayarmod.yol_coz(v["olay_db"], taban))
        self.motor = kararmod.KararMotoru(self.depo, self.ayar["karar"]["misafir_kurali"])
        self.boru = boru or borumod.Boru(self.ayar, taban)
        self.kapi_surucu = kapi_surucu or kapimod.olustur(self.ayar)
        self.sunucu = sunucu or SunucuIstemcisi(self.ayar["sunucu"])
        self.dinleyiciler: list = []
        self.kam_durum: dict = {}  # id -> {durum, son_kare, son_okuma}
        self.kapi_durum: dict = {}
        self._akislar: list = []
        self._dur = threading.Event()
        self._kayitli = False
        self._arka = None
        self.son_hata = ""

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
        olay = {
            "schema_version": self.ayar["sunucu"]["schema_version"], "event_id": uuid.uuid4().hex,
            "zaman": datetime.fromtimestamp(okuma.zaman, timezone.utc).isoformat(),
            "site_kodu": self.ayar["sunucu"]["site_kodu"], "kamera_id": okuma.kamera_id,
            "kapi_id": kam.get("kapi_id", ""), "yon": karar.yon, "plaka": okuma.plaka,
            "guven": round(okuma.guven, 3), "karar": sonuc, "neden": neden,
            "dogrulanmis": okuma.dogrulanmis, "arac_tur": karar.arac_tur, "kaynak": okuma.kaynak,
        }
        s = self.ayar["sunucu"]
        if self.sunucu.uc_etkin("olay") and (okuma.dogrulanmis or s["dogrulanmamis_olay_gonder"]):
            self.kuyruk.ekle(olay)
        log.info("okuma kamera=%s plaka=%s karar=%s neden=%s", okuma.kamera_id, okuma.plaka, sonuc, neden)
        k = self.ayar["karar"]
        if sonuc == "tanimsiz" and k["tanimsiz_kare_sakla"] and kare is not None:
            self._kare_yaz(k["tanimsiz_kare_dizini"], olay["zaman"], okuma.kamera_id, kare, ".jpg")
        if self.boru.kalibrasyon_modu and k["kalibrasyon_kare_kaydet"] and okuma.plaka_goruntu is not None:
            self._kare_yaz(k["kalibrasyon_dizini"], olay["zaman"], okuma.kamera_id, okuma.plaka_goruntu, ".png")
        self._bildir(olay)
        return olay

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

    def senkronla(self) -> int:
        if not self._kayitli:
            r = self._dene("kayit", lambda: self.sunucu.kayit({
                "istemci_surum": ayarmod.SURUM, "bilgisayar": socket.gethostname(),
                "kameralar": [{"id": k["id"], "ad": k.get("ad", ""), "kapi_id": k.get("kapi_id", "")}
                              for k in self.ayar["kameralar"]],
                "kapilar": [{"id": k["id"], "ad": k.get("ad", ""), "yon_modu": k.get("yon_modu", "cift"),
                             "skp_uid": k.get("skp_uid", "")} for k in self.ayar["kapilar"]]}))
            self._kayitli = r is not None or not self.sunucu.uc_etkin("kayit")
        toplam = 0
        for _ in range(20):  # sayfali delta
            r = self._dene("senkron", lambda: self.sunucu.senkron(self.depo.imlec()))
            if r is None:
                break
            toplam += self.depo.delta_uygula(r.govde)
            if not r.govde.get("devam"):
                break
        return toplam

    def olay_gonder(self) -> int:
        liste = self.kuyruk.bekleyenler(int(self.ayar["sunucu"]["olay_toplu_adet"]))
        if not liste or not self.sunucu.uc_etkin("olay"):
            return 0
        idler = [o["event_id"] for o in liste]
        try:
            self.sunucu.olaylar(liste)
        except SunucuHatasi as e:
            self.son_hata = f"olay: {e}"
            self.kuyruk.basarisiz(idler, kalici=e.kalici)
            return 0
        self.kuyruk.gonderildi(idler)
        self.son_hata = ""
        return len(idler)

    def kalp_atisi(self) -> None:
        self._dene("kalp_atisi", lambda: self.sunucu.kalp_atisi(self.durum()))

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
