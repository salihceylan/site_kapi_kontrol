// S2: e-posta doğrulama kodu üretimi, atomik deneme sayacı SQL'i ve karar mantığı (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  SQL_CLAIM_VERIFICATION_ATTEMPT,
  SQL_CONSUME_VERIFICATION_CODE,
  SQL_FIND_PENDING_LOGIN_HASH,
  SQL_FIND_PENDING_REGISTRATION,
  SQL_SUPERSEDE_OLDER_VERIFICATION_CODES,
  SQL_SUPERSEDE_VERIFICATION_CODES,
  SQL_TAKE_PENDING_REGISTRATION,
  SQL_UPDATE_UNVERIFIED_USER_CREDENTIALS,
  SQL_UPSERT_PENDING_REGISTRATION,
  VERIFICATION_CODE_DIGITS,
  VERIFICATION_CODE_TTL_MINUTES,
  VERIFICATION_MAX_ATTEMPTS_PER_CODE,
  VERIFICATION_MAX_ATTEMPTS_PER_WINDOW,
  VERIFICATION_RESEND_COOLDOWN_SECONDS,
  classifyVerificationDenial,
  decideVerificationIssue,
  generateEmailVerificationCode,
  isValidVerificationCodeFormat,
  verificationDenialError,
  verificationIssueError,
} from '../src/services/membership_rules.js';
import {
  generateApartmentPin,
  generateNumericCode,
  generateVerificationCode,
  timingSafeEqualStrings,
} from '../src/utils/helpers.js';
import { generateVerificationCode as validatorsGenerateVerificationCode } from '../src/utils/validators.js';

const srcDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../src');

