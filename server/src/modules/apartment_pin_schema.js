// Daire PIN'inin düz metin kopyasının kaldırılması: 051. migrations/051_apartment_pin_hash.sql ile AYNI ifadeler, AYNI sırayla (test: apartment_pin).
//
// Daire PIN'i (yönetimin açtığı "daire hesabı"nın 4 haneli giriş şifresi) zaten users.password_hash'te bcrypt özeti (BCRYPT_COST) olarak saklanır ve
// girişte YALNIZ o özetle doğrulanır. apartments.resident_pin_code yalnız yöneticiye göstermek / sonradan yeniden e-postalamak için tutulan OKUNABİLİR
// KOPYAYDI (KVKK m.12 teknik tedbir). 051: kopya silinir; yerine sırrın hiçbir türevini taşımayan bir işaret gelir:
//   resident_pin_issued = "dairenin göstergesindeki hesabın parolası yönetimin verdiği PIN'dir" (oluşturma / sıfırlamada TRUE; sakin kendi parolasını
//   belirleyince, gösterge başka kişiye geçince ve sakin sıfırlanınca FALSE). FALSE iken yönetici PIN'i SIFIRLAYAMAZ (yalnız süper kullanıcı).
// İkinci bir özet sütunu BİLEREK eklenmez: doğrulayan tek yer users.password_hash'tir. resident_pin_code sütunu eski sürüm / geri alma uyumluluğu için
// KALIR ama yeni kod onu yazmaz / API'ye vermez; her açılıştaki süpürme eski bir sürecin yazdığı kopyayı da siler.
//
// İşaretin değeri (inceleme 2. tur P3): eski düz kopya her zaman GÜNCEL parola değildi (051'den önce PATCH /me ile parolasını değiştiren sakinde kopya
// eskimiş kalıyordu). Bu yüzden işaret YALNIZ düz kopya bcrypt.compare ile users.password_hash'e EŞİTSE TRUE olur; aksi halde FALSE (temkinli: yönetici
// sıfırlayamaz, süper kullanıcı sıfırlayabilir).
//  - Aşama A (SQL, ucuz): doğrulanamayan kopyalar (göstergede hesap yok / silinmiş, özet bcrypt değil, PIN boş) -> FALSE + NULL. Migration bu adımı
//    TEK ifadeyle yapar (APARTMENT_PIN_DDL.clearUnverifiable); doğrulanabilir satırlara DOKUNMAZ (işaret varsayılan FALSE kalır = temkinli).
//  - Aşama B (JS, bcrypt ~0,1 sn/satır): doğrulanabilir kopyalar okunur (kilitsiz), karşılaştırılır, satır sürümü (xmin) ve özet değişmediyse
//    işaret + NULL tek satırlık otomatik onaylı UPDATE ile yazılır (iyimser eşzamanlılık; uzun kilit yok). Migration'da YAPILAMAZ (SQL'de bcrypt yok):
//    migrate.js yolu doğrulanabilir satırları düz kopyasıyla bırakır, sunucu açılışı (ensureDbSchema; her dağıtımda çalışır) tamamlar.
//
// Sıcak tablo dersi (apartments sıcak bir üst tablodur):
//  - ALTER yalnız katalog sütunun eksik olduğunu söylüyorsa, kendi otomatik onaylı ifadesiyle, lock_timeout 2 sn + 40P01/55P03'te artan beklemeli yeniden
//    denemeyle çalışır. NOT NULL DEFAULT FALSE (sabit varsayılan): PG 11+ yalnız katalog değişikliğidir, tablo yeniden yazılmaz.
//  - Aşama A partileri kilitli satırı ATLAR (FOR NO KEY UPDATE SKIP LOCKED): satır kilidi beklenmez -> 40P01 döngüsüne girilemez; anahtar sütunlara
//    dokunulmaz -> FK KEY SHARE ile çakışmaz. Aşama B'nin tek satırlık UPDATE'i başka kilit tutmadan çalışır; 55P03'te satır sonraki geçişe kalır.
//  - Açılışı bekletmez: açılış en çok `syncBudgetMs` (3 sn) çalışır; kalan satırlar sunucu açıldıktan sonra arka planda dilimler hâlinde tamamlanır
//    (satır başına kısa ara; idempotent; süreç kesilirse sonraki açılış kaldığı yerden sürer).
//  - Normal açılışta tek bir katalog sorgusu + tek bir EXISTS çalışır; düz PIN yoksa hiçbir yazma / kilit yoktur.
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın; arka plan işi bağlantıyı çağıranın verdiği `connect` ile alır).

