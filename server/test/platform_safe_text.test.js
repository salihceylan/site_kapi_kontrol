// Güvenli metin normalizasyonu (utils/safe_text.js) ve normalizeSetupSiteInput'un İDEMPOTENT / 500 üretmez hâli (DB'siz).
// Neden: NUL (PostgreSQL 22021), eşsiz vekil karakter (JSONB 22P05) ve yön / görünmez karakterler (ör. sağdan sola geçersiz kılma) bireysel
// kullanıcıdan süper kullanıcıya uzanan güven sınırını geçmemeli ve 500 üretmemeli; kaydedilen değer onayda yeniden normalleştirilince
// DEĞİŞMEMELİ (aksi halde 422 APPLICATION_DATA_INVALID).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeSetupSiteInput } from '../src/services/membership_rules.js';
import { cleanText, clipChars, isDroppedCodePoint, isLoneSurrogate } from '../src/utils/safe_text.js';
import { revalidateStoredStructure } from '../src/modules/site_application_common.js';

const chr = (...codes) => String.fromCodePoint(...codes);
const NUL = chr(0);
const LONE_HIGH = String.fromCharCode(0xd800);
const LONE_LOW = String.fromCharCode(0xdc00);
const RLO = chr(0x202e);
const ZWSP = chr(0x200b);

describe('cleanText', () => {
  it('NUL, eşsiz vekil (yüksek / alçak), diğer kontrol karakterleri ve DEL atılır', () => {
    assert.equal(cleanText(`a${NUL}b${LONE_HIGH}c${LONE_LOW}d${chr(7)}e${chr(127)}f${chr(0x85)}g`), 'abcdefg');
  });

  it('yön / görünmez karakterler atılır (RLO, LRM / RLM, ZWSP, ZWJ / ZWNJ, kelime birleştirici, BOM, satır ayırıcı, yumuşak tire, ALM)', () => {
    const dirty = `A${RLO}B${chr(0x200e)}C${chr(0x200f)}D${ZWSP}E${chr(0x200d)}F${chr(0x200c)}G${chr(0x2060)}H${chr(0xfeff)}I${chr(0x2028)}J${chr(0xad)}K${chr(0x61c)}L${chr(0x2066)}M`;
    assert.equal(cleanText(dirty), 'ABCDEFGHIJKLM');
  });

  it('atanmamış karakterler (noncharacter) ve etiket karakterleri atılır; astral karakterler (emoji) korunur', () => {
    assert.equal(cleanText(`x${chr(0xfffe)}${chr(0xffff)}${chr(0x1fffe)}${chr(0xfdd0)}${chr(0xe0041)}y`), 'xy');
    assert.equal(cleanText(`Site ${chr(0x1f3e0)} A`), `Site ${chr(0x1f3e0)} A`);
  });

  it('tek satır modu: sekme / LF / CR / CRLF TEK boşluk olur; çok satırlı mod: satır sonu LF olarak korunur (CRLF ve CR -> LF)', () => {
    assert.equal(cleanText('a\tb\nc\rd\r\ne'), 'a b c d e');
    assert.equal(cleanText('a\tb\nc\rd\r\ne', { multiline: true }), 'a b\nc\nd\ne');
  });

  it('İDEMPOTENT: ikinci çağrı sonucu değiştirmez (rastgele karışık girdiler)', () => {
    const pool = [NUL, LONE_HIGH, LONE_LOW, RLO, ZWSP, '\t', '\n', '\r', ' ', 'a', 'Ş', chr(0x1f3e0), chr(0xfffe), chr(0x200d), 'x'];
    let seed = 12345;
    const next = () => {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed;
    };
    for (let round = 0; round < 300; round += 1) {
      let text = '';
      const length = next() % 24;
      for (let i = 0; i < length; i += 1) text += pool[next() % pool.length];
      for (const options of [{}, { multiline: true }]) {
        const once = cleanText(text, options);
        assert.equal(cleanText(once, options), once, JSON.stringify(text));
        assert.equal(Array.from(once).some((ch) => isDroppedCodePoint(ch.codePointAt(0)) && ch !== '\n'), false);
      }
    }
  });

  it('isLoneSurrogate / yardımcılar', () => {
    assert.equal(isLoneSurrogate(0xd800), true);
    assert.equal(isLoneSurrogate(0xdfff), true);
    assert.equal(isLoneSurrogate(0xd7ff), false);
    assert.equal(isLoneSurrogate(0xe000), false);
    assert.equal(isDroppedCodePoint(0x200d, { keepJoiners: true }), false);
    assert.equal(isDroppedCodePoint(0x200d), true);
    assert.equal(isDroppedCodePoint(10, { allowControls: [10] }), false);
  });
});

