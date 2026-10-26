// Toplu yükleme (Faz 2b) planlayıcıları (DB'siz): daireler / kişiler / araçlar. Girdi: doğrulanmış satırlar + sentetik veritabanı anlık görüntüsü.
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md. Gerçek PG doğrulaması: scripts/qa_platform_pg.mjs bölüm bulk_import.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { computePlan, collectApartmentIds } from '../src/modules/bulk_import_plan.js';
import { validateImportBody } from '../src/modules/bulk_import_body.js';

const TODAY = '2026-10-16';

// --- sentetik site: A Blok (Daire 1..6), B Blok (Daire 1..3) --------------------------------------------------------
function makeSnapshot() {
  const blocks = [
    { id: 1, name: 'A Blok' },
    { id: 2, name: 'B Blok' },
  ];
  const apartments = [];
  let id = 100;
  for (const [blockId, count] of [[1, 6], [2, 3]]) {
    for (let n = 1; n <= count; n += 1) {
      id += 1;
      apartments.push({ id, blockId, label: `Daire ${n}`, floor: null, category: null, lsNum: null, lsDen: null, responsible: 'both', hasFinance: false });
    }
  }
  return { blocks, apartments, people: [], residencies: [], vehicles: [] };
}
const aptId = (snapshot, block, n) => snapshot.apartments.find((a) => a.blockId === (block === 'A' ? 1 : 2) && a.label === `Daire ${n}`).id;

let personSeq = 500;
function addPerson(snapshot, over = {}) {
  personSeq += 1;
  const person = { id: personSeq, userCode: null, isActive: true, spName: 'Kişi', spPhone: null, spEmail: null, note: null, uName: null, uPhone: null, uEmail: null, ...over };
  snapshot.people.push(person);
  return person;
}
let residencySeq = 900;
function addResidency(snapshot, person, apartmentId, relation = 'resident') {
  residencySeq += 1;
  snapshot.residencies.push({ id: residencySeq, apartmentId, personId: person.id, relation });
  return residencySeq;
}
let vehicleSeq = 1;
function addVehicle(snapshot, person, plate) {
  vehicleSeq += 1;
  snapshot.vehicles.push({ id: vehicleSeq, personId: person?.id ?? null, plate });
}

/** Satır oluşturucu: [{ ad_soyad: 'x' }, ...] -> doğrulanmış gövde satırları (n = 2, 3, ...). */
function rowsOf(kind, list) {
  const body = { spec_version: 1, rows: list.map((cells, index) => ({ n: index + 2, cells })) };
  return validateImportBody(body, kind).rows;
}
const plan = (kind, snapshot, list, opts = {}) => computePlan({ kind, rows: rowsOf(kind, list), snapshot, today: TODAY, allowOverwrite: opts.allowOverwrite === true });
const issuesOf = (result, n) => result.view.issues.filter((issue) => issue.n === n);
const codesOf = (result, n) => issuesOf(result, n).map((issue) => `${issue.severity[0]}:${issue.code}`);
const statusOf = (result, n) => result.results.find((r) => r.n === n).status;

/** Planı sentetik veritabanına işler (yazıcının yaptığını taklit eder): ikinci planlama "değişiklik yok" olmalı. */
function applyPlan(snapshot, result) {
  const refToId = new Map();
  const pending = [];
  let nextPerson = 7000;
  for (const op of result.ops) {
    switch (op.t) {
      case 'pc': {
        nextPerson += 1;
        refToId.set(op.ref, nextPerson);
        snapshot.people.push({ id: nextPerson, userCode: null, isActive: true, spName: op.name, spPhone: op.phone, spEmail: op.email, note: op.note, uName: null, uPhone: null, uEmail: null });
        break;
      }
      case 'pf': {
        const id = refToId.get(op.ref) ?? Number(op.ref.slice(1));
        const person = snapshot.people.find((p) => p.id === id);
        if (op.field === 'phone') person.spPhone = op.value;
        else if (op.field === 'email') person.spEmail = op.value;
        else person.note = op.value;
        break;
      }
      case 'pr': {
        const person = snapshot.people.find((p) => p.id === Number(op.ref.slice(1)));
        person.isActive = true;
        if (op.name) person.spName = op.name;
        if (op.phone) person.spPhone = op.phone;
        break;
      }
      case 'ra': {
        residencySeq += 1;
        const personId = refToId.get(op.ref) ?? Number(op.ref.slice(1));
        const row = { id: residencySeq, apartmentId: op.aptId, personId, relation: op.relation };
        snapshot.residencies.push(row);
        pending.push({ ref: op.ref, aptId: op.aptId, row });
        break;
      }
      case 'ru': {
        if (op.residencyId === null) {
          pending.find((entry) => entry.ref === op.ref && entry.aptId === op.aptId).row.relation = op.to;
        } else {
          snapshot.residencies.find((r) => r.id === op.residencyId).relation = op.to;
        }
        break;
      }
      case 'va':
        vehicleSeq += 1;
        snapshot.vehicles.push({ id: vehicleSeq, personId: refToId.get(op.ref) ?? Number(op.ref.slice(1)), plate: op.plate });
        break;
      case 'au': {
        const apartment = snapshot.apartments.find((a) => a.id === op.aptId);
        const map = { floor: 'floor', category: 'category', land_share_numerator: 'lsNum', land_share_denominator: 'lsDen', responsible_party: 'responsible' };
        for (const [column, value] of Object.entries(op.set)) apartment[map[column]] = value;
        break;
      }
      default:
        break;
    }
  }
}

