// Giriş içeriğinin MEKANİK denetimi (anlamsal doğruluk değil): günlük ifadeleri kodda geçiyor mu, komutlar güvenli mi.
// Bağımsız çürütücü inceleme atlansa bile bu iki risk (uydurma günlük metni, sır basan/yıkıcı komut) tekrar üretimde yakalanır.
//
// Kurallar:
//  - logs: ifade kodda birebir geçmeli. Önek+mesaj şeklinde birleştirilerek üretilen metinler ("[ENV] UYARI: ..." gibi)
//    parçalara (": " ve "] " sınırlarından) ayrılıp HER parça kodda geçiyorsa kabul edilir. Değeri dinamik olan
//    ifadeler "~" ile başlatılır ("~[ENV] UYARI: JWT_SECRET 20 karakter"): denetlenmez, belgede "~" gösterilmez.
//  - commands: sır basanlar ASLA (pm2 env/jlist, .env okuma, printenv; "pm2 describe" yalnız "| grep" ile süzülürse);
//    değiştiriciler (rm -rf, DROP/DELETE/UPDATE SQL, git reset, pm2 restart/delete, docker stop ...) yalnızca komutta
//    "DEĞİŞTİRİR" etiketi varsa kabul edilir.

export const LINT_SOURCES = [
  ['lib', ['.dart']],
  ['server/src', ['.js']],
  ['server/scripts', ['.js', '.mjs', '.sh']],
  ['server/test', ['.js']],
  ['test', ['.dart']],
  ['integration_test', ['.dart']],
  ['test_driver', ['.dart']],
  ['cihaz_kontrol/src', ['.cpp', '.h', '.ino', '.c']],
  ['cihaz_kontrol/include', ['.h']],
  ['cihaz_kontrol/host_test', ['.py', '.cpp', '.h']],
  ['cihaz_kontrol/test', ['.py', '.cpp', '.h']],
  ['ekran_yazilimi/src', ['.cpp', '.h', '.ino', '.c']],
  ['ekran_yazilimi/include', ['.h']],
  ['company_qr_tool', ['.py']],
  ['cihaz_dene', ['.py']],
  ['deploy', ['.sh']],
];

/** Günlük ifadelerinin aranacağı kod gövdesi (tek metin). tools/klavuz yalnız üst düzey (.test ve entries hariç). */
export function buildCorpus(io) {
  const parts = [];
  for (const [dir, exts] of LINT_SOURCES) {
    for (const file of io.list(dir, { exts, recursive: true })) parts.push((io.lines(file) ?? []).join('\n'));
  }
  for (const file of io.list('tools/klavuz', { exts: ['.mjs'], recursive: false })) {
    if (!file.endsWith('.test.mjs')) parts.push((io.lines(file) ?? []).join('\n'));
  }
  return parts.join('\n');
}

export function logPhraseFound(corpus, phrase) {
  if (corpus.includes(phrase)) return true;
  const segments = phrase
    .split(/(?<=\])\s+|:\s+/)
    .map((s) => s.trim())
    .filter((s) => s.length >= 3);
  return segments.length > 1 && segments.every((s) => corpus.includes(s));
}

const SECRET_RULES = [
  [/\bpm2\s+(env|jlist|prettylist)\b/i, 'pm2 env/jlist ortam değişkenlerini (sırları) basar'],
  [/\bpm2\s+describe\b(?![^\n]*\|\s*(grep|head|awk|sed))/i, 'pm2 describe süzülmeden sır basabilir ("| grep" ile süzün)'],
  [/\b(cat|type|less|more|head|tail|sed|awk|grep|source)\s+[^|\n]*\.env\b(?!\.example)/i, '.env içeriğini okuma/yükleme'],
  [/\bprintenv\b|\benv\s*(\||$)/i, 'ortam değişkenlerini basma'],
];

const MUTATING_RULES = [
  [/\brm\s+-[a-z]*r[a-z]*f\b|\brm\s+-rf\b/i, 'rm -rf'],
  [/\b(DROP\s+(TABLE|DATABASE|INDEX)|TRUNCATE|DELETE\s+FROM)\b/i, 'yıkıcı SQL'],
  [/\bUPDATE\s+\w+\s+SET\b/i, 'veri değiştiren SQL (UPDATE)'],
  [/\bINSERT\s+INTO\b/i, 'veri ekleyen SQL (INSERT)'],
  [/\bgit\s+(reset|clean|checkout\s+--|push\s+(--force|-f)|stash\s+drop)\b/i, 'yıkıcı git'],
  [
    /\bpm2\s+(restart|delete|stop|reload)\b|\bsystemctl\s+(restart|stop|disable)\b|\bdocker\s+(rm|stop|restart|kill)\b|\bdocker\s+compose\s+down\b/i,
    'servis durdurma/yeniden başlatma',
  ],
  [/\bsed\s+-i\b/i, 'dosya düzenleme (sed -i)'],
];

const MUTATING_LABEL = /DEĞİŞTİRİR|DEGISTIRIR/i;

/** Tek bir komut için sorun listesi (boş = temiz). */
export function lintCommand(command) {
  const problems = [];
  for (const [re, why] of SECRET_RULES) {
    if (re.test(command)) problems.push(`sır riski: ${why}`);
  }
  if (!MUTATING_LABEL.test(command)) {
    for (const [re, why] of MUTATING_RULES) {
      if (re.test(command)) {
        problems.push(`değiştirici komut etiketsiz (${why}); komuta "# DEĞİŞTİRİR: ..." ekleyin ya da kaldırın`);
        break;
      }
    }
  }
  return problems;
}

/** areas: resolveArea çıktıları. Döner: [{ area, id, kind: 'günlük' | 'komut', text, why }] */
export function lintEntries(areas, io, corpus = buildCorpus(io)) {
  const warnings = [];
  for (const a of areas) {
    for (const e of a.entries) {
      for (const log of e.logs ?? []) {
        if (String(log).startsWith('~')) continue;
        if (!logPhraseFound(corpus, String(log))) {
          warnings.push({
            area: a.key,
            id: e.id,
            kind: 'günlük',
            text: String(log).slice(0, 110),
            why: 'kodda geçmiyor (dinamik değerliyse başına ~ koyun)',
          });
        }
      }
      for (const cmd of e.commands ?? []) {
        for (const why of lintCommand(String(cmd))) {
          warnings.push({ area: a.key, id: e.id, kind: 'komut', text: String(cmd).slice(0, 110), why });
        }
      }
    }
  }
  return warnings;
}
