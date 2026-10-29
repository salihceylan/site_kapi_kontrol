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
    assert.equal(claim.json.schema_version, 2);
    assert.deepEqual(claim.json.supported_schema_versions, [1, 2]);
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
    assert.equal((await e2('POST', '/claim', { schema_version: 2 })).json.schema_version, 2);

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
});
