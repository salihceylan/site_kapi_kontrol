"""Sentetik karakter seti ureticisi: varliklar/ icindeki DINish fontlarindan (SIL OFL)
SINIFLAR'daki her karakter icin 28x28 gri PNG uretir (BEYAZ karakter / SIYAH zemin —
Segmentleyici.normalize() cikisiyla ayni sozlesme). Etiket emegi ve KVKK riski sifirdir.

Kullanim:  python egitim/sentetik_uret.py [--cikti egitim/veri] [--varyant 24]
Sonra:     python egitim/karakter_cnn_egit.py --veri egitim/veri --cikti egitim/cikti/karakter_cnn.onnx
"""
from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from plaka_kenar.ayarlar import SINIFLAR  # noqa: E402

KOK = Path(__file__).resolve().parent


def fontlar() -> list[Path]:
    f = sorted((KOK / "varliklar").glob("*.ttf"))
    if not f:
        raise SystemExit("varliklar/ icinde .ttf yok (DINish fontlari bekleniyor)")
    return f


def karakter_ciz(harf: str, font_yolu: Path, boy: int, kaydir: tuple[int, int], aci: float) -> Image.Image:
    buyuk = 112
    img = Image.new("L", (buyuk, buyuk), 0)
    cizer = ImageDraw.Draw(img)
    fnt = ImageFont.truetype(str(font_yolu), boy)
    sol, ust, sag, alt = cizer.textbbox((0, 0), harf, font=fnt)
    x = (buyuk - (sag - sol)) // 2 - sol + kaydir[0]
    y = (buyuk - (alt - ust)) // 2 - ust + kaydir[1]
    cizer.text((x, y), harf, fill=255, font=fnt)
    if aci:
        img = img.rotate(aci, resample=Image.BILINEAR, fillcolor=0)
    return img.resize((28, 28), Image.LANCZOS)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cikti", default=str(KOK / "veri"))
    ap.add_argument("--varyant", type=int, default=24, help="font basina karakter varyanti")
    ap.add_argument("--tohum", type=int, default=42)
    a = ap.parse_args()
    random.seed(a.tohum)
    cikti = Path(a.cikti)
    fl = fontlar()
    toplam = 0
    for harf in SINIFLAR:
        kl = cikti / harf
        kl.mkdir(parents=True, exist_ok=True)
        i = 0
        for fp in fl:
            for _ in range(a.varyant):
                boy = random.randint(78, 100)
                kay = (random.randint(-4, 4), random.randint(-4, 4))
                aci = random.uniform(-7.0, 7.0)
                karakter_ciz(harf, fp, boy, kay, aci).save(kl / f"{fp.stem}_{i:03d}.png")
                i += 1
        toplam += i
    print(f"uretildi: {toplam} ornek, {len(SINIFLAR)} sinif, {len(fl)} font -> {cikti}")


if __name__ == "__main__":
    main()
