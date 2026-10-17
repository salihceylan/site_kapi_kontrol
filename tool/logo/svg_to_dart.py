#!/usr/bin/env python3
"""Logo SVG'sini Flutter'ın doğrudan çizebildiği Dart verisine çevirir.

Kullanım:  python tool/logo/svg_to_dart.py <logo.svg> [lib/brand/gude_logo_data.dart]

Girdi sözleşmesi (bkz. tool/logo/README.md): viewBox "0 0 W H"; yalnızca <g>/<path>/<linearGradient>/<radialGradient>/<stop>;
yol komutları yalnızca mutlak M L C Z; gradyanlar userSpaceOnUse; grup kimlikleri shadow, leaves(leaf1..), wordmark, tagline.
Çıktı: `lib/brand/gude_logo_data.dart` (üretilmiş dosya, elle düzenlenmez). Renk/gölge/gradyan GEÇERSİZ KILMALARI çalışma zamanında
AppColors'tan gelir (lib/brand/gude_logo.dart); buradaki değerler yalnızca SVG'deki özgün halidir.
"""
import re
import sys
import xml.etree.ElementTree as ET

SVG = '{http://www.w3.org/2000/svg}'


def local(tag):
    return tag.split('}', 1)[1] if '}' in tag else tag


def color_literal(value, opacity=1.0):
    value = value.strip()
    m = re.fullmatch(r'#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})', value)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = ''.join(ch * 2 for ch in h)
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    else:
        m = re.fullmatch(r'rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', value)
        if not m:
            raise SystemExit(f'desteklenmeyen renk: {value!r}')
        r, g, b = (int(m.group(i)) for i in (1, 2, 3))
    a = max(0, min(255, round(opacity * 255)))
    return f'Color(0x{a:02X}{r:02X}{g:02X}{b:02X})'


def num(v):
    s = f'{float(v):.2f}'.rstrip('0').rstrip('.')
    return s if s not in ('', '-0') else '0'


def check_path(d, ident):
    # Yalnızca mutlak M L C Z ve sayılar.
    bad = re.sub(r'[MLCZ\s,\-\.\deE+]', '', d)
    if bad:
        raise SystemExit(f'{ident}: izin verilmeyen yol komutu/karakter: {set(bad)}')


def normalize_path(d):
    d = re.sub(r'([MLCZ])', r' \1 ', d)
    d = re.sub(r'(?<![eE])-', ' -', d)
    d = re.sub(r'[,\s]+', ' ', d).strip()
    # Örtük tekrarları (ör. "C" sonrası birden çok koordinat kümesi) açık komutlara aç; sayıları kısalt.
    arity = {'M': 2, 'L': 2, 'C': 6, 'Z': 0}
    out = []
    cmd = None
    nums = []

    def flush():
        nonlocal nums
        if cmd is None:
            return
        n = arity[cmd]
        if n == 0:
            out.append('Z')
            return
        if len(nums) % n != 0 or not nums:
            raise SystemExit(f'{cmd} komutunda sayı sayısı {n} katı değil: {len(nums)}')
        for k in range(0, len(nums), n):
            c = cmd if k == 0 else ('L' if cmd == 'M' else cmd)
            out.append(c + ' ' + ' '.join(num(v) for v in nums[k:k + n]))
        nums = []

    for tok in d.split(' '):
        if re.fullmatch(r'[MLCZ]', tok):
            flush()
            cmd, nums = tok, []
        elif tok:
            nums.append(tok)
    flush()
    return ' '.join(out)


def parse_gradients(root):
    grads = {}
    for el in root.iter():
        t = local(el.tag)
        if t not in ('linearGradient', 'radialGradient'):
            continue
        gid = el.get('id')
        if el.get('gradientUnits', 'userSpaceOnUse') != 'userSpaceOnUse':
            raise SystemExit(f'{gid}: gradientUnits userSpaceOnUse olmalı')
        if el.get('gradientTransform'):
            raise SystemExit(f'{gid}: gradientTransform desteklenmiyor')
        stops = []
        for st in el:
            if local(st.tag) != 'stop':
                continue
            off = st.get('offset', '0')
            off = float(off[:-1]) / 100 if off.endswith('%') else float(off)
            style = dict(p.split(':', 1) for p in st.get('style', '').split(';') if ':' in p)
            col = st.get('stop-color') or style.get('stop-color') or '#000000'
            op = float(st.get('stop-opacity') or style.get('stop-opacity') or 1)
            stops.append((off, color_literal(col, op)))
        if t == 'linearGradient':
            grads[gid] = ('linear', [float(el.get(k, d)) for k, d in (('x1', 0), ('y1', 0), ('x2', 1), ('y2', 0))], stops)
        else:
            cx, cy, r = float(el.get('cx', 0)), float(el.get('cy', 0)), float(el.get('r', 0))
            fx, fy = float(el.get('fx', cx)), float(el.get('fy', cy))
            grads[gid] = ('radial', [cx, cy, r, fx, fy], stops)
    return grads


