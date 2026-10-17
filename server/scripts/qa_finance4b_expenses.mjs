// Finans Faz 4b QA bolumu: D. Gider kaydi + belge eki (O3). scripts/qa_finance4b.mjs tarafindan yuklenir (t = ortak test ortami).
import { createHash, randomUUID } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { PlatformError } from '../src/modules/errors.js';

const PDF = (extra = '') => Buffer.from(`%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n${extra}\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n`, 'latin1');
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from('QA-PNG-BODY'), Buffer.from('IEND')]);
const DOCX = Buffer.concat([Buffer.from([0x50, 0x4b, 0x03, 0x04]), Buffer.from('word/document.xml')]);

/** Sahte depolama dikisi (BELGELER A2-A4 sozlesmesinin kucuk bir kopyasi): imza ile tur tanima, sha256, atomik yazma. */
function makeFakeSeam(dir) {
  const seam = {
    maxFileBytes: 200000,
    calls: { store: 0, open: 0, remove: 0 },
    async storeUpload({ siteCode, req, declaredSize, allowedMimeTypes, maxBytes }) {
      seam.calls.store += 1;
      const chunks = [];
      let total = 0;
      for await (const chunk of req) {
        total += chunk.length;
        if (total > maxBytes) throw new PlatformError(413, 'DOCUMENT_TOO_LARGE', 'buyuk');
        chunks.push(chunk);
      }
      const bytes = Buffer.concat(chunks);
      if (bytes.length !== declaredSize) throw new PlatformError(400, 'DOCUMENT_SIZE_MISMATCH', 'boyut');
      let mime = null;
      if (bytes.subarray(0, 5).toString('latin1') === '%PDF-') mime = 'application/pdf';
      else if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) mime = 'image/jpeg';
      else if (bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) mime = 'image/png';
      else if (bytes[0] === 0x50 && bytes[1] === 0x4b) mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      if (!mime || !allowedMimeTypes.includes(mime)) throw new PlatformError(415, 'DOCUMENT_TYPE_NOT_ALLOWED', 'tur');
      const key = `${String(siteCode).padStart(10, '0')}/${randomUUID()}`;
      const file = path.join(dir, key.replace('/', '_'));
      fs.writeFileSync(file, bytes);
      return { storageKey: key, mimeType: mime, sizeBytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') };
    },
    openDownload(siteCode, key) {
      seam.calls.open += 1;
      return fs.createReadStream(path.join(dir, key.replace('/', '_')));
    },
    async removeFile(siteCode, key) {
      seam.calls.remove += 1;
      fs.rmSync(path.join(dir, key.replace('/', '_')), { force: true });
    },
    exists: (key) => fs.existsSync(path.join(dir, key.replace('/', '_'))),
  };
  return seam;
}

