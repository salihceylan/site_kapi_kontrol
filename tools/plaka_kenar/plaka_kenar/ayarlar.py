"""ayarlar.json yukleme/kaydetme. Esik, oran, adres ve yollarin HICBIRI kodda sabit degildir:
buradaki VARSAYILAN yalnizca dosyada olmayan anahtarlarin geri-dusus degeridir."""
from __future__ import annotations

import copy
import json
import os
import re
import sys
import threading
from pathlib import Path

SURUM = "0.3.0"
# Sunucu sozlesmesi (docs/PLATFORM_PLAKA_KENAR_SOZLESMESI.md): 2 = olay karar turu "kara_liste" (A3);
# 3 = uzaktan komutlar (kesif / sinama), goruntu karolari, sunucu kamera tanimlari, kimlik + kapi komutu alanlari. Sunucu 1, 2 ve 3'u kabul eder.
SCHEMA_VERSION = 3
_KAYIT_KILIDI = threading.Lock()  # arayuz Kaydet'i ile servisin sunucu kamera birlestirmesi ayni dosyayi yazar

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
        "komut_aralik_sn": 5,  # uzaktan komut (kesif / sinama) hizli yoklamasi; kalp atisi yaniti da komut tasir
        "komut_sonuc_deneme": 3,  # komut sonucu gecici hatada bu kadar kez denenir
        "komut_sonuc_bekle_sn": 2.0,
        # A1 sozlesmesindeki GERCEK yollar (/edge/plate/v1); tek tek kapatilabilir. {id}: komut / kamera kimligi.
        "uclar": {
            "kayit": {"etkin": True, "yol": "/edge/plate/v1/claim"},
            "senkron": {"etkin": True, "yol": "/edge/plate/v1/sync"},
            "olay": {"etkin": True, "yol": "/edge/plate/v1/events"},
            "kalp_atisi": {"etkin": True, "yol": "/edge/plate/v1/heartbeat"},
            "komutlar": {"etkin": True, "yol": "/edge/plate/v1/commands"},
            "komut_sonuc": {"etkin": True, "yol": "/edge/plate/v1/commands/{id}/result"},
            "goruntu": {"etkin": True, "yol": "/edge/plate/v1/cameras/{id}/snapshot"},
        },
    },
    # Goruntu karolari: etkin her kameradan kucuk JPEG (yalniz SON kare sunucuda tutulur, tarihce yok - KVKK). Aralik SUNUCUDAN gelir
    # (izleyen varken / yokken); buradaki aralik_sn ALT SINIRDIR. etkin=false: hic gonderilmez.
    "goruntu_gonderim": {
        "etkin": True,
        "aralik_sn": 4,
        "bosta_aralik_sn": 15,  # sunucu "izleyen yok" der ama aralik vermezse kullanilan geri-dusus
        "yukseklik": 360,
        "kalite": 60,
        "en_cok_bayt": 262144,
        "hata_bekleme_en_cok_sn": 60,
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
        "alternatif_k": 3,  # her karakter icin konsensusa verilen en iyi aday sayisi (yalniz onnx)
    },
    "plaka": {"regex": TR_PLAKA_REGEX, "min_guven": 0.6, "duzeltme": True},
    # Okuma hassasiyeti paketi. Kamera satirinda "profil" (gunduz|gece|oto) ve "roi" ([x, y, w, h] oran 0-1) ezer.
    "on_isleme": {
        "etkin": True,
        "profil": "oto",  # gunduz | gece | oto (kare parlakligindan secer)
        "gece_parlaklik_esik": 70,  # oto: kirpilan karenin ortalama gri degeri bunun altindaysa gece
        "tespit_oncesi": "gece",  # hep | gece | yok: tespitten once kareye CLAHE+golge dengeleme
        "otsu_min_ayrim": 0.55,  # Otsu sinif ayrim orani (0-1) bunun altindaysa adaptif esige dus
        "profiller": {
            "gunduz": {"clahe_clip": 2.0, "clahe_kare": 8, "golge_denge": True, "golge_cekirdek_oran": 0.9,
                       "gamma": 1.0, "yuzdelik_kirp": [0.0, 100.0], "adaptif_blok": 31, "adaptif_c": 8},
            "gece": {"clahe_clip": 3.5, "clahe_kare": 6, "golge_denge": True, "golge_cekirdek_oran": 0.9,
                     "gamma": 0.85, "yuzdelik_kirp": [1.0, 99.0], "adaptif_blok": 25, "adaptif_c": 6},
        },
    },
    # Cok-kare konsensus: plaka KARAKTER bazinda oylanir; tek kare yanlislari elenir.
    "konsensus": {
        "etkin": True,
        "kare_pencere": 5,  # oylamaya girecek son kare sayisi (3-5)
        "kare_min": 3,  # en az bu kadar ayni uzunlukta okuma yoksa sonuc yok (tetik_kare_sayisi >= kare_min olmali)
        "pencere_sn": 4.0,  # bundan eski okumalar oya girmez
        "gozlem_min_guven": 0.35,  # kare okumasi bunun altindaysa oya katilmaz
        "pozisyon_min_oy": 0.5,  # her pozisyonda kazanan karakterin oy orani bunun altindaysa 'dogrulanmamis'
        "guven_esik": 0.8,  # birlesik guven bunun altindaysa okuma 'dogrulanmamis' (kapi acilmaz)
    },
    # Akilli puanlama: yapi (il + 1-3 harf + 2-4 rakam), il kodu, konuma gore karisiklik duzeltme.
    "puanlama": {
        "format_puan": 50.0,
        "il_puan": 20.0,
        "yerel_il_kodlari": [],  # ornek ["34"]: sitenin ili; esit puanda tercih edilir
        "yerel_il_bonus": 3.0,
        "karakter_agirlik": 30.0,  # ortalama karakter skoru (0-1) x agirlik
        "duzeltme_ceza": 4.0,  # her karisiklik duzeltmesi icin dusulen puan
        "karisiklik_carpani": 0.85,  # duzeltilen karakterin skoruna uygulanir
        "duzeltme_guven_carpani": 0.92,  # her duzeltme icin birlesik guvene
        "il_alternatif": 3,  # il rakamlari icin denenen aday sayisi
        "rakama": {"O": "0", "Q": "0", "D": "0", "I": "1", "L": "1", "B": "8", "S": "5", "Z": "2", "G": "6"},
        "harfe": {"0": "O", "1": "I", "8": "B", "5": "S", "2": "Z", "6": "G"},
    },
    # Canli izleme sekmesi
    # Agda kamera kesfi: ONVIF WS-Discovery + yerel alt ag TCP taramasi (birlikte) - Kameralar sekmesi 'Agda kamera ara'
    "kesif": {
        "sure_sn": 3.5, "zaman_asimi_sn": 4.0, "rtsp_port": 554,
        "onvif_portlar": [80, 8000, 8080, 2020],  # ONVIF GetStreamUri denenen servis portlari (kamera XAddrs vermezse)
        "tarama": {
            "etkin": True,
            "portlar": [554, 80, 8000, 8080, 2020],  # 554 RTSP, 80/8080 web, 8000 Hikvision/ONVIF, 2020 Tapo ONVIF
            "zaman_asimi_sn": 0.3,  # her baglanti denemesi
            "is_parcacigi": 256,
            "alt_ag_uzunlugu": 24,  # PC'nin IPv4 adresinin /24 agi taranir
            "tur": 1,  # >1: yanit vermeyen (zaman asimi) portlar toplam bu kadar tur denenir (yavas ARP/Wi-Fi kameralar icin)
            "haric_aglar": ["100.64.0.0/10"],  # taranmayacak aglar (Tailscale/CGNAT gibi VPN arayuzleri)
            "rtsp_portlari": [554, 8554],  # bu portlardan biri aciksa 'RTSP var' diye siralamada one alinir
            "kamera_portlari": [554, 8000, 2020, 8554],  # 80/8080 tek basina (yonlendirici, yazici) daha dusuk olasilik
        },
    },
    # Canli izleme MOZAIGI: tum etkin kameralar ayni anda. goruntu_fps = akis -> karo yayin hizi (ISLEME fps'inden bagimsiz);
    # fps = arayuz cizim hizi; karo_yukseklik = mozaik karosunun kare yuksekligi (px, ~360p); buyuk_yukseklik = tek kamera modu (0 = tam cozunurluk).
    "izleme": {"fps": 12, "goruntu_fps": 12, "karo_yukseklik": 360, "buyuk_yukseklik": 720, "goruntu_yok_sn": 3.0,
               "rozet_sn": 4.0, "kare_genislik": 640, "fps_ema": 0.3, "min_roi": 0.05},
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
    sonuc = derin_birlestir(VARSAYILAN, ek)
    # Sozlesme surumu kodun sabitidir, ayar degil: eski surumun kaydettigi dosya yeni alanlari (v3) susturmasin.
    sonuc["sunucu"]["schema_version"] = max(int(sonuc["sunucu"].get("schema_version") or 0), SCHEMA_VERSION)
    return sonuc


