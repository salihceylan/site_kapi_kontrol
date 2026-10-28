# -*- coding: utf-8 -*-
"""PlatformIO ON-DERLEME betigi (platformio.ini: extra_scripts = pre:tools/ota_anahtar_kontrol_pio.py).

include/ota_public_key.h hala YER TUTUCU ise derleme cikisina belirgin bir UYARI basar. Yer tutuculu bir firmware OTA ile kurulamaz
ve KURULDUGU cihaz da bir daha OTA ile guncellenemez (yer tutucuyu cihaz calisma zamaninda tanir, hicbir paketi kurmaz) - bu yuzden
yayin derlemesinde ortam degiskeni ile derleme DURDURULABILIR:

    SKP_OTA_ANAHTAR_ZORUNLU=1  pio run -e lolin_c3_mini       (yer tutucu varsa derleme HATA ile biter)

Betik yalniz okur ve yazdirir; baska hicbir sey yapmaz. Hata olursa derlemeyi ENGELLEMEZ (yalnizca bilgi basar), ancak zorunlu
modda (SKP_OTA_ANAHTAR_ZORUNLU=1) denetim yapilamazsa da derleme durur: sessizce gecmek yayin guvenligini zayiflatirdi.
Ayrinti: docs/OTA_IMZA_CIHAZ.md  |  Yayin sonrasi ikili denetimi: node cihaz_kontrol/tools/ota_anahtar.mjs kontrol <firmware.bin> <genel_anahtar>
"""
import os
import re
import sys

try:
    Import("env")  # noqa: F821  (PlatformIO/SCons tarafindan saglanir)
except Exception:  # betik PlatformIO disinda (ornegin test) calistirilirsa
    env = None

YER_TUTUCU = b"OTA-PUBLIC-KEY-NOT-SET-REPLACE!!"


def derlemeyi_durdur():
    if env is not None:
        env.Exit(1)  # SCons: derleme hata koduyla biter
    sys.exit(1)


def baslik_yolu():
    """cihaz_kontrol/platformio.ini ($PROJECT_DIR/include) ve depo kokundeki platformio.ini (include_dir = cihaz_kontrol/include) icin."""
    if env is None:
        return os.path.join(os.getcwd(), "include", "ota_public_key.h")
    include_dizini = env.subst("$PROJECT_INCLUDE_DIR")
    if include_dizini and os.path.isfile(os.path.join(include_dizini, "ota_public_key.h")):
        return os.path.join(include_dizini, "ota_public_key.h")
    return os.path.join(env.subst("$PROJECT_DIR"), "include", "ota_public_key.h")


def anahtar_baytlari(metin):
    """Basliktaki 0xNN sabitlerinden 32 bayt okur (yorum satirlari dahil sayilmaz)."""
    govde = "\n".join(s.split("//")[0] for s in metin.splitlines())
    dizi = re.search(r"OTA_IMZA_GENEL_ANAHTAR\s*\[\s*32\s*\]\s*=\s*\{(.*?)\}", govde, re.S)
    if not dizi:
        return None
    baytlar = re.findall(r"0x([0-9a-fA-F]{2})", dizi.group(1))
    if len(baytlar) != 32:
        return None
    return bytes(int(b, 16) for b in baytlar)


def kontrol():
    zorunlu = os.environ.get("SKP_OTA_ANAHTAR_ZORUNLU") == "1"
    yol = baslik_yolu()
    try:
        with open(yol, encoding="utf-8", errors="replace") as f:
            anahtar = anahtar_baytlari(f.read())
    except OSError as hata:
        anahtar = None
        print("[OTA imza] UYARI: %s okunamadi (%s); anahtar durumu denetlenemedi." % (yol, hata))
    if anahtar is None:
        if zorunlu:
            print("[OTA imza] HATA: SKP_OTA_ANAHTAR_ZORUNLU=1 ama ota_public_key.h anahtari okunamadi; derleme durduruldu.")
            derlemeyi_durdur()
        return
    if anahtar == YER_TUTUCU:
        satir = "=" * 100
        print(satir)
        print("[OTA imza] UYARI: include/ota_public_key.h hala YER TUTUCU. Bu firmware OTA ile hicbir paketi KURMAZ;")
        print("           sahaya cikarsa cihazlar bir daha OTA ile guncellenemez (USB gerekir).")
        print("           Gercek anahtari yazin: node cihaz_kontrol/tools/ota_anahtar.mjs yaz <genel_anahtar>")
        print(satir)
        if zorunlu:
            print("[OTA imza] HATA: SKP_OTA_ANAHTAR_ZORUNLU=1 -> yer tutuculu derleme durduruldu.")
            derlemeyi_durdur()
    else:
        print("[OTA imza] ota_public_key.h: gercek anahtar yerlestirilmis (yer tutucu degil).")


kontrol()
