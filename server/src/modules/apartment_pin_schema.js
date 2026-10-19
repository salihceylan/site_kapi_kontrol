// Daire PIN'inin düz metin kopyasının kaldırılması: 051. migrations/051_apartment_pin_hash.sql ile AYNI ifadeler, AYNI sırayla (test: apartment_pin).
//
// Daire PIN'i (yönetimin açtığı "daire hesabı"nın 4 haneli giriş şifresi) zaten users.password_hash'te bcrypt özeti (BCRYPT_COST) olarak saklanır ve
// girişte YALNIZ o özetle doğrulanır. apartments.resident_pin_code yalnız yöneticiye göstermek / sonradan yeniden e-postalamak için tutulan OKUNABİLİR
// KOPYAYDI (KVKK m.12 teknik tedbir). 051: kopya silinir; yerine sırrın hiçbir türevini taşımayan bir işaret gelir:
//   resident_pin_issued = "dairenin göstergesindeki hesabın parolası yönetimin verdiği PIN'dir" (oluşturma / sıfırlamada TRUE; sakin kendi parolasını
//   belirleyince, gösterge başka kişiye geçince ve sakin sıfırlanınca FALSE).
// İkinci bir özet sütunu BİLEREK eklenmez: doğrulayan tek yer users.password_hash'tir; aynı 4 haneli sırrın (10.000 olasılık) ikinci bir özeti hiçbir
// işe yaramaz, yalnız saldırı yüzeyini büyütürdü. resident_pin_code sütunu eski sürüm / geri alma uyumluluğu için KALIR ama her zaman NULL'dır (kod
// artık yazmaz ve okumaz; her açılışta aşağıdaki süpürme, eski bir sürecin yazdığı kopyayı da siler).
//
// Sıcak tablo dersi (apartments sıcak bir üst tablodur):
//  - ALTER yalnız katalog sütunun eksik olduğunu söylüyorsa, kendi otomatik onaylı ifadesiyle, lock_timeout 2 sn + 40P01/55P03'te artan beklemeli yeniden
//    denemeyle çalışır. NOT NULL DEFAULT FALSE (sabit varsayılan): PG 11+ yalnız katalog değişikliğidir, tablo yeniden yazılmaz.
//  - Aktarım (düz PIN -> işaret + NULL) küçük partilerle yapılır; her parti kendi otomatik onaylı UPDATE'idir ve kilitli satırları ATLAR
//    (FOR NO KEY UPDATE SKIP LOCKED): satır kilidi hiç BEKLENMEDİĞİ için bu iş bir 40P01 döngüsüne giremez, yazıcıları da bekletmez (anahtar
//    sütunlara dokunmaz -> FK KEY SHARE kilitleriyle çakışmaz). Atlanan satırlar sonraki geçişte, kalırsa sonraki açılışta tamamlanır (idempotent).
//  - Normal açılışta tek bir katalog sorgusu + tek bir EXISTS çalışır; düz PIN yoksa hiçbir yazma / kilit yoktur.
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** Sıra BAĞLAYICIDIR (migration ile aynı): önce sütun, sonra aktarım. */
export const APARTMENT_PIN_DDL = Object.freeze({
  issuedColumn: `ALTER TABLE apartments ADD COLUMN IF NOT EXISTS resident_pin_issued BOOLEAN NOT NULL DEFAULT FALSE`,
  // Tek ifadelik aktarım (migration: migrate.js tek transaction'ı; ALTER'in kilidi zaten tutulduğu için kilitlenme yarışı yoktur). Boş / yalnız boşluk
  // olan eski değer "PIN verilmiş" sayılmaz ama yine silinir. İkinci çalıştırma hiçbir satıra dokunmaz (WHERE resident_pin_code IS NOT NULL).
  backfill: `UPDATE apartments SET resident_pin_issued = (resident_pin_issued OR btrim(resident_pin_code) <> ''), resident_pin_code = NULL WHERE resident_pin_code IS NOT NULL`,
});

export const APARTMENT_PIN_DDL_ORDER = Object.freeze(['issuedColumn', 'backfill']);

/**
 * Açılıştaki PARTİLİ aktarım: aynı SET ifadesi, anahtar kümesi sırasıyla (id > $2) ve kilitli satırı atlayarak. $1 = parti boyu, $2 = son id.
 * RETURNING yalnız id döner (PIN değeri hiçbir yere okunmaz / yazdırılmaz).
 */
