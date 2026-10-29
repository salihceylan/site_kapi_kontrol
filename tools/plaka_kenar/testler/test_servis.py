import copy
import unittest
from types import SimpleNamespace

from plaka_kenar import ayarlar
from plaka_kenar.boru import Okuma
from plaka_kenar.kapi import KapiSonucu
from plaka_kenar.karar import IzinDeposu
from plaka_kenar.kuyruk import OlayKuyrugu
from plaka_kenar.servis import Servis
from plaka_kenar.sunucu import SunucuHatasi, SunucuIstemcisi

try:
    from .yardimci import SIMDI, sync_yaniti
except ImportError:  # python -m unittest discover -s testler
    from yardimci import SIMDI, sync_yaniti

ANAHTAR = "12." + "ab" * 24


class SahteKapi:
    def __init__(self, sonuc=KapiSonucu(True)):
        self.cagrilar, self.sonuc = [], sonuc

    def ac(self, kapi):
        self.cagrilar.append(kapi["id"])
        return self.sonuc


class SahteSunucu:
    """SunucuIstemcisi yerine: cagrilari kaydeder; hatalar sirayla verilebilir."""

    def __init__(self, hatalar=None, yanit=None):
        self.olaylar, self.hatalar, self.yanit, self.senkron_cagrilari, self.kalp = [], list(hatalar or []), yanit, [], []
        self.kayit_cagrilari = []

    def uc_etkin(self, ad):
        return True

    def olay(self, govde):
        if self.hatalar:
            h = self.hatalar.pop(0)
            if h is not None:
                raise h
        self.olaylar.append(govde)

    def kayit(self, surum):
        self.kayit_cagrilari.append(surum)
        return SimpleNamespace(govde={"intervals": {"heartbeat_seconds": 30, "sync_seconds": 75}})

    def senkron(self, imlec, revler):
        self.senkron_cagrilari.append((imlec, dict(revler)))
        return SimpleNamespace(govde=self.yanit)

    def kalp_atisi(self, govde):
        self.kalp.append(govde)
        return SimpleNamespace(govde={"intervals": {"heartbeat_seconds": 20}})


def kur(kapi, sunucu=None, sunucu_id=7):
    ayar = copy.deepcopy(ayarlar.VARSAYILAN)
    ayar["kapilar"] = [{"id": "k1", "yon_modu": "giris", "skp_uid": "U", "skp_token": "T"}]
    ayar["kameralar"] = [{"id": "c1", "kapi_id": "k1", "sunucu_id": sunucu_id}]
    ayar["sunucu"].update(etkin=True, adres="https://x.test", cihaz_anahtari=ANAHTAR)  # olaylar kuyruga girer; ag'a cikilmaz
    depo = IzinDeposu()
    depo.delta_uygula(sync_yaniti())
    boru = SimpleNamespace(kalibrasyon_modu=False, tanima=SimpleNamespace(aciklama=""), istatistik={})
    s = Servis(ayar, boru=boru, kapi_surucu=kapi, depo=depo, kuyruk=OlayKuyrugu(), sunucu=sunucu)
    return s, ayar["kameralar"][0]


def okuma(dogrulanmis=True, kanonik="34SAK111"):
    return Okuma("c1", "34 SAK 111", kanonik, 0.9, dogrulanmis, "test", SIMDI)


