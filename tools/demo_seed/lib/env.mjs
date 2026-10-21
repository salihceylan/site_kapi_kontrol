// Ortam: sunucu dizini bulma, DATABASE_URL -> DB_* ortam degiskenleri (uygulamanin db.js'i bunlari okur),
// pg / bcryptjs modullerini sunucunun node_modules'undan yukleme, komut satiri bayraklari.

import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

export function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const eq = a.indexOf('=');
      if (eq > 0) {
        args[a.slice(2, eq)] = a.slice(eq + 1);
      } else if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
        args[a.slice(2)] = argv[i + 1];
        i += 1;
      } else {
        args[a.slice(2)] = true;
      }
    } else {
      args._.push(a);
    }
  }
  return args;
}

export function resolveServerDir(args = {}) {
  return path.resolve(args['server-dir'] || process.env.DEMO_SEED_SERVER_DIR || path.join(here, '..', '..', '..', 'server'));
}

export function loadServerRequire(serverDir) {
  return createRequire(path.join(serverDir, 'package.json'));
}

/** DATABASE_URL'i ayristirir. */
export function parseDatabaseUrl(url) {
  const u = new URL(url);
  return {
    host: u.hostname,
    port: Number(u.port || 5432),
    database: decodeURIComponent(u.pathname.replace(/^\//, '')),
    user: decodeURIComponent(u.username),
    password: decodeURIComponent(u.password),
  };
}

/** Uygulamanin db.js'i DB_* okur; bunlari DATABASE_URL'den kur (mevcut degerler EZILIR). */
export function applyDbEnv(url) {
  const c = parseDatabaseUrl(url);
  process.env.DB_HOST = c.host;
  process.env.DB_PORT = String(c.port);
  process.env.DB_NAME = c.database;
  process.env.DB_USER = c.user;
  process.env.DB_PASSWORD = c.password;
  return c;
}

export function describeTarget(url) {
  const c = parseDatabaseUrl(url);
  return `${c.user}@${c.host}:${c.port}/${c.database}`;
}

export function newPgClient(serverRequire, url) {
  const pg = serverRequire('pg');
  const c = parseDatabaseUrl(url);
  return new pg.Client({ ...c, application_name: 'demo-seed', options: '-c timezone=Europe/Istanbul' });
}

export const importFromServer = (serverDir, relative) => import(pathToFileURL(path.join(serverDir, relative)).href);
