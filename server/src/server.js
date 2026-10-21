// async route hatalarini next(err)'e baglayan yama: express yuklenmeden ONCE (en basta) import edilmeli.
import './utils/async_errors.js';

process.env.TZ = 'Europe/Istanbul';

import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { ensureDbSchema, pool } from './db.js';
import { startMqttBridge, stopMqttBridge } from './mqtt_bridge.js';
import { runDatabaseCleanup } from './services/maintenance_service.js';

import { firmwareRouter } from './routes/firmware_routes.js';
import { companyRouter, companyAccessLimiter } from './routes/company_routes.js';
import { authRouter } from './routes/auth_routes.js';
import { adminRouter } from './routes/admin_routes.js';
import { managerRouter } from './routes/manager_routes.js';
import { appDoorsRouter } from './routes/app_doors_routes.js';
import { guestPassesRouter } from './routes/guest_passes_routes.js';
import { doorLogRouter } from './routes/door_log_routes.js';
import { membershipRouter } from './routes/membership_routes.js';
import { moduleRouter } from './modules/module_routes.js';
import { moduleRequestRouter } from './modules/module_request_routes.js';
import { siteApplicationRouter } from './modules/site_application_routes.js';
import { peopleRouter } from './modules/people_routes.js';
import { bulkImportRouter, bulkPreviewGate, bulkCommitGate, BULK_PREVIEW_PATH, BULK_COMMIT_PATH } from './modules/bulk_import_routes.js';
import { announcementRouter } from './modules/announcement_routes.js';
import { announcementPublicRouter } from './modules/announcement_public_routes.js';
import { financeRouter } from './modules/finance_routes.js';
import { finance4bRouter } from './modules/finance_4b_routes.js';
import { accountRouter } from './modules/account_routes.js';
import { startAnnouncementScheduler, stopAnnouncementScheduler } from './modules/announcement_scheduler.js';
import { startFinanceReminderScheduler, stopFinanceReminderScheduler } from './modules/finance_reminder_scheduler.js';
import { platformServicesRouter } from './modules/platform_config_routes.js';
import { clientErrorBodyParser } from './modules/client_error_routes.js';
import { startClientErrorPurge, stopClientErrorPurge } from './modules/client_error_purge.js';
import { documentRouter } from './modules/document_routes.js';
import { workTrackingRouter } from './modules/work_tracking_routes.js';
import { reservationRouter } from './modules/reservation_routes.js';
import { surveyRouter } from './modules/survey_routes.js';
import { visitorLogRouter } from './modules/visitor_log_routes.js';
import { cardAccessRouter } from './modules/card_access_routes.js';
import { deviceIntegrationsRouter } from './modules/device_integrations_routes.js';
import { contractsRouter } from './modules/contracts_routes.js';
import { startContractReminders, stopContractReminders } from './modules/contracts_reminders.js';
import { decisionBookRouter } from './modules/decision_book_routes.js';
import { startDocumentsMaintenance, stopDocumentsMaintenance } from './modules/document_maintenance.js';
import { pushRouter } from './modules/push_routes.js';
import { startPushWorker, stopPushWorker } from './modules/push_worker.js';

import { buildCorsAllowlist, createCorsOptionsDelegate } from './config/cors.js';
import { resolveServerStart, validateEnv } from './config/env.js';
import { createTrustProxyMonitor, resolveTrustProxy } from './security/trust_proxy.js';
import { installProcessHandlers } from './config/process_handlers.js';
import { requireCompanyAccess } from './middlewares/company_auth.js';
import { errorHandler, notFoundHandler } from './middlewares/error_handler.js';
import { createRequestLogger } from './middlewares/request_logger.js';
import { createSecurityHeaders } from './middlewares/security_headers.js';

import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

dotenv.config();

installProcessHandlers();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const webBuildPath = path.resolve(__dirname, '../../build/web');

const app = express();
// trust proxy (S-C): varsayilan "loopback" = X-Forwarded-For'a YALNIZCA es 127.0.0.1/::1 (ayni makinedeki nginx) ise
// guvenilir; 8080'e dogrudan gelen istekte baslik yok sayilir (IP sahteciligiyle hiz siniri atlatilamaz). TRUST_PROXY ile ayarlanir.
app.set('trust proxy', resolveTrustProxy(process.env).value);
const port = Number(process.env.PORT || 8080);

