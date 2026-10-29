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

from . import ayarlar as ayarmod, boru as borumod, kamerasync, kapi as kapimod, karar as kararmod, yakalama
from .goruntu import GoruntuGonderici
from .komut import KomutIsleyici
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
                 sunucu=None, depo=None, kuyruk=None, ayar_yolu=None, komut_isleyici=None):
        self.ayar = ayar or ayarmod.yukle(ayar_yolu)
        self.ayar_yolu = ayar_yolu  # None: sunucudan inen kamera tanimlari dosyaya ISLENMEZ (testler); uygulama yolu verir
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
        self.komutlar = komut_isleyici or KomutIsleyici(self.ayar, self.sunucu)  # uzaktan komutlar (kesif / sinama), v3
        self.goruntu_sunucu: dict = {}  # sync config.settings: {aralik, bosta} (goruntu karosu araligi ipuclari)
        self.goruntu_gonderici = None
        self.kamera_surum = 0  # sunucu kamera tanimlari degistikce artar (arayuz tablolari tazelemek icin okur)
        self.dinleyiciler: list = []
        self.kam_durum: dict = {}  # id -> {durum, son_kare, son_okuma}
        self.kapi_durum: dict = {}
        self.son_kare: dict = {}  # id -> (kare, zaman)
        self.goruntu: dict = {}  # id -> (kucultulmus kare, zaman): mozaik yayini, isleme hizindan bagimsiz
        self._akislar: list = []
        self._dur = threading.Event()
        self._calisiyor = False
        self._kayitli = False
        self._arka = None
        self.son_hata = ""
        self._uyarilan: set = set()
        self._kapisiz_uyarilan: set = set()

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
        kapi_komut = ""  # v3: '' = acma denenmedi | 'accepted' = SmartKeyPass komutu KABUL ETTI (fiziksel acilma kaniti DEGIL) | 'failed'
        if karar.ac:
            if not kapi:
                sonuc, neden = "acma_basarisiz", "kapi_tanimsiz"
                kapi_komut = "failed"
            else:
                r = self.kapi_surucu.ac(kapi)
                self.kapi_durum[kapi["id"]] = {"basarili": r.basarili, "neden": r.neden, "zaman": okuma.zaman}
                if r.basarili:
                    sonuc = "acildi"
                    kapi_komut = "accepted"
                    self.depo.iceride_ayarla(okuma.kanonik, karar.yon == "giris")
                else:
                    sonuc, neden = "acma_basarisiz", r.neden or "bilinmeyen"
                    kapi_komut = "failed"
        # Kimlik baglama (v3): yalniz DOGRULANMIS okumada (kalibrasyonda okunan plaka guvenilmez); tanimsiz plakada kimlik yok, yalniz plaka.
        kimlik = self.depo.kimlik(okuma.kanonik) if okuma.dogrulanmis else None
        olay = {  # yerel (arayuz olay seridi); sunucuya giden govde sunucu_olayi()
            "schema_version": self.ayar["sunucu"]["schema_version"], "event_id": uuid.uuid4().hex,
            "zaman": _iso(okuma.zaman), "kamera_id": okuma.kamera_id,
            "kapi_id": kam.get("kapi_id", ""), "yon": karar.yon, "plaka": okuma.plaka,
            "guven": round(okuma.guven, 3), "karar": sonuc, "neden": neden,
            "dogrulanmis": okuma.dogrulanmis, "arac_tur": karar.arac_tur, "kaynak": okuma.kaynak,
            "daire_id": (kimlik or {}).get("daire_id") or "", "kimlik_tur": (kimlik or {}).get("tur", ""),
            "etiket": (kimlik or {}).get("etiket", ""), "kapi_komut": kapi_komut,
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
        if int(self.ayar["sunucu"]["schema_version"]) >= 3:  # v3 alanlari (hepsi isteğe bagli; yoksa hic konmaz)
            govde["apartment_id"] = _tam_sayi(olay.get("daire_id"))
            govde["kind"] = {"sakin": "resident", "misafir": "guest"}.get(olay.get("kimlik_tur"))
            govde["gate_command"] = olay.get("kapi_komut") if olay.get("kapi_komut") in ("accepted", "failed") else None
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
    def _akis_baslat(self, kam: dict) -> None:
        if not kam.get("etkin", True):
            return
        self.kam_durum.setdefault(kam["id"], {"durum": "bekliyor", "son_kare": 0, "son_okuma": 0})
        if kam.get("mod", "akis") == "akis":
            a = yakalama.AkisKaynagi(kam, self.ayar["yakalama"], self._kare_cb, self._durum_cb,
                                     self._goruntu_cb, self.ayar["izleme"])
            self._akislar.append(a)
            a.start()

    def baslat(self) -> None:
        self._dur.clear()
        self._calisiyor = True
        for kam in list(self.ayar["kameralar"]):
            self._akis_baslat(kam)
        self._arka = threading.Thread(target=self._arka_dongu, daemon=True, name="arka")
        self._arka.start()
        if self.ayar.get("goruntu_gonderim", {}).get("etkin", True) and not (
                self.goruntu_gonderici is not None and self.goruntu_gonderici.is_alive()):  # kapali ise hic baslamaz
            self.goruntu_gonderici = GoruntuGonderici(self)
            self.goruntu_gonderici.start()

    def durdur(self) -> None:
        self._calisiyor = False
        self._dur.set()
        for a in self._akislar:
            a.dur.set()
        self._akislar.clear()

    # --- sunucu kamera tanimlari (v3) ---------------------------------------------------------
    def kameralari_birlestir(self, sunucu_kameralari) -> dict:
        """Sync `config.cameras` -> yerel kameralar (kamerasync.birlestir). `None` (sunucu bu bolumu vermedi) hicbir sey yapmaz.
        Degisince calisan akislar farkla yenilenir ve sunucu-kaynakli satirlar dosyaya islenir (cevrimdisi acilista da kamera hazir olsun)."""
        fark = kamerasync.birlestir(self.ayar, sunucu_kameralari)
        yeni = [k for k in fark["kapisiz"] if k not in self._kapisiz_uyarilan]
        for k in yeni:
            self._kapisiz_uyarilan.add(k)
            log.warning("sunucu kamerasi %s: yerelde sunucu_id'si eslesen kapi yok; goruntu / sinama calisir, kapi acilmaz", k)
        if not fark["degisti"]:
            return fark
        log.info("sunucu kamera tanimlari: +%d -%d ~%d", len(fark["eklenen"]), len(fark["silinen"]), len(fark["guncellenen"]))
        self.kamera_surum += 1
        self.kameralari_yenile(fark)
        if self.ayar_yolu is not None:
            try:
                ayarmod.sunucu_kameralarini_yaz(self.ayar["kameralar"], self.ayar_yolu)
            except Exception as e:  # noqa: BLE001 - dosya hatasi calismayi durdurmasin (bellekteki tanim gecerli)
                log.warning("sunucu kamera tanimlari dosyaya yazilamadi: %s", type(e).__name__)
        return fark

    def kameralari_yenile(self, fark: dict) -> None:
        """Silinen / degisen akislari durdurur, yeni / degisenleri baslatir (servis calisiyorsa)."""
        for kid in fark["yeniden_baslat"]:
            a = self.akis(kid)
            if a is not None:
                a.dur.set()
                self._akislar.remove(a)
            if kid in fark["silinen"]:
                for tablo in (self.kam_durum, self.son_kare, self.goruntu):
                    tablo.pop(kid, None)
        if not self._calisiyor:
            return
        var = self.kameralar()
        for kid in fark["yeniden_baslat"]:
            if kid in var:
                self._akis_baslat(var[kid])

    def _kare_cb(self, kam, kare, t) -> None:
        try:
            self.kare_isle(kam, kare, t)
        except Exception:  # noqa: BLE001 - tek kare hatasi akisi oldurmesin
            log.exception("kare isleme hatasi")

    def _goruntu_cb(self, kid: str, kare, t: float) -> None:
        self.goruntu[kid] = (kare, t)

    def akis(self, kamera_id: str):
        """Kamera icin calisan RTSP akisi (yoksa None); arayuz tek kamera modunda goruntu yuksekligini degistirir."""
        return next((a for a in self._akislar if a.kam["id"] == kamera_id), None)

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
        sonraki = {"senkron": 0.0, "olay": 0.0, "kalp": 0.0, "temizle": 0.0, "komut": 0.0}
        while not self._dur.wait(1.0):
            t = time.monotonic()
            if t >= sonraki["komut"]:  # hizli yoklama: yonetici "Agda kamera ara" dediginde beklememek icin kalp atisindan ayri
                sonraki["komut"] = t + max(1.0, float(s.get("komut_aralik_sn", 5)))
                self.komut_yokla()
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
        cfg = r.govde.get("config") or {}
        self._araliklar(cfg.get("settings"))
        self._goruntu_araliklari(cfg.get("settings"))
        if isinstance(cfg.get("cameras"), list):  # sozlesme v3; eski sunucuda bolum yoktur: yerel kameralara dokunulmaz
            self.kameralari_birlestir(cfg["cameras"])
        return n

    def _goruntu_araliklari(self, ayar_sunucu: dict | None) -> None:
        """Sync config.settings goruntu karosu araliklari (izleyen varken / yokken). Yerel `goruntu_gonderim.aralik_sn` alt sinir olarak kalir."""
        a = ayar_sunucu or {}
        for anahtar, ad in (("snapshot_interval_seconds", "aralik"), ("snapshot_idle_interval_seconds", "bosta")):
            n = _tam_sayi(a.get(anahtar))
            if n is not None:
                self.goruntu_sunucu[ad] = n

    def komut_yokla(self) -> int:
        """GET commands: bekleyen uzaktan komutlari (kesif / sinama) talep edip ayri is parcaciginda calistirir. Doner: baslatilan komut sayisi."""
        r = self._dene("komutlar", self.sunucu.komutlar)
        return self.komutlar.ver((r.govde.get("commands") if r is not None else None) or [])

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
        govde = {"app_version": ayarmod.SURUM, "queue_depth": self.kuyruk.sayim()["bekleyen"], "cameras": kameralar}
        # v3: okuma hazir mi (model onayli, kalibrasyon modunda degil)? Uygulamadaki "Plakayla otomatik kapi acma" durumunu besler.
        not_ = " ".join(str(getattr(self.boru.tanima, "aciklama", "") or "").split())[:80]
        govde["recognition"] = {"ready": not self.boru.kalibrasyon_modu, **({"note": not_} if not_ else {})}
        return govde

    def kalp_atisi(self) -> None:
        r = self._dene("kalp_atisi", lambda: self.sunucu.kalp_atisi(self.kalp_atisi_govdesi()))
        if r is not None:
            self._araliklar(r.govde.get("intervals"))
            self.komutlar.ver(r.govde.get("commands") or [])  # kalp atisi yaniti da komut tasir (GET commands ile ayni atomik talep)

    def durum(self) -> dict:
        return {
            "istemci_surum": ayarmod.SURUM, "zaman": datetime.now(timezone.utc).isoformat(),
            "kalibrasyon_modu": self.boru.kalibrasyon_modu, "tanima": self.boru.tanima.aciklama,
            "kameralar": [{"id": i, **d} for i, d in self.kam_durum.items()],
            "kapilar": [{"id": i, **d} for i, d in self.kapi_durum.items()],
            "kuyruk": self.kuyruk.sayim(), "izin": self.depo.sayilar(), "boru": dict(self.boru.istatistik),
        }

    # --- Sina (ayar penceresi) -----------------------------------------------------------
    def sina(self, kamera_id: str | None = None) -> list:
        """[(ad, basarili, mesaj)] - her kameradan (ya da yalniz `kamera_id`) tek kare + isteğe bagli sunucu erisimi + ayar uyarilari.
        Sunucu bagi ISTEGE BAGLIDIR: adres/anahtar bos ise sorun degil, yalniz bilgi satiri yazilir."""
        sonuc = []
        for kam in self.ayar["kameralar"]:
            if kamera_id is not None and kam.get("id") != kamera_id:
                continue
            kare, hata = yakalama.tek_kare(kam["url"], self.ayar["yakalama"]) if kam.get("url") else (None, "url_bos")
            sonuc.append((f"Kamera {kam.get('ad') or kam['id']}", kare is not None,
                          f"kare {kare.shape[1]}x{kare.shape[0]}" if kare is not None else hata))
        if ayarmod.sunucu_hazir(self.ayar):
            ok, mesaj = self.sunucu.sina()
            sonuc.append(("Sunucu", ok, mesaj))
        else:
            sonuc.append(("Sunucu", True, "bağlantı kapalı (isteğe bağlı) — uygulama yalnız yerel çalışır, olaylar gönderilmez"))
        for u in ayarmod.dogrula(self.ayar):
            sonuc.append(("Ayar uyarisi", False, u))
        sonuc.append(("Tanima motoru", not self.boru.kalibrasyon_modu, self.boru.tanima.aciklama))
        return sonuc
