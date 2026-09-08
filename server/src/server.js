process.env.TZ = 'Europe/Istanbul';

import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { ensureDbSchema } from './db.js';
import { startMqttBridge } from './mqtt_bridge.js';
import { cleanupOldDoorLogs } from './services/door_service.js';

import { firmwareRouter } from './routes/firmware_routes.js';
import { companyRouter } from './routes/company_routes.js';
import { authRouter } from './routes/auth_routes.js';
import { adminRouter } from './routes/admin_routes.js';
import { managerRouter } from './routes/manager_routes.js';
import { appDoorsRouter } from './routes/app_doors_routes.js';
import { guestPassesRouter } from './routes/guest_passes_routes.js';
import { doorLogRouter } from './routes/door_log_routes.js';

dotenv.config();

const app = express();
app.set('trust proxy', 1);
const port = Number(process.env.PORT || 8080);

app.disable('x-powered-by');
app.use((_req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  next();
});

app.use(
  cors({
    origin: true,
    credentials: true,
  }),
);

app.use(express.json({ limit: '64kb' }));

// Mount Modular Routers
app.use(firmwareRouter);
app.use(companyRouter);
app.use(authRouter);
app.use(adminRouter);
app.use(managerRouter);
app.use(appDoorsRouter);
app.use(guestPassesRouter);
app.use(doorLogRouter);

// 404 Handler
app.use((_req, res) => {
  res.status(404).json({ error: 'Route bulunamadi.' });
});

async function startServer() {
  try {
    await ensureDbSchema();
    startMqttBridge();
    void cleanupOldDoorLogs();
    setInterval(cleanupOldDoorLogs, 24 * 60 * 60 * 1000);

    app.listen(port, () => {
      // eslint-disable-next-line no-console
      console.log(`API started on http://localhost:${port}`);
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Server startup failed:', error);
    process.exit(1);
  }
}

startServer();