def fill_literal(el, grads):
    fill = el.get('fill', '#000000')
    fo = float(el.get('fill-opacity', 1)) * float(el.get('opacity', 1))
    m = re.fullmatch(r'url\(#([^)]+)\)', fill.strip())
    if m:
        kind, vals, stops = grads[m.group(1)]
        offs = '[' + ', '.join(num(o) for o, _ in stops) + ']'
        cols = '[' + ', '.join(c for _, c in stops) + ']'
        if kind == 'linear':
            x1, y1, x2, y2 = vals
            return f'LogoLinear({num(x1)}, {num(y1)}, {num(x2)}, {num(y2)}, {offs}, {cols})', fo
        cx, cy, r, fx, fy = vals
        return f'LogoRadial({num(cx)}, {num(cy)}, {num(r)}, {num(fx)}, {num(fy)}, {offs}, {cols})', fo
    if fill == 'none':
        return 'LogoSolid(Color(0x00000000))', 0.0
    return f'LogoSolid({color_literal(fill)})', fo


def shape_literal(el, grads):
    d = el.get('d')
    ident = el.get('id', '?')
    check_path(d, ident)
    fill, opacity = fill_literal(el, grads)
    d = normalize_path(d)
    op = '' if abs(opacity - 1.0) < 1e-6 else f', opacity: {num(opacity)}'
    return f"LogoShape('{ident}', '{d}', {fill}{op})"


def group_shapes(g, grads):
    return [shape_literal(p, grads) for p in g.iter() if local(p.tag) == 'path']


def main():
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else 'lib/brand/gude_logo_data.dart'
    tree = ET.parse(src)
    root = tree.getroot()
    vb = [float(x) for x in root.get('viewBox').replace(',', ' ').split()]
    if vb[0] != 0 or vb[1] != 0:
        raise SystemExit('viewBox 0 0 W H olmalı')
    grads = parse_gradients(root)
    top = {g.get('id'): g for g in root if local(g.tag) == 'g'}
    for need in ('shadow', 'leaves', 'wordmark', 'tagline'):
        if need not in top:
            raise SystemExit(f'zorunlu grup yok: {need}')

    def block(name, shapes):
        body = ',\n'.join('  ' + s for s in shapes)
        return f'const {name} = <LogoShape>[\n{body},\n];\n'

    out = [
        '// ÜRETİLMİŞ DOSYA — elle düzenlemeyin. Kaynak: tool/logo/svg_to_dart.py  (girdi: logo.svg)\n',
        '// Güde Teknoloji logosunun vektör verisi (yollar ve özgün gradyanlar). Tema renkleri lib/brand/gude_logo.dart içinde AppColors\'tan gelir.\n',
        "import 'dart:ui' show Color;\n",
        "import 'logo_model.dart';\n",
        f'/// Logonun çizim uzayı (en/boy = {num(vb[2])}/{num(vb[3])}).\n',
        f'const kLogoViewWidth = {num(vb[2])};\n',
        f'const kLogoViewHeight = {num(vb[3])};\n',
        '/// Yaprakların ve yazının altındaki yumuşak gölge şekilleri (koyu temada çizilmez).\n',
        block('kLogoShadow', group_shapes(top['shadow'], grads)),
        '/// Dört yaprak (alttan üste): taban dolgusu ve kenar/parlama katmanları.\n',
        block('kLogoLeaves', group_shapes(top['leaves'], grads)),
        '/// "Güde Teknoloji" yazısı: önce koyu kenar, sonra harf yüzleri (yüzlerin gradyanı temadan gelir).\n',
        block('kLogoWordmark', group_shapes(top['wordmark'], grads)),
        '/// "gelecek sizin elinizde" yazısı: önce kenar, sonra dolgu.\n',
        block('kLogoTagline', group_shapes(top['tagline'], grads)),
    ]
    with open(dst, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out))
    n = sum(len(group_shapes(top[k], grads)) for k in ('shadow', 'leaves', 'wordmark', 'tagline'))
    print(f'{dst}: {n} şekil, {sum(len(s) for s in out) / 1024:.0f} KB')


if __name__ == '__main__':
    main()