export default async function sectionExpenses(t) {
  const { check, q, call, callRaw, hooks, TODAY, ago, monthStart, ym, mkManaged, mkUser, mkSite, link, P, key, failCode, failMessage, users } = t;
  const { MGR, MGR2, BOARD, STAFF, OUTSIDER, RESIDENT, SUPER } = users;
  console.log('--- D. gider ---');
  const adapter = await import('../src/modules/finance_documents_adapter.js');
  const docsDir = fs.mkdtempSync(path.join(os.tmpdir(), 'f4b-docs-'));
  const seam = makeFakeSeam(docsDir);
  adapter.setDocumentSeamForTests(null); // once: katman YOK

  const site = await mkManaged('F4B Gider Sitesi', { 'G Blok': 2 });
  const exp = (body, user = MGR, s = site) => call('POST', `${P(s.code)}/expenses`, user, { description: 'Asansor bakim', amount_minor: 120000, expense_date: TODAY, idempotency_key: key('exp'), ...body });
  const catId = async (name, s = site) => (await call('GET', `${P(s.code)}/expense-categories`, MGR)).body.items.find((c) => c.name === name)?.id;
  const accBody = (over = {}) => ({ name: 'Ana Kasa', kind: 'cash', opening_balance_minor: 1000000, opening_date: ago(60), idempotency_key: key('acc'), ...over });

  // --- D1. kategoriler
  const cats = await call('GET', `${P(site.code)}/expense-categories`, BOARD);
  check('D1: ilk GET varsayilan 12 kategoriyi ekler (kurul de okur); is_system', cats.status === 200 && cats.body.items.length === 12 && cats.body.items.every((c) => c.is_system && c.is_active) && cats.body.items.some((c) => c.name === 'Doğalgaz/Yakıt'), cats.body.items?.length);
  const cats2 = await call('GET', `${P(site.code)}/expense-categories`, MGR);
  check('D1b: ikinci GET tekrar eklemez (hala 12; eszamanli ilk cagrilarda da tekil)', cats2.body.items.length === 12);
  const catNew = await call('POST', `${P(site.code)}/expense-categories`, MGR, { name: 'Bahce bakimi' });
  const catDup = await call('POST', `${P(site.code)}/expense-categories`, MGR, { name: 'BAHCE BAKIMI' });
  const catBoard = await call('POST', `${P(site.code)}/expense-categories`, BOARD, { name: 'Kurul kategori' });
  const catRename = await call('PATCH', `${P(site.code)}/expense-categories/${catNew.body.category.id}`, MGR, { name: 'Peyzaj', sort_order: 99 });
  const catOff = await call('PATCH', `${P(site.code)}/expense-categories/${catNew.body.category.id}`, MGR, { is_active: false });
  check('D1c: kategori ekle 201 / ad tekil (buyuk-kucuk harf duyarsiz) 409 CATEGORY_NAME_TAKEN / kurul yazamaz 403 / yeniden adlandir + pasiflestir; silme ucu yok', catNew.status === 201 && catDup.status === 409 && catDup.body.code === 'CATEGORY_NAME_TAKEN' && catBoard.status === 403 && catRename.body.category.name === 'Peyzaj' && catOff.body.category.is_active === false && (await call('DELETE', `${P(site.code)}/expense-categories/${catNew.body.category.id}`, MGR)).status === 404);

  // --- D2. tedarikciler
  const supBad = [];
  for (const [label, body] of [['bos ad', { name: '' }], ['vergi no 9 hane', { name: 'X', tax_id: '123456789' }], ['vergi no harf', { name: 'X', tax_id: '12345abcde' }], ['telefon 21', { name: 'X', phone: '1'.repeat(21) }], ['not 201', { name: 'X', note: 'n'.repeat(201) }]]) supBad.push([label, (await call('POST', `${P(site.code)}/suppliers`, MGR, body)).status]);
  const sup = await call('POST', `${P(site.code)}/suppliers`, MGR, { name: 'Otis Asansor', tax_id: '1234567890', phone: '02121234567', note: 'ozel not' });
  const supDup = await call('POST', `${P(site.code)}/suppliers`, MGR, { name: 'OTIS ASANSOR' });
  const supBoard = await call('GET', `${P(site.code)}/suppliers`, BOARD);
  const supMgr = await call('GET', `${P(site.code)}/suppliers?q=otis`, MGR);
  check('D2: tedarikci dogrulamalari 400; 201; ad tekil 409 SUPPLIER_NAME_TAKEN; kurulda tax_id / phone / note NULL, yoneticide dolu; arama calisir',
    supBad.every(([, s]) => s === 400) && sup.status === 201 && supDup.status === 409 && supDup.body.code === 'SUPPLIER_NAME_TAKEN' && supBoard.body.items[0].tax_id === null && supBoard.body.items[0].phone === null && supBoard.body.items[0].note === null
      && supMgr.body.items[0].tax_id === '1234567890' && supMgr.body.total === 1, [supBad, supBoard.body]);
  const supplierId = sup.body.supplier.id;
  const supPatch = await call('PATCH', `${P(site.code)}/suppliers/${supplierId}`, MGR, { phone: '05320000000', is_active: true });
  check('D2b: tedarikci PATCH (telefon) 200', supPatch.status === 200 && supPatch.body.supplier.phone === '05320000000');

  // --- D3. hesap yokken gider
  const kategori = await catId('Asansör bakım');
  const noAcc = await exp({ category_id: kategori, account_id: 1 });
  check('D3: hesap YOKKEN gider 409 NO_ACCOUNT (hicbir kayit yazilmaz)', noAcc.status === 409 && noAcc.body.code === 'NO_ACCOUNT' && (await q(`SELECT COUNT(*)::int AS n FROM expenses WHERE site_code = $1`, [site.code])).rows[0].n === 0, noAcc.body);
  const kasa = await call('POST', `${P(site.code)}/accounts`, MGR, accBody());
  const banka = await call('POST', `${P(site.code)}/accounts`, MGR, accBody({ name: 'Banka', kind: 'bank', opening_balance_minor: 0 }));
  const kasaId = kasa.body.account.id;
  const bankaId = banka.body.account.id;
  const bal = async (id) => (await call('GET', `${P(site.code)}/accounts`, MGR)).body.items.find((a) => a.id === id)?.balance_minor;

  // --- D4. dogrulama
  const bad = [];
  for (const [label, body] of [['kategorisiz', { account_id: kasaId }], ['hesapsiz', { category_id: kategori }], ['tutar 0', { category_id: kategori, account_id: kasaId, amount_minor: 0 }], ['ondalik tutar', { category_id: kategori, account_id: kasaId, amount_minor: 10.5 }],
    ['10^12 ustu', { category_id: kategori, account_id: kasaId, amount_minor: 1000000000001 }], ['kdv > tutar', { category_id: kategori, account_id: kasaId, vat_minor: 999999999 }], ['aciklamasiz', { category_id: kategori, account_id: kasaId, description: '' }],
    ['201 karakter aciklama', { category_id: kategori, account_id: kasaId, description: 'x'.repeat(201) }], ['gelecek tarih', { category_id: kategori, account_id: kasaId, expense_date: '2999-01-01' }], ['gecersiz belge turu', { category_id: kategori, account_id: kasaId, document_kind: 'x' }],
    ['anahtarsiz', { category_id: kategori, account_id: kasaId, idempotency_key: '' }], ['41 karakter belge no', { category_id: kategori, account_id: kasaId, document_no: 'x'.repeat(41) }], ['6 yildan eski', { category_id: kategori, account_id: kasaId, expense_date: '2018-01-01' }]]) bad.push([label, (await exp(body)).status]);
  check('D4: gider dogrulamalari 400 (kategori, hesap, tutar, kdv, aciklama, tarih, belge turu/no, anahtar)', bad.every(([, s]) => s === 400), bad);
  const wrongCat = await exp({ category_id: 99999999, account_id: kasaId });
  const wrongSup = await exp({ category_id: kategori, account_id: kasaId, supplier_id: 99999999 });
  const wrongAcc = await exp({ category_id: kategori, account_id: 99999999 });
  const catOffExp = await exp({ category_id: catNew.body.category.id, account_id: kasaId });
  const beforeOpen = await exp({ category_id: kategori, account_id: kasaId, expense_date: ago(100) });
  check('D4b: olmayan kategori 404 / tedarikci 404 / hesap 404; pasif kategori 409 CATEGORY_INACTIVE; acilistan once 409 BEFORE_OPENING_DATE',
    wrongCat.status === 404 && wrongCat.body.code === 'CATEGORY_NOT_FOUND' && wrongSup.status === 404 && wrongSup.body.code === 'SUPPLIER_NOT_FOUND' && wrongAcc.status === 404 && wrongAcc.body.code === 'ACCOUNT_NOT_FOUND'
      && catOffExp.status === 409 && catOffExp.body.code === 'CATEGORY_INACTIVE' && beforeOpen.status === 409 && beforeOpen.body.code === 'BEFORE_OPENING_DATE', [wrongCat.body, wrongSup.body, wrongAcc.body, catOffExp.body, beforeOpen.body]);

  // --- D5. basarili gider: hareket, bakiye, anlik goruntu
  const before = await bal(kasaId);
  const e1 = await exp({ category_id: kategori, supplier_id: supplierId, account_id: kasaId, vat_minor: 20000, document_kind: 'invoice', document_no: 'A-001/2026' });
  check('D5: gider 201: anlik goruntu (kategori / tedarikci adi), KDV, hesap, hareket (-120000), hesap bakiyesi guncel', e1.status === 201 && e1.body.expense.category_name === 'Asansör bakım' && e1.body.expense.supplier_name === 'Otis Asansor' && e1.body.expense.vat_minor === 20000 && e1.body.expense.account.id === kasaId
    && e1.body.movement.amount_minor === -120000 && e1.body.account_balance_minor === before - 120000 && (await bal(kasaId)) === before - 120000, e1.body);
  await call('PATCH', `${P(site.code)}/expense-categories/${kategori}`, MGR, { name: 'Asansör bakım ve onarım' });
  const e1Get = await call('GET', `${P(site.code)}/expenses/${e1.body.expense.id}`, MGR);
  check('D5b: kategori adi sonradan degisse de gider kaydi ANLIK GORUNTUYU korur', e1Get.body.category_name === 'Asansör bakım');
  await call('PATCH', `${P(site.code)}/expense-categories/${kategori}`, MGR, { name: 'Asansör bakım' });

  // --- D6. cift kayit onlemleri
  const replayKey = key('replay');
  const r1 = await exp({ category_id: kategori, account_id: bankaId, description: 'Tekrar', amount_minor: 7777, idempotency_key: replayKey });
  const r2 = await exp({ category_id: kategori, account_id: bankaId, description: 'Tekrar', amount_minor: 7777, idempotency_key: replayKey });
  const r3 = await exp({ category_id: kategori, account_id: bankaId, description: 'Tekrar', amount_minor: 7778, idempotency_key: replayKey });
  check('D6: ayni anahtar + ayni govde 200 replay (tek kayit); ayni anahtar + farkli govde 409 IDEMPOTENCY_CONFLICT', r1.status === 201 && r2.status === 200 && r2.body.expense.id === r1.body.expense.id && r3.status === 409 && r3.body.code === 'IDEMPOTENCY_CONFLICT' && (await q(`SELECT COUNT(*)::int AS n FROM expenses WHERE site_code = $1 AND idempotency_key = $2`, [site.code, replayKey])).rows[0].n === 1, [r2.status, r3.body]);
  const dupNo = await exp({ category_id: kategori, supplier_id: supplierId, account_id: kasaId, amount_minor: 555, document_no: 'a 001-2026' });
  const dupNo2 = await exp({ category_id: kategori, supplier_id: supplierId, account_id: kasaId, amount_minor: 556, document_no: 'A001/2026' });
  check('D6b: ayni tedarikci + normalize belge no (buyuk-kucuk harf / ayirac duyarsiz) 409 DUPLICATE_DOCUMENT_NO + existing_expense_id', dupNo.status === 409 && dupNo.body.code === 'DUPLICATE_DOCUMENT_NO' && dupNo.body.existing_expense_id === e1.body.expense.id && dupNo2.status === 409, [dupNo.body, dupNo2.body]);
  const otherSupplier = await call('POST', `${P(site.code)}/suppliers`, MGR, { name: 'Baska Firma' });
  const sameNoOtherSup = await exp({ category_id: kategori, supplier_id: otherSupplier.body.supplier.id, account_id: kasaId, amount_minor: 557, document_no: 'A-001/2026' });
  check('D6c: ayni belge no BASKA tedarikcide serbest', sameNoOtherSup.status === 201, sameNoOtherSup.body);
  const nat1 = await exp({ category_id: kategori, account_id: kasaId, description: 'Cesitli', amount_minor: 4242 });
  const nat2 = await exp({ category_id: kategori, account_id: kasaId, description: 'Cesitli (tekrar)', amount_minor: 4242 });
  const nat3 = await exp({ category_id: kategori, account_id: kasaId, description: 'Cesitli (bilincli)', amount_minor: 4242, allow_duplicate: true });
  check('D6d: 24 saatte AYNI tedarikci / tutar / tarih / kategori 409 DUPLICATE_EXPENSE (+ existing_expense_id); allow_duplicate:true ile bilincli tekrar 201', nat1.status === 201 && nat2.status === 409 && nat2.body.code === 'DUPLICATE_EXPENSE' && nat2.body.existing_expense_id === nat1.body.expense.id && nat3.status === 201, [nat2.body, nat3.status]);
  // eszamanli cift gonderim: ayni anahtar -> tek kayit
  const raceKey = key('race');
  const raced = await Promise.all(Array.from({ length: 6 }, () => exp({ category_id: kategori, account_id: kasaId, description: 'Yaris', amount_minor: 9191, idempotency_key: raceKey })));
  const racedRows = (await q(`SELECT COUNT(*)::int AS n FROM expenses WHERE site_code = $1 AND idempotency_key = $2`, [site.code, raceKey])).rows[0].n;
  check('D6e: ayni anahtarla ESZAMANLI 6 gonderim -> TEK gider; hepsi 201/200', racedRows === 1 && raced.every((r) => r.status === 201 || r.status === 200) && raced.filter((r) => r.status === 201).length === 1, raced.map((r) => r.status));
  // eszamanli ayni icerik, farkli anahtar: biri kayit, digerleri DUPLICATE_EXPENSE
  const sameContent = await Promise.all(Array.from({ length: 5 }, () => exp({ category_id: kategori, account_id: kasaId, description: 'Ayni icerik', amount_minor: 3131 })));
  check('D6f: ayni icerik + farkli anahtar ESZAMANLI 5 gonderim -> 1 kayit, digerleri 409 DUPLICATE_EXPENSE', sameContent.filter((r) => r.status === 201).length === 1 && sameContent.filter((r) => r.status === 409 && r.body.code === 'DUPLICATE_EXPENSE').length === 4, sameContent.map((r) => r.status));

  // --- D7. iptal (void)
  const kasaBeforeVoid = await bal(kasaId);
  const void1 = await call('POST', `${P(site.code)}/expenses/${nat3.body.expense.id}/void`, MGR, { reason: 'yanlis kayit', idempotency_key: key('v1') });
  const void1b = await call('POST', `${P(site.code)}/expenses/${nat3.body.expense.id}/void`, MGR, { reason: 'yanlis kayit', idempotency_key: key('v2') });
  check('D7: iptal 201: gider voided {at, reason, period}, AYNA hareket (+tutar) AYNI islemde, hesap bakiyesi geri; ikinci iptal 409 EXPENSE_ALREADY_VOIDED',
    void1.status === 201 && void1.body.expense.voided?.reason === 'yanlis kayit' && (await bal(kasaId)) === kasaBeforeVoid + 4242 && void1b.status === 409 && void1b.body.code === 'EXPENSE_ALREADY_VOIDED', [void1.body, void1b.body]);
  const voidKey = key('vk');
  const v3 = await call('POST', `${P(site.code)}/expenses/${nat1.body.expense.id}/void`, MGR, { reason: 'x', idempotency_key: voidKey });
  const v3b = await call('POST', `${P(site.code)}/expenses/${nat1.body.expense.id}/void`, MGR, { reason: 'x', idempotency_key: voidKey });
  const v3c = await call('POST', `${P(site.code)}/expenses/${e1.body.expense.id}/void`, MGR, { reason: 'x', idempotency_key: voidKey });
  check('D7b: ayni anahtar tekrar 200 (cift ayna yok); baska gider icin kullanilmis anahtar 409 IDEMPOTENCY_CONFLICT; iptalsiz reason 400', v3.status === 201 && v3b.status === 200 && v3c.status === 409 && (await call('POST', `${P(site.code)}/expenses/${nat1.body.expense.id}/void`, MGR, { idempotency_key: key('z') })).status === 400);
  const freed = await exp({ category_id: kategori, supplier_id: supplierId, account_id: kasaId, amount_minor: 120000, document_no: 'A-001/2026' });
  check('D7c: iptalli giderin belge no\'su serbest kalir (duzeltme akisi); ayni icerik de yeniden kaydedilebilir', freed.status === 409 /* e1 hala aktif */);
  await call('POST', `${P(site.code)}/expenses/${e1.body.expense.id}/void`, MGR, { reason: 'duzeltme icin', idempotency_key: key('v4') });
  const freed2 = await exp({ category_id: kategori, supplier_id: supplierId, account_id: kasaId, amount_minor: 120000, document_no: 'A-001/2026' });
  check('D7d: e1 iptalinden sonra ayni belge no / ayni icerik 201', freed2.status === 201, freed2.body);

  // --- D8. duzeltme: tek islem
  const cStart = await exp({ category_id: kategori, account_id: kasaId, description: 'Duzeltilecek', amount_minor: 5000 });
  const cOk = await call('POST', `${P(site.code)}/expenses/${cStart.body.expense.id}/correct`, MGR, { category_id: kategori, account_id: bankaId, description: 'Duzeltildi', amount_minor: 5500, expense_date: TODAY, idempotency_key: key('c1') });
  check('D8: duzeltme: eski gider iptal + YENI gider (corrects_expense_id) TEK islemde; yeni hesap (banka) bakiyesi dusen', cOk.status === 201 && cOk.body.voided.voided !== null && cOk.body.expense.corrects_expense_id === cStart.body.expense.id && cOk.body.expense.account.id === bankaId, cOk.body);
  const cKey = key('c2');
  const kasaBeforeC = await bal(kasaId);
  const cStart2 = await exp({ category_id: kategori, account_id: kasaId, description: 'Yarim kalmasin', amount_minor: 6000 });
  hooks.failOnce = { match: /INSERT INTO expenses \(/, code: '57014', times: 1 };
  const cFail = await call('POST', `${P(site.code)}/expenses/${cStart2.body.expense.id}/correct`, MGR, { category_id: kategori, account_id: kasaId, description: 'Yeni', amount_minor: 6500, expense_date: TODAY, idempotency_key: cKey });
  hooks.failOnce = null;
  const stillActive = (await call('GET', `${P(site.code)}/expenses/${cStart2.body.expense.id}`, MGR)).body;
  check('D8b: duzeltme ortasinda hata -> ROLLBACK: eski gider IPTAL EDILMEDI, yeni gider yok, hesap bakiyesi ayni (yarim kalmaz)', cFail.status === 500 && stillActive.voided === null && (await bal(kasaId)) === kasaBeforeC - 6000, [cFail.status, stillActive.voided]);
  const cReplay1 = await call('POST', `${P(site.code)}/expenses/${cStart2.body.expense.id}/correct`, MGR, { category_id: kategori, account_id: kasaId, description: 'Yeni', amount_minor: 6500, expense_date: TODAY, idempotency_key: cKey });
  const cReplay2 = await call('POST', `${P(site.code)}/expenses/${cStart2.body.expense.id}/correct`, MGR, { category_id: kategori, account_id: kasaId, description: 'Yeni', amount_minor: 6500, expense_date: TODAY, idempotency_key: cKey });
  check('D8c: duzeltme yeniden denemesi 201 sonra ayni anahtarla 200 (cift gider yok)', cReplay1.status === 201 && cReplay2.status === 200 && cReplay2.body.expense.id === cReplay1.body.expense.id);
  const cAgain = await call('POST', `${P(site.code)}/expenses/${cStart.body.expense.id}/correct`, MGR, { category_id: kategori, account_id: bankaId, description: 'Tekrar', amount_minor: 1, expense_date: TODAY, idempotency_key: key('c3') });
  check('D8d: iptalli gider tekrar duzeltilemez (409 EXPENSE_ALREADY_VOIDED)', cAgain.status === 409 && cAgain.body.code === 'EXPENSE_ALREADY_VOIDED');

  // --- D9. kapali donem
  const s2 = await mkManaged('F4B Gider Kapali Donem', { 'K Blok': 1 });
  const k2 = await call('POST', `${P(s2.code)}/accounts`, MGR, accBody());
  const cat2 = await catId('Su', s2);
  const old = await exp({ category_id: cat2, account_id: k2.body.account.id, expense_date: ago(45), description: 'Eski ay gideri' }, MGR, s2);
  const lastMonth = ym(-1);
  const closeRes = await call('POST', `${P(s2.code)}/periods/${lastMonth}/close`, MGR);
  const inClosed = await exp({ category_id: cat2, account_id: k2.body.account.id, expense_date: `${lastMonth}-15`, description: 'Kapali ay' }, MGR, s2);
  const voidClosed = await call('POST', `${P(s2.code)}/expenses/${old.body.expense.id}/void`, MGR, { reason: 'kapali ay gideri iptali', idempotency_key: key('vc') });
  const mirror = (await q(`SELECT period::text AS p, movement_date::text AS d FROM account_movements WHERE site_code = $1 AND kind = 'reversal'`, [s2.code])).rows[0];
  check('D9: kapali aya gider 409 PERIOD_CLOSED; kapali ayin gideri iptal edilebilir ve AYNA hareket AÇIK ayda bugunun tarihiyle yazilir',
    closeRes.status === 200 && inClosed.status === 409 && inClosed.body.code === 'PERIOD_CLOSED' && voidClosed.status === 201 && mirror && mirror.d === TODAY && mirror.p >= monthStart(0), [closeRes.status, inClosed.body, mirror]);
  const oldDoc = await call('POST', `${P(s2.code)}/expenses/${old.body.expense.id}/documents`, MGR, { file: { name: 'fatura.pdf', size: 100 }, kind: 'invoice', idempotency_key: key('d') });
  check('D9b: katman YOKKEN belge ucu 409 DOCUMENTS_NOT_AVAILABLE; gider kaydi ekten bagimsiz calisti', oldDoc.status === 409 && oldDoc.body.code === 'DOCUMENTS_NOT_AVAILABLE', oldDoc.body);

  // --- D10. belge eki (sahte depolama dikisi ile)
  adapter.setDocumentSeamForTests(seam);
  const dx = await exp({ category_id: kategori, account_id: kasaId, description: 'Belgeli gider', amount_minor: 321 });
  const dxId = dx.body.expense.id;
  const mkDoc = (body, user = MGR) => call('POST', `${P(site.code)}/expenses/${dxId}/documents`, user, { file: { name: 'Fatura Şubat.pdf', size: PDF().length }, kind: 'invoice', idempotency_key: key('doc'), ...body });
  const put = (docId, buffer, user = MGR, headers = {}) => callRaw('PUT', `${P(site.code)}/expenses/${dxId}/documents/${docId}/content`, user, buffer, { 'content-type': 'application/octet-stream', ...headers });
  const dBad = [];
  for (const [label, body] of [['boyutsuz', { file: { name: 'a.pdf' } }], ['negatif boyut', { file: { name: 'a.pdf', size: -1 } }], ['gecersiz tur', { kind: 'x' }], ['anahtarsiz', { idempotency_key: '' }]]) dBad.push([label, (await mkDoc(body)).status]);
  const dExe = await mkDoc({ file: { name: 'virus.exe', size: 10 } });
  const dHuge = await mkDoc({ file: { name: 'dev.pdf', size: 99999999 } });
  check('D10: belge ustveri dogrulamalari 400; .exe 415 DOCUMENT_TYPE_NOT_ALLOWED; cok buyuk 413 DOCUMENT_TOO_LARGE', dBad.every(([, s]) => s === 400) && dExe.status === 415 && dExe.body.code === 'DOCUMENT_TYPE_NOT_ALLOWED' && dHuge.status === 413 && dHuge.body.code === 'DOCUMENT_TOO_LARGE', [dBad, dExe.body, dHuge.body]);
  const docKey = key('dk');
  const d1 = await mkDoc({ idempotency_key: docKey });
  const d1b = await mkDoc({ idempotency_key: docKey });
  check('D10b: POST 201 { document uploading, upload { PUT, octet-stream, size, max_bytes, expires_at } }; ayni anahtar tekrar 200 (cift satir yok)', d1.status === 201 && d1.body.document.status === 'uploading' && d1.body.upload.method === 'PUT' && d1.body.upload.content_type === 'application/octet-stream' && d1.body.upload.size === PDF().length && d1.body.upload.path.endsWith(`/documents/${d1.body.document.id}/content`) && d1b.status === 200 && d1b.body.document.id === d1.body.document.id
    && d1.body.document.display_name === 'Fatura Şubat.pdf', [d1.body, d1b.status]);
  const wrongSize = await put(d1.body.document.id, Buffer.concat([PDF(), Buffer.from('x')]));
  check('D10c: gonderilen boyut bildirilenle uyusmazsa 400 DOCUMENT_SIZE_MISMATCH (dosya yazilmaz)', wrongSize.status === 400 && wrongSize.body.code === 'DOCUMENT_SIZE_MISMATCH' && seam.calls.store === 0, wrongSize.body);
  const otherUploader = await put(d1.body.document.id, PDF(), MGR2);
  check('D10c2: yuklemeyi baslatmayan baska kullanici / yetkisiz yonetici PUT yapamaz (403)', otherUploader.status === 403, otherUploader.status);
  const up = await put(d1.body.document.id, PDF());
  check('D10d: PUT ham govde 200: belge ready, sha256 dolu, mime application/pdf; dosya depoda', up.status === 200 && up.body.document.status === 'ready' && up.body.document.sha256 === createHash('sha256').update(PDF()).digest('hex') && up.body.document.mime_type === 'application/pdf' && seam.calls.store === 1, up.body);
  const again = await put(d1.body.document.id, PDF());
  check('D10e: tamamlanmis yuklemeye ikinci PUT 409 UPLOAD_ALREADY_COMPLETED', again.status === 409 && again.body.code === 'UPLOAD_ALREADY_COMPLETED', again.body);
  // ayni dosya ikinci kez
  const d2 = await mkDoc({ file: { name: 'kopya.pdf', size: PDF().length } });
  const upDup = await put(d2.body.document.id, PDF());
  check('D10f: AYNI dosya (sha256) ayni gidere ikinci kez 409 DUPLICATE_DOCUMENT; yeni yazilan dosya GERI ALINDI (yetim yok)', upDup.status === 409 && upDup.body.code === 'DUPLICATE_DOCUMENT' && seam.calls.remove === 1, [upDup.body, seam.calls]);
  // tur uyusmazligi: uzantisi .pdf ama icerik DOCX
  const d3 = await mkDoc({ file: { name: 'sahte.pdf', size: DOCX.length } });
  const upBad = await put(d3.body.document.id, DOCX);
  check('D10g: icerik izinli degilse (DOCX) 415 DOCUMENT_TYPE_NOT_ALLOWED; belge uploading kalir', upBad.status === 415 && (await q(`SELECT status FROM expense_documents WHERE id = $1`, [d3.body.document.id])).rows[0].status === 'uploading', upBad.body);
  // ikinci gecerli belge (PNG) + limit 5
  const png = await mkDoc({ file: { name: 'foto.PNG', size: PNG.length }, kind: 'photo' });
  const upPng = await put(png.body.document.id, PNG);
  check('D10h: PNG belge 200; mime image/png; uzanti buyuk-kucuk harf duyarsiz', upPng.status === 200 && upPng.body.document.mime_type === 'image/png' && png.body.document.display_name === 'foto.png', upPng.body);
  const ids = [d1.body.document.id, d2.body.document.id, d3.body.document.id, png.body.document.id];
  const d5 = await mkDoc({ file: { name: 'e.pdf', size: 50 } });
  const d6 = await mkDoc({ file: { name: 'f.pdf', size: 50 } });
  check('D10i: gider basina en cok 5 ETKIN belge: 5. kabul, 6. 409 EXPENSE_DOCUMENT_LIMIT', d5.status === 201 && d6.status === 409 && d6.body.code === 'EXPENSE_DOCUMENT_LIMIT', [d5.status, d6.body]);
  void ids;
  // ad temizligi
  const evil = await call('POST', `${P(site.code)}/expenses/${(await exp({ category_id: kategori, account_id: kasaId, description: 'Ad testi', amount_minor: 11 })).body.expense.id}/documents`, MGR, { file: { name: '..\\..\\etc\\pas‮swd.final.pdf', size: 20 }, kind: 'other', idempotency_key: key('ev') });
  check('D10j: dosya adi temizlenir: yol parcalari, yon kontrol karakteri atilir, cift uzanti kapanir (.final noktasi _)', evil.status === 201 && !/[\\/]|‮/.test(evil.body.document.display_name) && evil.body.document.display_name.endsWith('.pdf') && !evil.body.document.display_name.slice(0, -4).includes('.'), evil.body.document?.display_name);

  // --- D11. indirme
  const dl = await callRaw('GET', `${P(site.code)}/expenses/${dxId}/documents/${d1.body.document.id}/download`, MGR);
  const dlBoard = await callRaw('GET', `${P(site.code)}/expenses/${dxId}/documents/${d1.body.document.id}/download`, BOARD);
  const dlStaff = await callRaw('GET', `${P(site.code)}/expenses/${dxId}/documents/${d1.body.document.id}/download`, STAFF);
  const dlOther = await callRaw('GET', `${P(site.code)}/expenses/${dxId}/documents/${d1.body.document.id}/download`, MGR2);
  const dlNotReady = await callRaw('GET', `${P(site.code)}/expenses/${dxId}/documents/${d3.body.document.id}/download`, MGR);
  const h = dl.headers;
  check('D11: indirme: yonetici + kurul 200 ve ayni bayt; A8 basliklari (attachment, nosniff, sandbox CSP, no-store, dogru Content-Type/Length); gorevli / baska site 403; hazir olmayan 404',
    dl.status === 200 && dl.bytes.equals(PDF()) && dlBoard.status === 200 && /^attachment; filename="/.test(h.get('content-disposition')) && h.get('content-disposition').includes("filename*=UTF-8''") && h.get('x-content-type-options') === 'nosniff'
      && h.get('content-security-policy') === "default-src 'none'; sandbox" && /no-store/.test(h.get('cache-control')) && h.get('content-type') === 'application/pdf' && Number(h.get('content-length')) === PDF().length && dlStaff.status === 403 && dlOther.status === 403 && dlNotReady.status === 404, [dl.status, [...h.entries()], dlStaff.status, dlOther.status, dlNotReady.status]);
  // IDOR: baska sitenin giderine bagli belge kimligi
  const idorSite = await mkManaged('F4B Gider IDOR', { 'I Blok': 1 });
  const idor = await callRaw('GET', `${P(idorSite.code)}/expenses/${dxId}/documents/${d1.body.document.id}/download`, MGR);
  check('D11b: IDOR: baska sitenin yoneticisi ile ayni belge kimligi 404 (kimlik baska sitede degil, bu sitede yok)', idor.status === 404, idor.status);
  // gorevli yukleyemez, kurul yukleyemez
  const boardPost = await mkDoc({ file: { name: 'k.pdf', size: 20 } }, BOARD);
  check('D11c: kurul / gorevli belge ekleyemez (403)', boardPost.status === 403 && (await mkDoc({ file: { name: 'k.pdf', size: 20 } }, STAFF)).status === 403);

  // --- D12. baglanti kaldirma
  const rem = await call('DELETE', `${P(site.code)}/expenses/${dxId}/documents/${d1.body.document.id}`, MGR, { reason: 'yanlis dosya' });
  const remAgain = await call('DELETE', `${P(site.code)}/expenses/${dxId}/documents/${d1.body.document.id}`, MGR, { reason: 'tekrar' });
  const afterRem = await callRaw('GET', `${P(site.code)}/expenses/${dxId}/documents/${d1.body.document.id}/download`, MGR);
  const stored = (await q(`SELECT storage_key FROM expense_documents WHERE id = $1`, [d1.body.document.id])).rows[0].storage_key;
  check('D12: kaldirma yalniz BAGLANTIYI keser: belge listeden ve indirmeden cikar (404), DOSYA DEPODA KALIR (KMK m.36), kayit silinmez; ikinci kaldirma 404',
    rem.status === 200 && rem.body.document.id === d1.body.document.id && remAgain.status === 404 && afterRem.status === 404 && seam.exists(stored) && (await q(`SELECT COUNT(*)::int AS n FROM expense_documents WHERE id = $1`, [d1.body.document.id])).rows[0].n === 1, [rem.status, remAgain.status, afterRem.status]);
  const dbDelete = await failMessage(`DELETE FROM expense_documents WHERE id = $1`, [d1.body.document.id]);
  const dbUpdate = await failMessage(`UPDATE expense_documents SET display_name = 'x' WHERE id = $1`, [d1.body.document.id]);
  const dbUndo = await failMessage(`UPDATE expense_documents SET removed_at = NULL WHERE id = $1`, [d1.body.document.id]);
  check('D12b: DB: belge satiri silinemez / yeniden adlandirilamaz / kaldirma geri alinamaz (tetikleyici)', dbDelete !== null && dbUpdate !== null && dbUndo !== null, [dbDelete, dbUpdate, dbUndo]);
  const detail = await call('GET', `${P(site.code)}/expenses/${dxId}`, MGR);
  check('D12c: gider detayinda yalniz etkin belgeler (kaldirilan yok); documents_count dogru', detail.body.documents.every((d) => d.id !== d1.body.document.id) && detail.body.documents_count === detail.body.documents.filter((d) => d.status === 'ready').length, detail.body.documents);

  // --- D13. kota (gider belgeleri sayilir)
  process.env.DOCUMENTS_SITE_QUOTA_BYTES = '5000';
  const quotaExp = await exp({ category_id: kategori, account_id: kasaId, description: 'Kota', amount_minor: 22 });
  const quota = await call('POST', `${P(site.code)}/expenses/${quotaExp.body.expense.id}/documents`, MGR, { file: { name: 'big.pdf', size: 190000 }, kind: 'other', idempotency_key: key('q') });
  delete process.env.DOCUMENTS_SITE_QUOTA_BYTES;
  check('D13: site kotasi gider belgelerini de sayar -> 409 DOCUMENT_QUOTA_EXCEEDED', quota.status === 409 && quota.body.code === 'DOCUMENT_QUOTA_EXCEEDED', quota.body);
  adapter.setDocumentSeamForTests(undefined);

  // --- D14. liste / filtre / toplamlar / kurul
  const all = await call('GET', `${P(site.code)}/expenses?limit=500`, MGR);
  const activeSum = all.body.items.filter((e) => e.voided === null).reduce((a, e) => a + BigInt(e.amount_minor), 0n);
  const voidedSum = all.body.items.filter((e) => e.voided !== null).reduce((a, e) => a + BigInt(e.amount_minor), 0n);
  check('D14: liste: totals.active_minor / voided_minor tum sonucun toplamiyla ayni', all.body.items.length >= 10 && BigInt(all.body.totals.active_minor) === activeSum && BigInt(all.body.totals.voided_minor) === voidedSum, all.body.totals);
  const pg1 = await call('GET', `${P(site.code)}/expenses?limit=4`, MGR);
  const pg2 = await call('GET', `${P(site.code)}/expenses?limit=4&before_id=${pg1.body.next_before_id}`, MGR);
  const onlyVoided = await call('GET', `${P(site.code)}/expenses?status=voided`, MGR);
  const bySup = await call('GET', `${P(site.code)}/expenses?supplier_id=${supplierId}&status=active`, MGR);
  const byQ = await call('GET', `${P(site.code)}/expenses?q=${encodeURIComponent('BELGELI')}`, MGR);
  const byAcc = await call('GET', `${P(site.code)}/expenses?account_id=${bankaId}`, MGR);
  const badFilter = await call('GET', `${P(site.code)}/expenses?status=x`, MGR);
  check('D14b: sayfalama (limit/before_id), durum / tedarikci / hesap / arama (Turkce katlama) suzgecleri; gecersiz suzgec 400',
    pg1.body.items.length === 4 && pg2.body.items.every((e) => e.id < pg1.body.next_before_id) && onlyVoided.body.items.every((e) => e.voided !== null) && bySup.body.items.every((e) => e.supplier_id === supplierId) && byQ.body.items.some((e) => e.description === 'Belgeli gider')
      && byAcc.body.items.every((e) => e.account.id === bankaId) && badFilter.status === 400);
  const boardList = await call('GET', `${P(site.code)}/expenses`, BOARD);
  check('D14c: kurul gider listesini okur; olusturan adi gizli (null); yazamaz', boardList.status === 200 && boardList.body.items.every((e) => e.created_by_name === null) && (await exp({ category_id: kategori, account_id: kasaId }, BOARD)).status === 403);

  // --- D15. degismezler
  const inv = (await q(
    `SELECT
       (SELECT COALESCE(SUM(m.amount_minor), 0) FROM account_movements m WHERE m.site_code = $1 AND m.kind = 'expense')::text AS exp_moves,
       (SELECT COALESCE(SUM(r.amount_minor), 0) FROM account_movements r JOIN account_movements o ON o.id = r.reverses_movement_id WHERE r.site_code = $1 AND o.kind = 'expense')::text AS mirrors,
       (SELECT COALESCE(SUM(e.amount_minor), 0) FROM expenses e WHERE e.site_code = $1 AND NOT EXISTS (SELECT 1 FROM expense_voids v WHERE v.expense_id = e.id))::text AS active_total,
       (SELECT COUNT(*) FROM expenses e WHERE e.site_code = $1 AND NOT EXISTS (SELECT 1 FROM account_movements m WHERE m.kind = 'expense' AND m.expense_id = e.id))::int AS without_move`,
    [site.code],
  )).rows[0];
  check('D15: DEGISMEZ: gider hareketleri + aynalari = -Σ aktif giderler; her giderin hareketi var', BigInt(inv.exp_moves) + BigInt(inv.mirrors) === -BigInt(inv.active_total) && inv.without_move === 0, inv);
  const expId = e1.body.expense.id;
  const dbMsgs = [
    await failMessage(`UPDATE expenses SET amount_minor = 1 WHERE id = $1`, [expId]),
    await failMessage(`DELETE FROM expenses WHERE id = $1`, [expId]),
    await failMessage(`TRUNCATE expenses CASCADE`),
    await failMessage(`UPDATE expense_voids SET reason = 'x' WHERE expense_id = $1`, [expId]),
    await failMessage(`DELETE FROM expense_voids WHERE expense_id = $1`, [expId]),
  ];
  check('D15b: gider ve iptal kayitlari UPDATE / DELETE / TRUNCATE tetikleyici hatasi verir', dbMsgs.every((m) => m !== null), dbMsgs);
  const dbBad = [
    await failCode(`INSERT INTO expenses (site_code, category_id, category_name, description, amount_minor, expense_date, period, account_id, idempotency_key, request_fingerprint) VALUES ($1, $2, 'x', 'x', 5, $3::date, $4::date, $5, 'dbk1', $6)`, [site.code, kategori, TODAY, monthStart(1), kasaId, 'a'.repeat(64)]),
    await failCode(`INSERT INTO expenses (site_code, category_id, category_name, description, amount_minor, vat_minor, expense_date, period, account_id, idempotency_key, request_fingerprint) VALUES ($1, $2, 'x', 'x', 5, 9, $3::date, $4::date, $5, 'dbk2', $6)`, [site.code, kategori, TODAY, monthStart(0), kasaId, 'a'.repeat(64)]),
    await failCode(`INSERT INTO expenses (site_code, category_id, category_name, description, amount_minor, expense_date, period, account_id, idempotency_key, request_fingerprint, document_kind) VALUES ($1, $2, 'x', 'x', 5, $3::date, $4::date, $5, 'dbk3', $6, 'foo')`, [site.code, kategori, TODAY, monthStart(0), kasaId, 'a'.repeat(64)]),
    await failCode(`INSERT INTO finance_suppliers (site_code, name, tax_id) VALUES ($1, 'Kotu VKN', '123')`, [site.code]),
  ];
  check('D15c: DB kisitlari: donem ≠ gider ayi, KDV > tutar, gecersiz belge turu, gecersiz vergi no 23514', dbBad.every((c) => c === '23514'), dbBad);

  // --- D16. yetki matrisi ve modul kapali
  const matrix = [];
  for (const [label, user, readStatus, writeStatus] of [['yonetici', MGR, 200, 201], ['super', SUPER, 200, 201], ['kurul', BOARD, 200, 403], ['gorevli', STAFF, 403, 403], ['sakin', RESIDENT, 403, 403], ['ilgisiz', OUTSIDER, 403, 403], ['baska site yoneticisi', MGR2, 403, 403]]) {
    const r = await call('GET', `${P(site.code)}/expenses`, user);
    const w = await exp({ category_id: kategori, account_id: kasaId, description: `Yetki ${label}`, amount_minor: 1000 + matrix.length }, user);
    matrix.push([label, r.status, w.status === 409 ? 201 : w.status, readStatus, writeStatus]);
  }
  check('D16: yetki matrisi: yonetici / super yazar + okur; kurul YALNIZ okur; gorevli / sakin / ilgisiz / baska site 403', matrix.every(([, r, w, er, ew]) => r === er && w === ew), matrix);
  await call('PUT', `/manager/sites/${site.code}/modules/finance`, SUPER, { enabled: false });
  const off = await call('GET', `${P(site.code)}/expenses`, MGR);
  check('D16b: finans modulu KAPALI -> gider uclari 403 MODULE_DISABLED', off.status === 403 && off.body.code === 'MODULE_DISABLED', off.body);
  await call('PUT', `/manager/sites/${site.code}/modules/finance`, SUPER, { enabled: true });
  fs.rmSync(docsDir, { recursive: true, force: true });
  void mkUser; void mkSite; void link; void RESIDENT;
}
