"""ayarlar.json yukleme/kaydetme. Esik, oran, adres ve yollarin HICBIRI kodda sabit degildir:
buradaki VARSAYILAN yalnizca dosyada olmayan anahtarlarin geri-dusus degeridir."""
from __future__ import annotations

import copy
import json
import os
import re
import sys
from pathlib import Path

SURUM = "0.2.0"
# Sunucu sozlesmesi (docs/PLATFORM_PLAKA_KENAR_SOZLESMESI.md): 2 = olay karar turu "kara_liste" (A3). Sunucu 1 ve 2'yi kabul eder.
SCHEMA_VERSION = 2

# Plan 2. bolum: TR plaka regex'i (bicimlendirilmis "34 ABC 123" metnine uygulanir).
TR_PLAKA_REGEX = r"^(0[1-9]|[1-7][0-9]|8[01])\s?[A-PR-VYZ]{1,3}\s?\d{2,4}$"
# TR plakasinda kullanilan harfler (Q, W, X yok) + rakamlar.
SINIFLAR = "0123456789ABCDEFGHIJKLMNOPRSTUVYZ"

VARSAYILAN: dict = {
    "surum": 1,
    "sunucu": {
        "etkin": False,
        "adres": "",
        "site_kodu": "",  # yalniz gosterim icin; kimlik ve kapsam cihaz anahtaridir (anahtar hangi siteye bagliysa o)
        "cihaz_anahtari": "",  # yonetici ekraninda uretilen "<id>.<48 onaltilik>" (Authorization: Bearer)
        "schema_version": SCHEMA_VERSION,
        "zaman_asimi_sn": 8,
        "tls_dogrula": True,
        "senkron_aralik_sn": 60,
        "olay_gonderim_aralik_sn": 5,
        "olay_toplu_adet": 50,
        "kalp_atisi_aralik_sn": 90,
        "olay_saklama_gun": 7,  # kuyruktaki (gonderilmemis dahil) olaylar bu sureden sonra silinir
        # A1 sozlesmesindeki GERCEK yollar (/edge/plate/v1); tek tek kapatilabilir.
        "uclar": {
            "kayit": {"etkin": True, "yol": "/edge/plate/v1/claim"},
            "senkron": {"etkin": True, "yol": "/edge/plate/v1/sync"},
            "olay": {"etkin": True, "yol": "/edge/plate/v1/events"},
            "kalp_atisi": {"etkin": True, "yol": "/edge/plate/v1/heartbeat"},
        },
    },
    # Sinirsiz satir. Ornek: {"id":"giris1","ad":"Giris","url":"rtsp://...","mod":"akis|tetik",
    #   "fps":3,"kapi_id":"kapi1","yon":"giris|cikis|","etkin":true,"roi":[0,0,1,1],
    #   "sunucu_id":7}   <- sunucudaki kamera kimligi (yonetici ekrani: Gecis noktalari); olay ve kalp atisi bununla gider
    "kameralar": [],
    # Ornek: {"id":"kapi1","ad":"Ana kapi","yon_modu":"giris|cikis|cift","skp_uid":"240AC4E2E001",
    #   "skp_ip":"","skp_token":"","komut":"open","sunucu_id":1}   (sunucu_id isteğe bagli: bos ise sunucu kapiyi kamera baglantisindan turetir)
    "kapilar": [],
    "yakalama": {
        "rtsp_tasima": "tcp",
        "yeniden_baglan_sn": 5,
        "tetik_kare_sayisi": 3,
        "tetik_aralik_sn": 0.3,
        "okuma_zaman_asimi_ms": 5000,
    },
    "tespit": {
        "tur": "klasik",
        "klasik": {
            "olcek_genislik": 960,
            "bulaniklik": 5,
            "kapama_cekirdek": [17, 3],
            "erozyon_tekrar": 2,
            "genlesme_tekrar": 2,
            "genisletme": [1.1, 2.2],
            "en_boy_min": 2.8,
            "en_boy_max": 6.5,
            "hedef_en_boy": 4.7,
            "alan_min_oran": 0.0015,
            "alan_max_oran": 0.25,
            "doluluk_min": 0.45,
            "aci_max": 20,
            "max_aday": 4,
            "cikis_boyut": [376, 80],
        },
    },
    "segmentleme": {
        "sol_kirp_oran": 0.0,
        "kenar_kirp_oran": 0.04,
        "yukseklik_min_oran": 0.35,
        "yukseklik_max_oran": 0.98,
        "genislik_max_oran": 0.22,
        "min_karakter": 5,
        "max_karakter": 9,
    },
    "tanima": {
        "tur": "otomatik",  # otomatik | onnx | sablon
        "model_yolu": "modeller/karakter.onnx",
        "model_onayli": True,  # false: model yuklenir ama okumalar 'dogrulanmamis' kalir (saha denemesi)
        "sablon_dizini": "sablonlar",
        "sablon_onayli": False,  # sahada dogrulama bitince elle true yapilir
        "sablon_min_ornek": 3,
        "siniflar": SINIFLAR,
        "karakter_boyut": 28,
    },
    "plaka": {"regex": TR_PLAKA_REGEX, "min_guven": 0.6, "duzeltme": True},
    "dogrulama": {"teyit_kare": 2, "teyit_pencere_sn": 4.0, "tekillestirme_sn": 5.0},
    "karar": {
        # tum_yerler_bos | en_az_bir_yer_bos  (plan 5, soru 3)
        # Sunucudan gelen site ayari (config.settings.guest_rule) ilk senkrondan sonra BUNU ezer; yerel deger yalniz ilk senkrona kadar geri-dusustur.
        "misafir_kurali": "tum_yerler_bos",
        # Kara listedeki plaka ASLA acilmaz (giris). Cikis icin de varsayilan kapali; true: kara listedeki aracin CIKISINA izin verilir
        # (iceride kalan araci hapsetmemek icin yonetici karariyla; kapali iken guvenlik gorevlisi elle acar).
        "kara_liste_cikis_acilir": False,
        "tanimsiz_kare_sakla": False,
        "tanimsiz_kare_gun": 7,
        "tanimsiz_kare_dizini": "veri/tanimsiz",
        "kalibrasyon_kare_kaydet": False,
        "kalibrasyon_dizini": "veri/kalibrasyon",
    },
    "skp": {
        "port": 8765,
        "zaman_asimi_sn": 1.5,
        "yeniden_deneme": 1,
        "yayin_adresi": "255.255.255.255",
        "izinli_komutlar": ["open", "pulse"],
    },
    "veri": {"izin_db": "veri/izin.db", "olay_db": "veri/olay.db", "gunluk": "veri/plaka_kenar.log"},
    "arayuz": {"olay_seridi_satir": 300},
}


