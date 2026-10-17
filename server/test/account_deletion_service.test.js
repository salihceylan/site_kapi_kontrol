// Hesap silme servisi (DB'siz, KATI kayıtlı sahte bağlantı): kilit sırası (mevcut akışlarla aynı yön), engeller, kapsam büyümesi / deadlock yeniden
// denemesi, silme sonrası işler (anahtar döndürme, e-posta), kişisel veri sızdırmama. Gerçek PostgreSQL davranışı: scripts/qa_platform_pg.mjs "account".
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import { pool } from '../src/db.js';
import { passwordChangeFailureTracker } from '../src/middlewares/login_throttle.js';
import { passwordGuardDeps } from '../src/modules/account_password_guard.js';
import {
  accountHooks,
  findLastManagerSites,
  performAccountDeletion,
  pickDeletedEmail,
  previewAccountDeletion,
  requestAccountDeletion,
  rotateKeysWithRetry,
  unusablePasswordHash,
} from '../src/modules/account_deletion_service.js';
import { peopleLockKey } from '../src/modules/people_sync.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

const USER = { id: 77, user_code: 12345, full_name: 'Ada Lovelace', email: 'ada@example.com', login_name: 'ada.l', role: 'apartment_owner', is_active: true, deleted_at: null };

let log;
let state;
let begins;
let originalConnect;
let originalQuery;
let originalCreds;
let consoleErrors;
let originalConsoleError;
let hookCalls;
let originalHooks;
let pendingBackground;
const settle = () => Promise.all(pendingBackground.splice(0));

function defaultState() {
  return {
    user: { ...USER },
    apartments: [{ id: 501, site_code: 1000000002, resident_user_code: 12345 }, { id: 502, site_code: 1000000001, resident_user_code: null }],
    siteRows: [1000000002, 1000000001],
    managed: [],
    devices: [11, 12],
    membershipRoles: new Map([[502, 'APARTMENT_ADMIN']]),
    lastManagerSites: [],
    scopeGrowth: 0, // kaç denemede kapsam kilitler alındıktan sonra büysün (yeniden deneme)
    scopeReads: 0,
    failWith: [], // sıradaki BEGIN denemeleri için hata kodları
    pendingApplications: [],
    rowCounts: {},
    takenEmails: [], // tombstone adresi önceden başka satırca alınmış (küçük harf)
    optionalTables: {}, // { reminders, push, documents }: sonradan eklenen migration tabloları var mı (katalog yanıtı)
    optionalCounts: {}, // { pushDevices, uploadedDocuments, pendingReminders }
    reminderRows: 0, // finance_reminder_items UPDATE'inin etkilediği satır
  };
}

function handle(sql, params) {
  if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) {
    if (sql === 'BEGIN') begins += 1;
    return ok();
  }
  if (/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
  if (/^SELECT id, user_code, full_name, email, login_name, role, is_active, deleted_at FROM users WHERE user_code = \$1/.test(sql)) {
    return state.user ? ok([state.user]) : ok();
  }
  if (/^SELECT a\.id, a\.site_code, a\.resident_user_code FROM apartments a/.test(sql)) {
    const rows = state.apartments.map((a) => ({ id: String(a.id), site_code: String(a.site_code), resident_user_code: a.resident_user_code }));
    state.scopeReads += 1;
    // her denemenin İKİNCİ okuması (kilitlerden sonra) büyümüş kapsam görür
    if (state.scopeReads % 2 === 0 && state.scopeGrowth > 0) {
      state.scopeGrowth -= 1;
      rows.push({ id: '999', site_code: '1000000009', resident_user_code: null });
    }
    return ok(rows);
  }
  if (/^SELECT site_code FROM site_manager_sites WHERE manager_user_code = \$1 UNION SELECT site_code FROM site_memberships WHERE user_code = \$1 UNION SELECT site_code FROM site_people/.test(sql)) {
    return ok(state.siteRows.map((code) => ({ site_code: String(code) })));
  }
  if (/^SELECT site_code FROM site_manager_sites WHERE manager_user_code = \$1 UNION SELECT site_code FROM site_memberships WHERE user_code = \$1 AND role IN/.test(sql)) {
    return ok(state.managed.map((code) => ({ site_code: String(code) })));
  }
  if (/^SELECT id FROM devices WHERE assigned_user_code = \$1 OR owner_user_id = \$2 ORDER BY id/.test(sql)) {
    return ok(state.devices.map((id) => ({ id: String(id) })));
  }
  if (/^SELECT to_regclass\('public\.finance_reminder_items'\) IS NOT NULL AS present$/.test(sql)) return ok([{ present: state.optionalTables.reminders === true }]);
  if (/^SELECT to_regclass\('public\.push_devices'\) IS NOT NULL AS has_devices, to_regclass\('public\.push_outbox'\) IS NOT NULL AS has_outbox$/.test(sql)) {
    return ok([{ has_devices: state.optionalTables.push === true, has_outbox: state.optionalTables.push === true }]);
  }
  if (/^SELECT \(to_regclass\('public\.push_devices'\) IS NOT NULL\) AS has_push_devices/.test(sql)) {
    return ok([{ has_push_devices: state.optionalTables.push === true, has_documents: state.optionalTables.documents === true, has_reminders: state.optionalTables.reminders === true }]);
  }
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM push_devices WHERE user_code = \$1$/.test(sql)) return ok([{ n: state.optionalCounts.pushDevices ?? 0 }]);
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM document_versions WHERE uploaded_by = \$1$/.test(sql)) return ok([{ n: state.optionalCounts.uploadedDocuments ?? 0 }]);
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM finance_reminder_items i /.test(sql)) return ok([{ n: state.optionalCounts.pendingReminders ?? 0 }]);
  if (/^UPDATE finance_reminder_items i SET /.test(sql)) return { rows: (state.reminderRunIds ?? []).map((id) => ({ run_id: String(id) })), rowCount: state.reminderRows };
  if (/^DELETE FROM push_devices WHERE id IN/.test(sql)) return ok([], 2);
  if (/^DELETE FROM push_outbox WHERE id IN/.test(sql)) return ok([], 3);
  if (/^SELECT 1 FROM users WHERE LOWER\(email\) = LOWER\(\$1\) AND user_code <> \$2 LIMIT 1$/.test(sql)) {
    return state.takenEmails.includes(String(params[0]).toLowerCase()) ? ok([{ '?column?': 1 }]) : ok();
  }
  if (/^UPDATE users SET full_name = \$2/.test(sql)) {
    return ok([{ user_code: params[0] }]);
  }
  if (/^WITH managed AS/.test(sql)) {
    return ok(state.lastManagerSites.map((s) => ({ site_code: String(s.site_code), name: s.name })));
  }
  if (/^DELETE FROM apartment_memberships WHERE user_code = \$1 RETURNING apartment_id, role/.test(sql)) {
    return ok([...state.membershipRoles].map(([apartment_id, role]) => ({ apartment_id: String(apartment_id), role })));
  }
  if (/^SELECT id, block_count, apartment_count, door_count FROM site_applications/.test(sql)) {
    return ok(state.pendingApplications);
  }
  for (const [pattern, count] of Object.entries(state.rowCounts)) {
    if (new RegExp(pattern).test(sql)) return ok([], count);
  }
  return ok();
}

function installFakeDb() {
  pool.connect = async () => ({
    query: async (text, params) => {
      const sql = norm(text);
      log.push({ sql, params: params ?? [] });
      if (sql === 'BEGIN' && state.failWith.length > 0) {
        const code = state.failWith.shift();
        if (code) {
          // BEGIN başarılı sayılır; hata ilk kilit sorgusunda çıkar
          state.pendingFailure = code;
        }
      }
      if (state.pendingFailure && /^SELECT pg_advisory_xact_lock/.test(sql)) {
        const code = state.pendingFailure;
        state.pendingFailure = null;
        throw Object.assign(new Error('simulated'), { code });
      }
      return handle(sql, params ?? []);
    },
    release() {},
  });
  pool.query = async (text, params) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [], pool: true });
    return handle(sql, params ?? []);
  };
}