def kaydet(ayar: dict, yol: Path | str | None = None) -> Path:
    p = Path(yol) if yol else varsayilan_yol()
    p.parent.mkdir(parents=True, exist_ok=True)
    gecici = p.with_suffix(".tmp")
    with _KAYIT_KILIDI:
        with open(gecici, "w", encoding="utf-8") as f:
            json.dump(ayar, f, ensure_ascii=False, indent=2)
        os.replace(gecici, p)
    return p


def sunucu_kameralarini_yaz(kameralar: list, yol: Path | str | None = None) -> Path:
    """Sunucudan inen kamera satirlarini (kaynak: "sunucu") dosyaya isler. Dosyadaki baska HER SEY (yerel satirlar, arayuzde henuz
    kaydedilmemis degisiklikler dahil bellekteki ayar) oldugu gibi kalir: yalniz sunucu-kaynakli satirlar degistirilir."""
    p = Path(yol) if yol else varsayilan_yol()
    ham: dict = {}
    if p.exists():
        with open(p, "r", encoding="utf-8") as f:
            ham = json.load(f)
    yerel = [k for k in ham.get("kameralar", []) if k.get("kaynak") != "sunucu"]
    ham["kameralar"] = yerel + [copy.deepcopy(k) for k in kameralar if k.get("kaynak") == "sunucu"]
    return kaydet(ham, p)


