#!/usr/bin/env node
// Demo tohumunu geri alir: demo_seed_registry'deki kayitli satirlari TERS SIRADA siler.
//
//   DATABASE_URL=postgres://... node cleanup.mjs --list
//   DATABASE_URL=postgres://... node cleanup.mjs --batch <batch_id> [--yes] [--keep-registry]
//
// Yalniz eklemeli (append-only) tablolarin (ledger_entries, receipts, audit_log, karar defteri vb.) tetikleyicileri DELETE'i
// engeller; bu yuzden silme ayni transaction'da `SET LOCAL session_replication_role = replica` ile yapilir (SUPERUSER gerekir).
// YALNIZ kayitli satirlar silinir. Replica modunda FK eylemleri (CASCADE/SET NULL) de calismaz: her satir acikca kayitli oldugu
// icin ters sirada silinir. Seed oncesi var olan satirlarda yapilan degisiklikler (op='update') before_image ile eski haline getirilir.
// Seed'in diske yazdigi dosyalar (table_name='@file') silinir.

import fs from 'node:fs';
import { applyDbEnv, describeTarget, loadServerRequire, newPgClient, parseArgs, resolveServerDir } from './lib/env.mjs';
import { REGISTRY_TABLE, primaryKeys } from './lib/registry.mjs';

const args = parseArgs(process.argv.slice(2));
const url = args['database-url'] || process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL (ya da --database-url) gerekli.');
  process.exit(2);
}
applyDbEnv(url);
const serverRequire = loadServerRequire(resolveServerDir(args));
const client = newPgClient(serverRequire, url);
await client.connect();

const q = (sql, params = []) => client.query(sql, params);

