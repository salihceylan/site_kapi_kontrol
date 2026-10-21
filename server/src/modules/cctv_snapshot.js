// Kamera anlik goruntusunu sunucudan cekme (SSRF KORUMALI). Sozlesme: docs/PLATFORM_KAMERA_CCTV.md.
//
// Kurallar: yalniz https; kullanici bilgisi (user:pass@) yok; ozel / yerel / link-local / yayin adresleri ve localhost ENGEL.
// Ad cozumlemesi SONRASI her adres dogrulanir (biri bile ozel ise engel) ve baglanti dogrulanan adrese SABITLENIR (DNS yeniden baglama yok).
// Yonlendirme IZLENMEZ (3xx = ulasilamaz). Toplam sure 5 sn, govde en cok 2 MB, yalniz image/jpeg | image/png (sihirli baytlarla da dogrulanir).
// Kimlik bilgisi varsa HTTP Basic olarak yalniz bu adrese gonderilir. Bu dosya db.js'i ICE AKTARMAZ.

import dns from 'node:dns';
import https from 'node:https';
import net from 'node:net';

export const SNAPSHOT_TIMEOUT_MS = 5000;
export const SNAPSHOT_MAX_BYTES = 2 * 1024 * 1024;
export const SNAPSHOT_TYPES = Object.freeze(['image/jpeg', 'image/png']);

const BLOCKED = new net.BlockList();
for (const [address, prefix] of [
  ['0.0.0.0', 8],
  ['10.0.0.0', 8],
  ['100.64.0.0', 10],
  ['127.0.0.0', 8],
  ['169.254.0.0', 16],
  ['172.16.0.0', 12],
  ['192.0.0.0', 24],
  ['192.0.2.0', 24],
  ['192.88.99.0', 24],
  ['192.168.0.0', 16],
  ['198.18.0.0', 15],
  ['198.51.100.0', 24],
  ['203.0.113.0', 24],
  ['224.0.0.0', 4],
  ['240.0.0.0', 4],
]) {
  BLOCKED.addSubnet(address, prefix, 'ipv4');
}
for (const [address, prefix] of [
  ['::', 128],
  ['::1', 128],
  ['64:ff9b::', 96],
  ['64:ff9b:1::', 48],
  ['100::', 64],
  ['2001::', 32],
  ['2001:db8::', 32],
  ['2002::', 16],
  ['fc00::', 7],
  ['fe80::', 10],
  ['fec0::', 10],
  ['ff00::', 8],
]) {
  BLOCKED.addSubnet(address, prefix, 'ipv6');
}

// IPv4 eslenmis IPv6 (::ffff:a.b.c.d) ad cozumlemesinde meşru degildir; ayri listede tutulur (BlockList, IPv4 adresleri de
// IPv6 kurallarina eslenmis gibi denetledigi icin ana listeye KONMAZ: tum IPv4 adresleri engellenirdi).
const MAPPED = new net.BlockList();
MAPPED.addSubnet('::ffff:0:0', 96, 'ipv6');

/** Genel (herkese acik) bir IP mi? IP olmayan ya da ozel/yerel/ayrilmis her sey false. */
export function isPublicIp(value) {
  const ip = String(value ?? '').trim().replace(/^\[|\]$/g, '').replace(/%.*$/, '');
  const family = net.isIP(ip);
  if (family === 0) return false;
  if (family === 6 && MAPPED.check(ip, 'ipv6')) return false;
  return !BLOCKED.check(ip, family === 4 ? 'ipv4' : 'ipv6');
}

const LOCAL_SUFFIXES = ['.localhost', '.local', '.localdomain', '.internal', '.intranet', '.lan', '.home', '.corp', '.private'];

/** Ad olarak bile yerel sayilan ana bilgisayar adlari (ad cozumlemesinden ONCE). */
export function isLocalHostname(hostname) {
  const host = String(hostname ?? '').toLowerCase().replace(/\.$/, '');
  if (host === '' || host === 'localhost' || !host.includes('.')) return true;
  return LOCAL_SUFFIXES.some((suffix) => host.endsWith(suffix));
}

/** Anlik goruntu adresi kurallari (kayit sirasinda ve cekmeden once). Gecerliyse URL nesnesi, degilse null. */
export function parseSnapshotUrl(value) {
  let url;
  try {
    url = new URL(String(value ?? '').trim());
  } catch {
    return null;
  }
  if (url.protocol !== 'https:' || url.username !== '' || url.password !== '' || url.hostname === '') return null;
  const host = url.hostname.replace(/^\[|\]$/g, '');
  if (net.isIP(host) === 0 && isLocalHostname(host)) return null;
  if (net.isIP(host) !== 0 && !isPublicIp(host)) return null;
  return url;
}

