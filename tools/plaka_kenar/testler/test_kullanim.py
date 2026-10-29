"""Kullanim duzeltmesi: sunucusuz calisma, kesif (ONVIF + alt ag taramasi), el ile IP ayristirma, kamera basina yon, mozaik yerlesimi."""
import copy
import socket
import unittest

import numpy as np

from plaka_kenar import ayarlar, kesif, mozaik, yakalama
from plaka_kenar.boru import Okuma
from plaka_kenar.karar import IzinDeposu, KararMotoru
from plaka_kenar.kuyruk import OlayKuyrugu
from plaka_kenar.servis import Servis
from plaka_kenar.sunucu import SunucuIstemcisi

try:
    from . import test_okuma_pro as _okuma_pro
    from .test_servis import SahteKapi, kur, okuma
    from .yardimci import SIMDI, sync_yaniti
except ImportError:  # python -m unittest discover -s testler
    import test_okuma_pro as _okuma_pro
    from test_servis import SahteKapi, kur, okuma
    from yardimci import SIMDI, sync_yaniti


class SahteTcp:
    """connect_ex((ip, port)): tablo {(ip, port): errno}; yoksa zaman asimi (10035). Her cagri yeni soket (is parcaciklari ayri)."""

    def __init__(self, tablo):
        self.tablo, self.denenen, self.zaman_asimlari = tablo, [], []

    def __call__(self):
        sahte = self

        class S:
            def settimeout(self, t):
                sahte.zaman_asimlari.append(t)

            def connect_ex(self, adres):
                sahte.denenen.append(adres)
                return sahte.tablo.get(adres, 10035)

            def close(self):
                pass
        return S()


class SahteUdp:
    """Probe gonderimini sayar; recvfrom her zaman zaman asimi (multicast kesik guvenlik duvari)."""

    def __init__(self, yanitlar=None):
        self.gonderilen, self.yanitlar = [], list(yanitlar or [])

    def __call__(self):
        sahte = self

        class S:
            def setsockopt(self, *a):
                pass

            def bind(self, a):
                pass

            def settimeout(self, t):
                pass

            def sendto(self, veri, adres):
                sahte.gonderilen.append(adres)

            def recvfrom(self, n):
                if sahte.yanitlar:
                    return sahte.yanitlar.pop(0)
                raise socket.timeout()

            def close(self):
                pass
        return S()


