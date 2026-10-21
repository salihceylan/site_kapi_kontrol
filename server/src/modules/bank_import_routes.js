// Banka dosyası uçları (067; Dalga 2 / 2C). server.js `app.use(bankImportRouter)`. Yalnız yönetici/süper (kurul, görevli, sakin 403); `finance` kapalıysa 403 MODULE_DISABLED.
// Gövde: genel 1 MB ayrıştırıcı (bir yüklemede en çok 1500 satır). Sözleşme: docs/PLATFORM_FINANS_BANKA.md.
import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { BASE, bodyOf, financeReadLimiter, financeWriteLimiter, managerHandler } from './finance_routes.js';
import { commitImport, deleteIban, getProfile, listIbans, listImports, previewImport, putProfile, revertImport } from './bank_import_service.js';
import { assignLine, classifyLine, confirmLines, linesSummary, linkLine, listLines, unclassifyLine } from './bank_line_service.js';

export const bankImportRouter = express.Router();

const read = (context, fallback, run) => [authRequired, financeReadLimiter, managerHandler({ context, fallback, write: true }, run)];
const write = (context, fallback, run) => [authRequired, financeWriteLimiter, managerHandler({ context, fallback, write: true }, run)];
const actorOf = (req) => req.authUser;

bankImportRouter.get(`${BASE}/accounts/:id/bank-profile`, ...read('bank_profile_get', 'Profil yüklenemedi.', async ({ req, access }) => ({ body: await getProfile(access.siteCode, req.params.id) })));
bankImportRouter.put(
  `${BASE}/accounts/:id/bank-profile`,
  ...write('bank_profile_put', 'Profil kaydedilemedi.', async ({ req, access }) => ({
    body: await putProfile({ siteCode: access.siteCode, rawAccountId: req.params.id, body: bodyOf(req), actor: actorOf(req) }),
  })),
);

bankImportRouter.post(
  `${BASE}/bank-imports/preview`,
  ...write('bank_import_preview', 'Önizleme hazırlanamadı.', async ({ req, access }) => ({ body: await previewImport({ siteCode: access.siteCode, body: bodyOf(req) }) })),
);
bankImportRouter.post(
  `${BASE}/bank-imports`,
  ...write('bank_import_commit', 'Yükleme tamamlanamadı.', async ({ req, access }) => commitImport({ siteCode: access.siteCode, body: bodyOf(req), actor: actorOf(req) })),
);
bankImportRouter.get(`${BASE}/bank-imports`, ...read('bank_import_list', 'Yüklemeler alınamadı.', async ({ access }) => ({ body: await listImports(access.siteCode) })));
bankImportRouter.post(
  `${BASE}/bank-imports/:id/revert`,
  ...write('bank_import_revert', 'Yükleme geri alınamadı.', async ({ req, access }) => ({
    body: await revertImport({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: actorOf(req) }),
  })),
);

bankImportRouter.get(`${BASE}/bank-lines/summary`, ...read('bank_lines_summary', 'Özet alınamadı.', async ({ access }) => ({ body: await linesSummary(access.siteCode) })));
bankImportRouter.get(`${BASE}/bank-lines`, ...read('bank_lines_list', 'Satırlar alınamadı.', async ({ req, access }) => ({ body: await listLines(access.siteCode, req.query ?? {}) })));
bankImportRouter.post(
  `${BASE}/bank-lines/confirm`,
  ...write('bank_lines_confirm', 'Satırlar onaylanamadı.', async ({ req, access }) => ({ body: await confirmLines({ siteCode: access.siteCode, body: bodyOf(req), actor: actorOf(req) }) })),
);
for (const [name, fn, fallback] of [
  ['assign', assignLine, 'Satır işlenemedi.'],
  ['link', linkLine, 'Satır bağlanamadı.'],
  ['classify', classifyLine, 'Satır sınıflanamadı.'],
]) {
  bankImportRouter.post(
    `${BASE}/bank-lines/:id/${name}`,
    ...write(`bank_line_${name}`, fallback, async ({ req, access }) => ({ body: await fn({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: actorOf(req) }) })),
  );
}
bankImportRouter.post(
  `${BASE}/bank-lines/:id/unclassify`,
  ...write('bank_line_unclassify', 'Sınıflama geri alınamadı.', async ({ req, access }) => ({ body: await unclassifyLine({ siteCode: access.siteCode, rawId: req.params.id, actor: actorOf(req) }) })),
);

bankImportRouter.get(`${BASE}/bank-ibans`, ...read('bank_ibans_list', 'IBAN listesi alınamadı.', async ({ access }) => ({ body: await listIbans(access.siteCode) })));
bankImportRouter.delete(
  `${BASE}/bank-ibans/:iban`,
  ...write('bank_ibans_delete', 'IBAN silinemedi.', async ({ req, access }) => ({ body: await deleteIban({ siteCode: access.siteCode, rawIban: req.params.iban, query: req.query ?? {} }) })),
);
