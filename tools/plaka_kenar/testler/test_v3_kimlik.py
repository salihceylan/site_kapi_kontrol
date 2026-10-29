"""Sozlesme v3 - kimlik baglama ("Daire A - 5 · Ali Y." / "Misafir — Daire A - 5" / tanimsizda yalniz plaka), kapi komutu durumu (accepted / failed,
"acildi" demeden), olay govdesi v3 alanlari, yerel depo gecisi (eski sema), kalp atisi tanima hazirligi ve arayuz metin yardimcilari."""
import copy
import sqlite3
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from plaka_kenar import ayarlar, gosterim
from plaka_kenar.kapi import KapiSonucu
from plaka_kenar.karar import IzinDeposu, kimlik_etiketi

try:
    from .test_servis import SahteKapi, SahteSunucu, kur, okuma
    from .yardimci import SIMDI, iso, sync_yaniti
except ImportError:  # python -m unittest discover -s testler
    from test_servis import SahteKapi, SahteSunucu, kur, okuma
    from yardimci import SIMDI, iso, sync_yaniti


def kimlikli_sync():
    return sync_yaniti(
        vehicles={"rev": "v9", "items": [
            {"plate": "34SAK111", "vehicle_id": 1, "apartment_id": 1, "apartment_label": "A - 5", "person_label": "Ali Y."},
            {"plate": "34KAR444", "vehicle_id": 2, "apartment_id": 1, "apartment_label": "A - 5", "person_label": "Veli K."},
            {"plate": "34YET555", "vehicle_id": 3, "apartment_id": 1}]},                      # etiketsiz (eski sunucu / kisi yok)
        guest_permits={"rev": "p9", "items": [
            {"id": 1, "plate": "34MIS222", "apartment_id": 1, "valid_from": iso(SIMDI - 60), "valid_until": iso(SIMDI + 3600), "apartment_label": "A - 5"}]})


def kimlikli_servis(kapi=None, sunucu=None):
    s, kam = kur(kapi or SahteKapi(), sunucu)
    s.depo.delta_uygula(kimlikli_sync())
    return s, kam


