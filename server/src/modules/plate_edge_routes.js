// Plaka Tanıma A1: KENAR İSTEMCİ uçları (güvenlik kulübesindeki Windows PC). Kullanıcı oturumu YOKTUR; kimlik kenar istemci anahtarıdır
// (Authorization: Bearer <id>.<gizli> ya da X-Edge-Key), kapsam anahtarın bağlı olduğu sitedir. Sözleşme sürümlüdür (schema_version, bkz. plate_gates_common.js).
//
//   POST /edge/plate/v1/claim       { schema_version?, app_version? }       anahtarı doğrula, aralık ipuçlarını al
//   GET  /edge/plate/v1/sync        ?updated_since&vehicles_rev&permits_rev&blacklist_rev    izin listesi + kapasite + içerideki sayılar (delta)
//   POST /edge/plate/v1/events      { schema_version, event_id, camera_id, plate, decision, seen_at, direction?, gate_id?, confidence?, reason? }   idempotent
//   POST /edge/plate/v1/heartbeat   { schema_version, app_version?, queue_depth?, cameras: [{ camera_id, last_frame_at?, last_read_at? }], recognition?: { ready, note? } }   (yanıt: commands[])
//   GET  /edge/plate/v1/commands                          bekleyen uzaktan komutları ATOMİK talep eder (sürüm 3)
//   POST /edge/plate/v1/commands/:id/result               { schema_version, status: done|failed, message?, result? }   (sürüm 3)
//   PUT  /edge/plate/v1/cameras/:cameraId/snapshot        ham JPEG gövde (image/jpeg), X-Captured-At? / X-Frame-Width? / X-Frame-Height?   (sürüm 3; yalnız SON kare tutulur)
//
// Hata sözleşmesi: 401 INVALID_EDGE_KEY / 403 MODULE_DISABLED (anahtar ya da modül sorunu), 400/404/409 KALICI hata (olayı yeniden deneme), 429/5xx geçici (yeniden dene).

import express from 'express';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError } from './route_helpers.js';
import { MAX_EDGE_BODY_BYTES, MAX_SNAPSHOT_BYTES, edgeKeyFromHeaders } from './plate_gates_common.js';
import { bodyTooLarge } from './plate_recognition_common.js';
import { PlatformError } from './errors.js';
import { authenticateEdge, claimEdge, commandResultEdge, commandsEdge, heartbeatEdge, recordEdgeEvent, snapshotEdge, syncEdge } from './plate_edge_service.js';

export const plateEdgeRouter = express.Router();

// Kenar PC başına birkaç istek / dakika; IP başına saatlik kaba kötüye kullanım freni (kulübedeki NAT arkasında birçok kamera olabilir).
const edgeLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 30000, key: ipKey }],
  message: 'Çok fazla istek.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

function assertBodySize(req) {
  if (req.method === 'GET') return;
  const declared = Number(req.headers['content-length']);
  const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
  if (size > MAX_EDGE_BODY_BYTES) throw bodyTooLarge();
}

function edgeHandler({ context, fallback }, run) {
  return [
    edgeLimiter,
    async (req, res) => {
      try {
        assertBodySize(req);
        const client = await authenticateEdge(edgeKeyFromHeaders(req.headers));
        res.set('Cache-Control', 'no-store');
        return res.json(await run({ req, client }));
      } catch (error) {
        return respondError(res, context, error, fallback);
      }
    },
  ];
}

const BASE = '/edge/plate/v1';

// Görüntü karoları: kamera başına birkaç saniyede bir istek; kaba kötüye kullanım freni IP başına (çok kameralı kulübe NAT'ı arkasında).
const snapshotLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 150000, key: ipKey }],
  message: 'Çok fazla görüntü isteği.',
  includeRetryBody: true,
});
const rawJpeg = express.raw({ type: 'image/jpeg', limit: MAX_SNAPSHOT_BYTES });

/** Kimlik ÖNCE doğrulanır, gövde SONRA okunur (kimliksiz istek 256 KB okutmaz). Gövde hatası (çok büyük / bozuk) KALICI 4xx olarak döner. */
function snapshotHandler(run) {
  return [
    snapshotLimiter,
    async (req, res, next) => {
      try {
        req.edgeClient = await authenticateEdge(edgeKeyFromHeaders(req.headers));
        next();
      } catch (error) {
        respondError(res, 'plate_edge_snapshot', error, 'Görüntü kaydedilemedi.');
      }
    },
    (req, res, next) =>
      rawJpeg(req, res, (error) => {
        if (!error) return next();
        const tooLarge = error.type === 'entity.too.large';
        return respondError(res, 'plate_edge_snapshot', tooLarge ? bodyTooLarge() : new PlatformError(400, 'INVALID_SNAPSHOT', 'Görüntü gövdesi okunamadı.'), 'Görüntü kaydedilemedi.');
      }),
    async (req, res) => {
      try {
        res.set('Cache-Control', 'no-store');
        return res.json(await run({ req, client: req.edgeClient }));
      } catch (error) {
        return respondError(res, 'plate_edge_snapshot', error, 'Görüntü kaydedilemedi.');
      }
    },
  ];
}

plateEdgeRouter.post(`${BASE}/claim`, ...edgeHandler({ context: 'plate_edge_claim', fallback: 'Kayıt yapılamadı.' }, ({ req, client }) => claimEdge(client, bodyOf(req))));
plateEdgeRouter.get(`${BASE}/sync`, ...edgeHandler({ context: 'plate_edge_sync', fallback: 'Senkron yapılamadı.' }, ({ req, client }) => syncEdge(client, req.query)));
plateEdgeRouter.post(`${BASE}/events`, ...edgeHandler({ context: 'plate_edge_event', fallback: 'Olay kaydedilemedi.' }, ({ req, client }) => recordEdgeEvent(client, bodyOf(req))));
plateEdgeRouter.post(`${BASE}/heartbeat`, ...edgeHandler({ context: 'plate_edge_heartbeat', fallback: 'Kalp atışı kaydedilemedi.' }, ({ req, client }) => heartbeatEdge(client, bodyOf(req))));
plateEdgeRouter.get(`${BASE}/commands`, ...edgeHandler({ context: 'plate_edge_commands', fallback: 'Komutlar alınamadı.' }, ({ client }) => commandsEdge(client)));
plateEdgeRouter.post(
  `${BASE}/commands/:id/result`,
  ...edgeHandler({ context: 'plate_edge_command_result', fallback: 'Komut sonucu kaydedilemedi.' }, ({ req, client }) => commandResultEdge(client, req.params.id, bodyOf(req))),
);
plateEdgeRouter.put(
  `${BASE}/cameras/:cameraId/snapshot`,
  ...snapshotHandler(({ req, client }) => snapshotEdge(client, req.params.cameraId, Buffer.isBuffer(req.body) ? req.body : null, req.headers)),
);
