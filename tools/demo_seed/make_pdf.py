#!/usr/bin/env python3
"""Demo hesap listesi PDF'i (A4, Turkce karakterler dogru).

Kullanim:
    python make_pdf.py --creds out/creds.json --out out/demo_hesaplar.pdf

Girdi: seed.mjs ya da restructure_families.mjs --creds-out dosyasi (JSON). Cikti: yonetim kadrosu ve gorevliler tablosu, ardindan daire daire
sakinler. Yeniden yapilandirilmis dosyada (accounts[].familyRole var) her dairede Malik, Daire admini (isaretli: sari satir, kalin) ve aile uyeleri
(es / cocuk / yasli ebeveyn; "Yas" sutunu ve rol etiketinde yas, hesapsiz olanlar belirtilir; hane basliginda resit olmayan cocuk / yasli sayisi) rolleriyle birlikte gelir
(--ensure-composition ciktisi da ayni bicimdedir); eski bicimde (yalniz tohum ciktisi) daire amiri isaretlenir. Yazi tipi: Windows C:\\Windows\\Fonts\\arial.ttf ya da DejaVu Sans; yoksa reportlab'in
yerlesik fontlari (Turkce harfler eksik cikabilir; uyari verir).
Gereken: pip install reportlab
"""
import argparse
import json
import os
import sys
from collections import OrderedDict

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

FONT_CANDIDATES = [
    ("C:\\Windows\\Fonts\\arial.ttf", "C:\\Windows\\Fonts\\arialbd.ttf"),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
    ("/usr/share/fonts/dejavu/DejaVuSans.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"),
    ("/Library/Fonts/Arial.ttf", "/Library/Fonts/Arial Bold.ttf"),
]


