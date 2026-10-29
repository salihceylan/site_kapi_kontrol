"""Cok-kare konsensus: plaka karakter bazinda oylanir (kamera basina kayan pencere).
Her gozlem = bir karenin ham okumasi (pozisyon basina {karakter: olasilik}). Tek kare yanlislari cogunluga yenilir.
Esikler ayarlar.json 'konsensus' bolumunden gelir; saat enjekte edilir (testler sahte zaman verir)."""
from __future__ import annotations

import threading
from collections import deque
from dataclasses import dataclass, field


@dataclass
class Gozlem:
    zaman: float
    metin: str  # ham okuma (yalniz A-Z0-9)
    guvenler: list  # karakter basina 0-1
    dagilim: list = field(default_factory=list)  # pozisyon basina {karakter: olasilik} (en iyi + alternatifler)
    dogrulanmis: bool = False
    kaynak: str = ""

    def poz(self, i: int) -> dict:
        if i < len(self.dagilim) and self.dagilim[i]:
            return self.dagilim[i]
        return {self.metin[i]: float(self.guvenler[i]) if i < len(self.guvenler) else 0.0}


@dataclass
class KonsensusSonucu:
    metin: str  # pozisyon basina kazanan karakterler
    dagilim: list  # pozisyon basina {karakter: ortalama olasilik} (puanlamaya girdi)
    pozisyon_guven: list  # 0-1: oy orani x kazananin ortalama guveni
    pozisyon_oy: list  # 0-1: kazananin ilk-tercih oy orani
    guven: float  # pozisyon_guven ortalamasi
    kare_adedi: int
    dogrulanmis: bool = False
    kaynak: str = ""

    @property
    def min_oy(self) -> float:
        return min(self.pozisyon_oy) if self.pozisyon_oy else 0.0


def birlestir(gozlemler: list) -> KonsensusSonucu | None:
    """Ayni uzunluktaki gozlemleri pozisyon pozisyon oylar. Uzunluklar karisiksa toplam guveni en yuksek olan uzunluk secilir."""
    if not gozlemler:
        return None
    agirlik: dict = {}
    for g in gozlemler:
        agirlik[len(g.metin)] = agirlik.get(len(g.metin), 0.0) + (sum(g.guvenler) / max(1, len(g.guvenler)))
    uzunluk = max(agirlik, key=lambda k: (agirlik[k], k))
    grup = [g for g in gozlemler if len(g.metin) == uzunluk]
    n = len(grup)
    dagilim, kazanan, poz_guven, poz_oy = [], [], [], []
    for i in range(uzunluk):
        toplam: dict = {}
        ilk_oy: dict = {}
        ilk_guven: dict = {}
        for g in grup:
            c = g.metin[i]
            ilk_oy[c] = ilk_oy.get(c, 0) + 1
            ilk_guven[c] = ilk_guven.get(c, 0.0) + (g.guvenler[i] if i < len(g.guvenler) else 0.0)
            for ch, p in g.poz(i).items():
                toplam[ch] = toplam.get(ch, 0.0) + float(p)
        # kazanan: once ilk-tercih oy sayisi, sonra toplam olasilik
        w = max(ilk_oy, key=lambda c: (ilk_oy[c], toplam.get(c, 0.0)))
        oy_orani = ilk_oy[w] / n
        ort_guven = ilk_guven[w] / ilk_oy[w]
        dagilim.append({c: v / n for c, v in sorted(toplam.items(), key=lambda kv: -kv[1])})
        kazanan.append(w)
        poz_oy.append(oy_orani)
        poz_guven.append(oy_orani * ort_guven)
    guven = sum(poz_guven) / max(1, len(poz_guven))
    return KonsensusSonucu("".join(kazanan), dagilim, poz_guven, poz_oy, guven, n,
                           all(g.dogrulanmis for g in grup), grup[-1].kaynak)


class KonsensusPenceresi:
    """Kamera basina son `kare_pencere` gozlem (en fazla `pencere_sn` eski)."""

    def __init__(self, kare_pencere: int = 5, kare_min: int = 3, pencere_sn: float = 4.0):
        self.n = max(1, int(kare_pencere))
        self.min = max(1, min(int(kare_min), self.n))
        self.pencere = float(pencere_sn)
        self._p: dict = {}
        self._kilit = threading.Lock()

    def ekle(self, kamera: str, g: Gozlem) -> None:
        with self._kilit:
            self._p.setdefault(kamera, deque(maxlen=self.n)).append(g)

    def sonuc(self, kamera: str, t: float) -> KonsensusSonucu | None:
        """Eskileri atar; yeterli ayni uzunlukta gozlem varsa oylama sonucu, yoksa None."""
        with self._kilit:
            d = self._p.get(kamera)
            if not d:
                return None
            while d and t - d[0].zaman > self.pencere:
                d.popleft()
            liste = list(d)
        r = birlestir(liste)
        return r if r is not None and r.kare_adedi >= self.min else None

    def sifirla(self, kamera: str) -> None:
        with self._kilit:
            self._p.pop(kamera, None)
