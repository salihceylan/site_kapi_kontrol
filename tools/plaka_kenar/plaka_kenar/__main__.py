"""python -m plaka_kenar            -> ayar penceresi + canli seritler
python -m plaka_kenar --servis    -> pencere olmadan (NSSM Windows servisi)
python -m plaka_kenar --sina      -> komut satirindan sina (kamera kare testi + sunucu erisimi)"""
from __future__ import annotations

import argparse
import logging
import sys
import threading

from . import ayarlar


def ana(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="plaka_kenar")
    ap.add_argument("--servis", action="store_true", help="pencere acmadan calis (Windows servisi)")
    ap.add_argument("--sina", action="store_true", help="kamera ve sunucu erisimini sina, cik")
    ap.add_argument("--ayar", help="ayarlar.json yolu (varsayilan: uygulama klasoru / PLAKA_KENAR_AYAR)")
    a = ap.parse_args(argv)
    ayar = ayarlar.yukle(a.ayar)
    gunluk = ayarlar.yol_coz(ayar["veri"]["gunluk"])
    gunluk.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
                        handlers=[logging.FileHandler(gunluk, encoding="utf-8"), logging.StreamHandler()])
    if a.sina or a.servis:
        from .servis import Servis
        s = Servis(ayar, ayar_yolu=a.ayar or ayarlar.varsayilan_yol())  # sunucudan inen kamera tanimlari bu dosyaya islenir
        if a.sina:
            for ad, ok, mesaj in s.sina():
                print(("TAMAM " if ok else "SORUN ") + f"{ad}: {mesaj}")
            return 0
        logging.info("servis basliyor; tanima: %s", s.boru.tanima.aciklama)
        s.baslat()
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            s.durdur()
        return 0
    from .arayuz import calistir
    calistir(a.ayar)
    return 0


if __name__ == "__main__":
    sys.exit(ana())
