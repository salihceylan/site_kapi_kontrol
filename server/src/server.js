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

import { buildCorsAllowlist, createCorsOptionsDelegate } from './config/cors.js';
import { validateEnv } from './config/env.js';
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
// nginx tek proxy: X-Forwarded-For'un son sirasi (nginx'in gordugu istemci) guvenilir; req.ip / req.secure buna gore.
app.set('trust proxy', 1);
const port = Number(process.env.PORT || 8080);

app.disable('x-powered-by');
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
    void runCleanupSafely();
    // Zamanlayıcı süreci açık tutmasın (düzgün kapanmayı engellemesin).
    setInterval(runCleanupSafely, 24 * 60 * 60 * 1000).unref();

    httpServer = app.listen(port, () => {
      // eslint-disable-next-line no-console
      console.log(`API started on http://localhost:${port}`);
    });
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

startServer();