import bcrypt from 'bcryptjs';

/** bcrypt özeti biçimi (SQL düzenli ifadesi). Biçimsiz özet (ör. silinmiş hesabın '!<hex>' özeti) doğrulanamaz sayılır. */
const BCRYPT_SQL_PATTERN = String.raw`'^\$2[abxy]\$[0-9]{2}\$'`;

/** Düz kopya users.password_hash'e karşı DOĞRULANABİLİR mi (gösterge hesabı var, silinmemiş, özet bcrypt, PIN boş değil). `a` = apartments. */
const VERIFIABLE_SQL = `EXISTS (SELECT 1 FROM users u WHERE u.user_code = a.resident_user_code AND u.deleted_at IS NULL AND u.password_hash ~ ${BCRYPT_SQL_PATTERN} AND btrim(a.resident_pin_code) <> '')`;

/** Sıra BAĞLAYICIDIR (migration ile aynı): önce sütun, sonra doğrulanamayan kopyaların temkinli temizliği. */
export const APARTMENT_PIN_DDL = Object.freeze({
  issuedColumn: `ALTER TABLE apartments ADD COLUMN IF NOT EXISTS resident_pin_issued BOOLEAN NOT NULL DEFAULT FALSE`,
  // Tek ifade (migrate.js tek transaction'ı; ALTER'in kilidi zaten tutulduğu için yarış yok). İkinci çalıştırma hiçbir satıra dokunmaz.
  clearUnverifiable: `UPDATE apartments a SET resident_pin_issued = FALSE, resident_pin_code = NULL WHERE a.resident_pin_code IS NOT NULL AND NOT ${VERIFIABLE_SQL}`,
});

export const APARTMENT_PIN_DDL_ORDER = Object.freeze(['issuedColumn', 'clearUnverifiable']);

/** Aşama A (açılış): aynı temizlik, partili, anahtar kümesi sırasıyla (id > $2), kilitli satırı atlayarak. $1 = parti boyu. Yalnız id döner. */
export const APARTMENT_PIN_CLEAR_BATCH_SQL = `
  WITH batch AS (
    SELECT a.id FROM apartments a
    WHERE a.resident_pin_code IS NOT NULL AND a.id > $2 AND NOT ${VERIFIABLE_SQL}
    ORDER BY a.id
    LIMIT $1
    FOR NO KEY UPDATE SKIP LOCKED
  )
  UPDATE apartments a
  SET resident_pin_issued = FALSE, resident_pin_code = NULL
  FROM batch
  WHERE a.id = batch.id
  RETURNING a.id
`;

/** Aşama B adayları (KİLİTSİZ okuma): satır sürümü (xmin), düz kopya ve özet. Düz kopya yalnız bellekte karşılaştırılır, hiçbir yere yazılmaz. */
export const APARTMENT_PIN_VERIFY_CANDIDATES_SQL = `
  SELECT a.id, a.xmin::TEXT AS version, a.resident_pin_code AS pin, u.password_hash AS hash
  FROM apartments a
  INNER JOIN users u ON u.user_code = a.resident_user_code
  WHERE a.resident_pin_code IS NOT NULL AND a.id > $2 AND ${VERIFIABLE_SQL}
  ORDER BY a.id
  LIMIT $1
`;