const indexOf = (pattern, from = 0) => log.findIndex((entry, i) => i >= from && pattern.test(entry.sql));
const lastIndexOf = (pattern) => {
  for (let i = log.length - 1; i >= 0; i -= 1) if (pattern.test(log[i].sql)) return i;
  return -1;
};
const sqls = (pattern) => log.filter((entry) => pattern.test(entry.sql));

beforeEach(() => {
  log = [];
  begins = 0;
  state = defaultState();
  consoleErrors = [];
  originalConsoleError = console.error;
  console.error = (...args) => {
    consoleErrors.push(args.map(String).join(' '));
  };
  originalConnect = pool.connect;
  originalQuery = pool.query;
  installFakeDb();
  passwordChangeFailureTracker.reset();
  originalCreds = { ...passwordGuardDeps };
  passwordGuardDeps.loadUser = async () => ({ password_hash: bcrypt.hashSync('Dogru-Parola-1', 4), deleted_at: null });
  hookCalls = { devices: [], sites: [], mails: [] };
  originalHooks = { ...accountHooks };
  pendingBackground = [];
  accountHooks.background = (task) => {
    pendingBackground.push(task());
  };
  accountHooks.rotateTokensForDevices = async (arg) => {
    hookCalls.devices.push(arg);
    return 0;
  };
  accountHooks.rotateTokensForSite = async (arg) => {
    hookCalls.sites.push(arg);
    return 0;
  };
  accountHooks.smtpConfigured = () => true;
  accountHooks.sendDeletedEmail = async (arg) => {
    hookCalls.mails.push(arg);
  };
  // anahtar döndürme yeniden denemesi: gerçek bekleme YOK (süreler kaydedilir), denetim satırı kaydedilir
  hookCalls.sleeps = [];
  hookCalls.rotationAudits = [];
  accountHooks.rotationBackoffMs = [1000, 5000, 20000];
  accountHooks.sleep = async (ms) => {
    hookCalls.sleeps.push(ms);
  };
  accountHooks.recordRotationFailure = async (userCode, details) => {
    hookCalls.rotationAudits.push({ userCode, details });
  };
});

afterEach(() => {
  console.error = originalConsoleError;
  pool.connect = originalConnect;
  pool.query = originalQuery;
  Object.assign(passwordGuardDeps, originalCreds);
  Object.assign(accountHooks, originalHooks);
  passwordChangeFailureTracker.reset();
});

describe('hesap silme: kilit sırası (mevcut akışlarla AYNI yön)', () => {
  it('sıra: küresel advisory -> join_requests -> people_sync advisory (siteler artan) -> sites -> daireler -> cihazlar -> yönetici satırları -> users -> kalan satırlar', async () => {
    state.managed = [1000000001];
    await performAccountDeletion(12345);
    const order = [
      ['küresel advisory', /^SELECT pg_advisory_xact_lock\(hashtext\(\$1\)\)$/, (e) => e.params[0] === 'account_deletion'],
      ['kullanıcı okuma', /^SELECT id, user_code, full_name, email, login_name, role, is_active, deleted_at FROM users/],
      ['join_requests kilidi', /^SELECT id FROM join_requests WHERE user_code = \$1 ORDER BY id FOR UPDATE$/],
      ['people_sync advisory', /^SELECT pg_advisory_xact_lock/, (e) => e.params[0] === peopleLockKey(1000000001)],
      ['sites ad anlık görüntüsü', /^UPDATE sites SET deletion_requested_by_name/],
      ['daire kilidi', /^SELECT id FROM apartments WHERE id = ANY\(\$1::BIGINT\[\]\) ORDER BY id FOR UPDATE$/],
      ['cihaz kilidi', /^SELECT id FROM devices WHERE id = ANY\(\$1::BIGINT\[\]\) ORDER BY id FOR UPDATE$/],
      ['cihaz güncelleme', /^UPDATE devices SET/],
      ['site_manager_sites kilidi', /^SELECT site_code FROM site_manager_sites WHERE site_code = ANY\(\$1::BIGINT\[\]\) ORDER BY site_code, manager_user_code FOR UPDATE$/],
      ['site_memberships kilidi', /^SELECT site_code FROM site_memberships WHERE site_code = ANY\(\$1::BIGINT\[\]\) AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE ORDER BY site_code, user_code FOR UPDATE$/],
      ['users anonimleştirme', /^UPDATE users SET full_name = \$2/],
      ['eş yöneticilerin users satırları (FOR SHARE, user_code sırası)', /^SELECT u\.user_code FROM users u WHERE u\.user_code <> \$1 .* ORDER BY u\.user_code FOR SHARE OF u$/],
      ['engel sorgusu', /^WITH managed AS/],
      ['daire üyelikleri silinir', /^DELETE FROM apartment_memberships WHERE user_code = \$1/],
      ['site_manager_sites silinir', /^DELETE FROM site_manager_sites WHERE manager_user_code = \$1$/],
      ['qr jetonları silinir', /^DELETE FROM qr_access_tokens/],
      ['duyuru alıcıları', /^UPDATE announcement_recipients/],
      ['başvuru kilidi', /^SELECT id, block_count, apartment_count, door_count FROM site_applications/],
      ['kişi kayıtları (CRM)', /^UPDATE site_people SET/],
      ['account.deleted denetimi', /^INSERT INTO audit_log/, (e) => e.params[3] === 'account.deleted'],
      ['COMMIT', /^COMMIT$/],
    ];
    let cursor = -1;
    for (const [label, pattern, extra] of order) {
      let found = -1;
      for (let i = cursor + 1; i < log.length; i += 1) {
        if (pattern.test(log[i].sql) && (!extra || extra(log[i]))) {
          found = i;
          break;
        }
      }
      assert.ok(found > cursor, `${label}: beklenen sırada bulunamadı (imleç ${cursor})`);
      cursor = found;
    }
  });

  it('site advisory kilitleri ARTAN sırada ve kullanıcının TÜM sitelerini kapsar', async () => {
    state.siteRows = [1000000009, 1000000001];
    state.apartments = [{ id: 501, site_code: 1000000005, resident_user_code: null }];
    await performAccountDeletion(12345);
    const keys = log.filter((e) => /^SELECT pg_advisory_xact_lock/.test(e.sql) && e.params[0] !== 'account_deletion').map((e) => e.params[0]);
    assert.deepEqual(keys, [1000000001, 1000000005, 1000000009].map(peopleLockKey));
  });

  it('daireler ve cihazlar id sırasıyla ve kullanıcı satırından ÖNCE kilitlenir; kullanıcı güncellemesinden sonra yalnız bu kullanıcıya özgü satırlar yazılır', async () => {
    await performAccountDeletion(12345);
    const users = indexOf(/^UPDATE users SET full_name = \$2/);
    assert.ok(indexOf(/FROM apartments WHERE id = ANY/) < users);
    assert.ok(indexOf(/FROM devices WHERE id = ANY/) < users);
    assert.ok(indexOf(/^UPDATE devices SET/) < users, 'cihaz güncellemesi kullanıcıdan önce (site başvurusu onayı: cihaz -> kullanıcı)');
    // kullanıcı satırından SONRA: paylaşılan kilit sahibi tablolar (apartments / devices / site_manager_sites kilitleri) yeniden kilitlenmez
    const after = log.slice(users + 1);
    assert.equal(after.some((e) => /FOR UPDATE/.test(e.sql) && /apartments|devices|site_manager_sites/.test(e.sql)), false);
  });

  it('ters sıra yok: hiçbir kilit sorgusu (FOR UPDATE) kullanıcı güncellemesinden sonra apartments / devices / join_requests için çalışmaz', async () => {
    await performAccountDeletion(12345);
    const users = indexOf(/^UPDATE users SET full_name = \$2/);
    for (const entry of log.slice(users + 1)) {
      assert.equal(/^SELECT .* FROM (apartments|devices|join_requests) .*FOR UPDATE/.test(entry.sql), false, entry.sql);
    }
  });

  it('eş yönetici kilidi (R2 F-4): yönetilen siteler parametre, kendi kodu hariç, ORDER BY user_code FOR SHARE; engel sorgusundan ÖNCE; yönetilen site yoksa HİÇ çalışmaz', async () => {
    state.managed = [1000000002, 1000000001];
    await performAccountDeletion(12345);
    const lock = sqls(/FOR SHARE OF u$/);
    assert.equal(lock.length, 1);
    assert.deepEqual(lock[0].params, [12345, [1000000002, 1000000001]]);
    assert.ok(lock[0].sql.includes('SELECT manager_user_code FROM site_manager_sites WHERE site_code = ANY($2::BIGINT[])'));
    assert.ok(lock[0].sql.includes("role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE"));
    assert.ok(indexOf(/FOR SHARE OF u$/) < indexOf(/^WITH managed AS/), 'kilit, engel kararından önce');
    assert.ok(indexOf(/^UPDATE users SET full_name = \$2/) < indexOf(/FOR SHARE OF u$/), 'önce kendi satırı (kilit sırası: kendi users -> eş users)');

    log = [];
    state = defaultState();
    await performAccountDeletion(12345);
    assert.equal(sqls(/FOR SHARE OF u$/).length, 0, 'yönetici olmayan hesap eş kilidi almaz');
  });

  it('kapsam kullanıcı kilidinden SONRA yeniden okunur (apartments sorgusu iki kez)', async () => {
    await performAccountDeletion(12345);
    const reads = log.map((e, i) => (/^SELECT a\.id, a\.site_code, a\.resident_user_code FROM apartments a/.test(e.sql) ? i : -1)).filter((i) => i >= 0);
    assert.equal(reads.length, 2);
    assert.ok(reads[0] < indexOf(/^UPDATE users SET full_name = \$2/) && indexOf(/^UPDATE users SET full_name = \$2/) < reads[1]);
  });
});

