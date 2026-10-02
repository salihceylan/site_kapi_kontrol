import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Migration zincirinin BOŞ bir veritabanında tek başına çalışabilmesi için statik koruma:
// bir migration, kendisinden ÖNCE (veya kendi içinde, üstte) oluşturulmamış bir tabloyu ALTER edemez.
// (Eski hata: 008, yalnızca src/db.js'te oluşturulan device_runtime_status'u ALTER ediyordu; boş DB'de
// docker-compose initdb.d ve scripts/migrate.js bu satırda düşüyordu.)
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations');
const files = readdirSync(dir).filter((f) => /^\d{3}_.+\.sql$/.test(f)).sort();

function stripComments(sql) {
  return sql.replace(/\/\*[\s\S]*?\*\//g, '').replace(/--.*$/gm, '');
}

describe('migration zinciri boş veritabanında kendi kendine yeterli', () => {
  it('migration dosyaları numara sırasıyla bulunur ve numaralar tekrarlanmaz', () => {
    assert.ok(files.length >= 27, `beklenenden az migration: ${files.length}`);
    const numbers = files.map((f) => f.slice(0, 3));
    assert.equal(new Set(numbers).size, numbers.length, 'aynı numaralı birden çok migration var');
  });

  it('her ALTER TABLE, aynı veya önceki bir migration\'da oluşturulmuş tabloyu hedefler', () => {
    const created = new Set();
    const problems = [];
    for (const file of files) {
      const sql = stripComments(readFileSync(path.join(dir, file), 'utf8'));
      // Dosya içinde sıra önemli: ifadeleri sırayla işle.
      const re = /(create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?(\w+)"?)|(alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?"?(\w+)"?)/gi;
      let m;
      while ((m = re.exec(sql)) !== null) {
        if (m[2]) {
          created.add(m[2].toLowerCase());
        } else if (m[4]) {
          const table = m[4].toLowerCase();
          const ifExists = /alter\s+table\s+if\s+exists/i.test(m[3]);
          if (!ifExists && !created.has(table)) {
            problems.push(`${file}: ALTER TABLE ${table} — tablo bu migration'dan önce hiçbir migration'da oluşturulmuyor`);
          }
        }
      }
    }
    assert.deepEqual(problems, [], `Boş DB'de düşecek migration'lar:\n${problems.join('\n')}`);
  });

  it('008, device_runtime_status tablosunu ALTER etmeden önce oluşturur', () => {
    const sql = stripComments(readFileSync(path.join(dir, '008_guest_passes_and_door_logs.sql'), 'utf8'));
    const create = sql.search(/create\s+table\s+if\s+not\s+exists\s+device_runtime_status/i);
    const alter = sql.search(/alter\s+table\s+device_runtime_status/i);
    assert.ok(create >= 0, '008 device_runtime_status tablosunu oluşturmuyor');
    assert.ok(create < alter, "008'de CREATE TABLE device_runtime_status, ilk ALTER'den önce gelmeli");
  });
});
