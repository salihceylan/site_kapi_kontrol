// Yasal belge uçları. Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md (1.4).
//
//   GET  /public/legal-documents        (kimliksiz) { documents: [{id,title,version,effective_date,required_for,complete}] }
//   GET  /public/legal-documents/:id    (kimliksiz) belge + content_md (yer tutucular doldurulmuş)
//   GET  /legal/:id                     (kimliksiz) sade HTML sayfası (mağaza / web bağlantısı); /legal/account-deletion = account_deletion
//   GET  /me/consents                   (auth) { consents, pending }
//   POST /me/consents                   (auth) { documents: [{id, version}] } -> { consents, pending }; 409 CONSENT_VERSION_STALE
//
// Kimliksiz uçlar SAVUNMACIDIR: yasal şirket ayarları okunamazsa belge yer tutucuları "[……]" kalır (complete:false) ve yanıt yine 200'dür;
// belge dizini yoksa liste boştur (account_deletion için yedek metin). Hata gövdesi: { error, code }.

import express from 'express';
import { pool } from '../db.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { acceptDocuments, getConsentState } from './legal_consent_service.js';
import {
  LEGAL_PAGE_CSP,
  legalDir,
  loadLegalFiles,
  renderLegalErrorPage,
  renderLegalNotFoundPage,
  renderLegalPage,
  resolveDocuments,
  summarizeDocument,
} from './legal_documents.js';
import { readPlatformConfig } from './platform_config_service.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

export const legalRouter = express.Router();

// Kimliksiz okuma: IP başına 600/saat (kayıt / giriş ekranları belgeleri açar; mağaza gözden geçirmesi sayfayı açar).
export const legalPublicLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 600, key: ipKey }],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
});
export const consentReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 20000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
});
export const consentWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 600, key: ipKey },
  ],
  message: 'Çok fazla onay işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const DOC_NOT_FOUND = Object.freeze({ error: 'Belge bulunamadı.', code: 'LEGAL_DOCUMENT_NOT_FOUND' });
const PUBLIC_CACHE = 'public, max-age=60';

/** Kimliksiz uçlar için belgeler: ayar okunamazsa yer tutucular boş kalır (savunmacı). */
async function publicDocuments() {
  let legal = {};
  try {
    legal = (await readPlatformConfig(pool)).legal;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[legal] ayarlar okunamadi (yer tutucular bos kalir):', error?.code || 'hata');
  }
  return resolveDocuments(await loadLegalFiles(legalDir()), legal);
}

/** "account-deletion" == "account_deletion"; biçimsiz -> null. */
function documentIdOf(param) {
  const id = String(param ?? '').toLowerCase().replace(/-/g, '_');
  return /^[a-z][a-z0-9_]{1,39}$/.test(id) ? id : null;
}

legalRouter.get('/public/legal-documents', legalPublicLimiter, async (_req, res) => {
  try {
    const docs = await publicDocuments();
    res.setHeader('Cache-Control', PUBLIC_CACHE);
    return res.status(200).json({ documents: docs.map(summarizeDocument) });
  } catch (error) {
    return respondError(res, 'legal_documents', error, 'Yasal belgeler yüklenemedi.');
  }
});

legalRouter.get('/public/legal-documents/:id', legalPublicLimiter, async (req, res) => {
  try {
    const id = documentIdOf(req.params.id);
    const doc = id ? (await publicDocuments()).find((candidate) => candidate.id === id) : null;
    if (!doc) {
      return res.status(404).json(DOC_NOT_FOUND);
    }
    res.setHeader('Cache-Control', PUBLIC_CACHE);
    return res.status(200).json(doc);
  } catch (error) {
    return respondError(res, 'legal_document', error, 'Yasal belge yüklenemedi.');
  }
});

legalRouter.get('/legal/:id', legalPublicLimiter, async (req, res) => {
  res.setHeader('Content-Security-Policy', LEGAL_PAGE_CSP);
  try {
    const id = documentIdOf(req.params.id);
    const doc = id ? (await publicDocuments()).find((candidate) => candidate.id === id) : null;
    if (!doc) {
      res.setHeader('Cache-Control', 'no-store');
      res.setHeader('X-Robots-Tag', 'noindex');
      return res.status(404).type('html').send(renderLegalNotFoundPage());
    }
    res.setHeader('Cache-Control', PUBLIC_CACHE);
    return res.status(200).type('html').send(renderLegalPage(doc));
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[legal] sayfa uretilemedi:', error?.code || error?.message || 'hata');
    res.setHeader('Cache-Control', 'no-store');
    return res.status(500).type('html').send(renderLegalErrorPage());
  }
});

// Onay uçlarının tamamı CSP'siz JSON; yanıtlar kişiye özeldir.
const userCodeOf = (req) => Number(req.authUser?.userCode ?? req.authUser?.user_code ?? req.authUser?.id);

legalRouter.get('/me/consents', authRequired, consentReadLimiter, async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json(await getConsentState(userCodeOf(req)));
  } catch (error) {
    return respondError(res, 'get_consents', error, 'Onaylarınız yüklenemedi.');
  }
});

legalRouter.post('/me/consents', authRequired, consentWriteLimiter, async (req, res) => {
  try {
    const body = req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {};
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json(await acceptDocuments({ userCode: userCodeOf(req), documents: body.documents }));
  } catch (error) {
    return respondError(res, 'post_consents', error, 'Onay kaydedilemedi.');
  }
});
