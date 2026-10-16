// Express `trust proxy` ayarı (req.ip / req.secure / req.protocol bundan türetilir).
//
// Neden "loopback" (varsayılan): canlıda nginx aynı makinede 127.0.0.1:8080'e vekalet eder. "loopback" yalnızca
// bağlantının KENDİSİ 127.0.0.1/::1'den geliyorsa X-Forwarded-For'un son halkasına güvenir. Eski ayar (`1` = "bir
// atlama") ise eşin kim olduğuna bakmaz: 8080 portu bir gün dışarı açılırsa (güvenlik duvarı hatası, docker port
// yayını) saldırgan kendi yazdığı X-Forwarded-For ile istediği IP'yi "req.ip" yapar ve IP tabanlı hız sınırlarını /
// giriş kilitlerini atlatır. "loopback" ile doğrudan gelen istekte başlık yok sayılır, req.ip gerçek eştir.
//
// TRUST_PROXY ortam değişkeni (isteğe bağlı):
//   (boş)                    -> "loopback"
//   loopback|linklocal|uniquelocal, IP ya da CIDR listesi (virgülle) -> olduğu gibi (ör. "loopback,10.0.0.0/8")
//   cloudflare               -> yayımlanan Cloudflare aralıkları (ör. "loopback,cloudflare": API turuncu bulut arkasındaysa)
//   false|0|off|none         -> vekil yok (req.ip = soket adresi)
//   1..5 (atlama sayısı)     -> kabul edilir ama UYARI üretir (eşi doğrulamaz)
//   true                     -> REDDEDİLİR (herkese güven = başlık sahteciliği); "loopback" kullanılır
// Cloudflare turuncu bulut önündeyse: TRUST_PROXY=loopback,cloudflare ya da nginx'te real_ip (set_real_ip_from
// <Cloudflare aralıkları>; real_ip_header CF-Connecting-IP). İkisi de yoksa tüm istemciler Cloudflare kenar IP'leri
// olarak görünür (IP tabanlı sınırlar binlerce kullanıcıya ortak olur; giriş korumasının IP geneli katmanı bu durumda
// kendini devre dışı bırakır — security/login_guard.js).

import net from 'node:net';
import { CLOUDFLARE_CIDRS, isCloudflareIp } from './cloudflare_ranges.js';

export const DEFAULT_TRUST_PROXY = 'loopback';
const CLOUDFLARE_ALIAS = 'cloudflare';
const NAMED_RANGES = new Set(['loopback', 'linklocal', 'uniquelocal']);
const MAX_HOPS = 5;

function isValidCidr(entry) {
  const slash = entry.indexOf('/');
  if (slash < 0) {
    return net.isIP(entry) !== 0;
  }
  const address = entry.slice(0, slash);
  const prefixText = entry.slice(slash + 1);
  const family = net.isIP(address);
  if (!family || !/^\d{1,3}$/.test(prefixText)) {
    return false;
  }
  const prefix = Number(prefixText);
  return family === 4 ? prefix >= 0 && prefix <= 32 : prefix >= 0 && prefix <= 128;
}

/**
 * @returns {{ value: string|number|boolean|string[], warnings: string[] }}
 *   value doğrudan `app.set('trust proxy', value)` ile kullanılır. Uyarılarda yalnızca ayarın biçimi anlatılır.
 */
export function resolveTrustProxy(env = process.env) {
  const raw = String(env?.TRUST_PROXY ?? '').trim();
  const warnings = [];
  if (!raw) {
    return { value: DEFAULT_TRUST_PROXY, warnings };
  }
  const lowered = raw.toLowerCase();
  if (['false', '0', 'off', 'none', 'no'].includes(lowered)) {
    return { value: false, warnings };
  }
  if (['true', 'yes', 'on', 'all', '*'].includes(lowered)) {
    warnings.push(
      'TRUST_PROXY=true reddedildi (her esin X-Forwarded-For basligina guvenmek IP sahteciligine acar); "loopback" kullaniliyor.',
    );
    return { value: DEFAULT_TRUST_PROXY, warnings };
  }
  if (/^\d+$/.test(lowered)) {
    const hops = Number(lowered);
    if (hops >= 1 && hops <= MAX_HOPS) {
      warnings.push(
        `TRUST_PROXY=${hops} (atlama sayisi) esin kim oldugunu dogrulamaz; 8080 portu disariya aciksa X-Forwarded-For ile IP sahteciligi mumkundur. Oneri: "loopback" (nginx ayni makinede) ya da vekil IP/CIDR listesi.`,
      );
      return { value: hops, warnings };
    }
    warnings.push(`TRUST_PROXY atlama sayisi 1-${MAX_HOPS} disinda; "loopback" kullaniliyor.`);
    return { value: DEFAULT_TRUST_PROXY, warnings };
  }
  const entries = lowered.split(',').map((entry) => entry.trim()).filter(Boolean);
  const invalid = entries.filter((entry) => !NAMED_RANGES.has(entry) && entry !== CLOUDFLARE_ALIAS && !isValidCidr(entry));
  if (entries.length === 0 || invalid.length > 0) {
    warnings.push(
      `TRUST_PROXY icinde gecersiz ${invalid.length} girdi var (ad: loopback/linklocal/uniquelocal/cloudflare ya da IP/CIDR beklenir); "loopback" kullaniliyor.`,
    );
    return { value: DEFAULT_TRUST_PROXY, warnings };
  }
  // "cloudflare" takma adi: yayimlanan Cloudflare kenar araliklari (security/cloudflare_ranges.js).
  const expanded = entries.flatMap((entry) => (entry === CLOUDFLARE_ALIAS ? CLOUDFLARE_CIDRS : [entry]));
  if (entries.includes(CLOUDFLARE_ALIAS) && !entries.includes('loopback')) {
    warnings.push('TRUST_PROXY "cloudflare" iceriyor ama "loopback" yok; nginx ayni makinedeyse "loopback,cloudflare" yazin.');
  }
  return { value: expanded.length === 1 ? expanded[0] : expanded, warnings };
}

export const CLOUDFLARE_TRUST_WARNING =
  '[ENV] UYARI: TRUST_PROXY=loopback,cloudflare gerekli: tum istekler Cloudflare adresiyle gorunuyor (API turuncu bulut ' +
  'arkasinda, istemci IP\'si cozulemiyor). IP tabanli hiz sinirlari tum kullanicilara ortak olur; .env\'e ' +
  'TRUST_PROXY=loopback,cloudflare yazip yeniden baslatin (ya da nginx real_ip + CF-Connecting-IP).';

/**
 * Açılıştan sonra req.ip bir Cloudflare kenar adresi çıkarsa (trust proxy ayarı Cloudflare'i kapsamıyor) süreç başına
 * TEK SEFER açık bir uyarı yazar. Uyarıdan sonra maliyeti tek bir boolean kontrolüdür. İsteği değiştirmez.
 */
export function createTrustProxyMonitor({ logger = console } = {}) {
  let warned = false;
  const middleware = (req, _res, next) => {
    if (!warned && isCloudflareIp(req.ip)) {
      warned = true;
      try {
        logger.warn(CLOUDFLARE_TRUST_WARNING);
      } catch (_error) {
        // günlük hatası isteği etkilemez
      }
    }
    next();
  };
  middleware.hasWarned = () => warned;
  return middleware;
}