class KimlikTesti(unittest.TestCase):
    def test_sakin_olayi_kimlik_etiketi_apartment_id_kind_ve_kapi_komutu_tasir(self):
        s, kam = kimlikli_servis()
        olay = s.okuma_isle(okuma(), kam)
        self.assertEqual((olay["etiket"], olay["kimlik_tur"], olay["daire_id"], olay["kapi_komut"]), ("Daire A - 5 · Ali Y.", "sakin", "1", "accepted"))
        g = s.kuyruk.bekleyenler()[0]
        self.assertEqual((g["schema_version"], g["apartment_id"], g["kind"], g["gate_command"], g["decision"]), (3, 1, "resident", "accepted", "acildi"))
        self.assertNotIn("etiket", g)                                           # kisi adi sunucuya GITMEZ (sunucu kendi kaydindan turetir)
        self.assertNotIn("Ali", str(g))

    def test_misafir_olayi_misafir_daire_etiketi(self):
        s, kam = kimlikli_servis()
        olay = s.okuma_isle(okuma(kanonik="34MIS222"), kam)
        self.assertEqual((olay["etiket"], olay["kimlik_tur"], olay["karar"]), ("Misafir — Daire A - 5", "misafir", "acildi"))
        g = s.kuyruk.bekleyenler()[0]
        self.assertEqual((g["apartment_id"], g["kind"], g["gate_command"]), (1, "guest", "accepted"))

    def test_tanimsiz_plakada_kimlik_yok_yalniz_plaka_ve_v3_alani_yok(self):
        s, kam = kimlikli_servis()
        olay = s.okuma_isle(okuma(kanonik="06XYZ99"), kam)
        self.assertEqual((olay["etiket"], olay["kimlik_tur"], olay["daire_id"], olay["kapi_komut"]), ("", "", "", ""))
        g = s.kuyruk.bekleyenler()[0]
        for alan in ("apartment_id", "kind", "gate_command"):
            self.assertNotIn(alan, g)
        self.assertEqual(g["decision"], "tanimsiz")

    def test_etiketsiz_kayitli_arac_kayitli_arac_der(self):
        s, kam = kimlikli_servis()
        olay = s.okuma_isle(okuma(kanonik="34YET555"), kam)
        self.assertEqual(olay["etiket"], "Kayıtlı araç")
        self.assertEqual(s.kuyruk.bekleyenler()[0]["kind"], "resident")

    def test_cihaz_acamazsa_gate_command_failed_acildi_denmez(self):
        s, kam = kimlikli_servis(SahteKapi(KapiSonucu(False, "cihaz_yanit_vermedi")))
        olay = s.okuma_isle(okuma(), kam)
        self.assertEqual((olay["karar"], olay["kapi_komut"]), ("acma_basarisiz", "failed"))
        g = s.kuyruk.bekleyenler()[0]
        self.assertEqual((g["decision"], g["reason"], g["gate_command"], g["apartment_id"], g["kind"]), ("red", "cihaz_yanit_vermedi", "failed", 1, "resident"))

    def test_kapi_tanimsizsa_deneme_yok_ama_acilamadi_failed(self):
        s, kam = kimlikli_servis()
        kam["kapi_id"] = "yok"
        olay = s.okuma_isle(okuma(), kam)
        self.assertEqual((olay["neden"], olay["kapi_komut"]), ("kapi_tanimsiz", "failed"))

    def test_acma_denenmeyen_kararlarda_gate_command_yok(self):
        s, kam = kimlikli_servis()
        s.okuma_isle(okuma(kanonik="34KAR444"), kam)                           # kara liste: kapi acilmaz
        s.depo.iceride_ayarla("34MIS222", False)
        s.depo.delta_uygula(sync_yaniti(apartments=[{"id": 1, "parking_slots": 2, "inside_count": 1}]))
        s.okuma_isle(okuma(kanonik="34MIS222"), kam)                           # misafir park dolu: red
        bodies = {g["decision"]: g for g in s.kuyruk.bekleyenler()}
        self.assertEqual(set(bodies), {"kara_liste", "red"})
        for g in bodies.values():
            self.assertNotIn("gate_command", g)
        self.assertEqual(bodies["kara_liste"]["kind"], "resident")             # kimlik yine bilinir: "kara listedeki Ali Y." yonetici icin degerli
        self.assertEqual(s.kapi_surucu.cagrilar, [])

    def test_dogrulanmamis_okumada_kimlik_baglanmaz(self):
        s, kam = kimlikli_servis()
        olay = s.okuma_isle(okuma(dogrulanmis=False), kam)
        self.assertEqual((olay["etiket"], olay["kimlik_tur"], olay["kapi_komut"]), ("", "", ""))
        self.assertEqual(s.kuyruk.sayim()["bekleyen"], 0)                       # dogrulanmamis sunucuya zaten gitmez

    def test_surum_2_ayariyla_v3_alanlari_gonderilmez(self):
        s, kam = kimlikli_servis()
        s.ayar["sunucu"]["schema_version"] = 2
        s.okuma_isle(okuma(), kam)
        g = s.kuyruk.bekleyenler()[0]
        self.assertEqual(g["schema_version"], 2)
        for alan in ("apartment_id", "kind", "gate_command"):
            self.assertNotIn(alan, g)

    def test_etiket_bicimleri(self):
        self.assertEqual(kimlik_etiketi("sakin", "A - 5", "Ali Y."), "Daire A - 5 · Ali Y.")
        self.assertEqual(kimlik_etiketi("sakin", "A - 5", None), "Daire A - 5")
        self.assertEqual(kimlik_etiketi("sakin", None, "Ali Y."), "Ali Y.")
        self.assertEqual(kimlik_etiketi("sakin", None, None), "Kayıtlı araç")
        self.assertEqual(kimlik_etiketi("misafir", "A - 5", "Ali Y."), "Misafir — Daire A - 5")         # misafirde kisi adi yok
        self.assertEqual(kimlik_etiketi("misafir", None, None), "Misafir")

    def test_depo_kimlik_sakin_misafir_ustundur_ve_unchanged_etiketi_korur(self):
        d = IzinDeposu()
        d.delta_uygula(kimlikli_sync())
        d.delta_uygula(sync_yaniti(vehicles={"rev": "v9", "unchanged": True}, guest_permits={"rev": "p9", "unchanged": True}))
        self.assertEqual(d.kimlik("34SAK111")["etiket"], "Daire A - 5 · Ali Y.")
        self.assertEqual(d.kimlik("34MIS222")["tur"], "misafir")
        self.assertIsNone(d.kimlik("06XYZ99"))
        d.delta_uygula(sync_yaniti(blacklist={"rev": "b2", "items": [{"plate": "06KARA00"}]}))
        self.assertIsNone(d.kimlik("06KARA00"))                                # yalniz kara listede: kimlik yok
        d.delta_uygula(sync_yaniti(guest_permits={"rev": "p10", "items": [
            {"id": 2, "plate": "34SAK111", "apartment_id": 2, "valid_from": iso(SIMDI - 60), "valid_until": iso(SIMDI + 60), "apartment_label": "B - 1"}]}))
        self.assertEqual(d.kimlik("34SAK111")["tur"], "sakin")                  # hem arac hem izin: sakin kazanir

    def test_etiketler_kirpilir_ve_bosluklar_toparlanir(self):
        d = IzinDeposu()
        d.delta_uygula(sync_yaniti(vehicles={"rev": "v1", "items": [{"plate": "34SAK111", "apartment_id": 1, "apartment_label": "  A   -  5 ", "person_label": "x" * 200}]}))
        k = d.kimlik("34SAK111")["etiket"]
        self.assertTrue(k.startswith("Daire A - 5 · xxx"))
        self.assertLessEqual(len(k), len("Daire A - 5 · ") + 60)


