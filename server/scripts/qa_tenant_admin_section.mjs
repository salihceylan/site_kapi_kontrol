// qa_platform_pg.mjs "tenant_admin" bolumu (Kiraci her zaman daire admini, migration 081; docs/PLATFORM_DAIRE_YONETIMI.md + docs/PLATFORM_FINANS_KASALAR.md bolum 7).
// GERCEK PostgreSQL. QA_ONLY=tenant_admin ile ayri kosulur (migration zinciri = ensure esitligi icin QA_ONLY=chain,live,tenant_admin). `npm test` ICINDE DEGILDIR.
//
// Kapsam:
//  A  migrations/081 dosyasi ve ensureTenantAdminRule ayni sonucu verir: guncel kiracisi olup admini malik (ya da baska) kalan daire kiraciya gecer;
//     adaylar disinda (hesapsiz kiraci, pasife alinmis uyelik, askida kisi, silinmis hesap, pasif daire, kiracisiz daire, zaten admin) HICBIR SEY degismez;
//     denetim kaydi (kisisel veri yok), adli kayit, devir, bildirim yazilir; kapi izinleri / uyelik satirlari / site uyelikleri DEGISMEZ; idempotans;
//     site yoneticisi devri korunur (acilis) ve yalniz yeni kiraci eklenirken ezilir; JS applyApartmentPrimaryAdmin ile PARITE.
//  B  calisma ani yollari (gercek servisler): malik kiraci ekler (hesapsiz -> hesap baglaninca; kayitli kisi -> davet kabulu), delegate_management:false yok sayilir,
//     site yoneticisi kisi karti / daire ekranindan kiraci ekler, iliski turunu kiraciya cevirir, kiraci cikinca admin malike doner (kiraci cikis, "Tasindi",
//     "Daireden cikar", "Sakini sil", pasife alma: onaylar B5, B10, B12-B14), kalan uye onceligi kiraci > malik > en eski aktif uye (B15-B16).
//  C  toplu yukleme: admin onceligi kiraci > malik > diger; mevcut malik admin iken sonradan eklenen kiraci admin olur; hesapsiz kiraci icin malik kalir.
//  D  eszamanli: ensureTenantIsAdmin x ensureTenantAdminRule x grantApartmentAccess (40P01 = 0, her daire icin tek denetim satiri, tek acik devir).

