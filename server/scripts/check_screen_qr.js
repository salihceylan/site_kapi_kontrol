import './_dev_guard.js';
import { deviceScreenQrStore } from '../src/mqtt_bridge.js';

// Ekran QR token'lari kapi acabilir: ciktiya (terminal/log) ham yazilmaz; yalnizca ilk 2 karakter + uzunluk gosterilir.
function maskToken(token) {
  if (!token) {
    return '-';
  }
  const text = String(token);
  return `${text.slice(0, 2)}***(${text.length})`;
}

setTimeout(() => {
  console.log('--- CANLI SCREEN QR STORE ---');
  for (const [uid, data] of deviceScreenQrStore.entries()) {
    console.log(`UID: ${uid} | Token: ${maskToken(data.currentToken)} | Prev: ${maskToken(data.previousToken)} | Kalan: ${Math.round((data.expiresAt - Date.now()) / 1000)}s`);
  }
  if (deviceScreenQrStore.size === 0) {
    console.log('Henuz screen_qr mesaji gelmedi veya bellek bos.');
  }
  process.exit(0);
}, 2000);

