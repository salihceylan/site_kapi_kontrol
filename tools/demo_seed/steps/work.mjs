// Is Takibi (modul: work_tracking): ~60 ariza/bakim/sikayet talebi; durumlar, atamalar, olaylar. Fotograf eki YOK.

import { addDays, clampDay, dayNo, diffDays, isoOf } from '../lib/util.mjs';

const TOPICS = [
  { cat: 'ariza', loc: 'ortak_alan', title: 'Asansör arızası', desc: 'Asansör katlar arasında duruyor ve kapı geç açılıyor.', pri: 'acil', days: [1, 4] },
  { cat: 'ariza', loc: 'ortak_alan', title: 'Merdiven aydınlatması yanmıyor', desc: '3. kat merdiven sahanlığındaki lamba yanmıyor, akşamları karanlık.', pri: 'normal', days: [2, 9] },
  { cat: 'ariza', loc: 'ortak_alan', title: 'Bodrumda su kaçağı', desc: 'Bodrum katında boru bağlantısından su damlıyor, zemin ıslak.', pri: 'acil', days: [1, 3] },
  { cat: 'ariza', loc: 'ortak_alan', title: 'Giriş kapısı otomatik kapanmıyor', desc: 'Bina giriş kapısının kapı kolu gevşemiş, kapı kendiliğinden kapanmıyor.', pri: 'normal', days: [2, 8] },
  { cat: 'ariza', loc: 'daire', title: 'İnterkom çalışmıyor', desc: 'Daire içi interkom cihazından ses gelmiyor, zil çalıyor ama konuşulamıyor.', pri: 'normal', days: [2, 10] },
  { cat: 'ariza', loc: 'daire', title: 'Petek ısınmıyor', desc: 'Salondaki petek ısınmıyor, diğer odalar normal.', pri: 'normal', days: [2, 7] },
  { cat: 'bakim', loc: 'ortak_alan', title: 'Çatı oluk temizliği', desc: 'Yağmur öncesi çatı oluklarının temizlenmesi gerekiyor.', pri: 'dusuk', days: [5, 25] },
  { cat: 'bakim', loc: 'ortak_alan', title: 'Bahçe aydınlatma bakımı', desc: 'Bahçe yolundaki bazı armatürlerin lambaları değiştirilmeli.', pri: 'dusuk', days: [5, 20] },
  { cat: 'bakim', loc: 'ortak_alan', title: 'Hidrofor basınç kontrolü', desc: 'Üst katlarda su basıncı zaman zaman düşüyor, hidrofor kontrol edilsin.', pri: 'normal', days: [3, 14] },
  { cat: 'sikayet_oneri', loc: 'ortak_alan', title: 'Çöp konteyneri kokusu', desc: 'Çöp alanından yaz aylarında yoğun koku geliyor, temizlik sıklığı artırılabilir.', pri: 'normal', days: [3, 12] },
  { cat: 'sikayet_oneri', loc: 'daire', title: 'Gece geç saatte gürültü', desc: 'Üst daireden gece 23:00 sonrası ses ve ayak gürültüsü geliyor, uyarı rica ederim.', pri: 'normal', days: [2, 15] },
  { cat: 'sikayet_oneri', loc: 'ortak_alan', title: 'Otoparkta usulsüz park', desc: 'Yangın merdiveni önüne sürekli araç park ediliyor.', pri: 'normal', days: [2, 12] },
  { cat: 'diger', loc: 'ortak_alan', title: 'Bahçeye bank ve çocuk oyun alanı önerisi', desc: 'Bahçeye birkaç bank ve küçük bir oyun alanı eklenmesini öneriyorum.', pri: 'dusuk', days: [10, 40] },
];
const STAFF_COMMENTS = ['Teknik servis bilgilendirildi.', 'Parça siparişi verildi, geldiğinde değiştirilecek.', 'Yerinde inceleme yapıldı.', 'Firma ile görüşüldü, randevu alındı.', 'Geçici çözüm uygulandı.'];

