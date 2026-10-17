// Belgeler (Faz 3b-A) duyuru eki (DB'siz, KATI sahte istemci): document_ids doğrulaması, ekleme kuralları (aynı site, active, residents, modül açık), kilit sırası
// (documents FOR KEY SHARE id sırasıyla -> ek bağları), audit, hata toleransı, e-postada ek sayısı notu. Gerçek PG: qa_platform_pg.mjs "documents" (K bölümü).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { buildAnnouncementEmail } from '../src/mailer.js';
import { getAnnouncementDetail } from '../src/modules/announcement_service.js';
import { loadAttachmentCounts, loadAttachments, loadAttachmentsSafe, parseDocumentIds, setAnnouncementAttachments } from '../src/modules/document_attachments.js';

const SITE = 1000000001;
const ACTOR = { user_code: 20001, userCode: 20001, id: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const code = async (promise) => {
  try {
    await promise;
    return null;
  } catch (error) {
    return `${error.statusCode}:${error.code}`;
  }
};

function fakeClient({ existing = [], docs = [], moduleEnabled = true } = {}) {
  const log = [];
  return {
    log,
    async query(text, params = []) {
      const sql = norm(text);
      log.push({ sql, params });
      if (/^SELECT document_id FROM announcement_attachments WHERE announcement_id = \$1 ORDER BY position, document_id$/.test(sql)) return ok(existing.map((id) => ({ document_id: String(id) })));
      if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) return ok([{ enabled: moduleEnabled }]);
      if (/^SELECT id, site_code, status, audience FROM documents WHERE id = ANY\(\$1::BIGINT\[\]\) ORDER BY id FOR KEY SHARE$/.test(sql)) {
        const wanted = new Set(params[0].map(Number));
        return ok(docs.filter((doc) => wanted.has(Number(doc.id))));
      }
      if (/^(DELETE FROM announcement_attachments|INSERT INTO announcement_attachments|INSERT INTO audit_log|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)/.test(sql)) return ok();
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 200)}`);
    },
  };
}

const goodDoc = (id, over = {}) => ({ id: String(id), site_code: String(SITE), status: 'active', audience: 'residents', ...over });
const run = (client, documentIds) => setAnnouncementAttachments(client, { siteCode: SITE, announcementId: 41, documentIds, actor: ACTOR });

describe('document_ids doğrulaması', () => {
  it('yok -> undefined (alan gönderilmedi); null / boş dizi -> [] (hepsini kaldır); tekilleştirilir; <= 5; geçersiz kimlik 400 INVALID_BODY', () => {
    assert.equal(parseDocumentIds(undefined), undefined);
    assert.deepEqual(parseDocumentIds(null), []);
    assert.deepEqual(parseDocumentIds([]), []);
    assert.deepEqual(parseDocumentIds([3, '4', 3]), [3, 4]);
    for (const bad of ['x', 5, {}, [0], [-1], ['abc'], [1.5], [null], [1, 2, 3, 4, 5, 6]]) {
      assert.throws(() => parseDocumentIds(bad), (error) => error.statusCode === 400 && error.code === 'INVALID_BODY', JSON.stringify(bad));
    }
  });
});

describe('ek listesini değiştirme', () => {
  it('yeni ekler: modül açık denetlenir, belgeler id SIRASIYLA FOR KEY SHARE kilitlenir (girdi sırası ne olursa olsun), sonra bağlar yazılır (sıra = dizideki sıra), audit document.attached', async () => {
    const client = fakeClient({ docs: [goodDoc(9), goodDoc(4)] });
    const result = await run(client, [9, 4]);
    assert.deepEqual(result, { attached: 2, detached: 0 });
    const order = client.log.map((entry) => entry.sql);
    const lockAt = order.findIndex((sql) => /FOR KEY SHARE$/.test(sql));
    assert.ok(lockAt > 0);
    assert.ok(order.findIndex((sql) => /FROM site_modules/.test(sql)) < lockAt, 'modül kapısı kilitten önce');
    assert.deepEqual(client.log[lockAt].params, [[4, 9]], 'kilit sırası id artan (deadlock olmasın)');
    const inserts = client.log.filter((entry) => /^INSERT INTO announcement_attachments/.test(entry.sql));
    assert.deepEqual(inserts.map((entry) => entry.params), [[41, 9, 0], [41, 4, 1]]);
    assert.ok(inserts.every((entry) => /ON CONFLICT \(announcement_id, document_id\) DO UPDATE SET position = EXCLUDED\.position/.test(entry.sql)));
    assert.ok(lockAt < order.findIndex((sql) => /^INSERT INTO announcement_attachments/.test(sql)), 'önce kilit, sonra bağ');
    const audits = client.log.filter((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    assert.deepEqual(audits.map((entry) => entry.params[3]), ['document.attached', 'document.attached']);
    assert.deepEqual(audits.map((entry) => entry.params[6]), ['9', '4'], 'hedef = belge kimliği');
    assert.deepEqual(JSON.parse(audits[0].params[7]), { announcement_id: 41, count: 1 });
  });

  it('eklenemeyenler 409 ATTACHMENT_NOT_ALLOWED: olmayan belge, başka site, silinmiş / bekleyen belge, kurul / yönetici belgesi; hiçbir bağ yazılmaz', async () => {
    for (const doc of [
      goodDoc(9, { site_code: String(SITE + 1) }),
      goodDoc(9, { status: 'deleted' }),
      goodDoc(9, { status: 'pending' }),
      goodDoc(9, { audience: 'board' }),
      goodDoc(9, { audience: 'managers' }),
    ]) {
      const client = fakeClient({ docs: [doc] });
      assert.equal(await code(run(client, [9])), '409:ATTACHMENT_NOT_ALLOWED', JSON.stringify(doc));
      assert.ok(!client.log.some((entry) => /^INSERT INTO announcement_attachments/.test(entry.sql)));
    }
    const missing = fakeClient({ docs: [] });
    assert.equal(await code(run(missing, [9])), '409:ATTACHMENT_NOT_ALLOWED');
  });

  it('modül KAPALIYSA yeni ek 403 MODULE_DISABLED (belge tablosu okunmaz)', async () => {
    const client = fakeClient({ docs: [goodDoc(9)], moduleEnabled: false });
    assert.equal(await code(run(client, [9])), '403:MODULE_DISABLED');
    assert.ok(!client.log.some((entry) => /FROM documents/.test(entry.sql)));
  });

  it('kaldırma: eksik olanlar DELETE edilir ve document.detached yazılır; zaten ekli (artık geçersiz olsa bile) belge yeniden doğrulanmaz; değişiklik yoksa YAZMA yok', async () => {
    const client = fakeClient({ existing: [5, 6], docs: [] });
    const result = await run(client, [6]);
    assert.deepEqual(result, { attached: 0, detached: 1 });
    const removal = client.log.find((entry) => /^DELETE FROM announcement_attachments/.test(entry.sql));
    assert.deepEqual(removal.params, [41, [5]]);
    assert.ok(!client.log.some((entry) => /FROM documents/.test(entry.sql)), 'yeni ek yok: belge kilidi / okuması yok (kalan 6 yeniden doğrulanmaz)');
    assert.deepEqual(client.log.filter((entry) => /^INSERT INTO audit_log/.test(entry.sql)).map((entry) => entry.params[3]), ['document.detached']);
    const same = fakeClient({ existing: [5, 6] });
    assert.deepEqual(await run(same, [5, 6]), { attached: 0, detached: 0 });
    assert.equal(same.log.length, 1, 'yalnız mevcut listeyi okur');
    const clear = fakeClient({ existing: [5, 6] });
    assert.deepEqual(await run(clear, []), { attached: 0, detached: 2 });
  });

  it('yalnız sıra değişirse bağlar yeniden numaralanır ama attached / detached sayılmaz', async () => {
    const client = fakeClient({ existing: [5, 6] });
    assert.deepEqual(await run(client, [6, 5]), { attached: 0, detached: 0 });
    assert.deepEqual(client.log.filter((entry) => /^INSERT INTO announcement_attachments/.test(entry.sql)).map((entry) => entry.params), [[41, 6, 0], [41, 5, 1]]);
  });
});

describe('okuma yardımcıları', () => {
  it('ek listesi: duyurunun sitesindeki belgeler (aynı site JOIN), güncel sürüm, available = active + kitle residents + sürüm var + modül açık; sıra position', async () => {
    let captured;
    const db = {
      async query(text, params) {
        captured = { sql: norm(text), params };
        return ok([
          { announcement_id: '41', document_id: '9', title: 'Yönetmelik', display_name: 'y.pdf', mime_type: 'application/pdf', size_bytes: '2048', available: true },
          { announcement_id: '41', document_id: '4', title: 'Silinmiş', display_name: null, mime_type: null, size_bytes: null, available: false },
        ]);
      },
    };
    const map = await loadAttachments(db, [41, 'x', -2, 41]);
    assert.deepEqual(captured.params, [[41, 41]]);
    assert.match(captured.sql, /INNER JOIN announcements a ON a\.id = aa\.announcement_id INNER JOIN documents d ON d\.id = aa\.document_id AND d\.site_code = a\.site_code/);
    assert.match(captured.sql, /d\.status = 'active' AND d\.audience = 'residents' AND cv\.version_no IS NOT NULL AND EXISTS \(SELECT 1 FROM site_modules smod/);
    assert.match(captured.sql, /ORDER BY aa\.announcement_id, aa\.position, aa\.document_id$/);
    assert.deepEqual(map.get(41), [
      { document_id: 9, title: 'Yönetmelik', file_name: 'y.pdf', mime_type: 'application/pdf', size_bytes: 2048, available: true },
      { document_id: 4, title: null, file_name: null, mime_type: null, size_bytes: null, available: false },
    ]);
    assert.equal((await loadAttachments(db, [])).size, 0);
    const counts = await loadAttachmentCounts({ query: async () => ok([{ announcement_id: '41', n: 2 }]) }, [41]);
    assert.equal(counts.get(41), 2);
  });

  it('R9 F1 + F7: kitlesi residents dışına çekilen (ya da silinmiş) belge available=false olur ve SAKİN görünümünde ad / dosya adı / tür / boyut NULL döner; yönetici görünümü (forManager) bilgiyi korur', async () => {
    const leaky = [
      { announcement_id: '41', document_id: '9', title: 'Kurul tutanağı', display_name: 'tutanak-v2.pdf', mime_type: 'application/pdf', size_bytes: '4096', available: false },
      { announcement_id: '41', document_id: '4', title: 'Yönetmelik', display_name: 'y.pdf', mime_type: 'application/pdf', size_bytes: '2048', available: true },
    ];
    const db = { query: async () => ok(leaky) };
    const resident = await loadAttachments(db, [41]);
    assert.deepEqual(resident.get(41), [
      { document_id: 9, title: null, file_name: null, mime_type: null, size_bytes: null, available: false },
      { document_id: 4, title: 'Yönetmelik', file_name: 'y.pdf', mime_type: 'application/pdf', size_bytes: 2048, available: true },
    ]);
    assert.equal(JSON.stringify([...resident.values()]).includes('Kurul'), false, 'sızıntı yok');
    assert.equal(JSON.stringify([...resident.values()]).includes('tutanak-v2'), false);
    const manager = await loadAttachments(db, [41], { forManager: true });
    assert.deepEqual(manager.get(41)[0], { document_id: 9, title: 'Kurul tutanağı', file_name: 'tutanak-v2.pdf', mime_type: 'application/pdf', size_bytes: 4096, available: false });
    const safe = await loadAttachmentsSafe(db, [41], { forManager: true });
    assert.equal(safe.get(41)[0].title, 'Kurul tutanağı', 'loadAttachmentsSafe seçenekleri iletir');
    assert.equal((await loadAttachmentsSafe(db, [41])).get(41)[0].title, null, 'varsayılan sakin görünümü');
  });

  it('duyuru okumayı BOZMAZ: ek sorgusu hata verirse boş liste döner ve günlüğe yalnız hata KODU yazılır', async () => {
    const lines = [];
    const real = console.error;
    console.error = (...args) => lines.push(args.join(' '));
    try {
      const map = await loadAttachmentsSafe({ query: async () => { throw Object.assign(new Error('GIZLI-AYRINTI'), { code: '42P01' }); } }, [41]);
      assert.equal(map.size, 0);
    } finally {
      console.error = real;
    }
    assert.ok(lines.some((line) => line.includes('42P01')) && !lines.join(' ').includes('GIZLI'));
  });
});

describe('e-postada ek sayısı (dosya EKLENMEZ)', () => {
  const base = { to: 'sakin@example.com', siteName: 'Gül Sitesi', title: 'Su kesintisi', body: 'Yarın su yok.', importance: 'normal', hasAccount: true };

  it('ek varsa gövdeye "Bu duyurunun N eki var; uygulamadan görüntüleyin." satırı girer (düz metin + HTML); ek yoksa satır YOKTUR; e-postada dosya ekleri yok', () => {
    const withAttachments = buildAnnouncementEmail({ ...base, attachmentCount: 2 });
    assert.match(withAttachments.text, /Yarın su yok\.\n\nBu duyurunun 2 eki var; uygulamadan görüntüleyin\.\n\n--/);
    assert.match(withAttachments.html, /Bu duyurunun 2 eki var; uygulamadan görüntüleyin\./);
    assert.equal(withAttachments.attachments, undefined, 'e-postaya dosya eki KONMAZ (kişisel veri SMTP\'ye çıkmasın)');
    for (const count of [0, undefined, null, -3, 'x']) {
      const plain = buildAnnouncementEmail({ ...base, attachmentCount: count });
      assert.ok(!/eki var/.test(plain.text) && !/eki var/.test(plain.html), String(count));
    }
    assert.equal(buildAnnouncementEmail(base).text, buildAnnouncementEmail({ ...base, attachmentCount: 0 }).text, 'ek yokken ileti eskisiyle birebir aynı');
  });
});

describe('yönetici duyuru ayrıntısı UÇ NOKTASI: kullanılamayan ekin bilgisi KORUNUR (R16 P2-2, sözleşme A12)', () => {
  const annRow = {
    id: '41', title: 'Başlık', body: 'Metin', importance: 'normal', status: 'published', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: false,
    publish_at: null, published_at: new Date('2026-10-16T08:00:00.000Z'), edited_at: null, edit_count: 0, recipient_count: 3,
    created_at: new Date('2026-10-16T07:00:00.000Z'), created_by_name: 'Ayşe Yönetici',
  };
  function detailDb(rows) {
    const calls = [];
    return {
      calls,
      async query(text, params = []) {
        const sql = norm(text);
        calls.push({ sql, params });
        if (/^SELECT a\.id, a\.title, a\.body/.test(sql)) return ok([annRow]);
        if (/^SELECT email_status, COUNT/.test(sql)) return ok([]);
        if (/FROM announcement_attachments aa INNER JOIN announcements a/.test(sql)) return ok(rows);
        throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 120)}`);
      },
    };
  }
  const gone = { announcement_id: '41', document_id: '9', title: 'Kurul Tutanağı', display_name: 'tutanak-v2.pdf', mime_type: 'application/pdf', size_bytes: '4096', available: false };
  const fine = { announcement_id: '41', document_id: '4', title: 'Yönetmelik', display_name: 'y.pdf', mime_type: 'application/pdf', size_bytes: '2048', available: true };

  it('getAnnouncementDetail (yönetici / kurul ayrıntı ucu): available=false olan ekin başlık / dosya adı / tür / boyutu null DEĞİL, görünür', async () => {
    const detail = await getAnnouncementDetail(SITE, '41', detailDb([gone, fine]));
    assert.deepEqual(detail.attachments, [
      { document_id: 9, title: 'Kurul Tutanağı', file_name: 'tutanak-v2.pdf', mime_type: 'application/pdf', size_bytes: 4096, available: false },
      { document_id: 4, title: 'Yönetmelik', file_name: 'y.pdf', mime_type: 'application/pdf', size_bytes: 2048, available: true },
    ]);
    assert.equal(detail.attachment_count, 2);
  });

  it('sakin görünümü (announcement_inbox.js) AYNI veriyle varsayılan olarak maskeler: ayrım çağıranın forManager seçeneğindedir', async () => {
    const residentView = await loadAttachments(detailDb([gone, fine]), [41]);
    assert.equal(residentView.get(41)[0].title, null);
    assert.equal(residentView.get(41)[0].file_name, null);
    assert.equal(residentView.get(41)[1].title, 'Yönetmelik');
  });
});