def _tam_sayi(v) -> bool:
    try:
        return int(v) > 0
    except (TypeError, ValueError):
        return False


def _roi_gecerli(r) -> bool:
    try:
        x, y, w, h = (float(v) for v in r)
    except (TypeError, ValueError):
        return False
    return 0 <= x < 1 and 0 <= y < 1 and w > 0 and h > 0 and x + w <= 1.0001 and y + h <= 1.0001


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
        if k.get("profil", "oto") not in ("gunduz", "gece", "oto"):
            u.append(f"Kamera {kid}: profil 'gunduz', 'gece' veya 'oto' olmali")
        r = k.get("roi")
        if r is not None and not _roi_gecerli(r):
            u.append(f"Kamera {kid}: roi [x, y, w, h] 0-1 oran olmali (x+w<=1, y+h<=1)")
    s = ayar.get("sunucu", {})
    # Sunucu baglantisi ISTEGE BAGLIDIR: adres/anahtar bos ise hicbir uyari cikmaz, olay gonderimi sessizce kapali kalir.
    if sunucu_hazir(ayar):
        if not re.fullmatch(r"\d{1,15}\.[a-f0-9]{48}", str(s["cihaz_anahtari"]).strip()):
            u.append("Cihaz anahtari '<id>.<48 onaltilik>' biciminde olmali")
        for k in ayar.get("kameralar", []):
            if k.get("etkin", True) and not _tam_sayi(k.get("sunucu_id")):
                u.append(f"Kamera {k.get('id')}: 'sunucu_id' (sunucudaki kamera kimligi) bos; olaylari sunucuya gonderilemez")
    if ayar.get("karar", {}).get("misafir_kurali") not in ("tum_yerler_bos", "en_az_bir_yer_bos"):
        u.append("karar.misafir_kurali gecersiz")
    for k in ayar.get("kameralar", []):
        if k.get("yon", "") not in ("", "giris", "cikis"):
            u.append(f"Kamera {k.get('id')}: yon 'giris' veya 'cikis' olmali")
        if k.get("kaynak") == "sunucu" and k.get("etkin", True) and not k.get("kapi_id"):
            u.append(f"Kamera {k.get('id')} (sunucudan): yerelde sunucu_id'si eslesen kapi yok; goruntu/sinama calisir ama kapi acilmaz "
                     "(kapi satirina sunucudaki kapi kimligini yazin)")
    g = ayar.get("goruntu_gonderim", {})
    if g.get("etkin", True):
        if not (_sayi(g.get("aralik_sn")) and float(g["aralik_sn"]) >= 1):
            u.append("goruntu_gonderim.aralik_sn en az 1 olmali")
        if not (_sayi(g.get("kalite")) and 10 <= float(g["kalite"]) <= 95):
            u.append("goruntu_gonderim.kalite 10-95 arasi olmali")
        if not (_sayi(g.get("yukseklik")) and float(g["yukseklik"]) >= 90):
            u.append("goruntu_gonderim.yukseklik en az 90 olmali")
        if not (_sayi(g.get("en_cok_bayt")) and float(g["en_cok_bayt"]) > 0):
            u.append("goruntu_gonderim.en_cok_bayt pozitif olmali")
    return u


