"""Okuma hassasiyeti paketi: konsensus, puanlama/karisiklik, ROI, on-isleme, boru entegrasyonu, ONVIF kesif ayrıştırma."""
import unittest

import cv2
import numpy as np

from plaka_kenar import ayarlar, kesif, konsensus, onisleme, plaka, roi
from plaka_kenar.boru import Boru
from plaka_kenar.konsensus import Gozlem, KonsensusPenceresi
from plaka_kenar.tanima import Karakter, Segmentleyici, TanimaSonucu
from plaka_kenar.tespit import Aday


def goz(metin, guven=0.95, t=0.0, dogr=True):
    return Gozlem(t, metin, [guven] * len(metin), [], dogr, "test")


class KonsensusTesti(unittest.TestCase):
    def test_tek_kare_yanlisi_elenir(self):
        r = konsensus.birlestir([goz("34ABC123"), goz("34ABC123"), goz("34A8C123"), goz("34ABC123"), goz("34ABC123")])
        self.assertEqual(r.metin, "34ABC123")
        self.assertEqual(r.kare_adedi, 5)
        self.assertAlmostEqual(r.pozisyon_oy[3], 0.8)  # 'B' konumu 4/5 oy
        self.assertTrue(0.8 < r.guven <= 1.0)
        self.assertAlmostEqual(r.pozisyon_guven[0], 0.95)

    def test_karisik_uzunluk_cogunlugu_secer(self):
        r = konsensus.birlestir([goz("34ABC123"), goz("34ABC1234"), goz("34ABC123"), goz("34ABC123")])
        self.assertEqual(len(r.metin), 8)
        self.assertEqual(r.kare_adedi, 3)

    def test_alternatifler_toplanir(self):
        a = Gozlem(0, "34A8C123", [0.9] * 8, [{c: 0.9} for c in "34A8C123"], True)
        a.dagilim[3] = {"8": 0.5, "B": 0.45}
        b = Gozlem(1, "34ABC123", [0.9] * 8, [{c: 0.9} for c in "34ABC123"], True)
        b.dagilim[3] = {"B": 0.6, "8": 0.3}
        r = konsensus.birlestir([a, b])
        self.assertEqual(r.dagilim[3]["B"], (0.45 + 0.6) / 2)
        self.assertEqual(r.metin[3], "B")  # 1-1 ilk-tercih beraberligi: toplam olasiligi yuksek olan (B 1.05 > 8 0.80)

    def test_pencere_min_kare_ve_zaman_asimi(self):
        w = KonsensusPenceresi(kare_pencere=5, kare_min=3, pencere_sn=4.0)
        w.ekle("k", goz("34ABC123", t=0.0))
        w.ekle("k", goz("34ABC123", t=1.0))
        self.assertIsNone(w.sonuc("k", 1.0))  # 2 kare < kare_min
        w.ekle("k", goz("34ABC123", t=2.0))
        self.assertIsNotNone(w.sonuc("k", 2.0))
        self.assertIsNone(w.sonuc("k", 7.0))  # hepsi pencere_sn'den eski
        w.sifirla("k")
        self.assertIsNone(w.sonuc("k", 2.0))

    def test_pencere_son_n_kareyle_sinirli(self):
        w = KonsensusPenceresi(kare_pencere=3, kare_min=3, pencere_sn=99)
        for i, m in enumerate(["06XYZ99", "34ABC123", "34ABC123", "34ABC123"]):
            w.ekle("k", goz(m, t=float(i)))
        self.assertEqual(w.sonuc("k", 3.0).metin, "34ABC123")


def dagilim(metin, guven=0.9):
    return [{c: guven} for c in metin]