export async function seedWork(ctx) {
  const { q, rng, site, apartments, people, peopleResult, manager, TODAY, START } = ctx;
  const siteCode = site.code;
  const techs = peopleResult.staff;
  const total = 60;
  const startN = dayNo(START);
  const endN = dayNo(TODAY);
  let count = 0;
  let eventCount = 0;
  const stats = {};
  for (let i = 0; i < total; i += 1) {
    const topic = TOPICS[(i * 5 + 3) % TOPICS.length];
    // tarih: ilk 45 talep gecmise yayili, son 15 talep son bir aya
    const createdDay = i < 45 ? isoOf(startN + Math.floor(((i + rng.next()) / 45) * (endN - startN - 45))) : addDays(TODAY, -rng.int(1, 28));
    const apt = topic.loc === 'daire' ? apartments[(i * 7 + 2) % apartments.length] : null;
    const members = apt ? peopleResult.peopleByApt.get(apt.id)?.filter((m) => m.age >= 18) ?? [] : [];
    const creator = apt ? members.find((m) => m.moveIn <= createdDay) : people.filter((p) => p.age >= 18 && p.moveIn <= createdDay)[i % Math.max(1, people.filter((p) => p.age >= 18 && p.moveIn <= createdDay).length)];
    const creatorUser = creator ? creator.userCode : manager.user_code;
    const creatorKind = creator ? 'resident' : 'manager';
    const hour = rng.int(8, 21);
    const createdAt = `${createdDay}T${String(hour).padStart(2, '0')}:${String(rng.int(0, 59)).padStart(2, '0')}:00+03:00`;
    const age = diffDays(TODAY, createdDay);
    const [dMin, dMax] = topic.days;
    const resolveDays = rng.int(dMin, dMax);
    let status;
    if (age > 45) status = rng.weighted([['kapandi', 80], ['cozuldu', 10], ['iptal', 5], ['kapandi', 5]]);
    else if (age > 14) status = rng.weighted([['kapandi', 35], ['cozuldu', 20], ['islemde', 25], ['beklemede', 20]]);
    else status = rng.weighted([['yeni', 35], ['islemde', 40], ['beklemede', 25]]);
    // cozum suresi gecmediyse acik kalir
    if ((status === 'kapandi' || status === 'cozuldu') && resolveDays > age) status = 'islemde';
    const assignee = status === 'yeni' ? null : techs[(i + (topic.cat === 'bakim' ? 1 : 0)) % techs.length]?.userCode ?? null;
    const resolvedAt = `${addDays(createdDay, resolveDays)}T${String(rng.int(9, 18)).padStart(2, '0')}:00:00+03:00`;
    const closedAt = status === 'kapandi' ? `${addDays(createdDay, resolveDays + 1)}T10:00:00+03:00` : status === 'iptal' ? `${addDays(createdDay, 1)}T11:00:00+03:00` : null;
    const updatedAt = closedAt ?? (status === 'cozuldu' ? resolvedAt : status === 'yeni' ? createdAt : `${addDays(createdDay, Math.min(age, rng.int(1, 4)))}T14:00:00+03:00`);
    const priority = topic.pri;
    const r = await q(
      `INSERT INTO work_items (site_code, category, location_type, title, description, apartment_id, block_id, status, priority, resident_urgent, assigned_to, due_date, created_by, created_at, updated_at, closed_at, requester_seen_at, resident_updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12::DATE, $13, $14::timestamptz, $15::timestamptz, $16::timestamptz, $15::timestamptz, $15::timestamptz) RETURNING id`,
      [
        siteCode, topic.cat, topic.loc, topic.title, topic.desc, apt ? apt.id : null, null, status, priority, priority === 'acil' && creatorKind === 'resident', assignee,
        priority === 'dusuk' ? addDays(createdDay, 21) : null, creatorUser, createdAt, updatedAt, closedAt,
      ],
    );
    const id = Number(r.rows[0].id);
    count += 1;
    stats[status] = (stats[status] ?? 0) + 1;
    const events = [{ type: 'created', kind: creatorKind, actor: creatorUser, vis: 'public', at: createdAt }];
    if (assignee) events.push({ type: 'assigned', kind: 'manager', actor: manager.user_code, vis: 'internal', at: `${createdDay}T${String(Math.min(23, hour + 1)).padStart(2, '0')}:30:00+03:00`, to: String(assignee) });
    if (status !== 'yeni') events.push({ type: 'status_changed', kind: 'staff', actor: assignee ?? manager.user_code, vis: 'public', at: `${addDays(createdDay, 0)}T${String(Math.min(23, hour + 2)).padStart(2, '0')}:10:00+03:00`, from: 'yeni', to: 'islemde' });
    if (status !== 'yeni' && rng.chance(0.6)) events.push({ type: 'comment', kind: 'staff', actor: assignee ?? manager.user_code, vis: 'public', at: `${addDays(createdDay, 1)}T10:20:00+03:00`, body: rng.pick(STAFF_COMMENTS) });
    if (status === 'beklemede') events.push({ type: 'status_changed', kind: 'manager', actor: manager.user_code, vis: 'public', at: updatedAt, from: 'islemde', to: 'beklemede' });
    if (status === 'cozuldu' || status === 'kapandi') events.push({ type: 'status_changed', kind: 'staff', actor: assignee ?? manager.user_code, vis: 'public', at: resolvedAt, from: 'islemde', to: 'cozuldu' });
    if (status === 'kapandi') events.push({ type: 'status_changed', kind: 'manager', actor: manager.user_code, vis: 'public', at: closedAt, from: 'cozuldu', to: 'kapandi' });
    if (status === 'iptal') events.push({ type: 'status_changed', kind: creatorKind, actor: creatorUser, vis: 'public', at: closedAt, from: 'yeni', to: 'iptal' });
    for (const e of events) {
      await q(
        `INSERT INTO work_item_events (work_item_id, site_code, event_type, visibility, actor_user_code, actor_kind, from_value, to_value, body, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::timestamptz)`,
        [id, siteCode, e.type, e.vis, e.actor, e.kind, e.from ?? null, e.to ?? null, e.body ?? null, e.at],
      );
      eventCount += 1;
    }
  }
  return { count, eventCount, stats, clampDay };
}
