// S-C: günlük metni kişisel veri / belirteç temizleyici (§0.9) ve PII yazan günlük satırlarının kaynak koruması.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describeErrorForLog, redactLogText } from '../src/security/log_redact.js';

const srcRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'src');
const read = (relative) => fs.readFileSync(path.join(srcRoot, relative), 'utf8');

describe('redactLogText / describeErrorForLog', () => {
  it('e-posta, telefon, Bearer ve JWT benzeri belirteçler maskelenir; kod korunur', () => {
    const text = redactLogText(
      '550 5.1.1 <ayse.yilmaz@example.com>: Recipient rejected; tel +90 532 123 45 67; Bearer abc.def.ghi; eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI0MiJ9.c2ln',
    );
    assert.equal(/ayse|example\.com|532 123|abc\.def|eyJhbGci/.test(text), false, text);
    assert.match(text, /^550 5\.1\.1/);
    assert.match(text, /<e-posta>/);
    assert.match(text, /<numara>/);
  });

  it('kısa sayılar (port, kod) korunur; uzunluk sınırı uygulanır', () => {
    assert.equal(redactLogText('ECONNREFUSED 127.0.0.1:587'), 'ECONNREFUSED 127.0.0.1:587');
    assert.equal(redactLogText('x'.repeat(1000)).length, 300);
  });

  it('describeErrorForLog: kod + temizlenmiş mesaj', () => {
    const error = Object.assign(new Error('Can\'t send mail - all recipients were rejected: 550 <a@b.co>'), { code: 'EENVELOPE' });
    const line = describeErrorForLog(error);
    assert.match(line, /^EENVELOPE: /);
    assert.equal(line.includes('a@b.co'), false);
    assert.equal(describeErrorForLog(undefined), 'hata');
  });
});

describe('kaynak koruması: düzeltilen PII günlük satırları geri gelmesin', () => {
  it('QR onay günlüğü kullanıcı adını yazmaz', () => {
    const source = read('services/qr_access_service.js');
    assert.equal(/QR Dogrulama ONAY\][^\n]*user_name/.test(source), false);
  });

  it('MQTT komutunun requested_by alanına kişisel veri (e-posta / ad / misafir başlığı) yazılmaz (R1 B8)', () => {
    const sources = {
      'routes/app_doors_routes.js': read('routes/app_doors_routes.js'),
      'routes/admin_routes.js': read('routes/admin_routes.js'),
      'routes/guest_passes_routes.js': read('routes/guest_passes_routes.js'),
      'services/qr_access_service.js': read('services/qr_access_service.js'),
    };
    for (const [name, source] of Object.entries(sources)) {
      const values = [...source.matchAll(/requestedBy:\s*([^\n]+)/g)].map((match) => match[1]);
      assert.ok(values.length > 0, name);
      for (const value of values) {
        assert.equal(/email|user_name|full_name|title/.test(value), false, `${name}: ${value}`);
        assert.match(value, /`(u|guest):\$\{Number\(/, `${name}: ${value}`);
      }
    }
  });

  it('katılım bildirimi / yönetici daveti hata günlükleri alıcı e-postasını ve ham SMTP mesajını yazmaz', () => {
    const membership = read('services/membership_service.js');
    assert.equal(/Katılım bildirimi e-postası gönderilemedi \(\$\{mgr\.email\}\)/.test(membership), false);
    const site = read('services/site_service.js');
    assert.equal(/gönderilemedi:', mailErr\?\.message\)/.test(site), false);
  });
});
