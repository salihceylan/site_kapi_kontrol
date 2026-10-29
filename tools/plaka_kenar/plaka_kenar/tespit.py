"""Plaka TESPIT katmani - takilabilir arayuz.

Bugun: KlasikDetector (Sobel dikey kenar + morfoloji + kontur, TR plaka orani ~4.7:1).
Yarin: model tabanli bir Detector alt sinifi `KAYITLI` sozlugune eklenir, ayarlar.json'da
tespit.tur ile secilir; boru hatti degismez.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

import cv2
import numpy as np


@dataclass
class Aday:
    kutu: tuple  # (x, y, w, h) - kare koordinatlarinda
    skor: float
    en_boy: float
    plaka: np.ndarray  # perspektif duzeltilmis gri plaka goruntusu


class Detector(ABC):
    ad = "detector"

    @abstractmethod
    def tespit_et(self, kare: np.ndarray) -> list:
        """BGR ya da gri kare -> Aday listesi (skora gore azalan)."""


def _sirala(pts: np.ndarray) -> np.ndarray:
    s = pts.sum(axis=1)
    d = pts[:, 1] - pts[:, 0]
    return np.array([pts[np.argmin(s)], pts[np.argmin(d)], pts[np.argmax(s)], pts[np.argmax(d)]], dtype=np.float32)


class KlasikDetector(Detector):
    ad = "klasik"

    def __init__(self, p: dict):
        self.p = p

    def tespit_et(self, kare: np.ndarray) -> list:
        p = self.p
        gri = kare if kare.ndim == 2 else cv2.cvtColor(kare, cv2.COLOR_BGR2GRAY)
        yuk, gen = gri.shape[:2]
        oran = 1.0
        kucuk = gri
        if p["olcek_genislik"] and gen > p["olcek_genislik"]:
            oran = p["olcek_genislik"] / gen
            kucuk = cv2.resize(gri, (int(gen * oran), int(yuk * oran)), interpolation=cv2.INTER_AREA)
        b = int(p["bulaniklik"]) | 1
        bulanik = cv2.GaussianBlur(kucuk, (b, b), 0)
        sobel = cv2.Sobel(bulanik, cv2.CV_16S, 1, 0, ksize=3)
        sobel = cv2.convertScaleAbs(sobel)
        _, ikili = cv2.threshold(sobel, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        kw, kh = p["kapama_cekirdek"]
        ikili = cv2.morphologyEx(ikili, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (int(kw), int(kh))))
        ikili = cv2.erode(ikili, None, iterations=int(p["erozyon_tekrar"]))
        ikili = cv2.dilate(ikili, None, iterations=int(p["genlesme_tekrar"]))
        konturlar, _ = cv2.findContours(ikili, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        toplam = kucuk.shape[0] * kucuk.shape[1]
        adaylar = []
        for c in konturlar:
            alan = cv2.contourArea(c)
            if not p["alan_min_oran"] * toplam <= alan <= p["alan_max_oran"] * toplam:
                continue
            (cx, cy), (rw, rh), aci = cv2.minAreaRect(c)
            if rw < 1 or rh < 1:
                continue
            if rh > rw:  # genislik hep uzun kenar
                rw, rh, aci = rh, rw, aci + 90
            aci = ((aci + 45) % 90) - 45
            doluluk = alan / (rw * rh)
            # Sobel kumesi bazen yalniz KARAKTER bandini (ince), bazen kenar cizgileriyle tum plakayi yakalar.
            # genisletme=[x_pay, y_azami]: genislige pay eklenir; band hedef orana gore, en fazla y_azami kati
            # kadar, yukseklikte tamamlanir. Oran bu tamamlanmis kutuda olculur.
            gx, gy_azami = p["genisletme"]
            rw *= gx
            hedef_h = rw / p["hedef_en_boy"]
            if rh < hedef_h <= rh * gy_azami:
                rh = hedef_h
            en_boy = rw / rh
            if not p["en_boy_min"] <= en_boy <= p["en_boy_max"] or doluluk < p["doluluk_min"] or abs(aci) > p["aci_max"]:
                continue
            skor = doluluk * (1.0 / (1.0 + abs(en_boy - p["hedef_en_boy"])))
            kutu = cv2.boxPoints(((cx, cy), (rw, rh), aci)) / oran
            adaylar.append((skor, en_boy, kutu))
        adaylar.sort(key=lambda a: a[0], reverse=True)
        cikti = []
        W, H = (int(v) for v in p["cikis_boyut"])
        hedef = np.array([[0, 0], [W - 1, 0], [W - 1, H - 1], [0, H - 1]], dtype=np.float32)
        for skor, en_boy, kutu in adaylar[: int(p["max_aday"])]:
            src = _sirala(kutu.astype(np.float32))
            M = cv2.getPerspectiveTransform(src, hedef)
            plaka = cv2.warpPerspective(gri, M, (W, H))
            x, y, w, h = cv2.boundingRect(kutu.astype(np.int32))
            cikti.append(Aday((x, y, w, h), float(skor), float(en_boy), plaka))
        return cikti


KAYITLI = {"klasik": KlasikDetector}


def olustur(ayar: dict) -> Detector:
    tur = ayar["tespit"]["tur"]
    if tur not in KAYITLI:
        raise ValueError(f"Bilinmeyen tespit.tur: {tur} (kayitli: {', '.join(KAYITLI)})")
    return KAYITLI[tur](ayar["tespit"].get(tur, {}))
