// Cloudflare kenar (edge) IP aralıkları — https://www.cloudflare.com/ips/ (yayımlanan liste; nadiren değişir).
// İki kullanım:
//  1) TRUST_PROXY=loopback,cloudflare: nginx -> Express zincirinde Cloudflare halkası da güvenilir sayılır; req.ip gerçek
//     istemci olur (Cloudflare'in X-Forwarded-For'a eklediği adres). Kökene doğrudan bağlanan saldırgan başlıkla IP
//     uyduramaz (en sağdaki halka onun kendi adresidir ve güvenilmez).
//  2) Güvenlik ağı: req.ip bir Cloudflare adresiyse istemci IP'si ÇÖZÜLEMEMİŞ demektir (binlerce kullanıcı aynı kenar
//     IP'sini paylaşır); IP geneli giriş kilidi bu durumda UYGULANMAZ (aksi halde ortak kilit = hizmet reddi).
// Liste güncellemesi: yukarıdaki adresten kontrol edilip burada güncellenir.

import net from 'node:net';
import { normalizeIp } from './client_ip.js';

export const CLOUDFLARE_IPV4_CIDRS = Object.freeze([
  '173.245.48.0/20',
  '103.21.244.0/22',
  '103.22.200.0/22',
  '103.31.4.0/22',
  '141.101.64.0/18',
  '108.162.192.0/18',
  '190.93.240.0/20',
  '188.114.96.0/20',
  '197.234.240.0/22',
  '198.41.128.0/17',
  '162.158.0.0/15',
  '104.16.0.0/13',
  '104.24.0.0/14',
  '172.64.0.0/13',
  '131.0.72.0/22',
]);

export const CLOUDFLARE_IPV6_CIDRS = Object.freeze([
  '2400:cb00::/32',
  '2606:4700::/32',
  '2803:f800::/32',
  '2405:b500::/32',
  '2405:8100::/32',
  '2a06:98c0::/29',
  '2c0f:f248::/32',
]);

export const CLOUDFLARE_CIDRS = Object.freeze([...CLOUDFLARE_IPV4_CIDRS, ...CLOUDFLARE_IPV6_CIDRS]);

const blockList = new net.BlockList();
for (const cidr of CLOUDFLARE_IPV4_CIDRS) {
  const [address, prefix] = cidr.split('/');
  blockList.addSubnet(address, Number(prefix), 'ipv4');
}
for (const cidr of CLOUDFLARE_IPV6_CIDRS) {
  const [address, prefix] = cidr.split('/');
  blockList.addSubnet(address, Number(prefix), 'ipv6');
}

/** Adres bir Cloudflare kenar adresi mi? (IPv4-eşlemeli IPv6 da tanınır) */
export function isCloudflareIp(raw) {
  const ip = normalizeIp(raw);
  if (!ip) {
    return false;
  }
  const family = net.isIPv4(ip) ? 'ipv4' : 'ipv6';
  try {
    return blockList.check(ip, family);
  } catch (_error) {
    return false;
  }
}
