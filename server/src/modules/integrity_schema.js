// 077 butunluk sertlestirme semasi: tek kaynak. migrations/077_integrity_hardening.sql bu adimlarin birlesimidir (test: integrity_schema).
// Icerik: (1) users.must_change_password ve sites.approval_status (+ CHECK) numarali migration'larda YOKTU, yalniz db.js'teydi (bos veritabani
// zincirinde eksik kaliyordu; site adi indeksi sites.approval_status'a baglidir); (2) site_name_key() IMMUTABLE islevi ve site adi tekillik
// indeksleri (Turkce harf / bosluk farkiyla asilmaz); (3) user_oauth_identities (076) ve web_push_subscriptions (063) icin
// users(user_code) yabanci anahtari (ON DELETE CASCADE; yetim satirlar once silinir). Bu dosya db.js'i ICE AKTARMAZ.
//
// AÇILIŞ 40P01 DERSI: ifadeler dev ensureDbSchema blogunda DEGIL, blok bittikten sonra, katalog kontrolu + her adim kendi otomatik onayli
// ifadesiyle, lock_timeout 2 sn + 40P01/55P03'te artan beklemeli yeniden denemeyle calisir. Her sey varsa hicbir ifade gonderilmez.
// Hata politikasi: islev / sutun adimlari ONEMLIDIR (uygulama koduna bagli) ve hatada firlatir; FK ve indeks adimlari ekleyici korumadir,
// hatada acilisi DURDURMAZ ama gorunur bicimde loglanir (sonraki acilista katalog yeniden dener).
// Mukerrer site adi varsa indeks KURULMAZ: RAISE WARNING ile mukerrerler bildirilir (acilista loglanir) ve acilis cokmez; eski indeks korunur.
//
// 078 (daire m2 sutunlarinin KALICI dusurulmesi): apartments.gross_area_m2 / net_area_m2 sutunlari 077 surumunde geri alma uyumlulugu icin
// birakilmisti (eski kod acilista ADD IF NOT EXISTS ile bos geri ekliyordu). Canlidaki geri alma hedefi artik bu sutunlari hic okumuyor; bu yuzden
// dusurmek geri alma icin guvenlidir. db.js 031 blogu sutunlari ARTIK EKLEMEZ; asagidaki AREA_DROP_STEPS katalog kontrollu (sutun yoksa hicbir
// ifade gonderilmez, tabloda kilit alinmaz) tek `ALTER TABLE ... DROP COLUMN IF EXISTS` calistirir. 031 migration'i tarihsel olarak sutunlari ekler
// (degistirilmez); migrations/078 ayni adimlari uygular, zincir sonunda sutunlar YOKTUR. Hata acilisi durdurmaz (loglanir, sonraki acilista denenir).

const NEWLINE = String.fromCharCode(10);

const SITE_NAME_KEY_FN = `CREATE OR REPLACE FUNCTION site_name_key(t TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $fn$
  SELECT btrim(regexp_replace(btrim(lower(translate(replace(replace(COALESCE(t, ''), chr(160), ' '), chr(9), ' '), 'İIıŞşĞğÜüÖöÇç', 'iiissgguuoocc'))), '\\s+', ' ', 'g'))
$fn$;`;

/** Yabanci anahtar adimi: yetim satirlar silinir (kullanici silinmis), sonra FK eklenir. users once kilitlenir (kilit sirasi: ust tablo -> alt tablo). */
function fk(table, column, parent, parentColumn) {
  const name = `${table}_${column}_fkey`;
  return {
    kind: 'fk',
    name,
    table,
    fatal: false,
    sql: `DO $$
DECLARE
  orphan_count BIGINT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
  ) THEN
    LOCK TABLE ${parent} IN SHARE ROW EXCLUSIVE MODE;
    DELETE FROM ${table} c WHERE NOT EXISTS (SELECT 1 FROM ${parent} p WHERE p.${parentColumn} = c.${column});
    GET DIAGNOSTICS orphan_count = ROW_COUNT;
    IF orphan_count > 0 THEN
      RAISE WARNING '077: % yetim ${table} satiri silindi (${column} ${parent} icinde yok)', orphan_count;
    END IF;
    ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE CASCADE;
  END IF;
END $$;`,
  };
}

/**
 * Tekillik indeksi adimi. Once mukerrer kontrolu (varsa indeks kurulmaz, RAISE WARNING ile bildirilir), sonra eski indeksler yalniz
 * YENI indeks mevcutsa duser (koruma hic kesilmez). Esli zamanli mukerrer (unique_violation) de uyariya cevrilir; sonraki acilis yeniden dener.
 * Tablo yoksa indeks kurulmaz (NOTICE; ornegin QA'nin kesik sablon senaryosu): sunucunun sonraki acilisi indeksi kurar.
 */