describe('clipChars: önce sınırla SONRA kırp', () => {
  it('sınırda kalan boşluk saklanmaz; vekil çiftleri (emoji) ortadan BÖLÜNMEZ', () => {
    assert.equal(clipChars('abc def', 4), 'abc');
    assert.equal(clipChars('  ab  ', 10), 'ab');
    const emoji = chr(0x1f3e0);
    const clipped = clipChars(emoji.repeat(5), 3);
    assert.equal(Array.from(clipped).length, 3);
    assert.equal(Array.from(clipped).some((ch) => isLoneSurrogate(ch.codePointAt(0))), false);
  });
});

describe('normalizeSetupSiteInput: güvenli ve idempotent', () => {
  it('ad / blok / kapı / şehir / ilçe / adresten tehlikeli karakterler atılır; 500 üretecek değer kalmaz', () => {
    const out = normalizeSetupSiteInput({
      name: ` Gül${NUL} Sitesi${RLO} `,
      city: `Ankara${LONE_HIGH}`,
      district: `${RLO}${ZWSP}`,
      address: `Cadde${NUL} 1\r\nKat 2`,
      blocks: [{ name: `A${LONE_LOW} Blok${NUL}`, apartmentCount: 5 }],
      doors: [{ name: `Ana${RLO} Kapı` }],
    });
    assert.equal(out.siteName, 'Gül Sitesi');
    assert.equal(out.city, 'Ankara');
    assert.equal(out.district, null, 'yalnız görünmez karakterden oluşan ilçe boş sayılır');
    assert.equal(out.address, 'Cadde 1\nKat 2');
    assert.equal(out.blocks[0].name, 'A Blok');
    assert.equal(out.doors[0].name, 'Ana Kapı');
    const flat = JSON.stringify(out);
    assert.equal(flat.includes('\\' + 'ud800') || flat.includes('\\' + 'udc00') || flat.includes('\\' + 'u0000'), false);
  });

  it('sonuç boşsa site adı için 400 (Site adı zorunludur); blok adı varsayılana, kapı adı "Kapı n"e düşer', () => {
    for (const name of [NUL, RLO, `${LONE_HIGH}${NUL}${RLO}`, '   ', `${ZWSP} ${ZWSP}`]) {
      assert.throws(() => normalizeSetupSiteInput({ name }), (error) => error.statusCode === 400 && /Site adı zorunludur/.test(error.message));
    }
    const out = normalizeSetupSiteInput({ name: 'S', blocks: [{ name: RLO, apartmentCount: 3 }], doors: [{ name: NUL }] });
    assert.equal(out.blocks[0].name, 'Blok 1');
    assert.equal(out.doors[0].name, 'Kapı 1');
  });

  it('İDEMPOTENT: 60. karakterde kesilip sonda boşluk kalan blok / kapı adı kırpılır; normalleştirilmiş çıktı yeniden normalleştirilince AYNI kalır', () => {
    // eski hata: önce trim sonra slice(0, 60) -> 60. karakter boşluksa sonda boşluk kalır, onayda yeniden normalleştirme ad uyuşmazlığı verirdi
    const longName = `${'x'.repeat(59)} yyyy`;
    const out = normalizeSetupSiteInput({ name: 'S', blocks: [{ name: longName, apartmentCount: 2 }], doors: [{ name: longName }], city: `${'c'.repeat(199)} d`, address: `${'a'.repeat(299)} b` });
    assert.equal(out.blocks[0].name, 'x'.repeat(59));
    assert.equal(out.doors[0].name, 'x'.repeat(59));
    assert.equal(out.city, 'c'.repeat(199));
    assert.equal(out.address, 'a'.repeat(299));
    const again = normalizeSetupSiteInput({
      name: out.siteName,
      city: out.city,
      district: out.district,
      address: out.address,
      blocks: out.blocks.map((b) => ({ name: b.name, apartmentCount: b.apartmentCount })),
      doors: out.doors.map((d) => ({ name: d.name })),
    });
    assert.deepEqual(again, out);
  });

  it('rastgele karışık girdilerde çıktı yeniden normalleştirilince DEĞİŞMEZ (idempotent) ve onayda 422 üretmez', () => {
    const parts = [NUL, LONE_HIGH, RLO, ZWSP, ' ', '\t', '\n', 'a', 'B', 'Ş', 'ğ', chr(0x1f3e0), 'x', '-', '.'];
    let seed = 987654321;
    const next = () => {
      seed = (seed * 1664525 + 1013904223) % 4294967296;
      return seed;
    };
    const random = (maxLength) => {
      let text = '';
      const length = 1 + (next() % maxLength);
      for (let i = 0; i < length; i += 1) text += parts[next() % parts.length];
      return text;
    };
    let checked = 0;
    for (let round = 0; round < 400; round += 1) {
      let out;
      try {
        out = normalizeSetupSiteInput({
          name: `s${random(130)}`,
          city: random(210),
          district: random(210),
          address: random(310),
          blocks: [{ name: random(70), apartmentCount: 1 + (next() % 5) }, { name: random(70), apartmentCount: 1 + (next() % 5) }],
          doors: [{ name: random(70) }, { name: random(70) }],
        });
      } catch (error) {
        assert.equal(error.statusCode, 400, 'tek meşru hata: 400 doğrulama');
        continue;
      }
      checked += 1;
      const again = normalizeSetupSiteInput({
        name: out.siteName,
        city: out.city,
        district: out.district,
        address: out.address,
        blocks: out.blocks.map((b) => ({ name: b.name, apartmentCount: b.apartmentCount })),
        doors: out.doors.map((d) => ({ name: d.name })),
      });
      assert.deepEqual(again, out, 'idempotent');
      // saklanan biçim (başvuru satırı) onayda yeniden doğrulanır: ad uyuşmazlığı / 422 olmamalı
      const row = {
        site_name: out.siteName,
        city: out.city,
        district: out.district,
        address: out.address,
        management_type: 'apartment_site',
        blocks: JSON.parse(JSON.stringify(out.blocks)),
        doors: JSON.parse(JSON.stringify(out.doors)),
        block_count: out.totalBlockCount,
        apartment_count: out.totalApartmentCount,
        door_count: out.totalDoorCount,
      };
      assert.deepEqual(revalidateStoredStructure(row).input, out);
      const jsonText = JSON.stringify(out.blocks) + JSON.stringify(out.doors);
      assert.equal(jsonText.includes('\\' + 'ud8') || jsonText.includes('\\' + 'udc') || jsonText.includes('\\' + 'u0000'), false);
    }
    assert.ok(checked > 200, `yeterli geçerli örnek: ${checked}`);
  });

  it('mevcut davranışlar korunur: normal ad / şehir aynen, üst sınırlar ve yinelenen blok adı 400', () => {
    const out = normalizeSetupSiteInput({ name: ' Yeşilvadi Sitesi ', city: ' İstanbul ', blocks: [{ name: 'A Blok', apartmentCount: 12 }] });
    assert.equal(out.siteName, 'Yeşilvadi Sitesi');
    assert.equal(out.city, 'İstanbul');
    assert.throws(() => normalizeSetupSiteInput({ name: 'x'.repeat(121) }), (e) => e.statusCode === 400);
    assert.throws(() => normalizeSetupSiteInput({ name: 'S', blocks: [{ name: 'A', apartmentCount: 1 }, { name: 'a', apartmentCount: 1 }] }), (e) => e.statusCode === 400);
  });
});

describe('serbest metin (not / gerekçe), cihaz kodu ve arama: eşsiz vekil / NUL / C1 atılır', () => {
  it('normalizeFreeText / normalizeDeviceUid / parseSearch', async () => {
    const { normalizeDeviceUid, normalizeFreeText, parseSearch } = await import('../src/modules/site_application_common.js');
    assert.equal(normalizeFreeText(`Not${NUL}${LONE_HIGH}${chr(0x85)}${RLO} ok`, 'Not', 500), 'Not ok');
    assert.equal(normalizeFreeText(`${LONE_LOW}${NUL}`, 'Not', 500), null);
    const family = `${chr(0x1f468)}${chr(0x200d)}${chr(0x1f469)}`;
    assert.equal(normalizeFreeText(family, 'Not', 500), family, 'emoji bağlayıcısı (ZWJ) serbest metinde korunur');
    assert.equal(normalizeDeviceUid(` ab${NUL}${LONE_HIGH}cd `), 'ABCD');
    assert.equal(parseSearch(`ay${NUL}se${LONE_HIGH}${RLO}`), 'ayse');
    assert.equal(parseSearch(`${NUL}${RLO}`), null);
  });
});
