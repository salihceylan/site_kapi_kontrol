// Yasal belge yükleyici (DB'siz): front-matter ayrıştırıcı, doğrulama, mtime önbelleği, yer tutucu doldurma / complete, yedek belge,
// Markdown -> HTML dönüşümü (kaçış / XSS / yalnız https / tablo yok) ve sayfa. Sabit belgeler: test/fixtures/legal/.
import { describe, it, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  DEFAULT_LEGAL_DIR,
  LEGAL_PAGE_CSP,
  UNFILLED,
  clearLegalCache,
  fillPlaceholders,
  legalDir,
  loadLegalFiles,
  markdownSafeValue,
  parseFrontMatter,
  parseLegalFile,
  renderInline,
  renderLegalPage,
  renderMarkdown,
  resolveDocuments,
  summarizeDocument,
} from '../src/modules/legal_documents.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES = path.join(here, 'fixtures', 'legal');
const BOM = String.fromCharCode(0xfeff);

const FULL_SETTINGS = {
  company_name: 'Örnek Teknoloji A.Ş.',
  company_address: 'Atatürk Cad. No:1 Çankaya / Ankara',
  mersis_no: '0123456789012345',
  kep_address: 'ornek@hs01.kep.tr',
  contact_email: 'info@example.com',
  contact_phone: '+90 312 000 00 00',
};

afterEach(() => {
  mock.restoreAll();
  clearLegalCache();
});

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'legal-test-'));
  return {
    dir,
    write: (name, text) => fs.writeFileSync(path.join(dir, name), text, 'utf8'),
    cleanup: () => fs.rmSync(dir, { recursive: true, force: true }),
  };
}

const validFile = (extra = '') => `---\nid: terms\ntitle: Koşullar\nversion: v1\nrequired_for: [register]\n${extra}---\n# Koşullar\n\nMetin.\n`;

// İzinli etiketler kaldırıldıktan sonra HİÇ ham < veya > kalmamalı (tüm metin kaçışlı).
const ALLOWED_TAG = /<\/?(?:h[1-6]|p|ul|ol|li|strong|hr)(?: class="sub")?>|<a href="https:\/\/[^"<>]*" rel="noopener noreferrer nofollow" target="_blank">|<\/a>/g;
function assertOnlyAllowedMarkup(html) {
  const rest = html.replace(ALLOWED_TAG, '');
  assert.ok(!/[<>]/.test(rest), `ham HTML kaldı: ${rest.match(/.{0,30}[<>].{0,30}/)?.[0]}`);
}

describe('front-matter ayrıştırıcı', () => {
  it('sözleşmedeki başlık: satır sonu yorumları, satır içi liste, tarih dizge kalır', () => {
    const parsed = parseFrontMatter(
      '---\nid: privacy            # terms | privacy | kvkk_notice\ntitle: Gizlilik Politikası\nversion: 2026-10-16\neffective_date: 2026-10-16\nrequired_for: [register, site_application]   # yorum\n---\n# Gövde\n',
    );
    assert.deepEqual(parsed.meta, {
      id: 'privacy',
      title: 'Gizlilik Politikası',
      version: '2026-10-16',
      effective_date: '2026-10-16',
      required_for: ['register', 'site_application'],
    });
    assert.equal(parsed.body, '# Gövde\n');
  });

  it('boş liste, tırnaklı değer ("#" tırnak içinde yorum değil), blok liste, CRLF ve BOM', () => {
    const text = `${BOM}---\r\nid: dpa\r\ntitle: "A # B"\r\nversion: '1'\r\nrequired_for: []\r\nother:\r\n  - x\r\n  - "y z"\r\n---\r\nGövde\r\n`;
    const parsed = parseFrontMatter(text);
    assert.equal(parsed.meta.title, 'A # B');
    assert.equal(parsed.meta.version, '1');
    assert.deepEqual(parsed.meta.required_for, []);
    assert.deepEqual(parsed.meta.other, ['x', 'y z']);
    assert.equal(parsed.body, 'Gövde\n');
  });

  it('front-matter yoksa ya da kapanmamışsa null; "__proto__" anahtarı prototipi kirletmez', () => {
    assert.equal(parseFrontMatter('Merhaba'), null);
    assert.equal(parseFrontMatter('---\nid: a\ntitle: b\n'), null);
    assert.equal(parseFrontMatter(''), null);
    const parsed = parseFrontMatter('---\n__proto__: x\nid: aa\n---\n');
    assert.equal({}.x, undefined);
    assert.equal(parsed.meta.id, 'aa');
  });
});

