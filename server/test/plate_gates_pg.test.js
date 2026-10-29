// Plaka Tanıma A1 (120): GERÇEK PostgreSQL ile uçtan uca (gerçek server.js uygulaması, gerçek authRequired, gerçek SQL, migration zinciri + ensureDbSchema).
// YALNIZ PLATE_GATES_PG_URL tanımlıysa koşar (örn. postgres://postgres@127.0.0.1:55433/postgres); aksi halde atlanır (npm test hermetik kalır).
//
// Kanıtlanan: şema (idempotent), kapı CRUD + çakışmalar, daire park yeri alanı, kenar istemci anahtarı (düz saklanmaz) + claim, kalp atışı -> DURUM rozetleri,
// olay idempotansı, "içeride" giriş/çıkış + sıra dışı olay, misafir kuralı için kapasite / içerideki sayı, delta senkron (bölüm özeti + updated_since),
// site kapsamı (başka sitenin kamerası), modül kapalı, iptal edilen anahtar.
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';

const ADMIN_URL = process.env.PLATE_GATES_PG_URL;
const skip = ADMIN_URL ? false : 'PLATE_GATES_PG_URL tanımlı değil (gerçek PostgreSQL gerekir)';

describe('plaka geçiş noktaları + kenar istemci: gerçek PostgreSQL', { skip }, () => {
  let pool;
  let server;
  let baseUrl;
  let dbName;
  let adminClient;
  let signAccessToken;
  const ids = {};
  const HASH = '$2a$04$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ01234';
  const q = (sql, params = []) => pool.query(sql, params);
  const call = async (method, path, { token, edge, body } = {}) => {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...(edge ? { authorization: `Bearer ${edge}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch (_error) {
      // JSON değil
    }
    return { status: response.status, json, text };
  };
  const mgr = (method, suffix, body) => call(method, `/manager/sites/${ids.site}/plate-recognition${suffix}`, { token: ids.token, body });
  const edge = (method, suffix, body, key = ids.edgeKey) => call(method, `/edge/plate/v1${suffix}`, { edge: key, body });
  const ago = (seconds) => new Date(Date.now() - seconds * 1000).toISOString();
  const evt = (n, over = {}) => ({ schema_version: 1, event_id: `evt-pg-${String(n).padStart(6, '0')}`, camera_id: ids.camIn, plate: '34ABC123', decision: 'acildi', seen_at: new Date().toISOString(), ...over });

  before(async () => {
    const pg = (await import('pg')).default;
    adminClient = new pg.Client({ connectionString: ADMIN_URL });
    await adminClient.connect();
    dbName = `plate_gates_${Date.now().toString(36)}`;
    await adminClient.query(`CREATE DATABASE ${dbName}`);
    const url = new URL(ADMIN_URL);
    process.env.DB_HOST = url.hostname;
    process.env.DB_PORT = url.port || '5432';
    process.env.DB_NAME = dbName;
    process.env.DB_USER = decodeURIComponent(url.username || 'postgres');
    process.env.DB_PASSWORD = decodeURIComponent(url.password || '');
    process.env.JWT_SECRET = 'plate-gates-pg-secret-0123456789abcdef0123456789abcdef';
    process.env.SERVER_SKIP_START = '1';
    process.env.ANNOUNCEMENT_SCHEDULER_DISABLED = '1';
    delete process.env.JWT_EXPIRES_IN;
    const errors = [];
    const { main: migrate } = await import('../scripts/migrate.js');
    const exitCode = await migrate(['--apply', '--yes'], { ...process.env }, { log() {}, logError: (message) => errors.push(message) });
    assert.equal(exitCode, 0, `migration zinciri uygulanamadı: ${errors.join(' | ')}`);
    const db = await import('../src/db.js');
    pool = db.pool;
    await db.ensureDbSchema();
    ({ signAccessToken } = await import('../src/jwt.js'));
    const { enableCoreModulesForSite } = await import('../src/modules/core_modules.js');
    const { app } = await import('../src/server.js');
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;

    const user = await q(
      `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash)
       VALUES ('Sahip', 'sahip-plaka@example.com', 'super_user', TRUE, TRUE, 'approved', $1) RETURNING user_code`,
      [HASH],
    );
    ids.token = signAccessToken({ id: user.rows[0].user_code }, { passwordHash: HASH });
    const mkSite = async (name) => Number((await q(`INSERT INTO sites (name, approval_status, approved_at) VALUES ($1, 'approved', NOW()) RETURNING site_code`, [name])).rows[0].site_code);
    ids.site = await mkSite('Plaka Sitesi');
    ids.other = await mkSite('Başka Site');
    for (const site of [ids.site, ids.other]) {
      await enableCoreModulesForSite(pool, site);
      await q(`INSERT INTO site_modules (site_code, module_code, enabled, updated_at) VALUES ($1, 'plate_recognition', TRUE, NOW()) ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE`, [site]);
    }
    const block = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A', 1) RETURNING id`, [ids.site])).rows[0].id);
    const apt = async (label, order) =>
      Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [ids.site, block, label, order])).rows[0].id);
    ids.aptA = await apt('1', 1);
    ids.aptB = await apt('2', 2);
    await q(`INSERT INTO vehicles (site_code, apartment_id, plate, plate_display) VALUES ($1, $2, '34ABC123', '34 ABC 123')`, [ids.site, ids.aptA]);
    const cam = async (site, name) =>
      Number((await q(`INSERT INTO camera_devices (site_code, brand, name, host, token_hash) VALUES ($1, 'onvif', $2, '10.0.0.5', 'x') RETURNING id`, [site, name])).rows[0].id);
    ids.camIn = await cam(ids.site, 'Giriş kamerası');
    ids.camOut = await cam(ids.site, 'Çıkış kamerası');
    ids.camFree = await cam(ids.site, 'Boşta kamera');
    ids.camOther = await cam(ids.other, 'Başka sitenin kamerası');
    await q(`INSERT INTO devices (device_uid, site_code, gate_name) VALUES ('SKP-PG-001', $1, 'Ana kapı')`, [ids.site]);
  });

  after(async () => {
    if (server) {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    }
    if (pool) await pool.end().catch(() => {});
    if (adminClient) {
      await adminClient.query(`DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`).catch(() => {});
      await adminClient.end().catch(() => {});
    }
  });

  it('şema: tablolar + sütunlar kurulu; ikinci ensure ve migration dosyası ikinci kez sorunsuz (idempotent)', async () => {
    for (const table of ['plate_gates', 'plate_gate_cameras', 'plate_edge_clients', 'plate_camera_status', 'plate_site_settings', 'plate_presence']) {
      assert.ok((await q(`SELECT to_regclass($1) AS t`, [`public.${table}`])).rows[0].t, table);
    }
    const { ensureDbSchema } = await import('../src/db.js');
    await ensureDbSchema();
    const { readFileSync } = await import('node:fs');
    await q(readFileSync(new URL('../migrations/120_plate_gates_edge.sql', import.meta.url), 'utf8'));
    assert.equal((await q(`SELECT parking_slots FROM apartments WHERE id = $1`, [ids.aptA])).rows[0].parking_slots, 0);
  });

  it('daire formu: park yeri sayısı PATCH ile kaydolur ve okunur; 51 ve null reddedilir', async () => {
    const patch = (value) => call('PATCH', `/manager/sites/${ids.site}/apartments/${ids.aptA}`, { token: ids.token, body: { parking_slots: value } });
    const ok = await patch(2);
    assert.equal(ok.status, 200, ok.text);
    assert.equal(ok.json.parking_slots ?? ok.json.apartment?.parking_slots, 2);
    assert.equal((await patch(51)).status, 400);
    assert.equal((await patch(null)).status, 400);
    assert.equal((await q(`SELECT parking_slots FROM apartments WHERE id = $1`, [ids.aptA])).rows[0].parking_slots, 2);
  });

  it('kapı CRUD: oluştur / çakışmalar / yön uyumu / güncelle / ilk durum "hiç bağlanmadı"', async () => {
    const created = await mgr('POST', '/gates', {
      name: 'Ana Kapı',
      direction_mode: 'cift',
      device_uid: 'SKP-PG-001',
      cameras: [{ camera_id: ids.camIn, direction: 'giris' }, { camera_id: ids.camOut, direction: 'cikis' }],
    });
    assert.equal(created.status, 201, created.text);
    const gate = created.json.gates[0];
    ids.gate = gate.id;
    assert.equal(gate.cameras.length, 2);
    assert.equal(gate.status.state, 'hic_baglanmadi');
    assert.equal(gate.device.status.state, 'hic_baglanmadi');
    assert.deepEqual(created.json.unassigned_cameras.map((c) => c.id), [ids.camFree]);
    assert.equal((await mgr('POST', '/gates', { name: 'ana kapı' })).json.code, 'GATE_NAME_TAKEN');
    assert.equal((await mgr('POST', '/gates', { name: 'Yan Kapı', cameras: [{ camera_id: ids.camIn }] })).json.code, 'CAMERA_ALREADY_MAPPED');
    assert.equal((await mgr('POST', '/gates', { name: 'Yan Kapı', device_uid: 'SKP-PG-001' })).json.code, 'DEVICE_ALREADY_MAPPED');
    assert.equal((await mgr('POST', '/gates', { name: 'Yan Kapı', cameras: [{ camera_id: ids.camOther }] })).json.code, 'CAMERA_NOT_FOUND');
    assert.equal((await mgr('POST', '/gates', { name: 'Yalnız Giriş', direction_mode: 'giris', cameras: [{ camera_id: ids.camFree, direction: 'cikis' }] })).json.code, 'CAMERA_DIRECTION_CONFLICT');
    const second = await mgr('POST', '/gates', { name: 'Yan Kapı', direction_mode: 'giris', cameras: [{ camera_id: ids.camFree }] });
    assert.equal(second.status, 201, second.text);
    ids.gate2 = second.json.gates.find((g) => g.name === 'Yan Kapı').id;
    const renamed = await mgr('PUT', `/gates/${ids.gate2}`, { name: 'Servis Kapısı', cameras: [] });
    assert.equal(renamed.status, 200, renamed.text);
    assert.deepEqual(renamed.json.gates.find((g) => g.id === ids.gate2).cameras, []);
    assert.equal((await mgr('DELETE', `/gates/${ids.gate2}`)).status, 200);
    assert.equal((await mgr('DELETE', `/gates/${ids.gate2}`)).status, 404);
  });

  it('site ayarı: misafir kuralı + eşikler site ayarıdır; geçersiz aralık / kırmızı<=sarı 400', async () => {
    assert.equal((await mgr('GET', '/gate-settings')).json.settings.guest_rule, 'tum_bos');
    assert.equal((await mgr('PUT', '/gate-settings', { guest_rule: 'en_az_bir_bos' })).json.settings.guest_rule, 'en_az_bir_bos');
    assert.equal((await mgr('PUT', '/gate-settings', { guest_rule: 'tum_bos' })).json.settings.guest_rule, 'tum_bos');
    assert.equal((await mgr('PUT', '/gate-settings', { guest_rule: 'rastgele' })).status, 400);
    assert.equal((await mgr('PUT', '/gate-settings', { heartbeat_warn_seconds: 700 })).status, 400);
    assert.equal((await mgr('PUT', '/gate-settings', { heartbeat_warn_seconds: 180, heartbeat_crit_seconds: 600 })).status, 200);
  });

  it('kenar istemci: anahtar bir kez görünür, DB\'de düz yok; yanlış anahtar 401; claim; kalp atışı -> rozetler', async () => {
    const created = await mgr('POST', '/edge-clients', { name: 'Kulübe PC' });
    assert.equal(created.status, 201, created.text);
    ids.edgeKey = created.json.edge_key;
    ids.edgeId = created.json.client.id;
    assert.match(ids.edgeKey, /^\d+\.[a-f0-9]{48}$/);
    const stored = (await q(`SELECT key_hash FROM plate_edge_clients WHERE id = $1`, [ids.edgeId])).rows[0].key_hash;
    assert.ok(!ids.edgeKey.includes(stored) && !stored.includes(ids.edgeKey.split('.')[1]));
    assert.equal((await edge('POST', '/claim', {}, `${ids.edgeId}.${'0'.repeat(48)}`)).status, 401);
    assert.equal((await call('POST', '/edge/plate/v1/claim', { body: {} })).status, 401);
    const claim = await edge('POST', '/claim', { schema_version: 1, app_version: '0.1.0' });
    assert.equal(claim.status, 200, claim.text);
    assert.equal(claim.json.schema_version, 3);
    assert.deepEqual(claim.json.supported_schema_versions, [1, 2, 3]);
    assert.equal(claim.json.intervals.heartbeat_seconds, 60);
    assert.equal((await edge('POST', '/claim', { schema_version: 9 })).json.code, 'UNSUPPORTED_SCHEMA');
    const beat = await edge('POST', '/heartbeat', {
      schema_version: 1,
      queue_depth: 0,
      cameras: [{ camera_id: ids.camIn, last_frame_at: ago(5) }, { camera_id: ids.camOut, last_frame_at: ago(300) }, { camera_id: ids.camOther, last_frame_at: ago(1) }],
    });
    assert.equal(beat.status, 200, beat.text);
    const overview = (await mgr('GET', '/gates')).json;
    const cams = Object.fromEntries(overview.gates.find((g) => g.id === ids.gate).cameras.map((c) => [c.camera_id, c.status.color]));
    assert.equal(cams[ids.camIn], 'yesil');
    assert.equal(cams[ids.camOut], 'sari');
    assert.equal(overview.edge_clients[0].status.color, 'yesil');
    assert.equal((await q(`SELECT 1 FROM plate_camera_status WHERE camera_id = $1`, [ids.camOther])).rows.length, 0, 'başka sitenin kamerası yazılmaz');
    await q(`UPDATE plate_camera_status SET last_frame_at = NOW() - INTERVAL '20 minutes' WHERE camera_id = $1`, [ids.camOut]);
    assert.equal((await mgr('GET', '/gates')).json.gates.find((g) => g.id === ids.gate).status.color, 'kirmizi');
  });

  it('olaylar: kayıtlı araç girişi "içeride" işaretler; aynı event_id idempotent; çıkış düşürür; sıra dışı eski olay etkisiz', async () => {
    const enter = await edge('POST', '/events', evt(1, { seen_at: ago(60) }));
    assert.equal(enter.status, 200, enter.text);
    assert.deepEqual([enter.json.duplicate, enter.json.direction, enter.json.inside], [false, 'giris', true]);
    const dup = await edge('POST', '/events', evt(1, { seen_at: ago(60) }));
    assert.deepEqual([dup.status, dup.json.duplicate], [200, true]);
    assert.equal((await q(`SELECT COUNT(*)::INT AS n FROM plate_events WHERE client_event_id = 'evt-pg-000001'`)).rows[0].n, 1);
    const sync = (await edge('GET', '/sync')).json;
    assert.deepEqual(sync.apartments.find((a) => a.id === ids.aptA), { id: ids.aptA, parking_slots: 2, inside_count: 1 });
    // 2 park yerli dairede 1 araç içeride: varsayılan kuralda misafir kabul edilmez (kenar bu veriyle yerelde karar verir).
    const { evaluateGuestAdmission } = await import('../src/modules/plate_gates_common.js');
    assert.equal(evaluateGuestAdmission({ parkingSlots: 2, insideCount: 1, rule: sync.config.settings.guest_rule }).allowed, false);
    const stale = await edge('POST', '/events', evt(2, { camera_id: ids.camOut, seen_at: ago(3600) }));
    assert.deepEqual([stale.json.direction, stale.json.inside], ['cikis', true], 'eski çıkış olayı daha yeni girişi bozmaz');
    const leave = await edge('POST', '/events', evt(3, { camera_id: ids.camOut, seen_at: ago(10) }));
    assert.deepEqual([leave.json.direction, leave.json.inside], ['cikis', false]);
    const after = (await edge('GET', '/sync')).json;
    assert.equal(after.apartments.find((a) => a.id === ids.aptA).inside_count, 0);
  });

  it('tanımsız plaka içeriye alınmaz (yalnız loglanır); misafir izni daireye bağlanır; kapı/yön kamera bağından türetilir', async () => {
    const unknown = await edge('POST', '/events', evt(4, { plate: '06XYZ99', decision: 'tanimsiz' }));
    assert.deepEqual([unknown.json.direction, unknown.json.inside], ['giris', false]);
    assert.equal((await q(`SELECT 1 FROM plate_presence WHERE plate = '06XYZ99'`)).rows.length, 0);
    await q(`INSERT INTO plate_guest_permits (site_code, apartment_id, plate, valid_until) VALUES ($1, $2, '35GST123', NOW() + INTERVAL '2 days')`, [ids.site, ids.aptA]);
    const guest = await edge('POST', '/events', evt(5, { plate: '35GST123', seen_at: ago(5) }));
    assert.equal(guest.json.inside, true);
    const row = (await q(`SELECT kind, apartment_id, gate_id FROM plate_presence WHERE plate = '35GST123'`)).rows[0];
    assert.deepEqual([row.kind, Number(row.apartment_id), Number(row.gate_id)], ['guest', ids.aptA, ids.gate]);
    assert.equal((await edge('POST', '/events', evt(6, { camera_id: ids.camOther }))).json.code, 'CAMERA_NOT_FOUND');
    assert.equal((await edge('POST', '/events', evt(7, { plate: 'ABC' }))).status, 400);
    const inside = (await mgr('GET', '/inside')).json;
    assert.equal(inside.total, 1);
    assert.equal(inside.apartments.find((a) => a.id === ids.aptA).guest_admit.allowed, false);
    const feed = (await mgr('GET', '/events')).json.events;
    assert.ok(feed.some((e) => e.decision === 'ALLOWED') && feed.some((e) => e.decision === 'UNKNOWN'), 'mevcut Olaylar akışı kenar olaylarını gösterir');
  });

  it('delta senkron: bölüm özeti aynıysa "değişmedi"; updated_since yalnız değişen "içeride" satırlarını (çıkış dahil) döner', async () => {
    // updated_since 2 sn çakışmayla okunur (yarış koruması): öncesindeki yazmalar çakışma penceresinin dışına çıksın.
    await new Promise((resolve) => setTimeout(resolve, 2300));
    const first = (await edge('GET', '/sync')).json;
    assert.equal(first.full, true);
    assert.deepEqual(first.vehicles.items.map((v) => v.plate), ['34ABC123']);
    assert.equal(first.guest_permits.items[0].plate, '35GST123');
    const again = (await edge('GET', `/sync?vehicles_rev=${first.vehicles.rev}&permits_rev=${first.guest_permits.rev}&blacklist_rev=${first.blacklist.rev}&updated_since=${encodeURIComponent(first.server_time)}`)).json;
    assert.equal(again.full, false);
    assert.equal(again.vehicles.unchanged, true);
    assert.equal(again.guest_permits.unchanged, true);
    assert.deepEqual(again.presence.items, []);
    await edge('POST', '/events', evt(8, { plate: '35GST123', camera_id: ids.camOut, seen_at: new Date().toISOString() }));
    const delta = (await edge('GET', `/sync?updated_since=${encodeURIComponent(first.server_time)}`)).json;
    assert.deepEqual(delta.presence.items.map((p) => [p.plate, p.inside]), [['35GST123', false]]);
    assert.equal(first.config.gates[0].cameras.length, 2);
  });

  it('elle düzeltme, modül kapalı ve iptal: clear düşürür; modül kapanınca 403; iptal edilen anahtar 401', async () => {
    await edge('POST', '/events', evt(9, { seen_at: new Date().toISOString() }));
    const row = (await q(`SELECT id FROM plate_presence WHERE plate = '34ABC123' AND inside`)).rows[0];
    assert.equal((await mgr('POST', `/inside/${row.id}/clear`)).status, 200);
    assert.equal((await mgr('GET', '/inside')).json.total, 0);
    await q(`UPDATE site_modules SET enabled = FALSE WHERE site_code = $1 AND module_code = 'plate_recognition'`, [ids.site]);
    const off = await edge('GET', '/sync');
    assert.deepEqual([off.status, off.json.code], [403, 'MODULE_DISABLED']);
    await q(`UPDATE site_modules SET enabled = TRUE WHERE site_code = $1 AND module_code = 'plate_recognition'`, [ids.site]);
    assert.equal((await mgr('POST', `/edge-clients/${ids.edgeId}/revoke`)).status, 200);
    assert.equal((await edge('GET', '/sync')).status, 401);
    const audits = (await q(`SELECT DISTINCT action FROM audit_log WHERE site_code = $1 AND action LIKE 'plate.%'`, [ids.site])).rows.map((r) => r.action);
    for (const action of ['plate.gate_created', 'plate.gate_updated', 'plate.gate_deleted', 'plate.site_settings_changed', 'plate.edge_client_created', 'plate.edge_client_revoked', 'plate.inside_cleared']) {
      assert.ok(audits.includes(action), action);
    }
  });

  it('A3 (121): kara liste kararı (sözleşme v2), içeride raporu + zaman aşımı, kopukluk uyarısı sınırlayıcısı, sakin bildirim tercihi', async () => {
    const created = await mgr('POST', '/edge-clients', { name: 'Kulübe PC 2' });
    assert.equal(created.status, 201, created.text);
    const key = created.json.edge_key;
    const e2 = (method, suffix, body) => edge(method, suffix, body, key);
    assert.equal((await e2('POST', '/claim', { schema_version: 2 })).json.schema_version, 3);

    // Site ayarı: yeni eşikler (zaman aşımı rapor eşiğinden büyük olmalı) ve varsayılanlar
    assert.equal((await mgr('PUT', '/gate-settings', { inside_report_hours: 4, inside_timeout_hours: 3 })).status, 400);
    const saved = await mgr('PUT', '/gate-settings', { inside_report_hours: 2, inside_timeout_hours: 4 });
    assert.equal(saved.status, 200, saved.text);
    assert.deepEqual([saved.json.settings.inside_report_hours, saved.json.settings.inside_timeout_hours, saved.json.settings.alert_interval_minutes], [2, 4, 60]);

    // Kara liste: tablo 073'te vardı; senkrona girer, v2 olay kara_liste karar türüyle kaydolur, içeri almaz
    const added = await mgr('POST', '/blacklist', { plate: '34 KRA 999', reason: 'deneme' });
    assert.equal(added.status, 201, added.text);
    assert.ok((await e2('GET', '/sync')).json.blacklist.items.some((b) => b.plate === '34KRA999'));
    assert.equal((await e2('POST', '/events', evt(20, { plate: '34KRA999', decision: 'kara_liste', schema_version: 1 }))).status, 400, 'v1 istemci kara_liste gönderemez');
    const black = await e2('POST', '/events', evt(21, { plate: '34KRA999', decision: 'kara_liste', schema_version: 2 }));
    assert.equal(black.status, 200, black.text);
    assert.equal(black.json.inside, false);
    assert.equal((await q(`SELECT decision_kind FROM plate_events WHERE client_event_id = 'evt-pg-000021'`)).rows[0].decision_kind, 'kara_liste');
    const legacy = (await q(`SELECT decision, reason FROM plate_decisions WHERE plate = '34KRA999'`)).rows[0];
    assert.deepEqual([legacy.decision, legacy.reason], ['DENIED', 'blacklist']);
    assert.equal((await q(`SELECT 1 FROM plate_presence WHERE plate = '34KRA999'`)).rows.length, 0);

    // Çıkışı olmayan girişler raporu (eşik site ayarı) + zaman aşımı bakımı (site ayarı: 4 saat)
    await q(`INSERT INTO plate_presence (site_code, plate, apartment_id, kind, inside, since_at) VALUES ($1, '34OLD111', $2, 'resident', TRUE, NOW() - INTERVAL '5 hours'), ($1, '34NEW222', $2, 'resident', TRUE, NOW())`, [ids.site, ids.aptA]);
    const report = (await mgr('GET', '/inside')).json;
    assert.equal(report.overdue.after_hours, 2);
    assert.deepEqual(report.overdue.items.map((i) => i.plate), ['34 OLD 111']);
    assert.ok(report.overdue.items[0].inside_hours >= 5);
    assert.ok(report.items.some((i) => i.plate === '34 NEW 222'));
    const { expireStalePresence, checkEdgeHealth, notifyResidentMovement } = await import('../src/modules/plate_notify.js');
    assert.equal(await expireStalePresence(pool), 1);
    assert.deepEqual((await q(`SELECT plate, inside FROM plate_presence WHERE plate IN ('34OLD111', '34NEW222') ORDER BY plate`)).rows.map((r) => [r.plate, r.inside]), [['34NEW222', true], ['34OLD111', false]]);
    const timeoutAudit = (await q(`SELECT details FROM audit_log WHERE site_code = $1 AND action = 'plate.inside_timeout'`, [ids.site])).rows[0];
    assert.equal(timeoutAudit.details.count, 1);
    assert.equal(timeoutAudit.details.timeout_hours, 4);
    assert.equal(await expireStalePresence(pool), 0, 'ikinci tur bir şey düşürmez');

    // Kopukluk uyarısı: kamera kırmızı eşiği aştı -> yöneticiye bir kez (kalıcı sınırlayıcı), tekrar çağrı sessiz
    const beat = await e2('POST', '/heartbeat', { schema_version: 2, cameras: [{ camera_id: ids.camIn, last_frame_at: ago(5) }, { camera_id: ids.camOut, last_frame_at: ago(1800) }] });
    assert.equal(beat.status, 200, beat.text);
    assert.deepEqual(await checkEdgeHealth(pool, ids.site), { lost: true, alerted: true });
    assert.deepEqual(await checkEdgeHealth(pool, ids.site), { lost: true, alerted: false });
    const lostAudit = (await q(`SELECT details FROM audit_log WHERE site_code = $1 AND action = 'plate.edge_disconnected'`, [ids.site])).rows;
    assert.equal(lostAudit.length, 1);
    assert.ok(lostAudit[0].details.cameras.includes('Çıkış kamerası'));
    const { runPlateHealthTick } = await import('../src/modules/plate_health_scheduler.js');
    const tick = await runPlateHealthTick();
    assert.deepEqual([tick.sites >= 1, tick.alerted, tick.expired], [true, 0, 0]);

    // Sakin tercihi: kişi bazında, varsayılan KAPALI; açıkken kayıtlı aracın sahibi bildirim alıcısı olur
    const resident = await q(
      `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash)
       VALUES ('Sakin', 'sakin-plaka@example.com', 'individual', TRUE, TRUE, 'approved', $1) RETURNING user_code`,
      [HASH],
    );
    const residentCode = resident.rows[0].user_code;
    await q(`INSERT INTO apartment_memberships (apartment_id, user_code) VALUES ($1, $2)`, [ids.aptA, residentCode]);
    const residentToken = signAccessToken({ id: residentCode }, { passwordHash: HASH });
    const app = (method, path, body) => call(method, path, { token: residentToken, body });
    assert.equal((await app('GET', `/app/plate-permits?site_code=${ids.site}`)).json.movement_notify, false);
    assert.equal((await app('PUT', '/app/plate-permits/notify', { site_code: ids.site, movement_enabled: 'evet' })).status, 400);
    const vehicle = (await q(`SELECT id, apartment_id, person_id FROM vehicles WHERE site_code = $1 AND plate = '34ABC123'`, [ids.site])).rows[0];
    const movement = { siteCode: ids.site, vehicle, direction: 'giris', seenAt: new Date() };
    assert.deepEqual(await notifyResidentMovement(movement), { skipped: 'no_opt_in' });
    assert.equal((await app('PUT', '/app/plate-permits/notify', { site_code: ids.site, movement_enabled: true })).status, 200);
    assert.equal((await app('GET', `/app/plate-permits?site_code=${ids.site}`)).json.movement_notify, true);
    assert.equal((await notifyResidentMovement(movement)).recipients, 1);
    assert.deepEqual(await notifyResidentMovement({ ...movement, seenAt: new Date(Date.now() - 3 * 3600_000) }), { skipped: 'stale' });
  });

  it('sözleşme v3 (122): komut kuyruğu (keşif + sınama), şifreli kamera parolası gidiş-dönüş, otomatik açma durumu, görüntü karoları (403/304/KVKK), kimlik + kapı günlüğü', async () => {
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0xff, 0xd9]);
    const rawFetch = (method, path, { token, edgeKey, headers = {}, body } = {}) =>
      fetch(`${baseUrl}${path}`, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(edgeKey ? { authorization: `Bearer ${edgeKey}` } : {}), ...headers }, body });
    const mgrRaw = (suffix, headers = {}, token = ids.token) => rawFetch('GET', `/manager/sites/${ids.site}/plate-recognition${suffix}`, { token, headers });

    // Site ayari: komut omru / goruntu araliklari / saklama suresi site ayaridir (aralik disi 400, bos aralik < aktif aralik 400)
    assert.equal((await mgr('PUT', '/gate-settings', { command_ttl_seconds: 30 })).status, 400);
    assert.equal((await mgr('PUT', '/gate-settings', { snapshot_interval_seconds: 30, snapshot_idle_interval_seconds: 10 })).status, 400);
    assert.deepEqual(
      [(await mgr('GET', '/gate-settings')).json.settings].map((s) => [s.command_ttl_seconds, s.snapshot_interval_seconds, s.snapshot_idle_interval_seconds, s.snapshot_keep_minutes])[0],
      [600, 4, 15, 30],
    );

    // Iki etkin kenar: komut icin secim zorunlu; birini kaldirinca tek kenar otomatik hedef
    const pc2 = Number((await q(`SELECT id FROM plate_edge_clients WHERE name = 'Kulübe PC 2'`)).rows[0].id);
    const pc3 = await mgr('POST', '/edge-clients', { name: 'Kulübe PC 3' });
    assert.equal(pc3.status, 201, pc3.text);
    const e3 = (method, suffix, body) => edge(method, suffix, body, pc3.json.edge_key);
    const needPick = await mgr('POST', '/discovery', {});
    assert.deepEqual([needPick.status, needPick.json.code, needPick.json.clients.length], [400, 'EDGE_CLIENT_REQUIRED', 2]);
    assert.equal((await mgr('POST', `/edge-clients/${pc2}/revoke`)).status, 200);
    assert.equal((await mgr('POST', '/discovery', { edge_client_id: pc2 })).json.code, 'EDGE_CLIENT_NOT_FOUND');

    // Otomatik acma durumu: kenar hic haber vermedi -> cevrimdisi (durust)
    assert.equal((await mgr('GET', '/cameras')).json.auto_open.reason, 'edge_offline');

    // Ağda kamera ara: kuyruga girer, kenar cevrimdisi oldugu soylenir, ayni komut tekrar acilmaz
    const started = await mgr('POST', '/discovery', {});
    assert.equal(started.status, 202, started.text);
    assert.deepEqual([started.json.command.status, started.json.command.waiting_offline, started.json.reused], ['pending', true, false]);
    const again = await mgr('POST', '/discovery', {});
    assert.deepEqual([again.json.reused, again.json.command.id], [true, started.json.command.id]);
    // Kenar kalp atisiyla alir (ATOMIK: ayni komut ikinci kez verilmez); surum 2 kalp atisi komut ALMAZ
    const v2beat = await e3('POST', '/heartbeat', { schema_version: 2, cameras: [] });
    assert.deepEqual(v2beat.json.commands, []);
    const beat = await e3('POST', '/heartbeat', { schema_version: 3, recognition: { ready: false, note: 'kalibrasyon modu' }, cameras: [{ camera_id: ids.camIn, last_frame_at: ago(3) }] });
    assert.equal(beat.status, 200, beat.text);
    assert.deepEqual(beat.json.commands.map((c) => [c.id, c.kind]), [[started.json.command.id, 'discover']]);
    assert.deepEqual((await e3('GET', '/commands')).json.commands, []);
    assert.equal((await mgr('GET', '/discovery')).json.command.status, 'running');
    const result = await e3('POST', `/commands/${started.json.command.id}/result`, {
      schema_version: 3,
      status: 'done',
      result: { devices: [{ ip: '192.168.50.20', ports: [554, 8000], name: 'Hik', model: 'DS-2CD', source: 'onvif+tarama', label: 'ONVIF kamera', rtsp_port: 554 }, { ip: 'gecersiz', ports: [] }], summary: '1 cihaz', onvif_count: 1, scan_count: 1, interfaces: ['192.168.50.5'] },
    });
    assert.deepEqual([result.status, result.json.ok, result.json.duplicate], [200, true, false]);
    assert.equal((await e3('POST', `/commands/${started.json.command.id}/result`, { schema_version: 3, status: 'done', result: {} })).json.duplicate, true, 'idempotent');
    const latest = (await mgr('GET', '/discovery')).json;
    assert.equal(latest.command.status, 'done');
    assert.deepEqual(latest.command.result.devices.map((d) => d.ip), ['192.168.50.20']);
    assert.equal(latest.edge.online, true);
    assert.equal((await edge('POST', `/commands/${started.json.command.id}/result`, { schema_version: 3, status: 'done' }, ids.edgeKey)).status, 401, 'iptal edilen anahtar');

    // Otomatik acma: model onaylanmadi -> nedenli; onaylaninca (kapiya bagli etkin kamera var) Etkin
    assert.equal((await mgr('GET', '/cameras')).json.auto_open.reason, 'model_not_approved');
    await e3('POST', '/heartbeat', { schema_version: 3, recognition: { ready: true }, cameras: [{ camera_id: ids.camIn, last_frame_at: ago(3) }] });
    const overview = (await mgr('GET', '/cameras')).json;
    assert.equal(overview.auto_open.state, 'active');
    assert.equal(overview.edge.clients[0].recognition_ready, true);
    assert.equal(overview.cameras.find((c) => c.id === ids.camIn).status.color, 'yesil');
    assert.equal(overview.cameras.find((c) => c.id === ids.camIn).gate.id, ids.gate);

    // Uygulamadan kamera ekle: parola SIFRELI, yanitta yok; marka sablonuyla RTSP adresi; kapi + yon baglanir; sinama komutu kuyruga girer
    assert.equal((await mgr('POST', '/cameras', { name: 'Yan Giriş', brand: 'sony', host: '192.168.50.20' })).status, 400);
    assert.equal((await mgr('POST', '/cameras', { name: 'Yan Giriş', brand: 'hikvision', host: '192.168.50.20', gate_id: 999999 })).json.code, 'GATE_NOT_FOUND');
    const added = await mgr('POST', '/cameras', { name: 'Yan Giriş', brand: 'hikvision', host: '192.168.50.20', username: 'admin', password: 'Gizli-Parola-1', gate_id: ids.gate, direction: 'giris' });
    assert.equal(added.status, 201, added.text);
    const camId = added.json.camera.id;
    assert.equal(added.json.camera.rtsp_url, 'rtsp://192.168.50.20/Streaming/Channels/101');
    assert.deepEqual([added.json.camera.has_password, added.json.camera.direction, added.json.camera.gate.id, added.json.camera.probe.status], [true, 'giris', ids.gate, 'pending']);
    assert.ok(!added.text.includes('Gizli-Parola-1'));
    const stored = (await q(`SELECT password_enc, probe_status FROM camera_devices WHERE id = $1`, [camId])).rows[0];
    assert.ok(stored.password_enc.startsWith('v1:') && !stored.password_enc.includes('Gizli'), 'AES-256-GCM sifreli saklanir');
    assert.equal((await q(`SELECT 1 FROM plate_edge_commands WHERE payload::text LIKE '%Gizli%'`)).rows.length, 0, 'kuyrukta duz parola yok');
    const probeCmd = (await e3('GET', '/commands')).json.commands[0];
    assert.deepEqual([probeCmd.id, probeCmd.kind, probeCmd.payload.camera_id, probeCmd.payload.password, probeCmd.payload.username, probeCmd.payload.host], [added.json.probe_command_id, 'probe', camId, 'Gizli-Parola-1', 'admin', '192.168.50.20']);
    assert.equal((await e3('POST', `/commands/${probeCmd.id}/result`, { schema_version: 3, status: 'done', result: { ok: true, width: 1920, height: 1080 } })).status, 200);
    const probed = (await mgr('GET', '/cameras')).json.cameras.find((c) => c.id === camId);
    assert.deepEqual([probed.probe.status, probed.probe.width, probed.probe.height], ['ok', 1920, 1080]);
    // Uygulama "Yeniden sina": ulasilamayan kamera durust "basarisiz" + mesaj
    const reprobe = await mgr('POST', `/cameras/${camId}/probe`, {});
    assert.equal(reprobe.status, 202, reprobe.text);
    const cmd2 = (await e3('GET', '/commands')).json.commands[0];
    await e3('POST', `/commands/${cmd2.id}/result`, { schema_version: 3, status: 'done', result: { ok: false, reason: 'baglanti_acilamadi', message: 'RTSP bağlantısı açılamadı' } });
    const failedProbe = (await mgr('GET', '/cameras')).json.cameras.find((c) => c.id === camId).probe;
    assert.deepEqual([failedProbe.status, failedProbe.message], ['failed', 'RTSP bağlantısı açılamadı']);

    // Kenar sync: v3 istemci kamera tanimlarini (parola cozulmus) alir; v2 almaz
    const sync3 = (await e3('GET', '/sync?schema_version=3')).json;
    const synced = sync3.config.cameras.find((c) => c.camera_id === camId);
    assert.deepEqual([synced.password, synced.username, synced.rtsp_url, synced.gate_id, synced.direction], ['Gizli-Parola-1', 'admin', 'rtsp://192.168.50.20/Streaming/Channels/101', ids.gate, 'giris']);
    assert.deepEqual((await e3('GET', '/sync?schema_version=2')).json.config.cameras, []);
    assert.equal(sync3.config.settings.snapshot_interval_seconds, 4);

    // Parola degisince yeniden sinanir (yeni parola kenara iner); bos metin parolayi siler
    const changed = await mgr('PUT', `/cameras/${camId}`, { password: 'Yeni-Parola-2' });
    assert.equal(changed.status, 200, changed.text);
    assert.ok(changed.json.probe_command_id);
    assert.equal((await e3('GET', '/commands')).json.commands[0].payload.password, 'Yeni-Parola-2');
    await mgr('PUT', `/cameras/${camId}`, { password: '' });
    assert.equal((await q(`SELECT password_enc FROM camera_devices WHERE id = $1`, [camId])).rows[0].password_enc, null);
    await mgr('PUT', `/cameras/${camId}`, { password: 'Yeni-Parola-2' });

    // Goruntu karolari: yalniz SON kare; izleyen yokken bosta araligi, izleyince kisa aralik; yetkisiz 403; ETag/304; sinirlar
    const snapPath = `/edge/plate/v1/cameras/${camId}/snapshot`;
    const put = (buf, headers = {}, key = pc3.json.edge_key, path = snapPath) => rawFetch('PUT', path, { edgeKey: key, headers: { 'content-type': 'image/jpeg', ...headers }, body: buf });
    assert.equal((await q(`SELECT 1 FROM plate_snapshot_watch WHERE site_code = $1`, [ids.site])).rows.length, 1, 'yonetici ekrani acilinca izleyen isaretlendi');
    await q(`UPDATE plate_snapshot_watch SET watched_at = NOW() - INTERVAL '10 minutes' WHERE site_code = $1`, [ids.site]);
    const first = await put(jpeg, { 'x-frame-width': '640', 'x-frame-height': '360', 'x-captured-at': new Date(Date.now() - 2000).toISOString() });
    assert.equal(first.status, 200, await first.clone().text());
    assert.deepEqual(await first.json(), { schema_version: 3, ok: true, watched: false, next_seconds: 15 });
    assert.equal((await put(Buffer.from('<html>'))).status, 400);
    assert.equal((await put(Buffer.concat([jpeg, Buffer.alloc(300_000, 1)]))).status, 413);
    assert.equal((await put(jpeg, {}, `${pc3.json.client.id}.${'0'.repeat(48)}`)).status, 401);
    assert.equal((await put(jpeg, {}, pc3.json.edge_key, `/edge/plate/v1/cameras/${ids.camOther}/snapshot`)).status, 404, 'baska sitenin kamerasi');
    assert.equal((await rawFetch('PUT', snapPath, { edgeKey: pc3.json.edge_key, headers: { 'content-type': 'application/json' }, body: '{}' })).status, 400, 'JPEG degil');
    const unprivileged = await q(
      `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash) VALUES ('Yabancı', 'yabanci-plaka@example.com', 'individual', TRUE, TRUE, 'approved', $1) RETURNING user_code`,
      [HASH],
    );
    const outsiderToken = signAccessToken({ id: unprivileged.rows[0].user_code }, { passwordHash: HASH });
    for (const suffix of [`/cameras/${camId}/snapshot`, '/cameras', '/discovery']) assert.equal((await mgrRaw(suffix, {}, outsiderToken)).status, 403, suffix);
    const shot = await mgrRaw(`/cameras/${camId}/snapshot`);
    assert.equal(shot.status, 200);
    assert.equal(shot.headers.get('content-type'), 'image/jpeg');
    assert.equal(shot.headers.get('cache-control'), 'no-store');
    assert.deepEqual(Buffer.from(await shot.arrayBuffer()), jpeg);
    assert.equal((await mgrRaw(`/cameras/${camId}/snapshot`, { 'if-none-match': shot.headers.get('etag') })).status, 304);
    assert.equal((await mgrRaw(`/cameras/${ids.camOther}/snapshot`)).status, 404, 'baska sitenin karesi');
    const watched = await put(jpeg);
    assert.deepEqual([(await watched.json()).watched], [true]);
    const old = await put(Buffer.concat([jpeg, Buffer.from([1, 2, 3])]), { 'x-captured-at': new Date(Date.now() - 300_000).toISOString() });
    assert.equal(old.status, 200);
    assert.equal(Number((await q(`SELECT byte_size FROM plate_camera_snapshots WHERE camera_id = $1`, [camId])).rows[0].byte_size), jpeg.length, 'eski kare yeni kareyi EZMEZ');
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM plate_camera_snapshots WHERE camera_id = $1`, [camId])).rows[0].n), 1, 'tarihce yok: kamera basina tek satir');

    // KVKK bakimi: saklama suresi gecen kare silinir; pasif kameranin karesi hemen silinir ve sync'ten cikar
    const { runCamerasHousekeeping } = await import('../src/modules/plate_cameras_service.js');
    await q(`UPDATE plate_camera_snapshots SET received_at = NOW() - INTERVAL '2 hours' WHERE camera_id = $1`, [camId]);
    assert.equal((await mgrRaw(`/cameras/${camId}/snapshot`)).status, 404, 'saklama suresi disinda gosterilmez');
    assert.equal((await runCamerasHousekeeping(pool)).snapshotsRemoved, 1);
    await put(jpeg);
    assert.equal((await mgr('PUT', `/cameras/${camId}`, { is_active: false })).status, 200);
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM plate_camera_snapshots WHERE camera_id = $1`, [camId])).rows[0].n), 0);
    assert.equal((await put(jpeg)).status, 409);
    assert.equal((await e3('GET', '/sync?schema_version=3')).json.config.cameras.some((c) => c.camera_id === camId), false);
    assert.equal((await mgr('POST', `/cameras/${camId}/probe`, {})).json.code, 'CAMERA_INACTIVE');

    // Komut suresi dolumu: bekleyen komut `expired`; sinamasi bekleyen kamera durust "basarisiz"
    assert.equal((await mgr('PUT', '/gate-settings', { command_ttl_seconds: 60 })).status, 200);
    const stale = await mgr('POST', '/discovery', {});
    await q(`UPDATE plate_edge_commands SET created_at = NOW() - INTERVAL '2 hours' WHERE id = $1`, [stale.json.command.id]);
    assert.equal((await mgr('GET', '/discovery')).json.command.status, 'expired');
    assert.deepEqual((await e3('GET', '/commands')).json.commands, []);
    assert.equal((await mgr('PUT', '/gate-settings', { command_ttl_seconds: 600 })).status, 200);

    // Kimlik baglama + kapi komutu + SmartKeyPass kapi gunlugu
    const person = await q(`INSERT INTO site_people (site_code, full_name) VALUES ($1, 'Ali Yılmaz') RETURNING id`, [ids.site]);
    await q(`UPDATE vehicles SET person_id = $1 WHERE site_code = $2 AND plate = '34ABC123'`, [person.rows[0].id, ids.site]);
    const accepted = await e3('POST', '/events', evt(40, { schema_version: 3, direction: 'giris', gate_command: 'accepted', apartment_id: ids.aptA, kind: 'resident' }));
    assert.equal(accepted.status, 200, accepted.text);
    const stored1 = (await q(`SELECT apartment_id, person_id, identity_kind, gate_command FROM plate_events WHERE client_event_id = 'evt-pg-000040'`)).rows[0];
    assert.deepEqual([Number(stored1.apartment_id), Number(stored1.person_id), stored1.identity_kind, stored1.gate_command], [ids.aptA, Number(person.rows[0].id), 'resident', 'accepted']);
    const doorLogs = async () => (await q(`SELECT door_name, user_name, apartment_label, trigger_type, door_id FROM door_access_logs WHERE site_code = $1 AND trigger_type = 'plate' ORDER BY id`, [ids.site])).rows;
    let logs = await doorLogs();
    const logsBefore = logs.length - 1; // onceki testlerdeki surum 1 olaylari da (acildi = komut kabul edildi) "Plaka ile" satiri birakmistir
    assert.ok(logsBefore >= 0);
    assert.deepEqual([logs.at(-1).door_name, logs.at(-1).user_name, logs.at(-1).apartment_label], ['Ana Kapı', '34 ABC 123 · Ali Y.', 'A - 1']);
    assert.equal((await e3('POST', '/events', evt(40, { schema_version: 3, gate_command: 'accepted' }))).json.duplicate, true);
    const refused = await e3('POST', '/events', evt(41, { schema_version: 3, decision: 'red', direction: 'cikis', gate_command: 'failed', reason: 'cihaz_yanit_vermedi' }));
    assert.equal(refused.status, 200, refused.text);
    logs = await doorLogs();
    assert.equal(logs.length, logsBefore + 1, 'tekrar ve reddedilen komut kapi gunlugune yazilmaz');
    const feed = (await mgr('GET', '/events?live=1')).json.events;
    assert.deepEqual(feed[0].gate_state, 'no_response');
    const okRow = feed.find((e) => e.gate_state === 'triggered' && e.identity);
    assert.deepEqual(okRow.identity, { kind: 'resident', apartment_label: 'A - 1', person_label: 'Ali Y.' });
    assert.ok(!JSON.stringify(feed).includes('Yılmaz'), 'tam soyad donmez');
    const labels = (await e3('GET', '/sync?schema_version=3')).json.vehicles.items.find((v) => v.plate === '34ABC123');
    assert.deepEqual([labels.apartment_label, labels.person_label], ['A - 1', 'Ali Y.']);
    const audits = (await q(`SELECT DISTINCT action FROM audit_log WHERE site_code = $1 AND action LIKE 'plate.%'`, [ids.site])).rows.map((r) => r.action);
    for (const action of ['plate.camera_created', 'plate.camera_updated', 'plate.camera_probe_requested', 'plate.discovery_requested']) assert.ok(audits.includes(action), action);
    const auditText = JSON.stringify((await q(`SELECT details FROM audit_log WHERE site_code = $1 AND action LIKE 'plate.camera%'`, [ids.site])).rows);
    assert.ok(!auditText.includes('Parola') && !auditText.includes('Gizli'), 'denetim kaydinda parola yok');
  });
});
