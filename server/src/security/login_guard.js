// Giriş koruması (S-C): üç katmanlı, artan bekleme süreli hatalı-deneme kilidi. Bellek içi, süreç başına.
//
// Katmanlar (yalnız HATALI parola sayılır; başarılı giriş kendi "çift" sayacını sıfırlar):
//   A) çift   = hesap × kaynak   kaynak: güvenilir cihaz belirteci varsa cihaz, yoksa IP kovası (IPv6 /64)
//               5 hata / 15 dk -> 15 dk kilit; tekrarında 30 dk, 60 dk, en çok 2 sa (24 sa hatasız -> seviye sıfır)
//   B) hesap  = tüm kaynaklar   20 hata / 60 dk -> 15 dk; kilit sonrası her 5 hatada 30 dk, 1 sa ... en çok 4 sa
//   C) kaynak = IP kovası, tüm hesaplar (parola püskürtme)   30 hata / 15 dk -> 15 dk ... en çok 2 sa
//      (istemci IP'si çözülemediyse — genel olmayan adres (XFF yok -> 127.0.0.1), Cloudflare kenarı, bilinmiyor — C
//      uygulanmaz: ortak IP = ortak kilit olurdu)
// Güvenilir cihaz (imzalı device_token, hesapla eşleşen) B ve C'den MUAFTIR: saldırgan dağıtık denemeyle hesabı ya da
// ortak (CGNAT) IP'yi kilitlese bile hesap sahibinin kayıtlı cihazı girebilir (hizmet reddi önlenir). Parola yine şarttır.
//
// Yarış güvenliği: hata hakkı bcrypt karşılaştırmasından ÖNCE eşzamanlı olarak ayrılır (reserve); doğru parolada iade
// edilir (recordSuccess). Paralel N yanlış istekte en çok eşik kadar karşılaştırma çalışır. Eşiği dolduran rezervasyonun
// koyduğu kilit sonuç belli olana dek GEÇİCİDİR: diğer isteklere 2 sn Retry-After (doğru parolada kalkar); yanlış
// parola kesinleşince (commitFailure) gerçek kilide döner; sonuç hiç gelmezse 10 sn sonra gerçek sayılır.
//
// Kullanıcı varlığı sızmaz: hesap anahtarı var olan hesapta `u:<user_code>` (e-posta ve kullanıcı adı aynı bütçeyi
// paylaşır), olmayan hesapta `i:<küçük harfli tanımlayıcı>`; iki durumda da AYNI eşikler ve AYNI 429 yanıtı uygulanır.
//
// Kalıcılık: bilerek bellek içi (PM2 tek süreç). Yeniden başlatma sayaçları sıfırlar; dağıtım sıklığında kabul edilen
// risk. Kalıcı (DB) sayaç, kimliksiz uca her hatalı denemede yazma yükü ekler (kendisi bir hizmet reddi yüzeyi).

import crypto from 'node:crypto';
import { isPublicIp, requestIpBucket } from './client_ip.js';
import { isCloudflareIp } from './cloudflare_ranges.js';
import {
  deviceTokenMatchesPassword,
  issueDeviceToken,
  newDeviceId,
  readDeviceToken,
  verifyDeviceToken,
} from './login_device_token.js';

const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const MAX_KEYS = 50000;
// Harita doluyken tam süpürme (O(n)) en çok bu aralıkla yapılır; aradaki eklemeler O(1) tahliye ile yer açar.
const FULL_SWEEP_MIN_INTERVAL_MS = 30 * 1000;
// Tahliyede baştan en çok bu kadar kayıt taranır (kilitli olanlar sona taşınır; bkz. makeRoom).
const MAX_EVICTION_SCAN = 64;
// Geçici kilit: rezervasyonun koyduğu ama sonucu (bcrypt) henüz belli olmayan kilit. Bu sürede diğer isteklere kısa
// Retry-After döner (doğru parolada kilit kalkacak); sonuç hiç gelmezse (istek düştü) bu süreden sonra gerçek kilit sayılır.
export const PROVISIONAL_RETRY_AFTER_SECONDS = 2;
const PROVISIONAL_MAX_MS = 10 * 1000;

export const LOGIN_GUARD_DEFAULTS = Object.freeze({
  pair: { threshold: 5, repeatThreshold: 5, windowMs: 15 * MIN, baseLockMs: 15 * MIN, maxLockMs: 2 * HOUR, levelResetMs: 24 * HOUR },
  account: { threshold: 20, repeatThreshold: 5, windowMs: HOUR, baseLockMs: 15 * MIN, maxLockMs: 4 * HOUR, levelResetMs: 24 * HOUR },
  source: { threshold: 30, repeatThreshold: 15, windowMs: 15 * MIN, baseLockMs: 15 * MIN, maxLockMs: 2 * HOUR, levelResetMs: 24 * HOUR },
});