class PuanlamaTesti(unittest.TestCase):
    def test_pozisyona_gore_karisiklik(self):
        pc = plaka.puanla_coz(dagilim("O6ABC12I"))
        self.assertEqual(pc[2], "06ABC121")  # rakam konumunda O->0, I->1
        self.assertEqual(pc[3], 2)
        pc = plaka.puanla_coz(dagilim("34A8C123"))
        self.assertEqual(pc[2], "34ABC123")  # harf konumunda 8->B
        self.assertEqual(plaka.puanla_coz(dagilim("340BC123"))[2], "34OBC123")  # harf konumunda 0->O

    def test_duzeltme_kapaliysa_reddeder(self):
        self.assertIsNone(plaka.puanla_coz(dagilim("O6ABC123"), duzeltme=False))
        self.assertIsNotNone(plaka.puanla_coz(dagilim("06ABC123"), duzeltme=False))

    def test_gecersiz_il_alternatife_kayar(self):
        d = dagilim("84ABC123")
        d[0] = {"8": 0.5, "3": 0.45}  # 84 gecersiz il, 34 gecerli
        self.assertEqual(plaka.puanla_coz(d)[2], "34ABC123")
        self.assertIsNone(plaka.puanla_coz(dagilim("99ABC123")))
        self.assertIsNone(plaka.puanla_coz(dagilim("00ABC123")))

    def test_en_yuksek_puanli_yapi_secilir(self):
        # 8 karakter: 34 + ABC + 123 (3 harf) ya da 34 + AB + C123 (C harf konumunda rakam degil) -> yalniz ilki gecerli
        self.assertEqual(plaka.puanla_coz(dagilim("34ABC123"))[1], "34 ABC 123")
        self.assertEqual(plaka.puanla_coz(dagilim("06AB1234"))[1], "06 AB 1234")
        self.assertIsNone(plaka.puanla_coz(dagilim("34ABCDE12")))  # rakam konumunda E duzeltilemez

    def test_yerel_il_bonusu_esitligi_bozar(self):
        d = dagilim("34ABC123")
        d[1] = {"4": 0.5, "1": 0.5}  # 34 mu 31 mi: ikisi de gecerli
        yok = plaka.puanla_coz(d, {"yerel_il_kodlari": []})
        var = plaka.puanla_coz(d, {"yerel_il_kodlari": ["31"]})
        self.assertEqual(var[2][:2], "31")
        self.assertIsNotNone(yok)


class RoiTesti(unittest.TestCase):
    def test_kirp_oran_ve_kayma(self):
        kare = np.arange(100 * 200, dtype=np.uint8).reshape(100, 200) % 255
        k, x0, y0 = roi.kirp(kare, [0.25, 0.5, 0.5, 0.25])
        self.assertEqual((x0, y0), (50, 50))
        self.assertEqual(k.shape, (25, 100))
        self.assertTrue(np.array_equal(k, kare[50:75, 50:150]))

    def test_tam_ve_bozuk_roi_kareyi_dondurur(self):
        kare = np.zeros((40, 60), np.uint8)
        for r in (None, [0, 0, 1, 1], [0, 0], "x", [0.1, 0.1, 0.01, 0.5]):
            k, x0, y0 = roi.kirp(kare, r)
            self.assertIs(k, kare)
            self.assertEqual((x0, y0), (0, 0))

    def test_sinir_disi_kirpilir(self):
        self.assertEqual(roi.normalize([0.8, 0.9, 0.5, 0.5]), [0.8, 0.9, 0.2, 0.1])

    def test_surukleden_ters_yon_ve_kucuk(self):
        self.assertEqual(roi.surukleden(150, 80, 50, 20, 200, 100), [0.25, 0.2, 0.5, 0.6])
        self.assertIsNone(roi.surukleden(10, 10, 12, 12, 200, 100))
        self.assertTrue(ayarlar._roi_gecerli([0.1, 0.1, 0.5, 0.5]))
        self.assertFalse(ayarlar._roi_gecerli([0.6, 0.1, 0.5, 0.5]))


def sentetik_plaka(golge=True):
    p = np.full((80, 376), 235, np.uint8)
    cv2.putText(p, "34ABC123", (12, 62), cv2.FONT_HERSHEY_SIMPLEX, 2.0, 20, 5, cv2.LINE_AA)
    if golge:
        p = (p.astype(np.float32) * np.linspace(0.35, 1.0, 376)[None, :]).astype(np.uint8)
    return p


