// Mevcut parola doğrulaması (hesap silme / veri dışa aktarma): PATCH /me ile PAYLAŞILAN izleyici, rezervasyonlu (paralel tahmin güvenli) sayım,
// kodlar ve sırayla gözlenen davranışın PATCH /me ile uyumu (DB'siz; sahte kullanıcı + sahte bcrypt).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import {
  createFailureTracker,
  passwordChangeFailureTracker,
  passwordChangeThrottleKey,
} from '../src/middlewares/login_throttle.js';
import {
  MAX_CURRENT_PASSWORD_LENGTH,
  passwordGuardDeps,
  verifyCurrentPassword,
} from '../src/modules/account_password_guard.js';

const HASH = bcrypt.hashSync('Dogru-Parola-1', 4);

function makeDeps(overrides = {}) {
  const stats = { compares: 0, loads: 0 };
  const deps = {
    tracker: createFailureTracker({ maxFailures: 5, windowMs: 15 * 60 * 1000, lockMs: 15 * 60 * 1000 }),
    loadUser: async () => {
      stats.loads += 1;
      return { password_hash: HASH, deleted_at: null };
    },
    compare: async (plain, hash) => {
      stats.compares += 1;
      await new Promise((resolve) => setTimeout(resolve, 5)); // asenkron (gerçek bcrypt gibi)
      return bcrypt.compare(plain, hash);
    },
    ...overrides,
  };
  return { deps, stats };
}

const attempt = async (deps, password, userCode = 12345) => {
  try {
    await verifyCurrentPassword({ userCode, currentPassword: password }, deps);
    return 'ok';
  } catch (error) {
    return error.code;
  }
};

describe('mevcut parola doğrulaması: paylaşım ve kodlar', () => {
  it('varsayılan izleyici PATCH /me ile AYNI nesne ve AYNI anahtar (u:<user_code>): bütçe ortaktır', () => {
    assert.equal(passwordGuardDeps.tracker, passwordChangeFailureTracker);
    assert.equal(passwordChangeThrottleKey(12345), 'u:12345');
  });

  it('doğru parola: geçer, sayaç sıfırlanır (önceki hatalar silinir)', async () => {
    const { deps } = makeDeps();
    assert.equal(await attempt(deps, 'yanlis'), 'CURRENT_PASSWORD_INVALID');
    assert.equal(await attempt(deps, 'yanlis'), 'CURRENT_PASSWORD_INVALID');
    assert.equal(deps.tracker.size(), 1);
    assert.equal(await attempt(deps, 'Dogru-Parola-1'), 'ok');
    assert.equal(deps.tracker.size(), 0, 'başarıda sayaç temizlenir');
  });

  it('parola baştaki / sondaki boşlukla da çalışır (giriş parolayı trim eder; saklananlar trim edilmiştir)', async () => {
    const { deps } = makeDeps();
    assert.equal(await attempt(deps, '  Dogru-Parola-1  '), 'ok');
  });

  it('eksik / boş / yalnız boşluk -> CURRENT_PASSWORD_REQUIRED ve sayaç ilerlemez, veritabanına dokunulmaz', async () => {
    const { deps, stats } = makeDeps();
    for (const value of [undefined, null, '', '   ']) {
      assert.equal(await attempt(deps, value), 'CURRENT_PASSWORD_REQUIRED', String(value));
    }
    assert.equal(stats.loads, 0);
    assert.equal(deps.tracker.size(), 0);
  });

  it('metin olmayan değerler (sayı, nesne, dizi) geçersiz sayılır ve hata hakkı tüketir; karşılaştırma yapılmaz', async () => {
    const { deps, stats } = makeDeps();
    for (const value of [12345, { a: 1 }, ['x'], true]) {
      assert.equal(await attempt(deps, value), 'CURRENT_PASSWORD_INVALID', JSON.stringify(value));
    }
    assert.equal(stats.compares, 0);
  });

  it('aşırı uzun girdi karşılaştırılmaz (CPU koruması) ama geçersiz sayılır', async () => {
    const { deps, stats } = makeDeps();
    assert.equal(await attempt(deps, 'a'.repeat(MAX_CURRENT_PASSWORD_LENGTH + 1)), 'CURRENT_PASSWORD_INVALID');
    assert.equal(stats.compares, 0);
  });

  it('silinmiş / bulunamayan hesap -> 401 ACCOUNT_DELETED ("parola hatalı" değil) ve sayaç temizlenir', async () => {
    const deleted = makeDeps({ loadUser: async () => ({ password_hash: '!x', deleted_at: new Date() }) });
    assert.equal(await attempt(deleted.deps, 'Dogru-Parola-1'), 'ACCOUNT_DELETED');
    assert.equal(deleted.deps.tracker.size(), 0);
    const missing = makeDeps({ loadUser: async () => null });
    assert.equal(await attempt(missing.deps, 'x'), 'ACCOUNT_DELETED');
  });

  it('parola özeti boş hesapta bile karşılaştırma yapılır (zamanlama) ve hata dönülür', async () => {
    const { deps, stats } = makeDeps({ loadUser: async () => ({ password_hash: '', deleted_at: null }) });
    assert.equal(await attempt(deps, 'x'), 'CURRENT_PASSWORD_INVALID');
    assert.equal(stats.compares, 1);
  });
});

