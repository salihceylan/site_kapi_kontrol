// Toplu yükleme (Faz 2b) sütun sözleşmesi: `GET imports/spec` çıktısının TEK kaynağı. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md ("Şablon ve sütun sözleşmesi"). İstemci başlık eşlemesini bu `label` ve `aliases` ile yapar
// (Türkçe katlama = people_common.foldText + noktalama/boşluk sadeleştirme: `foldHeader`). Doğruluk kaynağı sunucudur; istemci yalnız
// ham hücreyi (metin/sayı/null) iletir.

import { foldText } from './people_common.js';

export const SPEC_VERSION = 1;
export const BULK_KINDS = Object.freeze(['apartments', 'people', 'vehicles', 'opening_balances', 'all_in_one']);
/** Modül kapısı gereken türler (tür -> modül anahtarı). Yeni toplu tür için tek satır. */
export const KIND_MODULE = Object.freeze({ opening_balances: 'finance' });
export const MAX_ROWS_LIMIT = 5000;
export const MAX_BODY_BYTES = 5 * 1024 * 1024;
/** Tek hücre için sert üst sınır (kötüye kullanım koruması). 600'ü aşan hücre satır hatası TOO_LONG, bunu aşan gövde 400 INVALID_BODY. */
export const CELL_HARD_LIMIT = 5000;
export const CELL_MAX_LENGTH = 600;

/** BULK_IMPORT_DISABLED=1 -> tüm toplu uçlar 503 IMPORT_DISABLED. */
export function isImportDisabled(env = process.env) {
  const raw = String(env.BULK_IMPORT_DISABLED ?? '').trim().toLowerCase();
  return raw === '1' || raw === 'true' || raw === 'yes';
}

/** BULK_IMPORT_MAX_ROWS (varsayılan ve üst sınır 5000; en az 1). */
export function maxRows(env = process.env) {
  const parsed = Number(env.BULK_IMPORT_MAX_ROWS);
  if (!Number.isFinite(parsed) || parsed < 1) {
    return MAX_ROWS_LIMIT;
  }
  return Math.min(MAX_ROWS_LIMIT, Math.floor(parsed));
}