/** Aşama B yazımı: yalnız satır ve özet okunduğu gibiyse (iyimser kilit). $2 = karşılaştırma sonucu. PIN parametre olarak GÖNDERİLMEZ. */
export const APARTMENT_PIN_VERIFY_APPLY_SQL = `
  UPDATE apartments a
  SET resident_pin_issued = $2, resident_pin_code = NULL
  WHERE a.id = $1 AND a.xmin::TEXT = $3
    AND EXISTS (SELECT 1 FROM users u WHERE u.user_code = a.resident_user_code AND u.password_hash = $4)
`;

const PLAIN_PIN_EXISTS_SQL = `SELECT EXISTS (SELECT 1 FROM apartments WHERE resident_pin_code IS NOT NULL) AS pending`;

const RETRYABLE = new Set(['40P01', '55P03']);

/**
 * Test ayarı: yeniden deneme beklemesi (ms) çarpanı, Aşama A parti boyu, Aşama B okuma boyu, en çok geçiş, geçişler arası bekleme, açılışın en çok
 * süresi (syncBudgetMs), arka plan dilimi süresi / dilimler arası bekleme / satırlar arası kısa ara (CPU payı).
 */
export const apartmentPinTuning = {
  retryDelayMs: 300,
  batchSize: 500,
  verifyBatchSize: 25,
  maxPasses: 5,
  passDelayMs: 200,
  syncBudgetMs: 3000,
  backgroundSliceMs: 10_000,
  backgroundDelayMs: 1000,
  backgroundRowPauseMs: 20,
};

const sleep = (ms) => new Promise((resolve) => {
  const timer = setTimeout(resolve, ms);
  timer.unref?.();
});

/** Tek ifade; 40P01 / 55P03'te (yalnız ilk dağıtım, yoğun yazma) en çok 6 deneme, artan bekleme. İfade tek başına otomatik onaylıdır. */
async function runWithRetry(client, sql, params) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await client.query(sql, params);
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await sleep(apartmentPinTuning.retryDelayMs * attempt);
    }
  }
}

/**
 * Düz PIN kopyalarını siler ve işareti DOĞRULAYARAK kurar. [deadline] (ms, Date.now ölçeği) aşılınca Aşama B durur ve `deferred: true` döner.
 * Dönüş: { cleared (doğrulanamayan -> FALSE), verified (bcrypt ile karşılaştırılıp yazılan), issued (verified içinde TRUE), converted, remaining, deferred }.
 * Satır sayıları dışında hiçbir şey yazdırılmaz; PIN değeri hiçbir sorguya parametre olarak gitmez.
 */
export async function runApartmentPinBackfill(client, { deadline = Infinity, rowPauseMs = 0 } = {}) {
  const result = { cleared: 0, verified: 0, issued: 0, converted: 0, remaining: false, deferred: false };
  const finish = async () => {
    result.converted = result.cleared + result.verified;
    if (!result.deferred) {
      result.remaining = (await client.query(PLAIN_PIN_EXISTS_SQL)).rows[0]?.pending === true;
    } else {
      result.remaining = true;
    }
    return result;
  };
  for (let pass = 1; pass <= apartmentPinTuning.maxPasses; pass += 1) {
    const pending = await client.query(PLAIN_PIN_EXISTS_SQL);
    if (pending.rows[0]?.pending !== true) {
      return finish();
    }
    if (pass > 1) {
      // Önceki geçişte kilitli / değişmiş olduğu için kalan satırlar: kısa bekleme, sonra baştan (id > 0) yeniden.
      await sleep(apartmentPinTuning.passDelayMs);
    }
    // Aşama A: doğrulanamayanlar (SQL partileri).
    let lastId = 0;
    for (;;) {
      if (Date.now() > deadline) {
        result.deferred = true;
        return finish();
      }
      const batch = await runWithRetry(client, APARTMENT_PIN_CLEAR_BATCH_SQL, [apartmentPinTuning.batchSize, lastId]);
      if (batch.rowCount === 0) break;
      result.cleared += batch.rowCount;
      lastId = batch.rows.reduce((max, row) => Math.max(max, Number(row.id)), lastId);
    }
    // Aşama B: doğrulanabilirler (bcrypt; satır satır, kilitsiz okuma + iyimser yazım).
    lastId = 0;
    for (;;) {
      const candidates = await client.query(APARTMENT_PIN_VERIFY_CANDIDATES_SQL, [apartmentPinTuning.verifyBatchSize, lastId]);
      if (candidates.rowCount === 0) break;
      for (const row of candidates.rows) {
        if (Date.now() > deadline) {
          result.deferred = true;
          return finish();
        }
        lastId = Math.max(lastId, Number(row.id));
        const matches = await bcrypt.compare(String(row.pin).trim(), String(row.hash));
        try {
          const applied = await client.query(APARTMENT_PIN_VERIFY_APPLY_SQL, [row.id, matches, row.version, row.hash]);
          if (applied.rowCount > 0) {
            result.verified += 1;
            if (matches) result.issued += 1;
          }
        } catch (error) {
          // Kilitli satır (55P03) ya da yarış (40P01): bu geçişte atlanır, sonraki geçişte / açılışta yeniden denenir.
          if (!RETRYABLE.has(error?.code)) throw error;
        }
        if (rowPauseMs > 0) await sleep(rowPauseMs);
      }
    }
  }
  return finish();
}