// ===============================================================================================================
describe('DAİRELER planlayıcısı', () => {
  it('boş alanlar dolar; 2. yükleme "değişiklik yok" (idempotans); hash aynı dosya için kararlı', () => {
    const snapshot = makeSnapshot();
    const file = [
      { blok: 'A', daire_no: '1', kat: 'Zemin', tip: '3+1', arsa_payi_pay: 35, arsa_payi_payda: 1000, sorumlu: 'Kiracı' },
      { blok: 'Blok A', daire_no: 'Daire 2', kat: '1. kat', tip: '2+1' },
      { blok: 'B Blok', daire_no: '03', kat: 4 },
    ];
    const first = plan('apartments', snapshot, file);
    assert.deepEqual(first.totals, { rows: 3, ok: 3, unchanged: 0, error: 0, with_warnings: 0 });
    assert.equal(first.counts.apartment_update, 3);
    assert.equal(first.counts.cells_set, 5 + 2 + 1);
    assert.equal(first.counts.overwritten_cells, 0);
    assert.equal(first.counts.cells_kept, 0);
    assert.equal(plan('apartments', snapshot, file).previewHash, first.previewHash);
    assert.match(first.previewHash, /^[0-9a-f]{64}$/);
    applyPlan(snapshot, first);
    const apt1 = snapshot.apartments.find((a) => a.id === aptId(snapshot, 'A', 1));
    assert.deepEqual([apt1.floor, apt1.category, apt1.lsNum, apt1.lsDen, apt1.responsible], [0, '3+1', 35, 1000, 'tenant']);
    const second = plan('apartments', snapshot, file);
    assert.deepEqual(second.totals, { rows: 3, ok: 0, unchanged: 3, error: 0, with_warnings: 0 });
    assert.equal(second.ops.length, 0);
    assert.equal(second.counts.apartment_update, 0);
  });

  it('dolu alan varsayılan KORUNUR (VALUE_KEPT); allow_overwrite ile yazılır ve overwritten_cells sayılır', () => {
    const snapshot = makeSnapshot();
    const apt = snapshot.apartments[0];
    Object.assign(apt, { floor: 2, category: '2+1' });
    const file = [{ blok: 'A', daire_no: '1', kat: 5, tip: '3+1', arsa_payi_pay: 35, arsa_payi_payda: 1000 }];
    const kept = plan('apartments', snapshot, file);
    assert.equal(kept.counts.cells_kept, 2);
    assert.equal(kept.counts.cells_set, 2); // yalnız arsa payı çifti (boştu)
    assert.deepEqual(codesOf(kept, 2).sort(), ['w:VALUE_KEPT', 'w:VALUE_KEPT']);
    assert.deepEqual(kept.ops[0].set, { land_share_numerator: 35, land_share_denominator: 1000 });
    const overwritten = plan('apartments', snapshot, file, { allowOverwrite: true });
    assert.equal(overwritten.counts.overwritten_cells, 2); // kat, tip
    assert.equal(overwritten.counts.cells_set, 2);
    assert.equal(overwritten.counts.cells_kept, 0);
    assert.deepEqual(overwritten.ops[0].set, { floor: 5, category: '3+1', land_share_numerator: 35, land_share_denominator: 1000 });
    assert.notEqual(kept.previewHash, overwritten.previewHash);
  });

  it('boş hücre değeri ASLA silmez; yalnız blok+daire olan satır NO_VALUES uyarısıyla "değişiklik yok"', () => {
    const snapshot = makeSnapshot();
    Object.assign(snapshot.apartments[0], { floor: 3, category: 'Dükkan' });
    const result = plan('apartments', snapshot, [
      { blok: 'A', daire_no: '1', kat: null, tip: '', sorumlu: ' ' },
      { blok: 'A', daire_no: '2' },
    ]);
    assert.equal(result.ops.length, 0);
    assert.deepEqual(codesOf(result, 3), ['w:NO_VALUES']);
    assert.equal(statusOf(result, 2), 'unchanged');
    assert.equal(statusOf(result, 3), 'unchanged');
  });

  it('sorumlu: veritabanı varsayılanı "both" boş sayılır (dolar); açık seçim korunur', () => {
    const snapshot = makeSnapshot();
    snapshot.apartments[1].responsible = 'owner';
    const result = plan('apartments', snapshot, [
      { blok: 'A', daire_no: '1', sorumlu: 'Malik' },
      { blok: 'A', daire_no: '2', sorumlu: 'Kiracı' },
    ]);
    assert.deepEqual(result.ops.map((op) => op.set), [{ responsible_party: 'owner' }]);
    assert.deepEqual(codesOf(result, 3), ['w:VALUE_KEPT']);
  });

  it('hata kodları: BLOCK_NOT_FOUND (blok adları sayılır), BLOCK_AMBIGUOUS, APARTMENT_NOT_FOUND (Site Yapısı ipucu), REQUIRED, DUPLICATE_IN_FILE (ikinci satır)', () => {
    const snapshot = makeSnapshot();
    const result = plan('apartments', snapshot, [
      { blok: 'C', daire_no: '1', kat: 1 },
      { blok: 'A', daire_no: '99', kat: 1 },
      { blok: 'B', daire_no: '1', kat: 1 },
      { blok: 'B', daire_no: 'D1', kat: 2 },
      { blok: '', daire_no: '1', kat: 1 },
      { blok: 'B', daire_no: '', kat: 1 },
    ]);
    assert.deepEqual(codesOf(result, 2), ['e:BLOCK_NOT_FOUND']);
    assert.ok(issuesOf(result, 2)[0].message.includes('A Blok') && issuesOf(result, 2)[0].message.includes('B Blok'));
    assert.deepEqual(codesOf(result, 3), ['e:APARTMENT_NOT_FOUND']);
    assert.ok(issuesOf(result, 3)[0].message.includes('Site Yapısı'));
    assert.equal(statusOf(result, 4), 'ok');
    assert.deepEqual(codesOf(result, 5), ['e:DUPLICATE_IN_FILE']);
    assert.ok(issuesOf(result, 5)[0].message.includes('satır 4'));
    assert.deepEqual(codesOf(result, 6), ['e:REQUIRED']);
    assert.deepEqual(codesOf(result, 7), ['e:REQUIRED']);
    assert.equal(result.totals.error, 5);
    // hatalı satırın işlemi yok
    assert.equal(result.ops.length, 1);
    // katlanınca aynı olan iki blok -> belirsiz
    const ambiguous = makeSnapshot();
    ambiguous.blocks.push({ id: 3, name: 'a blok' });
    assert.deepEqual(codesOf(plan('apartments', ambiguous, [{ blok: 'blok a', daire_no: '1', kat: 1 }]), 2), ['e:BLOCK_AMBIGUOUS']);
  });

  it('değer hataları: LAND_SHARE_INVALID (sayı değil / payda 0), FLOOR_INVALID, RESPONSIBLE_INVALID, FORMULA_LIKE, TOO_LONG; hatalı satır HİÇ uygulanmaz', () => {
    const snapshot = makeSnapshot();
    const result = plan('apartments', snapshot, [
      { blok: 'A', daire_no: '1', arsa_payi_pay: 'çok', kat: 'yedinci', sorumlu: 'komşu', tip: '=1+1' },
      { blok: 'A', daire_no: '2', tip: 'x'.repeat(41), arsa_payi_payda: 0 },
      { blok: 'A', daire_no: '3', kat: 4, tip: '2+1' },
    ]);
    assert.deepEqual(codesOf(result, 2).sort(), ['e:FLOOR_INVALID', 'e:FORMULA_LIKE', 'e:LAND_SHARE_INVALID', 'e:RESPONSIBLE_INVALID']);
    assert.deepEqual(codesOf(result, 3).sort(), ['e:LAND_SHARE_INVALID', 'e:TOO_LONG']);
    assert.equal(statusOf(result, 4), 'ok');
    assert.equal(result.ops.length, 1);
    assert.equal(result.ops[0].aptId, aptId(snapshot, 'A', 3));
  });

  it('arsa payı: yalnız biri verilirse DB\'deki diğeriyle birleştirilir; ikisi de boşsa LAND_SHARE_INVALID; pay > payda reddedilir', () => {
    const snapshot = makeSnapshot();
    Object.assign(snapshot.apartments[1], { lsNum: 10, lsDen: 1000 });
    const result = plan('apartments', snapshot, [
      { blok: 'A', daire_no: '1', arsa_payi_pay: 35 }, // DB boş -> payda yok -> geçersiz
      { blok: 'A', daire_no: '2', arsa_payi_pay: 20 }, // DB payda 1000 -> birleşir, ama pay DOLU -> korunur
      { blok: 'A', daire_no: '3', arsa_payi_pay: 50, arsa_payi_payda: 40 }, // pay > payda
      { blok: 'A', daire_no: '4', arsa_payi_pay: 0, arsa_payi_payda: 500 },
    ]);
    assert.deepEqual(codesOf(result, 2), ['e:LAND_SHARE_INVALID']);
    assert.deepEqual(codesOf(result, 3), ['w:VALUE_KEPT']);
    assert.deepEqual(codesOf(result, 4), ['e:LAND_SHARE_INVALID']);
    assert.equal(statusOf(result, 5), 'ok');
    const overwritten = plan('apartments', snapshot, [{ blok: 'A', daire_no: '2', arsa_payi_pay: 20 }], { allowOverwrite: true });
    assert.deepEqual(overwritten.ops[0].set, { land_share_numerator: 20 });
  });

  it('arsa payı toplamı kontrolü (engellemez): tek paydada ve hepsi doluysa Σpay/payda; değilse null', () => {
    const snapshot = makeSnapshot();
    const file = snapshot.apartments.map((a, i) => ({ blok: a.blockId === 1 ? 'A' : 'B', daire_no: String(Number(a.label.split(' ')[1])), arsa_payi_pay: 100, arsa_payi_payda: 1000, _i: i }));
    const rows = file.map(({ _i, ...rest }) => rest);
    const incomplete = plan('apartments', snapshot, rows.slice(0, 3));
    assert.equal(incomplete.view.checks.land_share, null);
    const full = plan('apartments', snapshot, rows);
    assert.deepEqual(full.view.checks.land_share, { sum: 900, denominator: 1000, complete: false, message: '900/1000: eksik olabilir' });
    const exact = plan('apartments', snapshot, rows.map((r, i) => ({ ...r, arsa_payi_pay: i < 8 ? 111 : 112 })));
    assert.equal(exact.view.checks.land_share.complete, true);
    assert.equal(exact.view.checks.land_share.message, '1000/1000 ✓');
    assert.equal(plan('apartments', snapshot, [{ blok: 'A', daire_no: '1', kat: 1 }]).view.checks.land_share, null);
  });

  it('uyarılar: FINANCE_RECORDS yalnız mali alan (tip, arsa payı, sorumlu) değişirse; kat mali alan değil', () => {
    const snapshot = makeSnapshot();
    snapshot.apartments[0].hasFinance = true;
    snapshot.apartments[1].hasFinance = true;
    const result = plan('apartments', snapshot, [
      { blok: 'A', daire_no: '1', tip: '3+1' },
      { blok: 'A', daire_no: '2', kat: 3 },
      { blok: 'A', daire_no: '3', kat: 1 },
    ]);
    assert.deepEqual(codesOf(result, 2), ['w:FINANCE_RECORDS']);
    assert.deepEqual(codesOf(result, 3), []);
    assert.deepEqual(codesOf(result, 4), []);
    assert.equal(result.totals.with_warnings, 1);
    assert.equal(result.totals.error, 0);
  });

  it('ESKİ m² SÜTUNLARI: gövde reddetmez, değerler yazılmaz; dosya başına TEK "m² artık kullanılmıyor" uyarısı; m² mantığı (AREA_UNUSUAL / NET_GT_GROSS / ROUNDED) yok', () => {
    const snapshot = makeSnapshot();
    const result = plan('apartments', snapshot, [
      { blok: 'A', daire_no: '1', kat: 2, brut_m2: '100,456', net_m2: '120' },
      { blok: 'A', daire_no: '2', brut_m2: 4 },
      { blok: 'A', daire_no: '3', kat: 1, net_m2: 'çok' }, // eskiden NUMBER_INVALID hatasıydı; artık yok sayılır
    ]);
    assert.equal(result.totals.error, 0);
    assert.deepEqual(codesOf(result, 2), ['w:AREA_COLUMN_IGNORED']);
    assert.equal(issuesOf(result, 2)[0].field, null);
    assert.match(issuesOf(result, 2)[0].message, /m²/);
    assert.deepEqual(codesOf(result, 3), ['w:NO_VALUES'], 'ikinci uyarı yok');
    assert.deepEqual(codesOf(result, 4), []);
    assert.deepEqual(result.ops.map((op) => op.set), [{ floor: 2 }, { floor: 1 }]);
    assert.ok(result.ops.every((op) => !('gross_area_m2' in op.set) && !('net_area_m2' in op.set)));
    // başka türler eski anahtarı hâlâ reddeder (tanımsız sütun)
    assert.throws(() => rowsOf('people', [{ ad_soyad: 'Ali', brut_m2: 5 }]), (error) => error.code === 'INVALID_BODY');
  });

  it('hash: veritabanı değeri değişirse değişir; ileti metni ve satır sırası dışı değişmezler', () => {
    const snapshot = makeSnapshot();
    const file = [{ blok: 'A', daire_no: '1', kat: 2 }, { blok: 'A', daire_no: '2', kat: 3 }];
    const base = plan('apartments', snapshot, file).previewHash;
    snapshot.apartments[0].floor = 9;
    assert.notEqual(plan('apartments', snapshot, file).previewHash, base);
    const other = makeSnapshot();
    other.apartments[5].category = 'başka daire değişti'; // dosyada olmayan daire hash'i etkilemez
    assert.equal(plan('apartments', other, file).previewHash, base);
  });

  it('collectApartmentIds: dosyanın başvurduğu daireler, artan ve tekil', () => {
    const snapshot = makeSnapshot();
    const rows = rowsOf('apartments', [{ blok: 'B', daire_no: '2' }, { blok: 'A', daire_no: '1' }, { blok: 'A', daire_no: '1' }, { blok: 'X', daire_no: '1' }, { blok: 'A', daire_no: '77' }]);
    assert.deepEqual(collectApartmentIds(rows, snapshot), [aptId(snapshot, 'A', 1), aptId(snapshot, 'B', 2)]);
  });
});

