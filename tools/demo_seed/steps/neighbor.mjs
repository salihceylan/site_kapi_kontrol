// Komsu Panosu (modul: neighbor_board): ~15 ilan; yayinda / onay bekleyen / reddedilen / kaldirilan.

import { addDays } from '../lib/util.mjs';

const POSTS = [
  ['Satılık çocuk bisikleti', 'Az kullanılmış 20 jant çocuk bisikleti, yanında kask hediye. Ücret için görüşelim.', 'published'],
  ['Matematik ve fizik dersi verilir', 'Lise ve ortaokul öğrencilerine evde birebir matematik ve fizik dersi verilir. Deneyimli, referans mevcut.', 'published'],
  ['Kayıp kedi: Pamuk', 'Beyaz tüylü, mavi gözlü kedimiz Pamuk 3 gündür kayıp. Gören olursa lütfen haber versin.', 'published'],
  ['Otopark takası', 'Zemin kattaki park yerimi bodrumdaki bir park yeri ile takas etmek istiyorum.', 'published'],
  ['Satılık yemek masası', '6 kişilik ahşap yemek masası, 2 yıllık, taşınma nedeniyle satılık.', 'published'],
  ['Köpek gezdirme hizmeti', 'Hafta içi akşamları ve hafta sonu köpeğinizi gezdirebilirim. Komşu fiyatı.', 'published'],
  ['İngilizce konuşma kulübü', 'Cumartesi sabahları toplantı salonunda ücretsiz İngilizce konuşma buluşması düzenlemek istiyoruz.', 'published'],
  ['Ücretsiz verilir: çocuk kitapları', 'Okuma yaşı 6-10 arası çocuk kitapları ücretsiz verilecektir. Kapı numarama ulaşabilirsiniz.', 'published'],
  ['Halı yıkama için ortak sipariş', 'Halı yıkamacı ile toplu anlaşma yapalım, 5 daire olursa indirim veriyorlar.', 'published'],
  ['Satılık ikinci el buzdolabı', 'No-frost buzdolabı, çalışır durumda. Fiyat sohbette.', 'pending'],
  ['Hafta sonu yürüyüş grubu', 'Pazar sabahları yakındaki parkta yürüyüş yapmak isteyen komşuları bekleriz.', 'pending'],
  ['Evden pasta ve kurabiye siparişi', 'Doğum günü ve özel günler için ev yapımı pasta siparişi alınır.', 'pending'],
  ['Reklam: indirimli klima servisi', 'Ücretli klima servisi için reklam metni (site içi ticari reklam).', 'rejected', 'Ticari reklam içeren ilanlar panoda yayınlanmaz.'],
  ['Komşu hakkında şikayet', 'Üst kat komşumuzla ilgili uzun bir şikayet metni.', 'rejected', 'Kişi hedef alan paylaşımlar panoda yayınlanamaz; yönetime başvurunuz.'],
  ['Satılık araba lastiği takımı', 'Kışlık lastik takımı, 2 mevsim kullanıldı.', 'removed', 'İlan sahibi isteğiyle yayından kaldırıldı.'],
];

export async function seedNeighbor(ctx) {
  const { q, rng, site, people, manager, TODAY, START } = ctx;
  const adults = people.filter((p) => p.age >= 18 && p.role !== 'landlord');
  let count = 0;
  for (const [i, [title, body, status, note]] of POSTS.entries()) {
    const author = adults[(i * 3 + 1) % adults.length];
    const base = i < 9 ? addDays(START, rng.int(150, 1300)) : addDays(TODAY, -rng.int(1, 9));
    const created = `${base > TODAY ? addDays(TODAY, -5) : base < author.moveIn ? author.moveIn : base}T${String(rng.int(9, 21)).padStart(2, '0')}:15:00+03:00`;
    const decided = status === 'pending' ? null : `${new Date(created).toISOString().slice(0, 10)}T20:00:00+03:00`;
    await q(
      `INSERT INTO neighbor_posts (site_code, author_user_code, title, body, status, decision_note, decided_by, decided_at, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::timestamptz, $9::timestamptz)`,
      [site.code, author.userCode, title, body, status, note ?? null, decided ? manager.user_code : null, decided, created],
    );
    count += 1;
  }
  return { count };
}