class TaramaTesti(unittest.TestCase):
    AYAR = {"sure_sn": 0.3, "tarama": {"is_parcacigi": 16}}

    def test_tcp_dene_durumlari(self):
        t = SahteTcp({("10.0.0.5", 554): 0, ("10.0.0.5", 80): 10061})
        self.assertEqual(kesif.tcp_dene("10.0.0.5", 554, 0.3, t), "acik")
        self.assertEqual(kesif.tcp_dene("10.0.0.5", 80, 0.3, t), "reddedildi")
        self.assertEqual(kesif.tcp_dene("10.0.0.5", 8000, 0.3, t), "zaman_asimi")
        self.assertEqual(set(t.zaman_asimlari), {0.3})

    def test_alt_ag_adresleri_kendisi_ve_agi_haric(self):
        h = kesif.alt_ag_adresleri("192.168.1.20", 24, {"192.168.1.20"})
        self.assertEqual(len(h), 253)
        self.assertNotIn("192.168.1.20", h)
        self.assertNotIn("192.168.1.0", h)
        self.assertNotIn("192.168.1.255", h)
        self.assertEqual(len(kesif.alt_ag_adresleri("10.0.0.1", 8)), 1022)  # guvenlik: en fazla /22

    def test_alt_ag_tara_ayarlardaki_portlari_ve_zaman_asimini_kullanir(self):
        t = SahteTcp({("192.168.1.64", 554): 0, ("192.168.1.64", 80): 0, ("192.168.1.99", 80): 0, ("192.168.1.50", 554): 10061})
        sonuc = kesif.alt_ag_tara(["192.168.1.20"], {"tarama": {"portlar": [554, 80], "zaman_asimi_sn": 0.25, "is_parcacigi": 16}}, t)
        self.assertEqual(sonuc, {"192.168.1.64": [80, 554], "192.168.1.99": [80]})  # reddedilen (.50) acik sayilmaz
        self.assertEqual({p for _, p in t.denenen}, {554, 80})  # yalniz ayardaki portlar
        self.assertEqual(len(t.denenen), 253 * 2)
        self.assertEqual(set(t.zaman_asimlari), {0.25})

    def test_vpn_agi_taranmaz_ve_iki_arayuz_birlikte_taranir(self):
        t = SahteTcp({("192.168.1.64", 554): 0, ("10.5.5.9", 80): 0, ("100.64.0.9", 80): 0})
        sonuc = kesif.alt_ag_tara(["192.168.1.20", "10.5.5.5", "100.117.226.65"], {"tarama": {"portlar": [554, 80], "is_parcacigi": 16}}, t)
        self.assertEqual(sonuc, {"192.168.1.64": [554], "10.5.5.9": [80]})
        self.assertFalse(any(ip.startswith("100.117.226.") for ip, _ in t.denenen))

    def test_tur_sayisi_yanit_vermeyeni_tekrar_dener(self):
        t = SahteTcp({})
        kesif.alt_ag_tara(["192.168.1.20"], {"tarama": {"portlar": [554], "is_parcacigi": 16, "tur": 2}}, t)
        self.assertEqual(len(t.denenen), 253 * 2)

    def test_ara_onvif_bos_donse_bile_tarama_sonuclari_listelenir(self):
        t = SahteTcp({("192.168.1.64", 554): 0, ("192.168.1.64", 80): 0, ("192.168.1.99", 80): 0})
        s = kesif.ara(self.AYAR, ["192.168.1.20"], t, SahteUdp())
        self.assertEqual((s["onvif_adet"], s["tarama_adet"]), (0, 2))
        self.assertEqual([d["ip"] for d in s["cihazlar"]], ["192.168.1.64", "192.168.1.99"])  # RTSP acik olan once
        self.assertEqual(s["cihazlar"][0]["kaynak"], "tarama")
        self.assertEqual(s["cihazlar"][0]["rtsp_port"], 554)
        self.assertIn("RTSP açık", s["cihazlar"][0]["tur"])
        self.assertIn("yalnız web", s["cihazlar"][1]["tur"])
        self.assertIn("ONVIF yanıtı gelmedi", kesif.ozet_mesaj(s))

    def test_ara_her_arayuzden_probe_gonderir(self):
        u = SahteUdp()
        kesif.ara({"sure_sn": 0.3, "tarama": {"etkin": False}}, ["192.168.1.20", "10.0.0.5"], SahteTcp({}), u)
        self.assertGreaterEqual(len(u.gonderilen), 2)  # iki arayuz = iki ayri soket
        self.assertTrue(all(a == kesif.COKLU_YAYIN for a in u.gonderilen))

    def test_ikisi_de_bossa_durust_mesaj_ve_el_ile_ekle_yonlendirmesi(self):
        s = kesif.ara(self.AYAR, ["192.168.1.20"], SahteTcp({}), SahteUdp())
        self.assertEqual(s["cihazlar"], [])
        m = kesif.ozet_mesaj(s)
        self.assertIn("kamera bulunamadı", m)
        self.assertIn("El ile ekle", m)
        self.assertIn("güvenlik duvarı", m)
        self.assertIn("IPv4", kesif.ozet_mesaj({"cihazlar": [], "onvif_adet": 0, "tarama_adet": 0, "arayuzler": [], "hatalar": []}))

    def test_onvif_ve_tarama_ayni_cihazi_birlestirir(self):
        d = kesif.ayristir(_okuma_pro.KesifTesti.YANIT, "192.168.1.64")
        c = kesif.birlestir([d], {"192.168.1.64": [80, 554], "192.168.1.7": [8000]})
        self.assertEqual([x["ip"] for x in c], ["192.168.1.64", "192.168.1.7"])
        self.assertEqual((c[0]["kaynak"], c[0]["tur"], c[0]["ad"], c[0]["portlar"]), ("onvif+tarama", "ONVIF kamera", "Giris Kamera", [80, 554]))
        self.assertIn("kamera/ONVIF portu", c[1]["tur"])  # 8000 kamera portu

    def test_tekil_probe_yaniti_ayristirilir(self):
        u = SahteUdp([(_okuma_pro.KesifTesti.YANIT, ("192.168.1.64", 3702))])
        r = kesif.onvif_tekil(["192.168.1.64"], 0.3, u)
        self.assertEqual([x["ip"] for x in r], ["192.168.1.64"])
        self.assertEqual(u.gonderilen, [("192.168.1.64", 3702)])


