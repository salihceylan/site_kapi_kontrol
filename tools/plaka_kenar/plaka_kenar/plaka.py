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