/**
 * Artan bekleme süreli hata sayacı. Kilitliyken gelen deneme sayılmaz (çağıran önce check yapar).
 */
export function createEscalatingCounter({
  threshold,
  repeatThreshold = threshold,
  windowMs,
  baseLockMs,
  maxLockMs,
  levelResetMs,
  maxKeys = MAX_KEYS,
}) {
  const entries = new Map();

  function isIdle(entry, at) {
    return (
      entry.lockedUntil <= at &&
      at - entry.windowStart > windowMs &&
      (entry.level === 0 || at - entry.lastEventAt > levelResetMs)
    );
  }

  function sweep(at) {
    for (const [key, entry] of entries) {
      if (isIdle(entry, at)) {
        entries.delete(key);
      }
    }
  }

  let lastFullSweepAt = -Infinity;
  let fullSweepsOnInsert = 0;

  // Harita dolu: (1) en çok FULL_SWEEP_MIN_INTERVAL_MS'de bir tam süpürme (O(n)); (2) aksi halde baştan (en eski) en
  // çok MAX_EVICTION_SCAN kayıt taranır, ilk kilitsiz kayıt atılır. Kilitli kayıtlar SONA taşınır: saldırgan anahtar
  // şişirerek mevcut kilitleri sildiremez ve sonraki taramalar aynı kilitli kayıtları yeniden gezmez (amortize O(1)).
  // Taranan hepsi kilitliyse son çare en eski kayıt atılır (bellek sınırı her koşulda korunur).
  function makeRoom(at) {
    if (at - lastFullSweepAt >= FULL_SWEEP_MIN_INTERVAL_MS) {
      lastFullSweepAt = at;
      fullSweepsOnInsert += 1;
      sweep(at);
      if (entries.size < maxKeys) {
        return;
      }
    }
    let scanned = 0;
    for (const [key, entry] of entries) {
      if (entry.lockedUntil <= at) {
        entries.delete(key);
        return;
      }
      entries.delete(key);
      entries.set(key, entry);
      scanned += 1;
      if (scanned >= MAX_EVICTION_SCAN) {
        break;
      }
    }
    const oldest = entries.keys().next().value;
    if (oldest !== undefined) {
      entries.delete(oldest);
    }
  }

  function isProvisional(entry, at) {
    return entry.provisional === true && at - entry.provisionalAt < PROVISIONAL_MAX_MS;
  }

  function retryAfter(entry, at) {
    const real = Math.max(1, Math.ceil((entry.lockedUntil - at) / 1000));
    return isProvisional(entry, at) ? Math.min(PROVISIONAL_RETRY_AFTER_SECONDS, real) : real;
  }

  return {
    check(key, at) {
      const entry = entries.get(key);
      if (entry && entry.lockedUntil > at) {
        return { locked: true, retryAfterSeconds: retryAfter(entry, at), level: entry.level, provisional: isProvisional(entry, at) };
      }
      return { locked: false, retryAfterSeconds: 0, level: entry?.level ?? 0 };
    },

    /** Geçici kilidi gerçek kilide çevirir (yanlış parola kesinleşti). Yalnız bu makbuzun koyduğu kilit. */
    confirm(key, receipt) {
      if (!receipt?.counted || !receipt.justLocked) {
        return;
      }
      const entry = entries.get(key);
      if (entry && entry.seq === receipt.seq) {
        entry.provisional = false;
      }
    },

    /**
     * Bir hata yazar (ya da rezerve eder). Dönen `receipt` ile `refund` çağrılarak geri alınabilir (doğru parola).
     * Kilitliyken çağrılırsa sayılmaz (receipt.counted=false).
     */
    fail(key, at) {
      let entry = entries.get(key);
      if (entry && entry.lockedUntil > at) {
        return {
          locked: true,
          justLocked: false,
          retryAfterSeconds: retryAfter(entry, at),
          level: entry.level,
          receipt: { counted: false },
        };
      }
      if (!entry) {
        if (entries.size >= maxKeys) {
          makeRoom(at);
        }
        entry = { failures: 0, windowStart: at, lockedUntil: 0, level: 0, lastEventAt: at, seq: 0 };
        entries.set(key, entry);
      }
      if (entry.level > 0 && at - entry.lastEventAt > levelResetMs) {
        entry.level = 0;
      }
      if (at - entry.windowStart > windowMs) {
        entry.failures = 0;
        entry.windowStart = at;
      }
      const receipt = {
        counted: true,
        prevFailures: entry.failures,
        prevLevel: entry.level,
        prevWindowStart: entry.windowStart,
        prevLastEventAt: entry.lastEventAt,
      };
      entry.failures += 1;
      entry.lastEventAt = at;
      const limit = entry.level === 0 ? threshold : repeatThreshold;
      if (entry.failures >= limit) {
        entry.level += 1;
        entry.seq += 1;
        const lockMs = Math.min(baseLockMs * 2 ** (entry.level - 1), maxLockMs);
        entry.lockedUntil = at + lockMs;
        entry.failures = 0;
        entry.windowStart = at;
        // Geçici: sonuç (bcrypt) belli olana dek diğer isteklere kısa Retry-After; confirm -> gerçek, refund -> kalkar.
        entry.provisional = true;
        entry.provisionalAt = at;
        return {
          locked: true,
          justLocked: true,
          // Rezervasyonu yapan isteğin kendi (yanlış parola) yanıtı GERÇEK süreyi taşır.
          retryAfterSeconds: Math.max(1, Math.ceil(lockMs / 1000)),
          level: entry.level,
          receipt: { ...receipt, justLocked: true, seq: entry.seq },
        };
      }
      return {
        locked: false,
        justLocked: false,
        retryAfterSeconds: 0,
        level: entry.level,
        failures: entry.failures,
        receipt: { ...receipt, justLocked: false, windowStart: entry.windowStart },
      };
    },

    /**
     * Rezervasyonu iade eder (doğru parola). Bu rezervasyonun koyduğu kilit geri alınır; aksi halde aynı penceredeki
     * sayaç bir azaltılır. Arada başka bir isteğin koyduğu kilide dokunulmaz (temkinli taraf).
     */
    refund(key, receipt, at) {
      if (!receipt?.counted) {
        return;
      }
      const entry = entries.get(key);
      if (!entry) {
        return;
      }
      if (receipt.justLocked) {
        if (entry.seq === receipt.seq && entry.lockedUntil > at) {
          entry.provisional = false;
          entry.level = receipt.prevLevel;
          entry.lockedUntil = 0;
          entry.failures = receipt.prevFailures;
          entry.windowStart = receipt.prevWindowStart;
          entry.lastEventAt = receipt.prevLastEventAt;
        }
      } else if (entry.lockedUntil <= at && entry.windowStart === receipt.windowStart && entry.failures > 0) {
        entry.failures -= 1;
      }
      if (entry.failures === 0 && entry.level === 0 && entry.lockedUntil <= at) {
        entries.delete(key);
      }
    },

    clear(key) {
      entries.delete(key);
    },
    clearWhere(predicate) {
      for (const key of entries.keys()) {
        if (predicate(key)) {
          entries.delete(key);
        }
      }
    },
    keys() {
      return entries.keys();
    },
    sweep,
    reset() {
      entries.clear();
    },
    size() {
      return entries.size;
    },
    /** İzleme/test: ekleme sırasında yapılan tam süpürme sayısı (harita doluyken en çok 30 sn'de bir). */
    stats() {
      return { fullSweepsOnInsert, size: entries.size };
    },
  };
}

