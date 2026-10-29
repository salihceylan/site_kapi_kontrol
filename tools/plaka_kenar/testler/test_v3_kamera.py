"""Sozlesme v3 - sunucudan inen kamera tanimlari: yerel ayarla birlestirme (yerel korunur, sunucu satiri eklenir / guncellenir / silinir, cakisma,
kapi eslesmesi), akislarin farkla yenilenmesi, dosyaya isleme (yalniz sunucu satirlari) ve sync entegrasyonu."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from plaka_kenar import ayarlar, kamerasync
from plaka_kenar.karar import IzinDeposu
from plaka_kenar.kuyruk import OlayKuyrugu
from plaka_kenar.servis import Servis

try:
    from .test_servis import SahteKapi, SahteSunucu, kur
    from .yardimci import sync_yaniti
except ImportError:  # python -m unittest discover -s testler
    from test_servis import SahteKapi, SahteSunucu, kur
    from yardimci import sync_yaniti

SIFRE = "P@rola/1"


def sunucu_kamera(cid=7, **ek):
    k = {"camera_id": cid, "name": f"Kamera {cid}", "brand": "hikvision", "host": "192.168.1.64", "port": 554,
         "rtsp_url": "rtsp://192.168.1.64:554/Streaming/Channels/101", "username": "admin", "password": SIFRE, "gate_id": 3, "direction": "giris"}
    k.update(ek)
    return k


def ayar_kur(**ek):
    a = copy.deepcopy(ayarlar.VARSAYILAN)
    a["kapilar"] = [{"id": "ana", "yon_modu": "cift", "sunucu_id": 3}, {"id": "yan", "yon_modu": "giris", "sunucu_id": 4}]
    a["kameralar"] = [{"id": "yerel1", "ad": "Elle", "url": "rtsp://10.0.0.9/x", "mod": "akis", "fps": 3, "kapi_id": "ana", "yon": "cikis", "etkin": True}]
    a.update(ek)
    return a


class BirlestirTesti(unittest.TestCase):
    def test_sunucu_satiri_eklenir_isaretlenir_kapi_ve_yon_eslesir_yerel_korunur(self):
        a = ayar_kur()
        yerel = a["kameralar"][0]
        f = kamerasync.birlestir(a, [sunucu_kamera(7), sunucu_kamera(8, gate_id=None, direction="auto"), sunucu_kamera(9, gate_id=99)])
        self.assertTrue(f["degisti"])
        self.assertEqual((f["eklenen"], f["silinen"], f["kapisiz"]), (["s7", "s8", "s9"], [], ["s9"]))
        self.assertIs(a["kameralar"][0], yerel)                           # yerel satir ayni nesne, oldugu gibi
        s7, s8, s9 = a["kameralar"][1:]
        self.assertEqual((s7["id"], s7["kaynak"], s7["sunucu_id"], s7["kapi_id"], s7["yon"], s7["etkin"], s7["mod"], s7["fps"]),
                         ("s7", "sunucu", 7, "ana", "giris", True, "akis", 3))
        self.assertEqual((s8["kapi_id"], s8["yon"]), ("", ""))             # kapi yok + 'auto' yon => bos
        self.assertEqual(s9["kapi_id"], "")                                # sunucu kapi 99'u yerelde eslesen yok: kapi acilmaz
        self.assertEqual(s7["url"], "rtsp://admin:P%40rola%2F1@192.168.1.64:554/Streaming/Channels/101")   # kimlik URL'de
        self.assertEqual(s7["ad"], "Kamera 7")
        self.assertNotIn("_kapi_yok", s7)

    def test_ayni_veri_ikinci_kez_degisiklik_yok_ayni_nesne(self):
        a = ayar_kur()
        kamerasync.birlestir(a, [sunucu_kamera(7)])
        nesne = a["kameralar"][1]
        nesne["roi"] = [0.1, 0.1, 0.5, 0.5]                                # yerelde ayarlanan alanlar sunucu tarafindan ezilmez
        nesne["fps"] = 5
        f = kamerasync.birlestir(a, [sunucu_kamera(7)])
        self.assertFalse(f["degisti"])
        self.assertIs(a["kameralar"][1], nesne)
        self.assertEqual((nesne["roi"], nesne["fps"]), ([0.1, 0.1, 0.5, 0.5], 5))

    def test_guncelleme_ayni_nesnede_url_degisince_akis_yeniden_baslar_yon_degisince_baslamaz(self):
        a = ayar_kur()
        kamerasync.birlestir(a, [sunucu_kamera(7)])
        nesne = a["kameralar"][1]
        f = kamerasync.birlestir(a, [sunucu_kamera(7, direction="cikis", name="Yeni ad")])
        self.assertEqual((f["guncellenen"], f["yeniden_baslat"]), (["s7"], []))
        self.assertIs(a["kameralar"][1], nesne)
        self.assertEqual((nesne["yon"], nesne["ad"]), ("cikis", "Yeni ad"))
        f = kamerasync.birlestir(a, [sunucu_kamera(7, direction="cikis", name="Yeni ad", password="baska")])
        self.assertEqual((f["guncellenen"], f["yeniden_baslat"]), (["s7"], ["s7"]))   # kimlik degisti => yeniden baglan
        self.assertIn("baska", nesne["url"])

    def test_sunucudan_gelmeyen_sunucu_satiri_silinir_yerel_asla(self):
        a = ayar_kur()
        kamerasync.birlestir(a, [sunucu_kamera(7), sunucu_kamera(8)])
        f = kamerasync.birlestir(a, [sunucu_kamera(8)])
        self.assertEqual((f["silinen"], f["yeniden_baslat"]), (["s7"], ["s7"]))
        self.assertEqual([k["id"] for k in a["kameralar"]], ["yerel1", "s8"])
        f = kamerasync.birlestir(a, [])                                    # sunucuda hic kamera kalmadi
        self.assertEqual([k["id"] for k in a["kameralar"]], ["yerel1"])
        self.assertTrue(f["degisti"])

    def test_ayni_sunucu_idli_yerel_satir_varsa_yerel_kazanir(self):
        a = ayar_kur()
        a["kameralar"][0]["sunucu_id"] = 7                                 # yerel satir ayni sunucu kamerasina baglanmis
        f = kamerasync.birlestir(a, [sunucu_kamera(7), sunucu_kamera(8)])
        self.assertEqual(f["eklenen"], ["s8"])
        self.assertEqual([k["id"] for k in a["kameralar"]], ["yerel1", "s8"])

    def test_gecersiz_satirlar_atlanir_ve_none_hicbir_sey_yapmaz(self):
        a = ayar_kur()
        f = kamerasync.birlestir(a, [sunucu_kamera(0), sunucu_kamera(5, rtsp_url=""), sunucu_kamera(6, rtsp_url="http://x"), "bozuk", None,
                                     sunucu_kamera(7), sunucu_kamera(7)])
        self.assertEqual(f["eklenen"], ["s7"])                              # tekrar eden kimlik yok sayilir
        onceki = list(a["kameralar"])
        self.assertFalse(kamerasync.birlestir(a, None)["degisti"])
        self.assertEqual(a["kameralar"], onceki)

    def test_dogrula_kapisiz_sunucu_kamerasini_uyarir(self):
        a = ayar_kur()
        kamerasync.birlestir(a, [sunucu_kamera(9, gate_id=99)])
        self.assertTrue(any("sunucudan" in u and "kapi acilmaz" in u for u in ayarlar.dogrula(a)))


class ServisKameraTesti(unittest.TestCase):
    def servis(self, ayar=None, yol=None):
        a = ayar or ayar_kur()
        a["sunucu"].update(etkin=True, adres="https://x.test", cihaz_anahtari="12." + "ab" * 24)
        boru = mock.Mock(kalibrasyon_modu=False, istatistik={})
        return Servis(a, boru=boru, kapi_surucu=SahteKapi(), depo=IzinDeposu(), kuyruk=OlayKuyrugu(), sunucu=SahteSunucu(), ayar_yolu=yol)

    def test_akislar_farkla_yenilenir_silinen_durur_yeni_baslar(self):
        with mock.patch("plaka_kenar.servis.yakalama.AkisKaynagi") as Akis:
            akislar = []

            def uret(kam, *a, **k):
                m = mock.Mock(kam=kam, dur=mock.Mock())
                akislar.append(m)
                return m

            Akis.side_effect = uret
            s = self.servis()
            s._calisiyor = True                                           # baslat() cagrilmadan: arka plan thread'leri acilmasin
            s.kameralari_birlestir([sunucu_kamera(7), sunucu_kamera(8)])
            self.assertEqual(sorted(a.kam["id"] for a in s._akislar), ["s7", "s8"])
            self.assertEqual(s.kamera_surum, 1)
            ilk7 = s.akis("s7")
            s.kameralari_birlestir([sunucu_kamera(7), sunucu_kamera(8)])   # degisiklik yok
            self.assertEqual((len(akislar), s.kamera_surum), (2, 1))
            s.kameralari_birlestir([sunucu_kamera(8, password="yeni")])    # s7 silindi, s8 kimlik degisti
            ilk7.dur.set.assert_called()
            self.assertEqual(sorted(a.kam["id"] for a in s._akislar), ["s8"])
            self.assertEqual(len(akislar), 3)                              # s8 yeniden baslatildi
            self.assertNotIn("s7", s.kam_durum)

    def test_calismiyorken_akis_baslatilmaz_ama_ayar_guncellenir(self):
        with mock.patch("plaka_kenar.servis.yakalama.AkisKaynagi") as Akis:
            s = self.servis()
            s.kameralari_birlestir([sunucu_kamera(7)])
            Akis.assert_not_called()
            self.assertEqual([k["id"] for k in s.ayar["kameralar"]], ["yerel1", "s7"])

    def test_dosyaya_yalniz_sunucu_satirlari_islenir_dosyadaki_yerel_ve_diger_ayarlar_korunur(self):
        with tempfile.TemporaryDirectory() as d:
            yol = Path(d) / "ayarlar.json"
            yol.write_text(json.dumps({"surum": 1, "karar": {"misafir_kurali": "en_az_bir_yer_bos"},
                                       "kameralar": [{"id": "diskte", "url": "rtsp://d/x"}, {"id": "s1", "kaynak": "sunucu", "url": "eski"}]}), encoding="utf-8")
            s = self.servis(yol=yol)
            s.ayar["kameralar"][0]["url"] = "rtsp://kaydedilmemis-degisiklik/x"   # arayuzde henuz Kaydet'e basilmamis
            s.kameralari_birlestir([sunucu_kamera(7)])
            dosya = json.loads(yol.read_text(encoding="utf-8"))
            yuklenen = ayarlar.yukle(yol)                                          # yeniden acilista sunucu kamerasi hazir (cevrimdisi dahil)
        self.assertEqual([k["id"] for k in dosya["kameralar"]], ["diskte", "s7"])      # eski s1 gitti, yerel 'diskte' degismedi
        self.assertEqual(dosya["kameralar"][0]["url"], "rtsp://d/x")
        self.assertEqual(dosya["karar"]["misafir_kurali"], "en_az_bir_yer_bos")
        self.assertEqual(dosya["kameralar"][1]["kaynak"], "sunucu")
        self.assertIn("s7", [k["id"] for k in yuklenen["kameralar"]])

    def test_yol_verilmezse_dosyaya_yazilmaz(self):
        s = self.servis()
        with mock.patch("plaka_kenar.servis.ayarmod.sunucu_kameralarini_yaz") as yaz:
            s.kameralari_birlestir([sunucu_kamera(7)])
        yaz.assert_not_called()

    def test_senkron_config_cameras_birlestirilir_alan_yoksa_yerel_kameralara_dokunulmaz(self):
        sunucu = SahteSunucu(yanit=sync_yaniti())
        s, _ = kur(SahteKapi(), sunucu)
        s.depo = IzinDeposu()
        s.motor.depo = s.depo
        s.ayar["kapilar"][0]["sunucu_id"] = 3
        onceki = [k["id"] for k in s.ayar["kameralar"]]
        s.senkronla()                                                         # eski sunucu: config.cameras yok
        self.assertEqual([k["id"] for k in s.ayar["kameralar"]], onceki)
        y = sync_yaniti()
        y["config"]["cameras"] = [sunucu_kamera(21)]
        y["config"]["settings"].update(snapshot_interval_seconds=3, snapshot_idle_interval_seconds=20)
        s.sunucu = SahteSunucu(yanit=y)
        s.senkronla()
        self.assertEqual([k["id"] for k in s.ayar["kameralar"]], onceki + ["s21"])
        self.assertEqual(s.ayar["kameralar"][-1]["kapi_id"], "k1")           # sunucu kapi 3 -> yerel 'k1'
        self.assertEqual(s.goruntu_sunucu, {"aralik": 3, "bosta": 20})
        y["config"]["cameras"] = []
        s.sunucu = SahteSunucu(yanit=y)
        s.senkronla()
        self.assertEqual([k["id"] for k in s.ayar["kameralar"]], onceki)


if __name__ == "__main__":
    unittest.main()
