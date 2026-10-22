#!/usr/bin/env python3
"""Demo plakalarinin gercek Turk plakasi gorunumunde PNG onizlemesini uretir (yalniz onizleme; uygulama plakayi duz metin gosterir).

Kullanim:
    python make_plate_previews.py --report out/vehicles-report-demo-vehicles-YYYYMMDDHHMMSS.json
    python make_plate_previews.py --plates "35 ABC 123, 35 AB 1234, 06 A 4821"

Cikti (varsayilan out/plaka_onizleme/, .gitignore'dadir):
    <plaka>.png   (ornek 35ABC123.png)  beyaz zemin, solda mavi serit + "TR", siyah kalin karakterler, yuvarlatilmis cerceve
    plakalar.png  hepsinin tek sayfada ozeti (daire, sahip, arac notu ile)

Gereksinim: pip install pillow. Girdi raporu add_vehicles.mjs ciktisidir (sifre / kimlik icermez).
Not: gercek Turk plakasinda mavi seritte yalniz "TR" yazar (AB'nin 12 yildizi yoktur); olcu orani 520x110 mm = 4,73:1.
"""

import argparse
import json
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "out", "plaka_onizleme")

PLATE_W, PLATE_H = 1040, 220  # 520x110 mm x 2
SS = 2  # supersampling
BLUE = (0, 51, 153)
INK = (14, 14, 16)


def first_font(candidates, size, variation=None):
    for path in candidates:
        if os.path.exists(path):
            try:
                font = ImageFont.truetype(path, size)
                if variation:
                    try:
                        font.set_variation_by_name(variation)
                    except Exception:
                        pass
                return font
            except Exception:
                continue
    return ImageFont.load_default()


PLATE_FONTS = [
    r"C:\Windows\Fonts\bahnschrift.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSansNarrow-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]
TEXT_FONTS = [r"C:\Windows\Fonts\segoeui.ttf", r"C:\Windows\Fonts\arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
TEXT_BOLD_FONTS = [r"C:\Windows\Fonts\segoeuib.ttf", r"C:\Windows\Fonts\arialbd.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]


def plate_font(size):
    return first_font(PLATE_FONTS, size, "Bold SemiCondensed")


def normalize(text):
    return re.sub(r"[\s\-._]", "", str(text)).upper()


def split_display(text):
    """'35 ABC 123' ya da '35ABC123' -> ('35', 'ABC', '123')."""
    norm = normalize(text)
    m = re.match(r"^(\d{2})([A-Z]{1,3})(\d{2,4})$", norm)
    if not m:
        raise ValueError(f"gecersiz plaka: {text!r}")
    return m.group(1), m.group(2), m.group(3)


def gradient(size, top, bottom):
    w, h = size
    col = Image.new("RGBA", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        col.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4)))
    return col.resize((w, h))


def draw_plate(display):
    """Plakanin kendisini (RGBA, seffaf koseler) 1040x220 olarak cizer."""
    il, letters, digits = split_display(display)
    w, h = PLATE_W * SS, PLATE_H * SS
    radius = 24 * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)

    base = Image.new("RGBA", (w, h), (250, 250, 247, 255))
    d = ImageDraw.Draw(base)
    strip_w = 116 * SS
    d.rectangle((0, 0, strip_w, h), fill=BLUE)

    # mavi seritte "TR"
    tr_font = first_font(TEXT_BOLD_FONTS, 62 * SS)
    tw = d.textlength("TR", font=tr_font)
    d.text(((strip_w - tw) / 2, h - 30 * SS), "TR", font=tr_font, fill=(255, 255, 255), anchor="ls")

    # karakterler
    avail_left = strip_w + 30 * SS
    avail_right = w - 34 * SS
    avail = avail_right - avail_left
    size = int(h * 0.80)
    while True:
        font = plate_font(size)
        track = int(size * 0.045)
        gap = int(size * 0.34)
        groups = [il, letters, digits]
        widths = [sum(d.textlength(ch, font=font) + track for ch in g) - track for g in groups]
        total = sum(widths) + gap * (len(groups) - 1)
        if total <= avail or size < 40 * SS:
            break
        size -= 4 * SS
    cap = font.getbbox("H", anchor="ls")  # (l, t, r, b) baseline-anchored; t negatif
    cap_h = -cap[1]
    # hedef: karakter yuksekligi plaka yuksekliginin ~%62'si
    target = h * 0.62
    if cap_h > target:
        scale = target / cap_h
        size = int(size * scale)
        font = plate_font(size)
        track = int(size * 0.045)
        gap = int(size * 0.34)
        widths = [sum(d.textlength(ch, font=font) + track for ch in g) - track for g in groups]
        total = sum(widths) + gap * (len(groups) - 1)
        cap_h = -font.getbbox("H", anchor="ls")[1]
    baseline = h / 2 + cap_h / 2 + 2 * SS
    x = avail_left + (avail - total) / 2
    for gi, g in enumerate(groups):
        for ch in g:
            d.text((x + 3 * SS, baseline + 3 * SS), ch, font=font, fill=(190, 190, 186), anchor="ls")  # kabartma golgesi
            d.text((x, baseline), ch, font=font, fill=INK, anchor="ls")
            x += d.textlength(ch, font=font) + track
        x += gap - track

    # parlama (hafif)
    base = Image.alpha_composite(base, gradient((w, h), (255, 255, 255, 46), (0, 0, 0, 22)))
    # ince siyah cerceve (kose yuvarlak)
    d2 = ImageDraw.Draw(base)
    inset = 9 * SS
    d2.rounded_rectangle((inset, inset, w - 1 - inset, h - 1 - inset), radius=radius - inset // 2, outline=INK, width=4 * SS)
    # dis kenar (alüminyum)
    img.paste(base, (0, 0), mask)
    ImageDraw.Draw(img).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, outline=(120, 120, 120, 255), width=2 * SS)
    return img.resize((PLATE_W, PLATE_H), Image.LANCZOS)


