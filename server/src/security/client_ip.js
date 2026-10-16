// İstemci IP'si yardımcıları: hız sınırı / kilit anahtarları için normalleştirme ve IPv6 /64 kovası.
//
// IPv6'da tek bir abone tipik olarak bir /64 (çoğu zaman /56 ya da /48) alır ve bu aralıktaki adresleri serbestçe
// değiştirebilir: ham adresle anahtarlanan bir sınırlayıcı, adres değiştiren saldırgan tarafından kolayca atlatılır.
// Bu nedenle IPv6 adresleri /64 önekine indirgenir. IPv4-eşlemeli IPv6 (::ffff:1.2.3.4) IPv4 olarak ele alınır.

import net from 'node:net';

/** "::ffff:1.2.3.4" -> "1.2.3.4"; bölge kimliği (%eth0) atılır; küçük harf. Geçersizse boş dize. */
export function normalizeIp(raw) {
  let text = String(raw ?? '').trim().toLowerCase();
  if (!text) {
    return '';
  }
  const zone = text.indexOf('%');
  if (zone >= 0) {
    text = text.slice(0, zone);
  }
  if (text.startsWith('::ffff:') && net.isIPv4(text.slice(7))) {
    return text.slice(7);
  }
  return net.isIP(text) ? text : '';
}

/** IPv6 adresini 8 onaltılık gruba açar (gömülü IPv4 kuyruğu dahil). Geçersizse null. */
export function expandIpv6(raw) {
  const text = String(raw ?? '').trim().toLowerCase();
  if (!net.isIPv6(text)) {
    return null;
  }
  let head = text;
  const tail = [];
  const lastColon = head.lastIndexOf(':');
  const maybeV4 = head.slice(lastColon + 1);
  if (net.isIPv4(maybeV4)) {
    const octets = maybeV4.split('.').map(Number);
    tail.push(((octets[0] << 8) | octets[1]).toString(16), ((octets[2] << 8) | octets[3]).toString(16));
    head = head.slice(0, lastColon + 1);
    if (head.endsWith(':') && !head.endsWith('::')) {
      head = head.slice(0, -1);
    }
  }
  const [left, right] = head.includes('::') ? head.split('::') : [head, null];
  const leftParts = left ? left.split(':').filter((part) => part !== '') : [];
  const rightParts = right ? right.split(':').filter((part) => part !== '') : [];
  const fixed = [...leftParts, ...rightParts, ...tail];
  const missing = 8 - fixed.length;
  if (missing < 0 || (right === null && missing !== 0)) {
    return null;
  }
  const groups = [...leftParts, ...Array(right === null ? 0 : missing).fill('0'), ...rightParts, ...tail];
  if (groups.length !== 8) {
    return null;
  }
  return groups.map((group) => group.replace(/^0+(?=.)/, ''));
}

/**
 * Sınırlayıcı anahtarı için IP kovası: IPv4 olduğu gibi, IPv6 /64 öneki ("2001:db8:1:2::/64").
 * IP çözümlenemezse "unknown" (bu durumda tüm bu istekler tek kovayı paylaşır: güvenli taraf).
 */
export function ipBucket(raw) {
  const ip = normalizeIp(raw);
  if (!ip) {
    return 'unknown';
  }
  if (net.isIPv4(ip)) {
    return ip;
  }
  const groups = expandIpv6(ip);
  if (!groups) {
    return 'unknown';
  }
  return `${groups.slice(0, 4).join(':')}::/64`;
}

// Genel (internet) olmayan aralıklar: loopback, özel, bağlantı-yerel, CGNAT, ULA. req.ip bunlardan biriyse istemci
// IP'si ÇÖZÜLEMEMİŞTİR (ör. nginx X-Forwarded-For iletmiyor -> herkes 127.0.0.1): bu adres birçok kullanıcıya ortaktır.
const NON_PUBLIC = new net.BlockList();
NON_PUBLIC.addSubnet('127.0.0.0', 8, 'ipv4');
NON_PUBLIC.addSubnet('10.0.0.0', 8, 'ipv4');
NON_PUBLIC.addSubnet('172.16.0.0', 12, 'ipv4');
NON_PUBLIC.addSubnet('192.168.0.0', 16, 'ipv4');
NON_PUBLIC.addSubnet('169.254.0.0', 16, 'ipv4');
NON_PUBLIC.addSubnet('100.64.0.0', 10, 'ipv4');
NON_PUBLIC.addSubnet('0.0.0.0', 8, 'ipv4');
NON_PUBLIC.addAddress('::1', 'ipv6');
NON_PUBLIC.addAddress('::', 'ipv6');
NON_PUBLIC.addSubnet('fc00::', 7, 'ipv6');
NON_PUBLIC.addSubnet('fe80::', 10, 'ipv6');

/** Adres genel (internet) bir IP mi? Geçersiz / loopback / özel aralık -> false. */
export function isPublicIp(raw) {
  const ip = normalizeIp(raw);
  if (!ip) {
    return false;
  }
  try {
    return !NON_PUBLIC.check(ip, net.isIPv4(ip) ? 'ipv4' : 'ipv6');
  } catch (_error) {
    return false;
  }
}

/** Express isteğinden kova (req.ip `trust proxy` ayarına göre hesaplanır). */
export function requestIpBucket(req) {
  return ipBucket(req?.ip || req?.socket?.remoteAddress || '');
}