class DepoGecisTesti(unittest.TestCase):
    def test_eski_sema_dosyasi_sutunlari_alir_veri_korunur_revler_sifirlanir(self):
        with tempfile.TemporaryDirectory() as dizin:
            yol = Path(dizin) / "izin.db"
            eski = sqlite3.connect(yol)
            eski.executescript("""
                CREATE TABLE s_arac(plaka TEXT PRIMARY KEY, daire_id TEXT);
                CREATE TABLE s_izin(plaka TEXT PRIMARY KEY, daire_id TEXT, baslangic REAL, bitis REAL);
                CREATE TABLE s_kara(plaka TEXT PRIMARY KEY);
                CREATE TABLE s_iceride(plaka TEXT PRIMARY KEY, daire_id TEXT, tur TEXT, zaman REAL);
                CREATE TABLE daireler(daire_id TEXT PRIMARY KEY, park_yeri INTEGER NOT NULL DEFAULT 0, iceride INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT);
                INSERT INTO s_arac VALUES('34SAK111', '1');
                INSERT INTO meta VALUES('rev_vehicles', 'eski'), ('rev_permits', 'eskip'), ('rev_blacklist', 'b1'), ('server_time', '2026-10-29T12:00:00Z');
            """)
            eski.commit()
            eski.close()
            d = IzinDeposu(yol)
            sutunlar = {r[1] for r in d.db.execute("PRAGMA table_info(s_arac)")}
            self.assertTrue({"etiket", "kisi"} <= sutunlar)
            self.assertIn("etiket", {r[1] for r in d.db.execute("PRAGMA table_info(s_izin)")})
            self.assertEqual(d.kimlik("34SAK111")["etiket"], "Kayıtlı araç")        # eski kayit okunur (etiketsiz)
            self.assertEqual(d.revler(), {"vehicles": "", "permits": "", "blacklist": "b1"})   # etiket icin tam bolum yeniden istenir
            self.assertEqual(d.imlec(), "2026-10-29T12:00:00Z")
            d.db.close()
            d2 = IzinDeposu(yol)                                                    # ikinci acilis: gecis tekrar calismaz, hata yok
            self.assertEqual(d2.revler()["blacklist"], "b1")
            d2.delta_uygula(kimlikli_sync())
            self.assertEqual(d2.kimlik("34SAK111")["etiket"], "Daire A - 5 · Ali Y.")
            d2.db.close()


