'use strict';
// Yalitim koruyucusu: `node --require node_guard.cjs <giris>` ile on yuklenir.
// KAZA korumasidir, guvenlik siniri DEGILDIR: ayni surecteki kasitli kotu niyetli kod
// (native eklenti, process.dlopen, ic baglamalar) bunu asabilir. Dosya sistemini sinirlamaz.
// Kaynak: astra/yerel-kabul dali. `[kap/yalitim]` ile isaretli yerler bu depoda eklenen/degistirilen
// kisimlardir (ayrinti ve gerekce: docs/YEREL_YALITIM_ARACI.md).
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const dns = require('node:dns');
const dgram = require('node:dgram');
const cp = require('node:child_process');
const workerThreads = require('node:worker_threads');
const log = process.env.ASTRA_EGRESS_LOG;
// [kap/yalitim] Hata adi degisti: bu koruma Node'un izin modeli (--permission) degildir.
if (process.env.ASTRA_LOCAL_ONLY !== '1' || !log || !process.env.ASTRA_LOCAL_RUNS_PATH) throw new Error('ASTRA_LOCAL_GUARD_ENV_REQUIRED');
// [kap/yalitim] Denetim gunlugu yalniz kosu koku altina yazilabilir (ortamdaki yolla baska dosyaya ekleme yapilamaz).
{
  const rel = path.relative(path.resolve(process.env.ASTRA_LOCAL_RUNS_PATH), path.resolve(log));
  if (!rel || rel.split(path.sep)[0] === '..' || path.isAbsolute(rel)) throw new Error('ASTRA_EGRESS_LOG_OUTSIDE_RUNS');
}
function hostname(target) {
  const value = String(target ?? '').toLowerCase();
  if (value.startsWith('[') && value.endsWith(']')) return value.slice(1, -1);
  return value;
}
function audit(channel, target, reason) {
  const crypto = require('node:crypto');
  const host = hostname(target || 'unknown');
  const target_sha256 = crypto.createHash('sha256').update(host).digest('hex');
  fs.appendFileSync(log, JSON.stringify({channel, target_sha256, reason}) + '\n');
}
function deny(channel, target) { audit(channel, target, 'loopback-only'); const e = new Error('External access denied'); e.code = 'ASTRA_LOOPBACK_ONLY'; throw e; }
function loop(host) { return ['127.0.0.1', '::1', 'localhost', '::ffff:127.0.0.1', '::ffff:7f00:1'].includes(hostname(host)); }
function checkOptions(options, channel) {
  if (options.path || options.socketPath) deny('pipe', options.path || options.socketPath);
  // [kap/yalitim] Ozel lookup islevi 'localhost' adini baska bir adrese cevirebilir; kabul edilmez.
  if (typeof options.lookup === 'function') deny(channel, 'custom-lookup');
  // Inspect both fields, even where Node itself gives hostname precedence.
  for (const key of ['host', 'hostname']) {
    if (options[key] != null && !loop(options[key])) deny(channel, options[key]);
  }
}
function connectOptions(args) {
  // Socket.connect also accepts the normalized [options, callback] tuple.
  if (Array.isArray(args[0])) return connectOptions(args[0]);
  if (typeof args[0] === 'object' && args[0] !== null) return args[0];
  if (typeof args[0] === 'string') return {path: args[0]};
  return {port: args[0], host: typeof args[1] === 'string' ? args[1] : undefined};
}
const originalBinding = process.binding;
const oldConnect = net.connect;
net.connect = net.createConnection = function(...args) {
  checkOptions(connectOptions(args), 'tcp');
  return oldConnect.apply(this, args);
};
const oldSocketConnect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function(...args) {
  checkOptions(connectOptions(args), 'tcp');
  return oldSocketConnect.apply(this, args);
};
// [kap/yalitim] Ana bilgisayar verilmezse Node TUM arayuzlerde dinler (:: / 0.0.0.0); onceki surum bunu
// yalnizca denetliyor, ama degistirmeden Node'a geciriyordu. Simdi eksik ana bilgisayar 127.0.0.1 olarak
// eklenir; yol/IPC, fd ve tutamac (handle) bicimleri reddedilir.
const oldListen = net.Server.prototype.listen;
function isPipeName(value) { return typeof value === 'string' && !(Number(value) >= 0); }
net.Server.prototype.listen = function(...args) {
  const first = args[0];
  if (first !== null && typeof first === 'object') {
    // listen(options[, cb]) ve listen(handle[, ...])
    checkOptions(first, 'listen');
    if (first.fd !== undefined || first.handle !== undefined || first._handle !== undefined) deny('listen', 'handle');
    if (first.host) { if (!loop(first.host)) deny('listen', first.host); }
    else args[0] = {...first, host: '127.0.0.1'};
  } else if (isPipeName(first)) {
    deny('pipe', first);
  } else {
    // listen([port[, host[, backlog]]][, cb])
    const callbackOnly = typeof first === 'function';
    let rest = callbackOnly ? args : args.slice(1);
    let host = '127.0.0.1';
    if (typeof rest[0] === 'string') { host = rest[0]; rest = rest.slice(1); }
    if (!loop(host)) deny('listen', host);
    args = [callbackOnly || first == null ? 0 : first, host, ...rest];
  }
  return oldListen.apply(this, args);
};
const oldLookup = dns.lookup, oldPromiseLookup = dns.promises.lookup;
dns.lookup = function(name, ...args) {
  if (!loop(name)) deny('dns', name);
  if (hostname(name) === 'localhost') {
    const cb = args.find(x => typeof x === 'function');
    const all = args.some(x => x && typeof x === 'object' && x.all);
    if (cb) return process.nextTick(cb, null, all ? [{address:'127.0.0.1',family:4}] : '127.0.0.1', 4);
  }
  return oldLookup.call(this, name, ...args);
};
dns.promises.lookup = async function(name, options) {
  if (!loop(name)) deny('dns-promise',name);
  if (hostname(name) === 'localhost') {
    const result = {address:'127.0.0.1',family:4};
    return options?.all ? [result] : result;
  }
  return oldPromiseLookup.call(dns.promises, name, options);
};
// [kap/yalitim] Sorgu yapan TUM dns yontemleri reddedilir. Onceki surum yalniz bir ad listesini ve
// Resolver#resolve4/resolve'u kapatiyordu; resolveAny/Naptr/Ptr/Caa, lookupService, Resolver#resolve6/Txt/...
// ve dns.promises.Resolver acik kaliyordu (dns.setServers ile sorgu istenen sunucuya gidebilirdi).
const DNS_QUERY = /^(resolve|reverse$|lookupService$)/;
function denyDnsQueries(target, channel) {
  for (const name of Object.getOwnPropertyNames(target)) {
    if (DNS_QUERY.test(name) && typeof target[name] === 'function') target[name] = function(host) { deny(channel, host); };
  }
}
denyDnsQueries(dns, 'dns');
denyDnsQueries(dns.promises, 'dns-promise');
denyDnsQueries(dns.Resolver.prototype, 'dns-resolver');
denyDnsQueries(dns.promises.Resolver.prototype, 'dns-resolver');
// [kap/yalitim] Hedef adresi ilk dize (ileti) degil, ileti sonrasi ilk dizedir; ileti gunluge girmez.
dgram.Socket.prototype.send = function(...args) { const address = args.slice(1).find(x => typeof x === 'string'); deny('udp', address); };
for (const method of ['connect']) {
  const tls = require('node:tls'); const previous = tls[method];
  tls[method] = function(...args) {
    checkOptions(connectOptions(args), 'tls');
    for (const arg of args.slice(1)) if (arg && typeof arg === 'object') checkOptions(arg, 'tls');
    return previous.apply(this, args);
  };
}
function checkUrl(url, channel) {
  let u; try { u = new URL(url); } catch { deny(channel, url); }
  const permittedScheme = ['http:', 'https:'].includes(u.protocol);
  if (!permittedScheme || u.username || u.password || !loop(u.hostname)) deny(channel, u.hostname);
  return u;
}
function requestOptions(input, extra, channel) {
  if (typeof input === 'string' || input instanceof URL) checkUrl(input, channel);
  else if (input && typeof input === 'object') {
    // HTTP path is a resource path, not a Unix socket.
    const {path, ...options} = input;
    checkOptions(options, channel);
  }
  if (extra && typeof extra === 'object') {
    const {path, ...options} = extra;
    checkOptions(options, channel);
  }
}
const http = require('node:http'), https = require('node:https');
for (const mod of [http, https]) for (const method of ['request','get']) {
 const previous = mod[method]; mod[method] = function(...args) { requestOptions(args[0], args[1], 'http'); return previous.apply(this,args); };
}
const oldFetch = global.fetch;
global.fetch = async function(url, options={}) {
  const target = checkUrl(url instanceof URL || typeof url === 'string' ? url : url?.url, 'fetch');
  const response = await oldFetch(url, {...options, redirect:'manual'});
  if (response.status>=300 && response.status<400 && response.headers.get('location')) {
    const location = new URL(response.headers.get('location'), target);
    try { checkUrl(location, 'redirect'); }
    catch (error) { await response.body?.cancel(); throw error; }
  }
  return response;
};
const h2 = require('node:http2'); h2.connect = function(url) { checkUrl(url,'http2'); deny('http2',url); };
const envProxy = new Proxy(process.env, {set(target,key,value) { if (/^(DB_|MQTT_|SMTP_|OAUTH_|NETGSM_|GOOGLE_|APPLE_)/.test(String(key)) && !Object.prototype.hasOwnProperty.call(target,key)) deny('environment',key); if (['DB_HOST','MQTT_HOST','SMTP_HOST'].includes(String(key))&&!loop(String(value))) deny('environment',value); target[key]=value; return true; }});
process.env = envProxy;
// [kap/yalitim] execFile/execFileSync de kapatildi (spawn'in yerel kopyasini kullandiklari icin
// cp.spawn'i degistirmek onlari etkilemiyordu).
cp.spawn = cp.spawnSync = cp.exec = cp.execSync = cp.execFile = cp.execFileSync = cp.fork = function() { const e=new Error('Child processes disabled');e.code='ERR_ACCESS_DENIED';throw e; };
workerThreads.Worker = global.Worker = class { constructor() { const e=new Error('Workers disabled');e.code='ERR_ACCESS_DENIED';throw e; } };
// [kap/yalitim] Ag ve surec olusturma ile ilgili ic baglamalar (pipe/process/spawn/cares/tls/stream) da kapatildi.
process.binding = function(name) { if (/(tcp|udp|pipe|process|spawn|cares|tls|stream)/.test(String(name))) deny('native-network',name); return originalBinding.call(process,name); };
