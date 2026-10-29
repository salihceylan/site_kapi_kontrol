"""Sozlesme v3 - uzaktan komutlar: discover / probe islemesi (sahte kesif + sahte kare), tekrar korumasi, hata -> failed, sonuc gonderimi, servis yoklamasi."""
import copy
import json
import unittest
from types import SimpleNamespace
from urllib.parse import quote

import numpy as np

from plaka_kenar import ayarlar, komut
from plaka_kenar.kuyruk import OlayKuyrugu
from plaka_kenar.karar import IzinDeposu
from plaka_kenar.servis import Servis
from plaka_kenar.sunucu import SunucuHatasi

try:
    from .test_servis import SahteKapi, SahteSunucu
except ImportError:  # python -m unittest discover -s testler
    from test_servis import SahteKapi, SahteSunucu

SIFRE = "S3rEt-Parola!"
KESIF = {"cihazlar": [
    {"ip": "192.168.1.64", "portlar": [80, 554, 8000], "ad": "Giris", "model": "DS-2CD", "kaynak": "onvif+tarama", "tur": "ONVIF kamera", "rtsp_port": 554},
    {"ip": "192.168.1.1", "portlar": [80], "ad": "", "model": "", "kaynak": "tarama", "tur": "Ağ cihazı — yalnız web arayüzü (kamera olabilir)", "rtsp_port": 554}],
    "onvif_adet": 1, "tarama_adet": 2, "arayuzler": ["192.168.1.10"], "hatalar": []}


class SunucuKaydi:
    """komut_sonucu cagrilarini kaydeder; hatalar sirayla verilebilir."""

    def __init__(self, hatalar=None):
        self.sonuclar, self.hatalar = [], list(hatalar or [])

    def komut_sonucu(self, kid, govde):
        if self.hatalar:
            h = self.hatalar.pop(0)
            if h is not None:
                raise h
        self.sonuclar.append((kid, govde))


def isleyici(sunucu=None, kesif_fn=None, kare_fn=None, stream_uri_fn=None, **kw):
    ayar = copy.deepcopy(ayarlar.VARSAYILAN)
    return komut.KomutIsleyici(ayar, sunucu or SunucuKaydi(), kesif_fn=kesif_fn or (lambda a: KESIF), kare_fn=kare_fn or (lambda u, y: (None, "baglanti_acilamadi")),
                               stream_uri_fn=stream_uri_fn or (lambda *a, **k: (None, "yok")), calistir=lambda f: f(), bekle_sn=0, **kw)


def probe_komutu(kid=5, **yuk):
    govde = {"camera_id": 7, "name": "Giriş", "brand": "hikvision", "host": "192.168.1.64", "port": 554,
             "rtsp_url": "rtsp://192.168.1.64:554/Streaming/Channels/101", "username": "admin", "password": SIFRE}
    govde.update(yuk)
    return {"id": kid, "kind": "probe", "created_at": "2026-10-29T12:00:00Z", "payload": govde}


class KesifKomutuTesti(unittest.TestCase):
    def test_discover_sozlesme_sonucu(self):
        s = SunucuKaydi()
        i = isleyici(s)
        self.assertEqual(i.ver([{"id": 3, "kind": "discover", "payload": {}}]), 1)
        (kid, g), = s.sonuclar
        self.assertEqual((kid, g["status"]), (3, "done"))
        r = g["result"]
        self.assertEqual((r["onvif_count"], r["scan_count"], r["interfaces"]), (1, 2, ["192.168.1.10"]))
        d = r["devices"][0]
        self.assertEqual((d["ip"], d["ports"], d["name"], d["model"], d["source"], d["rtsp_port"]),
                         ("192.168.1.64", [80, 554, 8000], "Giris", "DS-2CD", "onvif+tarama", 554))
        self.assertEqual(r["devices"][1]["source"], "tarama")
        self.assertIn("cihaz bulundu", r["summary"])
        self.assertEqual(g.get("message"), None)

    def test_ayni_komut_iki_kez_islenmez(self):
        s = SunucuKaydi()
        sayac = []
        i = isleyici(s, kesif_fn=lambda a: (sayac.append(1), KESIF)[1])
        k = {"id": 9, "kind": "discover", "payload": {}}
        self.assertEqual(i.ver([k]), 1)
        self.assertEqual(i.ver([k, dict(k)]), 0)                       # ayni kimlik: heartbeat + GET commands cift teslimi
        self.assertEqual((len(sayac), len(s.sonuclar)), (1, 1))

    def test_hata_failed_olarak_bildirilir_ve_bilinmeyen_tur_reddedilir(self):
        s = SunucuKaydi()

        def patla(a):
            raise OSError("ag")

        i = isleyici(s, kesif_fn=patla)
        i.ver([{"id": 1, "kind": "discover", "payload": {}}, {"id": 2, "kind": "yeniden_baslat", "payload": {}}, {"id": "x"}, "bozuk", None])
        durum = {kid: g["status"] for kid, g in s.sonuclar}
        self.assertEqual(durum, {1: "failed", 2: "failed"})
        self.assertIn("OSError", s.sonuclar[0][1]["message"])
        self.assertIn("Desteklenmeyen", s.sonuclar[1][1]["message"])

    def test_servis_komut_yokla_ve_kalp_atisi_yaniti_komut_tasir(self):
        class Sunucu(SahteSunucu, SunucuKaydi):
            def __init__(self):
                SahteSunucu.__init__(self)
                SunucuKaydi.__init__(self)

            def komutlar(self):
                return SimpleNamespace(govde={"commands": [{"id": 11, "kind": "discover", "payload": {}}]})

            def kalp_atisi(self, govde):
                self.kalp.append(govde)
                return SimpleNamespace(govde={"intervals": {}, "commands": [{"id": 12, "kind": "discover", "payload": {}},
                                                                            {"id": 11, "kind": "discover", "payload": {}}]})

        sunucu = Sunucu()
        ayar = copy.deepcopy(ayarlar.VARSAYILAN)
        ayar["sunucu"].update(etkin=True, adres="https://x.test", cihaz_anahtari="12." + "ab" * 24)
        boru = SimpleNamespace(kalibrasyon_modu=False, tanima=SimpleNamespace(aciklama=""), istatistik={})
        s = Servis(ayar, boru=boru, kapi_surucu=SahteKapi(), depo=IzinDeposu(), kuyruk=OlayKuyrugu(), sunucu=sunucu,
                   komut_isleyici=isleyici(sunucu))
        self.assertEqual(s.komut_yokla(), 1)                          # GET commands
        s.kalp_atisi()                                                 # 12 yeni, 11 zaten islendi
        self.assertEqual(sorted(k for k, _ in sunucu.sonuclar), [11, 12])