describe('ek `available` ifadesi çağıranın site ilişkisini ister (R16 P2-5)', () => {
  function capture() {
    const seen = [];
    return { seen, db: { async query(text, params) { seen.push({ sql: norm(text), params }); return ok([]); } } };
  }

  it('sakin görünümü (userCode verilmiş): my_apts CTE + aktif ilişki / BOARD_MEMBER koşulu available içinde; parametreler [kimlikler, userCode]', async () => {
    const { seen, db } = capture();
    await loadAttachments(db, [41], { userCode: 20004 });
    assert.deepEqual(seen[0].params, [[41], 20004]);
    assert.match(seen[0].sql, /^WITH my_apts AS MATERIALIZED \( SELECT ap\.id, ap\.block_id, ap\.site_code FROM site_people sp .* WHERE sp\.user_code = \$2 AND sp\.is_active = TRUE \) SELECT aa\.announcement_id/);
    assert.match(seen[0].sql, /AND \( EXISTS \(SELECT 1 FROM my_apts m WHERE m\.site_code = d\.site_code\) OR EXISTS \(SELECT 1 FROM site_memberships sm WHERE sm\.site_code = d\.site_code AND sm\.user_code = \$2 AND sm\.role = 'BOARD_MEMBER' AND sm\.is_active = TRUE\) \)\) AS available/);
    assert.ok(!/target_type|target_block_ids|target_apartment_ids/.test(seen[0].sql), 'hedef (blok / daire) koşulu YOK (A12)');
  });

  it('yönetici görünümü (forManager) ve userCode\'suz çağrı ilişki aramaz', async () => {
    const manager = capture();
    await loadAttachments(manager.db, [41], { forManager: true, userCode: 20004 });
    assert.deepEqual(manager.seen[0].params, [[41]]);
    assert.ok(!/my_apts/.test(manager.seen[0].sql));
    const plain = capture();
    await loadAttachments(plain.db, [41]);
    assert.ok(!/my_apts/.test(plain.seen[0].sql));
  });

  it('taşınan sakin: ilişki koşulunu sağlamayan ek (available=false) sakin görünümünde maskelenir', async () => {
    const db = { query: async () => ok([{ announcement_id: '41', document_id: '9', title: 'Yönetmelik', display_name: 'v2-yeni.pdf', mime_type: 'application/pdf', size_bytes: '10', available: false }]) };
    const map = await loadAttachments(db, [41], { userCode: 20004 });
    assert.deepEqual(map.get(41), [{ document_id: 9, title: null, file_name: null, mime_type: null, size_bytes: null, available: false }]);
  });
});
