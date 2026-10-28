// Kapi komutu dili (P1-15): komut kabul edilince kullaniciya donuk metin "acildi" demez.
//
// Sunucu yalniz komutu MQTT'ye yayinlar; cihaz yaniti ya da fiziksel acilma kaniti yoktur
// (door_access_logs.opened_at komut aninin damgasidir, sensor degildir). Bu yuzden basari metni
// "komut gonderildi"dir. DB/MQTT'ye baglanmaz: kaynak metnini ve saf HTML uretecini inceler.
//
// Gercek olay adlari (gecis kaydi, "Kapi erisimi yeniden acildi" gibi yetki kaydi etiketleri) bu kuralin disindadir.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { renderGuestPassPage } from '../src/utils/guest_pass_utils.js';

const srcRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'src');
const read = (relative) => readFileSync(path.join(srcRoot, relative), 'utf8').replace(/\r\n/g, '\n');

// Kapi durumunu kanitsiz iddia eden ifadeler (ASCII sunucu metinleri).
const UNPROVEN_DOOR_SUCCESS = [/basariyla acildi/i, /kapi acildi/i, /\bACILDI\b/, /gecebilirsiniz/i];

function guestScript() {
  const html = renderGuestPassPage({
    pass: {
      id: 7,
      token: 'a'.repeat(48),
      title: 'Kurye',
      pass_type: 'single_use',
      is_active: true,
      max_uses: 1,
      used_count: 0,
      expires_at: new Date(Date.now() + 30 * 60 * 1000),
      site_name: 'Yildiz Sitesi',
      door_name: 'Ana Kapi',
    },
    nonce: 'n',
  });
  const match = html.match(/<script nonce="n">([\s\S]*)<\/script>/);
  assert.ok(match, 'script blogu bulunamadi');
  return match[1];
}

test('misafir gecis sayfasi: basari metni yalniz komutun gonderildigini soyler', () => {
  const script = guestScript();
  assert.ok(script.includes("'GONDERILDI'"), 'dugme etiketi GONDERILDI');
  assert.ok(script.includes('Kapi acma komutu gonderildi.'), 'basari mesaji');
  for (const pattern of UNPROVEN_DOOR_SUCCESS) {
    assert.equal(pattern.test(script), false, `misafir sayfasi betiginde kanitsiz basari ifadesi: ${pattern}`);
  }
  // Devam ederken (komut yolda) etiket hâlâ ACILIYOR...; sonuc etiketi GONDERILDI'dir.
  assert.ok(script.includes("'ACILIYOR...'"));
});

test('karekodla acma yaniti: mesaj komutun gonderildigini soyler (acildi demez)', () => {
  const source = read('routes/app_doors_routes.js');
  assert.ok(source.includes("message: 'Kapi acma komutu gonderildi.'"));
  for (const pattern of UNPROVEN_DOOR_SUCCESS) {
    assert.equal(pattern.test(source), false, `app_doors_routes.js icinde kanitsiz basari ifadesi: ${pattern}`);
  }
});

test('herkese acik misafir acma yaniti: mesaj komutun gonderildigini soyler (aciliyor/acildi demez)', () => {
  const source = read('routes/guest_passes_routes.js');
  assert.ok(source.includes('${pass.door_name} icin kapi acma komutu gonderildi.'));
  assert.equal(/\$\{pass\.door_name\} aciliyor/.test(source), false);
  for (const pattern of UNPROVEN_DOOR_SUCCESS) {
    assert.equal(pattern.test(source), false, `guest_passes_routes.js icinde kanitsiz basari ifadesi: ${pattern}`);
  }
});