// ===============================================================================================================
describe('KİŞİLER planlayıcısı', () => {
  it('yeni kişi: hesapsız oluşur, daire + ilişki + tarih + plakalar; ikinci yükleme "değişiklik yok"', () => {
    const snapshot = makeSnapshot();
    const file = [
      { ad_soyad: 'Ahmet Yılmaz', telefon: '0 (555) 123 45 67', e_posta: 'ahmet@example.com', blok: 'A', daire_no: '3', iliski: 'Malik', giris_tarihi: '15.03.2021', plaka: '34 ABC 123, 06 XY 789', not: 'ilk not' },
      { ad_soyad: 'Ayşe Demir', blok: 'A', daire_no: '3', iliski: 'Kiracı' },
      { ad_soyad: 'Veli Demir', blok: 'A', daire_no: '3', iliski: 'Aile' },
      { ad_soyad: 'Zeynep Kaya', e_posta: 'zeynep@example.com' },
    ];
    const first = plan('people', snapshot, file);
    assert.deepEqual(first.totals, { rows: 4, ok: 4, unchanged: 0, error: 0, with_warnings: 0 });
    assert.equal(first.counts.people_create, 4);
    assert.equal(first.counts.residency_add, 3);
    assert.equal(first.counts.vehicle_add, 2);
    assert.equal(first.counts.account_create, 3, 'hesap açılacak kişi = daire ilişkisi eklenenler (dairesiz Zeynep hesap almaz)');
    const pc = first.ops.find((op) => op.t === 'pc');
    assert.deepEqual([pc.name, pc.phone, pc.email, pc.note], ['Ahmet Yılmaz', '+905551234567', 'ahmet@example.com', 'ilk not']);
    assert.equal(pc.n, 2, 'op kaynak satır numarasını taşır (sonuçta kullanıcı adı satırla eşleşir)');
    const ra = first.ops.find((op) => op.t === 'ra');
    assert.deepEqual([ra.relation, ra.moveIn], ['owner', '2021-03-15']);
    assert.equal(first.ops.filter((op) => op.t === 'ra').find((op) => op.ref === 'new:3').moveIn, null); // boş tarih = bugün (yazarken)
    assert.equal(first.view.samples[0].summary, 'Ahmet Yılmaz → A Blok - Daire 3 (Malik) + 2 plaka');
    applyPlan(snapshot, first);
    const second = plan('people', snapshot, file);
    assert.deepEqual(second.totals, { rows: 4, ok: 0, unchanged: 4, error: 0, with_warnings: 0 });
    assert.equal(second.ops.length, 0);
    assert.equal(second.counts.people_create, 0);
    assert.equal(second.counts.residency_unchanged, 3);
    assert.equal(second.counts.vehicle_unchanged, 2);
    assert.equal(second.counts.account_create, 0, 'ikinci yükleme yeni hesap açmaz');
  });

  it('eşleşme: e-posta -> (daire + ad) -> (ad + telefon, e-posta ve daire yokken); NO_IDENTIFIER; telefon TEK BAŞINA eşleştirmez', () => {
    const snapshot = makeSnapshot();
    const emailPerson = addPerson(snapshot, { spName: 'Ali Veli', spEmail: 'ali@example.com' });
    const residentPerson = addPerson(snapshot, { spName: 'Mehmet Öz', spPhone: '+905321112233' });
    addResidency(snapshot, residentPerson, aptId(snapshot, 'A', 1));
    const phonePerson = addPerson(snapshot, { spName: 'Fatma Çelik', spPhone: '+905443332211' });
    const result = plan('people', snapshot, [
      { ad_soyad: 'Başka Ad', e_posta: 'ALI@example.com' }, // e-posta büyük/küçük harf duyarsız -> Ali Veli
      { ad_soyad: 'mehmet oz', blok: 'A', daire_no: '1' }, // daire + katlanmış ad
      { ad_soyad: 'Fatma Çelik', telefon: '544 333 22 11' }, // ad + telefon
      { ad_soyad: 'Kemal Sunal', telefon: '544 333 22 11' }, // yalnız telefon aynı -> YENİ kişi
      { ad_soyad: 'Hiçbiri' }, // tanımlayıcı yok
    ]);
    assert.equal(result.view.samples.length > 0, true);
    const ref = (n) => result.results.find((r) => r.n === n);
    assert.ok(ref(2).sig.includes(`p${emailPerson.id}`));
    assert.ok(ref(3).sig.includes(`p${residentPerson.id}`));
    assert.ok(ref(4).sig.includes(`p${phonePerson.id}`));
    assert.ok(ref(5).sig.includes('new|'));
    assert.deepEqual(codesOf(result, 6), ['e:NO_IDENTIFIER']);
    assert.equal(result.counts.people_create, 1);
    assert.equal(result.counts.people_link, 3);
  });

  it('hesapsız kişi: BOŞ alanlar dolar, dolu alana dokunulmaz; hesaplı kişiye hiç dokunulmaz', () => {
    const snapshot = makeSnapshot();
    const plain = addPerson(snapshot, { spName: 'Ali Veli', spEmail: 'ali@example.com', spPhone: '+905551110000', note: null });
    const account = addPerson(snapshot, { userCode: 42, spName: null, uName: 'Hesaplı Kişi', uEmail: 'hesap@example.com', uPhone: '05552223344' });
    const result = plan('people', snapshot, [
      { ad_soyad: 'Ali Veli', e_posta: 'ali@example.com', telefon: '0555 999 88 77', not: 'yeni not' },
      { ad_soyad: 'Hesaplı Kişi', e_posta: 'hesap@example.com', telefon: '0555 000 00 00', not: 'ezilmez' },
    ]);
    const fills = result.ops.filter((op) => op.t === 'pf');
    assert.deepEqual(fills.map((op) => [op.ref, op.field]), [[`p${plain.id}`, 'note']]); // telefon DOLU -> dokunulmaz; e-posta zaten aynı
    assert.equal(statusOf(result, 3), 'unchanged'); // hesaplı: hiçbir alan değişmez
    assert.ok(!result.ops.some((op) => op.ref === `p${account.id}`));
    assert.equal(result.counts.people_filled, 1);
  });

  it('hesaplı kişiye YENİ daire eklenmez (ACCOUNT_NEW_APARTMENT); mevcut dairedeki resident ilişkisi yükseltilir; plaka eklenir', () => {
    const snapshot = makeSnapshot();
    const account = addPerson(snapshot, { userCode: 42, spName: null, uName: 'Hesaplı Kişi', uEmail: 'hesap@example.com' });
    addResidency(snapshot, account, aptId(snapshot, 'A', 1), 'resident');
    const result = plan('people', snapshot, [
      { ad_soyad: 'Hesaplı Kişi', e_posta: 'hesap@example.com', blok: 'A', daire_no: '2', iliski: 'Malik', plaka: '34 ABC 123' },
      { ad_soyad: 'Hesaplı Kişi', e_posta: 'hesap@example.com', blok: 'A', daire_no: '1', iliski: 'Malik' },
    ]);
    assert.deepEqual(codesOf(result, 2), ['w:ACCOUNT_NEW_APARTMENT']);
    assert.deepEqual(result.ops.filter((op) => op.t === 'va').map((op) => op.plate), ['34ABC123']);
    assert.ok(!result.ops.some((op) => op.t === 'ra'));
    const upgrade = result.ops.find((op) => op.t === 'ru');
    assert.deepEqual([upgrade.from, upgrade.to, upgrade.aptId], ['resident', 'owner', aptId(snapshot, 'A', 1)]);
    assert.equal(result.counts.residency_upgrade, 1);
  });

  it('ilişki: resident -> açık ilişkiye yükselir; açık ilişki farklıysa değişmez (RELATION_DIFFERS); boş ilişki görüş yoktur', () => {
    const snapshot = makeSnapshot();
    const a = addPerson(snapshot, { spName: 'Ali Sakin', spEmail: 'a@example.com' });
    const b = addPerson(snapshot, { spName: 'Berk Kiracı', spEmail: 'b@example.com' });
    const c = addPerson(snapshot, { spName: 'Can Malik', spEmail: 'c@example.com' });
    addResidency(snapshot, a, aptId(snapshot, 'A', 1), 'resident');
    addResidency(snapshot, b, aptId(snapshot, 'A', 2), 'tenant');
    addResidency(snapshot, c, aptId(snapshot, 'A', 3), 'owner');
    const result = plan('people', snapshot, [
      { ad_soyad: 'Ali Sakin', e_posta: 'a@example.com', blok: 'A', daire_no: '1', iliski: 'Malik' },
      { ad_soyad: 'Berk Kiracı', e_posta: 'b@example.com', blok: 'A', daire_no: '2', iliski: 'Malik' },
      { ad_soyad: 'Can Malik', e_posta: 'c@example.com', blok: 'A', daire_no: '3' },
      { ad_soyad: 'Can Malik', e_posta: 'c@example.com', blok: 'A', daire_no: '3', iliski: 'Sakin' },
    ]);
    assert.deepEqual(result.ops.filter((op) => op.t === 'ru').map((op) => op.to), ['owner']);
    assert.deepEqual(codesOf(result, 3), ['w:RELATION_DIFFERS']);
    assert.equal(statusOf(result, 3), 'unchanged');
    assert.equal(statusOf(result, 4), 'unchanged');
    assert.deepEqual(codesOf(result, 4), []);
    assert.equal(statusOf(result, 5), 'unchanged');
    assert.equal(result.counts.residency_unchanged, 2);
  });

  it('ikinci malik/kiracı RELATION_TAKEN (dosyada ve veritabanında); "Aile" yazılırsa kabul; hatalı satırın kişisi de oluşmaz', () => {
    const snapshot = makeSnapshot();
    const owner = addPerson(snapshot, { spName: 'Mevcut Malik', spEmail: 'm@example.com' });
    addResidency(snapshot, owner, aptId(snapshot, 'A', 1), 'owner');
    const result = plan('people', snapshot, [
      { ad_soyad: 'Yeni Malik', e_posta: 'y@example.com', blok: 'A', daire_no: '1', iliski: 'Malik' }, // DB'de malik var
      { ad_soyad: 'Eş Hissedar', e_posta: 'e@example.com', blok: 'A', daire_no: '1', iliski: 'Aile' },
      { ad_soyad: 'İlk Malik', e_posta: 'i@example.com', blok: 'A', daire_no: '2', iliski: 'Malik' },
      { ad_soyad: 'İkinci Malik', e_posta: 'k@example.com', blok: 'A', daire_no: '2', iliski: 'Malik' }, // dosyada ikinci
    ]);
    assert.deepEqual(codesOf(result, 2), ['e:RELATION_TAKEN']);
    assert.equal(statusOf(result, 3), 'ok');
    assert.equal(statusOf(result, 4), 'ok');
    assert.deepEqual(codesOf(result, 5), ['e:RELATION_TAKEN']);
    assert.equal(result.ops.filter((op) => op.t === 'pc').length, 2);
    assert.ok(issuesOf(result, 2)[0].message.includes('Aile'));
  });

  it('dosya içi yineleme: aynı kişi + daire + ilişki -> DUPLICATE_IN_FILE uyarısı ve plakalar birleşir; çelişen ilişki -> CONFLICTING_ROWS', () => {
    const snapshot = makeSnapshot();
    const result = plan('people', snapshot, [
      { ad_soyad: 'Ahmet Yılmaz', blok: 'A', daire_no: '1', iliski: 'Malik', plaka: '34 ABC 123' },
      { ad_soyad: 'ahmet yilmaz', blok: 'A', daire_no: '1', iliski: 'Malik', plaka: '34 ABC 123, 06 XY 789', telefon: '0555 111 22 33' },
      { ad_soyad: 'Ahmet Yılmaz', blok: 'A', daire_no: '1', iliski: 'Kiracı' },
    ]);
    assert.equal(result.counts.people_create, 1);
    assert.deepEqual(codesOf(result, 3), ['w:DUPLICATE_IN_FILE']);
    assert.deepEqual(result.ops.filter((op) => op.t === 'va').map((op) => op.plate), ['34ABC123', '06XY789']);
    assert.ok(result.ops.some((op) => op.t === 'pf' && op.field === 'phone' && op.ref === 'new:2'), 'ikinci satırın boş telefonu doldurur');
    assert.deepEqual(codesOf(result, 4), ['e:CONFLICTING_ROWS']);
    assert.ok(issuesOf(result, 4)[0].message.includes('e-posta ya da telefon'));
    assert.equal(result.counts.vehicle_unchanged, 1);
  });

  it('baba/oğul: aynı ad + daire, iletişim bilgisi FARKLIYSA ayrı kişiler; yoksa belirsiz (çelişki); mevcut iki aday -> PERSON_AMBIGUOUS', () => {
    const snapshot = makeSnapshot();
    const result = plan('people', snapshot, [
      { ad_soyad: 'Ali Yıldız', e_posta: 'baba@example.com', blok: 'A', daire_no: '1', iliski: 'Malik' },
      { ad_soyad: 'Ali Yıldız', e_posta: 'ogul@example.com', blok: 'A', daire_no: '1', iliski: 'Aile' },
      { ad_soyad: 'Veli Kara', blok: 'A', daire_no: '2', iliski: 'Malik' },
      { ad_soyad: 'Veli Kara', blok: 'A', daire_no: '2', iliski: 'Aile' },
    ]);
    assert.equal(statusOf(result, 2), 'ok');
    assert.equal(statusOf(result, 3), 'ok');
    assert.equal(result.ops.filter((op) => op.t === 'pc' && op.name === 'Ali Yıldız').length, 2);
    assert.deepEqual(codesOf(result, 5), ['e:CONFLICTING_ROWS']);

    const snap2 = makeSnapshot();
    const p1 = addPerson(snap2, { spName: 'Ali Yıldız' });
    const p2 = addPerson(snap2, { spName: 'Ali Yildiz' });
    addResidency(snap2, p1, aptId(snap2, 'A', 1));
    addResidency(snap2, p2, aptId(snap2, 'A', 1));
    const ambiguous = plan('people', snap2, [{ ad_soyad: 'ALİ YILDIZ', blok: 'A', daire_no: '1' }]);
    assert.deepEqual(codesOf(ambiguous, 2), ['e:PERSON_AMBIGUOUS']);
    const withEmail = plan('people', snap2, [{ ad_soyad: 'Ali Yıldız', e_posta: 'yeni@example.com', blok: 'A', daire_no: '1' }]);
    assert.equal(withEmail.counts.people_create, 0); // e-posta eşleşmedi, aday ikiye bölündü -> hâlâ belirsiz
    assert.deepEqual(codesOf(withEmail, 2), ['e:PERSON_AMBIGUOUS']);
  });

  it('pasif kişi yalnız e-posta ile bulunur ve yeniden etkinleştirilir (REACTIVATE_PERSON); ad ve telefon dosyadan yazılır', () => {
    const snapshot = makeSnapshot();
    const old = addPerson(snapshot, { isActive: false, spName: 'Eski Ad', spEmail: 'eski@example.com', spPhone: '+905550000000' });
    const result = plan('people', snapshot, [{ ad_soyad: 'Yeni Ad', e_posta: 'eski@example.com', telefon: '0555 111 22 33', blok: 'B', daire_no: '2', iliski: 'Kiracı' }]);
    assert.deepEqual(codesOf(result, 2), ['w:REACTIVATE_PERSON']);
    const reactivate = result.ops.find((op) => op.t === 'pr');
    assert.deepEqual([reactivate.ref, reactivate.name, reactivate.phone], [`p${old.id}`, 'Yeni Ad', '+905551112233']);
    assert.equal(result.counts.people_reactivate, 1);
    assert.equal(result.counts.residency_add, 1);
    assert.equal(result.counts.people_create, 0);
    // pasif kişi ad ile (e-postasız) BULUNMAZ
    const byName = plan('people', snapshot, [{ ad_soyad: 'Eski Ad', telefon: '0555 000 00 00' }]);
    assert.equal(byName.counts.people_create, 1);
    // reaktivasyon sonrası idempotans
    applyPlan(snapshot, result);
    assert.equal(plan('people', snapshot, [{ ad_soyad: 'Yeni Ad', e_posta: 'eski@example.com', telefon: '0555 111 22 33', blok: 'B', daire_no: '2', iliski: 'Kiracı' }]).totals.unchanged, 1);
  });

  it('plaka: geçersiz / sitede başkasında / dosyada başka kişide ATLANIR (uyarı), kişi yazılır; aynı kişide mevcut plaka "değişiklik yok"', () => {
    const snapshot = makeSnapshot();
    const other = addPerson(snapshot, { spName: 'Plaka Sahibi', spEmail: 'p@example.com' });
    const self = addPerson(snapshot, { spName: 'Kendi Plakası', spEmail: 's@example.com' });
    addVehicle(snapshot, other, '34ABC123');
    addVehicle(snapshot, self, '06XY789');
    const result = plan('people', snapshot, [
      { ad_soyad: 'Yeni Kişi', e_posta: 'y@example.com', plaka: '34 ABC 123, XX, 35 DE 456' },
      { ad_soyad: 'Başka Kişi', e_posta: 'b@example.com', plaka: '35 DE 456' },
      { ad_soyad: 'Kendi Plakası', e_posta: 's@example.com', plaka: '06 XY 789' },
    ]);
    assert.deepEqual(codesOf(result, 2).sort(), ['w:PLATE_EXISTS', 'w:PLATE_INVALID']);
    assert.equal(statusOf(result, 2), 'ok'); // kişi yazılır
    assert.deepEqual(codesOf(result, 3), ['w:PLATE_DUP_IN_FILE']);
    assert.equal(statusOf(result, 3), 'ok');
    assert.deepEqual(codesOf(result, 4), []);
    assert.equal(statusOf(result, 4), 'unchanged');
    assert.deepEqual(result.ops.filter((op) => op.t === 'va').map((op) => op.plate), ['35DE456']);
    assert.equal(result.counts.vehicle_unchanged, 1);
    assert.equal(result.totals.with_warnings, 2);
  });

  it('satır hataları: APARTMENT_REQUIRED, daire/blok bulunamadı, EMAIL_INVALID, PHONE_INVALID, NAME, tarih, ilişki, TOO_MANY_PLATES, FORMULA_LIKE; hatalı satır hiçbir kişi oluşturmaz', () => {
    const snapshot = makeSnapshot();
    const result = plan('people', snapshot, [
      { ad_soyad: 'A', e_posta: 'x@y.com' },
      { ad_soyad: 'Ali Veli', e_posta: 'bozuk' },
      { ad_soyad: 'Ali Veli', e_posta: 'a@b.com', blok: 'A' },
      { ad_soyad: 'Ali Veli', e_posta: 'a@b.com', blok: 'Z', daire_no: '1' },
      { ad_soyad: 'Ali Veli', e_posta: 'a@b.com', blok: 'A', daire_no: '42' },
      { ad_soyad: 'Ali Veli', e_posta: 'a@b.com', blok: 'A', daire_no: '1', iliski: 'patron', giris_tarihi: '31.02.2021' },
      { ad_soyad: 'Ali Veli', e_posta: 'a@b.com', telefon: '123' },
      { ad_soyad: 'Ali Veli', e_posta: 'a@b.com', plaka: '1,2,3,4,5,6' },
      { ad_soyad: '=cmd|calc', e_posta: 'a@b.com' },
      { ad_soyad: 'Ali Veli', e_posta: '=x@y.com' },
      { ad_soyad: 'Ali Veli', e_posta: 'daire@ahbu.local' },
      { e_posta: 'a@b.com' },
    ]);
    const expected = {
      2: ['e:NAME_INVALID'],
      3: ['e:EMAIL_INVALID'],
      4: ['e:APARTMENT_REQUIRED'],
      5: ['e:BLOCK_NOT_FOUND'],
      6: ['e:APARTMENT_NOT_FOUND'],
      7: ['e:DATE_INVALID', 'e:RELATION_INVALID'],
      8: ['e:PHONE_INVALID'],
      9: ['e:TOO_MANY_PLATES'],
      10: ['e:FORMULA_LIKE'],
      11: ['e:FORMULA_LIKE'],
      12: ['e:EMAIL_INTERNAL'],
      13: ['e:REQUIRED'],
    };
    for (const [n, codes] of Object.entries(expected)) {
      assert.deepEqual(codesOf(result, Number(n)).sort(), codes, `satır ${n}`);
    }
    assert.equal(result.totals.error, 12);
    assert.equal(result.ops.length, 0);
    assert.equal(result.counts.people_create, 0);
  });

  it('gelecek giriş tarihi FUTURE_DATE uyarısı; ilişki/tarih daire yokken yok sayılır (hata/uyarı yok)', () => {
    const snapshot = makeSnapshot();
    const result = plan('people', snapshot, [
      { ad_soyad: 'Ali Veli', e_posta: 'a@b.com', blok: 'A', daire_no: '1', giris_tarihi: '01.12.2026' },
      { ad_soyad: 'Veli Ali', e_posta: 'v@b.com', iliski: 'saçma', giris_tarihi: 'dün' },
    ]);
    assert.deepEqual(codesOf(result, 2), ['w:FUTURE_DATE']);
    assert.equal(statusOf(result, 3), 'ok');
    assert.deepEqual(codesOf(result, 3), []);
  });

  it('veritabanındaki gerçek sıra/kimlik değişirse hash değişir; ileti metni hash\'e girmez', () => {
    const snapshot = makeSnapshot();
    const file = [{ ad_soyad: 'Ali Veli', e_posta: 'a@b.com', blok: 'A', daire_no: '1' }];
    const before = plan('people', snapshot, file).previewHash;
    addPerson(snapshot, { spName: 'Ali Veli', spEmail: 'a@b.com' }); // önizleme ile commit arasında aynı e-postayla kişi eklendi
    assert.notEqual(plan('people', snapshot, file).previewHash, before);
  });
});

