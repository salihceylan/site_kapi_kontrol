// Yasal belge yükleyici ve sunucu tarafı Markdown -> HTML dönüştürücü. Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md (1.4).
//
// KAYNAK: server/legal/*.md (sahibi hukuk ajanı). LEGAL_DIR ortam değişkeni dizini geçersiz kılar (testler server/test/fixtures/legal/ kullanır).
// Dosya biçimi: "---" ile çevrili basit front-matter (id, title, version, effective_date, required_for) + Markdown gövde. Ayrıştırıcı
// bağımlılıksız ve KASITLI olarak minimaldir (YAML değil): "anahtar: değer", satır sonu yorumu (" # ..."), "[a, b]" ya da "- a" listeleri.
//
// YER TUTUCULAR: {{company_name}} {{company_address}} {{mersis_no}} {{kep_address}} {{contact_email}} {{contact_phone}} -> platform_settings
// "legal.*" değerleri. Dolmamış (ya da bilinmeyen) yer tutucu "[……]" olarak bırakılır ve belge complete:false sayılır; gövdede zaten "[……]"
// bulunması ya da front-matter'da "complete: false" olması da belgeyi tamamlanmamış yapar. Değerler yer tutucu olarak girerken Markdown
// ayırıcılarından arındırılır (bir ayar değeri bağlantı / kalın / başlık üretemez).
//
// HTML DÖNÜŞÜMÜ (izinli alt küme): # ## ### başlık, paragraf, "-" ve "1." listeleri, **kalın**, [metin](https://...) bağlantısı, ayırıcı çizgi.
// TÜM metin kaçışlanır; yalnız https:// bağlantılar; tablo YOK (satırlar düz metin kalır); ham HTML hiçbir koşulda geçmez.
//
// ÖNBELLEK: ayrıştırılmış dosyalar (ad, mtime, boyut) anahtarıyla bellekte tutulur; her istekte yalnız dizin listesi + stat okunur,
// değişen dosya yeniden ayrıştırılır. Yer tutucu doldurma ve HTML üretimi her istekte yapılır (ayarlar değişebilir; ucuz).

import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const DEFAULT_LEGAL_DIR = path.resolve(HERE, '..', '..', 'legal');

export const LEGAL_PLACEHOLDERS = Object.freeze([
  'company_name',
  'company_address',
  'mersis_no',
  'kep_address',
  'contact_email',
  'contact_phone',
]);
export const UNFILLED = '[……]';
export const REQUIRED_FOR_VALUES = Object.freeze(['register', 'site_application']);
export const DOCUMENT_ORDER = Object.freeze(['terms', 'privacy', 'kvkk_notice', 'dpa', 'account_deletion']);

