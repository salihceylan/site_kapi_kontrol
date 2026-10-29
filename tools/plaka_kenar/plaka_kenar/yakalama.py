"""Kare kaynaklari: RTSP (dusuk fps surekli akis) ve tetikli tek kare. Kareler diske YAZILMAZ."""
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


class AkisKaynagi(threading.Thread):
    """Surekli grab() (tampon sismesin), yalniz fps aralikla retrieve(). Kopunca yeniden baglanir."""

    def __init__(self, kam: dict, y: dict, kare_cb, durum_cb=None):
        super().__init__(daemon=True, name=f"kamera-{kam['id']}")
        self.kam, self.y, self.kare_cb, self.durum_cb = kam, y, kare_cb, durum_cb
        self.dur = threading.Event()

    def _durum(self, d: str) -> None:
        if self.durum_cb:
            self.durum_cb(self.kam["id"], d)

    def run(self) -> None:
        _rtsp_hazirla(self.y)
        aralik = 1.0 / max(0.1, float(self.kam.get("fps", 3)))
        while not self.dur.is_set():
            cap = cv2.VideoCapture(self.kam["url"], cv2.CAP_FFMPEG)
            if not cap.isOpened():
                self._durum("koptu")
                cap.release()
                self.dur.wait(float(self.y["yeniden_baglan_sn"]))
                continue
            self._durum("bagli")
            sonraki = 0.0
            while not self.dur.is_set():
                if not cap.grab():
                    break
                simdi = time.monotonic()
                if simdi < sonraki:
                    continue
                ok, kare = cap.retrieve()
                if not ok:
                    break
                sonraki = simdi + aralik
                self.kare_cb(self.kam, kare, time.time())
            cap.release()
            self._durum("koptu")
            self.dur.wait(float(self.y["yeniden_baglan_sn"]))
