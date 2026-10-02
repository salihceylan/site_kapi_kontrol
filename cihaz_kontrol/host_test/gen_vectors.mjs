// Node crypto ile rastgele HMAC vektorleri uretir: "token uid ch action sig" (bosluk ayracli). Firmware cekirdegi bunlarla capraz dogrulanir.
import crypto from 'node:crypto';
import fs from 'node:fs';
const alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
function rnd(n, set) { let s = ''; const b = crypto.randomBytes(n); for (let i = 0; i < n; i++) s += set[b[i] % set.length]; return s; }
const lines = [];
// sartname vektorleri
const T0 = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE';
for (const a of ['open', 'pulse']) lines.push([T0, '240AC4E2E001', '0123456789abcdef', a, crypto.createHmac('sha256', T0).update(`${a}|240AC4E2E001|0123456789abcdef`).digest('hex')].join(' '));
for (let i = 0; i < 600; i++) {
  const len = 16 + (crypto.randomBytes(1)[0] % 49);            // 16..64 (wifiLocalTokenGecerliMi araligi)
  const token = rnd(len, alpha);
  const uid = rnd(12, '0123456789ABCDEF');
  const ch = rnd(16, '0123456789abcdef');
  const action = i % 2 === 0 ? 'open' : 'pulse';
  const sig = crypto.createHmac('sha256', token).update(`${action}|${uid}|${ch}`).digest('hex');
  lines.push([token, uid, ch, action, sig].join(' '));
}
// uc deger: 64 bayttan uzun anahtar HMAC'te karilir (cihaz tokeni <=64 ama referans uygulama genel olmali)
fs.writeFileSync('vectors.txt', lines.join('\n') + '\n');
console.log('vektor sayisi', lines.length);
