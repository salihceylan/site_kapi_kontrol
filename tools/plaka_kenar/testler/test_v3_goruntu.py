"""Sozlesme v3 - goruntu karolari: JPEG uretimi (boyut / kalite siniri), gonderim (sahte sunucu + sahte kare), bayat kare atlama, sunucu araligina uyum,
hata geri cekilmesi (kuyruga biriktirme yok), kapatilabilirlik."""
import copy
import unittest
from types import SimpleNamespace

import numpy as np

from plaka_kenar import ayarlar, goruntu
from plaka_kenar.sunucu import SunucuHatasi

SIMDI = 1_800_000_000.0


class SahteSunucu:
    def __init__(self, yanit=None, hatalar=None):
        self.gonderilen, self.yanit, self.hatalar = [], yanit if yanit is not None else {"watched": True, "next_seconds": 4}, list(hatalar or [])

    def uc_etkin(self, ad):
        return True

    def goruntu_gonder(self, kamera_id, jpeg, zaman, genislik, yukseklik):
        if self.hatalar:
            h = self.hatalar.pop(0)
            if h is not None:
                raise h
        self.gonderilen.append((kamera_id, jpeg, zaman, genislik, yukseklik))
        return SimpleNamespace(govde=self.yanit)


def kare(h=720, w=1280, gurultu=False):
    if gurultu:
        return np.random.RandomState(1).randint(0, 255, (h, w, 3), dtype=np.uint8)
    k = np.zeros((h, w, 3), np.uint8)
    k[:, :, 1] = np.linspace(0, 255, w, dtype=np.uint8)[None, :]
    return k


def servis(sunucu=None, kameralar=None, **gayar):
    ayar = copy.deepcopy(ayarlar.VARSAYILAN)
    ayar["goruntu_gonderim"].update(gayar)
    ayar["kameralar"] = kameralar if kameralar is not None else [{"id": "c1", "sunucu_id": 7, "mod": "akis", "etkin": True}]
    return SimpleNamespace(ayar=ayar, sunucu=sunucu or SahteSunucu(), son_kare={"c1": (kare(), SIMDI)}, goruntu_sunucu={}, _dur=SimpleNamespace(wait=lambda s: True))


class JpegTesti(unittest.TestCase):
    def test_kucultulur_jpeg_basligi_ve_boyutlar(self):
        veri, w, h = goruntu.jpeg_uret(kare(1080, 1920), 360, 60, 262144)
        self.assertEqual(veri[:3], b"\xff\xd8\xff")
        self.assertEqual((w, h), (640, 360))                              # 16:9 korunur, ~360p
        self.assertLessEqual(len(veri), 262144)

    def test_boyut_siniri_kaliteyi_sonra_boyutu_dusurur(self):
        gurultulu = kare(720, 1280, gurultu=True)
        buyuk = goruntu.jpeg_uret(gurultulu, 360, 90, 10_000_000)
        sinirli = goruntu.jpeg_uret(gurultulu, 360, 90, 30_000)
        self.assertIsNotNone(sinirli)
        self.assertLessEqual(len(sinirli[0]), 30_000)
        self.assertLess(len(sinirli[0]), len(buyuk[0]))
        self.assertIsNone(goruntu.jpeg_uret(gurultulu, 360, 90, 10))        # hicbir kucultmeyle sigmaz: gonderilmez

    def test_sonraki_aralik_yerel_alt_sinir_ve_sunucu_ipucu(self):
        g = {"aralik_sn": 4, "bosta_aralik_sn": 15}
        self.assertEqual(goruntu.sonraki_aralik(g, {}, {"next_seconds": 9}), 9)
        self.assertEqual(goruntu.sonraki_aralik(g, {}, {"next_seconds": 2}), 4)           # yerel alt sinir
        self.assertEqual(goruntu.sonraki_aralik(g, {}, {"next_seconds": 99999}), 600)       # ust kistas
        self.assertEqual(goruntu.sonraki_aralik(g, {}, {"watched": False}), 15)
        self.assertEqual(goruntu.sonraki_aralik(g, {}, {"watched": True}), 4)
        self.assertEqual(goruntu.sonraki_aralik(g, {"aralik": 6, "bosta": 30}, {"watched": False}), 30)
        self.assertEqual(goruntu.sonraki_aralik(g, {"aralik": 6, "bosta": 30}, {"watched": True}), 6)
        self.assertEqual(goruntu.sonraki_aralik(g, {}, {"next_seconds": "x"}), 15)          # gecersiz deger + izleyen bilgisi yok: bosta aralik
        self.assertEqual(goruntu.sonraki_aralik(g, {}, {"next_seconds": "x", "watched": True}), 4)