describe('mevcut parola doğrulaması: kilit (PATCH /me ile aynı sıralı davranış)', () => {
  it('5 hatalı deneme: 1-4 -> 400 INVALID, 5. -> 429 LOCKED; 6. istek karşılaştırmasız 429; doğru parola da kilitliyken reddedilir', async () => {
    const { deps, stats } = makeDeps();
    const codes = [];
    for (let i = 0; i < 5; i += 1) codes.push(await attempt(deps, 'yanlis'));
    assert.deepEqual(codes, ['CURRENT_PASSWORD_INVALID', 'CURRENT_PASSWORD_INVALID', 'CURRENT_PASSWORD_INVALID', 'CURRENT_PASSWORD_INVALID', 'CURRENT_PASSWORD_LOCKED']);
    const comparesBefore = stats.compares;
    assert.equal(await attempt(deps, 'yanlis'), 'CURRENT_PASSWORD_LOCKED');
    assert.equal(await attempt(deps, 'Dogru-Parola-1'), 'CURRENT_PASSWORD_LOCKED');
    assert.equal(stats.compares, comparesBefore, 'kilitliyken bcrypt çalıştırılmaz');
  });

  it('kilit hatası retry_after_seconds taşır', async () => {
    const { deps } = makeDeps();
    for (let i = 0; i < 5; i += 1) await attempt(deps, 'yanlis');
    try {
      await verifyCurrentPassword({ userCode: 12345, currentPassword: 'x' }, deps);
      assert.fail('kilitli olmalıydı');
    } catch (error) {
      assert.equal(error.statusCode, 429);
      assert.ok(error.extra.retry_after_seconds >= 1 && error.extra.retry_after_seconds <= 15 * 60);
    }
  });

  it('5. denemede DOĞRU parola kilidi aşar ve sayacı sıfırlar (PATCH /me ile aynı)', async () => {
    const { deps } = makeDeps();
    for (let i = 0; i < 4; i += 1) await attempt(deps, 'yanlis');
    assert.equal(await attempt(deps, 'Dogru-Parola-1'), 'ok');
    assert.equal(deps.tracker.size(), 0);
  });

  it('kilit hesap bazlıdır: başka kullanıcı etkilenmez', async () => {
    const { deps } = makeDeps();
    for (let i = 0; i < 5; i += 1) await attempt(deps, 'yanlis', 12345);
    assert.equal(await attempt(deps, 'Dogru-Parola-1', 12345), 'CURRENT_PASSWORD_LOCKED');
    assert.equal(await attempt(deps, 'Dogru-Parola-1', 22222), 'ok');
  });

  it('PARALEL tahmin: 40 eşzamanlı yanlış istek en çok 5 karşılaştırma çalıştırır (hak karşılaştırmadan ÖNCE rezerve edilir)', async () => {
    const { deps, stats } = makeDeps();
    const results = await Promise.all(Array.from({ length: 40 }, () => attempt(deps, 'yanlis')));
    assert.ok(stats.compares <= 5, `bcrypt karşılaştırma sayısı ${stats.compares}`);
    assert.equal(results.filter((code) => code === 'CURRENT_PASSWORD_LOCKED').length >= 36, true);
    assert.equal(results.includes('ok'), false);
    // kilitlendi: doğru parola da artık geçmez
    assert.equal(await attempt(deps, 'Dogru-Parola-1'), 'CURRENT_PASSWORD_LOCKED');
  });

  it('PARALEL: doğru parolalı 4 eşzamanlı istek (çift dokunma dahil) hepsi geçer (rezervasyon başarıda geri alınır, yanlışlıkla kilitlenmez)', async () => {
    const { deps } = makeDeps();
    const results = await Promise.all(Array.from({ length: 4 }, () => attempt(deps, 'Dogru-Parola-1')));
    assert.deepEqual(results, ['ok', 'ok', 'ok', 'ok']);
    assert.equal(deps.tracker.size(), 0);
  });
});
