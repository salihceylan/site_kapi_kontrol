// R7: kullanıcı satırına yazan HER `UPDATE users` ifadesi silinmiş (kimliksizleştirilmiş) hesabı dışlar ya da gözden geçirilmiş güvenli listededir.
//
// Neden: hesap silme tombstone satırını bırakır (rol individual, parola özeti kullanılamaz, jeton alanları NULL, pasif). Silmeyle yarışan bir yazıcı
// (örn. bcrypt.hash beklerken commit eden silme) tombstone'a gerçek parola özeti / rol / jeton yazarsa bu değişmezler bozulur. Yeni bir `UPDATE users`
// eklenirse bu test düşer: ya `deleted_at IS NULL` ekleyin ya da neden güvenli olduğunu aşağıdaki listeye yazın.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createSiteWithStructure } from '../src/services/site_setup_core.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const srcRoot = path.join(here, '..', 'src');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = path.join(dir, name);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else if (name.endsWith('.js')) out.push(full);
  }
  return out;
}

/** Yorum satırları hariç her `UPDATE users` ifadesini (kapanış ters tırnağa kadar) döndürür. */
function userUpdates() {
  const found = [];
  for (const file of walk(srcRoot)) {
    const text = readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
    const lines = text.split('\n');
    let offset = 0;
    for (const line of lines) {
      const at = line.search(/UPDATE users\b/);
      if (at >= 0 && !/^\s*(\/\/|\*|\/\*)/.test(line)) {
        const start = offset + at;
        const end = text.indexOf('`', start);
        found.push({ file: path.relative(srcRoot, file).replace(/\\/g, '/'), sql: norm(text.slice(start, end < 0 ? start + 400 : end)) });
      }
      offset += line.length + 1;
    }
  }
  return found;
}

// `deleted_at IS NULL` OLMAYAN ama güvenli olduğu gözden geçirilmiş yazıcılar (dosya + ifade başlangıcı + NEDEN).
const REVIEWED_SAFE = [
  {
    file: 'modules/people_service.js',
    startsWith: 'UPDATE users SET is_active = FALSE WHERE user_code = $1 AND email LIKE',
    reason: 'yalnız dahili daire hesabı (@ahbu.local) pasifleştirir; tombstone e-postası @deleted.invalid olduğundan eşleşmez, is_active=FALSE zaten tombstone durumudur',
  },
  {
    file: 'routes/admin_routes.js',
    startsWith: 'UPDATE users SET approval_status = $1, is_active = $2',
    reason: "WHERE role = 'site_manager': silme rolü AYNI UPDATE'te 'individual' yapar, silme sonrası satır eşleşmez; silme commit etmediyse satır kilidi yüzünden bekler",
  },
  {
    file: 'services/membership_service.js',
    startsWith: 'UPDATE users SET email_verified = TRUE WHERE LOWER(email) = LOWER($1)',
    reason: 'e-posta ile anahtarlı: silme e-postayı tombstone adresiyle değiştirir, silme sonrası eşleşmez (statement-düzeyi kilit + yeniden değerlendirme)',
  },
  {
    file: 'services/membership_service.js',
    startsWith: "UPDATE users SET role = 'site_manager' WHERE user_code = $1",
    reason: 'aynı işlemde az önce e-posta doğrulama UPDATE\'i / INSERT ile satır kilitlenmiştir; silme bu işlem bitene dek bekler',
  },
  {
    file: 'services/site_service.js',
    startsWith: "UPDATE users SET role = 'site_manager', updated_at = NOW() WHERE user_code = $1",
    reason: 'inviteSiteManager: aynı işlemde hesap `deleted_at IS NULL ... FOR KEY SHARE` ile kilitlenmiştir (silme bekler)',
  },
  {
    file: 'services/site_service.js',
    startsWith: "UPDATE users SET role = $2, updated_at = NOW() WHERE user_code = $1 AND role = 'site_manager'",
    reason: "removeSiteManager: hesap FOR NO KEY UPDATE ile kilitli; ayrıca WHERE role = 'site_manager' tombstone'u (rol individual) dışlar",
  },
];

