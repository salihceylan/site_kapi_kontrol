"""Boru hatti: kare -> ROI -> on-isleme -> tespit -> perspektif+esik -> segmentasyon -> tanima
-> (cok-kare konsensus -> akilli puanlama | tek-kare TR regex + teyit) -> tekillestirme.

Kalibrasyon kilidi degismez: Okuma.dogrulanmis yalniz tanima motoru dogrulanmissa (model_onayli) ve birlesik guven
`konsensus.guven_esik` ustundeyse True olur; aksi halde karar motoru kapiyi acmaz."""
from __future__ import annotations

import time
from dataclasses import dataclass, field

from . import dogrulama, konsensus as konsmod, onisleme, plaka as plakamod, roi as roimod, tanima as tanimamod, tespit as tespitmod


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
    kare_adedi: int = 1  # konsensusa giren kare sayisi
    duzeltme: int = 0  # karisiklik duzeltmesi yapilan karakter sayisi


class Boru:
    def __init__(self, ayar: dict, taban=None, detector=None, tanima=None):
        self.ayar = ayar
        self.detector = detector or tespitmod.olustur(ayar)
        self.tanima = tanima or tanimamod.olustur(ayar, taban)
        self.on = onisleme.Onisleyici(ayar.get("on_isleme", {}))
        self.seg = tanimamod.Segmentleyici(ayar["segmentleme"], ayar["tanima"]["karakter_boyut"], self.on)
        d = ayar["dogrulama"]
        self.teyit = dogrulama.KareTeyidi(d["teyit_kare"], d["teyit_pencere_sn"])
        self.tekil = dogrulama.Tekillestirme(d["tekillestirme_sn"])
        kc = ayar.get("konsensus", {})
        self.kons_ayar = kc
        self.kons_etkin = bool(kc.get("etkin", False))
        self.kons = konsmod.KonsensusPenceresi(kc.get("kare_pencere", 5), kc.get("kare_min", 3), kc.get("pencere_sn", 4.0))
        self.istatistik = {"kare": 0, "aday": 0, "karakterli": 0, "gecerli": 0, "teyitli": 0}
        self.son: dict = {}  # kamera -> son analiz ozeti (canli izleme sekmesi okur)

    @property
    def kalibrasyon_modu(self) -> bool:
        return not self.tanima.dogrulanmis

    def _roi(self, kare, roi):
        return roimod.kirp(kare, roi, float(self.ayar.get("izleme", {}).get("min_roi", 0.05)))

    def _fps(self, kid: str, t: float) -> float:
        onceki = self.son.get(kid)
        if not onceki or t <= onceki["zaman"]:
            return onceki["fps"] if onceki else 0.0
        anlik = 1.0 / (t - onceki["zaman"])
        a = float(self.ayar.get("izleme", {}).get("fps_ema", 0.3))
        return anlik if onceki["fps"] <= 0 else a * anlik + (1 - a) * onceki["fps"]

    def isle(self, kamera: dict, kare, t: float) -> list:
        """Bir kareyi isler; teyitli+tekil Okuma listesi doner (cogu karede bos)."""
        t0 = time.perf_counter()
        self.istatistik["kare"] += 1
        p = self.ayar["plaka"]
        kid = kamera["id"]
        kirp, x0, y0 = self._roi(kare, kamera.get("roi"))
        profil = self.on.profil_coz(kamera.get("profil"), kirp) if self.on.etkin else "gunduz"
        giris = self.on.kare_hazirla(kirp, profil) if self.on.etkin else kirp
        kons = self.kons_etkin
        gm = float(self.kons_ayar.get("gozlem_min_guven", 0.35))
        sonuc = []
        en_iyi = None
        for aday in self.detector.tespit_et(giris):
            self.istatistik["aday"] += 1
            karakterler = self.seg.bol(aday.plaka, profil)
            if not karakterler:
                continue
            self.istatistik["karakterli"] += 1
            s = self.tanima.tani(karakterler)
            c = plakamod.coz(s.metin, p["regex"], p["duzeltme"])
            if c is not None and s.guven >= p["min_guven"]:
                self.istatistik["gecerli"] += 1
            if kons:
                if not s.metin or s.guven < gm:
                    continue
            elif c is None or s.guven < p["min_guven"]:
                continue
            if en_iyi is None or s.guven > en_iyi[0].guven:
                en_iyi = (s, c, aday)
        kutu = anlik = None
        if en_iyi is not None:
            s, c, aday = en_iyi
            kutu = (aday.kutu[0] + x0, aday.kutu[1] + y0, aday.kutu[2], aday.kutu[3])
            anlik = (s.metin, s.guven)
        konsensus_bilgi = (None, 0.0)
        if kons:
            if en_iyi is not None:
                s = en_iyi[0]
                ham = plakamod.normalize(s.metin)
                gv = list(s.guvenler)
                alt = list(s.alternatifler)
                if len(ham) == len(s.metin) and len(gv) == len(ham):
                    self.kons.ekle(kid, konsmod.Gozlem(t, ham, gv, alt, s.dogrulanmis, s.kaynak))
            r = self.kons.sonuc(kid, t)
            if r is not None:
                pc = plakamod.puanla_coz(r.dagilim, self.ayar.get("puanlama"), p["regex"], p["duzeltme"])
                if pc is not None:
                    _, bicimli, kanonik, dz = pc
                    carpan = float(self.ayar.get("puanlama", {}).get("duzeltme_guven_carpani", 0.92))
                    guven = r.guven * carpan ** dz
                    konsensus_bilgi = (bicimli, guven)
                    if guven >= p["min_guven"]:
                        dogr = (r.dogrulanmis and guven >= float(self.kons_ayar.get("guven_esik", 0.8))
                                and r.min_oy >= float(self.kons_ayar.get("pozisyon_min_oy", 0.5)))
                        self.istatistik["teyitli"] += 1
                        if self.tekil.izin_ver(kid, kanonik, t):
                            sonuc.append(Okuma(kid, bicimli, kanonik, guven, dogr, r.kaynak, t,
                                               en_iyi[2].plaka if en_iyi else None, r.kare_adedi, dz))
                        self.kons.sifirla(kid)
        elif en_iyi is None:
            self.teyit.bos(kid, t)
        else:
            s, (bicimli, kanonik), aday = en_iyi
            if self.teyit.ekle(kid, kanonik, t):
                self.istatistik["teyitli"] += 1
                if self.tekil.izin_ver(kid, kanonik, t):
                    sonuc.append(Okuma(kid, bicimli, kanonik, s.guven, s.dogrulanmis, s.kaynak, t, aday.plaka))
        self.son[kid] = {
            "zaman": t, "kutu": kutu, "anlik": anlik[0] if anlik else "", "anlik_guven": anlik[1] if anlik else 0.0,
            "konsensus": konsensus_bilgi[0] or "", "guven": konsensus_bilgi[1] or (anlik[1] if anlik else 0.0),
            "profil": profil, "sure_ms": (time.perf_counter() - t0) * 1000.0, "fps": self._fps(kid, t),
            "roi": roimod.normalize(kamera.get("roi")), "okundu": bool(sonuc)}
        return sonuc
