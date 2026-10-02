# -*- coding: utf-8 -*-
"""Firmware ana makine (host) testleri.

GERCEK firmware basliklari (cihaz_kontrol/include/*.h) sahte donanim katmani (stub/) ile Windows'ta MSVC ile derlenip
calistirilir; her test "SONUC: N dogrulama gecti, M basarisiz" satiri yazar. Ayrinti: README.md

Calistirma:
  python run_all.py                 hepsi (t_core, t_udp, t_pin, t_gm60, t_mqtt WROOM + C3)
  python run_all.py --new-vectors   t_core icin HMAC vektorlerini yeniden uret (varsayilan: yoksa uretilir)
  python run_all.py --fuzz          ek olarak AddressSanitizer'li rastgele olay/fuzz testi (uzun surer)
Ortam degiskeni VCVARS: vcvars64.bat yolu (varsayilan Visual Studio 18 Community).
Cikis kodu: tum dogrulamalar gectiyse 0, aksi halde 1.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
INCLUDE = os.path.normpath(os.path.join(HERE, '..', 'include'))
ARDUINOJSON = os.path.normpath(os.path.join(HERE, '..', '.pio', 'libdeps', 'lolin_c3_mini', 'ArduinoJson', 'src'))
VCVARS = os.environ.get(
    'VCVARS', r'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat')
CL_BASE = '/nologo /EHsc /std:c++17 /Zc:__cplusplus /utf-8 /W3 /D_CRT_SECURE_NO_WARNINGS'
WROOM = '/DBOARD_ESP32_WROOM_RELAY'
C3 = '/DBOARD_ESP32_C3'

# (gorunen ad, kaynak, exe, ek cl bayraklari, ArduinoJson gerekli mi, include/ gerekli mi)
TESTS = [
    ('t_core    (yerel_kontrol_cekirdek.h: KAT, Node capraz, durum makinesi, sarma)', 't_core.cpp', 't_core.exe', '', False, False),
    ('t_udp     (yerel_kapi_kontrol.h: UDP/HTTP uctan uca)', 't_udp.cpp', 't_udp.exe', WROOM, True, True),
    ('t_pin     (admin_pin.h: zayif PIN, kilit zamani)', 't_pin.cpp', 't_pin.exe', WROOM, False, True),
    ('t_gm60    (gm60_scanner.h: QR korumalari)', 't_gm60.cpp', 't_gm60.exe', WROOM, False, True),
    ('t_mqtt WROOM (mqtt_baglanti.h + ota_guncelleme.h + ota_is_kimligi.h)', 't_mqtt.cpp', 't_mqtt_wroom.exe', WROOM, True, True),
    ('t_mqtt C3    (mqtt_baglanti.h + ota_guncelleme.h + ota_is_kimligi.h)', 't_mqtt.cpp', 't_mqtt_c3.exe', C3, True, True),
]
FUZZ = ('t_fuzz    (rastgele olay dizileri, AddressSanitizer)', 't_fuzz.cpp', 't_fuzz.exe', WROOM + ' /Zi /fsanitize=address', True, True)


def run_one(ad, src, exe, extra, needs_json, needs_include, run_args=''):
    obj = os.path.splitext(exe)[0] + '.obj'
    includes = '/I stub'
    if needs_json:
        includes += ' /I "%s"' % ARDUINOJSON
    if needs_include:
        includes += ' /I "%s"' % INCLUDE
    bat = os.path.join(HERE, '_calistir_%s.bat' % os.path.splitext(exe)[0])
    lines = [
        '@echo off',
        'call "%s" >nul 2>&1' % VCVARS,
        'cd /d "%s"' % HERE,
        'cl %s %s %s %s /Fe:%s /Fo:%s' % (CL_BASE, extra, includes, src, exe, obj),
        'if errorlevel 1 exit /b 1',
        '.\\%s %s' % (exe, run_args),
        'exit /b %errorlevel%',
    ]
    with open(bat, 'w', encoding='utf-8', newline='') as f:
        f.write('\r\n'.join(lines) + '\r\n')
    try:
        r = subprocess.run([bat], capture_output=True, text=True, encoding='utf-8', errors='replace', cwd=HERE)
    finally:
        try:
            os.remove(bat)
        except OSError:
            pass
    return r


def main():
    args = sys.argv[1:]
    if not os.path.isdir(os.path.join(ARDUINOJSON)):
        print('UYARI: ArduinoJson bulunamadi (%s). Once `pio run -e lolin_c3_mini` ile cihaz_kontrol derlenmeli.' % ARDUINOJSON)
    if '--new-vectors' in args or not os.path.exists(os.path.join(HERE, 'vectors.txt')):
        subprocess.run(['node', 'gen_vectors.mjs'], cwd=HERE, check=True)

    tests = list(TESTS)
    if '--fuzz' in args:
        tests.append(FUZZ)
    toplam_gecen = 0
    toplam_kalan = 0
    for entry in tests:
        ad = entry[0]
        r = run_one(*entry)
        out = r.stdout
        m = re.search(r'SONUC: (\d+) dogrulama gecti, (\d+) basarisiz', out)
        if m:
            g, k = int(m.group(1)), int(m.group(2))
            toplam_gecen += g
            toplam_kalan += k
            print('%-78s gecti=%4d basarisiz=%d' % (ad, g, k))
            for line in out.splitlines():
                if 'FAIL' in line:
                    print('    ', line[:200])
        elif entry is FUZZ and r.returncode == 0:
            print('%-78s tamam (cikis=0)' % ad)
            print(out[-600:])
        else:
            print('%-78s CALISMADI / DERLENMEDI (cikis=%d)' % (ad, r.returncode))
            print(out[-1500:])
            toplam_kalan += 1
    print('\nTOPLAM: gecti=%d basarisiz=%d' % (toplam_gecen, toplam_kalan))
    return 0 if toplam_kalan == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