class ProbeKomutuTesti(unittest.TestCase):
    def test_basarili_sina_cozunurluk_doner_ve_parola_sonucta_yok(self):
        gorulen = []
        s = SunucuKaydi()
        i = isleyici(s, kare_fn=lambda url, y: (gorulen.append(url), (np.zeros((1080, 1920, 3), np.uint8), ""))[1])
        i.ver([probe_komutu()])
        self.assertEqual(gorulen, [f"rtsp://admin:{quote(SIFRE, safe='')}@192.168.1.64:554/Streaming/Channels/101"])   # kenar kimlikli adresle baglanir
        (_, g), = s.sonuclar
        self.assertEqual((g["status"], g["result"]["ok"], g["result"]["width"], g["result"]["height"]), ("done", True, 1920, 1080))
        self.assertNotIn(SIFRE, json.dumps(g))
        self.assertNotIn("rtsp_url", g["result"])                      # adres sunucuda zaten var: cozulmediyse geri gonderilmez

    def test_baglanti_hatasi_dogru_nedenle_ok_false_parola_sizmaz(self):
        s = SunucuKaydi()
        i = isleyici(s, kare_fn=lambda url, y: (None, "baglanti_acilamadi"))
        i.ver([probe_komutu()])
        (_, g), = s.sonuclar
        self.assertEqual(g["status"], "done")                          # komut calisti; kamera acilamadi => sonuc ok:false
        self.assertEqual((g["result"]["ok"], g["result"]["reason"]), (False, "baglanti_acilamadi"))
        self.assertIn("RTSP bağlantısı açılamadı", g["result"]["message"])
        self.assertNotIn(SIFRE, json.dumps(g))

    def test_sina_istisnasi_parolayi_mesaja_sizdirmaz(self):
        s = SunucuKaydi()

        def patla(url, y):
            raise RuntimeError(f"failed {url}")

        i = isleyici(s, kare_fn=patla)
        i.ver([probe_komutu()])
        g = s.sonuclar[0][1]
        self.assertFalse(g["result"]["ok"])
        self.assertNotIn(SIFRE, json.dumps(g))

    def test_rtsp_url_bossa_onvif_ile_cozulur_adres_kimliksiz_doner(self):
        cagrilar, s = [], SunucuKaydi()

        def uri(cihaz, kul, par, zaman_asimi, portlar):
            cagrilar.append((cihaz["ip"], kul, par))
            return f"rtsp://{kul}:{par}@192.168.1.64:554/onvif1", ""

        gorulen = []
        i = isleyici(s, stream_uri_fn=uri, kare_fn=lambda u, y: (gorulen.append(u), (np.zeros((720, 1280, 3), np.uint8), ""))[1])
        i.ver([probe_komutu(rtsp_url=None, brand="onvif")])
        self.assertEqual(cagrilar, [("192.168.1.64", "admin", SIFRE)])
        r = s.sonuclar[0][1]["result"]
        self.assertEqual((r["ok"], r["rtsp_url"], r["width"]), (True, "rtsp://192.168.1.64:554/onvif1", 1280))
        self.assertNotIn(SIFRE, json.dumps(s.sonuclar[0][1]))
        self.assertIn("admin:", gorulen[0])                            # baglanti yine kimlikli

    def test_onvif_cozulemezse_ok_false_ve_adres_yoksa_hata(self):
        s = SunucuKaydi()
        i = isleyici(s, stream_uri_fn=lambda *a, **k: (None, "kimlik doğrulanamadı"))
        i.ver([probe_komutu(rtsp_url=None), probe_komutu(kid=6, rtsp_url=None, host="")])
        r1, r2 = s.sonuclar[0][1]["result"], s.sonuclar[1][1]["result"]
        self.assertEqual((r1["ok"], r1["reason"]), (False, "onvif_cozulemedi"))
        self.assertEqual((r2["ok"], r2["reason"]), (False, "adres_yok"))

    def test_kimliksiz_ve_temizle(self):
        self.assertEqual(komut.kimliksiz("rtsp://a:b@10.0.0.1:8554/x?y=1"), "rtsp://10.0.0.1:8554/x?y=1")
        self.assertEqual(komut.kimliksiz("rtsp://10.0.0.1/x"), "rtsp://10.0.0.1/x")
        self.assertNotIn("p@ss", komut.temizle("hata rtsp://admin:p%40ss@10.0.0.1/x p@ss", "p@ss"))