class ElleEkleAyristirmaTesti(unittest.TestCase):
    def test_yalniz_ip_yaygin_sablonlari_onerir(self):
        r = kesif.rtsp_coz("192.168.1.64", "admin", "p@ss:1")
        self.assertEqual((r["hata"], r["ip"], r["tam"]), ("", "192.168.1.64", False))
        self.assertIn("rtsp://admin:p%40ss%3A1@192.168.1.64:554/Streaming/Channels/101", [a for _, a in r["oneriler"]])
        self.assertGreaterEqual(len(r["oneriler"]), 10)

    def test_ip_port_ve_yol_ve_sema(self):
        self.assertTrue(all(":8554/" in a for _, a in kesif.rtsp_coz("192.168.1.64:8554")["oneriler"]))
        r = kesif.rtsp_coz(" http://192.168.1.64/ ")
        self.assertEqual((r["hata"], r["ip"], r["tam"]), ("", "192.168.1.64", False))
        r = kesif.rtsp_coz("192.168.1.64/live/ch0", "u", "p", 554)
        self.assertEqual((r["tam"], r["oneriler"][0][1]), (True, "rtsp://u:p@192.168.1.64:554/live/ch0"))

    def test_tam_rtsp_adresi_oldugu_gibi_kimlik_eklenir(self):
        r = kesif.rtsp_coz("rtsp://192.168.1.64:554/stream1", "admin", "123")
        self.assertEqual((r["tam"], r["ip"], r["oneriler"][0][1]), (True, "192.168.1.64", "rtsp://admin:123@192.168.1.64:554/stream1"))
        self.assertEqual(kesif.rtsp_coz("rtsp://x:y@192.168.1.64/s", "admin", "123")["oneriler"][0][1], "rtsp://x:y@192.168.1.64/s")  # var olan kimlik korunur

    def test_gecersiz_girdiler_hata_verir(self):
        for girdi in ("", "   ", "999.1.1.1", "rtsp://", "192.168.1.64:abc", "ab cd", "http://"):
            self.assertTrue(kesif.rtsp_coz(girdi)["hata"], repr(girdi))

    def test_onvif_portlari_ayardan_gelir(self):
        self.assertEqual(kesif.kesif_ayari()["onvif_portlar"], [80, 8000, 8080, 2020])
        self.assertEqual(kesif.kesif_ayari({"tarama": {"portlar": [1]}})["tarama"]["zaman_asimi_sn"], 0.3)  # eksik anahtar geri-dusus


class SunucusuzCalismaTesti(unittest.TestCase):
    def ayar(self):
        a = copy.deepcopy(ayarlar.VARSAYILAN)
        a["kameralar"] = [{"id": "c1", "url": "", "yon": "giris"}]
        return a

    def test_bos_sunucu_alanlarinda_hicbir_uyari_cikmaz(self):
        a = self.ayar()
        self.assertEqual(ayarlar.dogrula(a), [])
        a["sunucu"]["etkin"] = True  # kutu isaretli ama adres/anahtar bos: sessizce kapali
        self.assertFalse(ayarlar.sunucu_hazir(a))
        self.assertEqual(ayarlar.dogrula(a), [])
        a["sunucu"]["adres"] = "https://x"
        self.assertFalse(ayarlar.sunucu_hazir(a))  # anahtar hala bos
        self.assertEqual(ayarlar.dogrula(a), [])

    def test_istemci_bos_alanlarda_hicbir_ucu_cagirmaz(self):
        s = copy.deepcopy(ayarlar.VARSAYILAN["sunucu"])
        s.update(etkin=True)
        c = SunucuIstemcisi(s)
        self.assertFalse(any(c.uc_etkin(u) for u in ("kayit", "senkron", "olay", "kalp_atisi")))
        s.update(adres="https://x.test", cihaz_anahtari="12." + "ab" * 24)
        self.assertTrue(c.uc_etkin("olay"))

    def test_sina_sunucu_bos_sorun_degil_ve_olay_kuyruga_girmez(self):
        ayar = self.ayar()
        ayar["sunucu"]["etkin"] = True
        ayar["kapilar"] = []
        depo = IzinDeposu()
        depo.delta_uygula(sync_yaniti())
        boru = type("B", (), {"kalibrasyon_modu": False, "tanima": type("T", (), {"aciklama": ""})(), "istatistik": {}})()
        s = Servis(ayar, boru=boru, kapi_surucu=SahteKapi(), depo=depo, kuyruk=OlayKuyrugu())
        sonuc = s.sina()
        self.assertEqual([(ad, ok) for ad, ok, _ in sonuc if ad == "Sunucu"], [("Sunucu", True)])
        self.assertIn("isteğe bağlı", [m for ad, _, m in sonuc if ad == "Sunucu"][0])
        self.assertFalse(any(ad == "Ayar uyarisi" for ad, _, _ in sonuc))
        kam = ayar["kameralar"][0]
        olay = s.okuma_isle(Okuma("c1", "34 SAK 111", "34SAK111", 0.9, True, "t", SIMDI), kam)
        self.assertEqual(olay["karar"], "acma_basarisiz")  # kapi tanimsiz: yerel karar calisti, sunucu gerekmedi
        self.assertEqual(s.kuyruk.sayim()["bekleyen"], 0)