class ServisTesti(unittest.TestCase):
    def test_kayitli_dogrulanmis_arac_acilir_ve_sozlesme_govdesiyle_kuyruga_girer(self):
        kapi = SahteKapi()
        s, kam = kur(kapi)
        olay = s.okuma_isle(okuma(), kam)
        self.assertEqual((olay["karar"], kapi.cagrilar), ("acildi", ["k1"]))
        self.assertEqual(s.kuyruk.sayim()["bekleyen"], 1)
        self.assertEqual(s.depo.arac("34SAK111")["iceride"], 1)
        g = s.kuyruk.bekleyenler()[0]
        self.assertEqual((g["camera_id"], g["plate"], g["decision"], g["direction"], g["reason"]), (7, "34SAK111", "acildi", "giris", "kayitli_arac"))
        self.assertEqual((g["schema_version"], g["seen_at"][:10], g["confidence"]), (2, "2027-01-15", 0.9))
        self.assertRegex(g["event_id"], r"^[A-Za-z0-9_-]{8,64}$")
        self.assertNotIn("gate_id", g)                                       # kapi sunucu_id'si yok: sunucu kameradan turetir

    def test_kalibrasyon_ve_tanimsiz_asla_acmaz_dogrulanmamis_sunucuya_gitmez(self):
        kapi = SahteKapi()
        s, kam = kur(kapi)
        self.assertEqual(s.okuma_isle(okuma(dogrulanmis=False), kam)["karar"], "dogrulanmamis")
        self.assertEqual(s.okuma_isle(okuma(kanonik="06XYZ99"), kam)["karar"], "tanimsiz")
        self.assertEqual(kapi.cagrilar, [])
        self.assertEqual([g["decision"] for g in s.kuyruk.bekleyenler()], ["tanimsiz"])

    def test_kara_liste_acmaz_ve_kara_liste_kararini_bildirir(self):
        kapi = SahteKapi()
        s, kam = kur(kapi)
        olay = s.okuma_isle(okuma(kanonik="34KAR444"), kam)
        self.assertEqual((olay["karar"], olay["neden"], kapi.cagrilar), ("kara_liste", "kara_liste", []))
        g = s.kuyruk.bekleyenler()[0]
        self.assertEqual((g["decision"], g["reason"]), ("kara_liste", "kara_liste"))
        self.assertEqual(s.depo.arac("34KAR444")["iceride"], 0)

    def test_cihaz_acamazsa_sahte_basari_yok_ve_red_olarak_bildirilir(self):
        s, kam = kur(SahteKapi(KapiSonucu(False, "cihaz_yanit_vermedi")))
        olay = s.okuma_isle(okuma(), kam)
        self.assertEqual((olay["karar"], olay["neden"]), ("acma_basarisiz", "cihaz_yanit_vermedi"))
        self.assertEqual(s.depo.arac("34SAK111")["iceride"], 0)
        g = s.kuyruk.bekleyenler()[0]
        self.assertEqual((g["decision"], g["reason"]), ("red", "cihaz_yanit_vermedi"))

    def test_sunucu_id_olmayan_kameranin_olayi_kuyruga_girmez(self):
        s, kam = kur(SahteKapi(), sunucu_id="")
        s.okuma_isle(okuma(), kam)
        self.assertEqual(s.kuyruk.sayim()["bekleyen"], 0)
        self.assertTrue(any("sunucu_id" in u for u in ayarlar.dogrula(s.ayar)))

    def test_olaylar_tek_tek_gider_kalici_hata_o_olayi_isaretler_gecici_hata_turu_keser(self):
        sunucu = SahteSunucu(hatalar=[SunucuHatasi("HTTP 400", kalici=True, kod=400)])
        s, kam = kur(SahteKapi(), sunucu)
        for plaka in ("34SAK111", "06XYZ99", "06XYZ98"):
            s.okuma_isle(okuma(kanonik=plaka), kam)
        self.assertEqual(s.olay_gonder(), 2)                                 # ilki kalici hata (atlanir), kalan ikisi gider
        self.assertEqual(len(sunucu.olaylar), 2)
        self.assertEqual(s.kuyruk.sayim(), {"bekleyen": 0, "gonderilen": 2, "hatali": 1})
        sunucu2 = SahteSunucu(hatalar=[SunucuHatasi("ConnectionError"), None])
        s2, kam2 = kur(SahteKapi(), sunucu2)
        s2.okuma_isle(okuma(kanonik="06XYZ99"), kam2)
        s2.okuma_isle(okuma(kanonik="06XYZ98"), kam2)
        self.assertEqual(s2.olay_gonder(), 0)                                # ag hatasi: tur kesilir, olaylar kuyrukta
        self.assertEqual(s2.kuyruk.sayim()["bekleyen"], 2)

    def test_senkron_claim_aralik_rev_ve_gonderilmemis_olay_korumasi(self):
        sunucu = SahteSunucu(yanit=sync_yaniti())
        s, kam = kur(SahteKapi(), sunucu)
        s.depo = IzinDeposu()
        s.motor.depo = s.depo
        self.assertGreater(s.senkronla(), 0)
        self.assertEqual(sunucu.kayit_cagrilari, [ayarlar.SURUM])
        self.assertEqual(s.ayar["sunucu"]["kalp_atisi_aralik_sn"], 45)       # claim 30 -> sync config.settings 45 (sonra gelen kazanir)
        self.assertEqual(s.ayar["sunucu"]["senkron_aralik_sn"], 90)
        self.assertEqual(sunucu.senkron_cagrilari[0], ("", {"vehicles": "", "permits": "", "blacklist": ""}))
        sunucu.yanit = sync_yaniti(vehicles={"rev": "v1", "unchanged": True}, server_time="2026-10-29T12:05:00Z")
        s.senkronla()
        self.assertEqual(sunucu.senkron_cagrilari[1], ("2026-10-29T12:00:00.000Z", {"vehicles": "v1", "permits": "p1", "blacklist": "b1"}))
        self.assertEqual(len(sunucu.kayit_cagrilari), 1)                     # claim yalniz bir kez
        # gonderilmemis yerel olay varken sunucunun "iceride" gorunumu uygulanmaz
        s.okuma_isle(okuma(), kam)
        s.sunucu = SahteSunucu(hatalar=[SunucuHatasi("ConnectionError")] * 5, yanit=sync_yaniti(server_time="2026-10-29T12:30:00Z"))
        s.senkronla()
        self.assertEqual(s.depo.arac("34SAK111")["iceride"], 1)
        self.assertEqual(s.depo.imlec(), "2026-10-29T12:05:00Z")

    def test_kalp_atisi_sozlesme_govdesi(self):
        sunucu = SahteSunucu()
        s, kam = kur(SahteKapi(), sunucu)
        s.ayar["kameralar"].append({"id": "c2", "etkin": True})              # sunucu_id'siz kamera gonderilmez
        s.kam_durum["c1"] = {"son_kare": SIMDI, "son_okuma": 0}
        s.kalp_atisi()
        g = sunucu.kalp[0]
        self.assertEqual((g["app_version"], g["queue_depth"], len(g["cameras"])), (ayarlar.SURUM, 0, 1))
        self.assertEqual(g["cameras"][0]["camera_id"], 7)
        self.assertTrue(g["cameras"][0]["last_frame_at"].startswith("2027-01-15"))
        self.assertNotIn("last_read_at", g["cameras"][0])
        self.assertEqual(s.ayar["sunucu"]["kalp_atisi_aralik_sn"], 20)