/** Ad cozumlemesi: TUM adresler genel olmali. Doner { address, family } ya da null. */
export async function resolvePublicAddress(hostname, lookup = dns.promises.lookup) {
  const host = hostname.replace(/^\[|\]$/g, '');
  if (net.isIP(host) !== 0) return isPublicIp(host) ? { address: host, family: net.isIP(host) } : null;
  const found = await lookup(host, { all: true, verbatim: true });
  const list = Array.isArray(found) ? found : [found];
  if (list.length === 0 || list.some((entry) => !isPublicIp(entry?.address))) return null;
  return { address: list[0].address, family: net.isIP(list[0].address) };
}

function looksLike(type, buffer) {
  if (type === 'image/jpeg') return buffer.length > 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  if (type === 'image/png') return buffer.length > 8 && buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  return false;
}

/**
 * Goruntuyu ceker. Hic bir kosulda firlatmaz.
 * @returns {Promise<{ ok: true, contentType: string, body: Buffer } | { ok: false, reason: string }>}
 *   reason: 'blocked' | 'timeout' | 'status' | 'content_type' | 'too_large' | 'network'
 */
export async function fetchSnapshot(rawUrl, options = {}) {
  const {
    username = null,
    password = null,
    lookup = dns.promises.lookup,
    request = https.request,
    timeoutMs = SNAPSHOT_TIMEOUT_MS,
    maxBytes = SNAPSHOT_MAX_BYTES,
  } = options;
  const url = parseSnapshotUrl(rawUrl);
  if (!url) return { ok: false, reason: 'blocked' };

  return new Promise((resolve) => {
    let settled = false;
    let req = null;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try {
        req?.destroy();
      } catch {
        // yok say
      }
      resolve(result);
    };
    const timer = setTimeout(() => finish({ ok: false, reason: 'timeout' }), timeoutMs);

    resolvePublicAddress(url.hostname, lookup).then(
      (target) => {
        if (settled) return;
        if (!target) return finish({ ok: false, reason: 'blocked' });
        const headers = { Accept: SNAPSHOT_TYPES.join(', '), 'User-Agent': 'SmartKeyPass-CCTV/1' };
        if (username) headers.Authorization = `Basic ${Buffer.from(`${username}:${password ?? ''}`, 'utf8').toString('base64')}`;
        const pinned = (_host, lookupOptions, callback) => {
          const cb = typeof lookupOptions === 'function' ? lookupOptions : callback;
          if (lookupOptions && typeof lookupOptions === 'object' && lookupOptions.all) cb(null, [{ address: target.address, family: target.family }]);
          else cb(null, target.address, target.family);
        };
        try {
          req = request(
            {
              protocol: 'https:',
              hostname: url.hostname.replace(/^\[|\]$/g, ''),
              port: url.port ? Number(url.port) : 443,
              path: `${url.pathname}${url.search}`,
              method: 'GET',
              headers,
              lookup: pinned,
              agent: false,
              timeout: timeoutMs,
            },
            (res) => {
              if (res.statusCode !== 200) {
                res.resume();
                return finish({ ok: false, reason: 'status' });
              }
              const type = String(res.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
              if (!SNAPSHOT_TYPES.includes(type)) {
                res.resume();
                return finish({ ok: false, reason: 'content_type' });
              }
              const declared = Number(res.headers['content-length']);
              if (Number.isFinite(declared) && declared > maxBytes) {
                res.resume();
                return finish({ ok: false, reason: 'too_large' });
              }
              const chunks = [];
              let total = 0;
              res.on('data', (chunk) => {
                total += chunk.length;
                if (total > maxBytes) return finish({ ok: false, reason: 'too_large' });
                chunks.push(chunk);
                return undefined;
              });
              res.on('end', () => {
                const body = Buffer.concat(chunks);
                if (!looksLike(type, body)) return finish({ ok: false, reason: 'content_type' });
                return finish({ ok: true, contentType: type, body });
              });
              res.on('error', () => finish({ ok: false, reason: 'network' }));
              res.on('aborted', () => finish({ ok: false, reason: 'network' }));
            },
          );
          req.on('timeout', () => finish({ ok: false, reason: 'timeout' }));
          req.on('error', () => finish({ ok: false, reason: 'network' }));
          req.end();
        } catch {
          finish({ ok: false, reason: 'network' });
        }
        return undefined;
      },
      () => finish({ ok: false, reason: 'network' }),
    );
  });
}
