import copy
import unittest
from types import SimpleNamespace

from plaka_kenar import ayarlar
from plaka_kenar.boru import Okuma
from plaka_kenar.kapi import KapiSonucu
from plaka_kenar.karar import IzinDeposu
from plaka_kenar.kuyruk import OlayKuyrugu
from plaka_kenar.servis import Servis


class SahteKapi:
    def __init__(self, sonuc=KapiSonucu(True)):
        self.cagrilar, self.sonuc = [], sonuc

    def ac(self, kapi):
        self.cagrilar.append(kapi["id"])
        return self.sonuc


def kur(kapi):
    ayar = copy.deepcopy(ayarlar.VARSAYILAN)
    ayar["kapilar"] = [{"id": "k1", "yon_modu": "giris", "skp_uid": "U", "skp_token": "T"}]
    ayar["kameralar"] = [{"id": "c1", "kapi_id": "k1"}]
    ayar["sunucu"].update(etkin=True)  # olaylar kuyruga girer; ag'a cikilmaz (gonderim dongusu calismiyor)
    depo = IzinDeposu()
    depo.delta_uygula({"araclar": [{"plaka": "34ABC123", "daire_id": "D", "tur": "sakin"}]})
    boru = SimpleNamespace(kalibrasyon_modu=False, tanima=SimpleNamespace(aciklama=""), istatistik={})
    return Servis(ayar, boru=boru, kapi_surucu=kapi, depo=depo, kuyruk=OlayKuyrugu()), ayar["kameralar"][0]


def okuma(dogrulanmis=True, kanonik="34ABC123"):
    return Okuma("c1", "34 ABC 123", kanonik, 0.9, dogrulanmis, "test", 1_800_000_000.0)


class ServisTesti(unittest.TestCase):
    def test_kayitli_dogrulanmis_arac_acilir_ve_kuyruga_girer(self):
        kapi = SahteKapi()
        s, kam = kur(kapi)
        olay = s.okuma_isle(okuma(), kam)
        self.assertEqual((olay["karar"], kapi.cagrilar), ("acildi", ["k1"]))
        self.assertEqual(s.kuyruk.sayim()["bekleyen"], 1)
        self.assertEqual(s.depo.arac("34ABC123")["iceride"], 1)

    def test_kalibrasyon_ve_tanimsiz_asla_acmaz(self):
        kapi = SahteKapi()
        s, kam = kur(kapi)
        self.assertEqual(s.okuma_isle(okuma(dogrulanmis=False), kam)["karar"], "dogrulanmamis")
        self.assertEqual(s.okuma_isle(okuma(kanonik="06XYZ99"), kam)["karar"], "tanimsiz")
        self.assertEqual(kapi.cagrilar, [])
        self.assertEqual(s.kuyruk.sayim()["bekleyen"], 1)  # dogrulanmamis olay sunucuya gitmez (varsayilan)

    def test_cihaz_acamazsa_sahte_basari_yok(self):
        s, kam = kur(SahteKapi(KapiSonucu(False, "cihaz_yanit_vermedi")))
        olay = s.okuma_isle(okuma(), kam)
        self.assertEqual((olay["karar"], olay["neden"]), ("acma_basarisiz", "cihaz_yanit_vermedi"))
        self.assertEqual(s.depo.arac("34ABC123")["iceride"], 0)


class TanimaTesti(unittest.TestCase):
    def test_modelsiz_kalibrasyon_ve_onayli_tam_sablon(self):
        import tempfile
        from pathlib import Path

        import cv2
        import numpy as np

        from plaka_kenar import tanima
        from plaka_kenar.tanima import Karakter

        ayar = copy.deepcopy(ayarlar.VARSAYILAN)
        with tempfile.TemporaryDirectory() as d:
            t = tanima.olustur(ayar, Path(d))                        # model yok, sablon yok
            self.assertFalse(t.dogrulanmis)
            self.assertIn("KALIBRASYON", t.aciklama)
            rng = np.random.default_rng(1)
            ornekler = {}
            for s in ayar["tanima"]["siniflar"]:
                (Path(d) / "sablonlar" / s).mkdir(parents=True)
                ornekler[s] = (rng.random((28, 28)) * 255).astype(np.uint8)
                for i in range(3):
                    ok, buf = cv2.imencode(".png", ornekler[s])
                    (Path(d) / "sablonlar" / s / f"{i}.png").write_bytes(buf.tobytes())
            kar = [Karakter(ornekler[c], (0, 0, 1, 1)) for c in "34A"]
            tam = tanima.olustur(ayar, Path(d))                      # kapsam tam ama sablon_onayli=false
            self.assertEqual((tam.dogrulanmis, tam.tani(kar).dogrulanmis, tam.tani(kar).metin), (False, False, "34A"))
            ayar["tanima"]["sablon_onayli"] = True
            self.assertTrue(tanima.olustur(ayar, Path(d)).tani(kar).dogrulanmis)


if __name__ == "__main__":
    unittest.main()