class YonTesti(unittest.TestCase):
    def depo(self):
        d = IzinDeposu()
        d.delta_uygula(sync_yaniti())
        return d

    def test_olay_yonu_kameradan_gelir_kapidan_degil(self):
        m = KararMotoru(self.depo())
        # kapi 'giris' modunda ama kamera 'cikis': cikis kurallari (suresi dolmus misafir cikabilir)
        k = m.karar("34BIT333", "giris", "cikis", simdi=SIMDI)
        self.assertEqual((k.yon, k.ac, k.neden), ("cikis", True, "cikis"))
        # kapi 'cikis' modunda ama kamera 'giris': giris kurali (sure dolmus -> red)
        k = m.karar("34BIT333", "cikis", "giris", simdi=SIMDI)
        self.assertEqual((k.yon, k.ac, k.neden), ("giris", False, "izin_suresi_doldu"))

    def test_cift_yonlu_kapida_yon_kameradan_icerideki_duruma_bakilmaz(self):
        d = self.depo()
        m = KararMotoru(d)
        d.iceride_ayarla("34SAK111", True)
        self.assertEqual(m.karar("34SAK111", "cift", "giris", simdi=SIMDI).yon, "giris")   # iceride olsa da giris kamerasi giris der
        self.assertEqual(m.karar("34SAK111", "cift", "cikis", simdi=SIMDI).yon, "cikis")
        d.iceride_ayarla("34SAK111", False)
        self.assertEqual(m.karar("34SAK111", "cift", "cikis", simdi=SIMDI).yon, "cikis")   # iceride degil, yine kamera belirler

    def test_servis_cikis_kamerasi_icerideyi_dusurur_giris_kamerasi_artirir(self):
        kapi = SahteKapi()
        s, kam = kur(kapi)  # kapi yon_modu = 'giris'
        kam["yon"] = "cikis"
        s.depo.iceride_ayarla("34SAK111", True)
        olay = s.okuma_isle(okuma(), kam)
        self.assertEqual((olay["yon"], olay["karar"]), ("cikis", "acildi"))
        self.assertEqual(s.depo.arac("34SAK111")["iceride"], 0)
        self.assertEqual(s.kuyruk.bekleyenler()[0]["direction"], "cikis")
        kam["yon"] = "giris"
        self.assertEqual(s.okuma_isle(okuma(), kam)["yon"], "giris")
        self.assertEqual(s.depo.arac("34SAK111")["iceride"], 1)

    def test_yonsuz_eski_kamera_kapi_modundan_geri_duser(self):
        s, kam = kur(SahteKapi())
        kam.pop("yon", None)
        self.assertEqual(s.okuma_isle(okuma(), kam)["yon"], "giris")  # kapi 'giris'

    def test_yon_uyarilari_cift_yonlu_kapi_giris_ve_cikis_kamerasi_ister(self):
        a = copy.deepcopy(ayarlar.VARSAYILAN)
        a["kapilar"] = [{"id": "k1", "yon_modu": "cift"}]
        a["kameralar"] = [{"id": "c1", "kapi_id": "k1", "yon": "giris"}]
        u = ayarlar.yon_uyarilari(a)
        self.assertEqual(u["kapilar"], {"k1": "çıkış kamerası eksik"})
        self.assertIn("çıkış kamerası eksik", u["kameralar"]["c1"])
        a["kameralar"].append({"id": "c2", "kapi_id": "k1", "yon": "cikis"})
        self.assertEqual(ayarlar.yon_uyarilari(a), {"kameralar": {}, "kapilar": {}})
        a["kameralar"][1]["etkin"] = False  # devre disi kamera sayilmaz
        self.assertIn("k1", ayarlar.yon_uyarilari(a)["kapilar"])

    def test_yonu_secilmemis_kamera_ve_tek_yonlu_kapi(self):
        a = copy.deepcopy(ayarlar.VARSAYILAN)
        a["kapilar"] = [{"id": "k1", "yon_modu": "giris"}]
        a["kameralar"] = [{"id": "c1", "kapi_id": "k1"}]
        u = ayarlar.yon_uyarilari(a)
        self.assertEqual(u["kameralar"]["c1"], "Yön seçilmemiş (giriş / çıkış)")
        self.assertEqual(u["kapilar"], {"k1": "giriş kamerası eksik"})
        a["kameralar"][0]["yon"] = "giris"
        self.assertEqual(ayarlar.yon_uyarilari(a), {"kameralar": {}, "kapilar": {}})

    def test_siradaki_yon_ikinci_kamera_icin_karsit_yonu_onerir(self):
        a = copy.deepcopy(ayarlar.VARSAYILAN)
        self.assertEqual(ayarlar.siradaki_yon(a), "giris")
        a["kameralar"] = [{"id": "c1", "yon": "giris"}]
        self.assertEqual(ayarlar.siradaki_yon(a), "cikis")
        a["kameralar"].append({"id": "c2", "yon": "cikis"})
        self.assertEqual(ayarlar.siradaki_yon(a), "giris")


