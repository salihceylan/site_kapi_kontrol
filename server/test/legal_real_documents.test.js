// GERÇEK server/legal/*.md belgeleri (hukuk ajanının yazdığı 5 belge) bu yükleyiciyle gerçek biçimde ayrıştırılır, doldurulur ve HTML'e çevrilir.
// Belgeler değişse de test çökmez: beklentiler dosyanın KENDİ içeriğinden (front-matter "complete:", gövdedeki açık iş işaretleri) türetilir.
import { describe, it, before, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  DEFAULT_LEGAL_DIR,
  LEGAL_OPTIONAL_PLACEHOLDERS,
  LEGAL_PLACEHOLDERS,
  UNFILLED,
  clearLegalCache,
  fillPlaceholders,
  loadLegalFiles,
  parseFrontMatter,
  renderLegalPage,
  renderMarkdown,
  resolveDocuments,
} from '../src/modules/legal_documents.js';

const FULL = {
  company_name: 'Örnek Teknoloji A.Ş.',
  company_address: 'Atatürk Cad. No:1 Çankaya / Ankara',
  mersis_no: '0123456789012345',
  kep_address: 'ornek@hs01.kep.tr',
  contact_email: 'info@example.com',
  contact_phone: '+90 312 000 00 00',
};
const EXPECTED_IDS = ['account_deletion', 'dpa', 'kvkk_notice', 'privacy', 'terms'];
const EXPECTED_REQUIRED_FOR = {
  account_deletion: [],
  dpa: ['site_application'],
  kvkk_notice: ['register'],
  privacy: ['register'],
  terms: ['register'],
};
const MARKER = /\[(?:KARAR\/BİLGİ GEREKLİ|AVUKAT DOĞRULASIN)/u;
// Karar H1 (2026-10-21): Cenk'in verdiği unvan, adres ve telefon; KEP ve MERSİS BOŞ. Belgeler iletişim e-postası da istediği için örnek bir
// e-posta eklenir (yalnız KEP / MERSİS boşluğunun etkisini ayırmak için).
const H1_SETTINGS = {
  company_name: 'GÜDE TEKNOLOJİ LTD. ŞTİ.',
  company_address: 'Yalı Mah. 6436 Sok. No:37/A Karşıyaka / İzmir',
  contact_phone: '0543 795 60 44',
  contact_email: 'kvkk@example.com',
  mersis_no: '',
  kep_address: '',
};
// Değeri silinmiş ama etiketi kalmış satır: "MERSİS ;", "KEP.", "- **MERSİS no:** " gibi.
const DANGLING_LABEL = /(?:MERSİS|KEP)(?:\s+(?:no|numarası|adresi))?[\s:*]*(?:$|[;.,])/mu;
const usesPlaceholder = (body, key) => new RegExp(`\\{\\{\\s*${key}\\s*\\}\\}`, 'i').test(body);
const ALLOWED_TAG = /<\/?(?:h[1-6]|p|ul|ol|li|strong|hr)(?: class="(?:sub|meta|notice)")?>|<a href="https:\/\/[^"<>]*" rel="noopener noreferrer nofollow" target="_blank">|<\/a>/g;

let files; // [{ name, text, meta, body }]
let raw;

before(async () => {
  clearLegalCache();
  files = fs
    .readdirSync(DEFAULT_LEGAL_DIR)
    .filter((name) => name.endsWith('.md'))
    .sort()
    .map((name) => {
      const text = fs.readFileSync(path.join(DEFAULT_LEGAL_DIR, name), 'utf8');
      return { name, text, ...parseFrontMatter(text) };
    });
  raw = await loadLegalFiles(DEFAULT_LEGAL_DIR);
});

afterEach(() => {
  clearLegalCache();
});

