// Yerel test duzenegi: "Cenk Sitesi" benzeri bir fixture (2 blok, 10 daire, yonetici, acik moduller) + dokunulmamasi gereken ikinci site.
// Yalniz TEST veritabaninda kullanilir.

import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const serverRequire = createRequire(path.join(process.env.DEMO_SEED_SERVER_DIR || path.join(here, '..', '..', '..', 'server'), 'package.json'));

export async function createFixture(url) {
  const pg = serverRequire('pg');
  const u = new URL(url);
  const client = new pg.Client({ host: u.hostname, port: Number(u.port), user: decodeURIComponent(u.username), password: decodeURIComponent(u.password), database: u.pathname.slice(1) });
  await client.connect();
  const q = (sql, params = []) => client.query(sql, params);
  const mgr = (
    await q(
      `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash, login_name)
       VALUES ('Cenk GUDE', 'cenk@fixture.test', 'site_manager', TRUE, TRUE, 'approved', 'x', 'cenk.gude') RETURNING user_code`,
    )
  ).rows[0].user_code;
  const other = (
    await q(
      `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash, login_name)
       VALUES ('Baska Yonetici', 'baska@fixture.test', 'site_manager', TRUE, TRUE, 'approved', 'x', 'baska.yonetici') RETURNING user_code`,
    )
  ).rows[0].user_code;
  async function makeSite(name, blocks, managerCode, siteCode) {
    await q(
      `INSERT INTO sites (site_code, name, approval_status, approved_at, block_count, apartment_count, block_apartment_counts, city, district)
       VALUES ($1, $2, 'approved', NOW(), $3, $4, $5, 'Ankara', 'Demo')`,
      [siteCode, name, blocks.length, blocks.reduce((s, b) => s + b.count, 0), blocks.map((b) => b.count)],
    );
    await q(`INSERT INTO site_manager_sites (site_code, manager_user_code, link_source) VALUES ($1, $2, 'owner')`, [siteCode, managerCode]);
    await q(`INSERT INTO site_memberships (site_code, user_code, role, is_active) VALUES ($1, $2, 'SITE_OWNER', TRUE)`, [siteCode, managerCode]);
    let order = 0;
    for (const b of blocks) {
      order += 1;
      const blockId = (await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, $2, $3) RETURNING id`, [siteCode, b.name, order])).rows[0].id;
      for (let n = 1; n <= b.count; n += 1) {
        await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4)`, [siteCode, blockId, `Daire ${n}`, n]);
      }
    }
  }
  await makeSite('Cenk Sitesi', [{ name: 'A Blok', count: 5 }, { name: 'B Blok', count: 5 }], mgr, 1000000001);
  await makeSite('Baska Sitesi', [{ name: 'Tek Blok', count: 3 }], other, 1000000002);
  const modules = [
    'finance', 'documents', 'reservation', 'work_tracking', 'metering', 'survey', 'visitor_log', 'contracts', 'decision_book', 'directory', 'budget', 'neighbor_board',
    'annual_report', 'equipment', 'plate_cameras',
  ];
  for (const m of modules) await q(`INSERT INTO site_modules (site_code, module_code, enabled) VALUES (1000000001, $1, TRUE)`, [m]);
  await client.end();
  return { siteCode: 1000000001, managerCode: mgr };
}

export async function tableCounts(url) {
  const pg = serverRequire('pg');
  const u = new URL(url);
  const client = new pg.Client({ host: u.hostname, port: Number(u.port), user: decodeURIComponent(u.username), password: decodeURIComponent(u.password), database: u.pathname.slice(1) });
  await client.connect();
  const tables = (await client.query(`SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'demo_seed_registry' ORDER BY 1`)).rows.map((r) => r.tablename);
  const counts = {};
  for (const t of tables) counts[t] = Number((await client.query(`SELECT COUNT(*) AS n FROM "${t}"`)).rows[0].n);
  await client.end();
  return counts;
}
