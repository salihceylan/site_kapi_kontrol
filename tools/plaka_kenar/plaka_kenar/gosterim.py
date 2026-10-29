"""Arayuz metinleri icin SAF yardimcilar (tkinter yok; headless test edilir).

Kapi dili (P1-15, durust basari): SmartKeyPass komutu KABUL ETTI ("tetiklendi") ile kapinin FIZIKSEL olarak acilmasi ayri seylerdir; cihaz acildigini
bildirmedigi surece "acildi" yazilmaz. Kimlik satiri yalniz taninan plakada (sakin / misafir) vardir; tanimsiz plakada yalniz plaka gorunur."""
from __future__ import annotations

KAPI_TETIKLENDI = "Kapı tetiklendi ✓"
KAPI_YANITSIZ = "Kapı yanıt vermedi ✗"

# karar kodu -> (etiket, ton). Ton renge arayuzde cevrilir (yesil | kirmizi | gri).
KARAR_ROZET = {
    "acildi": ("İZİN VERİLDİ", "yesil"), "red": ("RED", "kirmizi"), "kara_liste": ("KARA LİSTE", "kirmizi"),
    "acma_basarisiz": ("KAPI HATASI", "kirmizi"), "tanimsiz": ("TANIMSIZ", "gri"), "dogrulanmamis": ("TANIMSIZ", "gri"),
}
KARAR_METIN = {  # olay seridi (tablo) karar sutunu
    "acildi": "İzin verildi", "red": "Red", "tanimsiz": "Tanımsız", "dogrulanmamis": "Doğrulanmamış",
    "acma_basarisiz": "Kapı hatası", "kara_liste": "Kara liste",
}


def kapi_rozeti(kapi_komut: str | None):
    """Kapi durumu rozeti: ('Kapı tetiklendi ✓', 'yesil') | ('Kapı yanıt vermedi ✗', 'kirmizi') | None (acma denenmedi)."""
    if kapi_komut == "accepted":
        return KAPI_TETIKLENDI, "yesil"
    if kapi_komut == "failed":
        return KAPI_YANITSIZ, "kirmizi"
    return None


def kapi_metni(kapi_komut: str | None) -> str:
    r = kapi_rozeti(kapi_komut)
    return r[0] if r else ""


def kimlik_satiri(olay: dict | None) -> str:
    """Plakanin altindaki satir: "Daire A - 5 · Ali Y." / "Misafir — Daire A - 5"; kimlik yoksa ""."""
    return str((olay or {}).get("etiket") or "")


def olay_satiri(olay: dict, zaman: str) -> tuple:
    """Canli Olaylar tablosu satiri: zaman, kamera, yon, plaka, karar, kimlik, kapi durumu, neden, guven."""
    return (zaman, olay["kamera_id"], olay["yon"], olay["plaka"], KARAR_METIN.get(olay["karar"], olay["karar"]),
            kimlik_satiri(olay), kapi_metni(olay.get("kapi_komut")), olay["neden"], f"{olay['guven']:.2f}")


def sunucu_kaynakli(kamera: dict | None) -> bool:
    return (kamera or {}).get("kaynak") == "sunucu"
