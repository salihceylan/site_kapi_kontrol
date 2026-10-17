#!/usr/bin/env python3
"""Güde Teknoloji uygulama ikonu / açılış görseli dağıtımı ve doğrulaması (yalnız Python standart kütüphanesi).

Önce PNG'ler üretilir:   flutter test tool/icons/render_icons_test.dart      (-> build/icon_render/)
Sonra bu betik:          python tool/icons/apply_icons.py                    (dağıt + ICO/XML yaz + doğrula)
Yalnız doğrulama:        python tool/icons/apply_icons.py --check

Yaptıkları:
  1. build/icon_render altındaki PNG'leri depodaki nihai yollarına kopyalar (iOS, macOS, Android, Web, açılış görselleri).
  2. windows/runner/resources/app_icon.ico dosyasını yazar (16, 24, 32, 48, 64, 128, 256 px; hepsi PNG gömülü).
  3. tool/logo/gude_logo.svg yapraklarından vektör çizimleri üretir: Android monokrom (tema) ikonu ve bildirim küçük ikonu.
  4. web/index.html içindeki yükleme görselini (satır içi SVG) yaprak yollarından yazar.
  5. brand_spec.json renklerinden Android adaptive arka planı (drawable) ve açılış rengini (values) yazar.
  6. Her şeyi doğrular: PNG boyut/alfa, XML geçerliliği ve başvurular, ICO başlığı, manifest/index.html/storyboard renkleri.
Elle yazılmış (kaynak) dosyalar: mipmap-anydpi-v26/*.xml, drawable*/launch_background.xml, values-v31/*, manifest.json, index.html, LaunchScreen.storyboard.
"""
import argparse
import importlib.util
import json
import math
import os
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SVG_NS = '{http://www.w3.org/2000/svg}'
RES = 'android/app/src/main/res'
IOS_ICONS = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
IOS_LAUNCH = 'ios/Runner/Assets.xcassets/LaunchImage.imageset'
MAC_ICONS = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
ICO_PATH = 'windows/runner/resources/app_icon.ico'
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
LF = chr(10)
CRLF = chr(13) + chr(10)

errors = []


def fail(msg):
    errors.append(msg)
    print('HATA:', msg)


def p(*parts):
    return os.path.join(ROOT, *parts)


def read_text(rel):
    with open(p(rel), encoding='utf-8') as f:
        return f.read()


