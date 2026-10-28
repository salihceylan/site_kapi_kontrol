// Deneme listeleri (tools/deneme_listesi/platform.json), SAHA_KONTROL_LISTESI.md, arıza klavuzu ve demo senaryosu kodla çelişmemeli
// (karşılaştırma programı Dalga A inceleme düzeltmeleri, 2026-10-28). DB'siz, statik; CRLF ve LF dosyaların ikisini de okur.
//
//  1. m² (AGENTS.md Kural 15): hiçbir liste m² giriş / gösterim beklemez; m² yalnız "kaldırıldı / yoktur" gibi olumsuz bağlamda anılır.
//  2. Kapı komutu dili (P1-15): bireysel panel başarısı "<Kapı adı> için açma komutu gönderildi." der; listeler "Kapı açılıyor..." beklemez.
//  3. Ölçülemeyen birim: deneme adımları / önkoşulları testçiden "dp" ayarlamasını istemez (telefonda dp ayarlanamaz ve ölçülemez).
//  4. Yardım: dört "navigation" yardım konusu "Ana sayfa" düğmesini anlatıyorsa F28.13 ve SAHA 88.49 da anlatır.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (relative) => readFileSync(path.join(root, relative), 'utf8').replace(/\r\n/g, '\n');

const platform = JSON.parse(read('tools/deneme_listesi/platform.json'));
const items = new Map(platform.bolumler.flatMap((section) => section.maddeler.map((item) => [item.id, item])));
const saha = read('SAHA_KONTROL_LISTESI.md');
/** Bir maddenin başlığından sonraki "Nasıl Test Edilir / Beklenen Sonuç" alt satırlarıyla birlikte metni. */
const sahaItem = (id) => {
  const lines = saha.split('\n');
  const start = lines.findIndex((candidate) => candidate.startsWith(`- [ ] **${id}.`) || candidate.startsWith(`- [x] **${id}.`));
  assert.ok(start >= 0, `SAHA ${id} bulunamadı`);
  const block = [lines[start]];
  for (let i = start + 1; i < lines.length && /^\s{2,}\S/.test(lines[i]); i += 1) block.push(lines[i]);
  return block.join('\n');
};

function strings(value, out = []) {
  if (typeof value === 'string') out.push(value);
  else if (Array.isArray(value)) for (const entry of value) strings(entry, out);
  else if (value && typeof value === 'object') for (const entry of Object.values(value)) strings(entry, out);
  return out;
}

const sentences = (text) =>
  text
    .split(/(?<=[.!?;])\s+|\n+/)
    .map((sentence) => sentence.trim())
    .filter(Boolean);

// --- 1. m² -------------------------------------------------------------------------------------------------------------------------------------
const AREA = /m²|metrekare/i;
// m² yalnız bunlardan biriyle birlikte (aynı cümlede) anılabilir: kaldırıldığı / olmadığı söylenir.
const AREA_NEGATION = /maması|memesi|olmadan|kaldırıl|yok\b|yoktur|geçmez|yer almamal|görünmemel|kullanılmıyor|düşür|sistemden|tarihçe|artık|yok sayıl|silin|çıkar(ıl|d)/i;

test('m² (Kural 15): deneme listesi, saha listesi ve demo senaryosu m² giriş / gösterim beklemez', () => {
  const sources = {
    'tools/deneme_listesi/platform.json': strings(platform),
    'SAHA_KONTROL_LISTESI.md': [saha],
    'docs/DEMO_SENARYOSU.md': [read('docs/DEMO_SENARYOSU.md')],
  };
  const offenders = [];
  for (const [file, blocks] of Object.entries(sources)) {
    for (const block of blocks) {
      for (const sentence of sentences(block)) {
        if (AREA.test(sentence) && !AREA_NEGATION.test(sentence)) offenders.push(`${file}: ${sentence.slice(0, 160)}`);
      }
    }
  }
  assert.deepEqual(offenders, [], 'm² yalnız "kaldırıldı / yoktur" gibi olumsuz bağlamda anılabilir (daire kartında, formlarda ve şablonda m² alanı yoktur)');
});

test('m² (Kural 15): Toplu Yükle dairesi için listeler uygulamadaki gerçek metni ve gerçek sütunları söyler', () => {
  // lib/ui/widgets/bulk_kind_step.dart (Daireler kartı açıklaması) ve lib/services/bulk_template.dart (kExcludedTemplateKeys: m² ve arsa payı sütunları şablonda yok).
  const cardText = 'kat, tip, arsa payı ve borç sorumlusu bilgilerini doldurur';
  assert.ok(read('lib/ui/widgets/bulk_kind_step.dart').includes(cardText), 'kart metni kodda değişmiş: listeleri de güncelleyin');
  assert.ok(items.get('F13.03').beklenen.includes(cardText), 'F13.03 kart metni');
  assert.ok(sahaItem('72.3').includes(cardText), 'SAHA 72.3 kart metni');
  const template = read('lib/services/bulk_template.dart');
  for (const key of ['brut_m2', 'net_m2', 'arsa_payi_pay', 'arsa_payi_payda']) assert.ok(template.includes(`'${key}'`), `${key} şablondan gizli sütun olarak kodda durmalı`);
  // F13.04 önkoşulu şablonda bulunmayan sütunları doldurtmaz.
  const precondition = items.get('F13.04').on_kosul;
  assert.ok(precondition.startsWith('Şablonun "Daireler" sayfasında 2-3 dairenin Kat, Tip ve Borç Sorumlusu hücreleri'), precondition);
  assert.equal(/Net m²,\s*Arsa Payı \(Pay\)/.test(precondition), false);
  // Mali kayıt bilgi satırı: listeler sunucudaki gerçek metni anar (server/src/modules/bulk_import_messages.js financeRecordsNotice).
  const notice = 'Borç Sorumlusu / Tip / Arsa Payı değişiklikleri mevcut borçları değiştirmez, yalnız sonraki borçlandırmadan itibaren geçerlidir.';
  assert.ok(read('server/src/modules/bulk_import_messages.js').includes(notice), 'sunucu metni değişmiş: listeleri de güncelleyin');
  assert.ok(items.get('F13.05').beklenen.includes(notice), 'F13.05 mali kayıt metni');
  assert.ok(sahaItem('72.5').includes(notice), 'SAHA 72.5 mali kayıt metni');
});

