// Duyurular (modul: announcements): ~35 yayinlanmis duyuru, okundu kayitlari, 3 okunmamis guncel, 1 geri cekilmis.
// E-POSTA YOK: send_email=false, alici email_status='none', email alani bos; kuyruk/zamanlayici tablolarina yazilmaz.

import { addDays } from '../lib/util.mjs';

const TEMPLATES = [
  // [aciklama anahtari, baslik, govde, onem]
  ['lift', 'Asansör Bakım Çalışması', 'Asansör yıllık bakımı nedeniyle {gun} günü 10:00-14:00 saatleri arasında asansörler hizmet veremeyecektir. Anlayışınız için teşekkür ederiz.', 'normal'],
  ['water', 'Planlı Su Kesintisi', 'Şebeke bakım çalışması nedeniyle {gun} günü 09:00-13:00 arasında su kesintisi yaşanabilir. Lütfen gerekli önlemleri alınız.', 'normal'],
  ['assembly', 'Olağan Genel Kurul Toplantısı Daveti', 'Olağan genel kurul toplantımız {gun} günü saat 19:00\'da site toplantı salonunda yapılacaktır. Gündem: faaliyet raporu, işletme projesi, aidat tutarı ve yönetim kurulu seçimi.', 'normal'],
  ['dues', 'Aidat Hatırlatması', 'Aylık aidatın son ödeme günü her ayın 10\'udur. Havale yaparken açıklamaya daire numaranızı yazmayı unutmayınız.', 'normal'],
  ['heating', 'Kalorifer Sezonu Başlıyor', 'Merkezi ısıtma sistemi {gun} tarihinden itibaren çalıştırılacaktır. Petek havalandırması yapmanız önerilir.', 'normal'],
  ['pest', 'İlaçlama Çalışması', 'Bahçe ve ortak alanlarda {gun} günü böcek ilaçlama yapılacaktır. Evcil hayvanlarınızı o gün bahçeye çıkarmayınız.', 'normal'],
  ['parking', 'Otopark Kullanım Kuralları', 'Misafir araçlarının otoparkta en fazla 24 saat kalabileceğini, yangın merdiveni önüne araç park edilmemesi gerektiğini hatırlatırız.', 'normal'],
  ['noise', 'Gürültü ve Sessizlik Saatleri', 'Komşularımızın huzuru için 22:00-08:00 saatleri arasında gürültülü işlerden kaçınılması rica olunur.', 'normal'],
  ['holiday', 'Bayram Tebriği', 'Yönetim olarak tüm sakinlerimizin bayramını kutlar, sağlık ve mutluluk dileriz.', 'normal'],
  ['garbage', 'Çöp Toplama Saatleri', 'Çöpler 20:00-22:00 saatleri arasında kapı önüne bırakılmalı, ortak alanlara çöp poşeti konulmamalıdır.', 'normal'],
  ['garden', 'Bahçe Düzenleme Çalışması', 'Bahçe düzenleme çalışması {gun} günü başlayacaktır. Çalışma sırasında bahçe girişlerinde dikkatli olunuz.', 'normal'],
  ['camera', 'Güvenlik Kamerası Bakımı', 'Kamera sistemi bakımı {gun} günü yapılacaktır. Bu sürede görevli kapıda nöbet tutacaktır.', 'normal'],
];
const URGENT = [
  ['2023-08-14', 'ACİL: Asansör Arızası', 'Asansör arızalanmıştır, teknik servis çağrılmıştır. Onarım tamamlanana kadar merdiveni kullanınız.'],
  ['2023-12-05', 'ACİL: Doğalgaz Kesintisi', 'Bölgede doğalgaz kesintisi yaşanmaktadır. Dağıtım şirketi çalışma yapmaktadır, kesinti sürecinde ocak ve soba kullanmayınız.'],
  ['2024-06-19', 'ACİL: Elektrik Kesintisi', 'Ana panoda arıza nedeniyle ortak alan elektrikleri kesilmiştir. Teknik görevli müdahale etmektedir.'],
  ['2025-11-09', 'ACİL: Su Kaçağı', 'B blok bodrum katında su kaçağı tespit edilmiştir. Vana kapatılmıştır; sular kısa süreli kesilecektir.'],
];

/** '2026-5-4' gibi tarihleri '2026-05-04' bicimine getirir (metin siralamasi ve Date ayristirmasi icin). */
function norm(text) {
  return String(text).replace(/-([0-9])(?=-|$)/g, '-0$1');
}

