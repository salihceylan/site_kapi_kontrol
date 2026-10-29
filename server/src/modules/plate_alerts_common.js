// Plaka Tanıma A3: bildirim metinleri ve kopukluk değerlendirmesi için SAF yardımcılar (DB / ağ yok). Eşikler (kırmızı gecikme, uyarı sıklığı, bildirim yaşı)
// koda gömülü değildir: çağıran site ayarından (plate_site_settings) verir.

export const TIME_ZONE = 'Europe/Istanbul';
export const ALERT_KIND_EDGE_LOST = 'edge_lost';
export const EDGE_LOST_AUDIT_ACTION = 'plate.edge_disconnected';
export const INSIDE_TIMEOUT_AUDIT_ACTION = 'plate.inside_timeout';
/** Bildirimde / denetim ayrıntısında en çok bu kadar ad ya da plaka yazılır (kalanı sayı olarak). */
export const MAX_LISTED = 3;

// --- "18:32'de" gibi Türkçe bulunma eki: okunuşun SON sözcüğüne göre (bir/iki -> de, üç/dört/beş -> te, altı/dokuz/on/otuz/sıfır -> da, kırk -> ta) -----------------

const ONES_SUFFIX = Object.freeze(['da', 'de', 'de', 'te', 'te', 'te', 'da', 'de', 'de', 'da']); // sıfır .. dokuz
const TENS_SUFFIX = Object.freeze({ 10: 'da', 20: 'de', 30: 'da', 40: 'ta', 50: 'de' });

/** 0-59 arası bir sayının okunuşunun son sözcüğüne göre -de/-da/-te/-ta. */
export function locativeSuffix(n) {
  const value = Number.isInteger(n) && n >= 0 && n <= 59 ? n : 0;
  if (value < 10) return ONES_SUFFIX[value];
  return value % 10 === 0 ? TENS_SUFFIX[value] : ONES_SUFFIX[value % 10];
}

/** Saat:dakika okunuşunda son sözcük dakikadır; dakika 00 ise saattir ("18:00" -> "on sekiz'de"). */
export const clockSuffix = (hour, minute) => (minute === 0 ? locativeSuffix(hour) : locativeSuffix(minute));

/** İstanbul saatiyle { hour, minute } (sunucu saat dilimine bağlı değil). */
export function clockParts(date, timeZone = TIME_ZONE) {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(date);
  const pick = (type) => Number(parts.find((p) => p.type === type)?.value ?? 0);
  return { hour: pick('hour') % 24, minute: pick('minute') };
}

/** Sakin bildirimi: "Aracınız 18:32'de giriş yaptı." Plaka metne konmaz (kilit ekranında görünür). */
export function movementTexts({ direction, seenAt, timeZone = TIME_ZONE }) {
  const verb = direction === 'cikis' ? 'çıkış' : 'giriş';
  const { hour, minute } = clockParts(seenAt, timeZone);
  const text = `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
  return { title: `Aracınız ${verb} yaptı`, body: `Aracınız ${text}'${clockSuffix(hour, minute)} ${verb} yaptı.` };
}

// --- Kopukluk (kenar PC / kamera) ---------------------------------------------------------------------------------------------------

const ageSeconds = (value, nowMs) => {
  if (value === null || value === undefined) return null;
  const ms = new Date(value).getTime();
  return Number.isNaN(ms) ? null : Math.max(0, Math.round((nowMs - ms) / 1000));
};

/**
 * Kırmızı (koptu) durumdaki bileşenler. En az bir kez haber vermiş olması şart (hiç bağlanmamış = gri, uyarı sebebi değil).
 * @param {{ edgeClients: Array<{ name: string, last_seen_at: any }>, cameras: Array<{ name: string, reported_at: any, last_frame_at: any }>, critSeconds: number, nowMs: number }} input
 */
export function lostComponents({ edgeClients, cameras, critSeconds, nowMs }) {
  const edge = [];
  for (const client of edgeClients) {
    const age = ageSeconds(client.last_seen_at, nowMs);
    if (age !== null && age >= critSeconds) edge.push({ name: client.name, ageSeconds: age });
  }
  const lostCameras = [];
  for (const camera of cameras) {
    if (camera.reported_at === null || camera.reported_at === undefined) continue;
    const age = ageSeconds(camera.last_frame_at, nowMs);
    if (age === null || age >= critSeconds) lostCameras.push({ name: camera.name, ageSeconds: age });
  }
  return { edge, cameras: lostCameras, any: edge.length > 0 || lostCameras.length > 0 };
}

const listNames = (items) => {
  const names = items.slice(0, MAX_LISTED).map((item) => item.name);
  return items.length > MAX_LISTED ? `${names.join(', ')} +${items.length - MAX_LISTED}` : names.join(', ');
};

/** Yönetici uyarısı (anlık bildirim metni). Kenar PC koptuysa kameralar onun sonucu sayılır, ayrıca sayılır. */
export function lostAlertTexts(lost) {
  const parts = [];
  if (lost.edge.length) parts.push(`Kenar PC: ${listNames(lost.edge)}`);
  if (lost.cameras.length) parts.push(`Kamera: ${listNames(lost.cameras)}`);
  return { title: 'Plaka tanıma bağlantısı koptu', body: `${parts.join(' • ')}. Güvenlik kulübesindeki bilgisayarı ve kameraları kontrol edin.` };
}