class OnIslemeTesti(unittest.TestCase):
    def setUp(self):
        self.a = ayarlar.yukle("yok.json")
        self.on = onisleme.Onisleyici(self.a["on_isleme"])

    def test_profil_oto_parlakliktan(self):
        self.assertEqual(self.on.profil_coz("oto", np.full((50, 50), 20, np.uint8)), "gece")
        self.assertEqual(self.on.profil_coz("oto", np.full((50, 50), 150, np.uint8)), "gunduz")
        self.assertEqual(self.on.profil_coz("gece", np.full((50, 50), 150, np.uint8)), "gece")

    def test_golgeli_plaka_segmentlenir(self):
        seg = Segmentleyici(self.a["segmentleme"], 28, self.on)
        for profil in ("gunduz", "gece"):
            self.assertEqual(len(seg.bol(sentetik_plaka(), profil)), 8, profil)

    def test_otsu_yetersizse_adaptife_duser(self):
        duz = np.full((60, 120), 128, np.uint8)
        self.assertLess(onisleme.otsu_ayrim(duz, 128), 0.55)
        self.assertGreater(onisleme.otsu_ayrim(sentetik_plaka(False), 128), 0.55)
        self.assertEqual(self.on.ikili(duz, "gunduz").shape, duz.shape)  # cokmeden adaptif yola gider


class SahteTanima:
    def __init__(self, dogrulanmis, okumalar):
        self.dogrulanmis, self.okumalar, self.aciklama = dogrulanmis, list(okumalar), "sahte"

    def tani(self, karakterler):
        metin, guven = self.okumalar.pop(0)
        return TanimaSonucu(metin, [guven] * len(metin), self.dogrulanmis, "sahte")


class SahteDetector:
    def tespit_et(self, kare):
        return [Aday((10, 20, 100, 25), 1.0, 4.0, np.zeros((80, 376), np.uint8))]


class SahteSeg:
    def bol(self, plaka, profil=None):
        return [Karakter(np.zeros((28, 28), np.uint8), (0, 0, 1, 1))]


class BoruTesti(unittest.TestCase):
    def boru(self, dogrulanmis, okumalar):
        b = Boru(ayarlar.yukle("yok.json"), detector=SahteDetector(), tanima=SahteTanima(dogrulanmis, okumalar))
        b.seg = SahteSeg()
        return b

    def calistir(self, b, kare=None, n=None):
        kare = np.zeros((100, 200, 3), np.uint8) if kare is None else kare
        kam = {"id": "k1", "roi": [0.1, 0.2, 0.8, 0.7]}
        cikti = []
        for i in range(n or len(b.tanima.okumalar)):
            cikti.append(b.isle(kam, kare, 100.0 + i * 0.3))
        return cikti

    def test_konsensus_tek_kare_yanlisini_eler_ve_dogrular(self):
        b = self.boru(True, [("34ABC123", 0.95), ("34A8C123", 0.9), ("34ABC123", 0.95), ("34ABC123", 0.95)])
        c = self.calistir(b)
        self.assertEqual([len(x) for x in c], [0, 0, 1, 0])  # 3. karede konsensus, sonra tekillestirme
        o = c[2][0]
        self.assertEqual((o.plaka, o.kanonik, o.kare_adedi), ("34 ABC 123", "34ABC123", 3))
        self.assertTrue(o.dogrulanmis)
        self.assertEqual(b.son["k1"]["kutu"], (10 + 20, 20 + 20, 100, 25))  # ROI kaymasi eklenir (200*0.1, 100*0.2)

    def test_karisiklik_duzeltilir_guven_duser(self):
        b = self.boru(True, [("O6ABC123", 0.95)] * 3)
        o = self.calistir(b)[2][0]
        self.assertEqual(o.kanonik, "06ABC123")
        self.assertEqual(o.duzeltme, 1)
        self.assertLess(o.guven, 0.95)

    def test_dusuk_guven_dogrulanmamis(self):
        b = self.boru(True, [("34ABC123", 0.65)] * 3)  # min_guven (0.6) ustu, guven_esik (0.8) alti
        o = self.calistir(b)[2][0]
        self.assertFalse(o.dogrulanmis)

    def test_cok_dusuk_guven_olay_uretmez(self):
        b = self.boru(True, [("34ABC123", 0.5)] * 4)
        self.assertEqual(sum(len(x) for x in self.calistir(b)), 0)

    def test_kalibrasyon_kilidi_degismez(self):
        b = self.boru(False, [("34ABC123", 0.99)] * 3)
        self.assertTrue(b.kalibrasyon_modu)
        o = self.calistir(b)[2][0]
        self.assertFalse(o.dogrulanmis)  # tanima dogrulanmamis: guven yuksek olsa da kapi acilmaz

    def test_konsensus_kapaliysa_eski_teyit_yolu(self):
        a = ayarlar.yukle("yok.json")
        a["konsensus"]["etkin"] = False
        b = Boru(a, detector=SahteDetector(), tanima=SahteTanima(True, [("34ABC123", 0.9)] * 2))
        b.seg = SahteSeg()
        c = self.calistir(b)
        self.assertEqual([len(x) for x in c], [0, 1])  # teyit_kare=2


