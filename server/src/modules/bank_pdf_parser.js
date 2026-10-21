// Banka PDF hesap ekstresi ayrıştırıcı (saf; PDF kütüphanesinden bağımsız). Girdi: sayfa metin ögeleri { str, x, y, w, h } (pdf.js getTextContent çıktısı).
// OCR YOK: yalnız metin katmanı olan PDF'ler okunur. Çıktı, istemcideki Excel/CSV ayrıştırıcının ürettiği satır yapısıyla aynıdır
// ({ n, value_date, amount_minor, description, counterparty_name, counterparty_iban, bank_reference, balance_after_minor }) + `confidence`.
// Yaklaşım: ögeleri konumlarına göre satır ve hücrelere topla -> başlık satırı (Tarih/Açıklama/Tutar/Borç/Alacak/Bakiye...) varsa sütunları ondan al,
// yoksa genel sezgi (tarih + Türk para biçimi) -> işaret: sütun (Borç/Alacak), tutar işareti/(B)(A) göstergesi, yoksa bakiye farkı -> işareti
// belirlenemeyen satır "okunamayan" sayılır (yanlış yönde tahsilat yazmaktansa atlanır). Gerçek banka PDF örneği bu depoda YOKTUR; biçimler
// yaygın TR ekstre düzenlerine göre tasarlandı ve ancak kodla üretilmiş PDF/öge fikstürleriyle sınandı (docs/PLATFORM_FINANS_BANKA.md).
import { foldText } from './people_common.js';
import { normalizeIban } from './bank_line_match.js';

export const PDF_MAX_LINES = 1500;

const fold = (s) => foldText(String(s ?? '')).replace(/[^a-z0-9]+/g, ' ').trim();

// --- Tutar ve tarih -----------------------------------------------------------------------------------------

const ODD_SPACES = new RegExp('[' + String.fromCharCode(160, 8201, 8239) + ']', 'g'); // NBSP, ince ve dar boşluk
const INDICATOR_NEG = new Set(['b', 'borc', 'dr']);
const INDICATOR_POS = new Set(['a', 'alacak', 'cr']);

/** Türk para biçimi -> { minor (mutlak, kuruş), sign: -1 | 0 (açık işaret yok) | 1 }. Tutar değilse null. `allowInteger`: yalnız başlıklı sütunlarda "1250" gibi kuruşsuz sayılar. */
export function parseMoney(raw, { allowInteger = false } = {}) {
  let s = String(raw ?? '').replace(ODD_SPACES, ' ').trim();
  if (!s || s.length > 24) return null;
  let sign = 0;
  const ind = /^(.*\d)\s*\(?\s*(borc|alacak|b|a|dr|cr)\s*\)?$/.exec(foldText(s));
  if (ind) {
    sign = INDICATOR_NEG.has(ind[2]) ? -1 : 1;
    s = s.slice(0, ind[1].length);
  }
  s = s.replace(/\s*(₺|tl|try)\s*$/i, '').replace(/^(₺|tl|try)\s*/i, '').trim();
  const paren = /^\((.*)\)$/.exec(s);
  if (paren) {
    sign = -1;
    s = paren[1].trim();
  }
  if (/^[-−–]/.test(s)) {
    sign = -1;
    s = s.slice(1).trim();
  } else if (s.startsWith('+')) {
    sign = 1;
    s = s.slice(1).trim();
  }
  if (/[-−–]$/.test(s)) {
    sign = -1;
    s = s.slice(0, -1).trim();
  } else if (s.endsWith('+')) {
    sign = 1;
    s = s.slice(0, -1).trim();
  }
  s = s.replace(/(?<=\d) (?=\d{3}(?!\d))/g, '');
  let whole;
  let frac = '00';
  let m;
  if ((m = /^(\d{1,3}(?:\.\d{3})*|\d+),(\d{1,2})$/.exec(s))) {
    whole = m[1].replace(/\./g, '');
    frac = m[2].padEnd(2, '0');
  } else if ((m = /^(\d+)\.(\d{2})$/.exec(s))) {
    whole = m[1];
    frac = m[2].padEnd(2, '0');
  } else if (allowInteger && (m = /^(\d{1,3}(?:\.\d{3})+|\d+)$/.exec(s))) {
    whole = m[1].replace(/\./g, '');
  } else {
    return null;
  }
  const minor = Number(whole) * 100 + Number(frac);
  return Number.isSafeInteger(minor) && minor < 1_000_000_000_000 ? { minor, sign } : null;
}