function uniqueNameIndex({ index, table, expr, where, keyColumn, idColumn, oldIndex }) {
  const build = `FOR dup IN
      SELECT site_name_key(${keyColumn}) AS name_key, COUNT(*) AS n, array_agg(${idColumn} ORDER BY ${idColumn}) AS ids
      FROM ${table} WHERE ${where} GROUP BY 1 HAVING COUNT(*) > 1
    LOOP
      dup_count := dup_count + 1;
      RAISE WARNING '077: ${index} KURULMADI, mukerrer ${table} adi "%" (% kayit): ${idColumn} %', dup.name_key, dup.n, dup.ids;
    END LOOP;
    IF dup_count = 0 THEN
      BEGIN
        CREATE UNIQUE INDEX IF NOT EXISTS ${index} ON ${table} (${expr}) WHERE ${where};
      EXCEPTION WHEN unique_violation THEN
        RAISE WARNING '077: ${index} kurulamadi (es zamanli mukerrer ad); sonraki acilista yeniden denenecek';
      END;
    END IF;`;
  const indented = build.split(NEWLINE).join(`${NEWLINE}  `);
  return {
    kind: 'index',
    name: index,
    table,
    drops: [oldIndex],
    fatal: false,
    sql: `DO $$
DECLARE
  dup RECORD;
  dup_count INTEGER := 0;
BEGIN
  IF to_regclass('public.${index}') IS NULL THEN
    IF to_regclass('public.${table}') IS NOT NULL THEN
      ${indented}
    ELSE
      RAISE NOTICE '077: ${table} henuz yok; ${index} sunucunun sonraki acilisinda kurulur';
    END IF;
  END IF;
  IF to_regclass('public.${index}') IS NOT NULL THEN
    DROP INDEX IF EXISTS ${oldIndex};
  END IF;
END $$;`,
  };
}