/** İstemcideki başlık katlamasıyla AYNI: Türkçe katlama + küçük harf + noktalama/boşluk sadeleştirme. */
export function foldHeader(text) {
  return foldText(text)
    .replace(/㎡/g, 'm2')
    .replace(/²/g, '2')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export const RELATION_WORDS = Object.freeze({
  owner: Object.freeze(['Malik', 'Mal sahibi', 'Ev sahibi']),
  tenant: Object.freeze(['Kiracı']),
  family_member: Object.freeze(['Aile', 'Aile üyesi', 'Eş', 'Çocuk']),
  resident: Object.freeze(['Sakin', 'Oturan']),
});

export const RESPONSIBLE_WORDS = Object.freeze({
  owner: Object.freeze(['Malik', 'Mal sahibi', 'Ev sahibi']),
  tenant: Object.freeze(['Kiracı']),
  both: Object.freeze(['İkisi', 'İkisi de', 'Her ikisi']),
});

const col = (key, label, required, type, max_length, aliases, hint) =>
  Object.freeze({ key, label, required, type, max_length, aliases: Object.freeze(aliases), hint });

const BLOCK_COLUMN = (required, hint) =>
  col('blok', 'Blok', required, 'text', 60, ['Blok Adı', 'Blok No', 'Bloğu'], hint);
const APARTMENT_NO_COLUMN = (required, hint) =>
  col(
    'daire_no',
    'Daire No',
    required,
    'text',
    30,
    ['Daire', 'Daire Numarası', 'Kapı No', 'Kapı Numarası', 'Bağımsız Bölüm No', 'No'],
    hint,
  );
const PLATE_COLUMN = (required, hint) =>
  col('plaka', 'Plaka', required, 'text', 120, ['Plakalar', 'Araç Plakası', 'Araç Plakaları', 'Araç'], hint);
const NOTE_COLUMN = (hint) => col('not', 'Not', false, 'text', 500, ['Notlar', 'Açıklama', 'Yönetici Notu'], hint);
const NAME_COLUMN = (required, hint) =>
  col('ad_soyad', 'Ad Soyad', required, 'text', 100, ['Ad', 'İsim', 'Adı Soyadı', 'Ad-Soyad', 'İsim Soyisim', 'Kişi', 'Sakin Adı'], hint);
const EMAIL_COLUMN = (hint) =>
  col('e_posta', 'E-posta', false, 'text', 254, ['Eposta', 'E Posta', 'E-posta Adresi', 'Email', 'E-mail', 'Mail'], hint);
const PASSWORD_COLUMN = (hint) =>
  col('sifre', 'Başlangıç Şifresi', false, 'text', 30, ['Şifre', 'Geçici Şifre', 'PIN', 'Parola', 'Sifre', 'Baslangic Sifresi'], hint);
const LOGIN_NAME_COLUMN = (hint) =>
  col('kullanici_adi', 'Kullanıcı Adı', false, 'text', 50, ['Kullanıcı Adı', 'Kullanici Adi', 'Giriş Adı', 'Giris Adi', 'Username', 'User Name', 'Kullanıcı', 'Kullanici', 'Hesap Adı'], hint);

const BASE_COLUMNS = Object.freeze({
  apartments: Object.freeze([
    BLOCK_COLUMN(true, 'Sitedeki blok adı: «A», «A Blok» ya da «Blok A» aynı sayılır.'),
    APARTMENT_NO_COLUMN(true, 'Daire numarası: «5», «05» ya da «Daire 5». Daire sayısı Site Yapısı’ndan belirlenir.'),
    col('kat', 'Kat', false, 'text', 20, ['Kat No', 'Bulunduğu Kat'], 'Tam sayı (−20 ile 500). «Zemin» 0, «Bodrum» −1 sayılır.'),
    col('tip', 'Tip', false, 'text', 40, ['Daire Tipi', 'Tür', 'Kategori'], 'Örneğin «3+1» ya da «Dükkan» (en çok 40 karakter).'),
    col('arsa_payi_pay', 'Arsa Payı (Pay)', false, 'number', null, ['Arsa Payı Pay', 'Pay'], 'Arsa payının payı (tam sayı). Örneğin 35/1000 için 35.'),
    col('arsa_payi_payda', 'Arsa Payı (Payda)', false, 'number', null, ['Arsa Payı Payda', 'Payda'], 'Arsa payının paydası (tam sayı). Örneğin 35/1000 için 1000.'),
    col('sorumlu', 'Borç Sorumlusu', false, 'enum', 20, ['Sorumlu', 'Borçlandırma', 'Kim Öder'], 'Malik, Kiracı ya da İkisi. Borç ve bildirimlerin kime gideceğini belirler.'),
  ]),
  people: Object.freeze([
    NAME_COLUMN(true, 'Kişinin adı ve soyadı (2–100 karakter).'),
    LOGIN_NAME_COLUMN('Kullanıcının sisteme giriş yapacağı kullanıcı adı (boşsa ad soyadından otomatik üretilir).'),
    col('telefon', 'Telefon', false, 'text', 30, ['Tel', 'Cep', 'Cep Telefonu', 'GSM', 'Telefon No'], '10 haneli cep telefonu: 0 (555) 123 45 67. Excel baştaki sıfırı atsa da kabul edilir.'),
    EMAIL_COLUMN('Kişinin e-posta adresi. Aynı kişiyi tekrar yüklemede tanımak için en güvenilir alandır.'),
    PASSWORD_COLUMN('Kişinin ilk giriş şifresi (boş bırakılırsa 1234 tanımlanır).'),
    BLOCK_COLUMN(false, 'Daire verilecekse Blok ve Daire No birlikte doldurulmalıdır.'),
    APARTMENT_NO_COLUMN(false, 'Daire verilecekse Blok ve Daire No birlikte doldurulmalıdır.'),
    col('iliski', 'İlişki', false, 'enum', 40, ['İlişki Türü', 'Sakin Türü'], 'Malik, Kiracı, Aile (eş/çocuk) ya da Sakin. Boşsa «Sakin» sayılır.'),
    col('giris_tarihi', 'Giriş Tarihi', false, 'date', 20, ['Giriş', 'Taşınma Tarihi', 'Oturum Başlangıcı'], 'GG.AA.YYYY (örn. 15.03.2021). Boşsa bugün.'),
    PLATE_COLUMN(false, 'Araç plakası. Birden çok plaka için virgül, noktalı virgül ya da / ile ayırın (en çok 5).'),
    NOTE_COLUMN('Yönetici notu (en çok 500 karakter).'),
  ]),
  vehicles: Object.freeze([
    PLATE_COLUMN(true, 'Araç plakası. Birden çok plaka için virgül, noktalı virgül ya da / ile ayırın (en çok 5).'),
    EMAIL_COLUMN('Aracın sahibi kişinin e-postası. Boşsa Blok ve Daire No ile bulunur.'),
    BLOCK_COLUMN(false, 'E-posta yoksa sahibi bulmak için Blok ve Daire No birlikte gerekir.'),
    APARTMENT_NO_COLUMN(false, 'E-posta yoksa sahibi bulmak için Blok ve Daire No birlikte gerekir.'),
    NAME_COLUMN(false, 'Dairede birden çok sakin varsa sahibini ayırmak için kullanılır.'),
    NOTE_COLUMN('Araç notu (en çok 500 karakter).'),
  ]),
});

const OPENING_COLUMNS = Object.freeze([
  BLOCK_COLUMN(true, 'Sitedeki blok adı: «A», «A Blok» ya da «Blok A» aynı sayılır.'),
  APARTMENT_NO_COLUMN(true, 'Daire numarası: «5», «05» ya da «Daire 5».'),
  col('hesap', 'Hesap', false, 'enum', 40, ['Ev Sahibi', 'Malik', 'Mal Sahibi', 'Kiracı', 'Borçlu', 'Hesap Türü'], 'Ev sahibi ya da Kiracı. Boşsa ev sahibi hesabına yazılır.'),
  col('tutar', 'Tutar', true, 'text', 40, ['Devir Tutarı', 'Devir Bakiyesi', 'Borç', 'Bakiye', 'Tutar TL'], 'Devreden borç, TL: 1.250,50 ya da 1250,5. Eksi (alacak) desteklenmez.'),
  col('vade', 'Vade', false, 'date', 20, ['Vade Tarihi', 'Son Ödeme Tarihi'], 'GG.AA.YYYY. Boşsa devir tarihi.'),
  col('aciklama', 'Açıklama', false, 'text', 200, ['Not', 'Notlar'], 'En çok 200 karakter (yalnız yönetici ekstresinde görünür).'),
]);

// Hepsi bir arada: daire + sakin sütunları (blok/daire_no tek sefer). Taşınma tarihi etiketi Giriş Tarihi'nin yerini alır.
const ALL_IN_ONE_COLUMNS = Object.freeze([
  ...BASE_COLUMNS.apartments,
  ...BASE_COLUMNS.people
    .filter((column) => column.key !== 'blok' && column.key !== 'daire_no')
    .map((column) =>
      column.key === 'giris_tarihi'
        ? col('giris_tarihi', 'Taşınma Tarihi', false, 'date', 20, ['Giriş Tarihi', 'Giriş', 'Oturum Başlangıcı'], 'GG.AA.YYYY. Sakin, Borcum’da borçlarını bu tarihin ayından itibaren görür.')
        : column,
    ),
]);

const COLUMNS = Object.freeze({
  ...BASE_COLUMNS,
  opening_balances: OPENING_COLUMNS,
  all_in_one: ALL_IN_ONE_COLUMNS,
});

export function columnsOf(kind) {
  return COLUMNS[kind] ?? null;
}

export function isBulkKind(kind) {
  return typeof kind === 'string' && BULK_KINDS.includes(kind);
}

/** Bir türün geçerli hücre anahtarları (Set; `__proto__`/`constructor` içermez). */
export function columnKeysOf(kind) {
  return new Set((COLUMNS[kind] ?? []).map((column) => column.key));
}

/**
 * Eski şablonlardan kalan, ARTIK KULLANILMAYAN sütun anahtarları (m² kaldırıldı). Gövde doğrulaması bunları reddetmez (eski dosya 400 ile düşmesin);
 * planlayıcı dolu olanı yok sayar ve "m² artık kullanılmıyor" uyarısı verir. Şablonda/spec'te ve dışa aktarmada YOKTUR.
 */
export const LEGACY_IGNORED_KEYS = Object.freeze({
  apartments: Object.freeze(['brut_m2', 'net_m2']),
  all_in_one: Object.freeze(['brut_m2', 'net_m2']),
});

/** Gövdede kabul edilen hücre anahtarları = spec sütunları + o türün eski/yok sayılan anahtarları. */
export function acceptedKeysOf(kind) {
  return new Set([...columnKeysOf(kind), ...(LEGACY_IGNORED_KEYS[kind] ?? [])]);
}

/** Başlık katlaması -> sütun anahtarı (label + aliases). Aynı katlamış başlık iki sütuna düşmez (test). */
export function headerIndexOf(kind) {
  const index = new Map();
  for (const column of COLUMNS[kind] ?? []) {
    for (const text of [column.label, ...column.aliases]) {
      index.set(foldHeader(text), column.key);
    }
  }
  return index;
}

export function labelOf(kind, key) {
  return (COLUMNS[kind] ?? []).find((column) => column.key === key)?.label ?? key;
}

/** GET imports/spec gövdesi. */
export function buildSpec(env = process.env) {
  const kinds = {};
  for (const kind of BULK_KINDS) {
    kinds[kind] = {
      columns: COLUMNS[kind].map((column) => ({
        key: column.key,
        label: column.label,
        required: column.required,
        type: column.type,
        max_length: column.max_length,
        aliases: [...column.aliases],
        hint: column.hint,
      })),
      relation_words: kind === 'people' || kind === 'all_in_one' ? clone(RELATION_WORDS) : {},
      ...(kind === 'apartments' || kind === 'all_in_one' ? { responsible_words: clone(RESPONSIBLE_WORDS) } : {}),
      ...(kind === 'opening_balances' ? { account_words: clone({ owner: ['Ev sahibi', 'Malik', 'Mal sahibi'], tenant: ['Kiracı'] }), module: 'finance' } : {}),
    };
  }
  return { spec_version: SPEC_VERSION, max_rows: maxRows(env), max_body_bytes: MAX_BODY_BYTES, kinds };
}

function clone(words) {
  return Object.fromEntries(Object.entries(words).map(([key, list]) => [key, [...list]]));
}
