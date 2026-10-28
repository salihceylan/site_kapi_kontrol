// Sayac saha okuma (070) DB'siz testleri: sema <-> migration, ad kurali, fotograf dogrulama, db.js baglantisi.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR } from '../scripts/migrate.js';
import { METERING_FIELD_DDL, METERING_FIELD_DDL_ORDER, ensureMeteringFieldSchema } from '../src/modules/metering_field_schema.js';
import { fileBaseName, folderNameFor } from '../src/modules/drive_common.js';
import { PHOTO_MAX_BYTES, blockLetter, decodePhoto, unitNumber } from '../src/modules/metering_field_routes.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '070_meter_reading_photos.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const normalize = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(40, 1)]);

describe('metering_field (070)', () => {
  it('migration, DDL ile ayni ifadeler ve ayni sirada; ekleyici', () => {
    const actual = normalize(MIGRATION);
    let cursor = 0;
    for (const name of METERING_FIELD_DDL_ORDER) {
      const at = actual.indexOf(normalize(METERING_FIELD_DDL[name]), cursor);
      assert.ok(at >= cursor, `sirasiz ya da eksik: ${name}`);
      cursor = at + normalize(METERING_FIELD_DDL[name]).length;
    }
    assert.ok(!/\b(DROP|TRUNCATE)\b/i.test(actual));
  });

  it('db.js ensureMeteringFieldSchema cagirir; tablo varsa ifade yok, yoksa 4 ifade', async () => {
    assert.ok(DB_SOURCE.includes('await ensureMeteringFieldSchema(client)'));
    const sent = [];
    const mk = (present) => ({
      query: async (text) => {
        sent.push(String(text));
        return { rows: [{ present, parent: true }] };
      },
    });
    await ensureMeteringFieldSchema(mk(true));
    assert.equal(sent.length, 1);
    sent.length = 0;
    await ensureMeteringFieldSchema(mk(false));
    assert.equal(sent.length, 5);
  });

  it('dosya adi AB_D13_201026 ve klasor suEkim_26', () => {
    const date = { year: 2026, month: 10, day: 20 };
    assert.equal(fileBaseName({ kind: 'su', block: blockLetter('A Blok'), apartment: unitNumber('Daire 13'), date }), 'AB_D13_201026');
    assert.equal(blockLetter('Blok B'), 'B');
    assert.equal(folderNameFor('isi', date), 'isiEkim_26');
    assert.equal(folderNameFor('elektrik', date), 'elektrikEkim_26');
  });

  it('P1-11: okuma fotografinin adi OKM-<okuma no> onekini tasir (Drive ve sunucu yedegi ayni kural); Drive kaydi okumaya baglanir', () => {
    const date = { year: 2026, month: 10, day: 20 };
    const source = { type: 'meter_reading', id: 77 };
    assert.equal(fileBaseName({ kind: 'su', block: blockLetter('A Blok'), apartment: unitNumber('Daire 13'), date, source }), 'OKM-77_AB_D13_201026');
    const routes = readFileSync(path.join(here, '..', 'src', 'modules', 'metering_field_routes.js'), 'utf8');
    assert.match(routes, /const source = \{ type: 'meter_reading', id: readingId \}/);
    assert.match(routes, /data: photo\.data,\s*source,/, 'driveService.upload kaynak baglantisini alir');
    assert.match(routes, /fileBaseName\(\{ kind: driveKind, block, apartment, date: parsed, source \}\)/, 'sunucu tablosundaki ad da onekli');
  });

  it('fotograf dogrulama: tur, boyut, icerik', () => {
    assert.ok(decodePhoto(JPEG.toString('base64'), 'image/jpeg'));
    assert.equal(decodePhoto(JPEG.toString('base64'), 'image/png'), null);
    assert.equal(decodePhoto(JPEG.toString('base64'), 'text/html'), null);
    assert.equal(decodePhoto('', 'image/jpeg'), null);
    assert.equal(decodePhoto(Buffer.alloc(PHOTO_MAX_BYTES + 1, 7).toString('base64'), 'image/jpeg'), null);
  });
});