describe('belge dosyası doğrulaması', () => {
  it('geçerli dosya: id küçük harf, required_for yalnız bilinen değerler, geçersiz tarih null', () => {
    const { doc } = parseLegalFile('a.md', '---\nid: Terms\ntitle: Koşullar\nversion: v1\neffective_date: dün\nrequired_for: [register, bilinmeyen, site_application]\n---\nx');
    assert.equal(doc.id, 'terms');
    assert.equal(doc.effective_date, null);
    assert.deepEqual(doc.required_for, ['register', 'site_application']);
    assert.equal(doc.forceIncomplete, false);
  });

  it('eksik / geçersiz alanlar hata döndürür (belge yüklenmez)', () => {
    for (const bad of [
      '---\ntitle: T\nversion: v1\n---\n',
      '---\nid: 1abc\ntitle: T\nversion: v1\n---\n',
      '---\nid: ok\nversion: v1\n---\n',
      '---\nid: ok\ntitle: T\n---\n',
      '---\nid: ok\ntitle: T\nversion: "a b"\n---\n',
      '---\nid: ok\ntitle: T\nversion: 12345678901234567890123456789012345678901\n---\n',
    ]) {
      assert.ok(parseLegalFile('x.md', bad).error, bad);
    }
    assert.ok(parseLegalFile('x.md', 'front-matter yok').error);
  });

  it('"complete: false" belgeyi zorla tamamlanmamış yapar', () => {
    const { doc } = parseLegalFile('a.md', validFile('complete: false\n'));
    assert.equal(doc.forceIncomplete, true);
  });
});

describe('dizin ve yükleme', () => {
  it('LEGAL_DIR ortam değişkeni dizini geçersiz kılar; yoksa server/legal', () => {
    assert.equal(legalDir({}), DEFAULT_LEGAL_DIR);
    assert.equal(legalDir({ LEGAL_DIR: '  ' }), DEFAULT_LEGAL_DIR);
    assert.equal(legalDir({ LEGAL_DIR: FIXTURES }), path.resolve(FIXTURES));
    assert.ok(DEFAULT_LEGAL_DIR.endsWith(path.join('server', 'legal')));
  });

  it('sabit belgeler yüklenir; front-matter\'sız dosya atlanır (hata günlüğü), sıra dosya adına göre', async () => {
    const errors = mock.method(console, 'error', () => {});
    const docs = await loadLegalFiles(FIXTURES);
    assert.deepEqual(docs.map((d) => d.id), ['dpa', 'draft_notice', 'evil', 'kvkk_notice', 'privacy', 'terms']);
    assert.ok(errors.mock.calls.some((c) => /broken\.md/.test(String(c.arguments[0]))));
    const kvkk = docs.find((d) => d.id === 'kvkk_notice');
    assert.deepEqual(kvkk.required_for, ['register']);
    assert.equal(kvkk.version, '2026-10-16');
  });

  it('dizin yoksa boş liste (hata fırlatmaz, günlük şişmez)', async () => {
    const errors = mock.method(console, 'error', () => {});
    assert.deepEqual(await loadLegalFiles(path.join(FIXTURES, 'yok-boyle-dizin')), []);
    assert.equal(errors.mock.calls.length, 0);
  });

  it('mtime önbelleği: değişmeyen dosya yeniden ayrıştırılmaz (aynı nesne); değişen dosya yeniden okunur; silinen kaybolur', async () => {
    const t = tempDir();
    try {
      t.write('terms.md', validFile());
      const first = await loadLegalFiles(t.dir);
      const second = await loadLegalFiles(t.dir);
      assert.equal(second[0], first[0], 'aynı mtime+boyut -> önbellekten');

      t.write('terms.md', validFile().replace('version: v1', 'version: v2'));
      const bump = new Date(Date.now() + 5000);
      fs.utimesSync(path.join(t.dir, 'terms.md'), bump, bump);
      const third = await loadLegalFiles(t.dir);
      assert.equal(third[0].version, 'v2');
      assert.notEqual(third[0], first[0]);

      fs.rmSync(path.join(t.dir, 'terms.md'));
      assert.deepEqual(await loadLegalFiles(t.dir), []);
    } finally {
      t.cleanup();
    }
  });

  it('aynı id\'li ikinci dosya yok sayılır; çok büyük dosya atlanır', async () => {
    mock.method(console, 'error', () => {});
    const t = tempDir();
    try {
      t.write('a.md', validFile());
      t.write('b.md', validFile().replace('Koşullar\nversion', 'Başka\nversion'));
      t.write('c.md', `${validFile().replace('id: terms', 'id: huge')}${'x'.repeat(600 * 1024)}`);
      const docs = await loadLegalFiles(t.dir);
      assert.deepEqual(docs.map((d) => d.id), ['terms']);
      assert.equal(docs[0].title, 'Koşullar');
    } finally {
      t.cleanup();
    }
  });
});