app.disable('x-powered-by');
// req.ip bir Cloudflare kenar adresiyse (TRUST_PROXY Cloudflare'i kapsamiyor) tek seferlik acik uyari (S-C).
app.use(createTrustProxyMonitor());
app.use(createSecurityHeaders());

// CORS: yalnizca allowlist (CORS_ORIGINS + PUBLIC_APP_URL + PUBLIC_BASE_URL). Native mobil istemciler CORS kullanmaz.
const { allowlist: corsAllowlist, rejected: corsRejected } = buildCorsAllowlist(process.env);
app.use(cors(createCorsOptionsDelegate(corsAllowlist)));

app.use(createRequestLogger());

// JSON govde limiti: genel 1 MB; yalnizca sirket etiketli cihaz kaydi (PNG base64) icin 5 MB.
// Buyuk limit YALNIZCA yetki dogrulandiktan sonra uygulanir (anonim istek 5 MB okutamaz).
// Hiz sinirlayici yetkiden ONCE calisir: yanlis X-Company-Key denemeleri de sayilir (router'daki ayni sinirlayici
// ayni istegi ikinci kez saymaz).
app.post('/api/company/labeled-devices', companyAccessLimiter, requireCompanyAccess, express.json({ limit: '5mb' }));
// Istemci hata raporu: kimliksiz uc icin KUCUK govde siniri (32 KB), genel 1 MB ayristiriciden ONCE (sonrakiler ayristirilmis govdeyi atlar).
app.post('/public/client-errors', clientErrorBodyParser);
// Toplu yukleme (Faz 2b): preview/commit icin 5 MB govde siniri YALNIZ authRequired + yetki + hiz sinirlayicidan SONRA (anonim istek 5 MB okutamaz);
// genel 1 MB ayristiriciden ONCE baglanir (ayni zincir bulkImportRouter'da da var, ikinci gecis bayrakla atlanir).
app.post(BULK_PREVIEW_PATH, ...bulkPreviewGate);
app.post(BULK_COMMIT_PATH, ...bulkCommitGate);
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// Mount Modular Routers
app.use(firmwareRouter);
app.use(companyRouter);
app.use(authRouter);
app.use(adminRouter);
app.use(managerRouter);
app.use(appDoorsRouter);
app.use(guestPassesRouter);
app.use(doorLogRouter);
app.use(membershipRouter);
app.use(moduleRouter);
app.use(moduleRequestRouter);
app.use(siteApplicationRouter);
app.use(peopleRouter);
app.use(bulkImportRouter);
app.use(announcementRouter);
app.use(announcementPublicRouter);
app.use(financeRouter);
app.use(finance4bRouter);
// Belgeler (dosya deposu): yonetici uclari + sakin uclari + ham govde akisi (PUT .../content, application/octet-stream; JSON govde sinirina dokunmaz).
app.use(documentRouter);
// Is takibi (ariza, bakim, talep): /manager/sites/:siteCode/work-items[...] + /app/work-items[...] (modul work_tracking, varsayilan KAPALI).
app.use(workTrackingRouter);
// Rezervasyon ve konsiyerj: /manager/sites/:siteCode/{reservation-areas,reservations,concierge-requests}[...] + /app/{reservation-areas,reservations,concierge-requests}[...] (modul reservation, varsayilan KAPALI).
app.use(reservationRouter);
// Anket ve oylama: /manager/sites/:siteCode/surveys[...] + /app/surveys[...] (modul survey, varsayilan KAPALI).
app.use(surveyRouter);
// Ziyaretci ve kargo (F11.03): /manager/sites/:siteCode/visitor-entries[/:id] + /app/visitor-entries[/summary|/:id/seen] (modul visitor_log, varsayilan KAPALI).
app.use(visitorLogRouter);
// Kartli gecis (F10): /manager/sites/:siteCode/access-cards[...] + /app/access-cards (modul card_access, varsayilan KAPALI).
app.use(cardAccessRouter);
// Kart odemesi saglayici arayuzu (F6) + kamera/plaka baglastiricilari (T8): modul card_payments / plate_cameras, varsayilan KAPALI.
app.use(deviceIntegrationsRouter);
// Firma ve sozlesme takibi: /manager/sites/:siteCode/contract-vendors[/:id] + /manager/sites/:siteCode/contracts[/summary|/:id] (modul contracts, varsayilan KAPALI; sakin ucu yok).
app.use(contractsRouter);
// Karar defteri: /manager/sites/:siteCode/decisions[/:id[/finalize]] + /app/decisions[/:id] (modul decision_book, varsayilan KAPALI).
app.use(decisionBookRouter);
// Telefon bildirimi (Faz 3b-B): /app/push/devices[/:installId], /app/push/test, /admin/push/status (tercihler /app/notification-preferences'ta).
app.use(pushRouter);
// Hesap silme (kimliksizlestirme) ve kisisel veri disa aktarma: /me/account-deletion[/preview], /me/data-export (yalniz kendi hesabi).
app.use(accountRouter);
// Platform hizmetleri: yasal belgeler (/public/legal-documents, /legal/:id, /me/consents), /public/app-config, /public/client-errors, /admin/platform-config.
// SPA yedek yolundan (app.get('*')) ONCE baglanir: /legal/:id tarayicida HTML ister.
app.use(platformServicesRouter);

