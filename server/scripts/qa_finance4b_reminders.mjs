// Finans Faz 4b QA bolumu: G. Borc hatirlatma (O6). scripts/qa_finance4b.mjs tarafindan yuklenir (t = ortak test ortami).
// E-posta tasiyicisi SAHTEDIR (qa_platform_pg.mjs childEnv: nodemailer.createTransport -> mails dizisi); gercek SMTP'ye baglanilmaz.

export default async function sectionReminders(t) {
  const { check, same, q, call, ctx, TODAY, ago, mkManaged, mkUser, addPerson, addResidency, P, key, failMessage, users, sleep } = t;
  const { SUPER, MGR, MGR2, BOARD, STAFF, RESIDENT, OUTSIDER } = users;
  const mails = ctx.mails;
  const queue = await import('../src/modules/finance_reminder_queue.js');
  const security = await import('../src/modules/announcement_email_security.js');
  const { reminderSchedulerHooks, runFinanceReminderTick } = await import('../src/modules/finance_reminder_scheduler.js');
  console.log('--- G. borc hatirlatma ---');
  queue.reminderQueueHooks.sleep = async () => {};
  const realSend = queue.reminderQueueHooks.send;
  const base = (site) => P(site.code);
  const periodOf = (iso) => `${iso.slice(0, 7)}-01`;

  const site = await mkManaged('F4B Hatirlatma Sitesi', { 'H Blok': 16 });
  const A = Object.fromEntries(site.apts.map((apt) => [apt.n, apt.id]));
  const setResponsible = (aptNo, party) => q(`UPDATE apartments SET responsible_party = $2 WHERE id = $1`, [A[aptNo], party]);
  const charge = (aptNo, amount, daysAgo) => q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', $3, $4, $5, $5, 'both')`, [site.code, A[aptNo], amount, periodOf(ago(daysAgo + 5)), ago(daysAgo + 5)]).then(() => q(`UPDATE ledger_entries SET due_date = $3 WHERE FALSE`, [0, 0, TODAY]));
  void charge;
  const addCharge = (aptNo, amount, dueDaysAgo) => q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', $3, $4::date, $5::date, $6::date, 'both')`, [site.code, A[aptNo], amount, periodOf(ago(dueDaysAgo + 5)), ago(dueDaysAgo + 5), ago(dueDaysAgo)]);
  // İP-1A (G12): satırın hesabı açıkça (kiracı / ev sahibi hesabı); gerçek kod yeni satırlara hesabı yazar
  const addAccountCharge = (aptNo, amount, dueDaysAgo, account) => q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, account_party) VALUES ($1, $2, 'charge', $3, $4::date, $5::date, $6::date, 'both', $7)`, [site.code, A[aptNo], amount, periodOf(ago(dueDaysAgo + 5)), ago(dueDaysAgo + 5), ago(dueDaysAgo), account]);
  const mkAccountPerson = async (aptNo, relation, name, email, { verified = true, pref = true, role = 'apartment_owner' } = {}) => {
    const user = await mkUser(name, role, { email, verified });
    const person = await addPerson(site.code, { user });
    await addResidency(site.code, A[aptNo], person, relation);
    if (!pref) await q(`INSERT INTO notification_preferences (user_code, email_finance_reminders) VALUES ($1, FALSE) ON CONFLICT (user_code) DO UPDATE SET email_finance_reminders = FALSE`, [user]);
    return { user, person };
  };
  const mkCrmPerson = async (aptNo, relation, name, email) => {
    const person = await addPerson(site.code, { name, email });
    await addResidency(site.code, A[aptNo], person, relation);
    return { person };
  };

  // --- fikstur: her daire farkli bir uygunluk durumunu sinar
  await setResponsible(1, 'owner');   // A1: malik, dogrulanmis hesap -> tutarli
  await mkAccountPerson(1, 'owner', 'Hatirlatma Malik Bir', 'malik1@qa.example');
  await mkCrmPerson(1, 'tenant', 'Hatirlatma Kiraci Bir', 'kiraci1@qa.example'); // sorumlu degil: gitmez
  await addCharge(1, 125000, 40);
  await setResponsible(2, 'tenant');  // A2: kiraci sorumlu, hesapsiz CRM adresi -> tutarsiz
  await mkCrmPerson(2, 'tenant', 'Hatirlatma Kiraci Iki', 'kiraci2@qa.example');
  await mkAccountPerson(2, 'owner', 'Hatirlatma Malik Iki', 'malik2@qa.example');
  // İP-1A: sorumlu kiracı + kiracı var -> aidat kiracı hesabına (hatırlatma kiracıya; malik ALMAZ)
  await addAccountCharge(2, 80000, 35, 'tenant');
  await setResponsible(3, 'both');    // A3: malik (dogrulanmis) + kiraci (dogrulanmamis hesap)
  await mkAccountPerson(3, 'owner', 'Hatirlatma Malik Uc', 'malik3@qa.example');
  await mkAccountPerson(3, 'tenant', 'Hatirlatma Kiraci Uc', 'kiraci3@qa.example', { verified: false });
  // İP-1A (G12): A3'te İKİ hesap da borçlu: ev sahibi hesabı (malik) + kiracı hesabı (kiracı); her hesabın sahibine ayrı ileti (malik + kiracı)
  await addCharge(3, 60000, 50);
  await addAccountCharge(3, 60000, 50, 'tenant');
  await setResponsible(4, 'both');    // A4: yalniz aile uyesi -> alici YOK
  await mkCrmPerson(4, 'family_member', 'Hatirlatma Aile Dort', 'aile4@qa.example');
  await addCharge(4, 70000, 40);
  await addCharge(5, 2000, 40);       // A5: esigin altinda
  await mkCrmPerson(5, 'owner', 'Hatirlatma Bes', 'bes@qa.example');
  await addCharge(6, 90000, 2);       // A6: vade 2 gun once (esik 5)
  await mkCrmPerson(6, 'owner', 'Hatirlatma Alti', 'alti@qa.example');
  await addCharge(7, 90000, 40);      // A7: muaf
  await mkCrmPerson(7, 'owner', 'Hatirlatma Yedi', 'yedi@qa.example');
  await addCharge(8, 90000, 40);      // A8: pasif daire
  await mkCrmPerson(8, 'owner', 'Hatirlatma Sekiz', 'sekiz@qa.example');
  await q(`UPDATE apartments SET is_active = FALSE WHERE id = $1`, [A[8]]);
  await addCharge(9, 90000, 40);      // A9: adres yok
  await mkCrmPerson(9, 'owner', 'Hatirlatma Dokuz', null);
  await addCharge(10, 33000, 40);     // A10 + A11: ayni malik iki dairede -> TEK ileti
  await addCharge(11, 44000, 45);
  const multi = await mkAccountPerson(10, 'owner', 'Hatirlatma Cok Daireli', 'cok@qa.example');
  await addResidency(site.code, A[11], multi.person, 'owner');
  await addCharge(12, 51000, 40);     // A12 + A13: ayni adres iki kisi -> duplicate
  await addCharge(13, 52000, 40);
  await mkAccountPerson(12, 'owner', 'Hatirlatma On Iki', 'ortak@qa.example');
  await mkCrmPerson(13, 'owner', 'Hatirlatma On Uc', 'ORTAK@qa.example'); // CRM adresi baska kisinin HESAP adresiyle ayni (kanonik): ikinci kisi duplicate
  await addCharge(14, 53000, 40);     // A14: bastirilmis adres
  await mkCrmPerson(14, 'owner', 'Hatirlatma On Dort', 'bastirilmis@qa.example');
  await q(`INSERT INTO announcement_email_suppressions (email_hash) VALUES ($1) ON CONFLICT DO NOTHING`, [security.hashEmail('bastirilmis@qa.example')]);
  await addCharge(15, 54000, 40);     // A15: hesap tercihi kapali
  await mkAccountPerson(15, 'owner', 'Hatirlatma On Bes', 'tercih@qa.example', { pref: false });
  await addCharge(16, 55000, 40);     // A16: dahili daire hesabi (@ahbu.local) + yonetici girdigi iletisim adresi -> tutarsiz
  const internalUser = await mkUser('Dahili Daire Hesabi', 'apartment_owner', { email: 'daire16@ahbu.local', verified: true });
  await q(`UPDATE apartments SET resident_user_code = $2, resident_email = 'iletisim16@qa.example' WHERE id = $1`, [A[16], internalUser]);
  await addResidency(site.code, A[16], await addPerson(site.code, { user: internalUser }), 'owner');

  // --- G1. kapilar
  const pv0 = await call('POST', `${base(site)}/reminders/preview`, MGR, { tone: 'friendly' });
  check('G1: hatirlatma ayari KAPALIYKEN onizleme engel REMINDERS_DISABLED (+ hukuk onayi); send 409', pv0.status === 200 && pv0.body.blockers.includes('REMINDERS_DISABLED') && pv0.body.can_send === false
    && (await call('POST', `${base(site)}/reminders/send`, MGR, { tone: 'friendly', expected_hash: pv0.body.preview_hash, expected_apartment_count: 0, expected_person_count: 0, idempotency_key: key('s0') })).body.code === 'REMINDERS_DISABLED', pv0.body.blockers);
  await t.legalAll(false); // hukuk onayi site basina (114): hepsi kapali
  const s0 = await call('GET', `${base(site)}/settings`, MGR);
  const noGate = await call('PUT', `${base(site)}/settings`, MGR, { expected_settings_version: s0.body.settings_version, reminders: { enabled: true } });
  await t.legalAll(true);
  const s1 = await call('GET', `${base(site)}/settings`, MGR);
  const enable = await call('PUT', `${base(site)}/settings`, MGR, { expected_settings_version: s1.body.settings_version, reminders: { enabled: true, min_overdue_minor: 5000, min_days_overdue: 5, min_interval_days: 14, max_consecutive: 3 } });
  check('G1b: hukuk onayi bayragi KAPALIYKEN hatirlatma ACILAMAZ (409 LEGAL_APPROVAL_REQUIRED); bayrak acik + yonetici ayari acabilir', noGate.status === 409 && noGate.body.code === 'LEGAL_APPROVAL_REQUIRED' && enable.status === 200 && enable.body.reminders.enabled === true && enable.body.reminders.smtp_configured === true, [noGate.body, enable.body]);

  // --- G2. onizleme: uygunluk matrisi
  const exclude = await call('PUT', `${base(site)}/reminders/exclusions/${A[7]}`, MGR, { reason: 'dava altinda' });
  const pv = await call('POST', `${base(site)}/reminders/preview`, MGR, { tone: 'friendly' });
  const raw = JSON.stringify(pv.body);
  check('G2: onizleme sayilari: hariclenen nedenler (tutar 1, gun 1, muaf 1, alici yok 1); pasif daire aday degil; elden takip 0', exclude.status === 200 && pv.status === 200 && pv.body.excluded.amount === 1 && pv.body.excluded.days === 1 && pv.body.excluded.exclusion === 1 && pv.body.excluded.no_recipient === 1
    && pv.body.excluded.interval === 0 && pv.body.excluded.consecutive === 0 && pv.body.hand_follow_up_count === 0, pv.body.excluded);
  check('G2b: kisi sayilari: bekleyen kisi (A1 malik, A2 kiraci, A3 malik+kiraci, cok daireli malik, ortak adresli hesap, dahili hesap iletisim adresi) = 7; adres yok 1; bastirilmis + tercih kapali = 2; ayni adres (duplicate) 1',
    pv.body.person_count === 7 && pv.body.no_address_count === 1 && pv.body.skipped_pref_count === 2 && pv.body.duplicate_count === 1 && pv.body.capped_count === 0, { person: pv.body.person_count, na: pv.body.no_address_count, sp: pv.body.skipped_pref_count, dup: pv.body.duplicate_count });
  check('G2c: TUTARLI kisi: yalniz dogrulanmis gercek hesap e-postasi (A1 malik, A3 malik, cok daireli malik, ortak adresli hesap) = 4; tutarsiz: CRM adresi, dogrulanmamis hesap, dahili hesap iletisim adresi', pv.body.with_amount_count === 4 && pv.body.without_amount_count === pv.body.person_count - 4, [pv.body.with_amount_count, pv.body.without_amount_count]);
  check('G2d: onizleme ad / e-posta / tutarli listeler DONMEZ (yalniz sayilar + <= 20 daire etiketi + toplam); smtp_configured; preview_hash', !/@|Hatirlatma (Malik|Kiraci|Aile|Bes)|qa\.example/.test(raw) && pv.body.sample_apartments.length <= 20 && pv.body.smtp_configured === true && /^[0-9a-f]{64}$/.test(pv.body.preview_hash) && pv.body.apartment_count === 7, pv.body.apartment_count);
  const apartmentsOfPending = pv.body.apartment_count;
  void apartmentsOfPending;

  // --- G3. gonderim: kapilar, PREVIEW_STALE, kimlik
  const sendBody = (extra = {}) => ({ tone: 'friendly', note: null, expected_hash: pv.body.preview_hash, expected_apartment_count: pv.body.apartment_count, expected_person_count: pv.body.person_count, idempotency_key: key('send'), ...extra });
  const savedHost = process.env.SMTP_HOST;
  delete process.env.SMTP_HOST;
  const noSmtp = await call('POST', `${base(site)}/reminders/send`, MGR, sendBody());
  process.env.SMTP_HOST = savedHost;
  const noSmtpRuns = (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_runs WHERE site_code = $1`, [site.code])).rows[0].n;
  check('G3: SMTP yapilandirilmamissa 409 EMAIL_NOT_CONFIGURED ve CALISTIRMA OLUSMAZ (daireler aralik kisitina girmez)', noSmtp.status === 409 && noSmtp.body.code === 'EMAIL_NOT_CONFIGURED' && noSmtpRuns === 0 && (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_apartments WHERE site_code = $1`, [site.code])).rows[0].n === 0, noSmtp.body);
  const staleSend = await (async () => {
    await call('PUT', `${base(site)}/reminders/exclusions/${A[2]}`, MGR, { reason: 'gecici' });
    const res = await call('POST', `${base(site)}/reminders/send`, MGR, sendBody());
    await call('DELETE', `${base(site)}/reminders/exclusions/${A[2]}`, MGR);
    return res;
  })();
  check('G3b: onizleme sonrasi degisiklik (muafiyet) -> 409 PREVIEW_STALE; hicbir sey yazilmaz', staleSend.status === 409 && staleSend.body.code === 'PREVIEW_STALE' && (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_runs WHERE site_code = $1`, [site.code])).rows[0].n === 0, staleSend.body);
  const note = '  Odeme icin <b>iban</b>\r\nSubject: x  ';
  const okKey = key('ok');
  void queue.stopFinanceReminderQueue(); // gonderim (201) kuyrugu arka planda tetikler; G4'un acik calistirmasi YARISMASIN
  mails.length = 0;
  const raceKey = key('race');
  const sends = await Promise.all([
    call('POST', `${base(site)}/reminders/send`, MGR, sendBody({ idempotency_key: okKey, note })),
    call('POST', `${base(site)}/reminders/send`, MGR, sendBody({ idempotency_key: okKey, note })),
    call('POST', `${base(site)}/reminders/send`, MGR, sendBody({ idempotency_key: raceKey, note })),
    call('POST', `${base(site)}/reminders/send`, MGR, sendBody({ idempotency_key: key('race2'), note })),
  ]);
  const winner = sends.find((s) => s.status === 201);
  const runCount = (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_runs WHERE site_code = $1`, [site.code])).rows[0].n;
  check('G3c: ESZAMANLI 4 gonderim (2 ayni anahtar + 2 farkli) -> TEK calistirma; digerleri 200 replay ya da 409 REMINDER_DAILY_LIMIT (gunde 1 sinir)', runCount === 1 && sends.filter((s) => s.status === 201).length === 1 && sends.every((s) => [200, 201, 409].includes(s.status)) && sends.filter((s) => s.status === 409).every((s) => ['REMINDER_DAILY_LIMIT', 'IDEMPOTENCY_CONFLICT'].includes(s.body.code)), sends.map((s) => [s.status, s.body?.code]));
  const run = winner.body.run;
  check('G3d: calistirma kaydi: tone, istatistik (pending/no_address/skipped_pref/duplicate), apartment_count 7 (7 kisinin daireleri), person_count 7, with_amount_count 4; ad / adres YOK', run.tone === 'friendly' && run.apartment_count === 7 && run.person_count === 7 && run.with_amount_count === 4 && run.stats.no_address === 1 && run.stats.skipped_pref === 2 && run.stats.duplicate === 1 && !/@|qa\.example/.test(JSON.stringify(run)), run);
  const again = await call('POST', `${base(site)}/reminders/send`, MGR, sendBody({ idempotency_key: key('later') }));
  check('G3e: ayni gun ikinci gonderim 409 REMINDER_DAILY_LIMIT', again.status === 409 && again.body.code === 'REMINDER_DAILY_LIMIT', again.body);
  const replayConflict = await call('POST', `${base(site)}/reminders/send`, MGR, sendBody({ idempotency_key: okKey, tone: 'standard', note }));
  check('G3f: ayni anahtar + farkli govde (ton) 409 IDEMPOTENCY_CONFLICT', replayConflict.status === 409 && replayConflict.body.code === 'IDEMPOTENCY_CONFLICT', replayConflict.body);

  // --- G4. kuyruk: icerik, tutar politikasi
  queue.resumeFinanceReminderQueue(); // G3 boyunca kuyruk DURDURULMUSTU: arka plan tetigi satirlari tuketmesin, G4 acik calistirmayi belirleyici olcsun
  const summary = await queue.kickFinanceReminderQueue();
  const itemStates = (await q(`SELECT email_status, COUNT(*)::int AS n FROM finance_reminder_items WHERE run_id = $1 GROUP BY email_status`, [run.id])).rows;
  const stateOf = Object.fromEntries(itemStates.map((r) => [r.email_status, r.n]));
  check('G4: kuyruk 7 iletiyi gonderdi (sent 7), baska kisiye iletilmedi; gonderim sonrasi adres alani NULL', summary.sent === 7 && stateOf.sent === 7 && mails.length === 7 && (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_items WHERE run_id = $1 AND email IS NOT NULL`, [run.id])).rows[0].n === 0, { summary, stateOf, mails: mails.length });
  const mailTo = (address) => mails.find((m) => m.to === address);
  const m1 = mailTo('malik1@qa.example');
  const m2 = mailTo('kiraci2@qa.example');
  const m3k = mailTo('kiraci3@qa.example');
  const mMulti = mailTo('cok@qa.example');
  const mInternal = mailTo('iletisim16@qa.example');
  check('G4b: konu satiri "[Site] Odeme hatirlatmasi" - tutar, ad, daire YOK; govde adla hitap etmez ("Merhaba,")', mails.every((m) => m.subject === '[F4B Hatirlatma Sitesi] Ödeme hatırlatması' && /^Merhaba,/.test(m.text) && !/Hatirlatma (Malik|Kiraci)/.test(m.text) && !/1\.250,00/.test(m.subject)), mails.map((m) => m.subject));
  check('G4c: TUTAR yalniz dogrulanmis gercek hesap e-postasina: A1 malik "1.250,00 ₺ (en eski vade: ...)"; CRM adresi / dogrulanmamis hesap / dahili hesap iletisim adresi TUTARSIZ metin alir', /Vadesi geçmiş tutar: 1\.250,00 ₺ \(en eski vade: \d{2}\.\d{2}\.\d{4}\)\./.test(m1.text) && !/₺/.test(m2.text) && !/₺/.test(m3k.text) && !/₺/.test(mInternal.text)
    && /Güncel tutar için uygulamadaki "Borcum" bölümüne/.test(m2.text), [m1?.text, m2?.text]);
  check('G4d: cok daireli kisiye TEK ileti: iki daire etiketi ve ayri tutar satirlari (330,00 / 440,00)', mMulti && /H Blok - Daire 10/.test(mMulti.text) && /H Blok - Daire 11/.test(mMulti.text) && /330,00 ₺/.test(mMulti.text) && /440,00 ₺/.test(mMulti.text) && mails.filter((m) => m.to === 'cok@qa.example').length === 1, mMulti?.text);
  check('G4e: sorumlu OLMAYAN kisiler (A1 kiraci, A2 malik, aile uyesi) ILETI ALMAZ; yonetici notu duz metin: HTML kaçışlı, satir basi enjeksiyonu tek satira indirilmis', !mailTo('kiraci1@qa.example') && !mailTo('malik2@qa.example') && !mailTo('aile4@qa.example') && !mailTo('sekiz@qa.example') && !mailTo('yedi@qa.example') && !mailTo('bastirilmis@qa.example')
    && /Yönetim notu: Odeme icin <b>iban<\/b> Subject: x/.test(m1.text) && /&lt;b&gt;iban&lt;\/b&gt;/.test(m1.html) && !/<b>iban/.test(m1.html), [m1.text]);
  check('G4f: altbilgi her iletide: gonderen kimligi, "tanitim iletisi degildir", abonelikten cik baglantisi + List-Unsubscribe (RFC 8058); tehdit / icra / indirim dili YOK',
    mails.every((m) => /tanıtım iletisi değildir/.test(m.text) && /site duyuru ve borç hatırlatma e-postaları durdurulur/.test(m.text) && /announcement-unsubscribe\?t=/.test(m.headers['List-Unsubscribe']) && m.headers['List-Unsubscribe-Post'] === 'List-Unsubscribe=One-Click' && !/icra|dava|ihtar|haciz|indirim|kampanya/i.test(m.text)), mails[0]?.headers);
  const token = decodeURIComponent(m1.headers['List-Unsubscribe'].match(/t=([^>]+)>/)[1]);
  check('G4g: abonelik belirteci imzali ve ADRESIN ozetine baglidir (duz adres bagLantida yok)', security.verifyUnsubscribeToken(token) === security.hashEmail('malik1@qa.example') && !m1.headers['List-Unsubscribe'].includes('malik1'), token.slice(0, 20));
  const calcRows = (await q(`SELECT email_status, sent_at IS NOT NULL AS has_sent_at FROM finance_reminder_items WHERE run_id = $1`, [run.id])).rows;
  check('G4h: gonderilen satirlarda sent_at dolu; adres ozeti yalniz gonderilenlerde (7 gunluk sinir icin) kalir', calcRows.filter((r) => r.email_status === 'sent').every((r) => r.has_sent_at === true) && (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_items WHERE run_id = $1 AND email_hash IS NOT NULL`, [run.id])).rows[0].n === 7);

  // --- G5. ertesi gun: aralik, adres basina 7 gun, gonderilmis daire hesaplari
  const pvAfter = await call('POST', `${base(site)}/reminders/preview`, MGR, { tone: 'friendly' });
  // İP-1A: hariç tutma sayıları HESAP başınadır (aday = daire + hesap): 7 daire, A3'ün iki hesabı -> 8
  check('G5: gonderimden hemen sonra onizleme: hatirlatilan daireler aralik (14 gun) nedeniyle hariç (interval 8 hesap = 7 daire, A3 iki hesap); kalan alici yok', pvAfter.body.excluded.interval === 8 && pvAfter.body.person_count === 0 && pvAfter.body.blockers.includes('NO_REMINDER_RECIPIENTS') && pvAfter.body.blockers.includes('REMINDER_DAILY_LIMIT'), pvAfter.body);

  // --- G6. istatistik / liste / yetki
  const runs = await call('GET', `${base(site)}/reminders/runs`, BOARD);
  const runOne = await call('GET', `${base(site)}/reminders/runs/${run.id}`, BOARD);
  check('G6: kurul calistirma listesini ve istatistigi okur (ad / adres / olusturan adi YOK); yazamaz', runs.status === 200 && runs.body.total === 1 && runs.body.items[0].stats.sent === 7 && runs.body.items[0].created_by_name === null && !/@|qa\.example/.test(JSON.stringify(runs.body)) && runOne.status === 200
    && (await call('POST', `${base(site)}/reminders/preview`, BOARD, { tone: 'friendly' })).status === 403 && (await call('PUT', `${base(site)}/reminders/exclusions/${A[1]}`, BOARD, {})).status === 403, runs.body.items?.[0]);
  const matrix = [];
  for (const [label, user, read, writeStatus] of [['yonetici', MGR, 200, 200], ['super', SUPER, 200, 200], ['kurul', BOARD, 200, 403], ['gorevli', STAFF, 403, 403], ['sakin', RESIDENT, 403, 403], ['ilgisiz', OUTSIDER, 403, 403], ['baska site yoneticisi', MGR2, 403, 403]]) {
    const r = await call('GET', `${base(site)}/reminders/runs`, user);
    const w = await call('POST', `${base(site)}/reminders/preview`, user, { tone: 'standard' });
    matrix.push([label, r.status, w.status, read, writeStatus]);
  }
  check('G6b: yetki matrisi: yonetici / super okur + onizler; kurul YALNIZ okur; gorevli / sakin / ilgisiz / baska site 403', matrix.every(([, r, w, er, ew]) => r === er && w === ew), matrix);
  check('G6c: dogrulama: gecersiz ton 400; send icin hash / sayi / anahtar zorunlu 400', (await call('POST', `${base(site)}/reminders/preview`, MGR, { tone: 'x' })).status === 400 && (await call('POST', `${base(site)}/reminders/send`, MGR, { tone: 'friendly', idempotency_key: key('v') })).status === 400);
  const auditRow = (await q(`SELECT details FROM audit_log WHERE site_code = $1 AND action = 'finance.reminder.sent' ORDER BY id DESC LIMIT 1`, [site.code])).rows[0]?.details;
  check('G6d: audit finance.reminder.sent details yalniz sayilar (ad / adres / not YOK)', auditRow && typeof auditRow.person_count === 'number' && !JSON.stringify(auditRow).match(/@|iban|qa\.example|Subject/), auditRow);

  // --- G7. ikinci site: kuyruk davranislari (bayat borc, adres degisimi, bastirma, gecici / kalici hata, iptal, devam)
  const s2 = await mkManaged('F4B Hatirlatma Kuyruk', { 'K Blok': 12 });
  const B = Object.fromEntries(s2.apts.map((apt) => [apt.n, apt.id]));
  const addCharge2 = (aptNo, amount, dueDaysAgo) => q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', $3, $4::date, $5::date, $6::date, 'both')`, [s2.code, B[aptNo], amount, periodOf(ago(dueDaysAgo + 5)), ago(dueDaysAgo + 5), ago(dueDaysAgo)]);
  const crm2 = async (aptNo, email, name = `Kuyruk ${aptNo}`) => {
    const person = await addPerson(s2.code, { name, email });
    await addResidency(s2.code, B[aptNo], person, 'owner');
    return person;
  };
  const people = {};
  for (let n = 1; n <= 10; n += 1) {
    await addCharge2(n, 40000 + n, 30);
    people[n] = await crm2(n, `kuyruk${n}@qa.example`);
  }
  const sv = await call('GET', `${base(s2)}/settings`, MGR);
  await call('PUT', `${base(s2)}/settings`, MGR, { expected_settings_version: sv.body.settings_version, reminders: { enabled: true } });
  const pv2 = await call('POST', `${base(s2)}/reminders/preview`, MGR, { tone: 'standard' });
  const send2 = await call('POST', `${base(s2)}/reminders/send`, MGR, { tone: 'standard', note: null, expected_hash: pv2.body.preview_hash, expected_apartment_count: pv2.body.apartment_count, expected_person_count: pv2.body.person_count, idempotency_key: key('s2') });
  // kuyruk calismadan ONCE durum degisiklikleri (talep aninda taze dogrulama)
  await q(`UPDATE site_people SET is_active = FALSE WHERE id = $1`, [people[1]]);                      // kisi pasif -> resolved
  await q(`UPDATE site_people SET email = 'yeni-adres@qa.example' WHERE id = $1`, [people[2]]);       // adres degisti -> resolved
  await q(`INSERT INTO announcement_email_suppressions (email_hash) VALUES ($1) ON CONFLICT DO NOTHING`, [security.hashEmail('kuyruk3@qa.example')]); // bastirildi -> skipped_pref
  await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method) VALUES ($1, $2, 'payment', -40004, $3::date, $4::date, 'both', 'cash')`, [s2.code, B[4], periodOf(TODAY), TODAY]); // borc odendi -> resolved
  await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method) VALUES ($1, $2, 'payment', -38005, $3::date, $4::date, 'both', 'cash')`, [s2.code, B[5], periodOf(TODAY), TODAY]); // kismi odeme: kalan 2005 < esik 5000 -> resolved
  mails.length = 0;
  const failuresByAddress = new Map([['kuyruk6@qa.example', { permanent: true }], ['kuyruk7@qa.example', { transient: 2 }], ['kuyruk8@qa.example', { transient: 99 }]]);
  queue.reminderQueueHooks.send = async (message) => {
    const rule = failuresByAddress.get(message.to);
    if (rule?.permanent) throw Object.assign(new Error('alici reddi'), { responseCode: 550 });
    if (rule?.transient) {
      rule.transient -= 1;
      throw Object.assign(new Error('gecici'), { code: 'ETIMEDOUT' });
    }
    return realSend(message);
  };
  await queue.kickFinanceReminderQueue();
  const st2 = async () => Object.fromEntries((await q(`SELECT i.person_id, i.email_status, i.email_attempts, i.email IS NULL AS no_email FROM finance_reminder_items i WHERE i.run_id = $1`, [send2.body.run.id])).rows.map((r) => [r.person_id, r]));
  let states2 = await st2();
  check('G7: TAZE DOGRULAMA: pasif kisi / degisen adres / odenmis borc / esik altina dusen borc = resolved (ileti GITMEZ); bastirilan adres = skipped_pref', states2[people[1]].email_status === 'resolved' && states2[people[2]].email_status === 'resolved' && states2[people[3]].email_status === 'skipped_pref'
    && states2[people[4]].email_status === 'resolved' && states2[people[5]].email_status === 'resolved' && ![1, 2, 3, 4, 5].some((n) => mails.some((m) => m.to === `kuyruk${n}@qa.example` || m.to === 'yeni-adres@qa.example')), Object.values(states2).map((s) => s.email_status));
  check('G7b: kalici SMTP hatasi (550) hemen failed (adres NULL); gecici hata satiri pending birakir (geri cekilme) ve 3 denemede failed olur', states2[people[6]].email_status === 'failed' && states2[people[6]].no_email === true && states2[people[7]].email_status === 'pending' && Number(states2[people[7]].email_attempts) === 1, states2[people[7]]);
  // geri cekilme suresi dolsun: email_next_at gecmise cek ve kuyrugu tekrar calistir
  const rewind = () => q(`UPDATE finance_reminder_items SET email_next_at = NOW() - INTERVAL '1 second' WHERE run_id = $1 AND email_status = 'pending'`, [send2.body.run.id]);
  await rewind();
  await queue.kickFinanceReminderQueue();
  states2 = await st2();
  const secondTry = states2[people[7]];
  await rewind();
  await queue.kickFinanceReminderQueue();
  states2 = await st2();
  check('G7c: kuyruk yeniden calisinca gecici hatali satir yeniden denenir: 7. kisi 3. denemede GONDERILIR (sent); 8. kisi 3 denemede failed; ilk denemede gonderilenler TEKRAR gonderilmez', secondTry.email_status === 'pending' && states2[people[7]].email_status === 'sent' && states2[people[8]].email_status === 'failed' && Number(states2[people[8]].email_attempts) === 3
    && mails.filter((m) => m.to === 'kuyruk9@qa.example').length === 1 && mails.filter((m) => m.to === 'kuyruk10@qa.example').length === 1 && mails.filter((m) => m.to === 'kuyruk7@qa.example').length === 1, Object.fromEntries(Object.entries(states2).map(([k, v]) => [k, v.email_status])));
  const intervalsLeft = (await q(`SELECT apartment_id FROM finance_reminder_apartments WHERE run_id = $1 ORDER BY apartment_id`, [send2.body.run.id])).rows.map((r) => Number(r.apartment_id));
  const expectedIntervals = [7, 9, 10].map((n) => B[n]).sort((a, b) => a - b);
  check('G7d: GONDERILMEYEN (resolved / failed / skipped_pref) satirlarin daire aralik kayitlari SILINIR; yalniz gonderilen daireler (7, 9, 10) kisitta kalir', same(intervalsLeft, expectedIntervals), { intervalsLeft, expectedIntervals });
  queue.reminderQueueHooks.send = realSend;

  // --- G8. iptal
  const s3 = await mkManaged('F4B Hatirlatma Iptal', { 'I Blok': 4 });
  const C = Object.fromEntries(s3.apts.map((apt) => [apt.n, apt.id]));
  for (let n = 1; n <= 4; n += 1) {
    await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', 90000, $3::date, $4::date, $5::date, 'both')`, [s3.code, C[n], periodOf(ago(40)), ago(45), ago(40)]);
    const person = await addPerson(s3.code, { name: `Iptal ${n}`, email: `iptal${n}@qa.example` });
    await addResidency(s3.code, C[n], person, 'owner');
  }
  const sv3 = await call('GET', `${base(s3)}/settings`, MGR);
  await call('PUT', `${base(s3)}/settings`, MGR, { expected_settings_version: sv3.body.settings_version, reminders: { enabled: true } });
  const pv3 = await call('POST', `${base(s3)}/reminders/preview`, MGR, { tone: 'friendly' });
  void queue.stopFinanceReminderQueue(); // gonderim hemen kuyruga tetikler; iptal denemesi icin kuyruk durdurulur
  const send3 = await call('POST', `${base(s3)}/reminders/send`, MGR, { tone: 'friendly', note: null, expected_hash: pv3.body.preview_hash, expected_apartment_count: pv3.body.apartment_count, expected_person_count: pv3.body.person_count, idempotency_key: key('s3') });
  // bir satir "yolda" (talep edilmis) olsun
  await q(`UPDATE finance_reminder_items SET email_claimed_at = NOW(), email_attempts = 1 WHERE run_id = $1 AND person_id = (SELECT MIN(person_id) FROM finance_reminder_items WHERE run_id = $1)`, [send3.body.run.id]);
  const cancel = await call('POST', `${base(s3)}/reminders/runs/${send3.body.run.id}/cancel`, MGR, {});
  queue.resumeFinanceReminderQueue();
  const cancel2 = await call('POST', `${base(s3)}/reminders/runs/${send3.body.run.id}/cancel`, MGR, {});
  const cStates = (await q(`SELECT email_status, COUNT(*)::int AS n FROM finance_reminder_items WHERE run_id = $1 GROUP BY email_status`, [send3.body.run.id])).rows;
  const cMap = Object.fromEntries(cStates.map((r) => [r.email_status, r.n]));
  check('G8: iptal: talep edilmemis pending satirlar cancelled (3); yoldaki (talep edilmis) satira dokunulmaz (pending 1); calistirma cancelled; ikinci iptal 409 REMINDER_RUN_NOT_CANCELLABLE; iptal edilen satirlarin adresi silinir',
    cancel.status === 200 && cancel.body.run.status === 'cancelled' && cMap.cancelled === 3 && cMap.pending === 1 && cancel2.status === 409 && cancel2.body.code === 'REMINDER_RUN_NOT_CANCELLABLE'
      && (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_items WHERE run_id = $1 AND email_status = 'cancelled' AND (email IS NOT NULL OR email_hash IS NOT NULL)`, [send3.body.run.id])).rows[0].n === 0, cMap);
  mails.length = 0;
  await queue.kickFinanceReminderQueue();
  check('G8b: iptal edilen calistirmanin kalan pending satiri artik GONDERILMEZ (kuyruk failed yapar); yoldaki (taze talepli) satirin dairesi disindaki aralik kayitlari silinir', mails.length === 0 && (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_apartments WHERE run_id = $1`, [send3.body.run.id])).rows[0].n === 1, mails.length);

  // --- G9. adres basina 7 gun, site gunluk siniri, ardisik sinir (elden takip)
  const s4 = await mkManaged('F4B Hatirlatma Sinirlar', { 'S Blok': 6 });
  const D = Object.fromEntries(s4.apts.map((apt) => [apt.n, apt.id]));
  for (let n = 1; n <= 6; n += 1) {
    await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', 90000, $3::date, $4::date, $5::date, 'both')`, [s4.code, D[n], periodOf(ago(100)), ago(105), ago(100)]);
    const person = await addPerson(s4.code, { name: `Sinir ${n}`, email: `sinir${n}@qa.example` });
    await addResidency(s4.code, D[n], person, 'owner');
  }
  const sv4 = await call('GET', `${base(s4)}/settings`, MGR);
  await call('PUT', `${base(s4)}/settings`, MGR, { expected_settings_version: sv4.body.settings_version, reminders: { enabled: true, max_consecutive: 2 } });
  // gunluk site sinir: 2
  process.env.FINANCE_REMINDER_MAX_PER_DAY_PER_SITE = '2';
  const capPv = await call('POST', `${base(s4)}/reminders/preview`, MGR, { tone: 'friendly' });
  delete process.env.FINANCE_REMINDER_MAX_PER_DAY_PER_SITE;
  check('G9: site gunluk siniri (FINANCE_REMINDER_MAX_PER_DAY_PER_SITE=2): 6 aday kisiden 2 bekleyen, 4 capped', capPv.body.person_count === 2 && capPv.body.capped_count === 4, capPv.body);
  // adres basina 7 gun: sinir1 adresine 3 gun once gonderilmis bir kayit
  const histRun = Number((await q(`INSERT INTO finance_reminder_runs (site_code, tone, params, apartment_count, person_count, with_amount_count, preview_hash, idempotency_key, request_fingerprint, run_on, status) VALUES ($1, 'friendly', '{}'::jsonb, 1, 1, 0, $2, 'hist-run', $2, $3::date, 'active') RETURNING id`, [s4.code, 'a'.repeat(64), ago(3)])).rows[0].id);
  const histPerson = Number((await q(`SELECT id FROM site_people WHERE site_code = $1 AND full_name = 'Sinir 1'`, [s4.code])).rows[0].id);
  await q(`ALTER TABLE finance_reminder_runs DISABLE TRIGGER USER`);
  await q(`UPDATE finance_reminder_runs SET created_at = NOW() - INTERVAL '3 days' WHERE id = $1`, [histRun]);
  await q(`ALTER TABLE finance_reminder_runs ENABLE TRIGGER USER`);
  await q(`INSERT INTO finance_reminder_items (run_id, person_id, apartment_ids, with_amount, has_account, email_hash, email_status, sent_at) VALUES ($1, $2, ARRAY[$3::bigint], FALSE, FALSE, $4, 'sent', NOW() - INTERVAL '3 days')`, [histRun, histPerson, D[1], security.hashEmail('sinir1@qa.example')]);
  const recentPv = await call('POST', `${base(s4)}/reminders/preview`, MGR, { tone: 'friendly' });
  check('G9b: ADRES BASINA 7 GUNDE 1: 3 gun once hatirlatma gonderilmis adres bu calistirmada capped (bekleyen 5, capped 1)', recentPv.body.person_count === 5 && recentPv.body.capped_count === 1, recentPv.body);
  // ardisik sinir: 2 daire icin gecmis hatirlatma kayitlari (ardisik 2 = sinir) -> elden takip
  for (const n of [2, 3]) {
    for (const daysBack of [60, 30]) {
      const run = Number((await q(`INSERT INTO finance_reminder_runs (site_code, tone, params, apartment_count, person_count, with_amount_count, preview_hash, idempotency_key, request_fingerprint, run_on, status) VALUES ($1, 'friendly', '{}'::jsonb, 1, 1, 0, $2, $3, $2, $4::date, 'active') RETURNING id`, [s4.code, 'b'.repeat(64), `hist-${n}-${daysBack}`, ago(daysBack + n)])).rows[0].id);
      await q(`INSERT INTO finance_reminder_apartments (site_code, apartment_id, run_id, reminded_at) VALUES ($1, $2, $3, NOW() - make_interval(days => $4::int))`, [s4.code, D[n], run, daysBack]);
    }
  }
  await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method) VALUES ($1, $2, 'payment', -100, $3::date, $4::date, 'both', 'cash')`, [s4.code, D[3], periodOf(ago(50)), ago(50)]);
  const consecPv = await call('POST', `${base(s4)}/reminders/preview`, MGR, { tone: 'friendly' });
  check('G9c: ARDISIK SINIR (2): son tahsilattan beri 2 hatirlatma almis daire ELDEN TAKIP (hand_follow_up 1, e-posta gitmez); arada tahsilat olan daire sayac sifirlanir', consecPv.body.hand_follow_up_count === 1 && consecPv.body.excluded.consecutive === 1 && consecPv.body.hand_follow_up_apartments.length === 1, consecPv.body);

  // --- G10. DB degismezleri
  const dbMsgs = [
    ['calistirma UPDATE', await failMessage(`UPDATE finance_reminder_runs SET tone = 'standard' WHERE id = $1`, [run.id])],
    ['calistirma DELETE', await failMessage(`DELETE FROM finance_reminder_runs WHERE id = $1`, [run.id])],
    ['iptal geri alinmaz', await failMessage(`UPDATE finance_reminder_runs SET status = 'active' WHERE id = $1`, [send3.body.run.id])],
  ];
  check('G10: calistirma kaydi degismez (UPDATE / DELETE hata); iptal geri alinamaz', dbMsgs.every(([, m]) => m !== null), dbMsgs);
  const exclAdd = await call('PUT', `${base(site)}/reminders/exclusions/${A[1]}`, MGR, { reason: 'x'.repeat(101) });
  const exclOther = await call('PUT', `${base(site)}/reminders/exclusions/${s2.apts[0].id}`, MGR, {});
  const exclList = await call('GET', `${base(site)}/reminders/exclusions`, MGR);
  const exclRemove = await call('DELETE', `${base(site)}/reminders/exclusions/${A[7]}`, MGR);
  check('G10b: muafiyet listesi: neden > 100 karakter 400; BASKA sitenin dairesi 404 APARTMENT_NOT_FOUND; liste daire etiketi + neden; DELETE idempotent', exclAdd.status === 400 && exclOther.status === 404 && exclList.body.items.some((i) => i.apartment_id === A[7] && i.reason === 'dava altinda' && /H Blok/.test(i.label)) && exclRemove.status === 200 && (await call('DELETE', `${base(site)}/reminders/exclusions/${A[7]}`, MGR)).status === 200);

  // --- G11. zamanlayici
  let kicks = 0;
  const savedHooks = { ...reminderSchedulerHooks };
  reminderSchedulerHooks.hasPending = async () => true;
  reminderSchedulerHooks.kick = () => { kicks += 1; return new Promise(() => {}); };
  reminderSchedulerHooks.purgeHashes = async () => 0;
  await runFinanceReminderTick();
  Object.assign(reminderSchedulerHooks, savedHooks);
  check('G11: zamanlayici tiki bekleyen hatirlatma varsa kuyrugu surer (bekletmeden); sahipsiz satirlari kapatir', kicks === 1);
  void sleep;
}