describe('hesap silme: kimliksizleştirme ifadesi', () => {
  it('users UPDATE: ad, benzersiz tombstone e-postası, kullanıcı adı / telefon NULL, kullanılamaz parola özeti, jeton alanları NULL, pasif + deleted_at, rol individual', async () => {
    await performAccountDeletion(12345);
    const update = sqls(/^UPDATE users SET full_name = \$2/)[0];
    for (const fragment of [
      'login_name = NULL',
      'phone_number = NULL',
      'email_verification_code_hash = NULL',
      'email_verification_expires_at = NULL',
      'password_reset_token_hash = NULL',
      'password_reset_expires_at = NULL',
      'is_active = FALSE',
      "role = 'individual'",
      'deleted_at = NOW()',
    ]) {
      assert.ok(update.sql.includes(fragment), fragment);
    }
    assert.ok(update.sql.includes("deleted_at IS NULL AND role <> 'super_user'"), 'çift silme ve süper kullanıcı koruması WHERE içinde');
    assert.equal(update.params[0], 12345);
    assert.equal(update.params[1], 'Silinmiş Kullanıcı');
    assert.equal(update.params[2], 'deleted-12345@deleted.invalid');
    assert.equal(typeof update.params[3], 'string');
    assert.notEqual(update.params[3], update.params[1]);
  });

  it('tombstone e-postası rezerve DEĞİL (R2 F-8): kontrol users UPDATE\'inden ÖNCE; çakışma yoksa deleted-<kod>@deleted.invalid', async () => {
    await performAccountDeletion(12345);
    const check = indexOf(/^SELECT 1 FROM users WHERE LOWER\(email\) = LOWER\(\$1\) AND user_code <> \$2 LIMIT 1$/);
    assert.ok(check >= 0, 'çakışma kontrolü yapılmalı');
    assert.ok(check < indexOf(/^UPDATE users SET full_name = \$2/));
    assert.deepEqual(log[check].params, ['deleted-12345@deleted.invalid', 12345]);
  });

  it('tombstone adresi önceden BAŞKA satırca alınmışsa (büyük/küçük harf farkıyla bile) rastgele sonekli adres seçilir; silme 23505 ile düşmez', async () => {
    state.takenEmails = ['deleted-12345@deleted.invalid'];
    const result = await performAccountDeletion(12345);
    assert.equal(result.deleted !== false, true);
    const update = sqls(/^UPDATE users SET full_name = \$2/)[0];
    assert.match(update.params[2], /^deleted-12345-[0-9a-f]{10}@deleted\.invalid$/);
    assert.notEqual(update.params[2], 'deleted-12345@deleted.invalid');
    // eski adrese gelen davetler de AYNI (sonekli) tombstone adresine taşınır
    const invitation = sqls(/^UPDATE site_manager_invitations SET email = \$2/)[0];
    assert.equal(invitation.params[1], update.params[2]);
    assert.equal(log.some((e) => /^ROLLBACK$/.test(e.sql)), false);
  });

  it('pickDeletedEmail: sonek çakışırsa yeniden dener; 5 denemede de çakışırsa 409 ACCOUNT_DELETE_BUSY (sonsuz döngü yok)', async () => {
    const taken = new Set();
    const client = {
      queries: 0,
      async query(_sql, params) {
        this.queries += 1;
        return taken.has(String(params[0]).toLowerCase()) ? { rows: [{ x: 1 }] } : { rows: [] };
      },
    };
    taken.add('deleted-7@deleted.invalid');
    taken.add('deleted-7-aaaa@deleted.invalid');
    const sequence = ['aaaa', 'bbbb'];
    assert.equal(await pickDeletedEmail(client, 7, () => sequence.shift()), 'deleted-7-bbbb@deleted.invalid');
    assert.equal(client.queries, 3);
    const always = { async query() { return { rows: [{ x: 1 }] }; } };
    await assert.rejects(() => pickDeletedEmail(always, 7, () => 'cccc'), (error) => error.code === 'ACCOUNT_DELETE_BUSY' && error.statusCode === 409);
  });

  it('R10: aidat hatırlatma kalemleri ve push verisi AYNI işlemde temizlenir: bildirim tercihi -> push (cihaz + kuyruk) -> hatırlatma kalemleri -> ... -> kişi kayıtlarının hesaptan KOPMASI (kalemler site_people.user_code ile eşleştiği için ÖNCE)', async () => {
    state.optionalTables = { push: true, reminders: true };
    state.reminderRows = 4;
    const result = await performAccountDeletion(12345);
    const update = sqls(/^UPDATE finance_reminder_items i SET /)[0];
    assert.ok(update, 'kalem güncellemesi çalıştı');
    assert.deepEqual(update.params, [12345]);
    assert.ok(update.sql.includes('email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL'));
    assert.ok(update.sql.includes("email_status = CASE WHEN i.email_status = 'pending' THEN 'resolved' ELSE i.email_status END"), 'bekleyen -> resolved (gönderilmez)');
    assert.ok(update.sql.includes('INNER JOIN site_people sp ON sp.id = i2.person_id AND sp.user_code = $1'), 'yalnız çağıranın hesabına bağlı kişi kayıtları');
    assert.ok(update.sql.includes('ORDER BY i2.run_id, i2.person_id FOR UPDATE OF i2'), 'işçiyle aynı kilit sırası (run_id, person_id)');
    const prefs = indexOf(/^DELETE FROM notification_preferences WHERE user_code = \$1$/);
    const pushDevices = indexOf(/^DELETE FROM push_devices WHERE id IN/);
    const pushOutbox = indexOf(/^DELETE FROM push_outbox WHERE id IN/);
    const reminders = indexOf(/^UPDATE finance_reminder_items i SET /);
    const unlink = indexOf(/^UPDATE site_people SET/);
    assert.ok(prefs >= 0 && prefs < pushDevices && pushDevices < pushOutbox && pushOutbox < reminders && reminders < unlink, [prefs, pushDevices, pushOutbox, reminders, unlink].join(','));
    assert.equal(result.summary.reminder_rows, 4);
    assert.equal(result.summary.push_devices, 2);
    assert.equal(result.summary.push_outbox, 3);
    const audit = log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql) && entry.params[3] === 'account.deleted');
    const details = JSON.parse(audit.params[7]);
    assert.equal(details.reminder_rows, 4);
    assert.ok(Object.entries(details).every(([key, value]) => key === 'previous_role' || typeof value === 'number'), 'denetim ayrıntısı yalnız sayı');
  });

  it('R16: gönderilmeden çözülen hatırlatma kalemlerinin DAİRE ARALIK kayıtları (finance_reminder_apartments) AYNI işlemde serbest bırakılır: yalnız etkilenen çalıştırmalar (tekil, artan), kalem güncellemesinden SONRA, kişi kopmadan ÖNCE; sent / pending kapsayan daire kaydı KORUNUR', async () => {
    state.optionalTables = { reminders: true };
    state.reminderRows = 3;
    state.reminderRunIds = [12, 9, 12];
    await performAccountDeletion(12345);
    const release = sqls(/^DELETE FROM finance_reminder_apartments fa WHERE /)[0];
    assert.ok(release, 'aralık kayıtları serbest bırakıldı');
    assert.deepEqual(release.params, [[9, 12]]);
    assert.ok(release.sql.includes("gone.email_status IN ('failed', 'resolved', 'skipped_pref', 'cancelled')"));
    assert.ok(release.sql.includes("keep.email_status IN ('sent', 'pending') AND fa2.apartment_id = ANY(keep.apartment_ids)"), 'gönderilmiş / bekleyen kalemin kapsadığı daire kaydı korunur');
    assert.ok(release.sql.includes('ORDER BY fa2.run_id, fa2.apartment_id FOR UPDATE OF fa2'), 'kilit sırası (run_id, apartment_id)');
    const items = indexOf(/^UPDATE finance_reminder_items i SET /);
    const at = indexOf(/^DELETE FROM finance_reminder_apartments fa WHERE /);
    const unlink = indexOf(/^UPDATE site_people SET/);
    assert.ok(items >= 0 && items < at && at < unlink, [items, at, unlink].join(','));
  });

  it('R16: kalem güncellenmediyse (kullanıcının hatırlatma kalemi yok) aralık kayıtlarına HİÇ dokunulmaz', async () => {
    state.optionalTables = { reminders: true };
    state.reminderRows = 0;
    state.reminderRunIds = [];
    await performAccountDeletion(12345);
    assert.equal(sqls(/^DELETE FROM finance_reminder_apartments/).length, 0);
  });

  it('R10: finance_reminder_items / push tabloları yoksa (eski şema) bu adımlar atlanır; silme yine tamamlanır', async () => {
    state.optionalTables = {};
    const result = await performAccountDeletion(12345);
    assert.equal(sqls(/^UPDATE finance_reminder_items/).length, 0);
    assert.equal(sqls(/^DELETE FROM push_/).length, 0);
    assert.equal(result.summary.reminder_rows, 0);
    assert.ok(log.some((entry) => entry.sql === 'COMMIT'));
  });

  it('parola özeti: her çağrıda farklı, geçerli bcrypt biçiminde DEĞİL (hiçbir parola eşleşmez)', async () => {
    const a = unusablePasswordHash();
    const b = unusablePasswordHash();
    assert.notEqual(a, b);
    assert.notEqual(a.length, 60);
    assert.equal(await bcrypt.compare('Dogru-Parola-1', a), false);
    assert.equal(await bcrypt.compare('', a), false);
  });

  it('kişisel iz silinir / kimliksizleşir: üyelikler, jetonlar, misafir başlığı, kapı kaydı adı + IP, duyuru okundu/e-posta, tercihler, adres tabanlı kayıtlar', async () => {
    await performAccountDeletion(12345);
    const text = log.map((e) => e.sql).join('\n');
    for (const fragment of [
      'DELETE FROM apartment_memberships WHERE user_code = $1',
      'DELETE FROM site_manager_sites WHERE manager_user_code = $1',
      'DELETE FROM site_memberships WHERE user_code = $1',
      'DELETE FROM join_requests WHERE user_code = $1',
      'DELETE FROM qr_access_tokens WHERE user_code = $1',
      'DELETE FROM door_access_overrides WHERE user_code = $1',
      'UPDATE guest_passes SET is_active = FALSE, title = $2 WHERE created_by_user_code = $1',
      'UPDATE door_access_logs SET user_name = $2, ip_address = NULL WHERE user_code = $1',
      'DELETE FROM notification_preferences WHERE user_code = $1',
      'DELETE FROM site_manager_invitations WHERE invited_by_user_code = $1',
      'DELETE FROM email_verifications WHERE LOWER(email) = LOWER($1)',
      'DELETE FROM pending_registrations WHERE LOWER(email) = LOWER($1)',
      'DELETE FROM account_data_exports WHERE user_code = $1',
      'UPDATE ota_update_jobs SET requested_by_email = NULL',
      'UPDATE module_requests SET requested_by_name = $2',
      'UPDATE module_requests SET decided_by_name = $2',
    ]) {
      assert.ok(text.includes(fragment), fragment);
    }
    assert.equal(log.some((e) => /\b(UPDATE|DELETE FROM|TRUNCATE)\s+audit_log\b/i.test(e.sql)), false, 'audit_log yalnızca EKLENİR (platform değişmezi)');
    const recipients = sqls(/^UPDATE announcement_recipients/)[0].sql;
    assert.ok(recipients.includes('read_at = NULL'));
    assert.ok(recipients.includes('email = NULL'));
    assert.ok(recipients.includes('email_hash = NULL'));
    assert.ok(recipients.includes("email_status = CASE WHEN r.email_status = 'pending' THEN 'none'"), 'bekleyen e-posta girdileri iptal edilir');
    assert.ok(recipients.includes('sp.user_code = $1'), 'yalnız çağıranın kişi satırlarına bağlı');
  });

  it('CRM kişi kaydı: pasif, hesaptan kopar, e-posta NULL; hesaptaki telefon / e-posta KOPYALANMAZ; ilişkiler biter, araçlar pasifleşir', async () => {
    await performAccountDeletion(12345);
    const people = sqls(/^UPDATE site_people SET/)[0];
    assert.ok(people.sql.includes('is_active = FALSE'));
    assert.ok(people.sql.includes('user_code = NULL'));
    assert.ok(people.sql.includes('email = NULL'));
    assert.equal(/phone/.test(people.sql), false, 'telefon dokunulmaz / kopyalanmaz');
    assert.equal(people.params[1], 'Ada Lovelace', 'yalnız ad (CRM_KEEP_NAME)');
    assert.ok(sqls(/^UPDATE apartment_residencies r SET is_current = FALSE/).length === 1);
    assert.ok(sqls(/^UPDATE vehicles v SET is_active = FALSE/).length === 1);
  });

  it('eski tekil sakin göstergesi olan daire: iletişim e-postası temizlenir; daire yöneticisi / gösterge devri çağrılır', async () => {
    await performAccountDeletion(12345);
    const clear = sqls(/^UPDATE apartments SET resident_email = NULL WHERE id = ANY/);
    assert.equal(clear.length, 1);
    assert.deepEqual(clear[0].params[0], [501]);
    // 501 (gösterge sahibi) ve 502 (APARTMENT_ADMIN) için devir sorguları çalışır
    const handovers = sqls(/FROM apartment_memberships WHERE apartment_id = \$1 AND user_code <> \$2 AND is_active = TRUE AND role = 'APARTMENT_ADMIN'/);
    assert.deepEqual(handovers.map((e) => e.params[0]).sort(), [501, 502]);
  });

  it('kimliksiz denetim kaydı: ad / e-posta / telefon YOK; yalnız önceki rol ve sayılar; kişi pasifleşme denetimi sistem adına', async () => {
    state.rowCounts = { '^DELETE FROM apartment_memberships': 3 };
    await performAccountDeletion(12345);
    const audit = log.find((e) => /^INSERT INTO audit_log/.test(e.sql) && e.params[3] === 'account.deleted');
    assert.ok(audit);
    assert.equal(audit.params[0], null, 'actor_user_code NULL');
    assert.equal(audit.params[1], 'Sistem');
    const details = JSON.parse(audit.params[7]);
    assert.equal(details.previous_role, 'apartment_owner');
    const serialized = JSON.stringify(audit.params);
    assert.equal(/ada@example|Lovelace|ada\.l/.test(serialized), false);
    const personAudit = sqls(/jsonb_build_object\('reason', 'account_deleted'/)[0];
    assert.ok(personAudit.sql.includes("'Sistem', 'system', 'person.deactivated'"));
  });

  it('açık site başvurusu geri çekilir ve denetlenir (sistem adına, gerekçe account_deleted)', async () => {
    state.pendingApplications = [{ id: '31', block_count: 2, apartment_count: 20, door_count: 3 }];
    const result = await performAccountDeletion(12345);
    assert.equal(result.summary.applications_cancelled, 1);
    assert.ok(sqls(/^UPDATE site_applications SET status = 'cancelled'/).length === 1);
    const cancelled = log.find((e) => /^INSERT INTO audit_log/.test(e.sql) && e.params[3] === 'site_application.cancelled');
    assert.ok(cancelled);
    assert.equal(JSON.parse(cancelled.params[7]).reason, 'account_deleted');
    // başvuru kilidi kullanıcı güncellemesinden SONRA (iptal akışıyla aynı yön: kullanıcı -> başvuru)
    assert.ok(indexOf(/^SELECT id, block_count, apartment_count, door_count FROM site_applications/) > indexOf(/^UPDATE users SET full_name = \$2/));
  });
});