// ===============================================================================================================
describe('ARAÇLAR planlayıcısı', () => {
  function vehicleWorld() {
    const snapshot = makeSnapshot();
    const solo = addPerson(snapshot, { spName: 'Tek Sakin', spEmail: 'tek@example.com' });
    addResidency(snapshot, solo, aptId(snapshot, 'A', 1));
    const p1 = addPerson(snapshot, { spName: 'Birinci Sakin' });
    const p2 = addPerson(snapshot, { spName: 'İkinci Sakin' });
    addResidency(snapshot, p1, aptId(snapshot, 'A', 2));
    addResidency(snapshot, p2, aptId(snapshot, 'A', 2));
    return { snapshot, solo, p1, p2 };
  }

  it('sahibi bul: e-posta; yoksa dairenin TEK sakini; çoksa ad_soyad; belirsiz/bulunamadı hataları', () => {
    const { snapshot, solo, p1 } = vehicleWorld();
    const result = plan('vehicles', snapshot, [
      { plaka: '34 ABC 123', e_posta: 'tek@example.com' },
      { plaka: '34 ABC 124', blok: 'A', daire_no: '1' },
      { plaka: '34 ABC 125', blok: 'A', daire_no: '2', ad_soyad: 'birinci sakin' },
      { plaka: '34 ABC 126', blok: 'A', daire_no: '2' },
      { plaka: '34 ABC 127', blok: 'A', daire_no: '2', ad_soyad: 'Üçüncü Kişi' },
      { plaka: '34 ABC 128', blok: 'A', daire_no: '4' },
      { plaka: '34 ABC 129' },
      { plaka: '34 ABC 130', e_posta: 'yok@example.com' },
    ]);
    assert.equal(result.ops.filter((op) => op.t === 'va').length, 3);
    assert.deepEqual(result.ops.filter((op) => op.t === 'va').map((op) => op.ref), [`p${solo.id}`, `p${solo.id}`, `p${p1.id}`]);
    assert.deepEqual(codesOf(result, 5), ['e:PERSON_AMBIGUOUS']);
    assert.deepEqual(codesOf(result, 6), ['e:PERSON_NOT_FOUND']);
    assert.deepEqual(codesOf(result, 7), ['e:PERSON_NOT_FOUND']);
    assert.deepEqual(codesOf(result, 8), ['e:PERSON_NOT_FOUND']);
    assert.deepEqual(codesOf(result, 9), ['e:PERSON_NOT_FOUND']);
    assert.equal(result.counts.vehicle_add, 3);
    assert.equal(result.counts.people_link, 2);
  });

  it('plaka kuralları: zorunlu; mevcut aynı kişide "değişiklik yok"; başkasında / dosyada başka kişide atlanır; hepsi atlanırsa HATA, biri eklenirse uyarı', () => {
    const { snapshot, solo, p1 } = vehicleWorld();
    addVehicle(snapshot, solo, '06XY789');
    addVehicle(snapshot, p1, '35DE456');
    const result = plan('vehicles', snapshot, [
      { plaka: '', e_posta: 'tek@example.com' },
      { plaka: '06 XY 789', e_posta: 'tek@example.com' }, // aynı kişide mevcut
      { plaka: '35 DE 456', e_posta: 'tek@example.com' }, // başkasında -> hepsi atlandı -> hata
      { plaka: '35 DE 456, 16 AB 111', e_posta: 'tek@example.com' }, // biri eklenir -> uyarı
      { plaka: 'XX', e_posta: 'tek@example.com' }, // geçersiz, tek -> hata
      { plaka: '16 AB 111', blok: 'A', daire_no: '2', ad_soyad: 'Birinci Sakin' }, // dosyada başka kişide
    ]);
    assert.deepEqual(codesOf(result, 2), ['e:PLATE_REQUIRED']);
    assert.equal(statusOf(result, 3), 'unchanged');
    assert.deepEqual(codesOf(result, 4), ['e:PLATE_EXISTS']);
    assert.equal(statusOf(result, 4), 'error');
    assert.deepEqual(codesOf(result, 5), ['w:PLATE_EXISTS']);
    assert.equal(statusOf(result, 5), 'ok');
    assert.deepEqual(codesOf(result, 6), ['e:PLATE_INVALID']);
    assert.deepEqual(codesOf(result, 7), ['e:PLATE_DUP_IN_FILE']);
    assert.equal(result.counts.vehicle_add, 1);
    assert.equal(result.counts.vehicle_unchanged, 1);
  });

  it('araç notu araca yazılır; ikinci yükleme "değişiklik yok"', () => {
    const { snapshot } = vehicleWorld();
    const file = [{ plaka: '34 ABC 123', blok: 'A', daire_no: '1', not: 'ziyaretçi aracı' }];
    const first = plan('vehicles', snapshot, file);
    assert.equal(first.ops[0].note, 'ziyaretçi aracı');
    applyPlan(snapshot, first);
    const second = plan('vehicles', snapshot, file);
    assert.equal(second.totals.unchanged, 1);
    assert.equal(second.ops.length, 0);
  });
});
