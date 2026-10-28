// Toplu yükleme: planın hesap bölümü (kullanıcı adı önerileri). Planlayıcılar saftır; bu modül planın "hesap açılacak satırlar" listesini veritabanına
// karşı çözer (önizleme, öneri ucu ve commit AYNI işlevi kullanır):
//   - satırdan yeni hesap açılacak mı, yoksa e-postası mevcut bir hesaba mı ait (o hesaba bağlanır, kullanıcı adı salt okunur) ya da bu e-posta kullanılamaz mı
//     (yazıcıdaki provisionOne kuralının aynısı; fark: burada yalnız BU SİTENİN görebildiği hesaplar aranır, aşağıya bakın);
//   - yeni hesaplar için Ad Soyad'dan kullanıcı adı (bu sitede ve aynı yüklemede boşta olan ilk varyasyon).
// Çözümlenen adlar `preview_hash`'e girer: ön izlemeden sonra bu sitede bir ad başkasına geçerse commit PREVIEW_STALE verir ve yönetici yeni adı görür.
//
// SİTE KAPSAMI (güvenlik denetimi 2026-10-28, authz-modules-1): önizleme / öneri ucu HİÇBİR yanıtta başka sitenin hesabı hakkında var/yok bilgisi vermez. Başka sitede
// kayıtlı e-posta ya da kullanıcı adı «yok» gibi davranır (yeni hesap, boş ad); aynı sitedeki gerçek çakışma (bağlanabilir hesap → `existing`, bağlanamayan →
// `email_in_use`, alınmış ad → `_N`) doğru raporlanır. Sistem genelindeki kesin denetim yazım anındadır (bulk_import_writer.js: `EMAIL_IN_USE` atlaması, `renamed`).

import { sha256 } from './bulk_import_body.js';
import { slugifyLoginName, resolveLoginNames, takenLoginNames, normalizeTypedLoginName } from './bulk_import_login_names.js';
import { requireScopeSite, siteVisibleUserSql } from './bulk_import_scope.js';
import { LOGIN_NAME_OVERRIDE_KEY } from './bulk_import_spec.js';
import { siteTiePredicate } from './people_sync_sql.js';

/** Hesap açılabilen (kişi satırı içeren) türler. */
export const ACCOUNT_KINDS = Object.freeze(new Set(['people', 'all_in_one']));

const QUERY_CHUNK = 5000;
const INTERNAL_EMAIL_SUFFIX = '@ahbu.local';

const realEmailOf = (value) => {
  if (typeof value !== 'string') return null;
  const text = value.trim().toLowerCase();
  return text !== '' && !text.endsWith(INTERNAL_EMAIL_SUFFIX) ? text : null;
};

/** Satırlardaki biçimi geçerli, yönetici seçimi kullanıcı adları (küçük harfli, tekil). */
export function collectOverrideLoginNames(rows) {
  const names = new Set();
  for (const row of rows) {
    const raw = row.cells[LOGIN_NAME_OVERRIDE_KEY];
    if (raw === null || raw === undefined || String(raw).trim() === '') continue;
    const typed = normalizeTypedLoginName(String(raw));
    if (!typed.error) names.add(typed.value);
  }
  return [...names];
}

/**
 * Gövde satırlarındaki seçilmiş adlardan BU SİTEDE ZATEN kayıtlı olanlar (plan aşaması bunları LOGIN_NAME_TAKEN hatası yapar). Tek sorgu. Başka sitedeki ad burada
 * «kayıtlı» sayılmaz (sayım açığı kapalı); o ad yazımda sıradaki boş adla değiştirilir ve sonuçta bildirilir.
 */
export async function loadTakenOverrides(db, siteCode, rows) {
  const names = collectOverrideLoginNames(rows);
  return names.length === 0 ? new Set() : takenLoginNames(db, names, { siteCode });
}

/**
 * E-postası BU SİTENİN görebildiği (siteVisibleUserSql) bir hesaba ait adaylar: küçük harfli e-posta -> { userCode, loginName, linkable }. Başka sitedeki / yönetici
 * hesabındaki e-posta burada HİÇ dönmez: önizleme onu bilinmeyen e-posta gibi (yeni hesap) gösterir; yazım anındaki sistem geneli denetim `EMAIL_IN_USE` ile atlar.
 */
async function loadEmailOwners(db, siteCode, emails) {
  const site = requireScopeSite(siteCode);
  const owners = new Map();
  for (let index = 0; index < emails.length; index += QUERY_CHUNK) {
    const part = emails.slice(index, index + QUERY_CHUNK);
    const found = await db.query(
      `
        SELECT LOWER(u.email) AS email, u.user_code, u.login_name,
               (u.deleted_at IS NULL AND u.role NOT IN ('super_user', 'site_manager') AND ${siteTiePredicate('u.user_code', '$2::BIGINT')}) AS linkable
        FROM users u
        WHERE LOWER(u.email) = ANY($1::TEXT[])
          AND ${siteVisibleUserSql('u.user_code', '$2::BIGINT')}
      `,
      [part, site],
    );
    for (const row of found.rows) {
      if (!owners.has(row.email)) {
        owners.set(row.email, { userCode: Number(row.user_code), loginName: row.login_name ?? null, linkable: row.linkable === true });
      }
    }
  }
  return owners;
}