describe('hesap silme: engeller ve hatalar', () => {
  it('süper kullanıcı: 409 SUPER_USER, hiçbir yazma yapılmaz, ROLLBACK', async () => {
    state.user.role = 'super_user';
    await assert.rejects(performAccountDeletion(12345), (error) => {
      assert.equal(error.code, 'ACCOUNT_DELETE_BLOCKED');
      assert.equal(error.statusCode, 409);
      assert.equal(error.extra.blockers[0].code, 'SUPER_USER');
      return true;
    });
    assert.equal(log.some((e) => /^(UPDATE|DELETE|INSERT)/.test(e.sql)), false);
    assert.ok(indexOf(/^ROLLBACK$/) >= 0);
    assert.equal(indexOf(/^COMMIT$/), -1);
  });

  it('son site yöneticisi: 409 LAST_SITE_MANAGER (site_id), kullanıcı güncellemesi GERİ ALINIR, yıkıcı adımlar çalışmaz', async () => {
    state.managed = [1000000001];
    state.lastManagerSites = [{ site_code: 1000000001, name: 'Gül Sitesi' }];
    await assert.rejects(performAccountDeletion(12345), (error) => {
      assert.equal(error.code, 'ACCOUNT_DELETE_BLOCKED');
      assert.deepEqual(error.extra.blockers.map((b) => [b.code, b.site_id]), [['LAST_SITE_MANAGER', 1000000001]]);
      return true;
    });
    assert.equal(sqls(/^DELETE FROM/).length, 0);
    assert.equal(indexOf(/^COMMIT$/), -1);
    assert.ok(indexOf(/^ROLLBACK$/) > indexOf(/^WITH managed AS/));
    assert.equal(hookCalls.mails.length + hookCalls.devices.length + hookCalls.sites.length, 0, 'engelde silme sonrası iş çalışmaz');
  });

  it('zaten silinmiş / olmayan hesap: 401 ACCOUNT_DELETED, ROLLBACK', async () => {
    state.user.deleted_at = new Date();
    await assert.rejects(performAccountDeletion(12345), (error) => error.code === 'ACCOUNT_DELETED' && error.statusCode === 401);
    state.user = null;
    await assert.rejects(performAccountDeletion(12345), (error) => error.code === 'ACCOUNT_DELETED');
    assert.equal(indexOf(/^COMMIT$/), -1);
  });

  it('kullanıcı satırı bu arada silindi / süper oldu (UPDATE satır döndürmedi): doğru hata', async () => {
    const original = pool.connect;
    let phase = 0;
    pool.connect = async () => {
      const client = await original();
      const query = client.query;
      client.query = async (text, params) => {
        const sql = norm(text);
        if (/^UPDATE users SET full_name = \$2/.test(sql)) {
          log.push({ sql, params });
          return ok();
        }
        if (/^SELECT role, deleted_at FROM users WHERE user_code = \$1/.test(sql)) {
          log.push({ sql, params });
          phase += 1;
          return ok(phase === 1 ? [{ role: 'super_user', deleted_at: null }] : []);
        }
        return query(text, params);
      };
      return client;
    };
    await assert.rejects(performAccountDeletion(12345), (error) => error.extra?.blockers?.[0]?.code === 'SUPER_USER');
    await assert.rejects(performAccountDeletion(12345), (error) => error.code === 'ACCOUNT_DELETED');
    pool.connect = original;
  });

  it('kapsam kilitler alınırken büyürse işlem GERİ ALINIR ve baştan denenir (2. denemede tamamlanır)', async () => {
    state.scopeGrowth = 1;
    const result = await performAccountDeletion(12345);
    assert.equal(begins, 2);
    assert.ok(indexOf(/^ROLLBACK$/) >= 0 && lastIndexOf(/^COMMIT$/) > indexOf(/^ROLLBACK$/));
    assert.equal(result.userCode, 12345);
  });

  it('kapsam sürekli büyürse 3 denemeden sonra 409 ACCOUNT_DELETE_BUSY (sonsuz döngü yok)', async () => {
    state.scopeGrowth = 99;
    await assert.rejects(performAccountDeletion(12345), (error) => error.code === 'ACCOUNT_DELETE_BUSY' && error.statusCode === 409);
    assert.equal(begins, 3);
    assert.equal(indexOf(/^COMMIT$/), -1);
  });

  it('nadir 40P01: TEK sefer baştan denenir; ikinci 40P01 hata olarak çıkar', async () => {
    state.failWith = ['40P01'];
    const result = await performAccountDeletion(12345);
    assert.equal(begins, 2);
    assert.equal(result.userCode, 12345);

    log = [];
    begins = 0;
    state.failWith = ['40P01', '40P01'];
    await assert.rejects(performAccountDeletion(12345), (error) => error.code === '40P01');
    assert.equal(begins, 2);
  });

  it('beklenmeyen hata: ROLLBACK ve olduğu gibi yukarı (route genel 500 üretir)', async () => {
    state.failWith = ['XX000'];
    await assert.rejects(performAccountDeletion(12345), (error) => error.code === 'XX000');
    assert.ok(indexOf(/^ROLLBACK$/) >= 0);
    assert.equal(indexOf(/^COMMIT$/), -1);
  });
});