// Serve Flutter Web SPA if build/web exists
if (fs.existsSync(webBuildPath)) {
  console.log(`[WEB] Serving Flutter Web from: ${webBuildPath}`);
  app.use(express.static(webBuildPath, { maxAge: '1h' }));

  // Fallback for HTML5 history mode (SPA routing)
  app.get('*', (req, res, next) => {
    if (req.method === 'GET' && req.accepts('html')) {
      return res.sendFile(path.join(webBuildPath, 'index.html'));
    }
    next();
  });
}

// 404 Handler
app.use(notFoundHandler);

// Global hata middleware'i (en sonda): 5xx'te genel mesaj + errorId; stack/mesaj istemciye ASLA gitmez.
app.use(errorHandler);

function checkEnvOrExit() {
  const { errors, warnings } = validateEnv(process.env);
  for (const warning of warnings) {
    console.warn(`[ENV] UYARI: ${warning}`);
  }
  for (const entry of corsRejected) {
    console.warn(`[CORS] Gecersiz origin girdisi yok sayildi: ${entry}`);
  }
  console.log(`[CORS] Izinli origin sayisi: ${corsAllowlist.size}`);
  if (errors.length > 0) {
    for (const message of errors) {
      console.error(`[ENV] HATA: ${message}`);
    }
    console.error('[ENV] Gecersiz yapilandirma nedeniyle sunucu baslatilmadi.');
    process.exit(1);
  }
}

const SHUTDOWN_GRACE_MS = 8000;
let httpServer = null;
let shuttingDown = false;

// Düzgün kapanma: yeni bağlantı kabul etme, süren istekleri bitir, MQTT + DB havuzunu kapat.
// PM2 reload/restart ve SIGTERM sırasında istekler yarıda kesilmez; takılırsa zorla çıkar.
async function shutdown(signal) {
  if (shuttingDown) {
    return;
  }
  shuttingDown = true;
  // eslint-disable-next-line no-console
  console.log(`[SHUTDOWN] ${signal} alindi, sunucu kapatiliyor...`);

  const forceTimer = setTimeout(() => {
    // eslint-disable-next-line no-console
    console.error('[SHUTDOWN] Sure asildi, zorla cikiliyor.');
    process.exit(1);
  }, SHUTDOWN_GRACE_MS);
  forceTimer.unref();

  try {
    if (httpServer) {
      await new Promise((resolve) => {
        httpServer.close(() => resolve());
        httpServer.closeIdleConnections?.();
        const dropTimer = setTimeout(() => httpServer.closeAllConnections?.(), SHUTDOWN_GRACE_MS - 3000);
        dropTimer.unref();
      });
    }
    await stopAnnouncementScheduler();
    await stopFinanceReminderScheduler();
    await stopClientErrorPurge();
    await stopDocumentsMaintenance();
    await stopContractReminders();
    await stopPushWorker();
    await stopMqttBridge();
    await pool.end();
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[SHUTDOWN] Kapanis hatasi:', error?.message);
  }
  process.exit(0);
}

