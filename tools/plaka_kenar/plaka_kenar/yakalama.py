"""Kare kaynaklari: RTSP (surekli akis) ve tetikli tek kare. Kareler diske YAZILMAZ."""
from __future__ import annotations

import os
import threading
import time

import cv2


def _rtsp_hazirla(y: dict) -> None:
    # TCP tasima + zaman asimi; cv2 ilk VideoCapture'dan ONCE okunur.
    os.environ.setdefault("OPENCV_FFMPEG_CAPTURE_OPTIONS",
                          f"rtsp_transport;{y['rtsp_tasima']}|stimeout;{int(y['okuma_zaman_asimi_ms']) * 1000}")


def tek_kare(url: str, y: dict):
    """Baglan, tek kare al, kapat (tetikli mod / 'Sina'). (kare|None, hata_metni)."""
    _rtsp_hazirla(y)
    cap = cv2.VideoCapture(url, cv2.CAP_FFMPEG) if url.startswith(("rtsp", "http")) else cv2.VideoCapture(url)
    try:
        if not cap.isOpened():
            return None, "baglanti_acilamadi"
        for _ in range(3):  # ilk kare bayat olabilir
            ok, kare = cap.read()
        return (kare, "") if ok and kare is not None else (None, "kare_okunamadi")
    finally:
        cap.release()


def kucult(kare, yukseklik: int):
    """Goruntuleme icin kareyi `yukseklik` piksele kucultur (en-boy korunur); 0/negatif ya da zaten kucukse ayni kare doner."""
    h, w = kare.shape[:2]
    if yukseklik <= 0 or h <= yukseklik:
        return kare
    return cv2.resize(kare, (max(1, int(round(w * yukseklik / h))), int(yukseklik)), interpolation=cv2.INTER_AREA)


class AkisKaynagi(threading.Thread):
    """Surekli grab() (tampon sismesin). Iki bagimsiz cikis:
    - GORUNTU: `goruntu_fps` aralikla kucultulmus kare -> goruntu_cb(kamera_id, kare, zaman) (mozaik; akici, isleme hizindan bagimsiz)
    - ISLEME: kamera `fps` aralikla tam kare -> AYRI isleyici thread'ine (yalniz en son kare tutulur; yavas isleme goruntuyu takmaz)
    Kopunca yeniden baglanir. `kare_cb` None ise yalniz goruntu (onizleme) akisi olur."""

    def __init__(self, kam: dict, y: dict, kare_cb, durum_cb=None, goruntu_cb=None, goruntu_ayar: dict | None = None):
        super().__init__(daemon=True, name=f"kamera-{kam['id']}")
        self.kam, self.y, self.kare_cb, self.durum_cb, self.goruntu_cb = kam, y, kare_cb, durum_cb, goruntu_cb
        self.dur = threading.Event()
        self.goruntu_aralik = 1.0 / max(1.0, float(goruntu_ayar["goruntu_fps"])) if goruntu_cb else 0.0
        self.goruntu_yukseklik = int(goruntu_ayar["karo_yukseklik"]) if goruntu_cb else 0  # arayuz tek kamera modunda degistirir
        self.goruntu_acik = True  # arayuz izleme sekmesi gorunmuyorsa kapatir: kare cozulup kucultulmez (CPU)
        self._son = None
        self._yeni = threading.Event()

    def _durum(self, d: str) -> None:
        if self.durum_cb:
            self.durum_cb(self.kam["id"], d)

    def _isleyici(self) -> None:
        """En son tam kareyi alir ve isler; mesgulken gelen ara kareler atlanir."""
        while not self.dur.is_set():
            if not self._yeni.wait(0.5):
                continue
            self._yeni.clear()
            ham, self._son = self._son, None
            if ham is not None:
                try:
                    self.kare_cb(self.kam, ham[0], ham[1])
                except Exception:  # noqa: BLE001 - tek kare hatasi akisi oldurmesin
                    pass

    def run(self) -> None:
        _rtsp_hazirla(self.y)
        aralik = 1.0 / max(0.1, float(self.kam.get("fps", 3)))
        if self.kare_cb:
            threading.Thread(target=self._isleyici, daemon=True, name=f"isleme-{self.kam['id']}").start()
        while not self.dur.is_set():
            cap = cv2.VideoCapture(self.kam["url"], cv2.CAP_FFMPEG)
            if not cap.isOpened():
                self._durum("koptu")
                cap.release()
                self.dur.wait(float(self.y["yeniden_baglan_sn"]))
                continue
            self._durum("bagli")
            sonraki = sonraki_goruntu = 0.0
            while not self.dur.is_set():
                if not cap.grab():
                    break
                simdi = time.monotonic()
                isle = self.kare_cb is not None and simdi >= sonraki
                goster = self.goruntu_cb is not None and self.goruntu_acik and simdi >= sonraki_goruntu
                if not (isle or goster):
                    continue
                ok, kare = cap.retrieve()
                if not ok:
                    break
                t = time.time()
                if goster:
                    sonraki_goruntu = simdi + self.goruntu_aralik
                    self.goruntu_cb(self.kam["id"], kucult(kare, self.goruntu_yukseklik), t)
                if isle:
                    sonraki = simdi + aralik
                    self._son = (kare, t)
                    self._yeni.set()
            cap.release()
            self._durum("koptu")
            self.dur.wait(float(self.y["yeniden_baglan_sn"]))