describe('hesap silme: istek akışı (onay -> parola -> silme) ve silme sonrası işler', () => {
  it('confirm !== true: 400 CONFIRM_REQUIRED ve veritabanına HİÇ dokunulmaz (parola izleyicisi de ilerlemez)', async () => {
    for (const confirm of [undefined, false, 'true', 1, null]) {
      await assert.rejects(
        requestAccountDeletion({ authUser: USER, body: { current_password: 'Dogru-Parola-1', confirm } }),
        (error) => error.code === 'CONFIRM_REQUIRED' && error.statusCode === 400,
        String(confirm),
      );
    }
    assert.equal(log.length, 0);
    assert.equal(passwordChangeFailureTracker.size(), 0);
  });

  it('parola yok: 400 CURRENT_PASSWORD_REQUIRED; yanlış parola: 400 CURRENT_PASSWORD_INVALID; ikisinde de silme başlamaz', async () => {
    await assert.rejects(requestAccountDeletion({ authUser: USER, body: { confirm: true } }), (e) => e.code === 'CURRENT_PASSWORD_REQUIRED');
    await assert.rejects(requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'yanlis' } }), (e) => e.code === 'CURRENT_PASSWORD_INVALID');
    assert.equal(begins, 0);
  });

  it('5 yanlış parola sonrası 429 CURRENT_PASSWORD_LOCKED (PATCH /me ile paylaşılan izleyici); doğru parola da kilitliyken silmez', async () => {
    for (let i = 0; i < 4; i += 1) {
      await assert.rejects(requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'yanlis' } }), (e) => e.code === 'CURRENT_PASSWORD_INVALID');
    }
    await assert.rejects(requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'yanlis' } }), (e) => e.code === 'CURRENT_PASSWORD_LOCKED');
    await assert.rejects(requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'Dogru-Parola-1' } }), (e) => e.code === 'CURRENT_PASSWORD_LOCKED');
    assert.equal(begins, 0);
  });

  it('başarı: { deleted: true }; eski adrese bildirim (adres + ad), erişilen siteler ve cihazlar için anahtar döndürme', async () => {
    const result = await requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'Dogru-Parola-1' } });
    await settle();
    assert.deepEqual(result, { deleted: true });
    assert.equal(hookCalls.mails.length, 1);
    assert.equal(hookCalls.mails[0].to, 'ada@example.com');
    assert.equal(hookCalls.mails[0].fullName, 'Ada Lovelace');
    assert.deepEqual(hookCalls.devices.map((d) => d.deviceIds), [[11, 12]]);
    assert.deepEqual(hookCalls.sites.map((s) => s.siteCode).sort(), [1000000001, 1000000002]);
    assert.ok(hookCalls.sites.every((s) => s.reason === 'account_deleted'));
  });

  it('parola sayacı başarıdan sonra temizlenir; giriş kilitleri kullanıcının eski adresi / adıyla da temizlenir', async () => {
    await requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'Dogru-Parola-1' } });
    assert.equal(passwordChangeFailureTracker.size(), 0);
  });

  it('dahili daire hesabı (@ahbu.local), SMTP yok ya da geçersiz adres: bildirim GÖNDERİLMEZ ama silme başarılı', async () => {
    state.user.email = 'daire11@ahbu.local';
    await requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'Dogru-Parola-1' } });
    await settle();
    assert.equal(hookCalls.mails.length, 0);
    assert.equal(hookCalls.sites.length > 0, true, 'anahtar döndürme yine de çalışır');

    state.user = { ...USER };
    accountHooks.smtpConfigured = () => false;
    await requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'Dogru-Parola-1' } });
    await settle();
    assert.equal(hookCalls.mails.length, 0);
  });

  it('e-posta gönderimi başarısız: silme GERİ ALINMAZ (commit yapıldı), hata yalnız KOD olarak loglanır (adres / ad / ileti yok)', async () => {
    accountHooks.sendDeletedEmail = async () => {
      throw Object.assign(new Error('550 mailbox ada@example.com unavailable for Ada Lovelace'), { code: 'EENVELOPE' });
    };
    const result = await requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'Dogru-Parola-1' } });
    await settle();
    assert.deepEqual(result, { deleted: true });
    assert.ok(indexOf(/^COMMIT$/) >= 0);
    const logged = consoleErrors.join('\n');
    assert.ok(logged.includes('EENVELOPE'));
    assert.equal(/ada@example\.com|Lovelace|mailbox/.test(logged), false);
  });

  it('anahtar döndürme hatası silmeyi bozmaz ve yanıtı bekletmez (arka plan; asıl hata yalnız kodla loglanır)', async () => {
    accountHooks.background = (task) => {
      void task().catch((error) => console.error('[account] silme sonrasi islem basarisiz:', error?.code || error?.name || 'error'));
    };
    accountHooks.rotateTokensForDevices = async () => {
      throw Object.assign(new Error('mqtt down for ada@example.com'), { code: 'MQTT' });
    };
    const result = await requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'Dogru-Parola-1' } });
    assert.deepEqual(result, { deleted: true });
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(/ada@example\.com/.test(consoleErrors.join('\n')), false);
  });

  it('R1 B6 / anahtar döndürme yeniden deneme: cihaz döndürme 2 kez başarısız, 3. denemede başarılı -> bekleme 1 sn + 5 sn, denetim satırı YOK; çağrılar throwOnError ile yapılır', async () => {
    let attempts = 0;
    accountHooks.rotateTokensForDevices = async (arg) => {
      attempts += 1;
      hookCalls.devices.push(arg);
      if (attempts < 3) throw Object.assign(new Error('db down'), { code: 'ECONNRESET' });
      return 2;
    };
    await requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'Dogru-Parola-1' } });
    await settle();
    assert.equal(attempts, 3);
    assert.deepEqual(hookCalls.sleeps, [1000, 5000]);
    assert.ok(hookCalls.devices.every((arg) => arg.throwOnError === true && arg.reason === 'account_deleted'));
    assert.deepEqual(hookCalls.rotationAudits, []);
    assert.equal(consoleErrors.some((line) => /anahtar/.test(line)), false);
  });

  it('R1 B6 / anahtar döndürme TÜKENDİ: ilk deneme + 3 yeniden deneme (1 / 5 / 20 sn), sonra KİMLİKSİZ denetim account.key_rotation_failed (cihaz / site sayıları) + errorId\'li hata günlüğü; silme yine başarılı', async () => {
    let deviceAttempts = 0;
    accountHooks.rotateTokensForDevices = async () => {
      deviceAttempts += 1;
      throw Object.assign(new Error('mqtt down for ada@example.com'), { code: 'MQTT' });
    };
    const siteAttempts = new Map();
    accountHooks.rotateTokensForSite = async ({ siteCode }) => {
      siteAttempts.set(siteCode, (siteAttempts.get(siteCode) ?? 0) + 1);
      if (siteCode === 1000000002) throw Object.assign(new Error('x'), { code: '57014' }); // yalnız bu site hep başarısız
      return 1;
    };
    const result = await requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'Dogru-Parola-1' } });
    await settle();
    assert.deepEqual(result, { deleted: true });
    assert.equal(deviceAttempts, 4, 'ilk deneme + 3 yeniden deneme');
    assert.equal(siteAttempts.get(1000000002), 4);
    assert.equal(siteAttempts.get(1000000001), 1, 'başarılı site yeniden denenmez');
    assert.deepEqual(hookCalls.sleeps, [1000, 5000, 20000]);
    assert.equal(hookCalls.rotationAudits.length, 1);
    const [{ userCode, details }] = hookCalls.rotationAudits;
    assert.equal(userCode, 12345);
    assert.deepEqual(Object.keys(details).sort(), ['attempts', 'error_id', 'failed_device_count', 'failed_site_count']);
    assert.equal(details.failed_device_count, 2);
    assert.equal(details.failed_site_count, 1);
    assert.equal(details.attempts, 4);
    assert.match(details.error_id, /^[A-Za-z0-9-]{6,}$/);
    const logged = consoleErrors.filter((line) => /anahtar/.test(line));
    assert.equal(logged.length, 1);
    assert.ok(logged[0].includes(`errorId=${details.error_id}`), 'günlük ve denetim AYNI errorId\'yi taşır');
    assert.ok(/cihaz=2 site=1/.test(logged[0]));
    assert.equal(/ada@example|Lovelace|mqtt down/.test(JSON.stringify(details) + consoleErrors.join('\n')), false, 'kişisel veri / hata iletisi yok');
  });

  it('anahtar döndürme: denetim satırı da yazılamazsa asıl akış etkilenmez (yalnız kod loglanır); rotationBackoffMs boşsa tek deneme', async () => {
    accountHooks.rotateTokensForDevices = async () => {
      throw new Error('boom');
    };
    accountHooks.recordRotationFailure = async () => {
      throw Object.assign(new Error('audit down ada@example.com'), { code: '57P01' });
    };
    accountHooks.rotationBackoffMs = [];
    const outcome = await rotateKeysWithRetry({ userCode: 12345, deviceIds: [11], siteCodes: [] });
    assert.deepEqual(outcome, { failedDevices: 1, failedSites: 0 });
    assert.deepEqual(hookCalls.sleeps, []);
    assert.ok(consoleErrors.some((line) => /denetim satiri yazilamadi: 57P01/.test(line)));
    assert.equal(/ada@example/.test(consoleErrors.join('\n')), false);
  });

  it('anahtar döndürme: hedef yoksa hiçbir şey çağrılmaz; sorunsuz akışta bekleme ve denetim yok', async () => {
    assert.deepEqual(await rotateKeysWithRetry({ userCode: 12345, deviceIds: [], siteCodes: [] }), { failedDevices: 0, failedSites: 0 });
    assert.deepEqual(await rotateKeysWithRetry({ userCode: 12345, deviceIds: [11, 12], siteCodes: [1000000001] }), { failedDevices: 0, failedSites: 0 });
    assert.deepEqual(hookCalls.sleeps, []);
    assert.deepEqual(hookCalls.rotationAudits, []);
    assert.equal(hookCalls.devices.length, 1);
    assert.equal(hookCalls.sites.length, 1);
  });

  it('local_token_service: throwOnError varsayılan KAPALI (diğer çağıranların davranışı değişmedi: hata yutulur, 0 döner); AÇIKKEN hata yukarı çıkar', async () => {
    const source = (await import('node:fs')).readFileSync(new URL('../src/services/local_token_service.js', import.meta.url), 'utf8');
    assert.match(source, /rotateTokensForDevices\(\{ deviceIds, reason, throwOnError = false \}\)/);
    assert.match(source, /rotateTokensForSite\(\{ siteCode, reason, throwOnError = false \}\)/);
    assert.equal((source.match(/if \(throwOnError\) \{\s+throw error;/g) ?? []).length, 2);
  });

  it('silme sırasında konsola kişisel veri yazılmaz (başarılı akış)', async () => {
    await requestAccountDeletion({ authUser: USER, body: { confirm: true, current_password: 'Dogru-Parola-1' } });
    await settle();
    assert.equal(/ada@example|Lovelace|ada\.l|Dogru-Parola/.test(consoleErrors.join('\n')), false);
  });
});