describe('UPDATE users yazıcıları: silinmiş hesabı dışlar ya da gözden geçirilmiş güvenli listede', () => {
  const all = userUpdates();
  const unguarded = all.filter((entry) => !/deleted_at IS NULL/.test(entry.sql));

  it('tarama çalışıyor (en az 12 yazıcı bulundu) ve kritik yazıcılar korumalı', () => {
    assert.ok(all.length >= 12, `bulunan ${all.length}`);
    const guarded = (needle) => all.filter((entry) => entry.sql.includes(needle) && /deleted_at IS NULL/.test(entry.sql)).length;
    // Aynı ifade başlangıcı iki yazıcıda: daire sakini change-password (membership_service) ve daire PIN'i sıfırlama (apartment_service, migration 051).
    assert.equal(guarded('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE user_code = $2'), 2, 'daire sakini change-password + daire PIN sıfırlama');
    assert.ok(all.some((entry) => entry.file === 'services/membership_service.js' && entry.sql.startsWith('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE user_code = $2 AND deleted_at IS NULL')), 'daire sakini change-password');
    assert.ok(all.some((entry) => entry.file === 'services/apartment_service.js' && entry.sql.startsWith('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE user_code = $2 AND deleted_at IS NULL')), 'daire PIN sıfırlama');
    assert.equal(guarded('UPDATE users SET full_name = $1, password_hash = $2, updated_at = NOW() WHERE user_code = $3'), 1, 'doğrulanmamış hesap kimlik bilgileri');
    assert.equal(guarded('UPDATE users SET password_reset_token_hash = $1'), 1, 'parola sıfırlama isteği');
    assert.ok(all.some((entry) => entry.file === 'services/user_service.js' && /email_verification_code_hash/.test(entry.sql) && /deleted_at IS NULL/.test(entry.sql)));
    assert.ok(all.some((entry) => entry.file === 'services/site_setup_core.js' && /deleted_at IS NULL/.test(entry.sql)));
    assert.ok(all.some((entry) => entry.file === 'services/apartment_service.js' && /deleted_at IS NULL/.test(entry.sql)));
    assert.ok(all.some((entry) => entry.file === 'routes/auth_routes.js' && /password_reset_token_hash/.test(entry.sql) && /deleted_at IS NULL/.test(entry.sql)));
  });

  it('korumasız her yazıcı gözden geçirilmiş listede ve liste güncel (bayat kayıt yok)', () => {
    const unreviewed = unguarded.filter((entry) => !REVIEWED_SAFE.some((safe) => safe.file === entry.file && entry.sql.startsWith(safe.startsWith)));
    assert.deepEqual(unreviewed, [], 'bu UPDATE users ifadelerine `deleted_at IS NULL` ekleyin ya da güvenli olduğunu REVIEWED_SAFE listesine gerekçeyle yazın');
    for (const safe of REVIEWED_SAFE) {
      const matches = unguarded.filter((entry) => entry.file === safe.file && entry.sql.startsWith(safe.startsWith));
      assert.equal(matches.length, 1, `güvenli liste kaydı tam 1 ifadeyle eşleşmeli: ${safe.file} :: ${safe.startsWith}`);
      assert.ok(safe.reason.length > 40);
    }
  });
});

describe('site kurulum çekirdeği: silinmiş hesaba rol yazılmaz, site kurulmaz', () => {
  const input = {
    siteName: 'S', address: null, city: null, district: null,
    blocks: [{ name: 'A', apartmentCount: 2, sortOrder: 1 }], doors: [{ name: 'K', doorIndex: 1 }],
    totalBlockCount: 1, totalApartmentCount: 2, totalDoorCount: 1,
  };
  const makeClient = (roleUpdateRows) => {
    const log = [];
    return {
      log,
      query: async (text, params = []) => {
        const sql = norm(text);
        log.push({ sql, params });
        if (/^INSERT INTO sites/.test(sql)) return { rows: [{ id: 900, name: 'S', management_type: 'apartment_site' }], rowCount: 1 };
        if (/^INSERT INTO site_blocks/.test(sql)) return { rows: [{ id: 31, site_code: 900, block_name: 'A', sort_order: 1 }], rowCount: 1 };
        if (/^INSERT INTO site_doors/.test(sql)) return { rows: [{ id: 41, site_code: 900, door_name: 'K', door_index: 1, is_active: true }], rowCount: 1 };
        if (/^UPDATE users SET role/.test(sql)) return { rows: [], rowCount: roleUpdateRows };
        return { rows: [], rowCount: 0 };
      },
    };
  };

  it('rol UPDATE `WHERE id = $1 AND deleted_at IS NULL`; satır dönmezse 401 ACCOUNT_DELETED ile durur (abonelik satırı dahil sonraki adımlar çalışmaz; çağıran ROLLBACK eder)', async () => {
    const client = makeClient(0);
    await assert.rejects(
      createSiteWithStructure(client, { user: { id: 7, user_code: 48213, role: 'site_manager' }, input, managementType: 'apartment_site' }),
      (error) => error.statusCode === 401 && error.code === 'ACCOUNT_DELETED' && error.expose === true,
    );
    const update = client.log.find((entry) => /^UPDATE users SET role/.test(entry.sql));
    assert.equal(update.sql, "UPDATE users SET role = 'site_manager' WHERE id = $1 AND deleted_at IS NULL");
    assert.deepEqual(update.params, [7]);
    assert.equal(client.log.some((entry) => /^INSERT INTO site_subscriptions|^INSERT INTO site_blocks/.test(entry.sql)), false, 'kurulum rol adımında kesildi');
  });

  it('hesap varsa kurulum aynen sürer; süper kullanıcıda rol UPDATE\'i yok', async () => {
    const client = makeClient(1);
    await createSiteWithStructure(client, { user: { id: 7, user_code: 48213, role: 'individual' }, input, managementType: 'apartment_site' });
    assert.ok(client.log.some((entry) => /^INSERT INTO site_subscriptions/.test(entry.sql)));
    const superClient = makeClient(0);
    await createSiteWithStructure(superClient, { user: { id: 1, user_code: 1, role: 'super_user' }, input, managementType: 'apartment_site' });
    assert.equal(superClient.log.some((entry) => /^UPDATE users/.test(entry.sql)), false);
  });
});

describe('diğer yazıcıların SQL korumaları', () => {
  const read = (relative) => norm(readFileSync(path.join(srcRoot, relative), 'utf8'));

  it('doğrulanmamış hesap kimlik bilgileri, e-posta doğrulama kodu ve dahili daire hesabı güncellemesi silinmişi dışlar', () => {
    assert.ok(read('services/membership_rules.js').includes('WHERE user_code = $3 AND email_verified = FALSE AND deleted_at IS NULL AND NOT EXISTS'));
    assert.ok(read('services/user_service.js').includes('email_verified = FALSE WHERE user_code = $3 AND deleted_at IS NULL'));
    const apartment = read('services/apartment_service.js');
    assert.ok(apartment.includes('SELECT email FROM users WHERE user_code = $1 AND deleted_at IS NULL LIMIT 1'));
    assert.ok(apartment.includes('is_active = $5 WHERE user_code = $6 AND deleted_at IS NULL'));
  });
});
