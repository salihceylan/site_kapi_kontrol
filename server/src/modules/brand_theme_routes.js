// Beyaz etiket tema uçları (G9; docs/PLATFORM_BEYAZ_ETIKET.md). platform_config_routes.js'teki platformServicesRouter'a bağlanır.
//
//   GET    /brand-theme/mine                       giriş yapmış: kendi etkin temam ({ theme: null } = varsayılan Gude teması)
//   GET    /brand-themes/:scopeType/:scopeId       süper / firma sahibi: kapsamın (company | site) kendi teması
//   PUT    /brand-themes/:scopeType/:scopeId       { display_name?, colors:{primary,accent,background,surface,text}, logo_data? }
//   DELETE /brand-themes/:scopeType/:scopeId       varsayılana döndür
// Yanıtlar `Cache-Control: no-store`. Kapı davranışına dokunmaz.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { getEditableTheme, resetTheme, saveTheme, themeForUser } from './brand_theme_service.js';

export const brandThemeRouter = express.Router();

const readLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 20000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
const writeLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla değişiklik. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

function handle(context, fallback, fn) {
  return async (req, res) => {
    try {
      res.setHeader('Cache-Control', 'no-store');
      return res.status(200).json(await fn(req));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const scopeOf = (req) => ({ scopeType: req.params.scopeType, scopeId: req.params.scopeId, user: req.authUser });

brandThemeRouter.get('/brand-theme/mine', authRequired, readLimiter, handle('brand_theme_mine', 'Tema yüklenemedi.', (req) => themeForUser(req.authUser)));
brandThemeRouter.get('/brand-themes/:scopeType/:scopeId', authRequired, readLimiter, handle('brand_theme_get', 'Tema yüklenemedi.', (req) => getEditableTheme(scopeOf(req))));
brandThemeRouter.put('/brand-themes/:scopeType/:scopeId', authRequired, writeLimiter, handle('brand_theme_save', 'Tema kaydedilemedi.', (req) => saveTheme({ ...scopeOf(req), body: req.body })));
brandThemeRouter.delete('/brand-themes/:scopeType/:scopeId', authRequired, writeLimiter, handle('brand_theme_reset', 'Tema sıfırlanamadı.', (req) => resetTheme(scopeOf(req))));
