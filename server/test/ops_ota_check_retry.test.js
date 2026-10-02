import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const bridgeSource = fs.readFileSync(path.join(here, '..', 'src', 'mqtt_bridge.js'), 'utf8');

// Firmware (cihaz_kontrol/include/mqtt_baglanti.h): ota_check içinde `retry:true` aynı sürüm için tükenen
// OTA deneme sayacını sıfırlar. Yönetici paneli toplu "OTA kontrolü" bu bayrağı göndermezse, geçici ağ
// hatalarında 3 hakkı tüketen cihazlar yeni sürüm çıkana kadar eski firmware'de takılı kalır.
test('toplu ota_check komutu retry:true taşır', () => {
  const start = bridgeSource.indexOf("action: 'ota_check'");
  assert.ok(start > 0, "mqtt_bridge.js içinde action: 'ota_check' bulunamadı");
  const block = bridgeSource.slice(start, start + 400);
  assert.match(block, /retry:\s*true/);
});
