// Surec duzeyi hata yakalayicilar.
// - unhandledRejection: loglanir, surec devam eder.
// - uncaughtException: loglanir ve surec exit(1) ile kapanir (PM2 yeniden baslatir).

import crypto from 'crypto';

function describeError(reason) {
  if (reason instanceof Error) {
    return reason.stack || `${reason.name}: ${reason.message}`;
  }
  try {
    return typeof reason === 'string' ? reason : JSON.stringify(reason);
  } catch (_) {
    return String(reason);
  }
}

export function installProcessHandlers({
  proc = process,
  logger = console,
  exit = (code) => process.exit(code),
} = {}) {
  const onUnhandledRejection = (reason) => {
    const errorId = crypto.randomBytes(4).toString('hex');
    logger.error(`[unhandledRejection] ${errorId}: ${describeError(reason)}`);
  };

  const onUncaughtException = (error) => {
    const errorId = crypto.randomBytes(4).toString('hex');
    logger.error(`[uncaughtException] ${errorId}: ${describeError(error)}`);
    exit(1);
  };

  proc.on('unhandledRejection', onUnhandledRejection);
  proc.on('uncaughtException', onUncaughtException);

  return { onUnhandledRejection, onUncaughtException };
}
