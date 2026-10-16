// Hesap silme / dışa aktarma: kaynak koruma testleri (DB'siz). Kişisel veri log'a yazılmaz, görünmez-yön karakteri yok, kilit sırası kaynakta
// (kullanıcı satırından sonra paylaşılan kilitler yok), rota bağlama, kimliksizleştirme sabitleri.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const serverDir = path.join(here, '..');
const MODULES_DIR = path.join(serverDir, 'src', 'modules');
const accountFiles = readdirSync(MODULES_DIR).filter((f) => /^account_.*\.js$/.test(f)).sort();
const raw = (relative) => readFileSync(path.join(serverDir, relative), 'utf8');
const rawModule = (name) => readFileSync(path.join(MODULES_DIR, name), 'utf8');

describe('hesap modülleri: dosya kümesi', () => {
  it('beklenen modül dosyaları var', () => {
    for (const name of ['account_common.js', 'account_deletion_service.js', 'account_export_service.js', 'account_password_guard.js', 'account_routes.js']) {
      assert.ok(accountFiles.includes(name), name);
    }
  });

  it('görünmez / yön değiştiren Unicode karakter yok (kaynak ve testler)', () => {
    const files = [
      ...accountFiles.map((name) => path.join(MODULES_DIR, name)),
      ...readdirSync(here).filter((f) => /^account_.*\.test\.js$/.test(f)).map((f) => path.join(here, f)),
      path.join(serverDir, 'migrations', '036_account_deletion.sql'),
    ];
    for (const file of files) {
      const text = readFileSync(file, 'utf8');
      for (const [index, char] of [...text].entries()) {
        const code = char.codePointAt(0);
        const bad = (code >= 0x200b && code <= 0x200f) || (code >= 0x2028 && code <= 0x202e) || code === 0x2060 || code === 0xfeff || (code >= 0x2066 && code <= 0x2069);
        assert.equal(bad, false, `${path.basename(file)}: U+${code.toString(16)} (karakter ${index})`);
      }
    }
  });
});