const PAIR_SEPARATOR = '\u0000';

function shortHash(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex').slice(0, 10);
}

/**
 * @param {{ now?: () => number, config?: typeof LOGIN_GUARD_DEFAULTS, onLock?: (event) => void }} [options]
 */
export function createLoginGuard({ now = Date.now, config = LOGIN_GUARD_DEFAULTS, onLock } = {}) {
  const pair = createEscalatingCounter(config.pair);
  const account = createEscalatingCounter(config.account);
  const source = createEscalatingCounter(config.source);
  const notify =
    onLock ??
    ((event) => {
      // Kişisel veri yok: anahtarlar yalnızca kısa özetle; e-posta / IP / parola yazılmaz.
      // eslint-disable-next-line no-console
      console.warn(
        `[login-guard] kilit kapsam=${event.scope} seviye=${event.level} sure_sn=${event.retryAfterSeconds} anahtar=${shortHash(event.key)}`,
      );
    });

  const pairKey = (attempt) => `${attempt.accountKey}${PAIR_SEPARATOR}${attempt.sourceKey}`;

  function layers(attempt) {
    const list = [{ scope: 'pair', counter: pair, key: pairKey(attempt) }];
    if (!attempt.trusted) {
      list.push({ scope: 'account', counter: account, key: attempt.accountKey });
      if (attempt.ipKey) {
        list.push({ scope: 'source', counter: source, key: attempt.ipKey });
      }
    }
    return list;
  }

  function strongest(results) {
    return results.reduce(
      (acc, item) => (item.locked && item.retryAfterSeconds > acc.retryAfterSeconds ? item : acc),
      { locked: false, retryAfterSeconds: 0, scope: null },
    );
  }

  function emitLocks(reservation) {
    for (const item of reservation?.items ?? []) {
      if (item.justLocked) {
        try {
          notify({ scope: item.scope, level: item.level, retryAfterSeconds: item.retryAfterSeconds, key: item.key });
        } catch (_error) {
          // günlük hatası girişi etkilemez
        }
      }
    }
  }

  const guard = {
    /** Deneme kilitli mi? { locked, retryAfterSeconds, scope } */
    check(attempt) {
      const at = now();
      return strongest(layers(attempt).map((layer) => ({ ...layer.counter.check(layer.key, at), scope: layer.scope })));
    },

    /**
     * Yarış güvenli giriş: kilit kontrolü + TÜM katmanlarda hata hakkı ayırma, bcrypt karşılaştırmasından ÖNCE ve aynı
     * eşzamanlı adımda (await yok). Böylece paralel N istekten en çok eşik kadarı karşılaştırmaya ulaşır, kalanlar
     * `blocked` (429) alır. Sonuçta: yanlış parola -> commitFailure(reservation); doğru parola -> recordSuccess(attempt,
     * reservation) (hak iade edilir; bu rezervasyonun koyduğu kilit geri alınır).
     * @returns {{ blocked: boolean, locked: boolean, retryAfterSeconds: number, scope: string|null, items: object[] }}
     */
    reserve(attempt) {
      const at = now();
      const active = layers(attempt);
      const current = strongest(active.map((layer) => ({ ...layer.counter.check(layer.key, at), scope: layer.scope })));
      if (current.locked) {
        return { blocked: true, locked: true, retryAfterSeconds: current.retryAfterSeconds, scope: current.scope, items: [] };
      }
      const items = active.map((layer) => ({ ...layer.counter.fail(layer.key, at), scope: layer.scope, key: layer.key }));
      const result = strongest(items);
      return { blocked: false, locked: result.locked, retryAfterSeconds: result.retryAfterSeconds, scope: result.scope, items };
    },

    /** Yanlış parola kesinleşti: rezervasyon sayılı kalır; bu rezervasyonun koyduğu kilitler günlüğe yazılır. */
    commitFailure(reservation) {
      // Bu rezervasyonun koyduğu geçici kilitler gerçek kilide döner (diğer isteklere artık tam Retry-After).
      for (const item of reservation?.items ?? []) {
        const counter = item.scope === 'pair' ? pair : item.scope === 'account' ? account : source;
        counter.confirm(item.key, item.receipt);
      }
      emitLocks(reservation);
      return { locked: Boolean(reservation?.locked), retryAfterSeconds: reservation?.retryAfterSeconds ?? 0 };
    },

    /** Hatalı parola (rezervasyonsuz kısa yol; eski arayüz ve testler): reserve + commitFailure. */
    recordFailure(attempt) {
      const reservation = guard.reserve(attempt);
      if (!reservation.blocked) {
        guard.commitFailure(reservation);
      }
      return { locked: reservation.locked, retryAfterSeconds: reservation.retryAfterSeconds, scope: reservation.scope };
    },

    /**
     * Doğru parola: bu (hesap × kaynak) çiftinin sayacı sıfırlanır; `reservation` verilmişse hesap ve IP geneli
     * katmanlardaki ayrılmış hak iade edilir (aksi halde bu katmanlar süreyle söner).
     */
    recordSuccess(attempt, reservation = null) {
      const at = now();
      pair.clear(pairKey(attempt));
      for (const item of reservation?.items ?? []) {
        if (item.scope === 'account') {
          account.refund(item.key, item.receipt, at);
        } else if (item.scope === 'source') {
          source.refund(item.key, item.receipt, at);
        }
      }
    },

    /** Parola sıfırlama (posta kutusu kanıtı) sonrası: hesabın TÜM çift ve hesap geneli kilitleri açılır. */
    clearAccount(accountKey) {
      if (!accountKey) {
        return;
      }
      const prefix = `${accountKey}${PAIR_SEPARATOR}`;
      pair.clearWhere((key) => key.startsWith(prefix));
      account.clear(accountKey);
    },

    /** Durumu olan farklı hesap sayısı (test/izleme). */
    size() {
      const accounts = new Set(account.keys());
      for (const key of pair.keys()) {
        accounts.add(key.slice(0, key.indexOf(PAIR_SEPARATOR)));
      }
      return accounts.size;
    },

    sweep(at = now()) {
      pair.sweep(at);
      account.sweep(at);
      source.sweep(at);
    },

    reset() {
      pair.reset();
      account.reset();
      source.reset();
    },
  };
  return guard;
}