const validDate = (y, mo, d) => {
  const t = new Date(Date.UTC(y, mo - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === mo - 1 && t.getUTCDate() === d;
};
const iso = (y, mo, d) => `${String(y).padStart(4, '0')}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

/** Metnin BAŞINDAKİ tarih (GG.AA.YYYY, GG/AA/YYYY, GG-AA-YYYY, GG.AA.YY, YYYY-AA-GG) -> 'YYYY-MM-DD' | null. */
export function parseDate(raw) {
  const s = String(raw ?? '').trim();
  let m = /^(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})(?!\d)/.exec(s);
  if (m) {
    const y = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
    return validDate(y, Number(m[2]), Number(m[1])) && y >= 2000 ? iso(y, Number(m[2]), Number(m[1])) : null;
  }
  m = /^(\d{4})-(\d{2})-(\d{2})(?!\d)/.exec(s);
  return m && validDate(Number(m[1]), Number(m[2]), Number(m[3])) ? iso(Number(m[1]), Number(m[2]), Number(m[3])) : null;
}

/** Hücre YALNIZ tarih (isteğe bağlı saat ile) ise tarih. */
const dateOnlyCell = (text) => (/^\s*(\d{1,2}[./-]\d{1,2}[./-]\d{2,4}|\d{4}-\d{2}-\d{2})(\s+\d{1,2}:\d{2}(:\d{2})?)?\s*$/.test(text) ? parseDate(text) : null);

// --- Sayfa düzeni: ögeler -> satırlar -> hücreler -----------------------------------------------------------

/** @returns {{ y:number, h:number, cells:{text:string,x:number,right:number,h:number}[] }[]} yukarıdan aşağıya */
export function layoutLines(items) {
  // Yalnız boşluk olan ögeler atılır: pdf.js, aralıklı metin parçalarının arasına genişliği boşluk kadar "sentetik" boşluk ögesi koyar; hücre sınırını onlar bozar.
  const clean = (items ?? []).filter((i) => typeof i.str === 'string' && i.str.trim() !== '' && Number.isFinite(i.x) && Number.isFinite(i.y));
  clean.sort((a, b) => b.y - a.y || a.x - b.x);
  const rows = [];
  for (const it of clean) {
    const h = it.h > 0 ? it.h : 8;
    const row = rows.find((r) => Math.abs(r.y - it.y) <= Math.max(1.5, 0.45 * Math.min(h, r.h)));
    if (row) {
      row.items.push(it);
      row.h = Math.max(row.h, h);
    } else rows.push({ y: it.y, h, items: [it] });
  }
  return rows.map((r) => {
    r.items.sort((a, b) => a.x - b.x);
    const cells = [];
    for (const it of r.items) {
      const w = it.w > 0 ? it.w : it.str.length * (it.h > 0 ? it.h : 8) * 0.5;
      const h = it.h > 0 ? it.h : 8;
      const last = cells[cells.length - 1];
      if (last && it.x - last.right <= 0.9 * Math.max(last.h, 6)) {
        const gap = it.x - last.right;
        const needSpace = gap > 0.12 * h && !last.text.endsWith(' ') && !it.str.startsWith(' ');
        last.text += (needSpace ? ' ' : '') + it.str;
        last.right = Math.max(last.right, it.x + w);
        last.h = Math.max(last.h, h);
      } else cells.push({ text: it.str, x: it.x, right: it.x + w, h });
    }
    const out = cells.map((c) => ({ ...c, text: c.text.replace(/\s+/g, ' ').trim() })).filter((c) => c.text !== '');
    return { y: r.y, h: r.h, cells: out };
  }).filter((r) => r.cells.length > 0);
}

// --- Başlık satırı ------------------------------------------------------------------------------------------

const HEADER_SYNONYMS = {
  indicator: ['b a', 'borc alacak', 'ba'],
  date: ['tarih', 'islem tarihi', 'tarihi', 'islem tarih', 'hareket tarihi'],
  valor: ['valor', 'valor tarihi'],
  description: ['aciklama', 'aciklamasi', 'islem aciklamasi', 'islem', 'detay', 'hareket aciklamasi', 'islem detayi', 'aciklama detay'],
  amount: ['tutar', 'islem tutari', 'miktar', 'hareket tutari', 'tutari', 'islem tutar'],
  debit: ['borc', 'cikan', 'borc tutari'],
  credit: ['alacak', 'giren', 'alacak tutari'],
  balance: ['bakiye', 'son bakiye', 'kalan bakiye', 'hesap bakiyesi'],
  reference: ['dekont no', 'dekont', 'referans', 'referans no', 'islem no', 'fis no', 'dekont numarasi'],
  name: ['gonderen', 'karsi taraf', 'gonderen alici', 'unvan', 'ad soyad', 'karsi hesap unvani'],
  iban: ['iban', 'karsi iban', 'gonderen iban'],
};
const SYNONYM_PAIRS = Object.entries(HEADER_SYNONYMS).flatMap(([key, list]) => list.map((syn) => [key, syn])).sort((a, b) => b[1].length - a[1].length);

function headerKey(text) {
  const f = fold(text);
  if (!f) return null;
  for (const [key, syn] of SYNONYM_PAIRS) if (f === syn || f.startsWith(`${syn} `)) return key;
  return null;
}

function headerColumns(cells) {
  const cols = [];
  for (const c of cells) {
    const key = headerKey(c.text);
    if (key && !cols.some((x) => x.key === key)) cols.push({ key, x: c.x, right: c.right, cx: (c.x + c.right) / 2 });
  }
  const keys = new Set(cols.map((c) => c.key));
  const ok = (keys.has('date') || keys.has('valor')) && (keys.has('amount') || keys.has('debit') || keys.has('credit')) && keys.size >= 3;
  return ok ? cols : null;
}

/** Tek satırdan, olmazsa altındaki satırla (iki satırlı başlık: "İşlem" / "Tarihi") birleştirerek başlık sütunlarını bulur. */
function findHeader(lines, i) {
  const single = headerColumns(lines[i].cells);
  if (single) return { cols: single, span: 1 };
  const next = lines[i + 1];
  if (!next || lines[i].y - next.y > 2.2 * Math.max(lines[i].h, next.h)) return null;
  const merged = lines[i].cells.map((c) => ({ ...c }));
  for (const c of next.cells) {
    const over = merged.find((m) => c.x <= m.right + 4 && m.x <= c.right + 4);
    if (over) {
      over.text = `${over.text} ${c.text}`;
      over.x = Math.min(over.x, c.x);
      over.right = Math.max(over.right, c.right);
    } else merged.push({ ...c });
  }
  const cols = headerColumns(merged);
  return cols ? { cols, span: 2 } : null;
}

function nearestColumn(cell, cols) {
  const cx = (cell.x + cell.right) / 2;
  let best = null;
  let bestD = Infinity;
  for (const col of cols) {
    const d = Math.min(Math.abs(cell.x - col.x), Math.abs(cell.right - col.right), Math.abs(cx - col.cx));
    if (d < bestD) {
      bestD = d;
      best = col;
    }
  }
  return best;
}

// --- Satır alanları -----------------------------------------------------------------------------------------

const TOTAL_RE = /\b(toplam|genel|ozet|devir|devreden|bakiye|donem sonu|donem basi|acilis)\b/;
const OPENING_RE = /^(onceki donem |donem basi |acilis )?(devir|devreden|bakiye|onceki bakiye|acilis bakiyesi)( bakiye| bakiyesi| tutari)?$/;
const FOOTER_RE = /^(sayfa|page|\d+ \d+$|www|mersis|ticaret sicil|bu belge|bilgilendirme|musteri hizmetleri|tel |faks|merkez|genel mudurluk)/;
const IBAN_RE = /TR\s?\d{2}(?:\s?\d{4}){5}\s?\d{2}/gi;
const ibansIn = (text) => [...String(text ?? '').matchAll(IBAN_RE)].map((m) => normalizeIban(m[0])).filter(Boolean);

/** Bir satırı alanlara ayırır. headerCols yoksa sezgisel kip. */
function fieldsOf(line, cols) {
  const f = { date: null, dateCell: null, desc: [], name: [], iban: [], ref: [], amount: null, debit: null, credit: null, balance: null, indicator: null, money: 0, textCells: 0 };
  const moneyCells = [];
  for (const cell of line.cells) {
    const key = cols ? nearestColumn(cell, cols)?.key : null;
    const asDate = dateOnlyCell(cell.text);
    if (asDate && (!cols || key === 'date' || key === 'valor' || (!f.date && cell === line.cells[0]))) {
      if (!f.date || key === 'date') {
        f.date = asDate;
        f.dateCell = cell;
      }
      continue;
    }
    if (cols) {
      if (key === 'amount' || key === 'debit' || key === 'credit' || key === 'balance') {
        const m = parseMoney(cell.text, { allowInteger: true });
        if (m) {
          f[key] = m;
          f.money += 1;
          continue;
        }
        if (key === 'amount' && INDICATOR_NEG.has(fold(cell.text)) || INDICATOR_POS.has(fold(cell.text))) {
          f.indicator = fold(cell.text);
          continue;
        }
        f.desc.push(cell.text);
        f.textCells += 1;
      } else if (key === 'indicator') f.indicator = fold(cell.text);
      else if (key === 'name') f.name.push(cell.text);
      else if (key === 'iban') f.iban.push(cell.text);
      else if (key === 'reference') f.ref.push(cell.text);
      else if (key === 'date' || key === 'valor') f.desc.push(cell.text); // tarih sütununda tarih olmayan metin
      else {
        f.desc.push(cell.text);
        f.textCells += 1;
      }
    } else {
      const m = parseMoney(cell.text);
      if (m) moneyCells.push(m);
      else if (INDICATOR_NEG.has(fold(cell.text)) || INDICATOR_POS.has(fold(cell.text))) f.indicator = fold(cell.text);
      else {
        f.desc.push(cell.text);
        f.textCells += 1;
      }
    }
  }
  if (!cols) {
    f.money = moneyCells.length;
    if (moneyCells.length === 1) f.amount = moneyCells[0];
    else if (moneyCells.length === 2) [f.amount, f.balance] = moneyCells;
    else if (moneyCells.length === 3) {
      f.amount = moneyCells[0];
      f.balance = moneyCells[2];
      f.ambiguous = true; // üç tutar: hangisi hangisi belli değil
    } else if (moneyCells.length > 3) f.ambiguous = true;
  }
  return f;
}

const median = (arr) => {
  const a = [...arr].sort((x, y) => x - y);
  return a.length === 0 ? 8 : a[Math.floor(a.length / 2)];
};

// --- Ana işlev ----------------------------------------------------------------------------------------------

/** Tutar + işaret kaynağı. Gösterge (B/A, Borç/Alacak) > tutardaki işaret > yok (0). */
function signedAmount(m, indicator) {
  if (!m) return null;
  if (indicator) return { minor: m.minor, sign: INDICATOR_NEG.has(indicator) ? -1 : 1, from: 'indicator' };
  return { minor: m.minor, sign: m.sign, from: m.sign !== 0 ? 'mark' : 'none' };
}

/** Başlıklı kipte tutar: ayrı Borç/Alacak sütunları ya da tek Tutar (+ gösterge). */
function amountOf(f) {
  if (f.debit || f.credit) {
    const net = (f.credit ? f.credit.minor : 0) - (f.debit ? f.debit.minor : 0);
    return net === 0 ? null : { minor: Math.abs(net), sign: net < 0 ? -1 : 1, from: 'column' };
  }
  return signedAmount(f.amount, f.indicator);
}

const joinText = (parts) => parts.join(' ').replace(/\s+/g, ' ').trim();

/**
 * pages: [{ items: [{ str, x, y, w, h }] }]; todayIso: gelecekteki tarihli satırlar okunamayan sayılır (sunucu zaten reddeder).
 * Dönüş: { lines, unreadable, skipped, mode: 'header'|'heuristic', accountIban, statement: {from,to}, charCount }
 */
export function parseBankPdf(pages, { todayIso } = {}) {
  const result = { lines: [], unreadable: 0, skipped: 0, mode: 'heuristic', accountIban: null, statement: { from: null, to: null }, charCount: 0 };
  const laid = (pages ?? []).map((p) => layoutLines(p.items));
  result.charCount = (pages ?? []).reduce((n, p) => n + (p.items ?? []).reduce((m, i) => m + String(i.str ?? '').replace(/\s+/g, '').length, 0), 0);
  let cols = null;
  for (const lines of laid) {
    for (let i = 0; i < lines.length && !cols; i += 1) cols = findHeader(lines, i)?.cols ?? null;
    if (cols) break;
  }
  result.mode = cols ? 'header' : 'heuristic';

  const seq = []; // işlemler ve bakiye-yalnız (devir) satırları, belge sırasıyla
  const preambleIbans = new Set();
  let started = false; // başlıklı kipte ilk başlık görüldü mü
  const live = () => started || seq.length > 0;
  for (const lines of laid) {
    const pageH = median(lines.flatMap((l) => l.cells.map((c) => c.h)));
    let current = null;
    let prevY = null;
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i];
      const header = cols ? findHeader(lines, i) : null;
      if (header) {
        cols = header.cols;
        i += header.span - 1;
        current = null;
        started = true;
        continue;
      }
      const rawText = line.cells.map((c) => c.text).join(' ');
      if (cols && !live()) {
        for (const t of ibansIn(rawText)) preambleIbans.add(t);
        continue;
      }
      const f = fieldsOf(line, cols);
      if (f.date) {
        const desc = joinText(f.desc);
        const amount = f.ambiguous ? null : cols ? amountOf(f) : signedAmount(f.amount, f.indicator);
        const balance = f.balance ? f.balance.minor * (f.balance.sign < 0 ? -1 : 1) : null;
        if (OPENING_RE.test(fold(desc)) || (!amount && balance !== null)) {
          seq.push({ kind: 'anchor', balance: balance ?? amount?.minor ?? null });
          current = null;
          continue;
        }
        if (!amount || (todayIso && f.date > todayIso)) {
          if (desc || f.money > 0) result.unreadable += 1;
          current = null;
          continue;
        }
        current = { kind: 'txn', date: f.date, amount, balance, desc: desc ? [desc] : [], name: [...f.name], iban: [...f.iban], ref: [...f.ref], header: Boolean(cols) };
        seq.push(current);
        prevY = line.y;
        continue;
      }
      if (!live()) {
        for (const t of ibansIn(rawText)) preambleIbans.add(t);
        continue;
      }
      if (f.money > 0) {
        if (TOTAL_RE.test(fold(rawText))) result.skipped += 1;
        else result.unreadable += 1;
        current = null;
        continue;
      }
      const textual = f.textCells > 0 || f.name.length > 0 || f.iban.length > 0 || f.ref.length > 0;
      if (current && textual && prevY !== null && prevY - line.y <= 1.9 * pageH && !FOOTER_RE.test(fold(rawText))) {
        if (f.desc.length > 0) current.desc.push(joinText(f.desc));
        current.name.push(...f.name);
        current.iban.push(...f.iban);
        current.ref.push(...f.ref);
        prevY = line.y;
      } else current = null;
    }
  }
  finish(result, seq, preambleIbans);
  return result;
}

const NAME_RE = /(?:g[oö]nderen|kar[sş][ıi] taraf|[oö]deyen)\s*:\s*([^;|:]{3,80})/i;
const NAME_STOP_RE = /\s+(?:a[cç][ıi]klama|iban|referans|ref|tr\d{2})\b.*$/i;

/** İşaret ve güven: bakiye zinciri (artan/azalan sıra), çelişki = düşük güven, işareti belirsiz satır = okunamayan. */
function finish(result, seq, preambleIbans) {
  let asc = 0;
  let desc = 0;
  for (let k = 1; k < seq.length; k += 1) {
    const prev = seq[k - 1];
    const cur = seq[k];
    if (prev.balance === null || cur.balance === null) continue;
    const delta = Math.abs(cur.balance - prev.balance);
    if (cur.kind === 'txn' && delta === cur.amount.minor) asc += 1;
    if (prev.kind === 'txn' && delta === prev.amount.minor) desc += 1;
  }
  const descending = desc > asc;
  const lines = [];
  for (let k = 0; k < seq.length; k += 1) {
    const row = seq[k];
    if (row.kind !== 'txn') continue;
    const neighbor = descending ? seq[k + 1] : seq[k - 1];
    let chainSign = 0;
    let chainBroken = false;
    if (neighbor && neighbor.balance !== null && row.balance !== null) {
      const delta = row.balance - neighbor.balance;
      if (Math.abs(delta) === row.amount.minor) chainSign = delta < 0 ? -1 : 1;
      else chainBroken = true;
    }
    let sign = row.amount.sign;
    let confidence = row.header ? 'high' : 'medium';
    if (sign === 0) {
      if (chainSign === 0) {
        result.unreadable += 1;
        continue;
      }
      sign = chainSign;
      confidence = 'medium';
    } else if (chainSign !== 0 && chainSign !== sign) confidence = 'low';
    if (chainBroken) confidence = 'low';
    const description = joinText(row.desc);
    if (description === '' && confidence === 'high') confidence = 'medium';
    const ibans = ibansIn([description, ...row.iban, ...row.name].join(' '));
    const nameHit = NAME_RE.exec(description);
    const name = joinText(row.name) || (nameHit ? nameHit[1].replace(NAME_STOP_RE, '').trim() : '');
    lines.push({
      value_date: row.date,
      amount_minor: sign * row.amount.minor,
      description,
      counterparty_name: name || null,
      counterparty_iban: ibans[0] ?? null,
      bank_reference: joinText(row.ref) || null,
      balance_after_minor: row.balance,
      confidence,
    });
  }
  lines.forEach((l, i) => {
    l.n = i + 1;
  });
  result.lines = lines;
  if (lines.length > 0) {
    const dates = lines.map((l) => l.value_date).sort();
    result.statement = { from: dates[0], to: dates[dates.length - 1] };
  }
  result.accountIban = preambleIbans.size === 1 ? [...preambleIbans][0] : null;
}