describe('members: doğrulama kodu üretimi (CSPRNG, 6 hane)', () => {
  it('kod 6 haneli ve yalnızca rakamdan oluşur; baştaki sıfırlar korunur', () => {
    assert.equal(VERIFICATION_CODE_DIGITS, 6);
    let leadingZero = 0;
    for (let i = 0; i < 3000; i += 1) {
      const code = generateEmailVerificationCode();
      assert.match(code, /^\d{6}$/);
      if (code.startsWith('0')) leadingZero += 1;
    }
    // ~%10 beklenir; hiç görülmemesi (0.9^3000) pratikte imkansızdır -> padStart çalışıyor
    assert.ok(leadingZero > 0, 'baştaki sıfır içeren kod hiç üretilmedi');
  });

  it('Math.random kullanılmaz: Math.random patlatılsa bile kodlar üretilir', () => {
    const original = Math.random;
    Math.random = () => {
      throw new Error('Math.random kullanıldı');
    };
    try {
      assert.match(generateEmailVerificationCode(), /^\d{6}$/);
      assert.match(generateVerificationCode(), /^\d{6}$/);
      assert.match(validatorsGenerateVerificationCode(), /^\d{6}$/);
      assert.match(generateApartmentPin(), /^[1-9]\d{3}$/);
      assert.match(generateNumericCode(4), /^\d{4}$/);
    } finally {
      Math.random = original;
    }
  });

  it('kaynak dosyalarda kod/PIN/şifre üretiminde Math.random geçmez', () => {
    const files = [
      'utils/helpers.js',
      'utils/validators.js',
      'services/membership_service.js',
      'services/membership_rules.js',
      'services/apartment_service.js',
      'services/user_service.js',
      'services/local_token_service.js',
    ];
    for (const file of files) {
      const text = fs.readFileSync(path.join(srcDir, file), 'utf8');
      // yorum satırlarındaki anma ("Math.random yerine ...") sayılmaz
      const code = text
        .split('\n')
        .filter((line) => !line.trim().startsWith('*') && !line.trim().startsWith('//'))
        .join('\n');
      assert.equal(/Math\.random\s*\(/.test(code), false, `${file} içinde Math.random çağrısı var`);
    }
  });

  it('daire PIN değeri 1000-9999 aralığındadır (tasarım: 4 haneli)', () => {
    for (let i = 0; i < 500; i += 1) {
      const pin = Number(generateApartmentPin());
      assert.ok(pin >= 1000 && pin <= 9999);
    }
  });

  it('timingSafeEqualStrings eşit/farklı/farklı uzunluk durumlarını doğru ayırır', () => {
    assert.equal(timingSafeEqualStrings('123456', '123456'), true);
    assert.equal(timingSafeEqualStrings('123456', '123457'), false);
    assert.equal(timingSafeEqualStrings('1234', '123456'), false);
    assert.equal(timingSafeEqualStrings(undefined, ''), true);
  });
});

describe('members: kod biçimi ve ret nedenleri', () => {
  it('6 haneli ve geçiş için eski 4 haneli kod kabul edilir; diğerleri reddedilir', () => {
    assert.equal(isValidVerificationCodeFormat('123456'), true);
    assert.equal(isValidVerificationCodeFormat('000123'), true);
    assert.equal(isValidVerificationCodeFormat('1234'), true);
    assert.equal(isValidVerificationCodeFormat('12345'), false);
    assert.equal(isValidVerificationCodeFormat('12345a'), false);
    assert.equal(isValidVerificationCodeFormat('1234567'), false);
    assert.equal(isValidVerificationCodeFormat(''), false);
    assert.equal(isValidVerificationCodeFormat(null), false);
  });

  it('classifyVerificationDenial: aktif kod yok / kod başına sınır / pencere sınırı', () => {
    assert.equal(
      classifyVerificationDenial({ hasActiveCode: false, codeAttempts: 0, windowAttempts: 0 }),
      'NO_ACTIVE_CODE',
    );
    assert.equal(
      classifyVerificationDenial({
        hasActiveCode: true,
        codeAttempts: VERIFICATION_MAX_ATTEMPTS_PER_CODE,
        windowAttempts: VERIFICATION_MAX_ATTEMPTS_PER_CODE,
      }),
      'CODE_ATTEMPTS_EXCEEDED',
    );
    // Yeni kod istenmiş (satır sayacı 0) ama pencere toplamı dolu: sayaç sıfırlanarak aşılamaz
    assert.equal(
      classifyVerificationDenial({
        hasActiveCode: true,
        codeAttempts: 0,
        windowAttempts: VERIFICATION_MAX_ATTEMPTS_PER_WINDOW,
      }),
      'WINDOW_ATTEMPTS_EXCEEDED',
    );
    assert.equal(
      classifyVerificationDenial({ hasActiveCode: true, codeAttempts: 1, windowAttempts: 2 }),
      'UNKNOWN',
    );
  });

  it('verificationDenialError doğru HTTP durumlarını üretir (404 / 429)', () => {
    assert.equal(verificationDenialError('NO_ACTIVE_CODE').statusCode, 404);
    assert.equal(verificationDenialError('CODE_ATTEMPTS_EXCEEDED').statusCode, 429);
    assert.equal(verificationDenialError('WINDOW_ATTEMPTS_EXCEEDED').statusCode, 429);
    assert.equal(verificationDenialError('UNKNOWN').statusCode, 429);
    assert.equal(verificationDenialError('NO_ACTIVE_CODE').expose, true);
  });

  it('decideVerificationIssue: bekleme süresi ve saatlik tavan', () => {
    assert.deepEqual(decideVerificationIssue({ secondsSinceLast: null, codesLastHour: 0 }), {
      allowed: true,
      reason: null,
    });
    // Kalan bekleme süresi yukarı yuvarlanır (en az 1 sn): istemciye dürüst geri sayım verilir.
    assert.deepEqual(
      decideVerificationIssue({ secondsSinceLast: VERIFICATION_RESEND_COOLDOWN_SECONDS - 1, codesLastHour: 1 }),
      { allowed: false, reason: 'COOLDOWN', retryAfterSeconds: 1 },
    );
    assert.equal(
      decideVerificationIssue({ secondsSinceLast: 10.2, codesLastHour: 1 }).retryAfterSeconds,
      VERIFICATION_RESEND_COOLDOWN_SECONDS - 10,
    );
    assert.equal(
      decideVerificationIssue({ secondsSinceLast: VERIFICATION_RESEND_COOLDOWN_SECONDS + 1, codesLastHour: 1 })
        .allowed,
      true,
    );
    assert.equal(decideVerificationIssue({ secondsSinceLast: 9999, codesLastHour: 10 }).reason, 'HOURLY_CAP');
  });
});

describe('members: atomik deneme sayacı SQL metni', () => {
  const sql = SQL_CLAIM_VERIFICATION_ATTEMPT.replace(/\s+/g, ' ').trim();

  it('tek UPDATE ile sayaç artırılır ve RETURNING ile döner (increment-first)', () => {
    assert.match(sql, /^UPDATE email_verifications ev SET attempt_count = ev\.attempt_count \+ 1 WHERE/);
    assert.match(sql, /RETURNING ev\.id, ev\.code_hash, ev\.attempt_count$/);
  });

  it('kod başına sınır, pencere içi toplam sınır ve geçerlilik süresi koşulları UPDATE içindedir', () => {
    assert.match(sql, /ev\.attempt_count < \$3::int/);
    assert.match(sql, /SUM\(w\.attempt_count\)/);
    assert.match(sql, /< \$5::int/);
    assert.match(sql, /created_at > NOW\(\) - make_interval\(mins => \$2::int\)/);
    assert.match(sql, /is_verified = FALSE/);
    assert.match(sql, /ORDER BY created_at DESC, id DESC LIMIT 1/);
  });

  it('süre/sınır sabitleri beklenen değerlerde', () => {
    // 30 dk: e-posta teslimi gecikebilir (gecikmiş kod kullanılamaz hâle gelmesin); kaba kuvveti kod başına
    // 5 + pencere başına 10 deneme sınırı engeller, yani süre uzunluğu tahmin riskini artırmaz.
    assert.equal(VERIFICATION_CODE_TTL_MINUTES, 30);
    assert.equal(VERIFICATION_MAX_ATTEMPTS_PER_CODE, 5);
    assert.ok(VERIFICATION_MAX_ATTEMPTS_PER_WINDOW >= VERIFICATION_MAX_ATTEMPTS_PER_CODE);
  });

  it('tüketim tek kullanımlıdır; yeni kod eskileri geçersiz kılar', () => {
    const consume = SQL_CONSUME_VERIFICATION_CODE.replace(/\s+/g, ' ');
    assert.match(consume, /WHERE id = \$1 AND is_verified = FALSE RETURNING id/);
    const supersede = SQL_SUPERSEDE_VERIFICATION_CODES.replace(/\s+/g, ' ');
    assert.match(supersede, /SET is_verified = TRUE WHERE LOWER\(email\) = LOWER\(\$1\) AND is_verified = FALSE/);
  });
});

describe('members: kod gönderilemediğinde dürüst hata (başarı gibi görünmez)', () => {
  it('MAIL_FAILED -> 503 EMAIL_DELIVERY_FAILED; mesajda "gönderildi" yok', () => {
    const error = verificationIssueError({ sent: false, reason: 'MAIL_FAILED' });
    assert.equal(error.statusCode, 503);
    assert.equal(error.code, 'EMAIL_DELIVERY_FAILED');
    assert.equal(error.expose, true);
    assert.match(error.message, /gönderilemiyor/);
    assert.equal(/gönderildi/.test(error.message), false);
  });

  it('COOLDOWN -> 429 ve kalan saniye; HOURLY_CAP -> 429', () => {
    const cooldown = verificationIssueError({ sent: false, reason: 'COOLDOWN', retryAfterSeconds: 17 });
    assert.equal(cooldown.statusCode, 429);
    assert.match(cooldown.message, /17 saniye/);
    assert.equal(verificationIssueError({ sent: false, reason: 'HOURLY_CAP' }).statusCode, 429);
  });

  it('bilinmeyen neden de başarı gibi sunulmaz (503)', () => {
    assert.equal(verificationIssueError({ sent: false, reason: 'BEKLENMEYEN' }).statusCode, 503);
  });
});

describe('members: bekleyen kayıt SQL metinleri', () => {
  const flat = (text) => text.replace(/\s+/g, ' ').trim();

  it('upsert: e-posta (büyük/küçük harf duyarsız) çakışmasında ad ve parola özetini günceller', () => {
    const sql = flat(SQL_UPSERT_PENDING_REGISTRATION);
    assert.match(sql, /^INSERT INTO pending_registrations \(email, full_name, password_hash\) SELECT \$1::text, \$2::text, \$3::text/);
    assert.match(sql, /ON CONFLICT \(\(LOWER\(email\)\)\) DO UPDATE SET/);
    assert.match(sql, /password_hash = EXCLUDED\.password_hash/);
    assert.match(sql, /updated_at = NOW\(\)/);
  });

  it('bayat gönderim kimlik bilgilerini ezemez: daha yeni açık kod varsa upsert / eski hesap güncellemesi hiçbir şey yapmaz', () => {
    const newerGuard = /NOT EXISTS \( SELECT 1 FROM email_verifications WHERE LOWER\(email\) = LOWER\(\$\d\) AND is_verified = FALSE AND id > \$\d \)/;
    assert.match(flat(SQL_UPSERT_PENDING_REGISTRATION), newerGuard);
    const legacy = flat(SQL_UPDATE_UNVERIFIED_USER_CREDENTIALS);
    assert.match(legacy, /^UPDATE users SET full_name = \$1, password_hash = \$2, updated_at = NOW\(\) WHERE user_code = \$3 AND email_verified = FALSE/);
    assert.match(legacy, newerGuard);
  });

  it('giriş denemesi için bekleyen kayıt araması yalnızca parola özetini döner', () => {
    assert.match(
      flat(SQL_FIND_PENDING_LOGIN_HASH),
      /^SELECT password_hash FROM pending_registrations WHERE LOWER\(email\) = LOWER\(\$1\) LIMIT 1$/,
    );
  });

  it('alma: tek DELETE ... RETURNING ile atomik (iki istek aynı kaydı iki kez alamaz)', () => {
    const sql = flat(SQL_TAKE_PENDING_REGISTRATION);
    assert.match(sql, /^DELETE FROM pending_registrations WHERE LOWER\(email\) = LOWER\(\$1\) RETURNING full_name, password_hash$/);
  });

  it('eski kodları kapatma: YALNIZCA daha eski satırlar (id < $2); daha yeni bir kod asla iptal edilmez', () => {
    const sql = flat(SQL_SUPERSEDE_OLDER_VERIFICATION_CODES);
    assert.match(sql, /^UPDATE email_verifications SET is_verified = TRUE WHERE LOWER\(email\) = LOWER\(\$1\) AND is_verified = FALSE AND id < \$2$/);
  });

  it('arama: yalnızca ad döner; parola özeti gereksiz yere okunmaz', () => {
    const sql = flat(SQL_FIND_PENDING_REGISTRATION);
    assert.match(sql, /^SELECT full_name FROM pending_registrations WHERE LOWER\(email\) = LOWER\(\$1\) LIMIT 1$/);
    assert.equal(/password_hash/.test(sql), false);
  });
});

describe('members: doğrulama servisleri DB\'ye gitmeden girdiyi reddeder', () => {
  process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-for-members-tests-0123456789abcdef';

  it('geçersiz kod biçimi / eksik alan / geçersiz e-posta -> 400', async () => {
    const { verifyIndividualEmailCode, resendIndividualVerificationCode, registerIndividualUser } =
      await import('../src/services/membership_service.js');

    await assert.rejects(
      () => verifyIndividualEmailCode({ email: 'kisi@example.com', code: '12' }),
      (err) => err.statusCode === 400,
    );
    await assert.rejects(
      () => verifyIndividualEmailCode({ email: '', code: '123456' }),
      (err) => err.statusCode === 400,
    );
    await assert.rejects(
      () => verifyIndividualEmailCode({ email: 'gecersiz', code: '123456' }),
      (err) => err.statusCode === 400,
    );
    await assert.rejects(
      () => resendIndividualVerificationCode({ email: 'gecersiz' }),
      (err) => err.statusCode === 400,
    );
    await assert.rejects(
      () => registerIndividualUser({ firstName: 'A', lastName: 'B', email: 'a@b', password: '123456' }),
      (err) => err.statusCode === 400,
    );
    await assert.rejects(
      () => registerIndividualUser({ firstName: 'A', lastName: 'B', email: 'a@b.co', password: '123' }),
      (err) => err.statusCode === 400,
    );
    await assert.rejects(
      () => registerIndividualUser({ firstName: 'A', lastName: 'B', email: 'a@b.co', password: 'x'.repeat(200) }),
      (err) => err.statusCode === 400,
    );
  });
});
