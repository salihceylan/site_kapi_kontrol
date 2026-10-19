// İş Takibi personel performans raporu (DB'siz): tarih aralığı ayrıştırma (İstanbul günleri, varsayılan 30 gün, 366 gün tavanı), SQL metin değişmezleri (site bağı,
// çözüm olayı seçimi, zaman dilimi), satırlardan rapor birleştirme (toplamlar, kategori sıfır doldurma, atanan adları / sıralama / zamanında oranı), sahte DB ile parametre
// akışı. Gerçek PostgreSQL doğrulaması (tohumlanmış veri ile sayılar): scripts/qa_platform_pg.mjs "work_tracking" L bölümü.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  REPORT_DEFAULT_DAYS,
  REPORT_MAX_DAYS,
  UNASSIGNED_LABEL,
  assembleReport,
  buildWorkReport,
  parseReportQuery,
  reportSql,
} from '../src/modules/work_tracking_report.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const TODAY = '2026-10-19';

describe('parseReportQuery', () => {
  it('varsayılan: to = bugün (İstanbul), from = bugün - 29 (30 gün dahil); tek uç verilirse diğeri tamamlanır', () => {
    assert.equal(REPORT_DEFAULT_DAYS, 30);
    assert.deepEqual(parseReportQuery({}, TODAY), { from: '2026-09-20', to: TODAY });
    assert.deepEqual(parseReportQuery({ to: '2026-03-01' }, TODAY), { from: '2026-01-31', to: '2026-03-01' });
    assert.deepEqual(parseReportQuery({ from: '2026-10-01' }, TODAY), { from: '2026-10-01', to: TODAY });
    assert.deepEqual(parseReportQuery({ from: '2026-10-19', to: '2026-10-19' }, TODAY), { from: TODAY, to: TODAY }, 'tek gün');
    assert.deepEqual(parseReportQuery({ from: '', to: ' ' }, TODAY), { from: '2026-09-20', to: TODAY }, 'boş değer = verilmemiş');
  });

  it('biçim / takvim / sıra / uzunluk hataları 400 INVALID_FIELD (366 gün kabul, 367 ret; 2100 üstü ve 1990 altı yıl ret)', () => {
    const reject = (query, pattern) => assert.throws(() => parseReportQuery(query, TODAY), (error) => error.statusCode === 400 && error.code === 'INVALID_FIELD' && pattern.test(error.message), JSON.stringify(query));
    reject({ from: '19-10-2026' }, /biçiminde/);
    reject({ to: 'dun' }, /biçiminde/);
    reject({ from: '2026-02-30' }, /geçerli bir gün/);
    reject({ from: '2101-01-01', to: '2101-01-02' }, /geçerli bir gün/);
    reject({ from: '2026-10-20', to: '2026-10-19' }, /sonra olamaz/);
    reject({ from: '2025-10-18', to: '2026-10-19' }, /en fazla 366/);
    assert.equal(REPORT_MAX_DAYS, 366);
    assert.deepEqual(parseReportQuery({ from: '2025-10-19', to: '2026-10-19' }, TODAY), { from: '2025-10-19', to: '2026-10-19' }, '366 gün (artık yıl değil) kabul');
    reject({ to: {} }, /biçiminde/);
    reject({ from: ['2026-10-01'] }, /biçiminde/);
  });
});

