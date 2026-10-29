"""Ardisik-kare teyidi ve zaman pencereli tekillestirme (plan 2: 2-3 kare teyit, 5 sn tekillestirme).
Saat enjekte edilebilir (testler sahte zaman verir); esikler ayarlar.json'dan gelir."""
from __future__ import annotations

import threading


class KareTeyidi:
    """Ayni kamerada ARDISIK `teyit_kare` okuma ayni plaka ise teyit. Farkli okuma ya da
    `pencere_sn`den uzun bosluk seriyi sifirlar."""

    def __init__(self, teyit_kare: int = 2, pencere_sn: float = 4.0):
        self.n = max(1, int(teyit_kare))
        self.pencere = float(pencere_sn)
        self._seri: dict = {}  # kamera -> [plaka, adet, son_zaman]
        self._kilit = threading.Lock()

    def ekle(self, kamera: str, plaka: str, t: float) -> bool:
        """True: bu okuma ile seri teyit sinirina ULASTI (yalniz ulasilan karede bir kez True)."""
        with self._kilit:
            s = self._seri.get(kamera)
            if s and s[0] == plaka and t - s[2] <= self.pencere:
                s[1] += 1
                s[2] = t
            else:
                s = self._seri[kamera] = [plaka, 1, t]
            return s[1] == self.n

    def bos(self, kamera: str, t: float) -> None:
        """Plaka okunamayan kare: pencereyi asan seri sifirlanir (kisa bosluk seriyi bozmaz)."""
        with self._kilit:
            s = self._seri.get(kamera)
            if s and t - s[2] > self.pencere:
                del self._seri[kamera]


class Tekillestirme:
    """Ayni (anahtar, plaka) icin `sure_sn` icinde ikinci olayi bastirir."""

    def __init__(self, sure_sn: float = 5.0):
        self.sure = float(sure_sn)
        self._son: dict = {}
        self._kilit = threading.Lock()

    def izin_ver(self, anahtar: str, plaka: str, t: float) -> bool:
        with self._kilit:
            k = (anahtar, plaka)
            onceki = self._son.get(k)
            if onceki is not None and t - onceki < self.sure:
                return False
            self._son[k] = t
            if len(self._son) > 2048:  # bellek siniri: eskileri at
                for kk in [kk for kk, tt in self._son.items() if t - tt >= self.sure]:
                    del self._son[kk]
            return True