const MAX_FILE_BYTES = 512 * 1024;
const MAX_FILES = 50;
const ID_RE = /^[a-z][a-z0-9_]{1,39}$/;
const VERSION_RE = /^[0-9A-Za-z._-]{1,40}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
// BOM'u kaynakta harf olarak yazmamak icin kodla uretilir.
const BOM_RE = new RegExp(`^${String.fromCharCode(0xfeff)}`);
const PLACEHOLDER_RE = /\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/g;
const UNFILLED_LITERAL_RE = /\[(?:…|\.{3,})+\]/;
// Hukuk taslağındaki açık iş işaretleri: "[KARAR/BİLGİ GEREKLİ: ...]" (karar / bilgi bekleniyor) ve "[AVUKAT DOĞRULASIN: ...]" (hukukçu doğrulaması
// bekleniyor). Gövdede kaldıkları sürece belge complete:false sayılır; metin olduğu gibi (işaretle birlikte) sunulur.
const OPEN_MARKER_RE = /\[\s*(?:KARAR\s*\/\s*BİLGİ\s+GEREKLİ|AVUKAT\s+DOĞRULASIN)/;

/** LEGAL_DIR (boş değilse) ya da varsayılan server/legal. */
export function legalDir(env = process.env) {
  const configured = String(env.LEGAL_DIR ?? '').trim();
  return configured === '' ? DEFAULT_LEGAL_DIR : path.resolve(configured);
}

// ---------------------------------------------------------------------------
// Front-matter
// ---------------------------------------------------------------------------

function stripQuotes(value) {
  const text = value.trim();
  if (text.length >= 2 && (text[0] === '"' || text[0] === "'") && text.at(-1) === text[0]) {
    return text.slice(1, -1);
  }
  return text;
}

/** "değer   # yorum" -> "değer" (tırnaklı değerde "#" yorum sayılmaz). */
function stripInlineComment(value) {
  const text = value.trim();
  if (text[0] === '"' || text[0] === "'") {
    const close = text.indexOf(text[0], 1);
    return close === -1 ? text : text.slice(0, close + 1);
  }
  const hash = text.search(/\s#/);
  return (hash === -1 ? text : text.slice(0, hash)).trim();
}

/**
 * Metni front-matter + gövdeye ayırır. Front-matter yoksa / kapanmamışsa null.
 * @returns {{ meta: Record<string, string|string[]>, body: string } | null}
 */
export function parseFrontMatter(raw) {
  const text = String(raw ?? '').replace(BOM_RE, '').replace(/\r\n?/g, '\n');
  const match = /^---[ \t]*\n([\s\S]*?)\n---[ \t]*(?:\n|$)/.exec(text);
  if (!match) {
    return null;
  }
  const meta = Object.create(null);
  let listKey = null;
  for (const line of match[1].split('\n')) {
    if (/^\s*(#.*)?$/.test(line)) {
      continue;
    }
    const item = /^\s+-\s+(.*)$/.exec(line) ?? (listKey ? /^-\s+(.*)$/.exec(line) : null);
    if (item && listKey) {
      meta[listKey].push(stripQuotes(stripInlineComment(item[1])));
      continue;
    }
    const pair = /^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$/.exec(line);
    if (!pair) {
      listKey = null;
      continue;
    }
    const key = pair[1];
    const value = stripInlineComment(pair[2]);
    if (value === '') {
      meta[key] = [];
      listKey = key;
    } else if (value.startsWith('[') && value.endsWith(']')) {
      meta[key] = value
        .slice(1, -1)
        .split(',')
        .map((part) => stripQuotes(part))
        .filter((part) => part !== '');
      listKey = null;
    } else {
      meta[key] = stripQuotes(value);
      listKey = null;
    }
  }
  return { meta: { ...meta }, body: text.slice(match[0].length) };
}

/**
 * Bir belge dosyasını ayrıştırır ve doğrular.
 * @returns {{ doc: object } | { error: string }}
 */
export function parseLegalFile(fileName, raw) {
  const parsed = parseFrontMatter(raw);
  if (!parsed) {
    return { error: `${fileName}: front-matter (--- ... ---) bulunamadı` };
  }
  const { meta, body } = parsed;
  const scalar = (key) => (typeof meta[key] === 'string' ? meta[key].trim() : '');
  const id = scalar('id').toLowerCase();
  if (!ID_RE.test(id)) {
    return { error: `${fileName}: geçersiz id` };
  }
  const title = scalar('title');
  if (title === '' || title.length > 200) {
    return { error: `${fileName}: title zorunlu (en çok 200 karakter)` };
  }
  const version = scalar('version');
  if (!VERSION_RE.test(version)) {
    return { error: `${fileName}: geçersiz version` };
  }
  const effective = scalar('effective_date');
  const requiredRaw = Array.isArray(meta.required_for) ? meta.required_for : scalar('required_for') === '' ? [] : [scalar('required_for')];
  const requiredFor = REQUIRED_FOR_VALUES.filter((value) => requiredRaw.map((item) => String(item).trim().toLowerCase()).includes(value));
  return {
    doc: {
      id,
      title,
      version,
      effective_date: DATE_RE.test(effective) ? effective : null,
      required_for: requiredFor,
      body,
      forceIncomplete: scalar('complete').toLowerCase() === 'false',
    },
  };
}

// ---------------------------------------------------------------------------
// Dosya yükleme (mtime önbelleği)
// ---------------------------------------------------------------------------

const fileCache = new Map(); // dir -> Map(fileName -> { mtimeMs, size, result })

/** Testler için önbelleği boşaltır. */
export function clearLegalCache() {
  fileCache.clear();
}

/**
 * dizindeki *.md dosyalarını yükler (değişmeyenler önbellekten). Dizin yoksa / okunamazsa boş liste (ayrıntı günlüğe yalnız kodla yazılır).
 * Aynı id'li ikinci dosya (ada göre sıralı) yok sayılır.
 * @returns {Promise<object[]>} ham belgeler (yer tutucu doldurulmamış)
 */
export async function loadLegalFiles(dir = legalDir()) {
  let names;
  try {
    names = (await fs.readdir(dir)).filter((name) => /\.md$/i.test(name)).sort().slice(0, MAX_FILES);
  } catch (error) {
    if (error?.code !== 'ENOENT') {
      // eslint-disable-next-line no-console
      console.error('[legal] belge dizini okunamadi:', error?.code || 'hata');
    }
    fileCache.delete(dir);
    return [];
  }
  const perDir = fileCache.get(dir) ?? new Map();
  fileCache.set(dir, perDir);
  const seen = new Set(names);
  for (const cachedName of [...perDir.keys()]) {
    if (!seen.has(cachedName)) {
      perDir.delete(cachedName);
    }
  }
  const docs = [];
  const ids = new Set();
  for (const name of names) {
    let entry = perDir.get(name);
    try {
      const stat = await fs.stat(path.join(dir, name));
      if (!stat.isFile()) {
        continue;
      }
      if (!entry || entry.mtimeMs !== stat.mtimeMs || entry.size !== stat.size) {
        if (stat.size > MAX_FILE_BYTES) {
          entry = { mtimeMs: stat.mtimeMs, size: stat.size, result: { error: `${name}: dosya çok büyük` } };
        } else {
          entry = { mtimeMs: stat.mtimeMs, size: stat.size, result: parseLegalFile(name, await fs.readFile(path.join(dir, name), 'utf8')) };
        }
        perDir.set(name, entry);
        if (entry.result.error) {
          // eslint-disable-next-line no-console
          console.error(`[legal] belge atlandi: ${entry.result.error}`);
        }
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[legal] belge okunamadi:', name, error?.code || 'hata');
      continue;
    }
    const doc = entry.result.doc;
    if (!doc) {
      continue;
    }
    if (ids.has(doc.id)) {
      // eslint-disable-next-line no-console
      console.error(`[legal] yinelenen belge id'si yok sayildi: ${doc.id} (${name})`);
      continue;
    }
    ids.add(doc.id);
    docs.push(doc);
  }
  return docs;
}

// ---------------------------------------------------------------------------
// Yer tutucu doldurma
// ---------------------------------------------------------------------------

/** Ayar değerini Markdown ayırıcılarından arındırır (tek satır; bağlantı / kalın / başlık / HTML üretemez). */
export function markdownSafeValue(value) {
  return String(value ?? '')
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, ' ')
    .replace(/[[\]<>`\\]/g, '')
    .replace(/\*{2,}/g, '*')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/^(?:[#>*+-]\s*)+/, '');
}

/**
 * Gövdedeki yer tutucuları doldurur. Dolu değer kullanılır; boş / bilinmeyen -> "[……]".
 * @returns {{ text: string, complete: boolean }} complete: hiç "[……]" ve açık iş işareti ("[KARAR/BİLGİ GEREKLİ" / "[AVUKAT DOĞRULASIN") kalmadı
 */
export function fillPlaceholders(body, legalSettings = {}) {
  let unfilled = false;
  // Tek geçiş: eklenen değerler yeniden taranmaz (değer içinde "{{...}}" olsa da genişlemez).
  const text = String(body ?? '').replace(PLACEHOLDER_RE, (_match, name) => {
    const key = String(name).toLowerCase();
    const value = LEGAL_PLACEHOLDERS.includes(key) && typeof legalSettings?.[key] === 'string' ? markdownSafeValue(legalSettings[key]) : '';
    if (value === '') {
      unfilled = true;
      return UNFILLED;
    }
    return value;
  });
  if (UNFILLED_LITERAL_RE.test(text) || OPEN_MARKER_RE.test(text.normalize('NFC'))) {
    unfilled = true;
  }
  return { text, complete: !unfilled };
}

const FALLBACK_ACCOUNT_DELETION = Object.freeze({
  id: 'account_deletion',
  title: 'Hesap ve Veri Silme',
  version: '2026-10-16',
  effective_date: '2026-10-16',
  required_for: [],
  forceIncomplete: false,
  body: [
    '# Hesap ve Veri Silme',
    '',
    'Hesabınızı ve hesabınıza bağlı kişisel verilerinizi silmek için uygulamada Profil bölümünde yer alan hesap silme seçeneğini kullanabilirsiniz. Silme işlemi için hesap parolanız istenir.',
    '',
    'Uygulamaya erişemiyorsanız silme talebinizi {{contact_email}} adresine e-posta ile iletebilirsiniz. Talebiniz, hesabın size ait olduğu doğrulandıktan sonra yerine getirilir.',
    '',
    'Hesap silindiğinde adınız, e-posta adresiniz ve telefon numaranız hesaptan kaldırılır; giriş yapamazsınız. Site yönetiminin yasal saklama yükümlülüğü kapsamındaki kayıtlar (örneğin aidat ve borç kayıtları) silinmeyebilir.',
  ].join('\n'),
});

/**
 * Dosyalardan okunan ham belgeleri yer tutucu doldurulmuş, API biçimindeki belgelere çevirir. `account_deletion` dosyası yoksa kısa yedek
 * metin eklenir. Sıra: bilinen belgeler (terms, privacy, kvkk_notice, dpa, account_deletion), sonra kalanlar id'ye göre.
 * @returns {Array<{id,title,version,effective_date,required_for,complete,content_md}>}
 */
export function resolveDocuments(rawDocs, legalSettings = {}) {
  const docs = [...rawDocs];
  if (!docs.some((doc) => doc.id === FALLBACK_ACCOUNT_DELETION.id)) {
    docs.push(FALLBACK_ACCOUNT_DELETION);
  }
  const rank = (id) => {
    const index = DOCUMENT_ORDER.indexOf(id);
    return index === -1 ? DOCUMENT_ORDER.length : index;
  };
  docs.sort((a, b) => rank(a.id) - rank(b.id) || a.id.localeCompare(b.id));
  return docs.map((doc) => {
    const filled = fillPlaceholders(doc.body, legalSettings);
    return {
      id: doc.id,
      title: doc.title,
      version: doc.version,
      effective_date: doc.effective_date,
      required_for: [...doc.required_for],
      complete: filled.complete && doc.forceIncomplete !== true,
      content_md: filled.text,
    };
  });
}

/** Liste yanıtı satırı (içeriksiz). */
export function summarizeDocument(doc) {
  const { content_md: _content, ...summary } = doc;
  return summary;
}

// ---------------------------------------------------------------------------
// Markdown -> HTML (izinli alt küme)
// ---------------------------------------------------------------------------

export function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

const INLINE_RE = /\*\*([^*\n]+?)\*\*|\[([^\]\n]{1,300})\]\((https:\/\/[^\s()<>"'`\\]{1,2000})\)/g;

function safeHttpsUrl(candidate) {
  try {
    const url = new URL(candidate);
    if (url.protocol !== 'https:' || !url.hostname || url.username || url.password) {
      return null;
    }
    return candidate;
  } catch (_error) {
    return null;
  }
}

/** Satır içi: **kalın** ve [metin](https://...) dışındaki HER ŞEY kaçışlanır. */
export function renderInline(text) {
  let out = '';
  let last = 0;
  for (const match of text.matchAll(INLINE_RE)) {
    out += escapeHtml(text.slice(last, match.index));
    if (match[1] !== undefined) {
      out += `<strong>${escapeHtml(match[1])}</strong>`;
    } else {
      const href = safeHttpsUrl(match[3]);
      out += href
        ? `<a href="${escapeHtml(href)}" rel="noopener noreferrer nofollow" target="_blank">${escapeHtml(match[2])}</a>`
        : escapeHtml(match[0]);
    }
    last = match.index + match[0].length;
  }
  return out + escapeHtml(text.slice(last));
}

const HEADING_RE = /^(#{1,3})[ \t]+(.+?)[ \t]*#*[ \t]*$/;
const UL_RE = /^([ \t]*)[-*][ \t]+(.*)$/;
const OL_RE = /^([ \t]*)\d{1,3}\.[ \t]+(.*)$/;
const HR_RE = /^(?:-{3,}|\*{3,}|_{3,})[ \t]*$/;

/**
 * İzinli Markdown alt kümesini HTML'e çevirir. `headingOffset`: "#" kaç seviye aşağı render edilsin (h1 sayfa başlığına ayrılabilir).
 * Çıktıdaki tek etiketler: h1-h6, p, ul, ol, li, hr, strong, a. Tablo yok; ham HTML kaçışlanır.
 */
export function renderMarkdown(markdown, { headingOffset = 0 } = {}) {
  const lines = String(markdown ?? '').replace(/\r\n?/g, '\n').split('\n');
  const html = [];
  let paragraph = [];
  let list = null; // { tag, items: [{ html, sub }] }

  const flushParagraph = () => {
    if (paragraph.length > 0) {
      html.push(`<p>${renderInline(paragraph.join(' '))}</p>`);
      paragraph = [];
    }
  };
  const flushList = () => {
    if (list) {
      const items = list.items.map((item) => `<li${item.sub ? ' class="sub"' : ''}>${item.html}</li>`).join('');
      html.push(`<${list.tag}>${items}</${list.tag}>`);
      list = null;
    }
  };

  for (const line of lines) {
    if (line.trim() === '') {
      flushParagraph();
      flushList();
      continue;
    }
    const heading = HEADING_RE.exec(line);
    if (heading) {
      flushParagraph();
      flushList();
      const level = Math.min(6, heading[1].length + headingOffset);
      html.push(`<h${level}>${renderInline(heading[2])}</h${level}>`);
      continue;
    }
    if (HR_RE.test(line.trim())) {
      flushParagraph();
      flushList();
      html.push('<hr>');
      continue;
    }
    const unordered = UL_RE.exec(line);
    const ordered = unordered ? null : OL_RE.exec(line);
    const item = unordered ?? ordered;
    if (item) {
      flushParagraph();
      const tag = unordered ? 'ul' : 'ol';
      if (list && list.tag !== tag && item[1].length === 0) {
        flushList();
      }
      list ??= { tag, items: [] };
      list.items.push({ html: renderInline(item[2]), sub: item[1].length >= 2 });
      continue;
    }
    if (list && /^[ \t]{2,}\S/.test(line)) {
      // girintili devam satırı: önceki madde metnine eklenir
      const lastItem = list.items.at(-1);
      lastItem.html += ` ${renderInline(line.trim())}`;
      continue;
    }
    flushList();
    paragraph.push(line.trim());
  }
  flushParagraph();
  flushList();
  return html.join('\n');
}

// ---------------------------------------------------------------------------
// Sayfa
// ---------------------------------------------------------------------------

export const LEGAL_PAGE_CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

const PAGE_STYLE = `
    :root { color-scheme: light; }
    body { margin: 0; padding: 16px; background: #f3f4f6; color: #111827; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; line-height: 1.65; }
    main { max-width: 760px; margin: 24px auto; background: #ffffff; border-radius: 12px; padding: 28px 32px; box-shadow: 0 1px 6px rgba(0, 0, 0, 0.08); }
    h1 { font-size: 26px; margin: 0 0 8px; line-height: 1.3; }
    h2 { font-size: 20px; margin: 28px 0 8px; }
    h3 { font-size: 17px; margin: 22px 0 6px; }
    h4, h5, h6 { font-size: 15px; margin: 18px 0 6px; }
    p { margin: 0 0 14px; }
    ul, ol { margin: 0 0 14px; padding-left: 24px; }
    li { margin-bottom: 6px; }
    li.sub { margin-left: 20px; list-style-type: circle; }
    hr { border: 0; border-top: 1px solid #e5e7eb; margin: 24px 0; }
    a { color: #1d4ed8; }
    .meta { color: #6b7280; font-size: 14px; margin: 0 0 20px; }
    .notice { background: #fef3c7; border: 1px solid #f59e0b; color: #78350f; border-radius: 8px; padding: 10px 14px; font-size: 14px; margin: 0 0 20px; }
    @media (max-width: 600px) { main { padding: 20px 16px; margin: 8px auto; } body { padding: 8px; } }
  `;

/** `GET /legal/:id` sayfası: sade, kendi stilini taşıyan, tüm metni kaçışlı HTML. */
export function renderLegalPage(doc) {
  // Sayfa başlığı (h1) her zaman belge başlığıdır; gövdedeki ilk "# ..." başlığı AYNI metinse tekrarlanmaz, farklıysa h2 olarak korunur.
  let markdown = doc.content_md;
  const lead = /^\s*#[ \t]+(.+?)[ \t]*#*[ \t]*(?:\n|$)/.exec(markdown);
  const leadIsTitle = Boolean(lead) && lead[1].trim() === doc.title.trim();
  if (leadIsTitle) {
    markdown = markdown.slice(lead[0].length);
  }
  // Başlık sayfa h1'ine taşındıysa "##" doğrudan h2 olur; taşınmadıysa tüm gövde başlıkları bir seviye aşağı iner.
  const body = renderMarkdown(markdown, { headingOffset: leadIsTitle ? 0 : 1 });
  const metaParts = [`Sürüm: ${doc.version}`];
  if (doc.effective_date) {
    metaParts.push(`Yürürlük tarihi: ${doc.effective_date}`);
  }
  const notice = doc.complete
    ? ''
    : `\n    <p class="notice">Bu belgede henüz doldurulmamış veya doğrulanmamış bölümler bulunuyor; belge taslak niteliğindedir.</p>`;
  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(doc.title)}</title>
  <style>${PAGE_STYLE}</style>
</head>
<body>
  <main>
    <h1>${escapeHtml(doc.title)}</h1>
    <p class="meta">${escapeHtml(metaParts.join(' · '))}</p>${notice}
${body}
  </main>
</body>
</html>`;
}

/** Başlık + tek paragraflı sade sayfa (404 / hata). */
export function renderMessagePage(title, message) {
  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="robots" content="noindex" />
  <title>${escapeHtml(title)}</title>
  <style>${PAGE_STYLE}</style>
</head>
<body>
  <main>
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(message)}</p>
  </main>
</body>
</html>`;
}

export const renderLegalNotFoundPage = () => renderMessagePage('Belge bulunamadı', 'İstediğiniz belge bulunamadı.');
export const renderLegalErrorPage = () => renderMessagePage('İşlem tamamlanamadı', 'Belge şu anda gösterilemiyor. Lütfen biraz sonra yeniden deneyin.');
