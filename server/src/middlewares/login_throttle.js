// Ardisik hata sayaclari.
// - Giris: security/login_guard.js (hesap x kaynak, hesap geneli, IP geneli; artan bekleme; guvenilir cihaz muafiyeti).
// - Mevcut parola denemesi (PATCH /me ve daire sakini change-password): hesap bazli 5 hata -> 15 dk kilit (429).
//   Bu uclar oturum ister; saldirgan yalnizca calintisi oturumun hesabini kilitleyebilir (hizmet reddi yuzeyi yok).

import { createLoginGuard, loginAccountKey } from '../security/login_guard.js';
import { registerSweeper } from './rate_limiters.js';

const MAX_KEYS = 50000;

export function createFailureTracker({
  maxFailures = 5,
  windowMs = 15 * 60 * 1000,
  lockMs = 15 * 60 * 1000,
  now = Date.now,
} = {}) {
  const entries = new Map();

  function sweep(at = now()) {
    for (const [key, entry] of entries.entries()) {
      if (entry.lockedUntil > 0) {
        if (entry.lockedUntil <= at) {
          entries.delete(key);
        }
      } else if (at - entry.firstFailureAt > windowMs) {
        entries.delete(key);
      }
    }
  }
  registerSweeper(sweep);

  function retryAfterSeconds(entry, at) {
    return Math.max(1, Math.ceil((entry.lockedUntil - at) / 1000));
  }

  return {
    /** { locked, retryAfterSeconds } */
    check(key) {
      const at = now();
      const entry = entries.get(key);
      if (!entry) {
        return { locked: false, retryAfterSeconds: 0 };
      }
      if (entry.lockedUntil > 0) {
        if (entry.lockedUntil <= at) {
          entries.delete(key);
          return { locked: false, retryAfterSeconds: 0 };
        }
        return { locked: true, retryAfterSeconds: retryAfterSeconds(entry, at) };
      }
      return { locked: false, retryAfterSeconds: 0 };
    },

    /** Hata kaydeder; esik asildiysa kilitler. { locked, retryAfterSeconds, failures } */
    recordFailure(key) {
      const at = now();
      let entry = entries.get(key);
      if (entry && entry.lockedUntil > 0 && entry.lockedUntil <= at) {
        entries.delete(key);
        entry = undefined;
      }
      if (entry && entry.lockedUntil === 0 && at - entry.firstFailureAt > windowMs) {
        entries.delete(key);
        entry = undefined;
      }
      if (!entry) {
        if (entries.size >= MAX_KEYS) {
          sweep(at);
          if (entries.size >= MAX_KEYS) {
            // En eski kaydi at (Map ekleme sirasi).
            const oldest = entries.keys().next().value;
            entries.delete(oldest);
          }
        }
        entry = { failures: 0, firstFailureAt: at, lockedUntil: 0 };
        entries.set(key, entry);
      }
      entry.failures += 1;
      if (entry.failures >= maxFailures && entry.lockedUntil === 0) {
        entry.lockedUntil = at + lockMs;
      }
      if (entry.lockedUntil > 0) {
        return { locked: true, retryAfterSeconds: retryAfterSeconds(entry, at), failures: entry.failures };
      }
      return { locked: false, retryAfterSeconds: 0, failures: entry.failures };
    },

    recordSuccess(key) {
      entries.delete(key);
    },

    reset() {
      entries.clear();
    },
    size() {
      return entries.size;
    },
  };
}

// Giris kilidi (S-C): hesap x kaynak / hesap geneli / IP geneli, artan bekleme (security/login_guard.js).
export const loginGuard = createLoginGuard();
registerSweeper((at) => loginGuard.sweep(at));

const LEGACY_SOURCE_KEY = 'legacy';
const legacyAttempt = (identifier) => ({
  accountKey: loginAccountKey({ identifier }),
  sourceKey: LEGACY_SOURCE_KEY,
  ipKey: null,
  trusted: false,
});

// Geriye donuk uyumlu ince arayuz (eski testler / araclar): tanimlayici bazli check/recordFailure/recordSuccess,
// reset ve size TUM giris kilidi durumunu kapsar. Giris rotasi dogrudan loginGuard + buildLoginAttempt kullanir.
export const loginFailureTracker = {
  check(identifier) {
    return loginGuard.check(legacyAttempt(identifier));
  },
  recordFailure(identifier) {
    return loginGuard.recordFailure(legacyAttempt(identifier));
  },
  recordSuccess(identifier) {
    loginGuard.clearAccount(loginAccountKey({ identifier }));
  },
  reset() {
    loginGuard.reset();
  },
  size() {
    return loginGuard.size();
  },
};

// Mevcut parolayi yanlis giren (PATCH /me ve daire sakini change-password) kullanicilar icin ayri sayac.
export const passwordChangeFailureTracker = createFailureTracker({ maxFailures: 5, windowMs: 15 * 60 * 1000, lockMs: 15 * 60 * 1000 });

// PATCH /me ve POST /membership/apartments/:id/members/:code/change-password ayni hesap-bazli kilidi PAYLASIR:
// iki uctan biri mevcut parolayi tahmin etmek icin kullanilsa da toplam 5 hata -> 15 dk kilit (butce ortaktir).
export function passwordChangeThrottleKey(userCode) {
  return `u:${userCode}`;
}

export const CURRENT_PASSWORD_LOCKED_MESSAGE = 'Cok fazla hatali mevcut parola denemesi. Biraz sonra tekrar deneyin.';

/** 429 CURRENT_PASSWORD_LOCKED hatasi (servis katmani icin; route Retry-After/retry_after_seconds uretir). */
export function currentPasswordLockedError(retryAfterSeconds) {
  const error = new Error(CURRENT_PASSWORD_LOCKED_MESSAGE);
  error.statusCode = 429;
  error.expose = true;
  error.code = 'CURRENT_PASSWORD_LOCKED';
  error.retryAfterSeconds = retryAfterSeconds;
  return error;
}

/**
 * Sifre sifirlama (posta kutusuna erisim kanitlandi) sonrasi hesabin tum giris/parola-degisim kilitlerini acar.
 * Anahtarlar: kucuk harfli e-posta ve kullanici adi (giris), `u:<user_code>` (mevcut parola denemesi).
 */
export function clearAccountLocks({ email, loginName, userCode } = {}) {
  for (const raw of [email, loginName]) {
    const key = String(raw ?? '').trim().toLowerCase();
    if (key) {
      loginGuard.clearAccount(loginAccountKey({ identifier: key }));
    }
  }
  if (userCode !== undefined && userCode !== null && userCode !== '') {
    loginGuard.clearAccount(loginAccountKey({ userCode }));
    passwordChangeFailureTracker.recordSuccess(passwordChangeThrottleKey(userCode));
  }
}