class IstemciTesti(unittest.TestCase):
    """Sozlesme yollari / basliklari / sorgu parametreleri (sahte requests oturumu)."""

    class Oturum:
        def __init__(self, kod=200, govde=None):
            self.cagrilar, self.kod, self.govde = [], kod, govde or {}

        def request(self, yontem, url, **kw):
            self.cagrilar.append((yontem, url, kw))
            return SimpleNamespace(status_code=self.kod, content=b"{}", json=lambda: self.govde)

    def istemci(self, oturum):
        s = copy.deepcopy(ayarlar.VARSAYILAN["sunucu"])
        s.update(etkin=True, adres="https://api.test/", cihaz_anahtari=ANAHTAR)
        return SunucuIstemcisi(s, oturum)

    def test_gercek_yollar_baslik_ve_parametreler(self):
        o = self.Oturum()
        c = self.istemci(o)
        c.kayit("0.2.0")
        c.senkron("2026-10-29T12:00:00Z", {"vehicles": "v1", "permits": "", "blacklist": "b1"})
        c.olay({"schema_version": 2, "event_id": "evt-00000001"})
        c.kalp_atisi({"app_version": "0.2.0", "cameras": []})
        yollar = [(m, u) for m, u, _ in o.cagrilar]
        self.assertEqual(yollar, [("POST", "https://api.test/edge/plate/v1/claim"), ("GET", "https://api.test/edge/plate/v1/sync"),
                                  ("POST", "https://api.test/edge/plate/v1/events"), ("POST", "https://api.test/edge/plate/v1/heartbeat")])
        self.assertEqual(o.cagrilar[0][2]["headers"]["Authorization"], f"Bearer {ANAHTAR}")
        self.assertEqual(o.cagrilar[0][2]["json"], {"schema_version": 2, "app_version": "0.2.0"})
        self.assertEqual(o.cagrilar[1][2]["params"], {"schema_version": 2, "updated_since": "2026-10-29T12:00:00Z",
                                                      "vehicles_rev": "v1", "blacklist_rev": "b1"})
        self.assertEqual(o.cagrilar[2][2]["json"]["event_id"], "evt-00000001")          # tek olay govdesi, dizi degil
        self.assertEqual(o.cagrilar[3][2]["json"]["schema_version"], 2)

    def test_hata_siniflandirmasi_401_403_gecici_diger_4xx_kalici(self):
        for kod, kalici in ((400, True), (404, True), (409, True), (401, False), (403, False), (429, False), (503, False)):
            with self.assertRaises(SunucuHatasi) as ctx:
                self.istemci(self.Oturum(kod, {"code": "X"})).olay({})
            self.assertEqual(ctx.exception.kalici, kalici, kod)

    def test_ayar_uyarilari(self):
        ayar = copy.deepcopy(ayarlar.VARSAYILAN)
        ayar["sunucu"].update(etkin=True, adres="https://x", cihaz_anahtari="gecersiz")
        ayar["kameralar"] = [{"id": "c1"}]
        uyarilar = " | ".join(ayarlar.dogrula(ayar))
        self.assertIn("biciminde", uyarilar)
        self.assertIn("sunucu_id", uyarilar)
        ayar["sunucu"]["cihaz_anahtari"] = ANAHTAR
        ayar["kameralar"] = [{"id": "c1", "sunucu_id": 3}]
        self.assertEqual(ayarlar.dogrula(ayar), [])


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