def uygulama_dizini() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


def varsayilan_yol() -> Path:
    env = os.environ.get("PLAKA_KENAR_AYAR")
    return Path(env) if env else uygulama_dizini() / "ayarlar.json"


def yol_coz(goreli: str, taban: Path | None = None) -> Path:
    p = Path(goreli)
    return p if p.is_absolute() else (taban or uygulama_dizini()) / p


def derin_birlestir(taban: dict, ek: dict) -> dict:
    sonuc = copy.deepcopy(taban)
    for k, v in (ek or {}).items():
        if isinstance(v, dict) and isinstance(sonuc.get(k), dict):
            sonuc[k] = derin_birlestir(sonuc[k], v)
        else:
            sonuc[k] = copy.deepcopy(v)
    return sonuc


def yukle(yol: Path | str | None = None) -> dict:
    p = Path(yol) if yol else varsayilan_yol()
    ek: dict = {}
    if p.exists():
        with open(p, "r", encoding="utf-8") as f:
            ek = json.load(f)
    return derin_birlestir(VARSAYILAN, ek)


def kaydet(ayar: dict, yol: Path | str | None = None) -> Path:
    p = Path(yol) if yol else varsayilan_yol()
    p.parent.mkdir(parents=True, exist_ok=True)
    gecici = p.with_suffix(".tmp")
    with open(gecici, "w", encoding="utf-8") as f:
        json.dump(ayar, f, ensure_ascii=False, indent=2)
    os.replace(gecici, p)
    return p


def _tam_sayi(v) -> bool:
    try:
        return int(v) > 0
    except (TypeError, ValueError):
        return False


def dogrula(ayar: dict) -> list[str]:
    """Insan-okur uyarilar dondurur (bos liste = sorun yok)."""
    u: list[str] = []
    kapi_idleri = {k.get("id") for k in ayar.get("kapilar", [])}
    idler: set = set()
    for k in ayar.get("kameralar", []):
        kid = k.get("id")
        if not kid:
            u.append("Kamera satirinda 'id' bos")
        elif kid in idler:
            u.append(f"Kamera id tekrar: {kid}")
        idler.add(kid)
        if k.get("kapi_id") and k["kapi_id"] not in kapi_idleri:
            u.append(f"Kamera {kid}: kapi_id '{k['kapi_id']}' tanimli degil")
        if k.get("mod", "akis") not in ("akis", "tetik"):
            u.append(f"Kamera {kid}: mod 'akis' veya 'tetik' olmali")
    s = ayar.get("sunucu", {})
    if s.get("etkin") and not (s.get("adres") and s.get("cihaz_anahtari")):
        u.append("Sunucu etkin ama adres/cihaz_anahtari eksik")
    if s.get("etkin") and s.get("cihaz_anahtari") and not re.fullmatch(r"\d{1,15}\.[a-f0-9]{48}", str(s["cihaz_anahtari"]).strip()):
        u.append("Cihaz anahtari '<id>.<48 onaltilik>' biciminde olmali")
    if s.get("etkin"):
        for k in ayar.get("kameralar", []):
            if k.get("etkin", True) and not _tam_sayi(k.get("sunucu_id")):
                u.append(f"Kamera {k.get('id')}: 'sunucu_id' (sunucudaki kamera kimligi) bos; olaylari sunucuya gonderilemez")
    if ayar.get("karar", {}).get("misafir_kurali") not in ("tum_yerler_bos", "en_az_bir_yer_bos"):
        u.append("karar.misafir_kurali gecersiz")
    return u