def _sayi(v) -> bool:
    try:
        float(v)
        return True
    except (TypeError, ValueError):
        return False


def sunucu_hazir(ayar: dict) -> bool:
    """Sunucu baglantisi yalniz etkin VE adres + cihaz anahtari doluysa acik sayilir; aksi halde uygulama yalniz yerel calisir."""
    s = ayar.get("sunucu", {})
    return bool(s.get("etkin")) and bool(str(s.get("adres", "")).strip()) and bool(str(s.get("cihaz_anahtari", "")).strip())


def yon_uyarilari(ayar: dict) -> dict:
    """Kamera basina yon denetimi (SARI uyari, engel degil): {"kameralar": {kamera_id: metin}, "kapilar": {kapi_id: metin}}.
    Cift yonlu kapida en az bir giris + bir cikis kamerasi beklenir; giris/cikis kapisinda o yonde bir kamera beklenir.
    Yonu secilmemis kamera da isaretlenir (olay yonu kameradan alinir)."""
    kam_u: dict = {}
    kapi_u: dict = {}
    etkin = [k for k in ayar.get("kameralar", []) if k.get("etkin", True)]
    for k in etkin:
        if k.get("yon", "") not in ("giris", "cikis"):
            kam_u[k.get("id", "")] = "Yön seçilmemiş (giriş / çıkış)"
    for kapi in ayar.get("kapilar", []):
        kid, mod = kapi.get("id"), kapi.get("yon_modu", "cift")
        yonler = {k.get("yon") for k in etkin if k.get("kapi_id") == kid}
        beklenen = {"giris": ["giris"], "cikis": ["cikis"]}.get(mod, ["giris", "cikis"])
        eksik = [y for y in beklenen if y not in yonler]
        if not eksik:
            continue
        ad = " ve ".join("giriş" if y == "giris" else "çıkış" for y in eksik)
        kapi_u[kid] = f"{ad} kamerası eksik"
        for k in etkin:
            if k.get("kapi_id") == kid and k.get("id", "") not in kam_u:
                kam_u[k.get("id", "")] = f"Kapı '{kid}' için {ad} kamerası eksik"
    return {"kameralar": kam_u, "kapilar": kapi_u}


def siradaki_yon(ayar: dict, kapi_id: str = "") -> str:
    """Yeni eklenen kamera icin yon onerisi: ayni kapida giris kamerasi var ve cikis yoksa 'cikis'; digerleri 'giris'."""
    yonler = {k.get("yon") for k in ayar.get("kameralar", []) if k.get("etkin", True) and (k.get("kapi_id") or "") == (kapi_id or "")}
    return "cikis" if "giris" in yonler and "cikis" not in yonler else "giris"