class KesifTesti(unittest.TestCase):
    YANIT = (b'<?xml version="1.0"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" '
             b'xmlns:a="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery">'
             b'<s:Body><d:ProbeMatches><d:ProbeMatch><a:EndpointReference><a:Address>urn:uuid:abc-123</a:Address></a:EndpointReference>'
             b'<d:Types>dn:NetworkVideoTransmitter</d:Types>'
             b'<d:Scopes>onvif://www.onvif.org/name/Giris%20Kamera onvif://www.onvif.org/hardware/DS-2CD2043 '
             b'onvif://www.onvif.org/location/otopark</d:Scopes>'
             b'<d:XAddrs>http://192.168.1.64:80/onvif/device_service</d:XAddrs></d:ProbeMatch></d:ProbeMatches></s:Body></s:Envelope>')

    def test_probe_xml_gecerli_ve_dogru_alanlar(self):
        x = kesif.probe_xml("uuid:test-1")
        self.assertIn(b"uuid:test-1", x)
        self.assertIn(b"NetworkVideoTransmitter", x)
        self.assertIn(b"discovery/Probe", x)
        self.assertIsNotNone(kesif._guvenli_xml(x))  # iyi bicimli
        self.assertNotEqual(kesif.probe_xml(), kesif.probe_xml())  # her Probe benzersiz MessageID

    def test_yanit_ayristirma(self):
        d = kesif.ayristir(self.YANIT, "192.168.1.64")
        self.assertEqual((d["ip"], d["ad"], d["model"], d["konum"]), ("192.168.1.64", "Giris Kamera", "DS-2CD2043", "otopark"))
        self.assertEqual(d["xaddrs"], ["http://192.168.1.64:80/onvif/device_service"])
        self.assertEqual(d["uuid"], "urn:uuid:abc-123")
        self.assertEqual(kesif.ayristir(self.YANIT, "")["ip"], "192.168.1.64")  # gonderen yoksa XAddrs'ten

    def test_ilgisiz_bozuk_ve_zararli_yanit_reddedilir(self):
        self.assertIsNone(kesif.ayristir(b"merhaba"))
        self.assertIsNone(kesif.ayristir(b"<a><b/></a>", "10.0.0.1"))
        self.assertIsNone(kesif.ayristir(b'<!DOCTYPE x [<!ENTITY a "aaaa">]>' + self.YANIT, "10.0.0.1"))
        self.assertIsNone(kesif.ayristir(self.YANIT + b" " * (kesif.MAX_XML + 1), "10.0.0.1"))

    def test_servis_adresi_yanit_verene_baglanir(self):
        self.assertEqual(kesif._servis_adresi("http://10.9.9.9:8000/onvif/media", "192.168.1.64"), "http://192.168.1.64:8000/onvif/media")

    def test_rtsp_oneri_ve_kimlik(self):
        o = kesif.rtsp_oneriler("192.168.1.64", "admin", "p@ss:1")
        self.assertTrue(any(a == "rtsp://admin:p%40ss%3A1@192.168.1.64:554/Streaming/Channels/101" for _, a in o))
        self.assertEqual(kesif.rtsp_adresi_ekle("rtsp://192.168.1.64:554/s1", "u", "p"), "rtsp://u:p@192.168.1.64:554/s1")
        self.assertEqual(kesif.rtsp_adresi_ekle("rtsp://x:y@192.168.1.64/s1", "u", "p"), "rtsp://x:y@192.168.1.64/s1")


if __name__ == "__main__":
    unittest.main()
