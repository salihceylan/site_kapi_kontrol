// Site yoneticisinin ISLEM KAYITLARI (P2-19; DB'siz): eylem katalogu ve gorunurluk, sorgu dogrulama, satir sunumu (kisisel veri asgari),
// SITE KAPSAMI (baska sitenin kaydi gorunmez), erisim matrisi (sakin / kurul / gorevli / baska site yoneticisi 403), tarih / tur / eylem
// suzgecleri ve sayfalama. Gercek PostgreSQL davranisi bu testte DEGIL (sahte DB, SQL parametrelerini yorumlar); sabit sorgunun gercek
// PG ile dogrulamasi scripts/qa_site_audit_log.mjs'tedir.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import {
  SITE_AUDIT_CATEGORIES,
  SITE_AUDIT_CATEGORY_KEYS,
  SITE_AUDIT_HIDDEN_ACTIONS,
  SITE_AUDIT_HIDDEN_PREFIXES,
  SITE_AUDIT_LABELS,
  actionLabelOf,
  categoryOfAction,
  isHiddenAction,
  isVisibleToManager,
  likePrefixPattern,
  visibilityParams,
} from '../src/modules/site_audit_log_catalog.js';
import {
  SAFE_DETAIL_KEYS,
  SITE_AUDIT_SQL,
  buildSiteAuditParams,
  listSiteAuditLog,
  mapSiteAuditRow,
  parseSiteAuditQuery,
  presentActor,
  safeDetails,
  safeTargetId,
  safeTargetType,
} from '../src/modules/site_audit_log_service.js';
import { siteAuditLogLimiter, siteAuditLogRouter } from '../src/modules/site_audit_log_routes.js';

process.env.JWT_SECRET ||= 'site-audit-log-test-secret';