describe('gerçek server/legal belgeleri', () => {
  it('5 belgenin tamamı yüklenir (kvkk_notice, privacy, terms, dpa, account_deletion); front-matter sözleşmeye uygun', () => {
    assert.deepEqual(raw.map((d) => d.id).sort(), EXPECTED_IDS);
    for (const doc of raw) {
      assert.deepEqual(doc.required_for, EXPECTED_REQUIRED_FOR[doc.id], doc.id);
      assert.match(doc.version, /^\d{4}-\d{2}-\d{2}$/, `${doc.id} sürüm`);
      assert.match(doc.effective_date, /^\d{4}-\d{2}-\d{2}$/, `${doc.id} yürürlük tarihi`);
      assert.ok(doc.title.length > 3 && doc.body.trim().length > 500, doc.id);
    }
  });

  it('dosyadaki "complete: false" (satır sonu yorumuyla birlikte) forceIncomplete olarak okunur', () => {
    for (const file of files) {
      const declared = /^complete:\s*false\b/m.test(file.text.split('\n---')[0]);
      const doc = raw.find((d) => d.id === file.meta.id);
      assert.equal(doc.forceIncomplete, declared, file.name);
      assert.equal(file.meta.complete === undefined ? false : String(file.meta.complete).toLowerCase() === 'false', declared, `${file.name}: yorum metni değeri bozmamalı`);
    }
  });

  it('gövdede yalnız bilinen yer tutucular; köşeli bağlantı varsa yalnız https; tablo satırı yok', () => {
    for (const file of files) {
      for (const match of file.body.matchAll(/\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/g)) {
        assert.ok(LEGAL_PLACEHOLDERS.includes(match[1].toLowerCase()), `${file.name}: bilinmeyen yer tutucu ${match[0]}`);
      }
      for (const match of file.body.matchAll(/\]\(([^)]*)\)/g)) {
        assert.ok(match[1].startsWith('https://'), `${file.name}: https dışı bağlantı ${match[0]}`);
      }
      assert.equal(/^\s*\|/m.test(file.body), false, `${file.name}: tablo yok kuralı`);
    }
  });

  it('açık iş işaretleri ("[KARAR/BİLGİ GEREKLİ" / "[AVUKAT DOĞRULASIN") belgeyi, front-matter\'dan BAĞIMSIZ olarak, complete:false yapar', () => {
    for (const file of files) {
      const hasMarker = MARKER.test(file.body.normalize('NFC'));
      const filled = fillPlaceholders(file.body, FULL);
      assert.equal(filled.complete, !hasMarker, `${file.name}: tüm yer tutucular dolu iken complete yalnız işaret yokluğuna bağlı`);
      assert.ok(!filled.text.includes('{{'), file.name);
      assert.ok(!filled.text.includes(UNFILLED) || /\[……\]/.test(file.body), `${file.name}: "[……]" yalnız dosyada zaten varsa kalır`);
    }
  });

  it('TAM ayarla: complete, dosyanın kendi "complete: false" ve işaretlerine göre; AYARSIZ: yer tutucusu olan her belge "[……]" içerir ve tamamlanmamıştır', () => {
    const full = resolveDocuments(raw, FULL);
    const empty = resolveDocuments(raw, {});
    for (const doc of raw) {
      const hasMarker = MARKER.test(doc.body.normalize('NFC'));
      assert.equal(full.find((d) => d.id === doc.id).complete, !hasMarker && !doc.forceIncomplete, `${doc.id} (tam ayar)`);
      const usesPlaceholder = /\{\{\s*[a-z_]+\s*\}\}/i.test(doc.body);
      const unfilled = empty.find((d) => d.id === doc.id);
      if (usesPlaceholder) {
        assert.equal(unfilled.complete, false, `${doc.id} (ayarsız)`);
        assert.ok(unfilled.content_md.includes(UNFILLED), doc.id);
      }
    }
    assert.equal(full.filter((d) => EXPECTED_IDS.includes(d.id)).length, 5, 'yedek account_deletion eklenmez: gerçek dosya var');
  });

  it('API şekli: gerçek içerikle liste ve ayrıntı alanları; içerik kaçışsız Markdown olarak döner', () => {
    const docs = resolveDocuments(raw, FULL);
    const privacy = docs.find((d) => d.id === 'privacy');
    assert.deepEqual(Object.keys(privacy), ['id', 'title', 'version', 'effective_date', 'required_for', 'complete', 'content_md']);
    assert.ok(privacy.content_md.includes('Örnek Teknoloji A.Ş.'), 'şirket adı yer tutucudan doldu');
    assert.ok(/^# Gizlilik Politikası/m.test(privacy.content_md));
  });

  it('karar H1: KEP ve MERSİS boşken hiçbir belgede "[……]" ya da değeri boş kalmış "MERSİS" / "KEP" etiketi yok; tamlık TAM ayarla aynı', () => {
    const h1 = resolveDocuments(raw, H1_SETTINGS);
    const full = resolveDocuments(raw, FULL);
    for (const doc of h1) {
      const source = raw.find((d) => d.id === doc.id)?.body ?? '';
      assert.ok(!doc.content_md.includes(UNFILLED), `${doc.id}: "[……]" kaldı`);
      const dangling = doc.content_md.split('\n').find((line) => DANGLING_LABEL.test(line));
      assert.equal(dangling, undefined, `${doc.id}: boş etiket kaldı: ${dangling?.slice(0, 160)}`);
      assert.equal(doc.complete, full.find((d) => d.id === doc.id).complete, `${doc.id}: boş KEP / MERSİS tamlığı değiştirmemeli`);
      for (const key of ['company_name', 'company_address', 'contact_phone']) {
        if (usesPlaceholder(source, key)) {
          assert.ok(doc.content_md.includes(H1_SETTINGS[key]), `${doc.id}: ${key} metne yazılmalı`);
        }
      }
    }
  });

  it('TAM ayarla KEP ve MERSİS değerleri, şablonda geçtikleri her belgede metne yazılır', () => {
    for (const doc of resolveDocuments(raw, FULL)) {
      const source = raw.find((d) => d.id === doc.id)?.body ?? '';
      for (const key of LEGAL_OPTIONAL_PLACEHOLDERS) {
        if (usesPlaceholder(source, key)) {
          assert.ok(doc.content_md.includes(FULL[key]), `${doc.id}: ${key}`);
        }
      }
    }
  });

  it('şablonlarda isteğe bağlı yer tutucu yalnız KENDİ koşullu bölümünün içinde geçer (bölüm dışında boşken "[……]" üretirdi)', () => {
    for (const file of files) {
      for (const line of file.body.split('\n')) {
        for (const key of LEGAL_OPTIONAL_PLACEHOLDERS) {
          const outside = line.replace(new RegExp(`\\{\\{#\\s*${key}\\s*\\}\\}.*?\\{\\{/\\s*${key}\\s*\\}\\}`, 'gi'), '');
          assert.ok(!usesPlaceholder(outside, key), `${file.name}: bölüm dışında {{${key}}}: ${line.slice(0, 140)}`);
        }
      }
    }
  });

  it('her belge sayfaya dönüşür: yalnız izinli etiketler, tek h1, betik yok, bağlantılar yalnız https; tamamlanmamışsa uyarı', () => {
    for (const doc of resolveDocuments(raw, FULL)) {
      const html = renderLegalPage(doc);
      const main = html.slice(html.indexOf('<main>'), html.indexOf('</main>') + 7).replace('<main>', '').replace('</main>', '');
      assert.ok(!/[<>]/.test(main.replace(ALLOWED_TAG, '')), `${doc.id}: ham HTML kaldı`);
      assert.equal(html.match(/<h1>/g).length, 1, doc.id);
      assert.ok(!/<script/i.test(html), doc.id);
      assert.equal(html.includes('class="notice"'), doc.complete === false, doc.id);
      for (const anchor of html.match(/<a [^>]*>/g) ?? []) assert.match(anchor, /href="https:\/\//, doc.id);
      const body = renderMarkdown(doc.content_md, { headingOffset: 1 });
      assert.ok(body.length > 400, doc.id);
    }
  });
});