try {
  const has = await q(`SELECT to_regclass('public.${REGISTRY_TABLE}') AS t`);
  if (!has.rows[0].t) {
    console.log('Kayit tablosu yok: yapilacak bir sey yok.');
    process.exit(0);
  }
  if (args.list || !args.batch) {
    const rows = await q(`SELECT batch_id, COUNT(*)::INT AS n, MIN(created_at) AS first, MAX(created_at) AS last FROM ${REGISTRY_TABLE} GROUP BY 1 ORDER BY 3`);
    console.log(`Hedef: ${describeTarget(url)}`);
    if (rows.rowCount === 0) console.log('Kayitli demo batch yok.');
    for (const r of rows.rows) console.log(`  ${r.batch_id}  satir=${r.n}  ${new Date(r.first).toISOString()} .. ${new Date(r.last).toISOString()}`);
    if (!args.batch) process.exit(0);
  }

  const batch = String(args.batch);
  const su = await q(`SELECT rolsuper FROM pg_roles WHERE rolname = current_user`);
  if (!su.rows[0]?.rolsuper) {
    console.error('Bu kullanici SUPERUSER degil: append-only tablolarda DELETE icin session_replication_role=replica gerekir. SUPERUSER URL ile calistirin.');
    process.exit(3);
  }
  // Arac batch'i (add_vehicles.mjs) tohum / yeniden yapilandirma kisilerine baglanir: o batch'ler arac batch'inden ONCE geri alinirsa yetim arac kalir.
  const isVehicleBatch = batch.startsWith('demo-vehicles-');
  if (!isVehicleBatch && !args.force) {
    const vehicles = await q(`SELECT DISTINCT batch_id FROM ${REGISTRY_TABLE} WHERE batch_id LIKE 'demo-vehicles-%' ORDER BY 1`);
    if (vehicles.rowCount > 0) {
      console.error(`DURDURULDU: ${vehicles.rows.map((r) => r.batch_id).join(', ')} arac batch'i hala kayitli. Once onu geri alin (cleanup.mjs --batch <o batch> --yes), sonra bunu. Bilerek devam etmek icin --force.`);
      process.exit(5);
    }
  }
  // Yeniden yapilandirma batch'i (restructure_families.mjs) tohum kisilerine baglanir: tohum batch'i ondan ONCE geri alinirsa yetim kayit kalir.
  if (!batch.startsWith('demo-restructure-') && !isVehicleBatch && !args.force) {
    const later = await q(`SELECT DISTINCT batch_id FROM ${REGISTRY_TABLE} WHERE batch_id LIKE 'demo-restructure-%' ORDER BY 1`);
    if (later.rowCount > 0) {
      console.error(`DURDURULDU: ${later.rows.map((r) => r.batch_id).join(', ')} yeniden yapilandirma batch'i hala kayitli. Once onu geri alin (cleanup.mjs --batch <o batch> --yes), sonra tohum batch'ini. Bilerek devam etmek icin --force.`);
      process.exit(5);
    }
  }
  const total = await q(`SELECT COUNT(*)::INT AS n FROM ${REGISTRY_TABLE} WHERE batch_id = $1`, [batch]);
  console.log(`Hedef: ${describeTarget(url)}  batch=${batch}  kayitli satir=${total.rows[0].n}`);
  if (total.rows[0].n === 0) {
    console.log('Bu batch icin kayit yok.');
    process.exit(0);
  }
  if (!args.yes) {
    console.error('Onay icin --yes ekleyin (silme geri alinamaz; once yedek alin).');
    process.exit(2);
  }

  const pks = await primaryKeys(client);
  await q('BEGIN');
  await q(`SET LOCAL session_replication_role = replica`);
  await q(`SET LOCAL statement_timeout = '600s'`);
  const rows = (await q(`SELECT id, table_name, row_id, op, before_image FROM ${REGISTRY_TABLE} WHERE batch_id = $1 ORDER BY id DESC`, [batch])).rows;

  const deleted = new Map();
  const restored = new Map();
  let files = 0;
  // replica modunda FK/tetikleyici yoktur: sira sonucu etkilemez; yine de tablolar "en son eklenenden once" (ters sira) islenir.
  const groups = new Map();
  for (const r of rows) {
    const key = `${r.op}::${r.table_name}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(r);
  }
  const orderedGroups = [...groups.values()].flatMap((list) => {
    const parts = [];
    for (let k = 0; k < list.length; k += 2000) parts.push(list.slice(k, k + 2000));
    return parts;
  });
  for (const group of orderedGroups) {
    const head = group[0];
    if (head.op === 'file') {
      for (const r of group) {
        try {
          if (fs.existsSync(r.row_id)) {
            fs.unlinkSync(r.row_id);
            files += 1;
          }
        } catch (error) {
          console.warn(`Dosya silinemedi: ${r.row_id} (${error.message})`);
        }
      }
      continue;
    }
    const cols = pks.get(head.table_name);
    if (!cols) {
      console.warn(`Atlandi (birincil anahtar yok): ${head.table_name}`);
      continue;
    }
    const keyExpr = cols.map((c) => `"${c}"::text`).join(` || '|' || `);
    if (head.op === 'update') {
      for (const r of group) {
        const image = r.before_image;
        const setCols = Object.keys(image).filter((k) => !cols.includes(k));
        if (setCols.length === 0) continue;
        const setSql = setCols.map((c) => `"${c}" = rec."${c}"`).join(', ');
        const res = await q(
          `UPDATE "${head.table_name}" AS t SET ${setSql} FROM jsonb_populate_record(NULL::"${head.table_name}", $1::jsonb) AS rec WHERE ${cols.map((c) => `t."${c}"::text`).join(` || '|' || `)} = $2`,
          [JSON.stringify(image), r.row_id],
        );
        restored.set(head.table_name, (restored.get(head.table_name) ?? 0) + res.rowCount);
      }
      continue;
    }
    const res = await q(`DELETE FROM "${head.table_name}" WHERE ${keyExpr} = ANY($1::text[])`, [group.map((r) => r.row_id)]);
    deleted.set(head.table_name, (deleted.get(head.table_name) ?? 0) + res.rowCount);
  }
  if (!args['keep-registry']) {
    await q(`DELETE FROM ${REGISTRY_TABLE} WHERE batch_id = $1`, [batch]);
  }
  await q('COMMIT');
  const sumDeleted = [...deleted.values()].reduce((s, v) => s + v, 0);
  console.log(`Silinen satir: ${sumDeleted}  geri yuklenen: ${[...restored.values()].reduce((s, v) => s + v, 0)}  dosya: ${files}`);
  for (const [table, n] of [...deleted.entries()].sort((a, b) => b[1] - a[1])) console.log(`  ${table.padEnd(34)} ${n}`);
  for (const [table, n] of restored) console.log(`  (geri yuklendi) ${table} ${n}`);
} catch (error) {
  try {
    await q('ROLLBACK');
  } catch {
    // yoksay
  }
  console.error('Temizlik BASARISIZ (geri alindi):', error.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