const here = path.dirname(fileURLToPath(import.meta.url));
const SRC = path.join(here, '..', 'src');
const readSrc = (relative) => readFileSync(path.join(SRC, relative), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;

// ---------------------------------------------------------------------------
// Katalog ve gorunurluk
// ---------------------------------------------------------------------------

describe('islem kayitlari: eylem katalogu', () => {
  it('kategori anahtarlari ve basliklari sabit; anahtarlar benzersiz', () => {
    assert.deepEqual(
      SITE_AUDIT_CATEGORIES.map((c) => [c.key, c.label]),
      [
        ['modules', 'Modüller'],
        ['roles', 'Yetki ve roller'],
        ['access', 'Kapı ve geçiş'],
        ['people', 'Kişi ve daire kayıtları'],
        ['finance', 'Aidat ve finans'],
        ['announcements', 'Duyurular'],
        ['documents', 'Dosya deposu'],
        ['services', 'Site hizmetleri'],
        ['settings', 'Site ayarları'],
      ],
    );
    assert.deepEqual(SITE_AUDIT_CATEGORY_KEYS, SITE_AUDIT_CATEGORIES.map((c) => c.key));
    assert.equal(new Set(SITE_AUDIT_CATEGORY_KEYS).size, SITE_AUDIT_CATEGORY_KEYS.length);
    assert.ok(Object.isFrozen(SITE_AUDIT_CATEGORIES) && Object.isFrozen(SITE_AUDIT_LABELS));
  });

  it('her baslikli eylem bir kategoride ve gizli degil; her baslik Turkce, bos degil, ham kod gostermez', () => {
    for (const [action, label] of Object.entries(SITE_AUDIT_LABELS)) {
      assert.ok(categoryOfAction(action), `${action} kategoride degil`);
      assert.equal(isHiddenAction(action), false, `${action} gizli ve baslikli olamaz`);
      assert.ok(typeof label === 'string' && label.trim() === label && label.length >= 4, action);
      assert.doesNotMatch(label, /[a-z]+_[a-z]+|\w+\.\w+/, `${action} basligi ham kod iceriyor`);
    }
  });

  it('gizli eylemler hicbir kategoriye girmez ve basliksizdir', () => {
    const hidden = [
      'safety_request.created',
      'safety_request.updated',
      'access_suspension.created',
      'access_suspension.lifted',
      'residency_log.viewed',
      'residency_log.exported',
      'apartment_mgmt.person_search',
      'apartment_mgmt.search_visibility_changed',
      'account.deleted',
      'account.data_exported',
      'account.key_rotation_failed',
      'user.role_changed',
      'user.password_set',
      'platform_config.updated',
      'platform_settings.updated',
      'subscription.trial_days_updated',
      'site_application.approved',
    ];
    for (const action of hidden) {
      assert.equal(isHiddenAction(action), true, action);
      assert.equal(categoryOfAction(action), null, action);
      assert.equal(isVisibleToManager(action), false, action);
      assert.equal(Object.hasOwn(SITE_AUDIT_LABELS, action), false, action);
      assert.equal(actionLabelOf(action), null, action);
    }
    for (const prefix of SITE_AUDIT_HIDDEN_PREFIXES) assert.ok(prefix.endsWith('.'), prefix);
    assert.deepEqual([...SITE_AUDIT_HIDDEN_ACTIONS].sort(), ['apartment_mgmt.person_search', 'apartment_mgmt.search_visibility_changed']);
  });

  it('gizli liste kategoriden ONCELIKLI: apartment_mgmt ailesi gorunur ama person_search gizli', () => {
    assert.equal(categoryOfAction('apartment_mgmt.tenant_added')?.key, 'people');
    assert.equal(categoryOfAction('apartment_mgmt.person_search'), null);
  });

  it('kataloga girmeyen yeni eylem GORUNMEZ (varsayilan kapali); bilinen ailedeki yeni eylem gorunur ve genel baslik alir', () => {
    for (const action of ['unknown.thing', 'inventory.item_created', 'sms.sent', '', 'finance', 'FINANCE.run.posted']) {
      assert.equal(categoryOfAction(action), null, action);
      assert.equal(actionLabelOf(action), null, action);
    }
    assert.equal(categoryOfAction('finance.future.thing')?.key, 'finance');
    assert.equal(actionLabelOf('finance.future.thing'), 'Aidat ve finans işlemi');
    assert.equal(actionLabelOf('work_item.future_event'), 'Site hizmetleri işlemi');
    assert.equal(actionLabelOf('people.bulk_deactivate'), 'Toplu kişi işlemi');
    assert.equal(categoryOfAction('export')?.key, 'people');
    assert.equal(categoryOfAction('exports.something'), null, "'export' tam ad, onek degil");
  });

  it('onek carpismalari dogru kategoriye gider (site_manager roller, site. ayarlar, site_application gizli)', () => {
    assert.equal(categoryOfAction('site_manager.added')?.key, 'roles');
    assert.equal(categoryOfAction('site.deletion_requested')?.key, 'settings');
    assert.equal(categoryOfAction('site_application.created'), null);
    assert.equal(categoryOfAction('reservation_area.created')?.key, 'services');
    assert.equal(categoryOfAction('contract_vendor.created')?.key, 'services');
    assert.equal(categoryOfAction('door_permission.granted')?.key, 'access');
    assert.equal(categoryOfAction('module_request.created')?.key, 'modules');
    assert.equal(categoryOfAction('device.ownership_released')?.key, 'access');
  });

  it("LIKE desenleri: '_' ve '%' kacirilir (work_item. yalnizca work_item. ile baslayani yakalar)", () => {
    assert.equal(likePrefixPattern('work_item.'), 'work\\_item.%');
    assert.equal(likePrefixPattern('a%b\\c'), 'a\\%b\\\\c%');
    const params = visibilityParams('services');
    assert.ok(params.includeLike.includes('work\\_item.%'));
    assert.ok(params.includeLike.every((p) => p.endsWith('%')));
    assert.deepEqual(params.includeExact, []);
    assert.deepEqual(visibilityParams('people').includeExact, ['export']);
    assert.ok(visibilityParams(null).includeLike.length > params.includeLike.length, 'kategorisiz = tum kategoriler');
    assert.ok(params.excludeLike.includes('safety\\_request.%'));
    assert.deepEqual(params.excludeExact, [...SITE_AUDIT_HIDDEN_ACTIONS]);
    assert.deepEqual(visibilityParams('yok').includeLike, [], 'bilinmeyen kategori hicbir sey gostermez');
  });

  it('kodda gecen HER gorunur denetim eylemi Turkce baslik alir (yeni eylem eklenince katalog guncellenmeli)', () => {
    const found = new Set();
    const walk = (dir) => {
      for (const name of readdirSync(dir)) {
        const full = path.join(dir, name);
        if (statSync(full).isDirectory()) walk(full);
        else if (name.endsWith('.js') && name !== 'site_audit_log_catalog.js') {
          for (const line of readFileSync(full, 'utf8').split(/\r?\n/)) {
            if (!/audit/i.test(line)) continue;
            for (const match of line.matchAll(/'([a-z_]+\.[a-z_.]+|export)'/g)) found.add(match[1]);
          }
        }
      }
    };
    walk(SRC);
    assert.ok(found.size > 150, `denetim eylemi taramasi calismadi (${found.size})`);
    const unlabeled = [...found].filter((action) => categoryOfAction(action) !== null && !Object.hasOwn(SITE_AUDIT_LABELS, action));
    assert.deepEqual(
      unlabeled,
      [],
      `Yeni denetim eylemi icin server/src/modules/site_audit_log_catalog.js icine Turkce baslik ekleyin (ya da gizli listeye alin): ${unlabeled.join(', ')}`,
    );
  });
});

// ---------------------------------------------------------------------------
// Sorgu dogrulama
// ---------------------------------------------------------------------------

describe('islem kayitlari: sorgu dogrulama', () => {
  it('bos sorgu: suzgecsiz varsayilanlar (limit 50)', () => {
    assert.deepEqual(parseSiteAuditQuery({}), { from: null, to: null, category: null, action: null, beforeId: null, limit: 50 });
    assert.deepEqual(parseSiteAuditQuery(undefined), { from: null, to: null, category: null, action: null, beforeId: null, limit: 50 });
    assert.deepEqual(parseSiteAuditQuery({ from: '', to: '  ', category: '', action: '', before_id: '', limit: '' }), {
      from: null, to: null, category: null, action: null, beforeId: null, limit: 50,
    });
  });

  it('gecerli sorgu: tarihler, tur, eylem, sayfalama', () => {
    assert.deepEqual(
      parseSiteAuditQuery({ from: '2026-10-01', to: '2026-10-31', category: 'finance', action: 'finance.run.posted', before_id: '900', limit: '25' }),
      { from: '2026-10-01', to: '2026-10-31', category: 'finance', action: 'finance.run.posted', beforeId: 900, limit: 25 },
    );
    assert.equal(parseSiteAuditQuery({ from: '2026-10-05', to: '2026-10-05' }).from, '2026-10-05', 'ayni gun gecerli');
    assert.equal(parseSiteAuditQuery({ limit: '9999' }).limit, 200);
    assert.equal(parseSiteAuditQuery({ limit: '0' }).limit, 1);
    assert.equal(parseSiteAuditQuery({ limit: 'abc' }).limit, 50);
    assert.equal(parseSiteAuditQuery({ from: '2024-02-29' }).from, '2024-02-29', 'artik yil');
  });

  it('gecersiz deger 400 INVALID_QUERY (tarih biçimi, takvim disi gun, aralik disi yil, dizi, nesne, bilinmeyen tur, kotu eylem, kotu id)', () => {
    const bad = [
      { from: '2026-1-1' }, { from: '01.10.2026' }, { from: '2026-13-01' }, { from: '2026-02-30' }, { from: '2025-02-29' }, { to: '2026-10-32' },
      { from: '1999-12-31' }, { to: '2101-01-01' }, { from: '2026-10-01T00:00:00Z' }, { from: ['2026-10-01', '2026-10-02'] }, { to: { a: 1 } },
      { category: 'yok' }, { category: 'FINANCE' }, { category: ['finance'] }, { category: 'finance;drop' },
      { action: 'Finance.Run' }, { action: 'x'.repeat(101) }, { action: "a'b" }, { action: ['a.b'] }, { action: '.hidden' },
      { before_id: '0' }, { before_id: '-3' }, { before_id: '1e3' }, { before_id: 'abc' }, { before_id: ['1', '2'] },
    ];
    for (const query of bad) {
      assert.throws(() => parseSiteAuditQuery(query), (error) => error.statusCode === 400 && error.code === 'INVALID_QUERY', JSON.stringify(query));
    }
  });

  it('baslangic > bitis: 400 INVALID_DATE_RANGE', () => {
    assert.throws(
      () => parseSiteAuditQuery({ from: '2026-10-10', to: '2026-10-09' }),
      (error) => error.statusCode === 400 && error.code === 'INVALID_DATE_RANGE' && /Başlangıç tarihi/.test(error.message),
    );
  });
});

// ---------------------------------------------------------------------------
// Satir sunumu: kisisel veri asgari
// ---------------------------------------------------------------------------

const baseRow = (extra = {}) => ({
  id: '41',
  created_at: new Date('2026-10-20T08:15:00.000Z'),
  actor_user_code: 20001,
  actor_name: 'Ayşe Yönetici',
  actor_role: 'site_manager',
  action: 'finance.run.posted',
  target_type: 'finance',
  target_id: '2026-10',
  details: { count: 12 },
  actor_deleted: false,
  ...extra,
});

describe('islem kayitlari: satir sunumu', () => {
  it('normal satir: kim / ne zaman / ne; kullanici kodu ve site kodu YOK', () => {
    const item = mapSiteAuditRow(baseRow());
    assert.deepEqual(item, {
      id: 41,
      created_at: '2026-10-20T08:15:00.000Z',
      actor_name: 'Ayşe Yönetici',
      actor_role: 'site_manager',
      actor_role_label: 'Site yöneticisi',
      action: 'finance.run.posted',
      action_label: 'Aidat borçlandırıldı',
      category: 'finance',
      category_label: 'Aidat ve finans',
      target_type: 'finance',
      target_id: '2026-10',
      details: { count: 12 },
    });
    for (const forbidden of ['actor_user_code', 'site_code', 'site_name', 'user_code', 'email', 'phone']) {
      assert.equal(Object.hasOwn(item, forbidden), false, forbidden);
    }
  });

  it('super kullanici adi cikmaz: "Sistem yoneticisi"; sistem satiri "Sistem"; aktorsuz satir "Sistem"', () => {
    const superRow = presentActor(baseRow({ actor_user_code: 1, actor_name: 'Cenk Gerçek Ad', actor_role: 'super_user' }));
    assert.deepEqual(superRow, { name: 'Sistem yöneticisi', role: 'super_user', roleLabel: null });
    assert.doesNotMatch(JSON.stringify(mapSiteAuditRow(baseRow({ actor_name: 'Cenk Gerçek Ad', actor_role: 'super_user' }))), /Cenk/);
    assert.deepEqual(presentActor(baseRow({ actor_user_code: null, actor_name: 'Sistem', actor_role: 'system' })), { name: 'Sistem', role: 'system', roleLabel: null });
    assert.deepEqual(presentActor(baseRow({ actor_user_code: null, actor_name: null, actor_role: null })), { name: 'Sistem', role: 'system', roleLabel: null });
  });

  it('silinmis hesap ya da hesabi kalmamis kisi: ad anlik goruntusu GOSTERILMEZ ("Silinmis Kullanici")', () => {
    const deleted = presentActor(baseRow({ actor_name: 'Eski Yönetici Adı', actor_deleted: true }));
    assert.equal(deleted.name, 'Silinmiş Kullanıcı');
    assert.equal(deleted.roleLabel, 'Site yöneticisi');
    const orphan = presentActor(baseRow({ actor_user_code: null, actor_name: 'Hesabı Kalmayan Kişi', actor_role: 'apartment_owner' }));
    assert.equal(orphan.name, 'Silinmiş Kullanıcı');
    assert.equal(orphan.roleLabel, 'Daire sakini');
    assert.doesNotMatch(JSON.stringify([deleted, orphan]), /Eski Yönetici|Hesabı Kalmayan/);
  });

  it('rol basliklari ve bilinmeyen rol; adsiz canli kullanici', () => {
    assert.equal(presentActor(baseRow({ actor_role: 'apartment_owner' })).roleLabel, 'Daire sakini');
    assert.equal(presentActor(baseRow({ actor_role: 'individual' })).roleLabel, 'Kullanıcı');
    assert.equal(presentActor(baseRow({ actor_role: 'baska_rol' })).roleLabel, null);
    assert.equal(presentActor(baseRow({ actor_name: null })).name, 'Bilinmeyen kullanıcı');
    assert.equal(presentActor(baseRow({ actor_name: `  ${'u'.repeat(300)}  ` })).name.length, 200);
  });

  it('details: yalniz izinli anahtar + guvenli tek deger; sifre / belirtec / e-posta / telefon / serbest metin / dizi / nesne ATILIR', () => {
    const hostile = {
      status: 'yeni',
      count: 3,
      enabled: true,
      to: 'aktif',
      number_label: '2026/123',
      module_code: 'plate_recognition',
      password: 'Parola123!',
      token: 'a'.repeat(20) + '1'.repeat(30),
      access_token: 'abc',
      secret: 'x',
      email: 'ali@example.com',
      phone: '05321234567',
      note: 'Serbest metin: Ali Veli aradı',
      uid_suffix: '9A3F',
      changes: [{ field: 'phone', from: '0532 123 45 67', to: '0533' }],
      nested: { password: 'x' },
      role: ['site_manager'],
      from: 'ali@example.com',
      field: '05321234567',
      kind: 'x'.repeat(65),
      via: 'iban TR330006100519786457841326',
      door_id: 12,
      scope: 'site',
    };
    assert.deepEqual(safeDetails(hostile), {
      module_code: 'plate_recognition',
      number_label: '2026/123',
      door_id: 12,
      count: 3,
      scope: 'site',
      enabled: true,
      status: 'yeni',
      to: 'aktif',
    });
    const text = JSON.stringify(safeDetails(hostile));
    assert.doesNotMatch(text, /password|token|secret|email|phone|@|0532|Parola|Serbest|iban/i);
    assert.deepEqual(safeDetails(JSON.stringify({ status: 'acik', password: 'x' })), { status: 'acik' }, 'JSON metni de ayrisir');
    for (const bad of [null, undefined, 'bozuk{', 5, [], ['status'], 'null']) assert.deepEqual(safeDetails(bad), {}, String(bad));
    assert.deepEqual(safeDetails({ count: NaN, door_id: Infinity, status: '' }), {});
    assert.deepEqual(safeDetails({ count: 1e15 }), {}, 'asiri buyuk sayi atilir');
    assert.ok(SAFE_DETAIL_KEYS.every((key) => !/pass|token|secret|mail|phone|note|name/i.test(key)), 'izinli anahtarlarda hassas ad yok');
  });

  it('hedef turu / no: kisa ve kod benzeri degilse null (belirtec, e-posta, uzun rakam dizisi)', () => {
    assert.equal(safeTargetType('finance'), 'finance');
    assert.equal(safeTargetType('Finance'), null);
    assert.equal(safeTargetType('a b'), null);
    assert.equal(safeTargetType(null), null);
    assert.equal(safeTargetId('12'), '12');
    assert.equal(safeTargetId(12), '12');
    assert.equal(safeTargetId('door_control'), 'door_control');
    assert.equal(safeTargetId('2026-10'), '2026-10');
    assert.equal(safeTargetId('late_fee.monthly_bp_max'), 'late_fee.monthly_bp_max');
    assert.equal(safeTargetId('ali@example.com'), null);
    assert.equal(safeTargetId('e'.repeat(40) + '9'), null, 'belirtec benzeri');
    assert.equal(safeTargetId('0123456789abcdef0123456789abcdef'), null, '32 haneli ozet');
    assert.equal(safeTargetId('1000000001'), '1000000001', '10 haneli site kodu / buyuk sira numarasi gecer');
    assert.equal(safeTargetId('05321234567'), null, 'telefon benzeri (11 hane)');
    assert.equal(safeTargetId('12345678901'), null, 'kimlik no benzeri (11 hane)');
    assert.equal(safeTargetId('TR33 0006 1005 1978 6457 8413 26'), null, 'IBAN benzeri');
    assert.equal(safeTargetId('x'.repeat(81)), null);
    assert.equal(safeTargetId(null), null);
    assert.equal(safeTargetId(''), null);
  });

  it('bilinmeyen eylem satiri "Diger islem" ve kategorisiz doner (SQL zaten listelemez; savunma)', () => {
    const item = mapSiteAuditRow(baseRow({ action: 'zzz.unknown' }));
    assert.equal(item.action_label, 'Diğer işlem');
    assert.equal(item.category, null);
    assert.equal(item.category_label, null);
  });

  it('tarih gecersizse created_at null; bozuk id sayiya cevrilir', () => {
    assert.equal(mapSiteAuditRow(baseRow({ created_at: 'bozuk' })).created_at, null);
    assert.equal(mapSiteAuditRow(baseRow({ created_at: null })).created_at, null);
    assert.equal(mapSiteAuditRow(baseRow({ created_at: '2026-10-20T08:15:00Z' })).created_at, '2026-10-20T08:15:00.000Z');
  });
});

// ---------------------------------------------------------------------------
// Sabit sorgu
// ---------------------------------------------------------------------------

describe('islem kayitlari: sabit sorgu', () => {
  const sql = norm(SITE_AUDIT_SQL);

  it('YALNIZ yola yazilan siteyi okur: ilk kosul a.site_code = $1; tum degerler parametre ($1..$10), SQL birlestirme yok', () => {
    assert.match(sql, /WHERE a\.site_code = \$1 AND/);
    const placeholders = [...new Set(sql.match(/\$\d+/g))].sort((a, b) => Number(a.slice(1)) - Number(b.slice(1)));
    assert.deepEqual(placeholders, ['$1', '$2', '$3', '$4', '$5', '$6', '$7', '$8', '$9', '$10']);
    assert.match(sql, /ORDER BY a\.id DESC LIMIT \$10$/);
    assert.doesNotMatch(sql, /\$\{|' \+ |\|\|/);
  });

  it('gun sinirlari Istanbul saatinde ve bitis DAHIL (bir sonraki gunun baslangicindan kucuk)', () => {
    assert.match(sql, /a\.created_at >= \(\$3::DATE\)::TIMESTAMP AT TIME ZONE 'Europe\/Istanbul'/);
    assert.match(sql, /a\.created_at < \(\(\$4::DATE \+ 1\)\)::TIMESTAMP AT TIME ZONE 'Europe\/Istanbul'/);
  });

  it('gorunurluk: dahil edilen desenler VE gizli liste (NOT) ayri parametreler', () => {
    assert.match(sql, /AND \(a\.action LIKE ANY\(\$5::TEXT\[\]\) OR a\.action = ANY\(\$6::TEXT\[\]\)\)/);
    assert.match(sql, /AND NOT \(a\.action LIKE ANY\(\$7::TEXT\[\]\) OR a\.action = ANY\(\$8::TEXT\[\]\)\)/);
    assert.match(sql, /AND \(\$9::TEXT IS NULL OR a\.action = \$9::TEXT\)/);
  });

  it('kisisel alan sizdirmaz: SELECT * yok; users tablosundan yalniz deleted_at okunur; e-posta / telefon / parola sutunu yok', () => {
    assert.doesNotMatch(sql, /SELECT \*|a\.\*|u\.\*/);
    assert.doesNotMatch(sql, /email|phone|password|token|secret|site_name|s\.name/i);
    assert.deepEqual([...sql.matchAll(/\bu\.(\w+)/g)].map((m) => m[1]).sort(), ['deleted_at', 'user_code']);
  });

  it('parametre dizisi: sira SITE_AUDIT_SQL aciklamasiyla ayni; limit + 1; suzgecler null', () => {
    const params = buildSiteAuditParams({ siteCode: SITE_1, limit: 50 });
    assert.equal(params.length, 10);
    assert.equal(params[0], SITE_1);
    assert.deepEqual(params.slice(1, 4), [null, null, null]);
    assert.equal(params[8], null);
    assert.equal(params[9], 51);
    assert.ok(Array.isArray(params[4]) && params[4].length > 10 && Array.isArray(params[5]) && params[5].includes('export'));
    assert.ok(params[6].includes('safety\\_request.%') && params[7].includes('apartment_mgmt.person_search'));
    const filtered = buildSiteAuditParams({ siteCode: SITE_2, beforeId: 77, from: '2026-10-01', to: '2026-10-31', category: 'modules', action: 'module.enabled', limit: 7 });
    assert.deepEqual(filtered.slice(0, 4), [SITE_2, 77, '2026-10-01', '2026-10-31']);
    assert.deepEqual(filtered[4], ['module.%', 'module\\_request.%']);
    assert.deepEqual(filtered[5], []);
    assert.equal(filtered[8], 'module.enabled');
    assert.equal(filtered[9], 8);
  });
});

// ---------------------------------------------------------------------------
// Sahte veritabani: sabit sorgunun parametrelerini yorumlar
// ---------------------------------------------------------------------------

const escapeRe = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function likeRegex(pattern) {
  let out = '';
  for (let i = 0; i < pattern.length; i += 1) {
    const ch = pattern[i];
    if (ch === '\\') {
      i += 1;
      out += escapeRe(pattern[i] ?? '');
    } else if (ch === '%') {
      out += '.*';
    } else if (ch === '_') {
      out += '.';
    } else {
      out += escapeRe(ch);
    }
  }
  return new RegExp(`^${out}$`, 's');
}

const ISTANBUL_OFFSET_MS = 3 * 3600 * 1000;
const dayStart = (day) => Date.parse(`${day}T00:00:00Z`) - ISTANBUL_OFFSET_MS;

/** SITE_AUDIT_SQL'in anlamini JS'te uygular (gercek PG esdegerligi scripts/qa_site_audit_log.mjs'te). */
function evaluateAuditQuery(rows, params) {
  const [siteCode, beforeId, from, to, includeLike, includeExact, excludeLike, excludeExact, action, limit] = params;
  const incRe = includeLike.map(likeRegex);
  const excRe = excludeLike.map(likeRegex);
  return rows
    .filter((row) => Number(row.site_code) === Number(siteCode))
    .filter((row) => beforeId === null || row.id < Number(beforeId))
    .filter((row) => from === null || row.created_at.getTime() >= dayStart(from))
    .filter((row) => to === null || row.created_at.getTime() < dayStart(to) + 24 * 3600 * 1000)
    .filter((row) => incRe.some((re) => re.test(row.action)) || includeExact.includes(row.action))
    .filter((row) => !(excRe.some((re) => re.test(row.action)) || excludeExact.includes(row.action)))
    .filter((row) => action === null || row.action === action)
    .sort((a, b) => b.id - a.id)
    .slice(0, limit)
    .map((row) => ({ ...row, actor_deleted: row.actor_deleted ?? false }));
}

const row = (id, site, action, iso, extra = {}) => ({
  id,
  site_code: site,
  created_at: new Date(iso),
  actor_user_code: 20001,
  actor_name: 'Ayşe Yönetici',
  actor_role: 'site_manager',
  action,
  target_type: null,
  target_id: null,
  details: {},
  ...extra,
});

function seedAuditRows() {
  return [
    row(1, SITE_1, 'module.enabled', '2026-10-01T09:00:00Z', { target_type: 'module', target_id: 'finance', details: { enabled: true } }),
    row(2, SITE_1, 'finance.run.posted', '2026-10-05T20:30:00Z', { target_type: 'finance', target_id: '2026-10' }), // 23:30 Istanbul, 5 Ekim
    row(3, SITE_1, 'finance.payment.recorded', '2026-10-05T21:00:00Z', { target_type: 'finance', target_id: '77' }), // 00:00 Istanbul, 6 Ekim
    row(4, SITE_2, 'module.enabled', '2026-10-06T09:00:00Z', { actor_name: 'Bora Yönetici', actor_user_code: 20002, target_type: 'module', target_id: 'survey' }),
    row(5, SITE_1, 'safety_request.created', '2026-10-07T09:00:00Z', { actor_name: 'Gizli Talep Eden', actor_role: 'apartment_owner', actor_user_code: 30044 }),
    row(6, SITE_1, 'residency_log.viewed', '2026-10-07T10:00:00Z'),
    row(7, SITE_1, 'apartment_mgmt.person_search', '2026-10-07T11:00:00Z', { actor_name: 'Arayan Sakin', actor_role: 'apartment_owner', actor_user_code: 30044, details: { query: 'Al*', results: 2 } }),
    row(8, SITE_1, 'announcement.published', '2026-10-08T06:00:00Z', { actor_user_code: null, actor_name: 'Sistem', actor_role: 'system', target_type: 'announcement', target_id: '5' }),
    row(9, SITE_1, 'staff_role.assigned', '2026-10-09T12:00:00Z', { actor_user_code: 1, actor_name: 'Cenk Gerçek Ad', actor_role: 'super_user', target_type: 'user', target_id: '20003', details: { role: 'BOARD_MEMBER' } }),
    row(10, SITE_1, 'person.created', '2026-10-10T12:00:00Z', { actor_user_code: 30009, actor_name: 'Silinen Kişi Adı', actor_role: 'site_manager', actor_deleted: true, target_type: 'person', target_id: '31' }),
    row(11, SITE_1, 'foo.unknown', '2026-10-11T12:00:00Z'),
    row(12, SITE_1, 'finance.future_thing', '2026-10-12T12:00:00Z', { details: { count: 2 } }),
    row(13, SITE_1, 'work_item.created', '2026-10-13T12:00:00Z', {
      actor_user_code: 30044,
      actor_name: 'Deniz Sakin',
      actor_role: 'apartment_owner',
      target_type: 'work_item',
      target_id: '9',
      details: { status: 'yeni', email: 'deniz@example.com', password: 'Parola123!', note: 'Asansörde ses var, 0532 111 22 33 arayın', changes: [{ field: 'phone', to: '0533' }], count: 3 },
    }),
    row(14, SITE_1, 'account.data_exported', '2026-10-14T12:00:00Z'),
    row(15, null, 'platform_config.updated', '2026-10-14T13:00:00Z'),
    row(16, SITE_1, 'export', '2026-10-15T12:00:00Z', { target_type: 'people' }),
    row(17, SITE_1, 'door_permission.granted', '2026-10-16T12:00:00Z', { target_type: 'user', target_id: '30004', details: { door_id: 4, user_codes: [30004], note: 'x' } }),
    row(18, SITE_1, 'site.deletion_requested', '2026-10-17T12:00:00Z', { target_type: 'site', target_id: String(SITE_1) }),
    row(19, SITE_2, 'finance.run.posted', '2026-10-18T12:00:00Z', { actor_name: 'Bora Yönetici', actor_user_code: 20002 }),
    row(20, SITE_1, 'work_item.status_changed', '2026-10-19T12:00:00Z', { target_type: 'work_item', target_id: '9', details: { from: 'yeni', to: 'devam' } }),
  ];
}

// --- servis (sahte db.query ile) ---

describe('islem kayitlari: servis (site kapsami, suzgecler, sayfalama)', () => {
  const rows = seedAuditRows();
  const fakeDb = () => {
    const calls = [];
    return {
      calls,
      async query(text, params) {
        calls.push({ sql: norm(text), params });
        assert.equal(norm(text), norm(SITE_AUDIT_SQL), 'servis yalniz sabit sorguyu calistirir');
        return ok(evaluateAuditQuery(rows, params));
      },
    };
  };
  const idsOf = (page) => page.items.map((item) => item.id);

  it('BASKA SITENIN kaydi gorunmez; gizli / kataloga girmeyen / sitesiz satirlar listelenmez', async () => {
    const page = await listSiteAuditLog({ siteCode: SITE_1 }, fakeDb());
    assert.deepEqual(idsOf(page), [20, 18, 17, 16, 13, 12, 10, 9, 8, 3, 2, 1]);
    for (const hiddenId of [4, 19, 5, 6, 7, 11, 14, 15]) assert.equal(idsOf(page).includes(hiddenId), false, `id ${hiddenId} gorunmemeli`);
    const other = await listSiteAuditLog({ siteCode: SITE_2 }, fakeDb());
    assert.deepEqual(idsOf(other), [19, 4]);
    assert.equal(page.next_before_id, null);
  });

  it('yanit ogeleri: gizli ayrinti sizmaz, aktor sunumu dogru, kategori + baslik dolu', async () => {
    const page = await listSiteAuditLog({ siteCode: SITE_1 }, fakeDb());
    const byId = new Map(page.items.map((item) => [item.id, item]));
    assert.equal(byId.get(9).actor_name, 'Sistem yöneticisi');
    assert.equal(byId.get(8).actor_name, 'Sistem');
    assert.equal(byId.get(10).actor_name, 'Silinmiş Kullanıcı');
    assert.equal(byId.get(1).actor_name, 'Ayşe Yönetici');
    assert.equal(byId.get(12).action_label, 'Aidat ve finans işlemi');
    assert.equal(byId.get(16).action_label, 'Veri dışa aktarıldı');
    assert.equal(byId.get(18).category, 'settings');
    assert.deepEqual(byId.get(13).details, { status: 'yeni', count: 3 });
    assert.deepEqual(byId.get(17).details, { door_id: 4 });
    assert.deepEqual(byId.get(20).details, { from: 'yeni', to: 'devam' });
    const text = JSON.stringify(page);
    // 30044 = islemi yapan sakinin kullanici kodu (hicbir yerde cikmaz); 30004 yalniz kapi izninin HEDEF numarasidir.
    assert.doesNotMatch(text, /Gizli Talep|Arayan Sakin|Silinen Kişi|Cenk|deniz@example|Parola123|0532|Asansörde|actor_user_code|site_code|30044/);
  });

  it('tarih araligi Istanbul gunudur ve bitis gunu DAHILDIR', async () => {
    // id 2 = 5 Ekim 23:30 (Istanbul); id 3 = 6 Ekim 00:00 (Istanbul)
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, from: '2026-10-05', to: '2026-10-05' }, fakeDb())), [2]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, from: '2026-10-06', to: '2026-10-06' }, fakeDb())), [3]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, from: '2026-10-05', to: '2026-10-06' }, fakeDb())), [3, 2]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, to: '2026-10-05' }, fakeDb())), [2, 1]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, from: '2026-10-16' }, fakeDb())), [20, 18, 17]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, from: '2026-11-01' }, fakeDb())), []);
  });

  it('islem turu (kategori) suzgeci yalniz o kategoriyi getirir; gizli eylemler turle de acilmaz', async () => {
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'finance' }, fakeDb())), [12, 3, 2]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'modules' }, fakeDb())), [1]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'people' }, fakeDb())), [16, 10]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'services' }, fakeDb())), [20, 13]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'roles' }, fakeDb())), [9]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'access' }, fakeDb())), [17]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'settings' }, fakeDb())), [18]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'announcements' }, fakeDb())), [8]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'documents' }, fakeDb())), []);
  });

  it('tam eylem suzgeci; gizli bir eylem istenirse bos doner (varligi sizmaz)', async () => {
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, action: 'finance.run.posted' }, fakeDb())), [2]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, action: 'module.enabled' }, fakeDb())), [1]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, action: 'safety_request.created' }, fakeDb())), []);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, action: 'residency_log.viewed' }, fakeDb())), []);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, action: 'foo.unknown' }, fakeDb())), []);
  });

  it('suzgecler birlesir (tarih + tur + eylem)', async () => {
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'finance', from: '2026-10-06', to: '2026-10-31' }, fakeDb())), [12, 3]);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'finance', action: 'module.enabled' }, fakeDb())), []);
    assert.deepEqual(idsOf(await listSiteAuditLog({ siteCode: SITE_1, category: 'finance', action: 'finance.payment.recorded', from: '2026-10-06', to: '2026-10-06' }, fakeDb())), [3]);
  });

  it('sayfalama: limit + 1 satir istenir; next_before_id son ogenin id\'si; before_id imleci siradaki sayfayi verir; son sayfada null', async () => {
    const db = fakeDb();
    const first = await listSiteAuditLog({ siteCode: SITE_1, limit: 5 }, db);
    assert.equal(db.calls[0].params[9], 6);
    assert.deepEqual(idsOf(first), [20, 18, 17, 16, 13]);
    assert.equal(first.next_before_id, 13);
    const second = await listSiteAuditLog({ siteCode: SITE_1, limit: 5, beforeId: first.next_before_id }, db);
    assert.deepEqual(idsOf(second), [12, 10, 9, 8, 3]);
    assert.equal(second.next_before_id, 3);
    const third = await listSiteAuditLog({ siteCode: SITE_1, limit: 5, beforeId: second.next_before_id }, db);
    assert.deepEqual(idsOf(third), [2, 1]);
    assert.equal(third.next_before_id, null);
    assert.deepEqual(await listSiteAuditLog({ siteCode: SITE_1, from: '2027-01-01' }, db), { items: [], next_before_id: null });
  });

  it('tam sayfa boyutunda biten liste de dogru: ek satir yoksa next_before_id null', async () => {
    const page = await listSiteAuditLog({ siteCode: SITE_1, limit: 12 }, fakeDb());
    assert.equal(page.items.length, 12);
    assert.equal(page.next_before_id, null);
  });

  it('veritabani hatasi servisten oldugu gibi yukselir (rota 500 + errorId uretir)', async () => {
    const db = { query: async () => { throw Object.assign(new Error('relation "audit_log" does not exist'), { code: '42P01' }); } };
    await assert.rejects(() => listSiteAuditLog({ siteCode: SITE_1 }, db), /audit_log/);
  });
});