class MozaikTesti(unittest.TestCase):
    def test_yerlesim_satir_sutun(self):
        beklenen = {0: (0, 0), 1: (1, 1), 2: (1, 2), 3: (2, 2), 4: (2, 2), 5: (2, 3), 6: (2, 3), 7: (3, 3), 9: (3, 3), 10: (3, 4), 12: (3, 4), 13: (4, 4)}
        for n, izgara in beklenen.items():
            self.assertEqual(mozaik.yerlesim(n), izgara, n)
        for n in range(1, 40):  # her kamera bir hucreye sigar
            s, c = mozaik.yerlesim(n)
            self.assertGreaterEqual(s * c, n)

    def test_karo_kutulari_cakismaz_ve_alana_sigar(self):
        for n in (1, 2, 3, 4, 6, 9, 11):
            kutular = mozaik.karo_kutulari(n, 1000, 600, 6)
            self.assertEqual(len(kutular), n)
            for x, y, w, h in kutular:
                self.assertTrue(x >= 0 and y >= 0 and x + w <= 1000 and y + h <= 600)
            for i, (x, y, w, h) in enumerate(kutular):
                for x2, y2, w2, h2 in kutular[i + 1:]:
                    self.assertTrue(x + w <= x2 or x2 + w2 <= x or y + h <= y2 or y2 + h2 <= y, (n, i))
        self.assertEqual(mozaik.karo_kutulari(0, 100, 100), [])
        self.assertEqual(mozaik.karo_kutulari(4, 1006, 606, 6), [(0, 0, 500, 300), (506, 0, 500, 300), (0, 306, 500, 300), (506, 306, 500, 300)])

    def test_tiklanan_karo_bulunur(self):
        kutular = mozaik.karo_kutulari(4, 1006, 606, 6)
        self.assertEqual(mozaik.karo_bul(kutular, 10, 10), 0)
        self.assertEqual(mozaik.karo_bul(kutular, 600, 400), 3)
        self.assertIsNone(mozaik.karo_bul(kutular, 502, 10))   # karolar arasi bosluk
        self.assertIsNone(mozaik.karo_bul(kutular, 2000, 10))

    def test_sigdir_en_boyu_korur(self):
        ox, oy, w, h, olcek = mozaik.sigdir(640, 360, 500, 500)
        self.assertEqual((w, h, ox, oy), (500, 281, 0, 109))
        self.assertAlmostEqual(olcek, 500 / 640)

    def test_goruntu_kucultme_en_boyu_korur_ve_kucukse_dokunmaz(self):
        kare = np.zeros((1080, 1920, 3), np.uint8)
        k = yakalama.kucult(kare, 360)
        self.assertEqual(k.shape[:2], (360, 640))
        self.assertIs(yakalama.kucult(k, 360), k)
        self.assertIs(yakalama.kucult(kare, 0), kare)  # 0 = tam cozunurluk


if __name__ == "__main__":
    unittest.main()
