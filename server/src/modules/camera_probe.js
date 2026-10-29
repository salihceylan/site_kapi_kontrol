// Kamera bağlantı "Sına"sı: sunucudan, zaman aşımı sınırlı, YALNIZ TCP el sıkışma denemesi. Görüntü çekilmez, işlenmez, kimlik bilgisi gönderilmez.
//
// SSRF kuralı: yalnız herkese açık adresler denenir (ad çözümlemesinde TÜM adresler genel olmalı). Kameralar çoğunlukla sitenin yerel ağındadır;
// sunucu oraya ulaşamaz. Bu durumda dürüst sonuç döner: "sunucudan sınanamaz" (başarı SAYILMAZ, hata da sayılmaz). Bu dosya db.js'i İÇE AKTARMAZ.

import net from 'node:net';
import { isLocalHostname, resolvePublicAddress } from './cctv_snapshot.js';

export const PROBE_TIMEOUT_MS = 4000;
export const DEFAULT_PROBE_PORT = 554;

const RESULTS = Object.freeze({
  connected: { ok: true, message: 'Bağlantı kuruldu (adrese ve bağlantı noktasına ulaşıldı).' },
  not_testable: { ok: false, message: 'Bu adres yerel ağda; sunucudan sınanamaz. Kamera olay gönderdiğinde "son olay" zamanı güncellenir.' },
  unresolved: { ok: false, message: 'Adres çözümlenemedi.' },
  timeout: { ok: false, message: 'Zaman aşımı: adrese ulaşılamadı.' },
  refused: { ok: false, message: 'Bağlantı reddedildi ya da bağlantı noktası kapalı.' },
});

function result(reason) {
  return { reason, ...RESULTS[reason] };
}

/** Çıktı yalnız { ok, reason, message }: ham adres / hata metni dönmez. `connect` ve `resolve` testlerde değiştirilir. */
export async function probeTcp({ host, port }, { resolve = resolvePublicAddress, connect = net.connect, timeoutMs = PROBE_TIMEOUT_MS } = {}) {
  const portNumber = Number.isInteger(port) && port >= 1 && port <= 65535 ? port : DEFAULT_PROBE_PORT;
  const name = String(host ?? '').trim().replace(/^\[|\]$/g, '');
  if (net.isIP(name) === 0 && isLocalHostname(name)) return result('not_testable');
  let target;
  try {
    target = await resolve(name);
  } catch {
    return result('unresolved');
  }
  if (!target) return result('not_testable');
  return new Promise((done) => {
    let settled = false;
    const socket = connect({ host: target.address, port: portNumber });
    const finish = (reason) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      done(result(reason));
    };
    socket.setTimeout(timeoutMs);
    socket.once('connect', () => finish('connected'));
    socket.once('timeout', () => finish('timeout'));
    socket.once('error', () => finish('refused'));
  });
}