describe('yer tutucu doldurma ve complete', () => {
  it('tüm yer tutucular doluysa complete:true ve metinde "[……]" yok', async () => {
    const docs = resolveDocuments(await loadLegalFiles(FIXTURES), FULL_SETTINGS);
    const privacy = docs.find((d) => d.id === 'privacy');
    assert.equal(privacy.complete, true);
    assert.ok(privacy.content_md.includes('Veri sorumlusu **Örnek Teknoloji A.Ş.** şirketidir. Adres: Atatürk Cad. No:1 Çankaya / Ankara. MERSİS: 0123456789012345.'));
    assert.ok(privacy.content_md.includes('- KEP: ornek@hs01.kep.tr'));
    assert.ok(!privacy.content_md.includes('{{'));
    assert.ok(!privacy.content_md.includes(UNFILLED));
  });

  it('dolmamış yer tutucu "[……]" olarak kalır ve belge complete:false olur; yer tutucusuz belge etkilenmez', async () => {
    const docs = resolveDocuments(await loadLegalFiles(FIXTURES), { company_name: 'Örnek A.Ş.' });
    const privacy = docs.find((d) => d.id === 'privacy');
    assert.equal(privacy.complete, false);
    assert.ok(privacy.content_md.includes(`Adres: ${UNFILLED}. MERSİS: ${UNFILLED}.`));
    assert.ok(privacy.content_md.includes('**Örnek A.Ş.**'));
    assert.equal(docs.find((d) => d.id === 'kvkk_notice').complete, true);
    assert.equal(docs.find((d) => d.id === 'dpa').complete, true);
    const terms = docs.find((d) => d.id === 'terms');
    assert.equal(terms.complete, false, 'terms contact_email yer tutucusu boş');
    assert.equal(resolveDocuments(await loadLegalFiles(FIXTURES), { company_name: 'A', contact_email: 'a@example.com' }).find((d) => d.id === 'terms').complete, true);
  });

  it('boş / yalnız boşluk değer ve metin dışı değer dolu sayılmaz; bilinmeyen yer tutucu da "[……]" olur', () => {
    for (const value of ['', '   ', null, undefined, 5, true, {}]) {
      const result = fillPlaceholders('A {{company_name}} B', { company_name: value });
      assert.equal(result.text, `A ${UNFILLED} B`, String(value));
      assert.equal(result.complete, false);
    }
    const unknown = fillPlaceholders('X {{secret_key}} Y {{ CONTACT_EMAIL }}', { contact_email: 'a@b.co', secret_key: 'sızmamalı' });
    assert.equal(unknown.text, `X ${UNFILLED} Y a@b.co`);
    assert.equal(unknown.complete, false);
  });

  it('gövdedeki hazır "[……]" (ve "[...]") belgeyi tamamlanmamış yapar; "complete: false" da', async () => {
    assert.equal(fillPlaceholders('Madde [……] bekliyor', {}).complete, false);
    assert.equal(fillPlaceholders('Madde [...] bekliyor', {}).complete, false);
    assert.equal(fillPlaceholders('Madde [kısa] tamam', {}).complete, true);
    const docs = resolveDocuments(await loadLegalFiles(FIXTURES), FULL_SETTINGS);
    const draft = docs.find((d) => d.id === 'draft_notice');
    assert.equal(draft.complete, false);
    const forced = resolveDocuments([parseLegalFile('a.md', validFile('complete: false\n')).doc], {}).find((d) => d.id === 'terms');
    assert.equal(forced.complete, false);
    assert.ok(!forced.content_md.includes(UNFILLED), 'metinde boşluk yok ama taslak işaretli');
  });

  it('hukuk taslağındaki açık iş işaretleri ("[KARAR/BİLGİ GEREKLİ: ...]", "[AVUKAT DOĞRULASIN: ...]") belgeyi complete:false yapar; metin işaretle birlikte korunur', () => {
    const decide = '[KARAR/BİLGİ GEREKLİ: saklama süresi]';
    const verify = '[AVUKAT DOĞRULASIN: kat mülkiyeti saklama süresi]';
    for (const text of [`Süre ${decide} gün.`, `Süre ${verify} gün.`, `a [ KARAR / BİLGİ GEREKLİ: x] b`, `Süre ${decide}`.normalize('NFD'), `Süre ${verify}`.normalize('NFD')]) {
      const result = fillPlaceholders(text, FULL_SETTINGS);
      assert.equal(result.complete, false, text);
      assert.equal(result.text, text, 'metin değiştirilmez');
    }
    // sıradan köşeli ifadeler, küçük harfli benzerleri ve front-matter yorumu işaret SAYILMAZ
    for (const text of ['Madde [kısa] tamam', 'karar/bilgi gerekli değil', '[Karar] verildi', 'KARAR/BİLGİ GEREKLİ ama köşeli parantezsiz']) {
      assert.equal(fillPlaceholders(text, FULL_SETTINGS).complete, true, text);
    }
    const parsed = parseLegalFile('a.md', `---\nid: dpa\ntitle: T\nversion: v1\nrequired_for: [site_application]\ncomplete: false   # köşeli ${decide} ve ${verify} işaretleri çözülünce bu satır silinir\n---\nGövde`);
    assert.equal(parsed.doc.forceIncomplete, true, 'satır sonu yorumu "complete: false" değerini bozmaz');
    assert.equal(parsed.doc.body, 'Gövde', 'front-matter yorumu gövdeye karışmaz');
    const resolved = resolveDocuments([parseLegalFile('b.md', `---\nid: terms\ntitle: T\nversion: v1\nrequired_for: [register]\n---\nİlk ${decide} son {{company_name}}`).doc], FULL_SETTINGS).find((d) => d.id === 'terms');
    assert.equal(resolved.complete, false, 'yer tutucular dolu olsa da işaret varsa tamamlanmamış');
    assert.ok(resolved.content_md.includes(decide) && resolved.content_md.includes('Örnek A.Ş.'.replace('Örnek A.Ş.', FULL_SETTINGS.company_name)));
  });

  it('ayar değeri Markdown / HTML üretemez: [ ] < > ` \\ ** arındırılır, tek satır, tek geçiş (yer tutucu genişlemez)', () => {
    const evil = 'Güde <b>x</b> [bağ](https://evil.example) **kalın** `kod` \\ \n# Başlık\n- madde';
    const safe = markdownSafeValue(evil);
    assert.ok(!/[[\]<>`\\\n]/.test(safe), safe);
    assert.ok(!safe.includes('**'));
    const filled = fillPlaceholders('Şirket: {{company_name}}.', { company_name: evil, contact_email: 'a@b.co' });
    assert.ok(!filled.text.includes('<b>') && !filled.text.includes('](https'));
    assert.equal(filled.text.split('\n').length, 1, 'değer yeni satır ekleyemez');
    const nested = fillPlaceholders('A {{company_name}}', { company_name: '{{contact_email}}', contact_email: 'sizmamali@example.com' });
    assert.ok(!nested.text.includes('sizmamali'), 'eklenen değer yeniden taranmaz');
    assert.equal(markdownSafeValue('# - başlık'), 'başlık');
  });
});

describe('belge çözümleme', () => {
  it('sıra: terms, privacy, kvkk_notice, dpa, account_deletion, sonra kalanlar id sırasıyla', async () => {
    const docs = resolveDocuments(await loadLegalFiles(FIXTURES), FULL_SETTINGS);
    assert.deepEqual(docs.map((d) => d.id), ['terms', 'privacy', 'kvkk_notice', 'dpa', 'account_deletion', 'draft_notice', 'evil']);
  });

  it('account_deletion dosyası yoksa yedek metin eklenir (iletişim e-postası dolunca complete); dosya varsa yedek EKLENMEZ', async () => {
    const empty = resolveDocuments([], {});
    assert.equal(empty.length, 1);
    assert.equal(empty[0].id, 'account_deletion');
    assert.deepEqual(empty[0].required_for, []);
    assert.equal(empty[0].complete, false);
    assert.ok(empty[0].content_md.includes(UNFILLED));
    const filled = resolveDocuments([], { contact_email: 'destek@example.com' });
    assert.equal(filled[0].complete, true);
    assert.ok(filled[0].content_md.includes('destek@example.com'));

    const own = parseLegalFile('d.md', '---\nid: account_deletion\ntitle: Silme\nversion: s1\n---\nÖzel metin').doc;
    const docs = resolveDocuments([own], {});
    assert.equal(docs.length, 1);
    assert.equal(docs[0].title, 'Silme');
  });

  it('summarizeDocument içeriği çıkarır; sözleşmedeki alanlar', async () => {
    const privacy = resolveDocuments(await loadLegalFiles(FIXTURES), FULL_SETTINGS).find((d) => d.id === 'privacy');
    assert.deepEqual(summarizeDocument(privacy), {
      id: 'privacy',
      title: 'Gizlilik Politikası',
      version: '2026-10-16',
      effective_date: '2026-10-16',
      required_for: ['register'],
      complete: true,
    });
  });
});

describe('Markdown -> HTML (izinli alt küme)', () => {
  it('başlık, paragraf, listeler, kalın ve https bağlantı', () => {
    const html = renderMarkdown('# Bir\n\n## İki\n\n### Üç\n\nMetin **kalın** ve [bağ](https://example.com/a?x=1&y=2).\nİkinci satır.\n\n- a\n- b\n\n1. bir\n2. iki\n');
    assert.equal(
      html,
      [
        '<h1>Bir</h1>',
        '<h2>İki</h2>',
        '<h3>Üç</h3>',
        '<p>Metin <strong>kalın</strong> ve <a href="https://example.com/a?x=1&amp;y=2" rel="noopener noreferrer nofollow" target="_blank">bağ</a>. İkinci satır.</p>',
        '<ul><li>a</li><li>b</li></ul>',
        '<ol><li>bir</li><li>iki</li></ol>',
      ].join('\n'),
    );
  });

  it('XSS sabit belgesi: ham HTML yok, javascript: / http: bağlantı yok, tablo düz metin, tırnaklar kaçışlı', async () => {
    const evil = resolveDocuments(await loadLegalFiles(FIXTURES), {}).find((d) => d.id === 'evil');
    const html = renderMarkdown(evil.content_md, { headingOffset: 1 });
    assertOnlyAllowedMarkup(html);
    assert.ok(!/<script/i.test(html) && !/<img/i.test(html) && !/<u>/i.test(html) && !/<b>/i.test(html));
    assert.ok(html.includes('&lt;script&gt;alert(1)&lt;/script&gt;'));
    assert.ok(!/href="javascript:/i.test(html) && !/href="http:/i.test(html));
    assert.ok(!html.includes('<table') && !html.includes('<tr'));
    assert.ok(html.includes('| a | b |'));
    const anchors = html.match(/<a [^>]*>/g) ?? [];
    assert.ok(anchors.length >= 2);
    for (const anchor of anchors) {
      assert.match(anchor, /^<a href="https:\/\/[^"]*" rel="noopener noreferrer nofollow" target="_blank">$/);
    }
    assert.ok(!html.includes('onmouseover="'), 'tırnak kaçışı çalışmalı');
  });

  it('satır içi: bozuk / yarım sözdizimi düz metin kalır; link metni ve bold içeriği kaçışlıdır', () => {
    assert.equal(renderInline('**yarım'), '**yarım');
    assert.equal(renderInline('[a](https://x.example'), '[a](https://x.example');
    assert.equal(renderInline('[<b>](https://x.example/)'), '<a href="https://x.example/" rel="noopener noreferrer nofollow" target="_blank">&lt;b&gt;</a>');
    assert.equal(renderInline('[a](https://user:pw@x.example/)'), '[a](https://user:pw@x.example/)');
    assert.equal(renderInline('[a](HTTPS://x.example/)'), '[a](HTTPS://x.example/)', 'yalnız küçük harf https:// (katı)');
    assert.equal(renderInline('& < > " \''), '&amp; &lt; &gt; &quot; &#39;');
  });

  it('girintili devam satırı önceki maddeye eklenir; ayırıcı çizgi; # yedi seviye paragraf', () => {
    assert.equal(renderMarkdown('- a\n  devam\n- b'), '<ul><li>a devam</li><li>b</li></ul>');
    assert.equal(renderMarkdown('önce\n\n---\n\nsonra'), '<p>önce</p>\n<hr>\n<p>sonra</p>');
    assert.equal(renderMarkdown('#### dört'), '<p>#### dört</p>');
    assert.equal(renderMarkdown(''), '');
  });

  it('rastgele (fuzz) girdi: çıktıda yalnız izinli etiketler, bağlantılar yalnız https', () => {
    const alphabet = ['<', '>', '"', "'", '&', '[', ']', '(', ')', '*', '#', '-', '`', '\\', '\n', ' ', 'a', '1', '. ', 'https://', 'javascript:', 'http://', '|', '{{', '}}', '<script>', '**', '](', '- ', '1. ', '## '];
    let seed = 12345;
    const next = () => {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed;
    };
    for (let round = 0; round < 400; round += 1) {
      let text = '';
      const length = 5 + (next() % 60);
      for (let i = 0; i < length; i += 1) text += alphabet[next() % alphabet.length];
      const html = renderMarkdown(text, { headingOffset: next() % 2 });
      assertOnlyAllowedMarkup(html);
      for (const anchor of html.match(/<a [^>]*>/g) ?? []) {
        assert.match(anchor, /^<a href="https:\/\/[^"<>]*" rel="noopener noreferrer nofollow" target="_blank">$/, text);
      }
    }
  });

  it('büyük girdide doğrusal sürede biter (ReDoS yok)', () => {
    const start = Date.now();
    renderMarkdown(`${'['.repeat(20000)}\n${'**'.repeat(20000)}\n${'- '.repeat(5000)}\n${'a'.repeat(50000)}`);
    assert.ok(Date.now() - start < 1500, `çok yavaş: ${Date.now() - start} ms`);
  });
});

describe('sayfa (GET /legal/:id gövdesi)', () => {
  it('tam HTML belgesi: dil, viewport, kendi stili, başlık h1, sürüm / tarih, betik yok; tamamlanmamış belgede uyarı', async () => {
    const docs = resolveDocuments(await loadLegalFiles(FIXTURES), { company_name: 'Örnek A.Ş.' });
    const page = renderLegalPage(docs.find((d) => d.id === 'privacy'));
    assert.match(page, /^<!DOCTYPE html>\n<html lang="tr">/);
    assert.ok(page.includes('<meta name="viewport"'));
    assert.ok(page.includes('<style>'));
    assert.ok(page.includes('<h1>Gizlilik Politikası</h1>'));
    assert.equal(page.match(/<h1>/g).length, 1, 'gövdedeki aynı başlık tekrarlanmaz');
    assert.ok(page.includes('Sürüm: 2026-10-16 · Yürürlük tarihi: 2026-10-16'));
    assert.ok(page.includes('class="notice"'));
    assert.ok(page.includes('<h2>İletişim</h2>'));
    assert.ok(!/<script/i.test(page));

    const complete = renderLegalPage(resolveDocuments(await loadLegalFiles(FIXTURES), FULL_SETTINGS).find((d) => d.id === 'privacy'));
    assert.ok(!complete.includes('class="notice"'));
  });

  it('başlık ve sürüm kaçışlanır; CSP sıkıdır (betik / form / çerçeve yok)', async () => {
    const page = renderLegalPage(resolveDocuments(await loadLegalFiles(FIXTURES), {}).find((d) => d.id === 'evil'));
    assert.ok(page.includes('<title>Saldırı &lt;script&gt;alert(1)&lt;/script&gt; Denemesi</title>'));
    assert.ok(!page.includes('<script>alert'));
    assert.match(LEGAL_PAGE_CSP, /default-src 'none'/);
    assert.match(LEGAL_PAGE_CSP, /frame-ancestors 'none'/);
    assert.match(LEGAL_PAGE_CSP, /form-action 'none'/);
    assert.ok(!/script-src/.test(LEGAL_PAGE_CSP));
  });
});
