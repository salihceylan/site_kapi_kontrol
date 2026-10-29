"""Goruntu karolari (sozlesme v3): etkin her kameradan kucuk bir JPEG (~360p) sunucuya gonderilir; yonetici uygulamada kamera izgarasini gorur.
KVKK: kareler yalniz bellekte islenir, DISKE YAZILMAZ; sunucuda her kameranin yalniz SON karesi tutulur (tarihce yok). Canli kare tek kullanimliktir:
gonderilemeyen kare KUYRUGA ALINMAZ, bir sonraki turda en yeni kare gonderilir.

Aralik sunucudan gelir (yanit `next_seconds`: izleyen varken kisa, yokken uzun); `goruntu_gonderim.aralik_sn` yerel ALT SINIRDIR
(kullanilan aralik = max(yerel alt sinir, sunucudan gelen)). Hata: ustel geri cekilme (en cok `hata_bekleme_en_cok_sn`).
`goruntu_gonderim.etkin=false` ise hic baslamaz / hic gondermez."""
from __future__ import annotations

import logging
import threading
import time
from datetime import datetime, timezone

import cv2

from . import yakalama
from .sunucu import SunucuHatasi

log = logging.getLogger("plaka_kenar.goruntu")

ARALIK_ALT, ARALIK_UST = 1.0, 600.0  # sunucudan gelen aralik bu araliga kistirilir (guvenlik kistasi, urun siniri degil)
EN_KUCUK_YUKSEKLIK = 90  # boyut sinirini tutturmak icin kucultmenin tabani


def _sayi(v):
    try:
        n = float(v)
    except (TypeError, ValueError):
        return None
    return n if n == n and n not in (float("inf"), float("-inf")) else None


def jpeg_uret(kare, yukseklik: int, kalite: int, en_cok_bayt: int):
    """Kareyi `yukseklik`e kucultup JPEG'e cevirir. en_cok_bayt asilirsa once kalite, sonra boyut dusurulup yeniden denenir.
    Doner (jpeg_bytes, genislik, yukseklik) ya da sigmazsa / kodlanamazsa None."""
    k = yakalama.kucult(kare, int(yukseklik))
    q = max(10, min(95, int(kalite)))
    while True:
        ok, buf = cv2.imencode(".jpg", k, [int(cv2.IMWRITE_JPEG_QUALITY), q])
        if not ok:
            return None
        veri = buf.tobytes()
        if len(veri) <= int(en_cok_bayt):
            return veri, int(k.shape[1]), int(k.shape[0])
        if q > 25:
            q = max(25, q - 15)
            continue
        kucuk = int(k.shape[0] * 0.8)
        if kucuk < EN_KUCUK_YUKSEKLIK:
            return None
        k = yakalama.kucult(k, kucuk)


def sonraki_aralik(g: dict, sunucu_ayar: dict, govde: dict) -> float:
    """Bir sonraki gonderime kadar saniye = clamp(max(yerel alt sinir, sunucudan gelen)). Yanitta `next_seconds` yoksa `watched`a gore
    sync'ten gelen aralik (varsa), o da yoksa yerel aralik / bosta aralik."""
    alt = _sayi(g.get("aralik_sn")) or ARALIK_ALT
    n = _sayi((govde or {}).get("next_seconds"))
    if n is None:
        izleniyor = bool((govde or {}).get("watched"))
        n = _sayi((sunucu_ayar or {}).get("aralik" if izleniyor else "bosta"))
        if n is None:
            n = alt if izleniyor else (_sayi(g.get("bosta_aralik_sn")) or alt)
    return min(ARALIK_UST, max(ARALIK_ALT, alt, n))