export async function seedAnnouncements(ctx) {
  const { q, rng, site, people, manager, TODAY, START } = ctx;
  const siteCode = site.code;
  const list = [];
  // her yil sabit olaylar
  for (let y = 2023; y <= Number(TODAY.slice(0, 4)); y += 1) {
    list.push([`${y}-03-0${rng.int(2, 8)}`, ...TEMPLATES[2], `${y}-03-${rng.int(15, 28)}`]);
    list.push([`${y}-10-${rng.int(8, 14)}`, ...TEMPLATES[4], `${y}-10-15`]);
    list.push([`${y}-05-${rng.int(2, 9)}`, ...TEMPLATES[0], `${y}-05-${rng.int(12, 24)}`]);
    list.push([`${y}-${String(rng.int(6, 9)).padStart(2, '0')}-${rng.int(2, 9)}`, ...TEMPLATES[5], `${y}-07-${rng.int(10, 20)}`]);
  }
  // rastgele diger duyurular
  const others = [1, 3, 6, 7, 8, 9, 10, 11, 3, 1, 6, 8, 11, 9];
  for (let i = 0; i < 17; i += 1) {
    const t = TEMPLATES[others[i % others.length]];
    const year = rng.int(2023, 2026);
    const month = rng.int(1, year === 2026 ? 9 : 12);
    list.push([`${year}-${String(month).padStart(2, '0')}-${String(rng.int(2, 26)).padStart(2, '0')}`, ...t, `${year}-${String(month).padStart(2, '0')}-${rng.int(27, 28)}`]);
  }
  for (const [date, title, body] of URGENT) list.push([date, 'urgent-flag', title, body, 'urgent', date]);
  // aidat hatirlatmalari (ceyreklik)
  for (const d of ['2023-04-03', '2023-10-02', '2024-04-01', '2024-10-01', '2025-04-02', '2025-10-01', '2026-04-01']) list.push([d, ...TEMPLATES[3], d]);

  // normalize: [date, key, title, body, importance, eventDay]
  const items = list
    .map((r) => [norm(r[0]), r[1], r[2], r[3], r[4], r[5] ? norm(r[5]) : r[5]])
    .filter((r) => r[0] >= START && r[0] <= TODAY)
    .map((r) => {
      const [date, key, title, body, importance, ev] = r;
      return { date, title, body: body.replace('{gun}', ev ?? date), importance: importance ?? 'normal', key };
    })
    .sort((a, b) => a.date.localeCompare(b.date));
  // son gunlerde 3 guncel duyuru (okunmamis agirlikli)
  items.push(
    { date: addDays(TODAY, -4), title: 'Asansör Periyodik Kontrol Randevusu', body: 'Asansörlerin yıllık periyodik kontrolü gelecek hafta yapılacaktır. Tarih ve saat ayrıca duyurulacaktır.', importance: 'normal', key: 'recent', recent: true },
    { date: addDays(TODAY, -2), title: 'Ekim Ayı Aidat Hatırlatması', body: 'Ekim ayı aidatının son ödeme günü geçmiştir. Henüz ödeme yapmadıysanız en kısa sürede yatırmanızı rica ederiz.', importance: 'normal', key: 'recent', recent: true },
    { date: addDays(TODAY, -1), title: 'Çatı Temizliği ve Yağmur Oluğu Bakımı', body: 'Kış öncesi çatı ve yağmur oluğu temizliği yarın başlayacaktır. Çalışma gün içinde tamamlanacaktır.', importance: 'normal', key: 'recent', recent: true },
  );

  const residentPeople = people.filter((p) => p.role !== undefined);
  let announcementCount = 0;
  let recipientCount = 0;
  let readCount = 0;
  const withdrawnAt = items.length > 6 ? 5 : -1;
  for (const [idx, a] of items.entries()) {
    const publishedAt = `${a.date}T${String(rng.int(8, 18)).padStart(2, '0')}:${String(rng.int(0, 59)).padStart(2, '0')}:00+03:00`;
    const audience = residentPeople.filter((p) => p.moveIn <= a.date);
    const withdrawn = idx === withdrawnAt;
    const r = await q(
      `INSERT INTO announcements (site_code, title, body, importance, status, target_type, send_email, published_at, withdrawn_at, recipient_count, created_by, published_by, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, 'site', FALSE, $6::timestamptz, $7::timestamptz, $8, $9, $9, $6::timestamptz, $6::timestamptz) RETURNING id`,
      [siteCode, a.title, a.body, a.importance, withdrawn ? 'withdrawn' : 'published', publishedAt, withdrawn ? `${addDays(a.date, 1)}T09:00:00+03:00` : null, audience.length, manager.user_code],
    );
    const id = Number(r.rows[0].id);
    announcementCount += 1;
    for (const person of audience) {
      const readProb = a.recent ? 0.22 : person.age >= 62 ? 0.72 : 0.9;
      let readAt = null;
      if (rng.chance(readProb)) {
        const delayHours = Math.min(96, Math.round(-Math.log(1 - rng.next() * 0.98) * 14));
        const when = new Date(new Date(publishedAt).getTime() + (delayHours + 1) * 3600 * 1000);
        if (when.getTime() < Date.now() + 3 * 3600 * 1000) readAt = when.toISOString();
      }
      await q(`INSERT INTO announcement_recipients (announcement_id, person_id, email, email_hash, email_status, read_at) VALUES ($1, $2, NULL, NULL, 'none', $3::timestamptz)`, [id, person.personId, readAt]);
      recipientCount += 1;
      if (readAt) readCount += 1;
    }
  }
  return { announcementCount, recipientCount, readCount };
}