export async function sectionTenantAdmin(ctx) {
  const { check, same, childEnv, finishChild, installPoolHooks, serverErrors } = ctx;
  await childEnv();
  const { pool, ensureDbSchema } = await import('../src/db.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const fs = await import('node:fs');
  const path = await import('node:path');
  const { fileURLToPath } = await import('node:url');
  const here = path.dirname(fileURLToPath(import.meta.url));

  const sqlMod = await import('../src/modules/apartment_tenant_admin_sql.js');
  const { ensureTenantIsAdmin } = await import('../src/modules/apartment_tenant_admin.js');
  const mgmt = await import('../src/modules/apartment_mgmt_service.js');
  const people = await import('../src/modules/people_service.js');
  const core = await import('../src/modules/apartment_mgmt_core.js');
  const rules = await import('../src/modules/apartment_mgmt_rules.js');
  const bulk = await import('../src/modules/bulk_import_service.js');
  const { changeApartmentAdmin } = await import('../src/modules/apartment_mgmt_manager.js');
  const membership = await import('../src/services/membership_service.js');
  const successor = await import('../src/modules/apartment_admin_successor.js');

  await ensureDbSchema();

  // ---- fabrikalar
  let nextUser = 83000;
  const mkUser = async (name, { role = 'apartment_owner', active = true, email = null } = {}) => {
    nextUser += 1;
    await q(
      `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status)
       VALUES ($1, $2, $3, $4, 'x', $5, TRUE, 'approved')`,
      [nextUser, name, email ?? `tadm${nextUser}@qa.example`, role, active],
    );
    return nextUser;
  };
  const authOf = (code, role = 'apartment_owner') => ({ id: code, user_code: code, userCode: code, role, full_name: `QA ${code}`, email: `tadm${code}@qa.example` });
  let nextSite = 1000001300;
  const mkSite = async (name, count) => {
    nextSite += 1;
    const code = nextSite;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [code, name]);
    const blockId = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1) RETURNING id`, [code])).rows[0].id);
    const apts = [];
    for (let n = 1; n <= count; n += 1) {
      apts.push(Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [code, blockId, `Daire ${n}`, n])).rows[0].id));
    }
    return { code, apts, blockId };
  };
  const member = (apt, user, role = 'FAMILY_MEMBER', active = true) =>
    q(`INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active) VALUES ($1, $2, $3, $4)`, [apt, user, role, active]);
  const siteMember = (site, user) =>
    q(`INSERT INTO site_memberships (site_code, user_code, role, is_active) VALUES ($1, $2, 'RESIDENT', TRUE) ON CONFLICT DO NOTHING`, [site, user]);
  /** Hesapli ya da hesapsiz kisi + guncel iliski. */
  const person = async (site, { user = null, name = null, apt, relation, email = null }) => {
    const id = Number((await q(
      `INSERT INTO site_people (site_code, user_code, full_name, email) VALUES ($1, $2, $3, $4) RETURNING id`,
      [site, user, user === null ? name : null, user === null ? email : null],
    )).rows[0].id);
    await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, origin) VALUES ($1, $2, $3, $4, TRUE, 'manual')`, [site, apt, id, relation]);
    return id;
  };
  const rolesOf = async (apt) => {
    const rows = (await q(`SELECT user_code, role, is_active FROM apartment_memberships WHERE apartment_id = $1 ORDER BY user_code`, [apt])).rows;
    return Object.fromEntries(rows.map((r) => [Number(r.user_code), `${r.role}${r.is_active ? '' : '(pasif)'}`]));
  };
  const indicatorOf = async (apt) => (await q(`SELECT resident_user_code, resident_email, resident_pin_issued FROM apartments WHERE id = $1`, [apt])).rows[0];
  const adminCodes = async (apt) =>
    (await q(`SELECT user_code FROM apartment_memberships WHERE apartment_id = $1 AND role = 'APARTMENT_ADMIN' AND is_active = TRUE ORDER BY user_code`, [apt])).rows.map((r) => Number(r.user_code));
  const auditRows = (apt) => q(`SELECT * FROM audit_log WHERE action = 'apartment.admin_tenant_enforced' AND target_id = $1 ORDER BY id`, [String(apt)]).then((r) => r.rows);
  const openDelegation = async (apt) => (await q(`SELECT * FROM apartment_admin_delegations WHERE apartment_id = $1 AND ended_at IS NULL`, [apt])).rows[0] ?? null;
  const countOf = async (sql, params = []) => Number((await q(sql, params)).rows[0].n);
  const failCode = async (promise) => { try { await promise; return null; } catch (error) { return error.code ?? String(error.message); } };
  const migrationText = fs.readFileSync(path.resolve(here, '..', 'migrations', '081_tenant_is_apartment_admin.sql'), 'utf8');

  // ============================================================================================================
  // A: migrations/081 (= acilis adimi) gercek PostgreSQL'de
  const S = await mkSite('TADM Gul Sitesi', 30);
  const A = S.apts;
  const MGR = await mkUser('TADM Yonetici', { role: 'site_manager' });
  await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [S.code, MGR]);
  const doorId = Number((await q(`INSERT INTO site_doors (site_code, door_name, door_index) VALUES ($1, 'Ana Kapi', 1) RETURNING id`, [S.code])).rows[0].id);

  // a1: malik admin + gosterge malikte (PIN verildi, iletisim e-postasi) + kiraci (FAMILY_MEMBER) + kiracinin aile uyesi
  const o1 = await mkUser('Malik Bir');
  const t1 = await mkUser('Kiraci Bir');
  const f1 = await mkUser('Kiraci Aile Bir');
  await member(A[0], o1, 'APARTMENT_ADMIN');
  await member(A[0], t1, 'FAMILY_MEMBER');
  await member(A[0], f1, 'FAMILY_MEMBER');
  for (const u of [o1, t1, f1]) await siteMember(S.code, u);
  await q(`UPDATE apartments SET resident_user_code = $2, resident_email = 'malik@qa.example', resident_pin_issued = TRUE WHERE id = $1`, [A[0], o1]);
  const pO1 = await person(S.code, { user: o1, apt: A[0], relation: 'owner' });
  const pT1 = await person(S.code, { user: t1, apt: A[0], relation: 'tenant' });
  await person(S.code, { user: f1, apt: A[0], relation: 'family_member' });
  await q(`INSERT INTO door_access_overrides (site_code, door_id, user_code, is_allowed) VALUES ($1, $2, $3, TRUE), ($1, $2, $4, TRUE)`, [S.code, doorId, o1, t1]);
  await q(`INSERT INTO apartment_admin_delegations (site_code, apartment_id, owner_person_id, admin_person_id, admin_user_code, source, state) VALUES ($1, $2, $3, $4, $5, 'tenant_delegated', 'active')`, [S.code, A[0], pO1, pT1, t1]);

  // a2: hesapsiz kiraci (admin malik kalir)
  const o2 = await mkUser('Malik Iki');
  await member(A[1], o2, 'APARTMENT_ADMIN');
  await q(`UPDATE apartments SET resident_user_code = $2 WHERE id = $1`, [A[1], o2]);
  await person(S.code, { user: o2, apt: A[1], relation: 'owner' });
  await person(S.code, { name: 'Hesapsiz Kiraci', apt: A[1], relation: 'tenant' });
  // a3: kiraci zaten admin
  const o3 = await mkUser('Malik Uc');
  const t3 = await mkUser('Kiraci Uc');
  await member(A[2], o3, 'FAMILY_MEMBER');
  await member(A[2], t3, 'APARTMENT_ADMIN');
  await q(`UPDATE apartments SET resident_user_code = $2 WHERE id = $1`, [A[2], t3]);
  await person(S.code, { user: o3, apt: A[2], relation: 'owner' });
  await person(S.code, { user: t3, apt: A[2], relation: 'tenant' });
  // a4: kiracinin uyeligi PASIF (pasife alinmis): admin degismez
  const o4 = await mkUser('Malik Dort');
  const t4 = await mkUser('Kiraci Dort');
  await member(A[3], o4, 'APARTMENT_ADMIN');
  await member(A[3], t4, 'FAMILY_MEMBER', false);
  await person(S.code, { user: o4, apt: A[3], relation: 'owner' });
  await person(S.code, { user: t4, apt: A[3], relation: 'tenant' });
  // a5: kiraci kapi erisimi ASKIDA
  const o5 = await mkUser('Malik Bes');
  const t5 = await mkUser('Kiraci Bes');
  await member(A[4], o5, 'APARTMENT_ADMIN');
  await member(A[4], t5, 'FAMILY_MEMBER');
  await person(S.code, { user: o5, apt: A[4], relation: 'owner' });
  await person(S.code, { user: t5, apt: A[4], relation: 'tenant' });
  await q(`INSERT INTO apartment_access_suspensions (site_code, apartment_id, user_code, reason_code, note) VALUES ($1, $2, $3, 'safety', 'QA')`, [S.code, A[4], t5]);
  // a6: site yoneticisi "Daire adminini degistir" karari (manager): malik admin olarak SECILMIS
  const o6 = await mkUser('Malik Alti');
  const t6 = await mkUser('Kiraci Alti');
  await member(A[5], o6, 'APARTMENT_ADMIN');
  await member(A[5], t6, 'FAMILY_MEMBER');
  const pO6 = await person(S.code, { user: o6, apt: A[5], relation: 'owner' });
  await person(S.code, { user: t6, apt: A[5], relation: 'tenant' });
  await q(`INSERT INTO apartment_admin_delegations (site_code, apartment_id, owner_person_id, admin_person_id, admin_user_code, source, state) VALUES ($1, $2, $3, $4, $5, 'manager', 'active')`, [S.code, A[5], pO6, pO6, o6]);
  // a7: kiraci admin AMA ikinci bir admin satiri da var (tutarsiz): ikincisi FAMILY_MEMBER olur
  const o7 = await mkUser('Malik Yedi');
  const t7 = await mkUser('Kiraci Yedi');
  await member(A[6], o7, 'APARTMENT_ADMIN');
  await member(A[6], t7, 'APARTMENT_ADMIN');
  await person(S.code, { user: o7, apt: A[6], relation: 'owner' });
  await person(S.code, { user: t7, apt: A[6], relation: 'tenant' });
  // a8: kiracisiz daire (malik admin kalir)
  const o8 = await mkUser('Malik Sekiz');
  await member(A[7], o8, 'APARTMENT_ADMIN');
  await person(S.code, { user: o8, apt: A[7], relation: 'owner' });
  // a9: PASIF daire
  const o9 = await mkUser('Malik Dokuz');
  const t9 = await mkUser('Kiraci Dokuz');
  await member(A[8], o9, 'APARTMENT_ADMIN');
  await member(A[8], t9, 'FAMILY_MEMBER');
  await person(S.code, { user: o9, apt: A[8], relation: 'owner' });
  await person(S.code, { user: t9, apt: A[8], relation: 'tenant' });
  await q(`UPDATE apartments SET is_active = FALSE WHERE id = $1`, [A[8]]);
  // a10: kiracinin hesabi silinmis (deleted_at)
  const o10 = await mkUser('Malik On');
  const t10 = await mkUser('Kiraci On');
  await member(A[9], o10, 'APARTMENT_ADMIN');
  await member(A[9], t10, 'FAMILY_MEMBER');
  await person(S.code, { user: o10, apt: A[9], relation: 'owner' });
  await person(S.code, { user: t10, apt: A[9], relation: 'tenant' });
  await q(`UPDATE users SET deleted_at = NOW(), is_active = FALSE WHERE user_code = $1`, [t10]);
  // a11: malik kaydi YOK, yalniz kiraci (admin baska bir uye: aile) -> kiraci admin olur
  const t11 = await mkUser('Kiraci OnBir');
  const x11 = await mkUser('Eski Admin OnBir');
  await member(A[10], x11, 'APARTMENT_ADMIN');
  await member(A[10], t11, 'FAMILY_MEMBER');
  await person(S.code, { user: t11, apt: A[10], relation: 'tenant' });
  // a12: JS parite ikizi (a1 ile ayni durum; JS yolu applyApartmentPrimaryAdmin ile uygulanir)
  const o12 = await mkUser('Malik Parite');
  const t12 = await mkUser('Kiraci Parite');
  const f12 = await mkUser('Aile Parite');
  await member(A[11], o12, 'APARTMENT_ADMIN');
  await member(A[11], t12, 'FAMILY_MEMBER');
  await member(A[11], f12, 'FAMILY_MEMBER');
  for (const u of [o12, t12, f12]) await siteMember(S.code, u);
  await q(`UPDATE apartments SET resident_user_code = $2, resident_email = 'malik@qa.example', resident_pin_issued = TRUE WHERE id = $1`, [A[11], o12]);
  await person(S.code, { user: o12, apt: A[11], relation: 'owner' });
  await person(S.code, { user: t12, apt: A[11], relation: 'tenant' });
  await person(S.code, { user: f12, apt: A[11], relation: 'family_member' });

  const snapshotCounts = async () => ({
    memberships: await countOf(`SELECT COUNT(*)::int AS n FROM apartment_memberships WHERE apartment_id = ANY($1::BIGINT[])`, [A]),
    activeFlags: (await q(`SELECT COALESCE(string_agg(apartment_id || ':' || user_code || ':' || is_active::text, ',' ORDER BY apartment_id, user_code), '') AS s FROM apartment_memberships WHERE apartment_id = ANY($1::BIGINT[])`, [A])).rows[0].s,
    siteMemberships: await countOf(`SELECT COUNT(*)::int AS n FROM site_memberships WHERE site_code = $1`, [S.code]),
    overrides: (await q(`SELECT COALESCE(string_agg(user_code || ':' || is_allowed::text, ',' ORDER BY user_code), '') AS s FROM door_access_overrides WHERE site_code = $1`, [S.code])).rows[0].s,
  });
  const before = await snapshotCounts();
  const residencyLogBefore = await countOf(`SELECT COUNT(*)::int AS n FROM apartment_residency_log WHERE site_code = $1 AND event_type = 'admin_changed'`, [S.code]);

  // 081 dosyasi aynen calistirilir (migrate.js ile ayni: tek basit sorgu, ortuk islem)
  const run1 = await q(migrationText);
  const afterFirst = await snapshotCounts();
  check('A1: migrations/081 dosyasi gercek PG\'de hatasiz calisir; ifade sayisi = TENANT_ADMIN_STATEMENTS', Array.isArray(run1) && run1.length === sqlMod.TENANT_ADMIN_STATEMENTS.length, Array.isArray(run1) ? run1.length : typeof run1);
  const changedApts = (await q(`SELECT DISTINCT target_id FROM audit_log WHERE action = 'apartment.admin_tenant_enforced' AND site_code = $1 ORDER BY target_id`, [S.code])).rows.map((r) => Number(r.target_id));
  check('A2: degisen daireler YALNIZ a1, a7, a11, a12 ; a2/a3/a4/a5/a6/a8/a9/a10 DEGISMEZ (hesapsiz, zaten admin, pasif uyelik, askida, site yoneticisi karari, kiracisiz, pasif daire, silinmis hesap)',
    same(changedApts.sort((a, b) => a - b), [A[0], A[6], A[10], A[11]].sort((a, b) => a - b)), { changedApts, expected: [A[0], A[6], A[10], A[11]] });
  check('A3: a1: kiraci APARTMENT_ADMIN, malik ve kiracinin ailesi FAMILY_MEMBER; gosterge kiraciya, malikin iletisim e-postasi ve PIN verildi isareti temizlendi',
    same(await rolesOf(A[0]), { [o1]: 'FAMILY_MEMBER', [t1]: 'APARTMENT_ADMIN', [f1]: 'FAMILY_MEMBER' })
      && same(await indicatorOf(A[0]), { resident_user_code: t1, resident_email: null, resident_pin_issued: false }), { roles: await rolesOf(A[0]), ind: await indicatorOf(A[0]) });
  check('A4: kiraci hesapsiz (a2), zaten admin (a3), pasif uyelik (a4), askida (a5), kiracisiz (a8): roller aynen',
    same(await rolesOf(A[1]), { [o2]: 'APARTMENT_ADMIN' }) && same(await rolesOf(A[2]), { [o3]: 'FAMILY_MEMBER', [t3]: 'APARTMENT_ADMIN' })
      && same(await rolesOf(A[3]), { [o4]: 'APARTMENT_ADMIN', [t4]: 'FAMILY_MEMBER(pasif)' }) && same(await rolesOf(A[4]), { [o5]: 'APARTMENT_ADMIN', [t5]: 'FAMILY_MEMBER' })
      && same(await rolesOf(A[7]), { [o8]: 'APARTMENT_ADMIN' }), null);
  check('A5: pasif daire (a9) ve silinmis hesaplı kiraci (a10) aynen',
    same(await rolesOf(A[8]), { [o9]: 'APARTMENT_ADMIN', [t9]: 'FAMILY_MEMBER' }) && same(await rolesOf(A[9]), { [o10]: 'APARTMENT_ADMIN', [t10]: 'FAMILY_MEMBER' }), null);
  check('A6: site yoneticisi karari (a6, source manager) KORUNUR: malik admin kalir, devir satiri acik',
    same(await rolesOf(A[5]), { [o6]: 'APARTMENT_ADMIN', [t6]: 'FAMILY_MEMBER' }) && (await openDelegation(A[5]))?.source === 'manager', await rolesOf(A[5]));
  check('A7: tutarsiz iki admin (a7): yalniz kiraci admin; kiracisi olan ama admini baska uye olan daire (a11): kiraci admin, eski admin FAMILY_MEMBER',
    same(await rolesOf(A[6]), { [o7]: 'FAMILY_MEMBER', [t7]: 'APARTMENT_ADMIN' }) && same(await rolesOf(A[10]), { [x11]: 'FAMILY_MEMBER', [t11]: 'APARTMENT_ADMIN' }), { a7: await rolesOf(A[6]), a11: await rolesOf(A[10]) });
  check('A8: KAPI / UYELIK DEGISMEZ: uyelik satiri sayisi, her uyenin is_active bayragi, site uyelikleri ve kapi izinleri (door_access_overrides) birebir ayni',
    same(before, afterFirst), { before, afterFirst });
  const dl = await openDelegation(A[0]);
  const oldDl = (await q(`SELECT state, end_reason FROM apartment_admin_delegations WHERE apartment_id = $1 AND ended_at IS NOT NULL`, [A[0]])).rows;
  check('A9: a1: onceki acik devir "replaced" ile kapandi; kiraci icin tek acik tenant_delegated/active devir (admin_user_code = kiraci, owner_person_id = malik kaydi)',
    dl?.source === 'tenant_delegated' && dl.state === 'active' && Number(dl.admin_user_code) === t1 && Number(dl.admin_person_id) === pT1 && Number(dl.owner_person_id) === pO1
      && oldDl.length === 1 && oldDl[0].end_reason === 'replaced', { dl, oldDl });
  const aud = await auditRows(A[0]);
  const audText = JSON.stringify(aud);
  check('A10: a1 denetim kaydi: tek satir, eylem apartment.admin_tenant_enforced, hedef daire, aktor Sistem/system, ayrintida yalniz kimlikler ve yol etiketi (ad / e-posta / telefon YOK)',
    aud.length === 1 && aud[0].actor_name === 'Sistem' && aud[0].actor_role === 'system' && aud[0].actor_user_code === null && Number(aud[0].site_code) === S.code
      && aud[0].target_type === 'apartment' && aud[0].details.via === 'backfill' && Number(aud[0].details.to_user_code) === t1 && Number(aud[0].details.from_user_code) === o1
      && !/Kiraci|Malik|qa\.example|@/.test(audText.replace(/"actor_name":"Sistem"/, '')), aud);
  const log = (await q(`SELECT * FROM apartment_residency_log WHERE apartment_id = $1 AND event_type = 'admin_changed'`, [A[0]])).rows;
  check('A11: adli kayit (apartment_residency_log): admin_changed/handover, ozne kiraci (ad, kiraci iliskisi, kisi ve kullanici kodu), related from/to; iletisim bilgisi yok',
    log.length === 1 && log[0].reason_code === 'handover' && log[0].subject_name === 'Kiraci Bir' && log[0].subject_relation === 'tenant' && Number(log[0].subject_user_code) === t1
      && Number(log[0].subject_person_id) === pT1 && log[0].actor_role === 'system' && log[0].apartment_label === 'A Blok - Daire 1'
      && Number(log[0].related.to_user_code) === t1 && Number(log[0].related.from_user_code) === o1, log);
  const notices = (await q(`SELECT user_code, kind, message FROM apartment_notices WHERE apartment_id = $1 ORDER BY user_code`, [A[0]])).rows;
  check('A12: uygulama ici bildirim: yeni admin kiraciya ve onceki admin malike (admin_tenant_enforced, kisisel veri yok, <= 300 karakter)',
    same(notices.map((n) => [Number(n.user_code), n.kind]), [[o1, 'admin_tenant_enforced'], [t1, 'admin_tenant_enforced']]) && notices.every((n) => n.message.length <= 300 && !/Kiraci|Malik/.test(n.message)), notices);

  // idempotans: ikinci calistirma hicbir sey yazmaz; acilis adimi 0 doner
  const auditTotal = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'apartment.admin_tenant_enforced' AND site_code = $1`, [S.code]);
  const run2 = await q(migrationText);
  const startup = await sqlMod.ensureTenantAdminRule(pool);
  const auditTotal2 = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'apartment.admin_tenant_enforced' AND site_code = $1`, [S.code]);
  check('A13: IDEMPOTANS: ikinci calistirma 0 satir yazar (denetim sayisi ayni), ensureTenantAdminRule 0 doner ve yalniz bir okuma yapar',
    Array.isArray(run2) && run2[0].rowCount === 0 && auditTotal === 4 && auditTotal2 === 4 && startup === 0, { auditTotal, auditTotal2, startup, first: run2[0]?.rowCount });
  const resLogAfter = await countOf(`SELECT COUNT(*)::int AS n FROM apartment_residency_log WHERE site_code = $1 AND event_type = 'admin_changed'`, [S.code]);
  check('A14: adli kayda tam 4 admin_changed satiri eklendi (her degisen daire icin bir)', resLogAfter - residencyLogBefore === 4, { residencyLogBefore, resLogAfter });

  // a1 ve a12 ayni baslangic durumundan SQL ile cevrildi: nihai durum sekli ayni olmali (kullanici kodlari farkli oldugu icin sekil karsilastirilir)
  {
    const shapeOf = async (apt, tenantUser) => ({ roles: Object.values(await rolesOf(apt)).sort(), ind: await indicatorOf(apt).then((i) => ({ indicatorIsTenant: i.resident_user_code === tenantUser, email: i.resident_email, pin: i.resident_pin_issued })) });
    check('A15: a1 ve a12 (ayni baslangic, ayni SQL) ayni nihai sekil: roller, gosterge kiracida, e-posta ve PIN isareti temizlendi', same(await shapeOf(A[0], t1), await shapeOf(A[11], t12)), { a1: await shapeOf(A[0], t1), a12: await shapeOf(A[11], t12) });
  }
  // JS yolunun ayni baslangic durumundan urettigi sonuc: temiz bir ikiz daire uzerinde karsilastirilir
  {
    const o13 = await mkUser('Malik Parite JS');
    const t13 = await mkUser('Kiraci Parite JS');
    const f13 = await mkUser('Aile Parite JS');
    const extra = await mkSite('TADM Parite Sitesi', 2);
    const [pa, pb] = extra.apts;
    for (const [apt, o, t, f] of [[pa, o13, t13, f13], [pb, await mkUser('Malik Parite SQL'), await mkUser('Kiraci Parite SQL'), await mkUser('Aile Parite SQL')]]) {
      await member(apt, o, 'APARTMENT_ADMIN');
      await member(apt, t, 'FAMILY_MEMBER');
      await member(apt, f, 'FAMILY_MEMBER');
      await q(`UPDATE apartments SET resident_user_code = $2, resident_email = 'malik@qa.example', resident_pin_issued = TRUE WHERE id = $1`, [apt, o]);
      await person(extra.code, { user: o, apt, relation: 'owner' });
      await person(extra.code, { user: t, apt, relation: 'tenant' });
      await person(extra.code, { user: f, apt, relation: 'family_member' });
    }
    const tenantOf = async (apt) => Number((await q(`SELECT sp.user_code FROM apartment_residencies r JOIN site_people sp ON sp.id = r.person_id WHERE r.apartment_id = $1 AND r.relation = 'tenant'`, [apt])).rows[0].user_code);
    // JS: pa
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [pa]);
      await core.transferApartmentAdmin(client, { apartmentId: pa, userCode: await tenantOf(pa), reasonCode: 'handover' });
      await client.query('COMMIT');
    } finally {
      client.release();
    }
    // SQL: yalniz pb (kapsamli calisma ani yolu)
    const c2 = await pool.connect();
    let ensured;
    try {
      await c2.query('BEGIN');
      ensured = await ensureTenantIsAdmin(c2, { apartmentIds: [pb], via: 'qa_parity' });
      await c2.query('COMMIT');
    } finally {
      c2.release();
    }
    const shape = async (apt) => {
      const rows = (await q(`SELECT role, is_active, (user_code = (SELECT resident_user_code FROM apartments WHERE id = $1)) AS is_indicator FROM apartment_memberships WHERE apartment_id = $1 ORDER BY user_code`, [apt])).rows;
      const ind = await indicatorOf(apt);
      const log2 = (await q(`SELECT event_type, reason_code, subject_relation, jsonb_object_keys(related) AS k FROM apartment_residency_log WHERE apartment_id = $1 AND event_type = 'admin_changed' ORDER BY k`, [apt])).rows;
      return { rows, email: ind.resident_email, pin: ind.resident_pin_issued, log: log2.map((r) => [r.event_type, r.reason_code, r.subject_relation, r.k]) };
    };
    const jsShape = await shape(pa);
    const sqlShape = await shape(pb);
    check('A16: PARITE (ikiz daire, ayni baslangic): JS transferApartmentAdmin ile SQL ensureTenantIsAdmin ayni roller, ayni gosterge sahibi, ayni temizlenen alanlar, ayni adli kayit sekli',
      ensured.changed === 1 && same(jsShape, sqlShape), { jsShape, sqlShape });
  }

  // runtime: site yoneticisi karari yalniz yeni kiraci eklenirken ezilir (overrideManager); aksi halde korunur
  {
    const client = await pool.connect();
    let kept; let overridden;
    try {
      await client.query('BEGIN');
      kept = await ensureTenantIsAdmin(client, { apartmentIds: [A[5]], via: 'qa' });
      await client.query('COMMIT');
      await client.query('BEGIN');
      overridden = await ensureTenantIsAdmin(client, { apartmentIds: [A[5]], overrideManager: true, via: 'qa_new_tenant' });
      await client.query('COMMIT');
    } finally {
      client.release();
    }
    const closedManager = (await q(`SELECT end_reason FROM apartment_admin_delegations WHERE apartment_id = $1 AND source = 'manager'`, [A[5]])).rows;
    check('A17: a6 (site yoneticisi karari): dolayli yolda korunur (0), yeni kiraci eklenirken (overrideManager) ezilir; manager devri "replaced" ile kapanir, yeni devir tenant_delegated',
      kept.changed === 0 && overridden.changed === 1 && same(await rolesOf(A[5]), { [o6]: 'FAMILY_MEMBER', [t6]: 'APARTMENT_ADMIN' }) && closedManager[0]?.end_reason === 'replaced'
        && (await openDelegation(A[5]))?.source === 'tenant_delegated', { kept, overridden, closedManager });
  }

  // Okuma tarafi: kural sunucudan gelir (rolesOfUser / listMyApartments)
  {
    const item = (await mgmt.listMyApartments(authOf(t1))).apartments.find((a) => a.apartment_id === A[0]);
    const ownerItem = (await mgmt.listMyApartments(authOf(o1))).apartments.find((a) => a.apartment_id === A[0]);
    check('A18: listMyApartments: kiraci is_admin + management.admin_side tenant + delegated; malik is_admin DEGIL, can.delegate_management false, can.manage_family false',
      item?.is_admin === true && item.management.admin_side === 'tenant' && item.management.delegated === true && ownerItem?.is_admin === false && ownerItem.is_owner === true
        && ownerItem.can.delegate_management === false && ownerItem.can.manage_family === false && ownerItem.can.manage_proxy === true, { item: item?.management, owner: ownerItem?.can });
  }

  // ============================================================================================================
  // B: calisma ani yollari (gercek servisler)
  const SB = await mkSite('TADM Lale Sitesi', 14);
  const B = SB.apts;
  const siteMgr = await mkUser('TADM Site Yoneticisi B', { role: 'site_manager' });
  await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [SB.code, siteMgr]);
  const mgrAuth = authOf(siteMgr, 'site_manager');
  const ownerOf = async (apt, name) => {
    const u = await mkUser(name);
    await member(apt, u, 'APARTMENT_ADMIN');
    await siteMember(SB.code, u);
    await q(`UPDATE apartments SET resident_user_code = $2 WHERE id = $1`, [apt, u]);
    await person(SB.code, { user: u, apt, relation: 'owner' });
    return u;
  };

  // B1: malik hesapsiz kiraci ekler; delegate_management:false gelse de yok sayilir; admin malik kalir (hesap yok), sonra site yoneticisi hesap acinca kiraci admin olur
  {
    const owner = await ownerOf(B[0], 'B Malik 1');
    const result = await mgmt.addTenant({ authUser: authOf(owner), apartmentId: B[0], body: { delegate_management: false, person: { full_name: 'Hesapsiz Kiraci B1', phone: null, email: null } } });
    const pending = await openDelegation(B[0]);
    const view1 = (await mgmt.listMyApartments(authOf(owner))).apartments.find((a) => a.apartment_id === B[0]);
    check('B1: malik hesapsiz kiraci ekler (delegate_management:false YOK SAYILIR): kiraci iliskisi var, hesap olmadigindan admin malik kalir, bekleyen devir (pending_account) ve delegation_pending=true',
      result.mode === 'added' && pending?.state === 'pending_account' && Number(pending.admin_person_id) === result.person_id && view1.management.delegation_pending === true && view1.management.delegated === false
        && view1.is_admin === true && (await adminCodes(B[0])).join() === String(owner), { result, pending, mgmt: view1?.management });
    const created = await people.provisionPersonAccount({ siteCode: SB.code, personId: result.person_id, loginName: 'b1.kiraci', password: 'Gecici-Sifre-1', actor: mgrAuth });
    const roles = await rolesOf(B[0]);
    const open = await openDelegation(B[0]);
    const view2 = (await mgmt.listMyApartments(authOf(created.user_code))).apartments.find((a) => a.apartment_id === B[0]);
    check('B2: site yoneticisi kiraciya hesap acinca (grantApartmentAccess kancasi) kiraci APARTMENT_ADMIN, malik FAMILY_MEMBER; tek acik tenant_delegated/active devir; gosterge kiraciya',
      roles[owner] === 'FAMILY_MEMBER' && roles[created.user_code] === 'APARTMENT_ADMIN' && open?.source === 'tenant_delegated' && open.state === 'active' && Number(open.admin_user_code) === created.user_code
        && (await indicatorOf(B[0])).resident_user_code === created.user_code && view2.is_admin === true && view2.management.delegation_pending === false && view2.management.delegated === true,
      { roles, open, view: view2?.management });
    const audits = await auditRows(B[0]);
    check('B3: kanca denetim kaydi yazar: apartment.admin_tenant_enforced, via access_granted; aktor sistem (hesap acan yonetici degil, kanca)', audits.length === 1 && audits[0].details.via === 'access_granted', audits);
  }

  // B4: malik kayitli kisiyi arayip davet eder (delegate_management:false); kiraci kabul edince admin olur
  {
    const owner = await ownerOf(B[1], 'B Malik 2');
    const tenantUser = await mkUser('B Kiraci 2');
    await member(B[2], tenantUser, 'FAMILY_MEMBER'); // baska dairede bagi var (arama sonucu secilebilir)
    await siteMember(SB.code, tenantUser);
    const handle = rules.signCandidateHandle(process.env.JWT_SECRET, owner, tenantUser);
    const invited = await mgmt.addTenant({ authUser: authOf(owner), apartmentId: B[1], body: { delegate_management: false, candidate: handle } });
    const accepted = await mgmt.respondToRequest({ authUser: authOf(tenantUser), requestId: invited.request.id, accept: true });
    const roles = await rolesOf(B[1]);
    const aud = await auditRows(B[1]);
    const acceptAudit = (await q(`SELECT details FROM audit_log WHERE action = 'apartment_mgmt.tenant_invite_accepted' AND target_id = $1`, [String(B[1])])).rows[0];
    check('B4: kayitli kisi davet + kabul (delegate_management:false yok sayilir): kiraci APARTMENT_ADMIN, malik FAMILY_MEMBER, kabul denetiminde delegated=true, tek apartment.admin_tenant_enforced',
      accepted.status === 'approved' && roles[owner] === 'FAMILY_MEMBER' && roles[tenantUser] === 'APARTMENT_ADMIN' && acceptAudit?.details?.delegated === true && aud.length === 1
        && (await indicatorOf(B[1])).resident_user_code === tenantUser, { roles, accept: acceptAudit?.details, aud: aud.length });

    // B5: kiraci cikis yapar -> admin yeniden malik, devir kapanir, kiraci iliskisi biter
    await mgmt.exitTenancy({ authUser: authOf(tenantUser), apartmentId: B[1] });
    const after = await rolesOf(B[1]);
    check('B5: kiraci "Daireyi devret / Cikis": admin yeniden MALIK, kiraci uyeligi pasif, acik devir kapandi (tenant_exit), gosterge malikte',
      after[owner] === 'APARTMENT_ADMIN' && after[tenantUser] === 'FAMILY_MEMBER(pasif)' && (await openDelegation(B[1])) === null && (await indicatorOf(B[1])).resident_user_code === owner, { after });
  }

  // B6: site yoneticisi KISI KARTINDAN hesapli kiraci ekler (createPerson, e-posta hesabi sitede bagi olan kayitli kisi)
  {
    const owner = await ownerOf(B[3], 'B Malik 3');
    const t = await mkUser('B Kiraci 3', { email: 'b.kiraci3@qa.example' });
    await member(B[4], t, 'FAMILY_MEMBER'); // sitede bagi var (e-postayla hesaba baglanabilir)
    await siteMember(SB.code, t);
    const created = await people.createPerson({
      siteCode: SB.code,
      input: people.parsePersonCreateInput({ full_name: 'B Kiraci 3', email: 'b.kiraci3@qa.example', apartment_id: B[3], relation: 'tenant' }),
      actor: mgrAuth,
    });
    const roles = await rolesOf(B[3]);
    check('B6: kisi karti (createPerson, relation tenant, hesapli): kiraci APARTMENT_ADMIN, malik FAMILY_MEMBER; hesap sitede bagi olan kisiye baglandi',
      created?.has_account === true && roles[owner] === 'FAMILY_MEMBER' && roles[t] === 'APARTMENT_ADMIN', { roles, hasAccount: created?.has_account });
    // B7: daire ekranindan yeni kiraci eklenemez (RELATION_TAKEN) - kural bozulmaz
    const dupCode = await failCode(people.createPerson({
      siteCode: SB.code,
      input: people.parsePersonCreateInput({ full_name: 'Ikinci Kiraci', apartment_id: B[3], relation: 'tenant' }),
      actor: mgrAuth,
    }));
    check('B7: dairede ikinci kiraci eklenemez (RELATION_TAKEN); admin degismedi', dupCode === 'RELATION_TAKEN' && (await rolesOf(B[3]))[t] === 'APARTMENT_ADMIN', dupCode);
  }

  // B8: addResidency (daire ekrani): mevcut hesapli kisiye kiraci iliskisi; B9: updateResidency: sakin -> kiraci
  {
    const owner = await ownerOf(B[5], 'B Malik 4');
    const t = await mkUser('B Kiraci 4');
    await member(B[6], t, 'FAMILY_MEMBER');
    await siteMember(SB.code, t);
    const pid = await person(SB.code, { user: t, apt: B[6], relation: 'family_member' });
    const detail = await people.addResidency({ siteCode: SB.code, personId: pid, body: { apartment_id: B[5], relation: 'tenant' }, actor: mgrAuth });
    const roles = await rolesOf(B[5]);
    check('B8: addResidency (kiraci, hesapli kisi): kiraci o dairede APARTMENT_ADMIN, malik FAMILY_MEMBER', detail !== null && roles[owner] === 'FAMILY_MEMBER' && roles[t] === 'APARTMENT_ADMIN', roles);

    const owner2 = await ownerOf(B[7], 'B Malik 5');
    const r = await mkUser('B Sakin 5');
    await member(B[7], r, 'FAMILY_MEMBER');
    await siteMember(SB.code, r);
    const pidR = await person(SB.code, { user: r, apt: B[7], relation: 'resident' });
    const resId = Number((await q(`SELECT id FROM apartment_residencies WHERE person_id = $1 AND apartment_id = $2`, [pidR, B[7]])).rows[0].id);
    await people.updateResidency({ siteCode: SB.code, residencyId: resId, body: { relation: 'tenant' }, actor: mgrAuth });
    const roles2 = await rolesOf(B[7]);
    check('B9: updateResidency (sakin -> kiraci): kiraci APARTMENT_ADMIN, malik FAMILY_MEMBER', roles2[owner2] === 'FAMILY_MEMBER' && roles2[r] === 'APARTMENT_ADMIN', roles2);

    // B10: "Tasindi" (site yoneticisi) kiraci admin iken: admin kiracinin aile uyesine DEGIL malike doner
    const owner3 = await ownerOf(B[8], 'B Malik 6');
    const t3b = await mkUser('B Kiraci 6');
    const fam = await mkUser('B Kiraci Aile 6');
    // kiracinin ailesi malikten ONCE uye olmus gibi: en eski aktif uye kuralinin yanlis kisiyi sececegi durum
    await q(`UPDATE apartment_memberships SET created_at = NOW() + INTERVAL '1 day' WHERE apartment_id = $1 AND user_code = $2`, [B[8], owner3]);
    await member(B[8], fam, 'FAMILY_MEMBER');
    await member(B[8], t3b, 'FAMILY_MEMBER');
    await siteMember(SB.code, t3b);
    await siteMember(SB.code, fam);
    const pT = await person(SB.code, { user: t3b, apt: B[8], relation: 'tenant' });
    await person(SB.code, { user: fam, apt: B[8], relation: 'family_member' });
    const gc = await pool.connect();
    try {
      await gc.query('BEGIN');
      await ensureTenantIsAdmin(gc, { apartmentIds: [B[8]], via: 'qa' });
      await gc.query('COMMIT');
    } finally {
      gc.release();
    }
    const rolesBefore = await rolesOf(B[8]);
    const resT = Number((await q(`SELECT id FROM apartment_residencies WHERE person_id = $1 AND apartment_id = $2 AND is_current`, [pT, B[8]])).rows[0].id);
    await people.endResidency({ siteCode: SB.code, residencyId: resT, body: {}, actor: mgrAuth });
    const rolesAfter = await rolesOf(B[8]);
    check('B10: "Tasindi" (site yoneticisi) kiraci admin iken: admin kiracinin AILE uyesine degil MALIKE doner (en eski aktif uye kurali aile uyesini secerdi); kiraci pasif',
      rolesBefore[t3b] === 'APARTMENT_ADMIN' && rolesAfter[owner3] === 'APARTMENT_ADMIN' && rolesAfter[fam] === 'FAMILY_MEMBER' && /\(pasif\)$/.test(rolesAfter[t3b])
        && (await indicatorOf(B[8])).resident_user_code === owner3 && (await openDelegation(B[8])) === null, { rolesBefore, rolesAfter });
  }

  // B11: site yoneticisi "Daire adminini degistir" KALIR ve sonraki dolayli yol (hesap baglama / acilis) onu ezmez
  {
    const owner = await ownerOf(B[9], 'B Malik 7');
    const t = await mkUser('B Kiraci 7');
    await member(B[9], t, 'FAMILY_MEMBER');
    await siteMember(SB.code, t);
    await person(SB.code, { user: t, apt: B[9], relation: 'tenant' });
    const ownerPerson = Number((await q(`SELECT sp.id FROM site_people sp JOIN apartment_residencies r ON r.person_id = sp.id WHERE r.apartment_id = $1 AND r.relation = 'owner'`, [B[9]])).rows[0].id);
    const first = await pool.connect();
    try {
      await first.query('BEGIN');
      await ensureTenantIsAdmin(first, { apartmentIds: [B[9]], via: 'qa' });
      await first.query('COMMIT');
    } finally {
      first.release();
    }
    const tenantFirst = await rolesOf(B[9]);
    const changed = await changeApartmentAdmin({ siteCode: SB.code, apartmentId: B[9], body: { user_code: owner, person_id: ownerPerson }, authUser: mgrAuth });
    const startupCount = await sqlMod.ensureTenantAdminRule(pool);
    const roles = await rolesOf(B[9]);
    const open = await openDelegation(B[9]);
    check('B11: kiraci admin iken site yoneticisi "Daire adminini degistir" ile malik adminini secerse (acil durum araci KALIR) acilis adimi bunu EZMEZ (devir kaynagi manager); kiraci yeniden admin olmaz',
      tenantFirst[t] === 'APARTMENT_ADMIN' && changed.changed === true && roles[owner] === 'APARTMENT_ADMIN' && roles[t] === 'FAMILY_MEMBER' && open?.source === 'manager' && startupCount === 0, { tenantFirst, changed, roles, open });
  }

  // B12-B16: kalan uyeye yonetim devri onceligi (apartment_admin_successor.js): guncel kiraci > guncel malik > en eski aktif uye.
  // Kiraci cikarilinca / silinince / pasife alininca yonetim MALIGE doner; kiracinin (malikten ONCE uye olmus) aile uyesine GECMEZ.
  {
    // her senaryo: malik (uyeligi sonradan -> "en eski aktif uye" kurali ailenin lehine olurdu) + kiraci + kiracinin aile uyesi
    const build = async (apt, label) => {
      const owner = await ownerOf(apt, `B Malik ${label}`);
      const tenant = await mkUser(`B Kiraci ${label}`);
      const family = await mkUser(`B Kiraci Aile ${label}`);
      await q(`UPDATE apartment_memberships SET created_at = NOW() + INTERVAL '1 day' WHERE apartment_id = $1 AND user_code = $2`, [apt, owner]);
      await member(apt, family, 'FAMILY_MEMBER');
      await member(apt, tenant, 'FAMILY_MEMBER');
      await siteMember(SB.code, tenant);
      await siteMember(SB.code, family);
      await person(SB.code, { user: tenant, apt, relation: 'tenant' });
      await person(SB.code, { user: family, apt, relation: 'family_member' });
      const gc = await pool.connect();
      try {
        await gc.query('BEGIN');
        await ensureTenantIsAdmin(gc, { apartmentIds: [apt], via: 'qa' });
        await gc.query('COMMIT');
      } finally {
        gc.release();
      }
      return { owner, tenant, family, before: await rolesOf(apt) };
    };

    // B12: daireden cikar (removeApartmentMember)
    const c12 = await build(B[10], '12');
    await membership.removeApartmentMember({ apartmentId: B[10], targetUserCode: c12.tenant, authUser: mgrAuth });
    const r12 = await rolesOf(B[10]);
    check('B12: site yoneticisi kiraci adminini "Daireden cikar": yonetim MALIKE doner (kiracinin aile uyesine degil); kiraci pasif; gosterge malikte',
      c12.before[c12.tenant] === 'APARTMENT_ADMIN' && r12[c12.owner] === 'APARTMENT_ADMIN' && r12[c12.family] === 'FAMILY_MEMBER' && /\(pasif\)$/.test(r12[c12.tenant])
        && (await indicatorOf(B[10])).resident_user_code === c12.owner && (await adminCodes(B[10])).join() === String(c12.owner), { before: c12.before, after: r12 });

    // B13: sakini sil (deleteApartmentMember)
    const c13 = await build(B[11], '13');
    await membership.deleteApartmentMember({ apartmentId: B[11], targetUserCode: c13.tenant, authUser: mgrAuth });
    const r13 = await rolesOf(B[11]);
    check('B13: site yoneticisi kiraci adminini "Sakini sil": yonetim MALIKE doner; aile uyesine gecmez; kiracinin uyelik satiri silinir',
      r13[c13.owner] === 'APARTMENT_ADMIN' && r13[c13.family] === 'FAMILY_MEMBER' && !(c13.tenant in r13) && (await indicatorOf(B[11])).resident_user_code === c13.owner, { after: r13 });

    // B14: gecici pasife alma (toggleApartmentMemberStatus) -> malik; yeniden etkinlestirilince gunluk bakim / acilis kurali kiraciyi yeniden admin yapar
    const c14 = await build(B[12], '14');
    await membership.toggleApartmentMemberStatus({ apartmentId: B[12], targetUserCode: c14.tenant, isActive: false, authUser: mgrAuth });
    const paused = await rolesOf(B[12]);
    await membership.toggleApartmentMemberStatus({ apartmentId: B[12], targetUserCode: c14.tenant, isActive: true, authUser: mgrAuth });
    const healed = await sqlMod.ensureTenantAdminRule(pool);
    const resumed = await rolesOf(B[12]);
    check('B14: kiraci admini pasife alininca yonetim MALIKE (aileye degil) gecer; geri etkinlestirilince acilis / gunluk bakim kurali kiraciyi yeniden admin yapar (kendi kendini onarir)',
      paused[c14.owner] === 'APARTMENT_ADMIN' && paused[c14.family] === 'FAMILY_MEMBER' && healed >= 1 && resumed[c14.tenant] === 'APARTMENT_ADMIN' && resumed[c14.owner] === 'FAMILY_MEMBER' && resumed[c14.family] === 'FAMILY_MEMBER',
      { paused, resumed, healed });

    // B15: oncelik sirasi dogrudan (kalan uye secimi): kiraci > malik > en eski aktif uye; askidaki kiraci / malik ust siraya yukselmez
    const c15 = await build(B[13], '15');
    await q(`UPDATE apartment_memberships SET created_at = NOW() - INTERVAL '2 days' WHERE apartment_id = $1 AND user_code = $2`, [B[13], c15.family]);
    const suspend = (user) => q(`INSERT INTO apartment_access_suspensions (site_code, apartment_id, user_code, reason_code, note) VALUES ($1, $2, $3, 'safety', 'QA')`, [SB.code, B[13], user]);
    const pick = () => successor.pickAdminSuccessor(pool, B[13], 1);
    const first = await pick();
    await suspend(c15.tenant);
    const second = await pick();
    await suspend(c15.owner);
    const third = await pick();
    await q(`UPDATE apartment_access_suspensions SET lifted_at = NOW() WHERE apartment_id = $1`, [B[13]]);
    const fourth = await pick();
    check('B15: kalan uye onceligi: kiraci > malik > en eski aktif uye (kiraci askidaysa malik; ikisi de askidaysa en eski aktif uye = aile); askilar kalkinca yine kiraci',
      first === c15.tenant && second === c15.owner && third === c15.family && fourth === c15.tenant, { first, second, third, fourth, ids: c15 });
    // hesabi silinmis / pasif kiraci ve malik de ust siraya yukselmez
    await q(`UPDATE users SET is_active = FALSE WHERE user_code = $1`, [c15.tenant]);
    const inactiveTenant = await pick();
    await q(`UPDATE users SET is_active = TRUE WHERE user_code = $1`, [c15.tenant]);
    check('B16: hesabi pasif kiraci ust siraya yukselmez (malik secilir); hesap yeniden aktif olunca kiraci', inactiveTenant === c15.owner && (await pick()) === c15.tenant, { inactiveTenant });
  }

  // ============================================================================================================
  // C: toplu yukleme (admin onceligi kiracı > malik > diger)
  {
    const SC = await mkSite('TADM Toplu Sitesi', 6);
    const mgr = await mkUser('TADM Toplu Yonetici', { role: 'site_manager' });
    await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [SC.code, mgr]);
    const actor = { id: mgr, user_code: mgr, userCode: mgr, role: 'site_manager', full_name: 'TADM Toplu Yonetici', email: `tadm${mgr}@qa.example` };
    const row = (n, cells) => ({ n, cells });
    const importPeople = async (rows, key) => {
      const body = { spec_version: 1, rows };
      const preview = await bulk.previewImport({ siteCode: SC.code, kind: 'people', body });
      return bulk.commitImport({ siteCode: SC.code, kind: 'people', actor, body: { ...body, expected_hash: preview.preview_hash, idempotency_key: key, acknowledged: true } });
    };
    // C1: ayni dosyada malik + kiraci + sakin (daire 1) ve yalniz malik (daire 2)
    const first = await importPeople([
      row(2, { ad_soyad: 'Toplu Malik Bir', blok: 'A', daire_no: '1', iliski: 'Malik' }),
      row(3, { ad_soyad: 'Toplu Kiraci Bir', blok: 'A', daire_no: '1', iliski: 'Kiracı' }),
      row(4, { ad_soyad: 'Toplu Sakin Bir', blok: 'A', daire_no: '1', iliski: 'Sakin' }),
      row(5, { ad_soyad: 'Toplu Malik Iki', blok: 'A', daire_no: '2', iliski: 'Malik' }),
    ], 'tadm-bulk-0001');
    const adminOf = async (apt) => {
      const r = (await q(
        `SELECT sp.id, r.relation, m.role FROM apartment_memberships m JOIN site_people sp ON sp.user_code = m.user_code AND sp.site_code = $2
         JOIN apartment_residencies r ON r.person_id = sp.id AND r.apartment_id = m.apartment_id AND r.is_current
         WHERE m.apartment_id = $1 AND m.is_active ORDER BY r.relation`, [apt, SC.code])).rows;
      return Object.fromEntries(r.map((x) => [x.relation, x.role]));
    };
    check('C1: toplu yukleme (ayni dosyada malik + kiraci + sakin): daire admini KIRACI, malik ve sakin FAMILY_MEMBER; yalniz-malik dairede malik admin',
      first.status === 201 && same(await adminOf(SC.apts[0]), { owner: 'FAMILY_MEMBER', resident: 'FAMILY_MEMBER', tenant: 'APARTMENT_ADMIN' }) && same(await adminOf(SC.apts[1]), { owner: 'APARTMENT_ADMIN' }),
      { a1: await adminOf(SC.apts[0]), a2: await adminOf(SC.apts[1]), status: first.status });
    const indicator1 = await indicatorOf(SC.apts[0]);
    const tenantUser1 = Number((await q(`SELECT sp.user_code FROM apartment_residencies r JOIN site_people sp ON sp.id = r.person_id WHERE r.apartment_id = $1 AND r.relation = 'tenant'`, [SC.apts[0]])).rows[0].user_code);
    check('C2: gosterge (resident_user_code) kiracida (kiraci ilk hesap alan olarak dogal admin; fazladan devir / denetim satiri yok)', indicator1.resident_user_code === tenantUser1 && (await auditRows(SC.apts[0])).length === 0, { indicator1, tenantUser1 });

    // C3: dairede MEVCUT admin malik iken sonraki dosyada kiraci eklenir -> admin kiraciya gecer (eski "mevcut admin korunur" kurali kiraci lehine degisti)
    const second = await importPeople([row(2, { ad_soyad: 'Toplu Kiraci Iki', blok: 'A', daire_no: '2', iliski: 'Kiracı' })], 'tadm-bulk-0002');
    check('C3: mevcut admin MALIK iken sonraki yuklemede kiraci eklenirse admin kiraci olur (malik FAMILY_MEMBER)',
      second.status === 201 && same(await adminOf(SC.apts[1]), { owner: 'FAMILY_MEMBER', tenant: 'APARTMENT_ADMIN' }), await adminOf(SC.apts[1]));
    const apt2Audits = await auditRows(SC.apts[1]);
    check('C4: toplu yukleme: admin gecisi daire basina TEK apartment.admin_tenant_enforced denetim satiri (aktor yukleyen yonetici ya da kanca/sistem), kisisel veri yok',
      apt2Audits.length === 1 && ['bulk_import', 'access_granted'].includes(apt2Audits[0].details.via) && !/Toplu|@/.test(JSON.stringify(apt2Audits[0].details)), apt2Audits.map((a) => a.details));

    // C5: hesapsiz kiraci icin dosya e-postasiz: hesap yine acilir (toplu yukleme her kisiye hesap acar)  - yalniz kiraci ve malik sirasi
    const third = await importPeople([
      row(2, { ad_soyad: 'Toplu Kiraci Uc', blok: 'A', daire_no: '3', iliski: 'Kiracı' }),
      row(3, { ad_soyad: 'Toplu Malik Uc', blok: 'A', daire_no: '3', iliski: 'Malik' }),
    ], 'tadm-bulk-0003');
    check('C5: dosyada once kiraci sonra malik satiri olsa da (satir sirasi fark etmez) admin kiraci', third.status === 201 && same(await adminOf(SC.apts[2]), { owner: 'FAMILY_MEMBER', tenant: 'APARTMENT_ADMIN' }), await adminOf(SC.apts[2]));
    // C6: ayni dosya ikinci kez: degisiklik yok, yeni denetim satiri yok
    const rowsBefore = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'apartment.admin_tenant_enforced' AND site_code = $1`, [SC.code]);
    const replay = await importPeople([
      row(2, { ad_soyad: 'Toplu Kiraci Uc', blok: 'A', daire_no: '3', iliski: 'Kiracı' }),
      row(3, { ad_soyad: 'Toplu Malik Uc', blok: 'A', daire_no: '3', iliski: 'Malik' }),
    ], 'tadm-bulk-0004');
    const rowsAfter = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'apartment.admin_tenant_enforced' AND site_code = $1`, [SC.code]);
    check('C6: ayni dosya yeniden yuklenir: yeni admin degisikligi / denetim satiri YOK (idempotans)', replay.status === 201 && rowsBefore === rowsAfter && same(await adminOf(SC.apts[2]), { owner: 'FAMILY_MEMBER', tenant: 'APARTMENT_ADMIN' }), { rowsBefore, rowsAfter });
  }

  // ============================================================================================================
  // D: eszamanli (kilit sirasi: 40P01 = 0; her daire icin tek denetim satiri ve tek acik devir)
  {
    const SD = await mkSite('TADM Eszamanli Sitesi', 40);
    const D = SD.apts;
    const owners = []; const tenants = [];
    for (let i = 0; i < D.length; i += 1) {
      const o = await mkUser(`D Malik ${i}`);
      const t = await mkUser(`D Kiraci ${i}`);
      await member(D[i], o, 'APARTMENT_ADMIN');
      await member(D[i], t, 'FAMILY_MEMBER');
      await q(`UPDATE apartments SET resident_user_code = $2 WHERE id = $1`, [D[i], o]);
      await person(SD.code, { user: o, apt: D[i], relation: 'owner' });
      await person(SD.code, { user: t, apt: D[i], relation: 'tenant' });
      owners.push(o); tenants.push(t);
    }
    hooks.deadlocks = 0;
    const errorsBefore = serverErrors.filter((line) => /errorId=|deadlock/i.test(line)).length;
    const runScoped = async (ids, order) => {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const list = order === 'desc' ? [...ids].reverse() : ids;
        const result = await ensureTenantIsAdmin(client, { apartmentIds: list, via: 'qa_concurrent' });
        await client.query('COMMIT');
        return result.changed;
      } catch (error) {
        await client.query('ROLLBACK').catch(() => {});
        throw error;
      } finally {
        client.release();
      }
    };
    const jobs = [
      runScoped(D.slice(0, 25), 'asc'),
      runScoped(D.slice(15, 40), 'desc'),
      runScoped(D.slice(10, 30), 'asc'),
      sqlMod.ensureTenantAdminRule(pool),
      sqlMod.ensureTenantAdminRule(pool),
      q(migrationText),
    ];
    const outcomes = await Promise.allSettled(jobs);
    const failed = outcomes.filter((o) => o.status === 'rejected').map((o) => o.reason?.code ?? String(o.reason?.message));
    const enforced = await countOf(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'apartment.admin_tenant_enforced' AND site_code = $1`, [SD.code]);
    const distinct = await countOf(`SELECT COUNT(DISTINCT target_id)::int AS n FROM audit_log WHERE action = 'apartment.admin_tenant_enforced' AND site_code = $1`, [SD.code]);
    const admins = (await q(`SELECT apartment_id, COUNT(*)::int AS n FROM apartment_memberships WHERE apartment_id = ANY($1::BIGINT[]) AND role = 'APARTMENT_ADMIN' GROUP BY apartment_id`, [D])).rows;
    const openCounts = (await q(`SELECT apartment_id, COUNT(*)::int AS n FROM apartment_admin_delegations WHERE apartment_id = ANY($1::BIGINT[]) AND ended_at IS NULL GROUP BY apartment_id`, [D])).rows;
    const allTenantAdmin = (await q(`SELECT COUNT(*)::int AS n FROM apartment_memberships m JOIN apartments a ON a.id = m.apartment_id WHERE m.apartment_id = ANY($1::BIGINT[]) AND m.role = 'APARTMENT_ADMIN' AND m.user_code = ANY($2::INT[]) AND a.resident_user_code = m.user_code`, [D, tenants])).rows[0].n;
    check(`D1: 3 kapsamli (ters siralama dahil) + 2 acilis + 1 migration metni ESZAMANLI: hata yok, 40P01 = ${hooks.deadlocks}, her daire icin tek denetim satiri (${enforced}/${distinct}/40), tek admin, tek acik devir, hepsi kiraci`,
      failed.length === 0 && hooks.deadlocks === 0 && enforced === 40 && distinct === 40 && admins.length === 40 && admins.every((r) => r.n === 1) && openCounts.length === 40 && openCounts.every((r) => r.n === 1)
        && allTenantAdmin === 40 && serverErrors.filter((line) => /errorId=|deadlock/i.test(line)).length === errorsBefore,
      { failed, enforced, distinct, admins: admins.length, open: openCounts.length, allTenantAdmin, deadlocks: hooks.deadlocks });
  }

  // ============================================================================================================
  // E: ensureDbSchema (acilis) ikinci kez: aday yok -> hatasiz
  {
    let ok = true;
    try { await ensureDbSchema(); } catch (_error) { ok = false; }
    const migrationStatementCount = sqlMod.TENANT_ADMIN_STATEMENTS.length;
    const dupCode = await failCode(q(`INSERT INTO apartment_admin_delegations (site_code, apartment_id, source, state) VALUES ($1, $2, 'tenant_delegated', 'active'), ($1, $2, 'tenant_delegated', 'active')`, [S.code, A[7]]));
    check('E1: ensureDbSchema ikinci kez hatasiz (kural adimi aday yokken tek okuma); acik devir tekilligi (uq_..._open) korunuyor (23505)', ok && migrationStatementCount === 8 && dupCode === '23505', { ok, dupCode });
  }

  await finishChild(pool);
}
