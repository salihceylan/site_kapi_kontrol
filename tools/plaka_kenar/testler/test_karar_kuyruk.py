import unittest

from plaka_kenar.karar import IzinDeposu, KararMotoru
from plaka_kenar.kuyruk import OlayKuyrugu

SIMDI = 1_800_000_000.0


def depo(**ek):
    d = IzinDeposu()
    d.delta_uygula({"imlec": "7", "araclar": [
        {"plaka": "34 SAK 111", "daire_id": "D1", "tur": "sakin"},
        {"plaka": "34 MIS 222", "daire_id": "D1", "tur": "misafir", "gecerli_bitis": SIMDI + 3600},
        {"plaka": "34 BIT 333", "daire_id": "D1", "tur": "misafir", "gecerli_bitis": SIMDI - 1},
        {"plaka": "34 KAR 444", "daire_id": "D1", "tur": "sakin", "kara_liste": True},
        {"plaka": "34 MIS 555", "daire_id": "D0", "tur": "misafir"},
    ], "daireler": [{"daire_id": "D1", "park_yeri": 2, "iceride": 0}, {"daire_id": "D0", "park_yeri": 0}], **ek})
    return d


class KararTesti(unittest.TestCase):
    def k(self, d, plaka, kural="tum_yerler_bos", **kw):
        return KararMotoru(d, kural).karar(plaka, simdi=SIMDI, **kw)

    def test_temel_kararlar(self):
        d = depo()
        self.assertEqual(d.imlec(), "7")
        self.assertTrue(self.k(d, "34SAK111").ac)
        self.assertEqual(self.k(d, "06YOK99").sonuc, "tanimsiz")            # listede yok: acilmaz
        self.assertEqual(self.k(d, "34KAR444").neden, "kara_liste")
        self.assertEqual(self.k(d, "34BIT333").neden, "izin_suresi_doldu")
        self.assertTrue(self.k(d, "34BIT333", kapi_yon_modu="cikis").ac)     # sure dolmus misafir cikabilir

    def test_kalibrasyon_asla_acmaz(self):
        r = self.k(depo(), "34SAK111", dogrulanmis=False)
        self.assertEqual((r.sonuc, r.ac), ("dogrulanmamis", False))

    def test_misafir_tum_yerler_bos(self):
        d = depo()
        self.assertTrue(self.k(d, "34MIS222").ac)                            # 2 yer, hepsi bos
        d.delta_uygula({"daireler": [{"daire_id": "D1", "park_yeri": 2, "iceride": 1}]})
        self.assertEqual(self.k(d, "34MIS222").neden, "misafir_park_dolu")   # 1 yer bos yetmez (sahip kurali)
        self.assertTrue(self.k(d, "34MIS222", kural="en_az_bir_yer_bos").ac) # tek ayarla degisir
        d.delta_uygula({"daireler": [{"daire_id": "D1", "park_yeri": 2, "iceride": 2}]})
        self.assertFalse(self.k(d, "34MIS222", kural="en_az_bir_yer_bos").ac)
        self.assertEqual(self.k(d, "34MIS555").neden, "misafir_park_yeri_yok")  # varsayilan 0 yer

    def test_cift_yon_icerideden_cikarilir_ve_yerel_durum(self):
        d = depo()
        m = KararMotoru(d)
        self.assertEqual(m.karar("34SAK111", "cift", simdi=SIMDI).yon, "giris")
        d.iceride_ayarla("34SAK111", True)                                   # acma basarili -> iceride
        self.assertEqual(d.daire("D1")["iceride"], 1)
        self.assertEqual(m.karar("34SAK111", "cift", simdi=SIMDI).yon, "cikis")
        self.assertEqual(m.karar("34SAK111", "cift", "giris", simdi=SIMDI).yon, "giris")  # kamera yonu onceliklidir
        d.iceride_ayarla("34SAK111", False)
        self.assertEqual(d.daire("D1")["iceride"], 0)


class KuyrukTesti(unittest.TestCase):
    def test_idempotent_ve_geri_cekilme(self):
        q = OlayKuyrugu()
        q.ekle({"event_id": "e1", "plaka": "34 SAK 111"})
        q.ekle({"event_id": "e1", "plaka": "tekrar"})                        # ayni id: ikinci kayit yok
        self.assertEqual(q.sayim()["bekleyen"], 1)
        self.assertEqual([o["event_id"] for o in q.bekleyenler(simdi=SIMDI)], ["e1"])
        q.basarisiz(["e1"], simdi=SIMDI)
        self.assertEqual(q.bekleyenler(simdi=SIMDI), [])                     # geri cekilme suruyor
        self.assertEqual(len(q.bekleyenler(simdi=SIMDI + 400)), 1)
        q.gonderildi(["e1"])
        self.assertEqual(q.sayim(), {"bekleyen": 0, "gonderilen": 1, "hatali": 0})


if __name__ == "__main__":
    unittest.main()