export const INTEGRITY_STEPS = Object.freeze([
  {
    kind: 'column',
    name: 'users.must_change_password',
    table: 'users',
    fatal: true,
    sql: `ALTER TABLE users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE;`,
  },
  {
    kind: 'column',
    name: 'sites.approval_status',
    table: 'sites',
    fatal: true,
    sql: `ALTER TABLE sites ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'approved';`,
  },
  {
    kind: 'check',
    name: 'sites_approval_status_check',
    table: 'sites',
    fatal: true,
    sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sites_approval_status_check'
  ) THEN
    ALTER TABLE sites ADD CONSTRAINT sites_approval_status_check CHECK (approval_status IN ('pending', 'approved', 'rejected'));
  END IF;
END $$;`,
  },
  { kind: 'function', name: 'site_name_key', table: null, fatal: true, sql: SITE_NAME_KEY_FN },
  fk('user_oauth_identities', 'user_code', 'users', 'user_code'),
  fk('web_push_subscriptions', 'user_code', 'users', 'user_code'),
  uniqueNameIndex({
    index: 'uq_sites_name_key',
    table: 'sites',
    expr: 'site_name_key(name)',
    where: `approval_status IS DISTINCT FROM 'rejected'`,
    keyColumn: 'name',
    idColumn: 'site_code',
    oldIndex: 'idx_sites_unique_name',
  }),
  uniqueNameIndex({
    index: 'uq_site_applications_pending_name_key',
    table: 'site_applications',
    expr: 'site_name_key(site_name)',
    where: `status = 'pending'`,
    keyColumn: 'site_name',
    idColumn: 'id',
    oldIndex: 'idx_site_applications_pending_unique_name',
  }),
]);

/** Migration dosyasinin govdesi (adimlarin birlesimi). */
export const integrityMigrationBody = () => `${INTEGRITY_STEPS.map((s) => s.sql).join('\n\n')}\n`;

/** 078: dusurulecek daire m2 sutunlari ("tablo.sutun"). Sutun VARSA adim bekliyor demektir (diger adimlarin tersi). */
export const AREA_DROP_COLUMNS = Object.freeze(['apartments.gross_area_m2', 'apartments.net_area_m2']);

/**
 * 078: daire m2 sutunlarini kalici dusurur. DO blogu katalog kontrollu: sutunlar yoksa ALTER gonderilmez (DROP COLUMN IF EXISTS sutun olmasa da
 * ACCESS EXCLUSIVE kilit alirdi); iki sutun TEK ifadede dusurulur (tek kilit, atomik). lock_timeout hic ayarli degilse (psql / elle calistirma)
 * islem-yerel 5 sn konur; migrate.js (MIGRATE_LOCK_TIMEOUT_MS) ve ensure yolu (2 sn) kendi ayarini tasir ve KISALTILMAZ / UZATILMAZ.
 */
export const AREA_DROP_STEPS = Object.freeze([
  {
    kind: 'drop_column',
    tag: '078',
    name: 'apartments.area_columns',
    table: 'apartments',
    columns: AREA_DROP_COLUMNS,
    fatal: false,
    sql: `DO $$
BEGIN
  IF current_setting('lock_timeout') = '0' THEN
    PERFORM set_config('lock_timeout', '5s', true);
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = to_regclass('public.apartments') AND attnum > 0 AND NOT attisdropped
      AND attname IN ('gross_area_m2', 'net_area_m2')
  ) THEN
    ALTER TABLE apartments DROP COLUMN IF EXISTS gross_area_m2, DROP COLUMN IF EXISTS net_area_m2;
  END IF;
END $$;`,
  },
]);

/** 078 migration dosyasinin govdesi (adimlarin birlesimi). */
export const areaDropMigrationBody = () => `${AREA_DROP_STEPS.map((s) => s.sql).join('\n\n')}\n`;

export const schemaTuning = { retryDelayMs: 300 };

const CATALOG_SQL = `SELECT
    ARRAY(SELECT (table_name || '.' || column_name)::TEXT FROM information_schema.columns
          WHERE table_schema = 'public' AND (table_name || '.' || column_name) = ANY($1::TEXT[])) AS columns,
    ARRAY(SELECT proname::TEXT FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY($2::TEXT[])) AS functions,
    ARRAY(SELECT conname::TEXT FROM pg_constraint
          WHERE contype IN ('f', 'c') AND connamespace = 'public'::regnamespace AND conname = ANY($3::TEXT[])) AS fks,
    ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($4::TEXT[])) AS indexes,
    ARRAY(SELECT (table_name || '.' || column_name)::TEXT FROM information_schema.columns
          WHERE table_schema = 'public' AND (table_name || '.' || column_name) = ANY($5::TEXT[])) AS drop_columns`;

const namesOf = (kind) => INTEGRITY_STEPS.filter((s) => s.kind === kind).map((s) => s.name);
const oldIndexNames = () => INTEGRITY_STEPS.flatMap((s) => s.drops ?? []);

async function readPresent(client) {
  const found = await client.query(CATALOG_SQL, [
    namesOf('column'),
    namesOf('function'),
    [...namesOf('fk'), ...namesOf('check')],
    [...namesOf('index'), ...oldIndexNames()],
    [...AREA_DROP_COLUMNS],
  ]);
  const row = found.rows?.[0] ?? {};
  return new Set([
    ...(row.columns ?? []),
    ...(row.functions ?? []),
    ...(row.fks ?? []),
    ...(row.indexes ?? []),
    ...(row.drop_columns ?? []),
  ]);
}

/** Adim tamam mi: nesne var ve (indekste) dusurulmesi gereken eski indeks kalmadi. */
const isDone = (step, present) => present.has(step.name) && !(step.drops ?? []).some((old) => present.has(old));

/** 078 dusurme adimi bekliyor mu: dusurulecek sutunlardan en az biri hala VAR. */
const isDropPending = (step, present) => step.columns.some((column) => present.has(column));

const logLine = (text) => {
  // eslint-disable-next-line no-console
  console.error(`[DB] ${text}`);
};

/**
 * Eksik nesneler varsa sirayla uygular; hepsi varsa tek katalog sorgusundan sonra hicbir ifade gondermez.
 * Mukerrer site adi gibi RAISE WARNING bildirimleri ve kurulamayan FK / indeksler acilista loglanir (acilisi durdurmaz).
 */
export async function ensureIntegritySchema(client) {
  const present = await readPresent(client);
  const pending = [
    ...INTEGRITY_STEPS.filter((s) => !isDone(s, present)),
    ...AREA_DROP_STEPS.filter((s) => isDropPending(s, present)),
  ];
  if (pending.length === 0) {
    return;
  }
  const onNotice = (notice) => {
    if (notice?.severity === 'WARNING' && notice.message) logLine(`UYARI ${notice.message}`);
  };
  if (typeof client.on === 'function') client.on('notice', onNotice);
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const step of pending) {
      try {
        for (let attempt = 1; ; attempt += 1) {
          try {
            await client.query(step.sql);
            break;
          } catch (error) {
            if ((error?.code !== '40P01' && error?.code !== '55P03') || attempt >= 6) throw error;
            await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
          }
        }
      } catch (error) {
        if (step.fatal) throw error;
        const verb = step.kind === 'drop_column' ? 'dusurulemedi' : 'kurulamadi';
        logLine(`UYARI ${step.tag ?? '077'} ${step.kind} ${step.name} ${verb} (sonraki acilista yeniden denenecek): ${error?.code || error?.message}`);
      }
    }
    // Kurulamayan koruma acilista GORUNUR olsun (ornegin mukerrer site adi): katalog yeniden okunur.
    const after = await readPresent(client);
    for (const step of pending) {
      if (step.kind === 'index' && !after.has(step.name)) {
        logLine(`UYARI ${step.name} yok: ${step.table} icinde mukerrer ad olabilir (ya da tablo henuz yok). Adlari duzeltin; sunucu sonraki acilista yeniden dener (eski indeks korunur).`);
      }
    }
  } finally {
    if (typeof client.removeListener === 'function') client.removeListener('notice', onNotice);
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
