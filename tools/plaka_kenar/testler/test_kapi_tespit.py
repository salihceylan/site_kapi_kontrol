import json
import socket
import threading
import unittest

import cv2
import numpy as np

from plaka_kenar import ayarlar
from plaka_kenar.kapi import SmartKeyPassYerel, imza
from plaka_kenar.tanima import Segmentleyici
from plaka_kenar.tespit import KlasikDetector

UID, TOKEN = "240AC4E2E001", "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE"  # docs/YEREL_KONTROL_V2.md test vektoru


class SahteCihaz(threading.Thread):
    """docs/YEREL_KONTROL_V2.md protokolunu taklit eden UDP cihaz: discover sonrasi challenge doner (yeniden deneme yolu)."""

    def __init__(self):
        super().__init__(daemon=True)
        self.s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.s.bind(("127.0.0.1", 0))
        self.s.settimeout(0.2)
        self.port = self.s.getsockname()[1]
        self.ch, self.alinan, self.dur = "1111111111111111", [], False

    def run(self):
        while not self.dur:
            try:
                veri, adr = self.s.recvfrom(1024)
            except socket.timeout:
                continue
            m = json.loads(veri)
            self.alinan.append(m)
            y = {"device_uid": UID, "nonce": m.get("nonce")}
            if m["action"] == "discover":
                y.update(ok=True, ip="127.0.0.1", port=self.port, ch=self.ch, local_control_available=True)
                self.s.sendto(json.dumps(y).encode(), adr)
                self.ch = "2222222222222222"  # discover'dan hemen sonra doner
                continue
            if m.get("ch") != self.ch:
                y.update(ok=False, error="challenge", ch=self.ch)
            elif m.get("sig") == imza(TOKEN, m["action"], UID, self.ch):
                y.update(ok=True, message="yerel_kapi_acma_komutu_alindi")
            else:
                y.update(ok=False, error="unauthorized", local_control_available=True)
            self.s.sendto(json.dumps(y).encode(), adr)
        self.s.close()


class KapiTesti(unittest.TestCase):
    def sur(self, port):
        p = dict(ayarlar.VARSAYILAN["skp"], port=port, zaman_asimi_sn=1.0)
        return SmartKeyPassYerel(p)

    def test_imza_bilinen_cevap_vektoru(self):
        self.assertEqual(imza(TOKEN, "open", UID, "0123456789abcdef"),
                         "92f22b8a741bcc00b1aec15ff573b6ee4d48edea1bba959807489eb3c6fed5f4")
        self.assertEqual(imza(TOKEN, "pulse", UID.lower(), "0123456789abcdef"),
                         "3bb6390fa9c7a2135232000306e9a6293e38fabd736edcf7400ecd55c597b881")

    def test_acma_challenge_yeniden_deneme_ve_guvenlik(self):
        c = SahteCihaz()
        c.start()
        try:
            kapi = {"skp_uid": UID, "skp_ip": "127.0.0.1", "skp_token": TOKEN}
            r = self.sur(c.port).ac(kapi)
            self.assertTrue(r.basarili, r.neden)
            self.assertEqual([m["action"] for m in c.alinan], ["discover", "open", "open"])  # tek yeniden deneme
            self.assertTrue(all("token" not in m for m in c.alinan))                            # token ag'a cikmaz
            kotu = self.sur(c.port).ac({**kapi, "skp_token": "yanlis"})
            self.assertEqual((kotu.basarili, kotu.neden), (False, "unauthorized"))
            self.assertFalse(self.sur(c.port).ac({**kapi, "komut": "close"}).basarili)           # kapat komutu YOK
            self.assertEqual(self.sur(c.port).ac({**kapi, "skp_token": ""}).neden, "skp_uid_veya_token_yok")
        finally:
            c.dur = True
            c.join(2)


class TespitTesti(unittest.TestCase):
    def sahne(self):
        # Gercekci TR plaka (520x110: sol mavi serit + 8 karakter), 0.5 olcekle sahneye (260x55 ~ 4.7:1)
        pl = np.full((110, 520, 3), 235, np.uint8)
        cv2.rectangle(pl, (0, 0), (42, 110), (160, 70, 20), -1)
        cv2.putText(pl, "34ABC123", (66, 88), cv2.FONT_HERSHEY_DUPLEX, 2.6, (20, 20, 20), 5, cv2.LINE_AA)
        pl = cv2.resize(pl, (260, 55), interpolation=cv2.INTER_AREA)
        img = np.full((480, 640, 3), 90, np.uint8)
        img[300:355, 200:460] = pl
        return img

    def test_sahte_karede_plaka_konturu_ve_segmentasyon(self):
        p = ayarlar.VARSAYILAN
        adaylar = KlasikDetector(p["tespit"]["klasik"]).tespit_et(self.sahne())
        self.assertTrue(adaylar, "plaka adayi bulunamadi")
        a = adaylar[0]
        x, y, w, h = a.kutu
        kesisim = max(0, min(x + w, 460) - max(x, 200)) * max(0, min(y + h, 355) - max(y, 300))
        self.assertGreater(kesisim / float(w * h + 260 * 55 - kesisim), 0.45)  # IoU
        self.assertTrue(3.5 <= a.en_boy <= 5.8, a.en_boy)
        self.assertEqual(a.plaka.shape[:2][::-1], tuple(p["tespit"]["klasik"]["cikis_boyut"]))
        kar = Segmentleyici(p["segmentleme"]).bol(a.plaka)
        self.assertEqual(len(kar), 8)  # 3 4 A B C 1 2 3


if __name__ == "__main__":
    unittest.main()