/** Var olan hesapta user_code, olmayanda küçük harfli tanımlayıcı. */
export function loginAccountKey({ userCode, identifier }) {
  const code = Number(userCode);
  if (Number.isSafeInteger(code) && code > 0) {
    return `u:${code}`;
  }
  return `i:${String(identifier ?? '').trim().toLowerCase()}`;
}

/**
 * Giriş denemesi bağlamı. `device` = verifyDeviceToken sonucu (imzası doğrulanmış); yalnızca çözülen hesapla VE hesabın
 * güncel parola sürümüyle (pv; `passwordHash`) eşleşirse güvenilir sayılır — parola sıfırlanınca/değişince eski cihaz
 * belirteçleri muafiyet sağlamaz.
 */
export function buildLoginAttempt({ req, identifier, userCode, device, passwordHash }) {
  const accountKey = loginAccountKey({ userCode, identifier });
  const code = Number(userCode);
  const trusted = Boolean(
    device &&
      Number.isSafeInteger(code) &&
      code > 0 &&
      device.userCode === code &&
      deviceTokenMatchesPassword(device, passwordHash),
  );
  const bucket = requestIpBucket(req);
  const ipKey = `ip:${bucket}`;
  // İstemci IP'si çözülemediyse (genel olmayan adres: nginx X-Forwarded-For iletmiyorsa herkes 127.0.0.1 görünür;
  // Cloudflare kenar adresi; bilinmiyor) IP geneli katman UYGULANMAZ: aynı adresi birçok kullanıcı paylaşır, ortak kilit
  // hizmet reddi olurdu. Çift ve hesap katmanları yine çalışır.
  const sharedSource = bucket === 'unknown' || !isPublicIp(req?.ip) || isCloudflareIp(req?.ip);
  if (sharedSource) {
    warnSharedSourceOnce();
  }
  return {
    accountKey,
    ipKey: sharedSource ? null : ipKey,
    trusted,
    deviceId: trusted ? device.deviceId : null,
    sourceKey: trusted ? `d:${device.deviceId}` : ipKey,
  };
}

