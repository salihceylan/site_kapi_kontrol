import unittest

from plaka_kenar.karar import IzinDeposu, KararMotoru
from plaka_kenar.kuyruk import OlayKuyrugu

try:
    from .yardimci import SIMDI, iso, sync_yaniti
except ImportError:  # python -m unittest discover -s testler
    from yardimci import SIMDI, iso, sync_yaniti

def depo(**ek):
    d = IzinDeposu()
    d.delta_uygula(sync_yaniti(**ek))
    return d


class KararTesti(unittest.TestCase):
    def k(self, d, plaka, kural="tum_yerler_bos", kara_cikis=False, **kw):
        return KararMotoru(d, kural, kara_cikis).karar(plaka, simdi=SIMDI, **kw)

    def test_temel_kararlar(self):
        d = depo()
        self.assertEqual(d.imlec(), "2026-10-29T12:00:00.000Z")
        self.assertEqual(d.revler(), {"vehicles": "v1", "permits": "p1", "blacklist": "b1"})
        self.assertTrue(self.k(d, "34SAK111").ac)
        self.assertEqual(self.k(d, "06YOK99").sonuc, "tanimsiz")            # listede yok: acilmaz
        self.assertEqual(self.k(d, "34BIT333").neden, "izin_suresi_doldu")
        self.assertEqual(self.k(d, "34GEL666").neden, "izin_henuz_baslamadi")
        self.assertTrue(self.k(d, "34BIT333", kapi_yon_modu="cikis").ac)     # sure dolmus misafir cikabilir

    def test_kara_liste_asla_acmaz(self):
        d = depo()
        r = self.k(d, "34KAR444")                                            # hem sakin hem kara listede: kara liste kazanir
        self.assertEqual((r.sonuc, r.neden, r.ac), ("kara_liste", "kara_liste", False))
        self.assertEqual(self.k(d, "06KAR000").sonuc, "kara_liste")          # yalniz kara listede (baska kaydi yok)
        self.assertEqual(self.k(d, "34KAR444", kapi_yon_modu="cikis").sonuc, "kara_liste")   # varsayilan: cikis da acilmaz
        self.assertTrue(self.k(d, "34KAR444", kara_cikis=True, kapi_yon_modu="cikis").ac)    # ayar: iceri hapsetme
        self.assertEqual(self.k(d, "34KAR444", kara_cikis=True).sonuc, "kara_liste")         # giris yine kapali

    def test_kalibrasyon_asla_acmaz(self):
        r = self.k(depo(), "34SAK111", dogrulanmis=False)
        self.assertEqual((r.sonuc, r.ac), ("dogrulanmamis", False))

    def test_bolum_degismedi_yerel_kopya_kalir_ve_sunucu_kurali_ezer(self):
        d = depo()
        d.delta_uygula({"server_time": "2026-10-29T12:05:00Z", "config": {"settings": {"guest_rule": "en_az_bir_bos"}},
                        "vehicles": {"rev": "v1", "unchanged": True}, "guest_permits": {"rev": "p1", "unchanged": True},
                        "blacklist": {"rev": "b2", "items": []}, "presence": {"full": False, "items": []}})
        self.assertTrue(self.k(d, "34SAK111").ac)                            # unchanged: silinmedi
        self.assertEqual(self.k(d, "34KAR444").sonuc, "ac")                  # kara liste bosaldi
        self.assertEqual(d.revler()["blacklist"], "b2")
        m = KararMotoru(d, "tum_yerler_bos")
        m.sunucu_kuralini_al()
        self.assertEqual(m.kural, "en_az_bir_yer_bos")

    def test_misafir_tum_yerler_bos(self):
        d = depo()
        self.assertTrue(self.k(d, "34MIS222").ac)                            # 2 yer, hepsi bos
        d.delta_uygula({"apartments": [{"id": 1, "parking_slots": 2, "inside_count": 1}]})
        self.assertEqual(self.k(d, "34MIS222").neden, "misafir_park_dolu")   # 1 yer bos yetmez (sahip kurali)
        self.assertTrue(self.k(d, "34MIS222", kural="en_az_bir_yer_bos").ac) # tek ayarla degisir
        d.delta_uygula({"apartments": [{"id": 1, "parking_slots": 2, "inside_count": 2}]})
        self.assertFalse(self.k(d, "34MIS222", kural="en_az_bir_yer_bos").ac)
        self.assertEqual(self.k(d, "34MIS555").neden, "misafir_park_yeri_yok")  # varsayilan 0 yer

    def test_cift_yon_icerideden_cikarilir_ve_yerel_durum(self):
        d = depo()
        m = KararMotoru(d)
        self.assertEqual(m.karar("34SAK111", "cift", simdi=SIMDI).yon, "giris")
        d.iceride_ayarla("34SAK111", True)                                   # acma basarili -> iceride
        self.assertEqual(d.daire("1")["iceride"], 1)
        self.assertEqual(m.karar("34SAK111", "cift", simdi=SIMDI).yon, "cikis")
        self.assertEqual(m.karar("34SAK111", "cift", "giris", simdi=SIMDI).yon, "giris")  # kamera yonu onceliklidir
        d.iceride_ayarla("34SAK111", False)
        self.assertEqual(d.daire("1")["iceride"], 0)

    def test_iceride_goruntusu_gonderilmemis_olay_varken_uygulanmaz(self):
        d = depo()
        d.iceride_ayarla("34SAK111", True)
        eski_imlec = d.imlec()
        d.delta_uygula(sync_yaniti(server_time="2026-10-29T12:10:00Z", presence={"full": True, "items": []},
                                   apartments=[{"id": 1, "parking_slots": 2, "inside_count": 0}]), iceride_uygula=False)
        self.assertEqual((d.daire("1")["iceride"], d.arac("34SAK111")["iceride"]), (1, 1))   # yerel iyimser durum korundu
        self.assertEqual(d.imlec(), eski_imlec)                                               # imlec ilerlemedi
        d.delta_uygula(sync_yaniti(server_time="2026-10-29T12:11:00Z",
                                   presence={"full": False, "items": [{"plate": "34SAK111", "apartment_id": 1, "kind": "resident", "inside": False,
                                                                       "since_at": "2026-10-29T12:09:00Z"}]},
                                   apartments=[{"id": 1, "parking_slots": 2, "inside_count": 0}]))
        self.assertEqual((d.daire("1")["iceride"], d.arac("34SAK111")["iceride"]), (0, 0))   # sunucu farki uygulandi

    def test_cok_izin_en_gec_biten_kazanir_ve_sakin_misafire_ustundur(self):
        d = depo(guest_permits={"rev": "p2", "items": [
            {"id": 1, "plate": "34SAK111", "apartment_id": 1, "valid_from": None, "valid_until": iso(SIMDI + 10)},
            {"id": 2, "plate": "34ABC123", "apartment_id": 1, "valid_from": None, "valid_until": iso(SIMDI + 10)},
            {"id": 3, "plate": "34ABC123", "apartment_id": 1, "valid_from": None, "valid_until": iso(SIMDI + 900)}]})
        self.assertEqual(d.arac("34SAK111")["tur"], "sakin")
        self.assertEqual(d.arac("34ABC123")["gecerli_bitis"], SIMDI + 900)


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

    def test_gecici_hata_olayi_oldurmez_kalici_hata_oldurur_saklama_suresi_siler(self):
        q = OlayKuyrugu()
        q.ekle({"event_id": "a"})
        q.ekle({"event_id": "b"})
        for i in range(60):                                                  # uzun kesinti: yuzlerce gecici hata
            q.basarisiz(["a"], simdi=SIMDI + i * 1000)
        self.assertEqual(q.sayim()["bekleyen"], 2)
        q.basarisiz(["b"], kalici=True, simdi=SIMDI)
        self.assertEqual(q.sayim(), {"bekleyen": 1, "gonderilen": 0, "hatali": 1})
        self.assertEqual(q.temizle(7, simdi=SIMDI + 8 * 86400 + 1e9), 2)     # saklama suresini asan (gonderilmemis dahil) silinir


if __name__ == "__main__":
    unittest.main()
