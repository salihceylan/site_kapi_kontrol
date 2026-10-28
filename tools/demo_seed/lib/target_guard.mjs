// Hedef korumasi: demo araclari (seed / cleanup / restructure_families / add_vehicles) SAHTE veri yazar ve siler. Elle calistirilan bir arac
// yanlislikla canli (ya da baska) bir veritabanina yazmasin diye her arac baslarken hedefi dogrular (karsilastirma programi P1-19;
// Astra `tools/yerel_hesap` hedef dogrulamasi gibi: yalniz geri donus sunucusu + izinli veritabani adi). Saf: ag / veritabani yok.
//
// Kural:
//  * YEREL KIP (varsayilan): sunucu geri donus adresi (127.0.0.1, localhost, ::1) VE veritabani adi izin listesinde olmali:
//    `site_kapi_yerel`, `site_kapi_yerel_test` ya da yerel test / prova adlari (`demo_seed_*`, `demo_restr_*`, `demo_veh_*`).
//  * ACIK IZIN: baska her hedef (canli, uzak, baska ad) YALNIZ `--allow-target <veritabani adi>` ile, adi AYNEN yazilarak acilir.
//    `run_remote*.sh` betikleri bunu canli ve prova veritabani icin kendisi verir; elle calistiran adi bilerek yazmak zorundadir.
//
// Guvenlik notu: hedef, araclarin baglanirken kullandigi ayristirma ile ([parseDatabaseUrl]) okunur; sorgu parametreleri (`?host=`) baglantiyi
// degistirmez. Parola hicbir cikti satirina yazilmaz.

import { describeTarget, parseDatabaseUrl } from './env.mjs';

/** Geri donus (loopback) sunucu adlari. IPv6 koseli parantezi atilir, buyuk / kucuk harf onemsizdir. */
export const LOOPBACK_HOSTS = Object.freeze(['127.0.0.1', 'localhost', '::1']);

/** Yerel kipte izinli kesin veritabani adlari. */
export const LOCAL_DATABASE_NAMES = Object.freeze(['site_kapi_yerel', 'site_kapi_yerel_test']);

/** Yerel test ve sunucu prova veritabanlari: demo_seed_test, demo_restr_test, demo_veh_test, demo_seed_rehearsal_<damga> ... */
export const LOCAL_DATABASE_PATTERN = /^demo_(?:seed|restr|veh)_[a-z0-9_]+$/;

export function isLoopbackHost(host) {
  const normalized = String(host ?? '')
    .trim()
    .toLowerCase()
    .replace(/^\[|\]$/g, '');
  return LOOPBACK_HOSTS.includes(normalized);
}

export function isLocalDatabaseName(name) {
  const text = String(name ?? '');
  return LOCAL_DATABASE_NAMES.includes(text) || LOCAL_DATABASE_PATTERN.test(text);
}

/**
 * @param {string} url DATABASE_URL
 * @param {Record<string, unknown>} [args] komut satiri bayraklari (`parseArgs` ciktisi); yalniz `allow-target` okunur
 * @returns {{ ok: boolean, mode?: 'local' | 'explicit', target: string, reason?: string }}
 */
export function checkDemoTarget(url, args = {}) {
  let parsed;
  try {
    parsed = parseDatabaseUrl(String(url));
  } catch {
    return { ok: false, target: '(ayristirilamadi)', reason: 'DATABASE_URL ayristirilamadi; postgres://kullanici:parola@host:port/veritabani biciminde verin.' };
  }
  const target = describeTarget(String(url));
  const database = parsed.database;
  const loopback = isLoopbackHost(parsed.host);
  const localName = isLocalDatabaseName(database);
  if (loopback && localName) return { ok: true, mode: 'local', target };

  const allow = args['allow-target'];
  if (allow !== undefined && allow !== false) {
    if (typeof allow !== 'string' || allow === '') {
      return { ok: false, target, reason: '--allow-target veritabani adini ister: --allow-target <veritabani adi>.' };
    }
    if (database !== '' && allow === database) return { ok: true, mode: 'explicit', target };
    return { ok: false, target, reason: `--allow-target "${allow}" hedef veritabani adiyla ("${database}") ayni degil; adi AYNEN yazin.` };
  }

  const reason = !loopback && !localName
    ? 'Sunucu geri donus adresi degil ve veritabani adi yerel izin listesinde yok.'
    : !loopback
      ? `Sunucu geri donus adresi degil (${LOOPBACK_HOSTS.join(', ')}).`
      : 'Veritabani adi yerel izin listesinde yok.';
  return { ok: false, target, reason };
}

/** Reddedilen hedef icin kullaniciya gosterilen metin (parola yok). */
export function targetRefusalMessage(check) {
  return [
    `DURDURULDU: hedef veritabani izinli degil: ${check.target}. ${check.reason}`,
    `Yerel kullanimda hedef YALNIZ geri donus sunucusu ve izinli bir veritabani adi olabilir: ${LOCAL_DATABASE_NAMES.join(', ')}, demo_seed_* / demo_restr_* / demo_veh_*.`,
    'Canli ya da uzak bir veritabanina BILEREK yazacaksaniz veritabani adini AYNEN onaylayin: --allow-target <veritabani adi> (run_remote*.sh bunu kendisi verir).',
  ].join('\n');
}

/** Hedef izinli degilse hata firlatir (kod `DEMO_TARGET_REFUSED`); izinliyse [checkDemoTarget] sonucunu doner. */
export function assertDemoTarget(url, args = {}) {
  const check = checkDemoTarget(url, args);
  if (!check.ok) {
    const error = new Error(targetRefusalMessage(check));
    error.code = 'DEMO_TARGET_REFUSED';
    throw error;
  }
  return check;
}

/** Araclarin giris noktasi: izinli degilse mesaji yazar ve cikis kodu 2 ile durur; acik izinde tek uyari satiri yazar. */
export function requireDemoTarget(url, args = {}, { out = console, exit = (code) => process.exit(code) } = {}) {
  try {
    const check = assertDemoTarget(url, args);
    if (check.mode === 'explicit') out.warn(`UYARI: hedef yerel izin listesinde degil; --allow-target ile acik izin verildi: ${check.target}`);
    return check;
  } catch (error) {
    if (error?.code !== 'DEMO_TARGET_REFUSED') throw error;
    out.error(error.message);
    return exit(2);
  }
}