export const APARTMENT_PIN_BACKFILL_BATCH_SQL = `
  WITH batch AS (
    SELECT id FROM apartments
    WHERE resident_pin_code IS NOT NULL AND id > $2
    ORDER BY id
    LIMIT $1
    FOR NO KEY UPDATE SKIP LOCKED
  )
  UPDATE apartments a
  SET resident_pin_issued = (a.resident_pin_issued OR btrim(a.resident_pin_code) <> ''), resident_pin_code = NULL
  FROM batch
  WHERE a.id = batch.id
  RETURNING a.id
`;

const PLAIN_PIN_EXISTS_SQL = `SELECT EXISTS (SELECT 1 FROM apartments WHERE resident_pin_code IS NOT NULL) AS pending`;

const RETRYABLE = new Set(['40P01', '55P03']);

/** Test ayarı: yeniden deneme beklemesi (ms) çarpanı, parti boyu ve kilitli satırlar için en çok geçiş sayısı. */
export const apartmentPinTuning = { retryDelayMs: 300, batchSize: 500, maxPasses: 5, passDelayMs: 200 };

/** Tek ifade; 40P01 / 55P03'te (yalnız ilk dağıtım, yoğun yazma) en çok 6 deneme, artan bekleme. İfade tek başına otomatik onaylıdır. */
async function runWithRetry(client, sql, params) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await client.query(sql, params);
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, apartmentPinTuning.retryDelayMs * attempt));
    }
  }
}

/**
 * Düz PIN kopyalarını partiler halinde siler (işareti korur / kurar). Dönüş: { converted, remaining } (remaining: kilitli olduğu için bu açılışta
 * atlanan satır kaldı mı). Satır sayısı dışında hiçbir şey yazdırılmaz.
 */
export async function runApartmentPinBackfill(client) {
  let converted = 0;
  for (let pass = 1; pass <= apartmentPinTuning.maxPasses; pass += 1) {
    const pending = await client.query(PLAIN_PIN_EXISTS_SQL);
    if (pending.rows[0]?.pending !== true) {
      return { converted, remaining: false };
    }
    if (pass > 1) {
      // Önceki geçişte kilitli olduğu için atlanan satırlar: kısa bekleme, sonra baştan (id > 0) yeniden.
      await new Promise((resolve) => setTimeout(resolve, apartmentPinTuning.passDelayMs));
    }
    let lastId = 0;
    for (;;) {
      const result = await runWithRetry(client, APARTMENT_PIN_BACKFILL_BATCH_SQL, [apartmentPinTuning.batchSize, lastId]);
      if (result.rowCount === 0) break;
      converted += result.rowCount;
      lastId = result.rows.reduce((max, row) => Math.max(max, Number(row.id)), lastId);
    }
  }
  const left = await client.query(PLAIN_PIN_EXISTS_SQL);
  return { converted, remaining: left.rows[0]?.pending === true };
}

/**
 * 051'i uygular (db.js'te ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). Sütun eksikse ALTER (fatal: diğer şema modülleriyle aynı); ardından
 * aktarım. Aktarım hatası açılışı DURDURMAZ (yeni kod düz PIN'i okumaz / göstermez; sonraki açılışta yeniden denenir) ama yüksek sesle günlüğe yazılır.
 */
export async function ensureApartmentPinSchema(client) {
  const found = await client.query(`
    SELECT
      to_regclass('public.apartments') IS NOT NULL AS has_table,
      EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = to_regclass('public.apartments') AND attname = 'resident_pin_issued' AND NOT attisdropped
      ) AS has_column,
      EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = to_regclass('public.apartments') AND attname = 'resident_pin_code' AND NOT attisdropped
      ) AS has_plain_column
  `);
  const state = found.rows[0] ?? {};
  if (state.has_table !== true) {
    return;
  }
  const plainPending = state.has_plain_column === true && (await client.query(PLAIN_PIN_EXISTS_SQL)).rows[0]?.pending === true;
  // Normal açılış (sütun var, düz PIN yok): yalnız iki okuma; kilit / yazma yok.
  if (state.has_column === true && !plainPending) {
    return;
  }
  // Kilit kuyruğunda sonsuza dek beklemesin: 2 sn sonra 55P03, yeniden denenir.
  await client.query("SET lock_timeout = '2s'");
  try {
    if (state.has_column !== true) {
      await runWithRetry(client, APARTMENT_PIN_DDL.issuedColumn);
    }
    if (!plainPending) {
      return;
    }
    try {
      const result = await runApartmentPinBackfill(client);
      if (result.converted > 0 || result.remaining) {
        // eslint-disable-next-line no-console
        console.log(`[DB] 051 daire PIN'i: ${result.converted} duz kopya silindi${result.remaining ? '; kilitli satir kaldi, sonraki acilista tamamlanacak' : ''}`);
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[DB] 051 daire PIN aktarimi basarisiz (sonraki acilista tekrar denenecek):', error?.code || error?.message);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