describe('hesap silme: önizleme', () => {
  function previewHandlers() {
    pool.query = async (text, params) => {
      const sql = norm(text);
      log.push({ sql, params: params ?? [], pool: true });
      if (/^SELECT id, role, deleted_at FROM users/.test(sql)) return ok([{ id: 77, role: state.user?.role ?? 'individual', deleted_at: state.user?.deleted_at ?? null }]);
      if (/^SELECT \(SELECT COUNT\(\*\) FROM apartment_memberships/.test(sql)) {
        return ok([{ apartment_links: 1, site_links: 1, active_passes: 2, active_qr: 1, pending_applications: 1, closed_applications: 1, devices: 1, has_consents: true }]);
      }
      return handle(sql, params ?? []);
    };
  }

  it('engel yok: can_delete true; will_remove / will_keep dolu (sayılar yalnız kendi kayıtlarından); yazma / kilit yok', async () => {
    previewHandlers();
    const preview = await previewAccountDeletion(USER);
    assert.equal(preview.can_delete, true);
    assert.deepEqual(preview.blockers, []);
    assert.ok(preview.will_remove.length >= 4 && preview.will_keep.length >= 3);
    assert.ok(preview.will_remove.some((line) => /iptal/.test(line) && /\(2\)/.test(line)), 'etkin misafir geçişi sayısı');
    assert.ok(preview.will_remove.some((line) => /başvuru/.test(line)));
    assert.ok(preview.will_keep.some((line) => /onay/.test(line)), 'user_consents varsa onay kaydı saklama satırı');
    assert.equal(log.some((e) => /FOR UPDATE|^UPDATE|^DELETE|^INSERT|advisory/.test(e.sql)), false);
    assert.equal(JSON.stringify(preview).includes('ada@example.com'), false);
  });

  it('R6: will_keep / will_remove metinleri yasal belgeyle (server/legal/account_deletion.md) TUTARLI: denetim adı değişmez ve "yalnız platform yöneticisi görür" DENMEZ (site yöneticisi / kurul geçmiş ekranında görür); yönetim girişli telefon / not, araç notu, çıkış özeti, kapanmış başvuru, çevrimdışı kapı kaydı adı', async () => {
    previewHandlers();
    const preview = await previewAccountDeletion(USER);
    const keep = preview.will_keep.join('\n');
    const remove = preview.will_remove.join('\n');
    // denetim: ad DEĞİŞMEDEN; platform yöneticisi okur AMA site yöneticisi / kurul da geçmişi görür (people_history_service / people_access)
    assert.match(keep, /denetim\) kayıtları .* adınız DEĞİŞTİRİLMEDEN saklanır/);
    assert.match(keep, /platform yöneticisi okur/);
    assert.match(keep, /sitenin yöneticisi ve kurul üyeleri de geçmiş ekranında görebilir/);
    assert.equal(/yalnız platform yöneticisi görür/i.test(keep + remove), false, 'eski yanlış ifade yok');
    assert.match(keep, /hesabı olmayan kişilerin eski ve yeni adları, araç plakaları/);
    // CRM: yönetimin girdiği telefon + not, araç notu; hesaptaki telefon kopyalanmaz
    assert.match(keep, /yönetimin kişi kaydınıza girdiği telefon numarası ve notlar ve araç kaydınıza girdiği not/);
    assert.match(keep, /hesabınızdaki telefon numarası kopyalanmaz/);
    // kapı kayıtları: 30 gün + çevrimdışı senkron kayıt adı
    assert.match(keep, /30 gün sonra otomatik silinir; kapı cihazından senkronlanan çevrimdışı geçiş kayıtları/);
    assert.match(keep, /ad 30 günlük süre dolana kadar kalabilir/);
    // abonelikten çıkma özeti, kimliksiz hesap kaydı, kapanmış başvuru, onay kaydı
    assert.match(keep, /geri döndürülemez özeti listede kalır/);
    assert.match(keep, /"Silinmiş Kullanıcı" adlı, ad, e-posta veya telefon içermeyen bir hesap kaydı/);
    assert.match(keep, /sonuçlanmış \(onaylanmış veya reddedilmiş\) site başvurularınızdaki/);
    // silinenler: kapı kaydındaki ad + IP, modül talebi adı, doğrulama kayıtları, katılım başvuruları / davetler
    assert.match(remove, /kapı geçiş kayıtlarındaki adınız "Silinmiş Kullanıcı" ile değiştirilir ve IP adresiniz silinir/);
    assert.match(remove, /modül talebi kayıtlarındaki adınız/);
    assert.match(remove, /doğrulama kodu ve bekleyen kayıt kayıtları silinir/);
    assert.match(remove, /Katılım başvurularınız ve gönderdiğiniz yönetici davetleri silinir/);
    // süre / dayanak iddiası yok (yasal belgede karar bekleyen maddeler)
    assert.equal(/\d+ (yıl|ay)\b/.test(keep), false, 'saklama süresi uydurulmaz');
    // kişisel veri yok
    assert.equal(JSON.stringify(preview).includes('Ada'), false);
  });

  it('R6: sayaç yoksa koşullu satırlar çıkmaz: kapanmış başvuru satırı yalnız closed_applications > 0 iken, bekleyen başvuru / cihaz / onay yalnız karşılığı varken', async () => {
    previewHandlers();
    const original = pool.query;
    pool.query = async (text, params) => {
      const sql = norm(text);
      if (/^SELECT \(SELECT COUNT\(\*\) FROM apartment_memberships/.test(sql)) {
        return ok([{ apartment_links: 0, site_links: 0, active_passes: 0, active_qr: 0, pending_applications: 0, closed_applications: 0, devices: 0, has_consents: false }]);
      }
      return original(text, params);
    };
    const preview = await previewAccountDeletion(USER);
    const all = preview.will_keep.concat(preview.will_remove).join('\n');
    assert.equal(/sonuçlanmış/.test(all), false);
    assert.equal(/Bekleyen site başvurunuz/.test(all), false);
    assert.equal(/cihazların/.test(all), false);
    assert.equal(/yasal onayların/.test(all), false);
  });

  it('R10/R9: önizleme — silinenler: telefon bildirimi cihazları (sayı) + bekleyen aidat hatırlatma adresi; saklananlar: yüklenen belgeler ("Silinmiş Kullanıcı" yükleyen), makbuz / tahsilat kayıtları KMK / VUK gereği DEĞİŞTİRİLMEDEN (ad anlık görüntüsü anonimleştirilmez)', async () => {
    previewHandlers();
    state.optionalTables = { push: true, documents: true, reminders: true };
    state.optionalCounts = { pushDevices: 2, uploadedDocuments: 3, pendingReminders: 1 };
    const preview = await previewAccountDeletion(USER);
    const remove = preview.will_remove.join('\n');
    const keep = preview.will_keep.join('\n');
    assert.match(remove, /Telefon bildirimi için kayıtlı cihazlarınız \(2\) ve bunların bildirim jetonları ile bekleyen telefon bildirimleriniz silinir/);
    assert.match(remove, /bekleyen aidat hatırlatma e-postalarının \(1\) kayıtlarındaki e-posta adresiniz silinir; bu hatırlatmalar gönderilmez/);
    assert.match(keep, /Yüklediğiniz belgeler \(3 dosya sürümü\) site yönetiminde kalır \(belgeler siteye aittir\); yükleyen adı "Silinmiş Kullanıcı" olarak görünür/);
    assert.match(keep, /Makbuz ve tahsilat kayıtları .*yasal mali kayıt saklama yükümlülükleri gereği DEĞİŞTİRİLMEDEN saklanır; makbuz anlık görüntüsündeki ad anonimleştirilmez/);
    assert.equal(/\d+ (yıl|ay)\b/.test(keep), false, 'saklama süresi uydurulmaz');
    assert.equal(JSON.stringify(preview).includes('Ada'), false);
  });

  it('R10: sayaçlar 0 / tablo yoksa bu satırlar çıkmaz (belge, push, hatırlatma); makbuz satırı üyeliği olmayan hesapta çıkmaz', async () => {
    previewHandlers();
    const original = pool.query;
    pool.query = async (text, params) => {
      const sql = norm(text);
      if (/^SELECT \(SELECT COUNT\(\*\) FROM apartment_memberships/.test(sql)) {
        return ok([{ apartment_links: 0, site_links: 0, active_passes: 0, active_qr: 0, pending_applications: 0, closed_applications: 0, devices: 0, has_consents: false }]);
      }
      return original(text, params);
    };
    state.optionalTables = { push: true, documents: true, reminders: true };
    state.optionalCounts = { pushDevices: 0, uploadedDocuments: 0, pendingReminders: 0 };
    let preview = await previewAccountDeletion(USER);
    let all = preview.will_keep.concat(preview.will_remove).join('\n');
    assert.equal(/Telefon bildirimi için|bekleyen aidat hatırlatma|Yüklediğiniz belgeler|Makbuz ve tahsilat/.test(all), false);
    state.optionalTables = {};
    state.optionalCounts = { pushDevices: 5, uploadedDocuments: 5, pendingReminders: 5 };
    preview = await previewAccountDeletion(USER);
    all = preview.will_keep.concat(preview.will_remove).join('\n');
    assert.equal(/Telefon bildirimi için|bekleyen aidat hatırlatma|Yüklediğiniz belgeler/.test(all), false, 'tablo yoksa sayılmaz (katalog bayrağı)');
  });

  it('süper kullanıcı: SUPER_USER engeli; son yönetici: LAST_SITE_MANAGER + site_id', async () => {
    previewHandlers();
    state.user.role = 'super_user';
    let preview = await previewAccountDeletion(USER);
    assert.equal(preview.can_delete, false);
    assert.deepEqual(preview.blockers.map((b) => b.code), ['SUPER_USER']);

    state.user.role = 'site_manager';
    state.lastManagerSites = [{ site_code: 1000000001, name: 'Gül Sitesi' }];
    preview = await previewAccountDeletion(USER);
    assert.equal(preview.can_delete, false);
    assert.deepEqual(preview.blockers.map((b) => [b.code, b.site_id]), [['LAST_SITE_MANAGER', 1000000001]]);
  });

  it('silinmiş hesap: 401 ACCOUNT_DELETED; kullanıcı kodu çözülemeyen kimlik: 401', async () => {
    previewHandlers();
    state.user.deleted_at = new Date();
    await assert.rejects(previewAccountDeletion(USER), (e) => e.code === 'ACCOUNT_DELETED');
    await assert.rejects(previewAccountDeletion({}), (e) => e.code === 'ACCOUNT_DELETED');
  });

  it('findLastManagerSites: tek küme sorgusu; kullanıcı kodu parametre, başka aktif yönetici / üye koşulları aktif ve silinmemiş hesaba bağlı', async () => {
    const queries = [];
    const rows = await findLastManagerSites(
      {
        query: async (text, params) => {
          queries.push({ sql: norm(text), params });
          return ok([{ site_code: '1000000007', name: 'Lale' }]);
        },
      },
      12345,
    );
    assert.deepEqual(rows, [{ site_code: 1000000007, name: 'Lale' }]);
    assert.equal(queries.length, 1, 'site başına döngü yok (ölçek)');
    assert.deepEqual(queries[0].params, [12345]);
    assert.ok(queries[0].sql.includes('mu.is_active = TRUE AND mu.deleted_at IS NULL'));
    assert.ok(queries[0].sql.includes('ms.manager_user_code <> $1'));
    assert.ok(queries[0].sql.includes("sm.role NOT IN ('SITE_OWNER', 'SITE_ADMIN')"));
  });
});