class SonucGonderimiTesti(unittest.TestCase):
    def test_gecici_hatada_yeniden_dener_kalici_hatada_birakir(self):
        s = SunucuKaydi(hatalar=[SunucuHatasi("ConnectionError"), SunucuHatasi("HTTP 503", kod=503), None])
        i = isleyici(s)
        self.assertTrue(i.bildir(4, {"status": "done"}))
        self.assertEqual(len(s.sonuclar), 1)
        s2 = SunucuKaydi(hatalar=[SunucuHatasi("HTTP 409 COMMAND_NOT_RUNNING", kalici=True, kod=409)])
        self.assertFalse(isleyici(s2).bildir(4, {"status": "done"}))      # komut artik gecersiz: tekrar deneme yok
        self.assertEqual(s2.sonuclar, [])

    def test_tum_denemeler_basarisizsa_false(self):
        s = SunucuKaydi(hatalar=[SunucuHatasi("x")] * 5)
        self.assertFalse(isleyici(s).bildir(4, {"status": "done"}))


class IstemciYollariTesti(unittest.TestCase):
    class Oturum:
        def __init__(self):
            self.cagrilar = []

        def request(self, yontem, url, **kw):
            self.cagrilar.append((yontem, url, kw))
            return SimpleNamespace(status_code=200, content=b"{}", json=lambda: {"ok": True})

    def test_komut_ve_goruntu_uclari_yol_baslik_govde(self):
        from plaka_kenar.sunucu import SunucuIstemcisi
        s = copy.deepcopy(ayarlar.VARSAYILAN["sunucu"])
        s.update(etkin=True, adres="https://api.test/", cihaz_anahtari="12." + "ab" * 24)
        o = self.Oturum()
        c = SunucuIstemcisi(s, o)
        c.komutlar()
        c.komut_sonucu(5, {"status": "done", "result": {"ok": True}})
        c.goruntu_gonder(7, b"\xff\xd8\xff\xe0jpeg", "2026-10-29T12:00:00+00:00", 640, 360)
        self.assertEqual([(m, u) for m, u, _ in o.cagrilar], [
            ("GET", "https://api.test/edge/plate/v1/commands"), ("POST", "https://api.test/edge/plate/v1/commands/5/result"),
            ("PUT", "https://api.test/edge/plate/v1/cameras/7/snapshot")])
        self.assertEqual(o.cagrilar[1][2]["json"], {"schema_version": 3, "status": "done", "result": {"ok": True}})
        k = o.cagrilar[2][2]
        self.assertEqual(k["data"], b"\xff\xd8\xff\xe0jpeg")
        self.assertEqual((k["headers"]["Content-Type"], k["headers"]["X-Captured-At"], k["headers"]["X-Frame-Width"], k["headers"]["X-Frame-Height"]),
                         ("image/jpeg", "2026-10-29T12:00:00+00:00", "640", "360"))
        self.assertTrue(k["headers"]["Authorization"].startswith("Bearer "))
        with self.assertRaises(SunucuHatasi) as ctx:                      # yol parametresi yalniz rakam
            c.komut_sonucu("5/../x", {})
        self.assertTrue(ctx.exception.kalici)

    def test_eski_ayar_dosyasi_yeni_uclari_ve_surumu_alir(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "a.json"
            p.write_text(json.dumps({"sunucu": {"schema_version": 2, "uclar": {"olay": {"etkin": True, "yol": "/edge/plate/v1/events"}}}}), encoding="utf-8")
            a = ayarlar.yukle(p)
        self.assertEqual(a["sunucu"]["schema_version"], 3)
        self.assertEqual(a["sunucu"]["uclar"]["komutlar"]["yol"], "/edge/plate/v1/commands")
        self.assertTrue(a["goruntu_gonderim"]["etkin"])
        self.assertEqual(ayarlar.SURUM, "0.3.0")


if __name__ == "__main__":
    unittest.main()