def write_text(rel, text):
    path = p(rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('yazildi:', rel)


def load_spec():
    with open(os.path.join(os.path.dirname(__file__), 'brand_spec.json'), encoding='utf-8') as f:
        return json.load(f)


def png_info(path):
    """(genislik, yukseklik, bit derinligi, renk tipi, tRNS var mi). Renk tipi 2=RGB, 6=RGBA."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('PNG imzasi yok')
    w, h, bd, ct = struct.unpack('>IIBB', data[16:26])
    return w, h, bd, ct, b'tRNS' in data[:2048]


# ---------------------------------------------------------------------------------------------
# 1) PNG dağıtımı
# ---------------------------------------------------------------------------------------------
def apply_pngs(render_dir):
    report_path = os.path.join(render_dir, '_render_report.json')
    if not os.path.exists(report_path):
        raise SystemExit(f'{report_path} yok. Once: flutter test tool/icons/render_icons_test.dart')
    with open(report_path, encoding='utf-8') as f:
        report = json.load(f)
    copied = 0
    for item in report:
        rel = item['path']
        if rel.startswith('_ico/'):
            continue
        src = os.path.join(render_dir, rel)
        dst = p(rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(src, 'rb') as a, open(dst, 'wb') as b:
            b.write(a.read())
        copied += 1
    print(f'{copied} PNG kopyalandi')
    return report


# ---------------------------------------------------------------------------------------------
# 2) ICO
# ---------------------------------------------------------------------------------------------
def write_ico(render_dir):
    images = []
    for size in ICO_SIZES:
        src = os.path.join(render_dir, '_ico', f'windows_{size}.png')
        with open(src, 'rb') as f:
            data = f.read()
        w, h, bd, ct, _ = png_info(src)
        if (w, h) != (size, size) or bd != 8 or ct != 6:
            raise SystemExit(f'{src}: beklenen {size}x{size} RGBA, bulunan {w}x{h} tip={ct}')
        images.append((size, data))
    header = struct.pack('<HHH', 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries, blobs = b'', b''
    for size, data in images:
        entries += struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(data), offset + len(blobs))
        blobs += data
    path = p(ICO_PATH)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(header + entries + blobs)
    print(f'yazildi: {ICO_PATH} ({len(images)} katman, {len(header + entries + blobs)} bayt)')


# ---------------------------------------------------------------------------------------------
# 3) Yaprak siluetinden Android vektörleri
# ---------------------------------------------------------------------------------------------
def _svg_to_dart():
    spec = importlib.util.spec_from_file_location('svg_to_dart', p('tool', 'logo', 'svg_to_dart.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def silhouette_paths(kind='rim0'):
    """Her yaprağın dış kenarı (rim0) ya da yüzü (face) yolu: [[('M',[x,y]), ('C',[6 sayı]), ..., ('Z',[])], ...]."""
    s2d = _svg_to_dart()
    tree = ET.parse(p('tool', 'logo', 'gude_logo.svg'))
    out = []
    for el in tree.getroot().iter(SVG_NS + 'path'):
        fill = el.get('fill', '')
        if re.fullmatch(r'url\(#leaf\d+_' + kind + r'\)', fill):
            d = s2d.normalize_path(el.get('d'))
            cmds = []
            toks = d.split(' ')
            i = 0
            arity = {'M': 2, 'L': 2, 'C': 6, 'Z': 0}
            while i < len(toks):
                c = toks[i]
                i += 1
                n = arity[c]
                cmds.append((c, [float(v) for v in toks[i:i + n]]))
                i += n
            out.append(cmds)
    if len(out) != 4:
        raise SystemExit(f'4 yaprak silueti bekleniyordu, {len(out)} bulundu')
    return out


def _cubic(p0, p1, p2, p3, t):
    u = 1 - t
    return (
        u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
        u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1],
    )


def sample_points(paths, per_curve=24):
    pts = []
    for cmds in paths:
        cur = None
        for c, v in cmds:
            if c == 'M':
                cur = (v[0], v[1])
                pts.append(cur)
            elif c == 'L':
                cur = (v[0], v[1])
                pts.append(cur)
            elif c == 'C':
                p0, p1, p2, p3 = cur, (v[0], v[1]), (v[2], v[3]), (v[4], v[5])
                pts.extend(_cubic(p0, p1, p2, p3, k / per_curve) for k in range(1, per_curve + 1))
                cur = p3
    return pts


def enclosing_circle(pts, iters=3000):
    """Badoiu-Clarkson yaklasimi: (merkez, yaricap)."""
    cx, cy = pts[0]
    for i in range(1, iters + 1):
        fx, fy = max(pts, key=lambda q: (q[0] - cx) ** 2 + (q[1] - cy) ** 2)
        cx += (fx - cx) / (i + 1)
        cy += (fy - cy) / (i + 1)
    r = max(math.hypot(q[0] - cx, q[1] - cy) for q in pts)
    return (cx, cy), r


def parse_path_data(data):
    """"M x y C ... Z" (bosluk ayrimli, mutlak M L C Z) -> [(komut, [sayilar])]."""
    toks = data.split()
    arity = {'M': 2, 'L': 2, 'C': 6, 'Z': 0}
    out, i = [], 0
    while i < len(toks):
        c = toks[i]
        i += 1
        n = arity[c]
        out.append((c, [float(v) for v in toks[i:i + n]]))
        i += n
    return out


def split_subpaths(cmds):
    """Komut listesini M ile baslayan alt yollara boler (sample_points her listeyi bir yol sayar)."""
    paths, cur = [], []
    for c, v in cmds:
        if c == 'M' and cur:
            paths.append(cur)
            cur = []
        cur.append((c, v))
    if cur:
        paths.append(cur)
    return paths



def fmt(v):
    s = f'{v:.2f}'.rstrip('0').rstrip('.')
    return '0' if s in ('', '-0') else s


def path_data(paths, tf):
    parts = []
    for cmds in paths:
        for c, v in cmds:
            if c == 'Z':
                parts.append('Z')
            else:
                nums = []
                for k in range(0, len(v), 2):
                    x, y = tf(v[k], v[k + 1])
                    nums += [fmt(x), fmt(y)]
                parts.append(c + ' ' + ' '.join(nums))
    return ' '.join(parts)


def vector_xml(size_dp, color, data, note):
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f'<!-- {note} -->\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        f'    android:width="{size_dp}dp"\n'
        f'    android:height="{size_dp}dp"\n'
        f'    android:viewportWidth="{size_dp}"\n'
        f'    android:viewportHeight="{size_dp}">\n'
        '    <path\n'
        f'        android:fillColor="{color}"\n'
        f'        android:pathData="{data}" />\n'
        '</vector>\n'
    )


def write_vectors():
    paths = silhouette_paths()
    pts = sample_points(paths)
    (cx, cy), r = enclosing_circle(pts)
    # Adaptive monokrom: 108dp tuval, işaret çapı 0.58 x 108 (66dp güvenli daire içinde; PNG ön planla aynı oran).
    k = (0.58 * 108) / (2 * r)
    data = path_data(paths, lambda x, y: ((x - cx) * k + 54, (y - cy) * k + 54))
    write_text(
        f'{RES}/drawable/ic_launcher_monochrome.xml',
        vector_xml(
            108,
            '#FF000000',
            data,
            'Android 13 temali (monokrom) simge: dort yaprak silueti. Uretici: tool/icons/apply_icons.py (kaynak tool/logo/gude_logo.svg).',
        ),
    )
    # Bildirim küçük ikonu: 24dp, beyaz silüet (Android yalnız alfa kanalını kullanır); yapraklar 20dp genişliğe sığar.
    xs = [q[0] for q in pts]
    ys = [q[1] for q in pts]
    bx, by = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    k2 = 20.0 / (max(xs) - min(xs))
    data2 = path_data(paths, lambda x, y: ((x - bx) * k2 + 12, (y - by) * k2 + 12))
    write_text(
        f'{RES}/drawable/ic_stat_notification.xml',
        vector_xml(
            24,
            '#FFFFFFFF',
            data2,
            'Telefon bildirimi durum cubugu simgesi: tek renk (beyaz) Guede yaprak silueti, seffaf zemin. Android yalniz alfa kanalini kullanir. '
            'Uretici: tool/icons/apply_icons.py (kaynak tool/logo/gude_logo.svg).',
        ),
    )


def write_web_loader():
    """web/index.html içindeki brand-loader işaretçileri arasına satır içi SVG yaprak yükleme görselini yazar."""
    rim, face = silhouette_paths('rim0'), silhouette_paths('face')
    pts = sample_points(rim)
    x0, x1 = min(q[0] for q in pts), max(q[0] for q in pts)
    y0, y1 = min(q[1] for q in pts), max(q[1] for q in pts)
    w, h = x1 - x0, y1 - y0

    def d(paths):
        return path_data(paths, lambda x, y: (x, y))

    def stops(*cols):
        n = len(cols) - 1
        return ''.join(f'<stop offset="{fmt(i / n)}" stop-color="{c}"/>' for i, c in enumerate(cols))

    grad = f'gradientUnits="userSpaceOnUse" x1="{fmt(x0)}" y1="{fmt(y0)}" x2="{fmt(x1)}" y2="{fmt(y1)}"'
    svg = (
        f'<svg viewBox="{fmt(x0)} {fmt(y0)} {fmt(w)} {fmt(h)}" aria-hidden="true" focusable="false">'
        f'<defs><linearGradient id="bb-rim" {grad}>{stops("#FFE9A8", "#F2B232", "#B8690C")}</linearGradient>'
        f'<linearGradient id="bb-face" {grad}>{stops("#FFF3C9", "#FFC83F", "#E08A1A")}</linearGradient></defs>'
        f'<path fill="url(#bb-rim)" d="{d(rim)}"/><path fill="url(#bb-face)" d="{d(face)}"/></svg>'
    )
    path = p('web', 'index.html')
    with open(path, 'rb') as f:
        raw = f.read().decode('utf-8')
    crlf = CRLF in raw
    text = raw.replace(CRLF, LF)
    a, b = '<!-- brand-loader:start -->', '<!-- brand-loader:end -->'
    i, j = text.index(a) + len(a), text.index(b)
    text = text[:i] + LF + '    ' + svg + LF + '    ' + text[j:]
    if crlf:
        text = text.replace(LF, CRLF)
    with open(path, 'wb') as f:
        f.write(text.encode('utf-8'))
    print(f'yazildi: web/index.html yukleme SVG ({len(svg)} bayt)')


# ---------------------------------------------------------------------------------------------
# 4) Renk kaynakları
# ---------------------------------------------------------------------------------------------
def write_colors(spec):
    flat = spec['flatDark'].upper()
    write_text(
        f'{RES}/values/brand_colors.xml',
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Marka acilis rengi. Uretici: tool/icons/apply_icons.py (kaynak tool/icons/brand_spec.json). -->\n'
        '<resources>\n'
        f'    <color name="launch_background">#FF{flat[1:]}</color>\n'
        '</resources>\n',
    )
    write_text(
        f'{RES}/drawable/ic_launcher_background.xml',
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Adaptive simge arka plani: derin lacivert-siyah radyal gradyan. Yaprak ve altin isima on planda (mipmap/ic_launcher_foreground).\n'
        '     Uretici: tool/icons/apply_icons.py (kaynak tool/icons/brand_spec.json). -->\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
        '    <gradient\n'
        '        android:type="radial"\n'
        '        android:centerX="0.5"\n'
        '        android:centerY="0.46"\n'
        '        android:gradientRadius="54%"\n'
        f'        android:startColor="{spec["bgCenter"].upper()}"\n'
        f'        android:centerColor="{spec["bgMid"].upper()}"\n'
        f'        android:endColor="{spec["bgEdge"].upper()}" />\n'
        '</shape>\n',
    )


# ---------------------------------------------------------------------------------------------
# 5) Doğrulama
# ---------------------------------------------------------------------------------------------
def tracked(prefix, suffix='.png'):
    out = subprocess.run(['git', 'ls-files', prefix], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split('\n')
    return [x for x in out if x.endswith(suffix)]


def check_png(rel, size=None, alpha=None, label=''):
    path = p(rel)
    if not os.path.exists(path):
        fail(f'{rel}: dosya yok')
        return
    try:
        w, h, bd, ct, trns = png_info(path)
    except Exception as e:  # noqa: BLE001
        fail(f'{rel}: PNG okunamadi ({e})')
        return
    if size is not None and (w, h) != (size, size):
        fail(f'{rel}: boyut {w}x{h}, beklenen {size}x{size}')
    if bd != 8:
        fail(f'{rel}: bit derinligi {bd}')
    has_alpha = ct in (4, 6) or trns
    if alpha is not None and has_alpha != alpha:
        fail(f'{rel}: alfa kanali {"var" if has_alpha else "yok"}, beklenen {"var" if alpha else "yok"} {label}')


def parse_xml(rel):
    try:
        return ET.parse(p(rel)).getroot()
    except Exception as e:  # noqa: BLE001
        fail(f'{rel}: XML gecersiz ({e})')
        return None


def check_all(spec):
    flat = spec['flatDark'].upper()
    # --- iOS / macOS: sabit liste = mevcut izlenen dosyalar; ad = piksel boyutu ---
    ios_files = [f for f in tracked(IOS_ICONS)]
    if len(ios_files) < 30:
        fail(f'iOS AppIcon PNG sayisi beklenenden az: {len(ios_files)}')
    for rel in ios_files:
        n = int(os.path.basename(rel).split('.')[0])
        check_png(rel, n, alpha=False, label='(iOS ikonunda alfa olmamali)')
    contents = json.loads(read_text(f'{IOS_ICONS}/Contents.json'))
    for im in contents['images']:
        fn = im.get('filename')
        if fn and not os.path.exists(p(IOS_ICONS, fn)):
            fail(f'Contents.json dosyayi gosteriyor ama yok: {fn}')
    for rel in tracked(MAC_ICONS):
        n = int(re.search(r'app_icon_(\d+)\.png', rel).group(1))
        check_png(rel, n, alpha=True)
    for i, (name, px) in enumerate([('LaunchImage.png', 256), ('LaunchImage@2x.png', 512), ('LaunchImage@3x.png', 768)]):
        check_png(f'{IOS_LAUNCH}/{name}', px, alpha=True)
    # --- Android PNG ---
    for dpi, scale in (('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)):
        check_png(f'{RES}/mipmap-{dpi}/ic_launcher.png', round(48 * scale), alpha=True)
        check_png(f'{RES}/mipmap-{dpi}/ic_launcher_round.png', round(48 * scale), alpha=True)
        check_png(f'{RES}/mipmap-{dpi}/ic_launcher_foreground.png', round(108 * scale), alpha=True)
        check_png(f'{RES}/drawable-{dpi}/launch_logo.png', round(256 * scale), alpha=True)
    check_png(f'{RES}/drawable-nodpi/ic_splash_mark.png', 864, alpha=True)
    # --- Web ---
    check_png('web/favicon.png', 64, alpha=True)
    for n in (192, 512):
        check_png(f'web/icons/Icon-{n}.png', n, alpha=False)
        check_png(f'web/icons/Icon-maskable-{n}.png', n, alpha=False)
    # --- Windows ICO ---
    check_ico()
    # --- Android XML ---
    xml_files = []
    for base, _dirs, files in os.walk(p(RES)):
        for fn in files:
            if fn.endswith('.xml'):
                xml_files.append(os.path.relpath(os.path.join(base, fn), ROOT).replace('\\', '/'))
    for rel in xml_files:
        parse_xml(rel)
    parse_xml('android/app/src/main/AndroidManifest.xml')
    parse_xml('ios/Runner/Base.lproj/LaunchScreen.storyboard')
    # Adaptive başvuruları
    for name in ('ic_launcher', 'ic_launcher_round'):
        rel = f'{RES}/mipmap-anydpi-v26/{name}.xml'
        root = parse_xml(rel)
        if root is None:
            continue
        refs = {}
        for child in root:
            tag = child.tag
            refs[tag] = child.get('{http://schemas.android.com/apk/res/android}drawable')
        for tag in ('background', 'foreground', 'monochrome'):
            ref = refs.get(tag)
            if not ref:
                fail(f'{rel}: <{tag}> yok')
                continue
            kind, resname = ref[1:].split('/')
            if kind == 'mipmap':
                ok = all(os.path.exists(p(RES, f'mipmap-{d}', resname + '.png')) for d in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'))
            else:
                ok = os.path.exists(p(RES, kind, resname + '.xml')) or os.path.exists(p(RES, kind, resname + '.png'))
            if not ok:
                fail(f'{rel}: {ref} bulunamadi')
    # Vektörler: örneklenen çizim noktaları güvenli bölgede mi (monokrom: 66dp daire; bildirim: 24dp tuvalde 1dp boşluk)
    for rel, kind in ((f'{RES}/drawable/ic_launcher_monochrome.xml', 'mono'), (f'{RES}/drawable/ic_stat_notification.xml', 'stat')):
        root = parse_xml(rel)
        if root is None:
            continue
        cmds_list = []
        for el in root.iter('path'):
            cmds_list.append(parse_path_data(el.get('{http://schemas.android.com/apk/res/android}pathData')))
        pts = sample_points([c for cl in cmds_list for c in split_subpaths(cl)])
        if kind == 'mono':
            far = max(math.hypot(x - 54, y - 54) for x, y in pts)
            if far > 33.0 + 1e-6:
                fail(f'{rel}: yapraklar 66dp guvenli daireyi asiyor (en uzak nokta {far:.2f}dp > 33dp)')
        else:
            lo = min(min(x, y) for x, y in pts)
            hi = max(max(x, y) for x, y in pts)
            if lo < 1.0 or hi > 23.0:
                fail(f'{rel}: bildirim simgesi 24dp tuvalde kenara cok yakin ([{lo:.2f}, {hi:.2f}])')
    # Eski ikon (zil) kalmadı
    if 'M12,22c1.1' in read_text(f'{RES}/drawable/ic_stat_notification.xml'):
        fail('ic_stat_notification.xml hala zil cizimi')
    # --- Manifest / styles ---
    man = read_text('android/app/src/main/AndroidManifest.xml')
    for needle in ('android:icon="@mipmap/ic_launcher"', 'android:roundIcon="@mipmap/ic_launcher_round"', '@drawable/ic_stat_notification'):
        if needle not in man:
            fail(f'AndroidManifest.xml: {needle} yok')
    colors = read_text(f'{RES}/values/brand_colors.xml')
    if flat[1:] not in colors:
        fail('brand_colors.xml spec rengini icermiyor')
    for rel in (f'{RES}/drawable/launch_background.xml', f'{RES}/drawable-v21/launch_background.xml'):
        t = read_text(rel)
        if '@color/launch_background' not in t or '@drawable/launch_logo' not in t:
            fail(f'{rel}: koyu zemin/launch_logo bagi yok')
    for rel in (f'{RES}/values-v31/styles.xml', f'{RES}/values-night-v31/styles.xml'):
        if not os.path.exists(p(rel)):
            fail(f'{rel}: yok (Android 12 splash)')
            continue
        t = read_text(rel)
        if 'windowSplashScreenBackground' not in t or 'windowSplashScreenAnimatedIcon' not in t:
            fail(f'{rel}: splash ogeleri eksik')
    # --- Web manifest / index.html ---
    try:
        mf = json.loads(read_text('web/manifest.json'))
    except Exception as e:  # noqa: BLE001
        fail(f'web/manifest.json gecersiz: {e}')
        mf = None
    if mf:
        if mf.get('theme_color', '').upper() != flat or mf.get('background_color', '').upper() != flat:
            fail('manifest.json theme_color/background_color spec ile ayni degil')
        for ic in mf.get('icons', []):
            if not os.path.exists(p('web', ic['src'])):
                fail(f'manifest.json: {ic["src"]} yok')
        if not mf.get('short_name'):
            fail('manifest.json short_name yok')
    html = read_text('web/index.html')
    if f'<meta name="theme-color" content="{flat}"' not in html and f'<meta name="theme-color" content="{flat.lower()}"' not in html:
        fail('index.html theme-color meta yok')
    if 'flutter-first-frame' not in html or 'flutter_bootstrap.js' not in html:
        fail('index.html yukleme gorseli/bootstrap bagi eksik')
    # --- Storyboard rengi ---
    sb = read_text('ios/Runner/Base.lproj/LaunchScreen.storyboard')
    m = re.search(r'<color key="backgroundColor" red="([\d.]+)" green="([\d.]+)" blue="([\d.]+)"', sb)
    if not m:
        fail('LaunchScreen.storyboard arka plan rengi bulunamadi')
    else:
        want = [int(flat[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        got = [float(x) for x in m.groups()]
        if any(abs(a - b) > 0.004 for a, b in zip(want, got)):
            fail(f'LaunchScreen.storyboard rengi {got} spec {want} ile uyusmuyor')
    if 'width="256" height="256"' not in sb:
        fail('LaunchScreen.storyboard LaunchImage boyutu 256x256 degil')
    # --- Eski AHBU görseli kalmadı mı ---
    old = p('assets', 'images', 'app_logo.png')
    if os.path.exists(old):
        with open(old, 'rb') as f:
            old_bytes = f.read()
        for rel in (f'{IOS_ICONS}/1024.png', f'{MAC_ICONS}/app_icon_1024.png'):
            with open(p(rel), 'rb') as f:
                if f.read() == old_bytes:
                    fail(f'{rel} hala eski AHBU gorseli')


def check_ico():
    path = p(ICO_PATH)
    if not os.path.exists(path):
        fail(f'{ICO_PATH} yok')
        return
    with open(path, 'rb') as f:
        data = f.read()
    res, typ, count = struct.unpack('<HHH', data[:6])
    if (res, typ) != (0, 1):
        fail(f'ICO basligi gecersiz: {res},{typ}')
        return
    if count != len(ICO_SIZES):
        fail(f'ICO katman sayisi {count}, beklenen {len(ICO_SIZES)}')
    seen = []
    for i in range(count):
        w, h, cc, rs, planes, bpp, size, off = struct.unpack('<BBBBHHII', data[6 + 16 * i:22 + 16 * i])
        real_w = w or 256
        real_h = h or 256
        seen.append(real_w)
        if off + size > len(data):
            fail(f'ICO katman {i}: veri dosya disina tasiyor')
            continue
        blob = data[off:off + size]
        if blob[:8] != b'\x89PNG\r\n\x1a\n':
            fail(f'ICO katman {i}: PNG imzasi yok')
            continue
        iw, ih = struct.unpack('>II', blob[16:24])
        if (iw, ih) != (real_w, real_h):
            fail(f'ICO katman {i}: girdi {real_w}x{real_h} ama PNG {iw}x{ih}')
        if bpp != 32 or planes != 1:
            fail(f'ICO katman {i}: planes/bpp {planes}/{bpp}')
    if sorted(seen) != ICO_SIZES:
        fail(f'ICO boyutlari {sorted(seen)}, beklenen {ICO_SIZES}')


def check_coverage(report):
    """Izlenen ikon PNG'lerinin hepsi uretilen listede mi (eksik/fazla dosya yok)?"""
    produced = {item['path'] for item in report}
    wanted = set()
    for prefix in (IOS_ICONS, IOS_LAUNCH, MAC_ICONS, f'{RES}/mipmap-*', 'web/icons', 'web/favicon.png'):
        wanted.update(tracked(prefix))
    wanted = {w for w in wanted if os.path.basename(w) not in ('README.md',)}
    missing = sorted(w for w in wanted if w.endswith('.png') and w not in produced)
    if missing:
        fail('uretilmeyen izlenen PNG: ' + ', '.join(missing))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--render-dir', default=os.path.join(ROOT, 'build', 'icon_render'))
    ap.add_argument('--check', action='store_true', help='yalniz dogrula (dosya yazma)')
    args = ap.parse_args()
    spec = load_spec()
    report = None
    if not args.check:
        report = apply_pngs(args.render_dir)
        write_ico(args.render_dir)
        write_vectors()
        write_colors(spec)
        write_web_loader()
    else:
        rp = os.path.join(args.render_dir, '_render_report.json')
        if os.path.exists(rp):
            with open(rp, encoding='utf-8') as f:
                report = json.load(f)
    check_all(spec)
    if report:
        check_coverage(report)
    if errors:
        print(f'\n{len(errors)} hata')
        sys.exit(1)
    print('\nTUM KONTROLLER GECTI')


if __name__ == '__main__':
    main()