// --- 2. Kapı komutu dili ---------------------------------------------------------------------------------------------------------------------
test('kapı komutu dili: listeler ve arıza klavuzu "Kapı açılıyor..." bildirimi beklemez (bireysel panel "için açma komutu gönderildi." der)', () => {
  const source = read('lib/ui/views/individual_home_view.dart');
  assert.ok(source.includes(`'"\${door.doorName}" için açma komutu gönderildi.'`), 'bireysel panel bildirimi kodda değişmiş');
  for (const file of [
    'SAHA_KONTROL_LISTESI.md',
    'tools/deneme_listesi/platform.json',
    'tools/klavuz/entries/31-uygulama-arayuz.mjs',
    'docs/ariza-klavuzu/31-uygulama-arayuz.md',
  ]) {
    // Yalnız olumsuz bağlamda ("... yazmamalıdır") anılabilir: bildirim olarak beklenmez.
    const offenders = sentences(read(file)).filter((sentence) => /kapı(sı)? açılıyor\.\.\./i.test(sentence) && !/yazmamal|denmez|beklenmez/i.test(sentence));
    assert.deepEqual(offenders, [], `${file}: "Kapı açılıyor..." beklentisi kalmış`);
  }
  const item = sahaItem('25.4');
  assert.ok(item.includes('için açma komutu gönderildi.'), 'SAHA 25.4 yeni bildirimi beklemeli');
  assert.ok(item.includes('GÖNDERİLDİ'), 'SAHA 25.4 düğme etiketini beklemeli');
});

// --- 3. Ölçülemeyen birim ----------------------------------------------------------------------------------------------------------------------
test('deneme adımları ve önkoşulları testçiden "dp" ayarlamasını istemez (telefonda ölçülemez)', () => {
  const offenders = [];
  for (const item of items.values()) {
    for (const field of ['adimlar', 'on_kosul']) {
      if (/\bdp\b/.test(strings(item[field]).join('\n'))) offenders.push(`${item.id}.${field}`);
    }
  }
  assert.deepEqual(offenders, []);
  for (const id of ['115.1', '115.5']) {
    const text = sahaItem(id);
    assert.equal(/\b\d+\s*dp\b/.test(text), false, `SAHA ${id}: dp eşiği testçiye bırakılmamalı`);
  }
});

test('F28.15 / F28.19: "Sakin Modu" için "hap" değil "düğme" denir; beklenen sonuçtaki her iddia bir adımla sınanır', () => {
  for (const id of ['F28.15', 'F28.19']) {
    const item = items.get(id);
    assert.equal(/\bhap/i.test(strings(item).join('\n')), false, `${id}: "hap" yerine "Sakin Modu düğmesi"`);
  }
  const f15 = items.get('F28.15');
  const steps = f15.adimlar.join('\n');
  assert.match(steps, /Sakin Modu/);
  assert.match(steps, /geri tuşuna basın/);
  assert.match(f15.beklenen, /geri tuşu/);
  assert.match(f15.beklenen, /Sakin Modu/);
  assert.equal(/\bdp\b/.test(f15.on_kosul + f15.beklenen), false);
});

// --- 4. Yardım ↔ liste eşliği ------------------------------------------------------------------------------------------------------------------
test('yardım "navigation" konuları "Ana sayfa" düğmesini anlatıyorsa F28.13 ve SAHA 88.49 da anlatır', () => {
  const help = read('lib/ui/views/help_content.dart');
  const topics = help.split('id: \'navigation\'').slice(1);
  assert.equal(topics.length, 4, 'dört grup (sakin, bireysel, yönetici, süper kullanıcı) için navigation konusu');
  for (const [index, topic] of topics.entries()) {
    const body = topic.split('static const')[0];
    assert.ok(body.includes('“Ana sayfa” düğmesi'), `yardım navigation konusu #${index + 1} Ana sayfa düğmesini anlatmalı`);
  }
  assert.ok(items.get('F28.13').beklenen.includes('“Ana sayfa” düğmesi anlatılır'), 'F28.13');
  assert.equal(items.get('F28.13').yeni, true, 'F28.13 değişti: yeni:true');
  assert.ok(sahaItem('88.49').includes('"Ana sayfa" düğmesi anlatılır'), 'SAHA 88.49');
});

test('İşletme Projesi ayrıntısı: F28.17 ve SAHA 115.3 kaydedilmemiş tutar onayını sınar', () => {
  const f17 = items.get('F28.17');
  assert.match(f17.adimlar.join('\n'), /Düzenlemeye Dön/);
  assert.match(f17.beklenen, /Kaydedilmemiş değişiklikler/);
  const text = sahaItem('115.3');
  assert.match(text, /Kaydedilmemiş değişiklikler/);
  assert.match(text, /Değişiklikleri Sil/);
  // Konum kuralı (derin ekranda sağ üst) belgede gerekçesiyle yazılı.
  const design = read('docs/TASARIM_DILI.md');
  assert.ok(design.includes('Konum bilerek ana kabuktakinden farklıdır'));
  assert.ok(design.includes('`HomeShortcutButton(onPressed: ...)`'));
});