let sharedSourceWarned = false;
function warnSharedSourceOnce() {
  if (sharedSourceWarned) {
    return;
  }
  sharedSourceWarned = true;
  // eslint-disable-next-line no-console
  console.warn(
    '[login-guard] Istemci IP\'si cozulemedi (genel olmayan adres / Cloudflare kenari / bilinmiyor): IP geneli giris kilidi ' +
      'bu isteklerde devre disi. nginx\'te "proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;" ve gerekirse ' +
      'TRUST_PROXY=loopback,cloudflare ya da nginx real_ip yapilandirin.',
  );
}

/** İstekteki cihaz belirtecini doğrular (hesap eşleşmesi buildLoginAttempt'te). */
export function readLoginDevice(req) {
  return verifyDeviceToken(readDeviceToken(req));
}

/** Başarılı girişte verilecek cihaz belirteci (güvenilir cihazın kimliği korunur, süresi yenilenir; güncel pv'ye bağlı). */
export function issueLoginDeviceToken({ userCode, attempt, passwordHash }) {
  return issueDeviceToken({ userCode, deviceId: attempt?.deviceId || newDeviceId(), passwordHash });
}

const BCRYPT_HASH_PATTERN = /^\$2[abxy]\$\d{2}\$[./A-Za-z0-9]{53}$/;

/**
 * Saklı özet gerçek bir bcrypt özeti mi? Değilse (silinmiş hesabın '!<hex>' özeti, boş, bozuk) karşılaştırma sahte
 * özetle yapılmalıdır: bcryptjs biçimsiz özette HEMEN false döner ve yanıt süresi hesabın durumunu ele verir.
 */
export function isBcryptHash(value) {
  return typeof value === 'string' && BCRYPT_HASH_PATTERN.test(value);
}