// ---------------------------------------------------------------------------
// Uc: erisim matrisi
// ---------------------------------------------------------------------------

const mkUser = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name });
const users = {
  superUser: mkUser(1, 'super_user', 'Süper Kullanıcı'),
  mgrA: mkUser(20001, 'site_manager', 'Ayşe Yönetici'),
  mgrB: mkUser(20002, 'site_manager', 'Bora Yönetici'),
  ownerAdmin: mkUser(20003, 'apartment_owner', 'Can Sahip'),
  resident: mkUser(20004, 'apartment_owner', 'Deniz Sakin'),
  staff: mkUser(20005, 'individual', 'Ece Görevli'),
  board: mkUser(20006, 'individual', 'Fatma Kurul'),
  outsider: mkUser(20008, 'individual', 'Hakan İlgisiz'),
};

let db;
let server;
let baseUrl;

function makeDb() {
  return {
    sites: new Map([[SITE_1, 'Güneş Sitesi'], [SITE_2, 'Ay Sitesi']]),
    managers: [[SITE_1, 20001], [SITE_2, 20002]],
    memberships: [
      [SITE_1, 20003, 'SITE_OWNER'],
      [SITE_1, 20005, 'STAFF'],
      [SITE_1, 20004, 'RESIDENT'],
      [SITE_1, 20006, 'BOARD_MEMBER'],
    ],
    audit: seedAuditRows(),
    queries: [],
    failAudit: false,
  };
}

