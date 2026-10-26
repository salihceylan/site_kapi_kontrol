// Yönetim kadrosu / davet / rehber (058) şeması ve saf kurallar (DB'siz).
// Gerçek PostgreSQL doğrulaması bu işte yapılmadı (kural: yalnız ilgili birim testleri); kullanıcı denemesinden sonra qa_platform_pg ile eklenecek.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { TEAM_DDL, TEAM_DDL_ORDER, ensureTeamSchema, schemaTuning } from '../src/modules/team_schema.js';
import { DUTIES, membershipRoleForDuty, normalizeTrMobile, parseDutyInput } from '../src/modules/team_service.js';
import { getInviteSummary, hashToken } from '../src/modules/person_invite_service.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '058_team_and_invitations.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

const normalizeSql = (text) => text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

function splitStatements(sqlText) {
  const text = sqlText.replace(/--.*$/gm, ' ');
  const statements = [];
  let current = '';
  let inDollar = false;
  for (let i = 0; i < text.length; i += 1) {
    if (text.startsWith('$$', i)) {
      inDollar = !inDollar;
      current += '$$';
      i += 1;
      continue;
    }
    if (text[i] === ';' && !inDollar) {
      if (current.trim() !== '') statements.push(normalizeSql(current));
      current = '';
      continue;
    }
    current += text[i];
  }
  if (current.trim() !== '') statements.push(normalizeSql(current));
  return statements;
}

describe('migration 058', () => {
  it('numarası yinelenmez, çalıştırıcı için güvenli', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    assert.equal(list.filter((m) => m.number === 58).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('TEAM_DDL migration ile AYNI ifadeler, AYNI sıra; ekleyici ve idempotent', () => {
    const statements = splitStatements(MIGRATION);
    assert.equal(statements.length, 18);
    assert.deepEqual(statements, TEAM_DDL_ORDER.map((n) => normalizeSql(TEAM_DDL[n])));
    assert.ok(!/\b(DROP|TRUNCATE|UPDATE|DELETE FROM|INSERT INTO)\b/i.test(normalizeSql(MIGRATION)));
  });

  it('açılış: DDL dev blokta DEĞİL, ensureTeamSchema people_v1 öncesi çağrılır', () => {
    assert.equal(/CREATE TABLE IF NOT EXISTS (site_team_duties|person_invitations|site_directory_contacts)\b/.test(DB_SOURCE), false);
    // ust tablo yoksa (platform oncesi kesilmis sema) adim ertelenir: ensureDeferred sarmalayicisi 42P01'i yutar, baska hatayi firlatir
    const call = DB_SOURCE.indexOf("await ensureDeferred('058 yonetim kadrosu', () => ensureTeamSchema(client));");
    assert.ok(call > 0, 'ensureTeamSchema ensureDeferred ile cagrilir');
    assert.ok(call > DB_SOURCE.indexOf('await ensurePlatformRulesSchema(client);'));
    assert.ok(call < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });

  it('kısıtlar: tek etkin görev, tek bekleyen davet, belirteç özeti benzersiz, bekleyen davette e-posta + özet zorunlu', () => {
    assert.match(normalizeSql(TEAM_DDL.dutiesActiveIndex), /UNIQUE INDEX .* \(person_id\) WHERE ended_at IS NULL/);
    assert.match(normalizeSql(TEAM_DDL.invitationsPendingIndex), /UNIQUE INDEX .* \(person_id\) WHERE status = 'pending'/);
    assert.match(normalizeSql(TEAM_DDL.invitationsTokenIndex), /UNIQUE INDEX .* \(token_hash\) WHERE token_hash IS NOT NULL/);
    assert.ok(normalizeSql(TEAM_DDL.invitationsTable).includes("status <> 'pending' OR (email IS NOT NULL AND token_hash IS NOT NULL)"));
    assert.ok(normalizeSql(TEAM_DDL.dutiesTable).includes("duty <> 'other' OR title IS NOT NULL"));
  });

  it('her şey varsa ensure yalnız tek katalog sorgusu gönderir', async () => {
    const queries = [];
    const client = {
      async query(text) {
        queries.push(text);
        return {
          rows: [{
            tables: ['site_team_duties', 'site_directory_contacts', 'person_invitations'],
            indexes: ['uq_site_team_duties_active', 'idx_site_team_duties_site', 'idx_site_directory_contacts_site', 'uq_person_invitations_pending', 'uq_person_invitations_token', 'idx_person_invitations_email'],
            fks: [
              'site_team_duties.site_team_duties_site_code_fkey', 'site_team_duties.site_team_duties_person_id_fkey', 'site_team_duties.site_team_duties_created_by_fkey',
              'site_directory_contacts.site_directory_contacts_site_code_fkey', 'site_directory_contacts.site_directory_contacts_created_by_fkey',
              'person_invitations.person_invitations_site_code_fkey', 'person_invitations.person_invitations_person_id_fkey',
              'person_invitations.person_invitations_invited_by_fkey', 'person_invitations.person_invitations_accepted_user_code_fkey',
            ],
          }],
        };
      },
    };
    await ensureTeamSchema(client);
    assert.equal(queries.length, 1);
  });
});

describe('kadro kuralları', () => {
  it('görev -> üyelik rolü: kurul ve denetçi BOARD_MEMBER, diğerleri STAFF', () => {
    assert.deepEqual(DUTIES.map(membershipRoleForDuty), ['BOARD_MEMBER', 'BOARD_MEMBER', 'STAFF', 'STAFF', 'STAFF', 'STAFF']);
  });

  it('telefon normalleştirme', () => {
    assert.equal(normalizeTrMobile('0532 123 45 67'), '+905321234567');
    assert.equal(normalizeTrMobile('+90 (532) 123-45-67'), '+905321234567');
    assert.equal(normalizeTrMobile('5321234567'), '+905321234567');
    assert.equal(normalizeTrMobile('112'), null);
    assert.equal(normalizeTrMobile('abc'), null);
  });

  it('görev gövdesi doğrulaması', () => {
    assert.deepEqual(parseDutyInput({ duty: 'doorman' }), { duty: 'doorman', title: null, publicPhone: null, showInDirectory: true });
    assert.throws(() => parseDutyInput({ duty: 'x' }), { code: 'DUTY_INVALID' });
    assert.throws(() => parseDutyInput({ duty: 'other' }), { code: 'INVALID_BODY' });
    assert.equal(parseDutyInput({ duty: 'other', title: ' Bahçıvan ', public_phone: '0532 123 45 67', show_in_directory: false }).title, 'Bahçıvan');
    assert.throws(() => parseDutyInput({ duty: 'doorman', public_phone: '123' }), { code: 'INVALID_BODY' });
    assert.throws(() => parseDutyInput({ duty: 'doorman', show_in_directory: 'yes' }), { code: 'INVALID_BODY' });
  });
});

describe('davet', () => {
  it('belirteç özeti SHA-256 hex; biçimi bozuk belirteç veritabanına gitmeden tek tip INVITE_INVALID', async () => {
    assert.match(hashToken('a'.repeat(64)), /^[0-9a-f]{64}$/);
    await assert.rejects(() => getInviteSummary('kisa'), { code: 'INVITE_INVALID', statusCode: 400 });
    await assert.rejects(() => getInviteSummary(undefined), { code: 'INVITE_INVALID' });
  });
});