let background = null;

/** Süren arka plan tamamlamasının sözü (yoksa çözülmüş söz). Testler / QA bekler; hata fırlatmaz. */
export function apartmentPinBackgroundDone() {
  return background ?? Promise.resolve();
}

function logResult(prefix, result) {
  if (result.converted > 0 || result.remaining) {
    // eslint-disable-next-line no-console
    console.log(
      `[DB] 051 daire PIN'i${prefix}: ${result.converted} duz kopya silindi (${result.verified} bcrypt ile dogrulandi, ${result.issued} yonetim PIN'i)`
        + `${result.remaining ? (result.deferred ? '; kalanlar arka planda suruyor' : '; kilitli satir kaldi, sonraki acilista tamamlanacak') : ''}`,
    );
  }
}

/** Açılış süresi dolduğunda kalan satırları sunucu açıldıktan sonra dilimler hâlinde tamamlar (tek iş; ilerleme yoksa durur). */
function scheduleBackground(connect) {
  if (background || typeof connect !== 'function') return;
  background = (async () => {
    try {
      for (;;) {
        await sleep(apartmentPinTuning.backgroundDelayMs);
        const client = await connect();
        let result;
        try {
          await client.query("SET lock_timeout = '2s'");
          result = await runApartmentPinBackfill(client, {
            deadline: Date.now() + apartmentPinTuning.backgroundSliceMs,
            rowPauseMs: apartmentPinTuning.backgroundRowPauseMs,
          });
        } finally {
          await client.query('RESET lock_timeout').catch(() => {});
          client.release();
        }
        logResult(' (arka plan)', result);
        // Bitti ya da ilerleme yok (yalnız kilitli satırlar kaldı): sonraki açılışa bırakılır.
        if (!result.remaining || (!result.deferred && result.converted === 0)) break;
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[DB] 051 daire PIN arka plan aktarimi durdu (sonraki acilista surer):', error?.code || error?.message);
    } finally {
      background = null;
    }
  })();
}

/**
 * 051'i uygular (db.js'te ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). Sütun eksikse ALTER (fatal: diğer şema modülleriyle aynı); ardından en çok
 * `syncBudgetMs` süren aktarım; kalan varsa [connect] ile arka planda sürer. Aktarım hatası açılışı DURDURMAZ (yeni kod düz PIN'i okumaz / göstermez;
 * sonraki açılışta yeniden denenir) ama günlüğe yazılır (yalnız kod).
 */
export async function ensureApartmentPinSchema(client, { connect = null } = {}) {
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
      const result = await runApartmentPinBackfill(client, { deadline: Date.now() + apartmentPinTuning.syncBudgetMs });
      logResult('', result);
      if (result.remaining && result.deferred) {
        scheduleBackground(connect);
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[DB] 051 daire PIN aktarimi basarisiz (sonraki acilista tekrar denenecek):', error?.code || error?.message);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