/**
 * Planın hesap bölümünü çözer.
 * @param {{ results: object[] }} plan computePlan çıktısı (satır sonuçlarında `account`: { type: 'candidate'|'existing', ... })
 * @returns {Promise<{ items: object[], expected: Map<string, object>, signature: string }>}
 *   items: satır sırasıyla { n, status: 'new'|'existing'|'email_in_use'|'shared'|'unavailable'|'rejected', login_name, editable, custom?, line?, code?, message? }
 *   expected: kişi ref'i -> { status, loginName, n } (yazıcı yalnız 'new' için bekleneni kullanır)
 */
export async function resolvePlanAccounts(db, { siteCode, plan }) {
  const items = [];
  const expected = new Map();
  const candidates = []; // ref başına İLK satır
  const firstLineOfRef = new Map();
  const itemAt = new Map(); // n -> items dizini (yeni hesaplar sonradan doldurulur)

  for (const result of plan.results) {
    const account = result.account;
    if (result.hasError) {
      // yöneticinin seçtiği ad reddedildi (geçersiz / bu sitede kayıtlı / dosyada tekrar): tabloda satırın hücresinde nedeniyle gösterilir
      const rejected = result.issues.find((issue) => issue.code.startsWith('LOGIN_NAME_'));
      if (rejected) items.push({ n: result.n, status: 'rejected', login_name: null, editable: true, code: rejected.code, message: rejected.message });
      continue;
    }
    if (!account) continue;
    if (account.type === 'existing') {
      items.push({ n: result.n, status: 'existing', login_name: account.loginName ?? null, editable: false });
      continue;
    }
    const first = firstLineOfRef.get(account.ref);
    if (first !== undefined) {
      items.push({ n: result.n, status: 'shared', login_name: null, editable: false, line: first, ref: account.ref, sig: true });
      continue;
    }
    firstLineOfRef.set(account.ref, result.n);
    candidates.push({ n: result.n, ...account });
    itemAt.set(result.n, items.length);
    items.push({ n: result.n, status: 'new', login_name: null, editable: true, custom: account.loginName !== null && account.loginName !== undefined, sig: true });
  }

  const emails = [...new Set(candidates.map((candidate) => realEmailOf(candidate.email)).filter((email) => email !== null))];
  const owners = emails.length > 0 ? await loadEmailOwners(db, siteCode, emails) : new Map();

  const requests = [];
  for (const candidate of candidates) {
    const item = items[itemAt.get(candidate.n)];
    const email = realEmailOf(candidate.email);
    const owner = email === null ? undefined : owners.get(email);
    if (owner !== undefined) {
      if (owner.linkable) {
        Object.assign(item, { status: 'existing', login_name: owner.loginName, editable: false, custom: false });
        expected.set(candidate.ref, { status: 'existing', loginName: owner.loginName, n: candidate.n });
      } else {
        Object.assign(item, { status: 'email_in_use', login_name: null, editable: false, custom: false });
        expected.set(candidate.ref, { status: 'email_in_use', loginName: null, n: candidate.n });
      }
      continue;
    }
    const fixed = candidate.loginName !== null && candidate.loginName !== undefined;
    const base = fixed ? candidate.loginName : candidate.name ? slugifyLoginName(candidate.name) : null;
    if (base === null) {
      // adsız kişi: yazıcı daire tabanlı yedek adı üretir; önizlemede ad gösterilemez
      Object.assign(item, { status: 'unavailable', login_name: null, editable: false, custom: false });
      expected.set(candidate.ref, { status: 'new', loginName: null, n: candidate.n });
      continue;
    }
    requests.push({ key: candidate.ref, base, fixed });
  }

  const resolved = await resolveLoginNames(db, requests, { siteCode });
  const candidateByRef = new Map(candidates.map((entry) => [entry.ref, entry]));
  for (const request of requests) {
    const candidate = candidateByRef.get(request.key);
    const item = items[itemAt.get(candidate.n)];
    const name = resolved.get(request.key) ?? null;
    if (name === null) {
      Object.assign(item, { status: 'unavailable', login_name: null, editable: false, custom: false });
      expected.set(candidate.ref, { status: 'new', loginName: null, n: candidate.n });
    } else {
      // seçilen ad kısa bir yarışla başkasına geçtiyse (plan taze olduğundan nadir) artık «özel» sayılmaz
      item.login_name = name;
      item.custom = request.fixed && name === request.base;
      expected.set(candidate.ref, { status: 'new', loginName: name, n: candidate.n });
    }
  }
  for (const item of items) {
    if (item.status === 'shared') item.login_name = expected.get(item.ref)?.loginName ?? null;
  }

  // imza: yalnız BU yüklemenin yeni açacağı / bağlayacağı hesaplar (planlayıcının salt okunur «mevcut hesap» satırları dışarıda)
  const signature = items
    .filter((item) => item.sig === true)
    .map((item) => `${item.n}:${item.status}:${item.login_name ?? ''}`)
    .join('|');
  for (const item of items) {
    delete item.ref;
    delete item.sig;
  }
  return { items, expected, signature };
}

/**
 * Hesap çözümlemesini plana işler: hesap listesi yanıta girer ve (hesap açılan satır varsa) çözümlenen adlar `preview_hash`'e katılır. Hesap açılacak
 * satır yoksa hash DEĞİŞMEZ.
 */
export async function attachPlanAccounts(db, { siteCode, plan }) {
  const accounts = await resolvePlanAccounts(db, { siteCode, plan });
  plan.accounts = accounts;
  plan.view.accounts = accounts.items;
  if (accounts.signature !== '') {
    plan.previewHash = sha256(`${plan.previewHash}
accounts
${accounts.signature}`);
    plan.view.preview_hash = plan.previewHash;
  }
  return plan;
}
