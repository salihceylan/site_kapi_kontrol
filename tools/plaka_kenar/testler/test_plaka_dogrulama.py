import unittest

from plaka_kenar import plaka
from plaka_kenar.dogrulama import KareTeyidi, Tekillestirme


class PlakaTesti(unittest.TestCase):
    def test_regex_gecerli_gecersiz(self):
        for ok in ("34 ABC 123", "06 A 1234", "81 ZZ 12", "34ABC1234", "01 PR 99"):
            self.assertTrue(plaka.gecerli(ok), ok)
        for kotu in ("00 ABC 123", "82 ABC 123", "34 QAB 123", "34 ABCD 123", "34 ABC 1", "34 ABC 12345", "3 ABC 123"):
            self.assertFalse(plaka.gecerli(kotu), kotu)

    def test_normalize_turkce_ve_bosluk(self):
        self.assertEqual(plaka.normalize("34 abc-123"), "34ABC123")
        self.assertEqual(plaka.normalize("06 şA 12"), "06SA12")

    def test_konuma_gore_duzeltme(self):
        self.assertEqual(plaka.coz("O6 ABC 123")[1], "06ABC123")      # il konumunda O -> 0
        self.assertEqual(plaka.coz("34 A8C 123")[1], "34ABC123")      # harf konumunda 8 -> B
        self.assertEqual(plaka.coz("34 ABC 1Z3")[1], "34ABC123")      # rakam konumunda Z -> 2
        self.assertEqual(plaka.coz("34ABC123")[0], "34 ABC 123")
        self.assertIsNone(plaka.coz("34 ABC 1"))
        self.assertIsNone(plaka.coz("99 ABC 123"))                    # gecersiz il
        self.assertIsNone(plaka.coz("O6 ABC 123", duzeltme=False))    # duzeltme kapaliysa reddedilir


class DogrulamaTesti(unittest.TestCase):
    def test_ardisik_teyit_ve_seri_sifirlama(self):
        t = KareTeyidi(teyit_kare=2, pencere_sn=4)
        self.assertFalse(t.ekle("k1", "34ABC123", 0))
        self.assertTrue(t.ekle("k1", "34ABC123", 1))        # 2. ardisik -> teyit
        self.assertFalse(t.ekle("k1", "34ABC123", 2))       # teyit yalniz bir kez
        self.assertFalse(t.ekle("k1", "06XYZ99", 3))        # farkli okuma seriyi sifirlar
        self.assertFalse(t.ekle("k1", "34ABC123", 4))
        self.assertFalse(t.ekle("k2", "34ABC123", 4))       # kameralar bagimsiz
        self.assertFalse(t.ekle("k1", "06XYZ99", 20))       # pencere asildi: seri yeniden
        t3 = KareTeyidi(teyit_kare=3, pencere_sn=4)
        self.assertEqual([t3.ekle("k", "A", i) for i in range(3)], [False, False, True])

    def test_tekillestirme_5sn(self):
        tk = Tekillestirme(5)
        self.assertTrue(tk.izin_ver("k1", "34ABC123", 100))
        self.assertFalse(tk.izin_ver("k1", "34ABC123", 104.9))
        self.assertTrue(tk.izin_ver("k1", "34ABC123", 105.0))
        self.assertTrue(tk.izin_ver("k1", "06XYZ99", 101))   # baska plaka
        self.assertTrue(tk.izin_ver("k2", "34ABC123", 106))  # baska kamera


if __name__ == "__main__":
    unittest.main()
