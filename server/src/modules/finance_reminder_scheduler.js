// Borç hatırlatma arka plan zamanlayıcısı (Faz 4b Ö6): bekleyen hatırlatma satırı varsa kuyruğu sürer, sahipsiz / süresi dolmuş satırları kapatır, eski adres özetlerini temizler.
//
// Sözleşme notu: docs/PLATFORM_FINANS_4B.md "Zamanlayıcı tiki bekleyen hatırlatma satırı varsa kuyruğu da sürer" — duyuru zamanlayıcısını (announcement_scheduler.js) DEĞİŞTİRMEMEK için
// (3a testleri sıkı) AYRI, hafif bir zamanlayıcıdır. Davranış eşdeğeri: 30 sn, unref'li, ANNOUNCEMENT_SCHEDULER_DISABLED=1 / FINANCE_REMINDER_SCHEDULER_DISABLED=1 ile kapalı,
// tek çalışan kilidi kuyruk işçisindedir (iş numarası 4), kapanışta temiz durur.

import { pool } from '../db.js';
import { failStaleReminderRows, hasPendingReminders, kickFinanceReminderQueue, purgeStaleReminderHashes, resumeFinanceReminderQueue, stopFinanceReminderQueue } from './finance_reminder_queue.js';

export const REMINDER_TICK_INTERVAL_MS = 30 * 1000;
const HASH_PURGE_INTERVAL_MS = 60 * 60 * 1000;

export const reminderSchedulerHooks = {
  closeStale: () => failStaleReminderRows(pool),
  hasPending: () => hasPendingReminders(),
  kick: () => kickFinanceReminderQueue(),
  purgeHashes: () => purgeStaleReminderHashes(),
};

let timer = null;
let tickPromise = null;
let stopped = false;
let lastPurgeAt = 0;

export function isReminderSchedulerDisabled(env = process.env) {
  const flag = (name) => ['1', 'true', 'yes'].includes(String(env[name] ?? '').trim().toLowerCase());
  return flag('ANNOUNCEMENT_SCHEDULER_DISABLED') || flag('FINANCE_REMINDER_SCHEDULER_DISABLED');
}

async function doTick() {
  if (stopped) {
    return;
  }
  try {
    await reminderSchedulerHooks.closeStale();
    if (!stopped && (await reminderSchedulerHooks.hasPending())) {
      void reminderSchedulerHooks.kick();
    }
    if (!stopped && Date.now() - lastPurgeAt >= HASH_PURGE_INTERVAL_MS) {
      lastPurgeAt = Date.now();
      await reminderSchedulerHooks.purgeHashes();
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[finance-reminder-scheduler] tik basarisiz:', error?.code || error?.message || 'hata');
  }
}

export function runFinanceReminderTick() {
  if (!tickPromise) {
    tickPromise = doTick().finally(() => {
      tickPromise = null;
    });
  }
  return tickPromise;
}

export function startFinanceReminderScheduler({ intervalMs = REMINDER_TICK_INTERVAL_MS, env = process.env } = {}) {
  if (isReminderSchedulerDisabled(env)) {
    return null;
  }
  if (!timer) {
    stopped = false;
    resumeFinanceReminderQueue();
    timer = setInterval(() => void runFinanceReminderTick(), intervalMs);
    timer.unref?.();
  }
  return { stop: stopFinanceReminderScheduler, intervalMs };
}

export async function stopFinanceReminderScheduler({ timeoutMs = 5000 } = {}) {
  stopped = true;
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
  const pending = [tickPromise, stopFinanceReminderQueue()].filter(Boolean);
  if (pending.length === 0) {
    return;
  }
  let timeout = null;
  try {
    await Promise.race([Promise.allSettled(pending), new Promise((resolve) => { timeout = setTimeout(resolve, timeoutMs); })]);
  } finally {
    clearTimeout(timeout);
  }
}
