// İstek günlüğü: arama metni (?q=) kişisel veri içerebilir (süper kullanıcının site başvurusu listesinde aradığı başvuran e-postası / adı);
// loga DÜŞMEZ. Mevcut maskeler (token, ?t= vb.) korunur. (DB'siz.)
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createRequestLogger, maskSensitiveUrl } from '../src/middlewares/request_logger.js';

describe('istek günlüğü: q (arama) sorgu parametresi maskelenir', () => {
  it('?q= değeri maskelenir (kodlu e-posta, ad, Türkçe karakter); diğer parametreler korunur', () => {
    assert.equal(maskSensitiveUrl('/admin/site-applications?status=pending&q=ayse%40example.com&limit=30'), '/admin/site-applications?status=pending&q=***&limit=30');
    assert.equal(maskSensitiveUrl('/admin/site-applications?q=Ayşe%20Yılmaz'), '/admin/site-applications?q=***');
    assert.equal(maskSensitiveUrl('/admin/site-applications?q='), '/admin/site-applications?q=***');
    assert.equal(maskSensitiveUrl('/x?a=1&Q=gizli&b=2'), '/x?a=1&Q=***&b=2', 'büyük-küçük harf duyarsız');
  });

  it('yalnız tam "q" anahtarı: q ile başlayan / biten başka parametreler ve yol parçaları etkilenmez', () => {
    assert.equal(maskSensitiveUrl('/x?qty=2&faq=1&sq=3'), '/x?qty=2&faq=1&sq=3');
    assert.equal(maskSensitiveUrl('/q/ayse'), '/q/ayse');
  });

  it('mevcut maskeler korunur (token, ?t=, code, yol token\'ları)', () => {
    assert.equal(maskSensitiveUrl('/auth/reset-password?token=abc123&lang=tr'), '/auth/reset-password?token=***&lang=tr');
    assert.equal(maskSensitiveUrl('/public/announcement-unsubscribe?t=abc.def'), '/public/announcement-unsubscribe?t=***');
    assert.equal(maskSensitiveUrl('/x?code=123456&q=a'), '/x?code=***&q=***');
    assert.equal(maskSensitiveUrl('/guest/AbCdEf123456'), '/guest/***');
  });

  it('günlük satırında arama metni (e-posta / ad) YOK; yol ve durum görünür', () => {
    const lines = [];
    const middleware = createRequestLogger({ logger: { log: (line) => lines.push(line) } });
    const handlers = {};
    const req = { method: 'GET', originalUrl: '/admin/site-applications?q=ayse.basvuran%40qa.example&status=all', path: '/admin/site-applications' };
    const res = { statusCode: 200, on: (event, fn) => { handlers[event] = fn; } };
    middleware(req, res, () => {});
    handlers.finish();
    assert.equal(lines.length, 1);
    assert.match(lines[0], /^\[API\] GET \/admin\/site-applications\?q=\*\*\*&status=all -> 200 \(\d+ms\)$/);
    assert.equal(lines[0].includes('ayse'), false);
    assert.equal(lines[0].includes('qa.example'), false);
  });
});
