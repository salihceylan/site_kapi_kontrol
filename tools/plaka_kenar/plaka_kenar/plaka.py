"""TR plaka metni: normallestirme, konuma gore OCR karisikligi duzeltme, regex dogrulama."""
from __future__ import annotations

import re

from .ayarlar import SINIFLAR, TR_PLAKA_REGEX

_TR_HARF = str.maketrans("İıŞşÇçĞğÖöÜü", "IISSCCGGOOUU")
_HARFLER = set(c for c in SINIFLAR if c.isalpha())
# Rakam konumunda harf okunduysa muhtemel rakam / harf konumunda rakam okunduysa muhtemel harf.
_RAKAMA = {"O": "0", "Q": "0", "D": "0", "I": "1", "L": "1", "B": "8", "S": "5", "Z": "2", "G": "6"}
_HARFE = {"0": "O", "1": "I", "8": "B", "5": "S", "2": "Z", "6": "G"}
_INF = 10 ** 6


def normalize(ham: str) -> str:
    """Buyuk harf, Turkce karakterleri ASCII'ye indir, harf/rakam disini at."""
    s = (ham or "").translate(_TR_HARF).upper()
    return re.sub(r"[^A-Z0-9]", "", s)


def bicimle(norm: str, il_uzunluk: int = 2, harf_sayisi: int = 0) -> str:
    """'34ABC123' -> '34 ABC 123' (harf_sayisi verilmemisse normalize metinden bulunur)."""
    if not harf_sayisi:
        harf_sayisi = sum(1 for c in norm[il_uzunluk:] if c.isalpha())
    return f"{norm[:il_uzunluk]} {norm[il_uzunluk:il_uzunluk + harf_sayisi]} {norm[il_uzunluk + harf_sayisi:]}"


def _maliyet(c: str, rakam_mi: bool) -> int:
    if rakam_mi:
        return 0 if c.isdigit() else (1 if c in _RAKAMA else _INF)
    return 0 if c in _HARFLER else (1 if c in _HARFE else _INF)


def coz(ham: str, regex: str = TR_PLAKA_REGEX, duzeltme: bool = True):
    """Ham OCR metnini TR plakasina cevirir. (bicimli, kanonik) ya da None.
    il(2 rakam) + 1-3 harf + 2-4 rakam yapisina gore konum bazli karisiklik duzeltilir."""
    s = normalize(ham)
    n = len(s)
    en_iyi = None
    for harf in (1, 2, 3):
        rakam = n - 2 - harf
        if not 2 <= rakam <= 4:
            continue
        maliyet = sum(_maliyet(c, True) for c in s[:2])
        maliyet += sum(_maliyet(c, False) for c in s[2:2 + harf])
        maliyet += sum(_maliyet(c, True) for c in s[2 + harf:])
        if maliyet >= _INF or (maliyet and not duzeltme):
            continue
        if en_iyi is None or maliyet < en_iyi[0]:
            en_iyi = (maliyet, harf)
    if en_iyi is None:
        return None
    harf = en_iyi[1]
    parca = []
    for i, c in enumerate(s):
        if i < 2 or i >= 2 + harf:
            parca.append(_RAKAMA.get(c, c) if not c.isdigit() else c)
        else:
            parca.append(_HARFE.get(c, c) if not c.isalpha() else c)
    kanonik = "".join(parca)
    bicimli = bicimle(kanonik, 2, harf)
    return (bicimli, kanonik) if gecerli(bicimli, regex) else None


def gecerli(metin: str, regex: str = TR_PLAKA_REGEX) -> bool:
    return re.match(regex, metin or "") is not None


def kanonik(metin: str) -> str:
    """Karsilastirma anahtari: bosluksuz buyuk harf (izin listesi bununla aranir)."""
    return normalize(metin)


def il_gecerli(il: str) -> bool:
    return len(il) == 2 and il.isdigit() and 1 <= int(il) <= 81


def _pozisyon_adaylari(dagilim: dict, rakam_mi: bool, pz: dict, duzeltme: bool) -> list:
    """Bir pozisyon icin beklenen sinifta (rakam/harf) [(skor, karakter, duzeltme_adedi)], skora gore azalan.
    Beklenen sinif disi karakter yalniz karisiklik tablosunda varsa (O->0, I->1 / 0->O, 8->B ...) ve skoru carpanla duser."""
    rakama, harfe = pz.get("rakama", _RAKAMA), pz.get("harfe", _HARFE)
    carp = float(pz.get("karisiklik_carpani", 0.85))
    en: dict = {}
    for c, s in dagilim.items():
        c = c.upper()
        if rakam_mi:
            hedef, dz = (c, 0) if c.isdigit() else (rakama.get(c), 1)
        else:
            hedef, dz = (c, 0) if c in _HARFLER else (harfe.get(c), 1)
        if hedef is None or (dz and not duzeltme):
            continue
        skor = float(s) * (carp if dz else 1.0)
        if hedef not in en or skor > en[hedef][0]:
            en[hedef] = (skor, hedef, dz)
    return sorted(en.values(), key=lambda a: -a[0])


def puanla_coz(dagilim: list, puanlama: dict | None = None, regex: str = TR_PLAKA_REGEX, duzeltme: bool = True):
    """Pozisyon dagilimlarindan (konsensus ciktisi) en yuksek puanli gecerli TR plakasini secer.
    Yapi: il(2 rakam, 01-81) + 1-3 harf + 2-4 rakam. Puan = format + il + karakter skoru - duzeltme cezasi (+ yerel il bonusu).
    Doner: (puan, bicimli, kanonik, duzeltme_adedi) ya da None."""
    pz = puanlama or {}
    n = len(dagilim)
    k = max(1, int(pz.get("il_alternatif", 3)))
    yerel = set(str(x) for x in pz.get("yerel_il_kodlari", []))
    en_iyi = None
    for harf in (1, 2, 3):
        if not 2 <= n - 2 - harf <= 4:
            continue
        il0 = _pozisyon_adaylari(dagilim[0], True, pz, duzeltme)[:k]
        il1 = _pozisyon_adaylari(dagilim[1], True, pz, duzeltme)[:k]
        govde, toplam, dz_govde, tamam = [], 0.0, 0, True
        for i in range(2, n):
            liste = _pozisyon_adaylari(dagilim[i], i >= 2 + harf, pz, duzeltme)
            if not liste:
                tamam = False
                break
            govde.append(liste[0][1])
            toplam += liste[0][0]
            dz_govde += liste[0][2]
        if not tamam:
            continue
        for a in il0:
            for b in il1:
                il = a[1] + b[1]
                if not il_gecerli(il):
                    continue
                dz = a[2] + b[2] + dz_govde
                ort = (a[0] + b[0] + toplam) / n
                puan = (float(pz.get("format_puan", 50.0)) + float(pz.get("il_puan", 20.0))
                        + float(pz.get("karakter_agirlik", 30.0)) * ort - float(pz.get("duzeltme_ceza", 4.0)) * dz
                        + (float(pz.get("yerel_il_bonus", 3.0)) if il in yerel else 0.0))
                kan = il + "".join(govde)
                bic = bicimle(kan, 2, harf)
                if gecerli(bic, regex) and (en_iyi is None or puan > en_iyi[0]):
                    en_iyi = (puan, bic, kan, dz)
    return en_iyi