describe('SQL değişmezleri', () => {
  it('her sorgu site_code = $1 bağı taşır; sınırlar $2/$3 İstanbul günleri; çözüm olayı: önce cozuldu sonra kapandi, ilk olay; çözüm anındaki atanan: la (önce / aynı işlem) -> fa (sonraki ilk olayın from\'u) -> güncel; güvenli tamsayı', () => {
    for (const [name, text] of Object.entries(reportSql)) {
      const sql = norm(text);
      assert.ok(sql.includes('w.site_code = $1'), name);
      assert.ok(sql.includes("($2::date)::timestamp AT TIME ZONE 'Europe/Istanbul'") && sql.includes("($3::date + 1)::timestamp AT TIME ZONE 'Europe/Istanbul'"), name);
      assert.equal(/\$\{/.test(text), false, `${name}: enterpolasyon yok`);
    }
    const resolved = norm(reportSql.RESOLVED_SQL);
    assert.ok(resolved.includes("e.site_code = $1 AND e.event_type = 'status_changed' AND e.to_value IN ('cozuldu', 'kapandi')"));
    assert.ok(resolved.includes("ORDER BY e.work_item_id, (e.to_value <> 'cozuldu'), e.id"));
    assert.ok(resolved.includes('percentile_cont(0.5) WITHIN GROUP (ORDER BY hours)'));
    const assignee = norm(reportSql.ASSIGNEE_SQL);
    // la: çözüm olayına kadarki YA DA çözümle aynı işlemdeki (tek PATCH'te "ata + cozuldu": aynı created_at, daha büyük id) son atama
    assert.ok(assignee.includes("a.event_type = 'assigned' AND (a.id <= r.event_id OR a.created_at = r.resolved_at) ORDER BY a.id DESC LIMIT 1 ) la ON TRUE"));
    // fa: yoksa çözümden SONRAKİ ilk atamanın from_value'su (çözüm anında kimdeydi)
    assert.ok(assignee.includes("a.event_type = 'assigned' AND a.id > r.event_id ORDER BY a.id ASC LIMIT 1 ) fa ON TRUE"));
    assert.ok(assignee.includes('WHEN la.event_id IS NOT NULL THEN la.assignee WHEN fa.event_id IS NOT NULL THEN fa.assignee ELSE w.assigned_to END AS assignee'));
    // güvenli tamsayı: biçim + INTEGER aralığı iç içe CASE ile (dönüşüm yalnız biçim doğruysa)
    for (const column of ['a.to_value', 'a.from_value']) {
      assert.ok(assignee.includes(`CASE WHEN ${column} ~ '^[0-9]{1,10}$' THEN CASE WHEN ${column}::BIGINT BETWEEN 1 AND 2147483647 THEN ${column}::INTEGER END END`), column);
    }
    assert.ok(assignee.includes('FULL OUTER JOIN res_stats r ON COALESCE(o.user_code, 0) = COALESCE(r.user_code, 0)'));
    assert.ok(assignee.includes('u.deleted_at IS NOT NULL THEN NULL ELSE u.full_name END AS name'));
    const items = norm(reportSql.ITEMS_SQL);
    assert.ok(items.includes("w.status NOT IN ('cozuldu', 'kapandi', 'iptal') AND w.due_date < b.today"));
    assert.ok(items.includes('GROUP BY GROUPING SETS ((w.category), ())'));
  });
});

describe('assembleReport', () => {
  const generatedAt = new Date('2026-10-19T12:00:00Z');

  it('toplamlar + yuvarlama; kategori sıfır doldurma sabit sırada; atananlar ad sırasıyla, silinmiş "Silinmiş Kullanıcı", atanmamış "Atanmamış" en sonda; zamanında oranı null / 3 ondalık', () => {
    const report = assembleReport({
      from: '2026-09-20',
      to: '2026-10-19',
      generatedAt,
      itemRows: [
        { category: 'ariza', is_total: 0, opened: '3', closed: '1', cancelled: '0', open_now: '2', overdue_now: '1' },
        { category: 'bakim', is_total: 0, opened: '1', closed: '0', cancelled: '1', open_now: '0', overdue_now: '0' },
        { category: null, is_total: 1, opened: '4', closed: '1', cancelled: '1', open_now: '2', overdue_now: '1' },
      ],
      resolvedRows: [
        { category: 'ariza', is_total: 0, resolved: '2', avg_hours: '5.26', median_hours: '5.26' },
        { category: null, is_total: 1, resolved: '2', avg_hours: '5.26', median_hours: '4.04' },
      ],
      assigneeRows: [
        { user_code: null, open_now: '1', overdue_now: '1', resolved: '0', avg_hours: null, with_due: '0', on_time: '0', name: null },
        { user_code: '77', open_now: '1', overdue_now: '0', resolved: '2', avg_hours: '5.26', with_due: '2', on_time: '1', name: 'Zeynep' },
        { user_code: '78', open_now: '0', overdue_now: '0', resolved: '1', avg_hours: '48', with_due: '0', on_time: '0', name: null },
        { user_code: '79', open_now: '2', overdue_now: '0', resolved: '0', avg_hours: null, with_due: '0', on_time: '0', name: 'Ali' },
      ],
    });
    assert.deepEqual(report.totals, { opened: 4, resolved: 2, closed: 1, cancelled: 1, open_now: 2, overdue_now: 1, avg_resolution_hours: 5.3, median_resolution_hours: 4 });
    assert.deepEqual(report.by_category, [
      { category: 'ariza', opened: 3, resolved: 2 },
      { category: 'bakim', opened: 1, resolved: 0 },
      { category: 'sikayet_oneri', opened: 0, resolved: 0 },
      { category: 'diger', opened: 0, resolved: 0 },
    ]);
    assert.deepEqual(report.by_assignee, [
      { user_code: 79, name: 'Ali', open_now: 2, overdue_now: 0, resolved: 0, avg_resolution_hours: null, on_time_rate: null },
      { user_code: 78, name: 'Silinmiş Kullanıcı', open_now: 0, overdue_now: 0, resolved: 1, avg_resolution_hours: 48, on_time_rate: null },
      { user_code: 77, name: 'Zeynep', open_now: 1, overdue_now: 0, resolved: 2, avg_resolution_hours: 5.3, on_time_rate: 0.5 },
      { user_code: null, name: UNASSIGNED_LABEL, open_now: 1, overdue_now: 1, resolved: 0, avg_resolution_hours: null, on_time_rate: null },
    ]);
    assert.deepEqual([report.from, report.to, report.generated_at], ['2026-09-20', '2026-10-19', '2026-10-19T12:00:00.000Z']);
  });

  it('boş site: sıfırlar, null süreler, boş atanan listesi, 4 kategori', () => {
    const report = assembleReport({ from: '2026-10-01', to: '2026-10-19', itemRows: [], resolvedRows: [], assigneeRows: [] });
    assert.deepEqual(report.totals, { opened: 0, resolved: 0, closed: 0, cancelled: 0, open_now: 0, overdue_now: 0, avg_resolution_hours: null, median_resolution_hours: null });
    assert.equal(report.by_category.length, 4);
    assert.deepEqual(report.by_assignee, []);
    assert.equal(typeof report.generated_at, 'string');
  });
});

describe('buildWorkReport (sahte DB)', () => {
  function fakeDb(today = TODAY) {
    const log = [];
    return {
      log,
      async query(text, params = []) {
        const sql = norm(text);
        log.push({ sql, params });
        if (/::date::text AS today$/.test(sql)) return { rows: [{ today }] };
        if (/GROUPING\(w\.category\)/.test(sql)) return { rows: [{ category: null, is_total: 1, opened: 2, closed: 0, cancelled: 0, open_now: 2, overdue_now: 0 }] };
        if (/GROUPING\(category\) AS is_total, COUNT\(\*\)::INTEGER AS resolved/.test(sql)) return { rows: [] };
        if (/FULL OUTER JOIN res_stats/.test(sql)) return { rows: [{ user_code: null, open_now: 2, overdue_now: 0, resolved: 0, avg_hours: null, with_due: 0, on_time: 0, name: null }] };
        throw new Error(`beklenmeyen sorgu: ${sql.slice(0, 80)}`);
    },
    };
  }

  it('bugün DB\'den (İstanbul) alınır, sonra 3 toplama sorgusu AYNI [site, from, to] parametreleriyle gider; sonuç birleştirilir', async () => {
    const db = fakeDb();
    const report = await buildWorkReport(1000000001, { from: '2026-10-01' }, db);
    assert.match(db.log[0].sql, /^SELECT \(NOW\(\) AT TIME ZONE 'Europe\/Istanbul'\)::date::text AS today$/);
    assert.equal(db.log.length, 4);
    for (const entry of db.log.slice(1)) assert.deepEqual(entry.params, [1000000001, '2026-10-01', TODAY]);
    assert.deepEqual([report.from, report.to, report.totals.opened, report.totals.open_now], ['2026-10-01', TODAY, 2, 2]);
    assert.deepEqual(report.by_assignee, [{ user_code: null, name: UNASSIGNED_LABEL, open_now: 2, overdue_now: 0, resolved: 0, avg_resolution_hours: null, on_time_rate: null }]);
  });

  it('geçersiz aralık toplama sorgusu gitmeden 400 INVALID_FIELD', async () => {
    const db = fakeDb();
    await assert.rejects(buildWorkReport(1000000001, { from: '2026-10-20', to: '2026-10-19' }, db), { statusCode: 400, code: 'INVALID_FIELD' });
    assert.equal(db.log.length, 1);
  });
});