function runCleanupSafely() {
  return Promise.resolve()
    .then(() => runDatabaseCleanup())
    .catch((error) => {
      // eslint-disable-next-line no-console
      console.error('[Bakim] Temizlik hatasi:', error?.code || error?.message);
    });
}

async function startServer() {
  try {
    checkEnvOrExit();
    await ensureDbSchema();
    startMqttBridge();
    // Telefon bildirimi (Faz 3b-B): hizmet hesabi BIR KEZ yuklenir (sir loglanmaz; okunamazsa configured:false, sunucu yine acilir) + push bakimi
    // (tek calisan advisory kilidi). Kuyruk turlari zamanlayici tikinde / yayindan sonra tetiklenir. ANNOUNCEMENT_SCHEDULER_DISABLED=1 ile bakim kapali.
    startPushWorker();
    // Duyuru zamanlayicisi (zamani gelen duyurulari yayinlar, e-posta kuyrugunu surer); ANNOUNCEMENT_SCHEDULER_DISABLED=1 ile kapali.
    startAnnouncementScheduler();
    // Borc hatirlatma kuyrugu (bekleyen satir varsa surer; FINANCE_REMINDER_SCHEDULER_DISABLED=1 / ANNOUNCEMENT_SCHEDULER_DISABLED=1 ile kapali).
    startFinanceReminderScheduler();
    // Istemci hata raporlari 90 gun sonra silinir (tek calisan advisory kilidi); CLIENT_ERROR_PURGE_DISABLED=1 ile kapali.
    startClientErrorPurge();
    // Belgeler bakim isi (bayat yukleme / suresi dolan silinmis belge / yetim dosya supurmesi; tek calisan advisory kilidi); DOCUMENTS_MAINTENANCE_DISABLED=1 ile kapali.
    startDocumentsMaintenance();
    // Sozlesme hatirlatmalari (gunluk, 09:00 sonrasi; tek calisan advisory kilidi; site yoneticilerine e-posta). SMTP yoksa / CONTRACT_REMINDERS_DISABLED=1 ile kapali.
    startContractReminders();
    void runCleanupSafely();
    // Zamanlayıcı süreci açık tutmasın (düzgün kapanmayı engellemesin).
    setInterval(runCleanupSafely, 24 * 60 * 60 * 1000).unref();

    // LISTEN_HOST (S-C, istege bagli): canlida LISTEN_HOST=127.0.0.1 -> 8080 yalnizca ayni makinedeki nginx'e acik (guvenlik
    // duvari hatasinda bile disaridan erisilemez). Tanimsizsa eski davranis (tum arayuzler). (HOST degil: bazi kabuklar
    // HOST'u makine adiyla doldurur.)
    const listenHost = String(process.env.LISTEN_HOST ?? '').trim();
    const onListening = () => {
      // eslint-disable-next-line no-console
      console.log(`API started on http://${listenHost || 'localhost'}:${port}`);
    };
    httpServer = listenHost ? app.listen(port, listenHost, onListening) : app.listen(port, onListening);
    // Yavaş/asılı istemcilere (slowloris) ve sonsuz bekleyen isteklere karşı sunucu zaman aşımları.
    httpServer.keepAliveTimeout = 65000;
    httpServer.headersTimeout = 66000;
    httpServer.requestTimeout = 60000;

    process.once('SIGTERM', () => void shutdown('SIGTERM'));
    process.once('SIGINT', () => void shutdown('SIGINT'));
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Server startup failed:', error);
    process.exit(1);
  }
}

export { app };

// Testler (SERVER_SKIP_START=1) uygulamayı ağa açmadan ve veritabanına bağlanmadan içe aktarabilir (gerçek ara katman zinciri, gerçek rotalar).
// Üretimde değişken tanımsızdır: davranış değişmez. dotenv .env'i de yüklediğinden değişken oraya yanlışlıkla yazılmış olabilir: NODE_ENV=production
// iken YOK SAYILIR ve yüksek sesle (hata) loglanır; sunucu normal başlar.
const startDecision = resolveServerStart(process.env);
if (startDecision.error) {
  // eslint-disable-next-line no-console
  console.error(`[ENV] HATA: ${startDecision.error}`);
}
if (!startDecision.skip) {
  startServer();
}