class GoruntuGonderici(threading.Thread):
    """`servis`: ayar, sunucu, son_kare (kamera kodu -> (kare, zaman)), goruntu_sunucu (sync aralik ipuclari), _dur (durdurma olayi) saglayan Servis."""

    def __init__(self, servis, saat=time.time):
        super().__init__(daemon=True, name="goruntu-gonderici")
        self.servis, self.saat = servis, saat
        self._sonraki: dict = {}  # kamera kodu -> bir sonraki deneme zamani
        self._hata = 0  # ardisik gecici hata (tum gonderici icin ortak geri cekilme)
        self._genel_sonraki = 0.0
        self.gonderilen = 0
        self.atlanan_bayat = 0

    # --- ayar -----------------------------------------------------------------------------
    def ayar(self) -> dict:
        return self.servis.ayar.get("goruntu_gonderim", {})

    def etkin(self) -> bool:
        return bool(self.ayar().get("etkin", True)) and self.servis.sunucu.uc_etkin("goruntu")

    # --- dongu -----------------------------------------------------------------------------
    def run(self) -> None:
        while not self.servis._dur.wait(0.5):
            try:
                self.tur()
            except Exception:  # noqa: BLE001 - gonderici hatasi akisi / karar hattini etkilemesin
                log.exception("goruntu gonderici hatasi")

    def tur(self, simdi: float | None = None) -> int:
        """Vakti gelen her kamerayi gonderir. Doner: gonderilen kare sayisi."""
        simdi = self.saat() if simdi is None else simdi
        if not self.etkin() or simdi < self._genel_sonraki:
            return 0
        n = 0
        for kam in list(self.servis.ayar.get("kameralar", [])):
            if not self._uygun(kam) or simdi < self._sonraki.get(kam["id"], 0.0):
                continue
            durum = self.gonder(kam, simdi)
            if durum == "ok":
                n += 1
            elif durum == "gecici_hata":
                break  # sunucu / ag sorunlu: kalan kameralari bu turda deneme (her biri zaman asimina kadar bekletir)
        return n

    @staticmethod
    def _uygun(kam: dict) -> bool:
        return bool(kam.get("id")) and kam.get("etkin", True) and kam.get("mod", "akis") == "akis" and _sayi(kam.get("sunucu_id")) not in (None, 0.0)

    # --- tek gonderim (test edilebilir) ---------------------------------------------------------
    def gonder(self, kam: dict, simdi: float | None = None) -> str:
        """Tek kamerayi gonderir. Doner: 'ok' | 'bayat' (kare yok / eski) | 'sigmadi' | 'gecici_hata' | 'kalici_hata'."""
        simdi = self.saat() if simdi is None else simdi
        g, kid = self.ayar(), kam["id"]
        alt = _sayi(g.get("aralik_sn")) or ARALIK_ALT
        kt = self.servis.son_kare.get(kid)
        if kt is None or simdi - kt[1] > 2 * max(alt, ARALIK_ALT):
            self.atlanan_bayat += 1
            self._sonraki[kid] = simdi + alt  # kare yok / eski: yeni kare gelince hemen gonderilir (kisa yoklama)
            return "bayat"
        uretim = jpeg_uret(kt[0], int(g.get("yukseklik", 360)), int(g.get("kalite", 60)), int(g.get("en_cok_bayt", 262144)))
        if uretim is None:
            self._sonraki[kid] = simdi + max(alt, 30.0)
            log.warning("kamera %s: kare boyut sinirina sigmadi", kid)
            return "sigmadi"
        jpeg, w, h = uretim
        zaman = datetime.fromtimestamp(kt[1], timezone.utc).isoformat()
        try:
            yanit = self.servis.sunucu.goruntu_gonder(int(float(kam["sunucu_id"])), jpeg, zaman, w, h)
        except SunucuHatasi as e:
            en_cok = _sayi(g.get("hata_bekleme_en_cok_sn")) or 60.0
            if e.kalici:  # 4xx (kamera sunucuda yok / pasif ...): yalniz bu kamera uzun bekler
                self._sonraki[kid] = simdi + en_cok
                log.warning("kamera %s goruntusu reddedildi: %s", kid, e)
                return "kalici_hata"
            self._hata += 1
            bekle = min(en_cok, max(alt, 1.0) * (2 ** min(self._hata, 10)))
            self._genel_sonraki = simdi + bekle
            log.warning("goruntu gonderilemedi (%s. hata, %.0f sn sonra yeniden): %s", self._hata, bekle, e)
            return "gecici_hata"
        self._hata, self._genel_sonraki = 0, 0.0
        self.gonderilen += 1
        self._sonraki[kid] = simdi + sonraki_aralik(g, getattr(self.servis, "goruntu_sunucu", {}), getattr(yanit, "govde", {}))
        return "ok"