describe('hesap modülleri: kişisel veri log\'a yazılmaz', () => {
  // console.* çağrılarının bulunduğu satırlar (ve devamındaki ilk 3 satır) e-posta / ad / telefon / parola / ileti / yığın içermemeli.
  it('hiçbir console çağrısı hata iletisi, yığın, e-posta, ad, telefon, parola ya da belirteç yazdırmaz', () => {
    for (const name of accountFiles) {
      const lines = rawModule(name).split('\n');
      lines.forEach((line, index) => {
        if (!/console\.(log|error|warn|info|debug)\(/.test(line)) return;
        const window = lines.slice(index, index + 4).join(' ');
        assert.equal(/\.message|\.stack|\bemail\b|fullName|full_name|phone|password|token|previousEmail|previousName/i.test(window.replace(/\[account\][^']*'/g, '')), false, `${name}:${index + 1}: ${line.trim()}`);
      });
    }
  });

  it('log satırları yalnız hata kodu / adı yazar (error?.code || error?.name)', () => {
    for (const name of ['account_deletion_service.js', 'account_export_service.js', 'account_routes.js']) {
      const text = rawModule(name);
      const calls = text.match(/console\.error\([^;]*;/g) ?? [];
      assert.ok(calls.length > 0, name);
      for (const call of calls) {
        assert.ok(/error\?\.code \|\| error\?\.name/.test(call) || /errorId/.test(call), `${name}: ${call}`);
      }
    }
  });
});

describe('hesap silme: kaynak düzeyinde güvenceler', () => {
  const deletion = rawModule('account_deletion_service.js');

  it('silme tek işlemdir: BEGIN ... COMMIT; hata yolunda ROLLBACK (finally); işlem dışı tek yazma yok', () => {
    assert.equal((deletion.match(/'BEGIN'/g) || []).length, 1);
    assert.equal((deletion.match(/'COMMIT'/g) || []).length, 1);
    assert.ok(/ROLLBACK/.test(deletion));
    assert.equal(/pool\.query\(/.test(deletion.replace(/previewAccountDeletion[\s\S]*?\n}\n/, '')), false, 'silme yolunda havuz sorgusu (işlem dışı) yok');
  });

  it("audit_log yazımı yalnızca INSERT: hiçbir hesap modülü audit_log tablosunu güncellemez / silmez (platform değişmezi)", () => {
    for (const name of accountFiles) {
      assert.equal(/UPDATE\s+audit_log\b|DELETE\s+FROM\s+audit_log\b|TRUNCATE\s+(TABLE\s+)?audit_log\b/i.test(rawModule(name)), false, name);
    }
  });

  it('kimliksizleştirme: hesap satırı SİLİNMEZ (DELETE FROM users yok); UPDATE users tek ifade', () => {
    assert.equal(/DELETE FROM users/.test(deletion), false);
    assert.equal((deletion.match(/UPDATE users\s+SET/g) || []).length, 1);
  });

  it('kullanıcı UPDATE\'inden sonra apartments / devices / join_requests kilidi (FOR UPDATE) yazılmaz: kaynakta kilit ifadeleri UPDATE users\'tan ÖNCE', () => {
    const usersAt = deletion.indexOf('UPDATE users');
    assert.ok(usersAt > 0);
    for (const pattern of [/FROM join_requests WHERE user_code = \$1 ORDER BY id FOR UPDATE/, /FROM apartments WHERE id = ANY\(\$1::BIGINT\[\]\) ORDER BY id FOR UPDATE/, /FROM devices WHERE id = ANY\(\$1::BIGINT\[\]\) ORDER BY id FOR UPDATE/, /FROM site_manager_sites WHERE site_code = ANY/]) {
      const at = deletion.search(pattern);
      assert.ok(at > 0 && at < usersAt, String(pattern));
    }
    const after = deletion.slice(usersAt);
    assert.equal(/FOR UPDATE/.test(after.replace(/site_applications[\s\S]*?FOR UPDATE/, '')), false, 'kullanıcıdan sonra yalnız başvuru satırı kilitlenir');
  });

  it('CRM kişi güncellemesi hesaptaki telefon / e-postayı kopyalamaz (users tablosundan phone_number / email okunmaz)', () => {
    const crm = deletion.slice(deletion.indexOf('UPDATE site_people'), deletion.indexOf('// 16.'));
    assert.equal(/phone_number|account_phone|u\.email/.test(crm), false);
  });

  it('parola özeti: kullanılamaz rastgele değer crypto.randomBytes ile üretilir', () => {
    assert.ok(/crypto\.randomBytes\(48\)/.test(deletion));
    assert.ok(/'!'|`!\$\{/.test(deletion));
  });
});

describe('bağlama ve düzenlemeler', () => {
  it('server.js hesap yönlendiricisini bağlar (SPA yedek yolundan ÖNCE)', () => {
    const server = raw('src/server.js');
    assert.ok(/import \{ accountRouter \} from '\.\/modules\/account_routes\.js';/.test(server));
    const mount = server.indexOf('app.use(accountRouter);');
    assert.ok(mount > 0);
    assert.ok(mount < server.indexOf("app.get('*'"));
    assert.ok(mount < server.indexOf('app.use(notFoundHandler)'));
  });

  it('authRequired deleted_at okur ve silinmiş hesaba 401 ACCOUNT_DELETED döner', () => {
    const middleware = raw('src/middlewares/auth_middleware.js');
    assert.ok(/\bdeleted_at\b/.test(middleware));
    assert.ok(/ACCOUNT_DELETED/.test(middleware));
  });

  it('mailer: sabit konulu hesap silindi bildirimi dışa aktarılır', () => {
    const mailer = raw('src/mailer.js');
    assert.ok(/export const ACCOUNT_DELETED_SUBJECT = /.test(mailer));
    assert.ok(/export async function sendAccountDeletedEmail\(/.test(mailer));
  });

  it('PATCH /me ile PAYLAŞILAN izleyici: parola doğrulayıcı passwordChangeFailureTracker + passwordChangeThrottleKey kullanır', () => {
    const guard = rawModule('account_password_guard.js');
    assert.ok(/passwordChangeFailureTracker/.test(guard) && /passwordChangeThrottleKey/.test(guard));
  });
});