def register_fonts():
    for regular, bold in FONT_CANDIDATES:
        if os.path.exists(regular) and os.path.exists(bold):
            pdfmetrics.registerFont(TTFont("DemoSans", regular))
            pdfmetrics.registerFont(TTFont("DemoSans-Bold", bold))
            return "DemoSans", "DemoSans-Bold"
    print("UYARI: Turkce destekli TTF yazi tipi bulunamadi; Helvetica kullanilacak (ğ ş ı harfleri eksik cikabilir).", file=sys.stderr)
    return "Helvetica", "Helvetica-Bold"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--creds", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    with open(args.creds, "r", encoding="utf-8") as fh:
        data = json.load(fh)

    font, bold = register_fonts()
    title = ParagraphStyle("title", fontName=bold, fontSize=17, leading=21, spaceAfter=4)
    warn = ParagraphStyle("warn", fontName=bold, fontSize=10, leading=13, textColor=colors.HexColor("#9c1c1c"), spaceAfter=8)
    h2 = ParagraphStyle("h2", fontName=bold, fontSize=12.5, leading=16, spaceBefore=10, spaceAfter=4)
    small = ParagraphStyle("small", fontName=font, fontSize=8.5, leading=11, textColor=colors.HexColor("#444444"))
    cell = ParagraphStyle("cell", fontName=font, fontSize=8.6, leading=10.4)
    cell_b = ParagraphStyle("cellb", fontName=bold, fontSize=8.6, leading=10.4)
    mono = ParagraphStyle("mono", fontName=font, fontSize=8.8, leading=10.4)

    site_name = data.get("siteName", "Cenk Sitesi")
    heading = f"{site_name} - Demo Hesaplar (SAHTE VERİ)"

    story = []
    story.append(Paragraph(heading, title))
    story.append(Paragraph("Bu hesaplar demo amaçlıdır; deneme bitince silinecektir.", warn))
    story.append(Paragraph(f"Oluşturma: {(data.get('generatedOn') or data.get('generatedAt', ''))[:10]} &nbsp;|&nbsp; Parti: {data.get('batchId', '')} &nbsp;|&nbsp; Giriş: E-posta veya Kullanıcı Adı + şifre", small))
    story.append(Spacer(1, 6))

    accounts = data.get("accounts", [])
    manager = data.get("manager", {})

    # --- yonetim kadrosu ve gorevliler ---
    story.append(Paragraph("Yönetim kadrosu ve görevliler", h2))
    rows = [[Paragraph("Ad Soyad", cell_b), Paragraph("Görev / Rol", cell_b), Paragraph("Kullanıcı adı", cell_b), Paragraph("Şifre", cell_b), Paragraph("Daire", cell_b)]]
    rows.append([Paragraph(manager.get("fullName", "-"), cell), Paragraph("Site yöneticisi (mevcut hesap)", cell), Paragraph("mevcut hesap", cell), Paragraph("değişmedi", cell), Paragraph("-", cell)])
    for acc in accounts:
        if acc.get("group") == "gorevli":
            rows.append([Paragraph(acc["fullName"], cell), Paragraph(acc["roleLabel"], cell), Paragraph(acc["username"], mono), Paragraph(acc["password"], mono), Paragraph("-", cell)])
    for acc in accounts:
        if acc.get("boardRole"):
            rows.append([Paragraph(acc["fullName"], cell), Paragraph(acc["boardRole"], cell), Paragraph(acc["username"], mono), Paragraph(acc["password"], mono), Paragraph(acc["apartmentLabel"], cell)])
    table = Table(rows, colWidths=[36 * mm, 38 * mm, 32 * mm, 36 * mm, 32 * mm], repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e6ecf5")),
                ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#9aa7b8")),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ]
        )
    )
    story.append(table)

    # --- daire daire ---
    story.append(PageBreak())
    story.append(Paragraph("Daireler ve sakinler", title))
    restructured = any(acc.get("familyRole") for acc in accounts if acc.get("group") == "daire")
    if restructured:
        story.append(Paragraph(
            "Her dairede TEK <b>daire admini</b> vardır (sarı satır, kalın): dairede oturan kişi - kiracı oturuyorsa kiracı, aksi halde malik. "
            "Kiracılı dairede malik dışarıda oturur (kapı yetkisi yoktur) ve yönetim kiracıdadır. Aile üyeleri: eş, çocuk, yaşlı ebeveyn; "
            "18 yaşından küçükler reşit değildir, hesapsız olanların giriş bilgisi yoktur.", small))
    else:
        story.append(Paragraph("Kalın yazılan ve rolünde &quot;daire amiri&quot; yazan kişi daire amiridir (APARTMENT_ADMIN). Rol: Malik / Kiracı / Aile üyesi.", small))
    meta_by_label = {h.get("apartmentLabel"): h for h in data.get("households", [])}
    groups = OrderedDict()
    for acc in accounts:
        if acc.get("group") != "daire":
            continue
        groups.setdefault(acc["apartmentLabel"], []).append(acc)
    for label, members in groups.items():
        meta = meta_by_label.get(label)
        if meta:
            who = "Kiracı oturuyor, yönetim kiracıda" if meta.get("occupancy") == "tenant" else "Malik oturuyor, yönetim malikte"
            comp = ""
            if restructured:
                n_child = sum(1 for m in members if m.get("familyRole") == "child" and m.get("isMinor"))
                n_elder = sum(1 for m in members if m.get("familyRole") == "elder")
                comp = f"; {n_child} reşit olmayan çocuk, {n_elder} yaşlı"
            story.append(Paragraph(f"{label} &nbsp;<font size=9 color='#555555'>({who}; {meta.get('residentCount', len(members))} kişi oturuyor{comp})</font>", h2))
        else:
            story.append(Paragraph(f"{label}", h2))
        header = [Paragraph("Ad Soyad", cell_b), Paragraph("Rol", cell_b)]
        if restructured:
            header.append(Paragraph("Yaş", cell_b))
        header += [Paragraph("Kullanıcı adı", cell_b), Paragraph("Şifre", cell_b)]
        rows = [header]
        admin_rows = []
        for idx, m in enumerate(members, start=1):
            name = m["fullName"]
            if restructured:
                role = m.get("roleLabel", "")
                has_account = m.get("hasAccount", True) and m.get("username")
                user_txt = m["username"] if has_account else "-"
                pass_txt = (m.get("password") or "(bilinmiyor)") if has_account else "hesap yok"
                age_txt = str(m["age"]) if m.get("age") else "-"
            else:
                role = m["roleLabel"] + (" - daire amiri" if m.get("isAmir") else "")
                user_txt = m["username"]
                pass_txt = m["password"]
            if m.get("isAmir"):
                admin_rows.append(idx)
            line = [Paragraph(name, cell_b if m.get("isAmir") else cell), Paragraph(role, cell_b if m.get("isAmir") else cell)]
            if restructured:
                line.append(Paragraph(age_txt, cell))
            line += [Paragraph(user_txt, mono), Paragraph(pass_txt, mono)]
            rows.append(line)
        col_widths = [42 * mm, 50 * mm, 11 * mm, 39 * mm, 32 * mm] if restructured else [46 * mm, 56 * mm, 40 * mm, 32 * mm]
        t = Table(rows, colWidths=col_widths, repeatRows=1)
        style = [
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#eef2f7")),
            ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#b4bdc9")),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("TOPPADDING", (0, 0), (-1, -1), 2.5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
        ]
        if restructured:
            for idx in admin_rows:
                style.append(("BACKGROUND", (0, idx), (-1, idx), colors.HexColor("#fff3c4")))
        t.setStyle(TableStyle(style))
        story.append(t)

    def footer(canvas, doc):
        canvas.saveState()
        canvas.setFont(font, 8)
        canvas.setFillColor(colors.HexColor("#666666"))
        canvas.drawString(18 * mm, 10 * mm, "SAHTE VERİ - bu belge gerçek kişi veya hesap içermez; deneme bitince hesaplar silinecektir.")
        canvas.drawRightString(A4[0] - 18 * mm, 10 * mm, f"Sayfa {doc.page}")
        canvas.restoreState()

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    doc = SimpleDocTemplate(
        args.out, pagesize=A4, leftMargin=18 * mm, rightMargin=18 * mm, topMargin=16 * mm, bottomMargin=18 * mm,
        title=heading, author="demo_seed",
    )
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    print(f"PDF yazildi: {args.out} ({len(groups)} daire, {sum(len(m) for m in groups.values())} sakin)")


if __name__ == "__main__":
    main()