def with_shadow(plate, margin=26, bg=(233, 237, 242)):
    w, h = plate.size
    canvas = Image.new("RGB", (w + 2 * margin, h + 2 * margin), bg)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_mask = Image.new("L", plate.size, 255)
    shadow.paste((0, 0, 0, 90), (margin + 4, margin + 10), Image.composite(shadow_mask, Image.new("L", plate.size, 0), plate.getchannel("A")))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    canvas.paste(plate, (margin, margin), plate)
    return canvas.convert("RGB")


def load_items(args):
    items = []
    if args.report:
        with open(args.report, encoding="utf-8") as fh:
            data = json.load(fh)
        site = (data.get("site") or {}).get("name") or ""
        for a in data.get("added", []):
            items.append({"plate": a["plate"], "display": a.get("display"), "apartment": a.get("apartment", ""), "person": a.get("person", ""), "note": a.get("note", ""), "kept": False})
        if not args.only_added:
            for k in data.get("kept", []):
                items.append({"plate": k["plate"], "display": k.get("display"), "apartment": k.get("apartment", ""), "person": "", "note": k.get("note") or "", "kept": True})
        args.site_name = site
    if args.plates:
        for p in re.split(r"[,;]", args.plates):
            if p.strip():
                items.append({"plate": normalize(p), "display": None, "apartment": "", "person": "", "note": "", "kept": False})
    return items


def make_sheet(items, plates, out_path, site_name):
    cols = 3
    cell_w, cell_h = 560, 200
    pad = 30
    rows = (len(items) + cols - 1) // cols
    title_h = 110
    w = pad * 2 + cols * cell_w
    h = title_h + rows * cell_h + pad
    sheet = Image.new("RGB", (w, h), (242, 244, 247))
    d = ImageDraw.Draw(sheet)
    title_font = first_font(TEXT_BOLD_FONTS, 34)
    sub_font = first_font(TEXT_FONTS, 20)
    cap_font = first_font(TEXT_BOLD_FONTS, 20)
    small_font = first_font(TEXT_FONTS, 18)
    added = sum(1 for it in items if not it["kept"])
    kept = len(items) - added
    d.text((pad, 24), f"Demo plakalar{(' - ' + site_name) if site_name else ''}", font=title_font, fill=(24, 30, 40))
    d.text((pad, 68), f"{added} yeni arac" + (f" + {kept} mevcut" if kept else "") + "  |  uygulamada plaka duz metin gosterilir; bu sayfa yalniz gorunum onizlemesidir", font=sub_font, fill=(90, 98, 112))
    for i, it in enumerate(items):
        r, c = divmod(i, cols)
        x0 = pad + c * cell_w
        y0 = title_h + r * cell_h
        plate = plates[it["plate"]].resize((520, int(520 * PLATE_H / PLATE_W)), Image.LANCZOS)
        sheet.paste(plate, (x0 + 20, y0 + 6), plate)
        ty = y0 + 6 + plate.size[1] + 8
        line1 = it["apartment"] or ""
        if it["kept"]:
            line1 = (line1 + "  (mevcut)").strip()
        if line1:
            d.text((x0 + 22, ty), line1, font=cap_font, fill=(24, 30, 40))
        line2 = " - ".join(x for x in (it["person"], it["note"]) if x)
        if line2:
            d.text((x0 + 22, ty + 26), line2, font=small_font, fill=(90, 98, 112))
    sheet.save(out_path, "PNG", optimize=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--report", help="add_vehicles.mjs rapor JSON'u")
    ap.add_argument("--plates", help="virgulle ayrilmis plakalar (ornek: '35 ABC 123, 34 AB 1234')")
    ap.add_argument("--out-dir", default=DEFAULT_OUT)
    ap.add_argument("--only-added", action="store_true", help="mevcut araclari tek sayfaya katma")
    args = ap.parse_args()
    args.site_name = ""
    items = load_items(args)
    if not items:
        print("Plaka yok: --report ya da --plates verin.", file=sys.stderr)
        return 2
    os.makedirs(args.out_dir, exist_ok=True)
    plates = {}
    for it in items:
        try:
            plates[it["plate"]] = draw_plate(it["plate"])
        except ValueError as exc:
            print(f"ATLANDI: {exc}", file=sys.stderr)
    items = [it for it in items if it["plate"] in plates]
    for plate_key, img in plates.items():
        with_shadow(img).save(os.path.join(args.out_dir, f"{plate_key}.png"), "PNG", optimize=True)
    sheet_path = os.path.join(args.out_dir, "plakalar.png")
    make_sheet(items, plates, sheet_path, args.site_name)
    print(f"{len(plates)} plaka PNG: {os.path.abspath(args.out_dir)}")
    print(f"Tek sayfa ozet: {os.path.abspath(sheet_path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