class KalpAtisiTanimaTesti(unittest.TestCase):
    def test_recognition_hazir_ve_kalibrasyon(self):
        s, _ = kur(SahteKapi(), SahteSunucu())
        s.boru = SimpleNamespace(kalibrasyon_modu=False, tanima=SimpleNamespace(aciklama="ONNX modeli onaylı"), istatistik={})
        self.assertEqual(s.kalp_atisi_govdesi()["recognition"], {"ready": True, "note": "ONNX modeli onaylı"})
        s.boru = SimpleNamespace(kalibrasyon_modu=True, tanima=SimpleNamespace(aciklama="model yok " * 20), istatistik={})
        r = s.kalp_atisi_govdesi()["recognition"]
        self.assertFalse(r["ready"])
        self.assertLessEqual(len(r["note"]), 80)
        s.boru = SimpleNamespace(kalibrasyon_modu=False, tanima=SimpleNamespace(aciklama=""), istatistik={})
        self.assertEqual(s.kalp_atisi_govdesi()["recognition"], {"ready": True})


class GosterimTesti(unittest.TestCase):
    def test_kapi_rozeti_tetiklendi_yanit_vermedi_ve_acildi_denmez(self):
        self.assertEqual(gosterim.kapi_rozeti("accepted"), ("Kapı tetiklendi ✓", "yesil"))
        self.assertEqual(gosterim.kapi_rozeti("failed"), ("Kapı yanıt vermedi ✗", "kirmizi"))
        self.assertIsNone(gosterim.kapi_rozeti(""))
        self.assertIsNone(gosterim.kapi_rozeti(None))
        tum = " ".join([m for m, _ in gosterim.KARAR_ROZET.values()] + list(gosterim.KARAR_METIN.values()) + [gosterim.KAPI_TETIKLENDI, gosterim.KAPI_YANITSIZ])
        self.assertNotIn("açıldı", tum.lower())                                   # "açıldı" hicbir arayuz metninde yok (P1-15)

    def test_olay_satiri_ve_sunucu_kaynakli(self):
        o = {"kamera_id": "c1", "yon": "giris", "plaka": "34 SAK 111", "karar": "acildi", "neden": "kayitli_arac", "guven": 0.9,
             "etiket": "Daire A - 5 · Ali Y.", "kapi_komut": "accepted"}
        self.assertEqual(gosterim.olay_satiri(o, "12:00:00"),
                         ("12:00:00", "c1", "giris", "34 SAK 111", "İzin verildi", "Daire A - 5 · Ali Y.", "Kapı tetiklendi ✓", "kayitli_arac", "0.90"))
        o2 = {**o, "karar": "tanimsiz", "etiket": "", "kapi_komut": ""}
        self.assertEqual(gosterim.olay_satiri(o2, "12:00:01")[5:7], ("", ""))
        self.assertTrue(gosterim.sunucu_kaynakli({"kaynak": "sunucu"}))
        self.assertFalse(gosterim.sunucu_kaynakli({"id": "x"}))
        self.assertFalse(gosterim.sunucu_kaynakli(None))


if __name__ == "__main__":
    unittest.main()