function handle(text, params) {
  const statement = norm(text);
  db.queries.push({ sql: statement, params });
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(statement)) {
    return ok(db.managers.filter(([s, u]) => s === Number(params[0]) && u === Number(params[1])).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\)/.test(statement)) {
    return ok(db.memberships.filter(([s, u, r]) => s === Number(params[0]) && u === Number(params[1]) && ['SITE_OWNER', 'SITE_ADMIN'].includes(r)).map(() => ({ x: 1 })));
  }
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(statement)) {
    const [site, user] = params.map(Number);
    const here = db.memberships.filter(([s, u]) => s === site && u === user);
    const otherRole = db.managers.some(([, u]) => u === user) || db.memberships.some(([, u, r]) => u === user && ['SITE_OWNER', 'SITE_ADMIN', 'BOARD_MEMBER'].includes(r));
    return ok([{ is_board_here: here.some(([, , r]) => r === 'BOARD_MEMBER'), is_member_here: here.length > 0, has_other_role: otherRole }]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(statement)) {
    return ok(db.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  }
  if (statement === norm(SITE_AUDIT_SQL)) {
    if (db.failAudit) throw Object.assign(new Error('connection terminated: host=10.0.0.5 password=hunter2'), { code: '57P01' });
    return ok(evaluateAuditQuery(db.audit, params));
  }
  if (/^(INSERT|UPDATE|DELETE)\b/i.test(statement)) throw new Error(`OKUMA ucu yazmamali: ${statement.slice(0, 120)}`);
  throw new Error(`BEKLENMEYEN SQL (sahte DB kati): ${statement.slice(0, 200)}`);
}

const ORIGINAL_ROUTES = siteAuditLogRouter.stack.filter((layer) => layer.route).map((layer) => ({
  path: layer.route.path,
  method: Object.keys(layer.route.methods)[0],
  handlers: layer.route.stack.map((entry) => entry.handle),
}));

before(async () => {
  for (const layer of siteAuditLogRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next();
  }
  const app = express();
  app.use(express.json());
  app.use(siteAuditLogRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
  delete pool.connect;
});

beforeEach(() => {
  db = makeDb();
  pool.query = async (text, params) => handle(text, params ?? []);
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  mock.restoreAll();
});

async function get(urlPath, user = users.mgrA) {
  const response = await fetch(`${baseUrl}${urlPath}`, { headers: { 'x-test-user': encodeURIComponent(JSON.stringify(user)) } });
  const body = await response.json();
  return { status: response.status, headers: response.headers, body };
}

const listPath = (site = SITE_1, query = '') => `/manager/sites/${site}/audit-log${query}`;
const idsOf = (res) => res.body.items.map((item) => item.id);

describe('islem kayitlari ucu: zincir ve kaynak', () => {
  it('tek rota GET /manager/sites/:siteCode/audit-log; authRequired ilk, hiz siniri ikinci; sunucuya baglanmis', () => {
    assert.deepEqual(ORIGINAL_ROUTES.map((r) => `${r.method.toUpperCase()} ${r.path}`), ['GET /manager/sites/:siteCode/audit-log']);
    assert.equal(ORIGINAL_ROUTES[0].handlers[0], authRequired);
    assert.equal(ORIGINAL_ROUTES[0].handlers[1], siteAuditLogLimiter);
    assert.equal(ORIGINAL_ROUTES[0].handlers.length, 3);
    assert.equal(typeof siteAuditLogLimiter, 'function');
    assert.match(readSrc('server.js'), /import \{ siteAuditLogRouter \} from '\.\/modules\/site_audit_log_routes\.js';/);
    assert.match(readSrc('server.js'), /app\.use\(siteAuditLogRouter\);/);
  });

  it('uc YALNIZ OKUR: kaynakta INSERT / UPDATE / DELETE / recordAudit yok; site kodu istek govdesi / sorgusundan alinmaz', () => {
    for (const file of ['modules/site_audit_log_routes.js', 'modules/site_audit_log_service.js', 'modules/site_audit_log_catalog.js']) {
      const source = readSrc(file);
      assert.doesNotMatch(source, /\bINSERT\s+INTO\b|\bUPDATE\s+\w+\s+SET\b|\bDELETE\s+FROM\b|\bTRUNCATE\b|recordAudit\s*\(/i, file);
    }
    const routes = readSrc('modules/site_audit_log_routes.js');
    assert.doesNotMatch(routes, /req\.(body|query)\.site_?[cC]ode|query\.site_code/);
    assert.match(routes, /siteCode: access\.siteCode/);
  });

  it('hiz sinirlayici kullanici basina 600/saat, IP basina 3000/saat; asilinca 429 + Retry-After', () => {
    assert.equal(typeof siteAuditLogLimiter.reset, 'function');
    const run = (req) => {
      const out = { headers: {}, statusCode: 200 };
      const res = { setHeader: (k, v) => { out.headers[k] = v; }, status(code) { out.statusCode = code; return this; }, json(body) { out.body = body; return this; } };
      let passed = false;
      siteAuditLogLimiter(req, res, () => { passed = true; });
      return { passed, ...out };
    };
    const req = { authUser: { userCode: 424242 }, ip: '10.9.9.9', headers: {}, socket: { remoteAddress: '10.9.9.9' } };
    siteAuditLogLimiter.reset();
    for (let i = 0; i < 600; i += 1) assert.equal(run(req).passed, true, `istek ${i + 1}`);
    const blocked = run(req);
    assert.equal(blocked.passed, false);
    assert.equal(blocked.statusCode, 429);
    assert.ok(Number(blocked.headers['Retry-After']) >= 1);
    assert.match(blocked.body.error, /Çok fazla istek/);
    siteAuditLogLimiter.reset();
  });
});

describe('islem kayitlari ucu: erisim (YALNIZ o sitenin yoneticisi ve super kullanici)', () => {
  it('site yoneticisi kendi sitesinin kayitlarini gorur; Cache-Control: no-store; yanit sekli', async () => {
    const res = await get(listPath());
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.deepEqual(Object.keys(res.body).sort(), ['items', 'next_before_id']);
    assert.deepEqual(idsOf(res), [20, 18, 17, 16, 13, 12, 10, 9, 8, 3, 2, 1]);
    assert.deepEqual(Object.keys(res.body.items[0]).sort(), [
      'action', 'action_label', 'actor_name', 'actor_role', 'actor_role_label', 'category', 'category_label', 'created_at', 'details', 'id', 'target_id', 'target_type',
    ]);
  });

  it('BASKA sitenin kaydi gorunmez; baska sitenin yoneticisi 403 FORBIDDEN_SITE; kendi sitesinde yalniz kendi kayitlari', async () => {
    const otherSite = await get(listPath(SITE_1), users.mgrB);
    assert.equal(otherSite.status, 403);
    assert.equal(otherSite.body.code, 'FORBIDDEN_SITE');
    assert.equal(otherSite.body.items, undefined);
    const own = await get(listPath(SITE_2), users.mgrB);
    assert.equal(own.status, 200);
    assert.deepEqual(idsOf(own), [19, 4]);
    // yoneticiler birbirinin sitesini goremez (yukaridaki 1. satir A'nin siteleri)
    const mgrAOnSite2 = await get(listPath(SITE_2), users.mgrA);
    assert.equal(mgrAOnSite2.status, 403);
  });

  it('site kodu sorgu dizesiyle degistirilemez (?site_code= yok sayilir)', async () => {
    const res = await get(listPath(SITE_1, `?site_code=${SITE_2}&siteCode=${SITE_2}`));
    assert.equal(res.status, 200);
    assert.ok(idsOf(res).every((id) => ![4, 19].includes(id)));
    assert.equal(db.queries.filter((q) => q.sql === norm(SITE_AUDIT_SQL))[0].params[0], SITE_1);
  });

  it('SAKIN, kurul uyesi, gorevli, ilgisiz kullanici ve daire sahibi (yonetici degil) 403; kayit sizmaz', async () => {
    for (const [name, user] of Object.entries({ resident: users.resident, board: users.board, staff: users.staff, outsider: users.outsider })) {
      const res = await get(listPath(), user);
      assert.equal(res.status, 403, name);
      assert.equal(res.body.code, 'FORBIDDEN_ROLE', name);
      assert.equal(res.body.items, undefined, name);
    }
    assert.equal(db.queries.some((q) => q.sql === norm(SITE_AUDIT_SQL)), false, 'yetkisiz istek denetim sorgusuna ulasmaz');
  });

  it('SITE_OWNER uyeligi olan kullanici (site yonetim yetkisi) gorur', async () => {
    const res = await get(listPath(), users.ownerAdmin);
    assert.equal(res.status, 200);
  });

  it('super kullanici her sitenin kaydini gorur; olmayan site 404; gecersiz site kodu 400', async () => {
    assert.equal((await get(listPath(SITE_1), users.superUser)).status, 200);
    assert.deepEqual(idsOf(await get(listPath(SITE_2), users.superUser)), [19, 4]);
    const missing = await get(listPath(1000000099), users.superUser);
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'SITE_NOT_FOUND');
    const invalid = await get('/manager/sites/abc/audit-log', users.superUser);
    assert.equal(invalid.status, 400);
    assert.equal(invalid.body.code, 'INVALID_SITE_CODE');
  });
});

describe('islem kayitlari ucu: suzgecler ve sayfalama', () => {
  it('tarih araligi', async () => {
    assert.deepEqual(idsOf(await get(listPath(SITE_1, '?from=2026-10-05&to=2026-10-05'))), [2]);
    assert.deepEqual(idsOf(await get(listPath(SITE_1, '?from=2026-10-06&to=2026-10-09'))), [9, 8, 3]);
    assert.deepEqual(idsOf(await get(listPath(SITE_1, '?to=2026-10-01'))), [1]);
  });

  it('islem turu (category) ve tam eylem (action)', async () => {
    assert.deepEqual(idsOf(await get(listPath(SITE_1, '?category=finance'))), [12, 3, 2]);
    assert.deepEqual(idsOf(await get(listPath(SITE_1, '?category=services'))), [20, 13]);
    assert.deepEqual(idsOf(await get(listPath(SITE_1, '?action=door_permission.granted'))), [17]);
    assert.deepEqual(idsOf(await get(listPath(SITE_1, '?category=finance&from=2026-10-06'))), [12, 3]);
  });

  it('gizli eylem turle ya da eylemle istense de gelmez', async () => {
    assert.deepEqual(idsOf(await get(listPath(SITE_1, '?action=safety_request.created'))), []);
    assert.deepEqual(idsOf(await get(listPath(SITE_1, '?action=apartment_mgmt.person_search'))), []);
    assert.deepEqual(idsOf(await get(listPath(SITE_1, '?category=people'))), [16, 10]);
  });

  it('sayfalama: limit + before_id; next_before_id', async () => {
    const first = await get(listPath(SITE_1, '?limit=4'));
    assert.deepEqual(idsOf(first), [20, 18, 17, 16]);
    assert.equal(first.body.next_before_id, 16);
    const second = await get(listPath(SITE_1, `?limit=4&before_id=${first.body.next_before_id}`));
    assert.deepEqual(idsOf(second), [13, 12, 10, 9]);
    const last = await get(listPath(SITE_1, '?limit=4&before_id=9'));
    assert.deepEqual(idsOf(last), [8, 3, 2, 1]);
    assert.equal(last.body.next_before_id, null);
    assert.equal((await get(listPath(SITE_1, '?limit=500'))).body.items.length, 12, 'limit en fazla 200');
  });

  it('gecersiz sorgu 400 (INVALID_QUERY / INVALID_DATE_RANGE); denetim sorgusu calismaz', async () => {
    for (const query of ['?from=bozuk', '?to=2026-02-30', '?category=yok', '?action=A.B', '?before_id=abc', '?from=2026-10-01&from=2026-10-02', '?category[]=finance']) {
      const res = await get(listPath(SITE_1, query));
      assert.equal(res.status, 400, query);
      assert.equal(res.body.code, 'INVALID_QUERY', query);
    }
    const range = await get(listPath(SITE_1, '?from=2026-10-10&to=2026-10-09'));
    assert.equal(range.status, 400);
    assert.equal(range.body.code, 'INVALID_DATE_RANGE');
    assert.equal(db.queries.some((q) => q.sql === norm(SITE_AUDIT_SQL)), false);
  });
});

describe('islem kayitlari ucu: yanit gizliligi ve hata davranisi', () => {
  it('yanitta sifre / belirtec / e-posta / telefon / kullanici kodu / site kodu / gizli talep eden adi YOK', async () => {
    const res = await get(listPath(SITE_1, '?limit=200'));
    const text = JSON.stringify(res.body);
    assert.doesNotMatch(text, /password|passwd|token|secret|apikey|api_key|deniz@example|0532|Parola123|actor_user_code|"site_code"|"user_code"/i);
    assert.doesNotMatch(text, /Gizli Talep|Arayan Sakin|Silinen Kişi Adı|Cenk Gerçek/);
    assert.doesNotMatch(text, /@/);
  });

  it('veritabani hatasi: 500 + genel mesaj + errorId; hata ayrintisi (baglanti bilgisi) istemciye SIZMAZ', async () => {
    db.failAudit = true;
    const res = await get(listPath());
    assert.equal(res.status, 500);
    assert.equal(res.body.error, 'İşlem kayıtları yüklenemedi.');
    assert.ok(res.body.errorId);
    assert.doesNotMatch(JSON.stringify(res.body), /hunter2|10\.0\.0\.5|password|57P01|connection/i);
  });
});