class GondericiTesti(unittest.TestCase):
    def test_gonderir_sozlesme_basliklariyla_ve_sunucu_araligina_uyar(self):
        s = servis(SahteSunucu({"watched": True, "next_seconds": 9}))
        g = goruntu.GoruntuGonderici(s, saat=lambda: SIMDI + 1)
        self.assertEqual(g.gonder(s.ayar["kameralar"][0]), "ok")
        (kid, jpeg, zaman, w, h), = s.sunucu.gonderilen
        self.assertEqual((kid, jpeg[:2], w, h), (7, b"\xff\xd8", 640, 360))
        self.assertTrue(zaman.startswith("2027-01-15"))                    # yakalama zamani kareden (UTC ISO)
        self.assertEqual(g._sonraki["c1"], SIMDI + 1 + 9)                  # yanittaki next_seconds
        self.assertEqual(g.tur(SIMDI + 5), 0)                              # vakti gelmedi
        s.son_kare["c1"] = (kare(), SIMDI + 9)
        self.assertEqual(g.tur(SIMDI + 10), 1)                             # vakti geldi, kare taze
        self.assertEqual(len(s.sunucu.gonderilen), 2)

    def test_bayat_kare_gonderilmez(self):
        s = servis()
        g = goruntu.GoruntuGonderici(s, saat=lambda: SIMDI + 100)
        self.assertEqual(g.gonder(s.ayar["kameralar"][0], SIMDI + 100), "bayat")    # kare 100 sn once: 2x aralik (8 sn) asildi
        s.son_kare.pop("c1")
        self.assertEqual(g.gonder(s.ayar["kameralar"][0], SIMDI + 100), "bayat")    # hic kare yok
        self.assertEqual(s.sunucu.gonderilen, [])
        self.assertEqual(g.atlanan_bayat, 2)

    def test_etkin_false_hic_gondermez_ve_servis_baslatilmaz(self):
        s = servis(etkin=False)
        g = goruntu.GoruntuGonderici(s, saat=lambda: SIMDI + 1)
        self.assertFalse(g.etkin())
        self.assertEqual(g.tur(SIMDI + 1), 0)
        self.assertEqual(s.sunucu.gonderilen, [])
        # Servis.baslat kapaliyken gondericiyi hic baslatmaz
        from unittest import mock
        from plaka_kenar.kuyruk import OlayKuyrugu
        from plaka_kenar.karar import IzinDeposu
        from plaka_kenar.servis import Servis
        ayar = copy.deepcopy(ayarlar.VARSAYILAN)
        ayar["goruntu_gonderim"]["etkin"] = False
        sv = Servis(ayar, boru=mock.Mock(kalibrasyon_modu=False, istatistik={}), kapi_surucu=mock.Mock(), depo=IzinDeposu(), kuyruk=OlayKuyrugu(),
                    sunucu=mock.Mock())
        sv.baslat()
        try:
            self.assertIsNone(sv.goruntu_gonderici)
        finally:
            sv.durdur()

    def test_yalniz_sunucu_idli_akis_modlu_etkin_kameralar(self):
        kameralar = [{"id": "c1", "sunucu_id": 7, "mod": "akis"}, {"id": "c2", "mod": "akis"}, {"id": "c3", "sunucu_id": 8, "mod": "tetik"},
                     {"id": "c4", "sunucu_id": 9, "etkin": False}, {"id": "c5", "sunucu_id": "", "mod": "akis"}]
        s = servis(kameralar=kameralar)
        for k in ("c2", "c3", "c4", "c5"):
            s.son_kare[k] = (kare(), SIMDI)
        g = goruntu.GoruntuGonderici(s, saat=lambda: SIMDI)
        self.assertEqual(g.tur(SIMDI), 1)
        self.assertEqual([x[0] for x in s.sunucu.gonderilen], [7])

    def test_gecici_hatada_ustel_geri_cekilme_ve_kuyruga_biriktirme_yok(self):
        s = servis(SahteSunucu(hatalar=[SunucuHatasi("ConnectionError")] * 8))
        g = goruntu.GoruntuGonderici(s, saat=lambda: SIMDI)
        kam = s.ayar["kameralar"][0]
        beklemeler = []
        for i in range(7):
            s.son_kare["c1"] = (kare(), SIMDI + 1000 * i)
            self.assertEqual(g.gonder(kam, SIMDI + 1000 * i), "gecici_hata")
            beklemeler.append(g._genel_sonraki - (SIMDI + 1000 * i))
        self.assertEqual(beklemeler[:4], [8, 16, 32, 60])                 # 4 * 2^n, hata_bekleme_en_cok_sn=60 ile kistli
        self.assertEqual(max(beklemeler), 60)
        s.son_kare["c1"] = (kare(), SIMDI + 9000)
        s.sunucu.hatalar.clear()
        self.assertEqual(g.tur(SIMDI + 9000), 1)                           # tek (en yeni) kare gider; eski kareler birikmemis
        self.assertEqual(len(s.sunucu.gonderilen), 1)
        self.assertEqual((g._hata, g._genel_sonraki), (0, 0.0))            # basari geri cekilmeyi sifirlar
        # geri cekilme sirasinda tur() hicbir seyi denemez
        g._genel_sonraki = SIMDI + 9500
        s.son_kare["c1"] = (kare(), SIMDI + 9100)
        g._sonraki.clear()
        self.assertEqual(g.tur(SIMDI + 9100), 0)

    def test_kalici_hata_yalniz_o_kamerayi_bekletir(self):
        kameralar = [{"id": "c1", "sunucu_id": 7, "mod": "akis"}, {"id": "c2", "sunucu_id": 8, "mod": "akis"}]
        s = servis(SahteSunucu(hatalar=[SunucuHatasi("HTTP 404 CAMERA_NOT_FOUND", kalici=True, kod=404)]), kameralar=kameralar)
        s.son_kare["c2"] = (kare(), SIMDI)
        g = goruntu.GoruntuGonderici(s, saat=lambda: SIMDI)
        self.assertEqual(g.tur(SIMDI), 1)                                  # c1 kalici hata, c2 gider
        self.assertEqual([x[0] for x in s.sunucu.gonderilen], [8])
        self.assertEqual(g._sonraki["c1"], SIMDI + 60)
        self.assertEqual(g._genel_sonraki, 0.0)

    def test_sigmayan_kare_gonderilmez(self):
        s = servis(en_cok_bayt=10)
        g = goruntu.GoruntuGonderici(s, saat=lambda: SIMDI)
        self.assertEqual(g.gonder(s.ayar["kameralar"][0], SIMDI), "sigmadi")
        self.assertEqual(s.sunucu.gonderilen, [])

    def test_kare_diske_yazilmaz(self):
        import os
        import tempfile
        s = servis()
        g = goruntu.GoruntuGonderici(s, saat=lambda: SIMDI)
        with tempfile.TemporaryDirectory() as d:
            eski = os.getcwd()
            os.chdir(d)
            try:
                g.gonder(s.ayar["kameralar"][0], SIMDI)
                self.assertEqual(os.listdir(d), [])
            finally:
                os.chdir(eski)


if __name__ == "__main__":
    unittest.main()
