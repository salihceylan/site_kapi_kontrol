"""Boru hatti: kare -> tespit -> perspektif+Otsu -> segmentasyon -> tanima -> TR regex -> teyit -> tekillestirme."""
from __future__ import annotations

from dataclasses import dataclass, field

from . import dogrulama, plaka as plakamod, tanima as tanimamod, tespit as tespitmod


@dataclass
class Okuma:
    kamera_id: str
    plaka: str  # bicimli: "34 ABC 123"
    kanonik: str  # "34ABC123"
    guven: float
    dogrulanmis: bool
    kaynak: str
    zaman: float
    plaka_goruntu: object = field(default=None, repr=False)  # yalniz kalibrasyon kaydi icin


class Boru:
    def __init__(self, ayar: dict, taban=None, detector=None, tanima=None):
        self.ayar = ayar
        self.detector = detector or tespitmod.olustur(ayar)
        self.tanima = tanima or tanimamod.olustur(ayar, taban)
        self.seg = tanimamod.Segmentleyici(ayar["segmentleme"], ayar["tanima"]["karakter_boyut"])
        d = ayar["dogrulama"]
        self.teyit = dogrulama.KareTeyidi(d["teyit_kare"], d["teyit_pencere_sn"])
        self.tekil = dogrulama.Tekillestirme(d["tekillestirme_sn"])
        self.istatistik = {"kare": 0, "aday": 0, "karakterli": 0, "gecerli": 0, "teyitli": 0}

    @property
    def kalibrasyon_modu(self) -> bool:
        return not self.tanima.dogrulanmis

    def _roi(self, kare, roi):
        if not roi or list(roi) == [0, 0, 1, 1]:
            return kare, 0, 0
        h, w = kare.shape[:2]
        x0, y0, x1, y1 = int(roi[0] * w), int(roi[1] * h), int(roi[2] * w), int(roi[3] * h)
        return kare[y0:y1, x0:x1], x0, y0

    def isle(self, kamera: dict, kare, t: float) -> list:
        """Bir kareyi isler; teyitli+tekil Okuma listesi doner (cogu karede bos)."""
        self.istatistik["kare"] += 1
        p = self.ayar["plaka"]
        kid = kamera["id"]
        kirp, _, _ = self._roi(kare, kamera.get("roi"))
        sonuc = []
        en_iyi = None
        for aday in self.detector.tespit_et(kirp):
            self.istatistik["aday"] += 1
            karakterler = self.seg.bol(aday.plaka)
            if not karakterler:
                continue
            self.istatistik["karakterli"] += 1
            s = self.tanima.tani(karakterler)
            c = plakamod.coz(s.metin, p["regex"], p["duzeltme"])
            if c is None or s.guven < p["min_guven"]:
                continue
            self.istatistik["gecerli"] += 1
            if en_iyi is None or s.guven > en_iyi[0].guven:
                en_iyi = (s, c, aday)
        if en_iyi is None:
            self.teyit.bos(kid, t)
            return sonuc
        s, (bicimli, kanonik), aday = en_iyi
        if self.teyit.ekle(kid, kanonik, t):
            self.istatistik["teyitli"] += 1
            if self.tekil.izin_ver(kid, kanonik, t):
                sonuc.append(Okuma(kid, bicimli, kanonik, s.guven, s.dogrulanmis, s.kaynak, t, aday.plaka))
        return sonuc
