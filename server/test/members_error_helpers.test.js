// S2: ortak hata yardımcıları (validators.js) yalnızca iş mantığı hatalarının mesajını istemciye geçirir (DB'siz).
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  handleDeviceMutationError,
  handleSiteMutationError,
  handleUserMutationError,
} from '../src/utils/validators.js';
import { httpError } from '../src/services/membership_rules.js';

function fakeRes() {
  const res = {
    statusCode: null,
    body: null,
    status(code) {
      res.statusCode = code;
      return res;
    },
    json(payload) {
      res.body = payload;
      return res;
    },
  };
  return res;
}

// pg DatabaseError benzeri: Error alt sınıfı + SQLSTATE kodu + severity
class FakeDatabaseError extends Error {
  constructor(message, code) {
    super(message);
    this.name = 'DatabaseError';
    this.code = code;
    this.severity = 'ERROR';
  }
}

describe('members: handleSiteMutationError iş mantığı / beklenmeyen hata ayrımı', () => {
  let originalConsoleError;
  const logged = [];

  beforeEach(() => {
    originalConsoleError = console.error;
    console.error = (...args) => logged.push(args.join(' '));
  });

  afterEach(() => {
    console.error = originalConsoleError;
    logged.length = 0;
  });

  it('düz Error iş mantığı mesajı 400 ile aynen geçer (mevcut davranış korunur)', () => {
    const res = fakeRes();
    handleSiteMutationError(new Error('Site adi en az 2 karakter olmali.'), res, 'Genel hata');
    assert.equal(res.statusCode, 400);
    assert.equal(res.body.error, 'Site adi en az 2 karakter olmali.');
  });

  it('kontrollü statusCode (404/409) mesajıyla birlikte korunur', () => {
    const res404 = fakeRes();
    handleSiteMutationError(httpError(404, 'Site bulunamadi.'), res404, 'Genel hata');
    assert.equal(res404.statusCode, 404);
    assert.equal(res404.body.error, 'Site bulunamadi.');

    const res409 = fakeRes();
    handleSiteMutationError(httpError(409, 'Cakisma'), res409, 'Genel hata');
    assert.equal(res409.statusCode, 409);
  });

  it('DB hatası (pg DatabaseError) mesajı SIZDIRILMAZ: genel mesaj + error_id, ayrıntı logda', () => {
    const res = fakeRes();
    const dbError = new FakeDatabaseError('relation "sites" does not exist at character 15', '42P01');
    handleSiteMutationError(dbError, res, 'Site kaydedilemedi.');
    assert.equal(res.statusCode, 500);
    assert.equal(res.body.error, 'Site kaydedilemedi.');
    assert.match(res.body.error_id, /^[0-9a-f]{8}$/);
    assert.equal(JSON.stringify(res.body).includes('relation'), false);
    assert.ok(logged.some((line) => line.includes(res.body.error_id)), 'error_id loglanmalı');
  });

  it('TypeError / sistem hatası (ECONNREFUSED) ve SQLSTATE kodlu düz Error genel mesaja düşer', () => {
    const typeErr = fakeRes();
    handleSiteMutationError(new TypeError("Cannot read properties of undefined (reading 'rows')"), typeErr, 'Genel');
    assert.equal(typeErr.statusCode, 500);
    assert.equal(typeErr.body.error, 'Genel');

    const sysErr = fakeRes();
    const econn = new Error('connect ECONNREFUSED 127.0.0.1:5432');
    econn.code = 'ECONNREFUSED';
    handleSiteMutationError(econn, sysErr, 'Genel');
    assert.equal(sysErr.statusCode, 500);
    assert.equal(sysErr.body.error, 'Genel');

    const internalCode = fakeRes();
    handleSiteMutationError(new Error('DOOR_NOT_FOUND'), internalCode, 'Genel');
    assert.equal(internalCode.statusCode, 500);
    assert.equal(internalCode.body.error, 'Genel');
  });

  it('bilinen 23505 eşlemeleri ve APARTMENT_LOGIN_GENERATION_FAILED davranışı korunur', () => {
    const emailDup = fakeRes();
    const dup = new FakeDatabaseError('duplicate key', '23505');
    dup.constraint = 'users_email_key';
    handleSiteMutationError(dup, emailDup, 'Genel');
    assert.equal(emailDup.statusCode, 409);

    const siteDup = fakeRes();
    handleSiteMutationError(new FakeDatabaseError('duplicate key', '23505'), siteDup, 'Genel');
    assert.equal(siteDup.statusCode, 409);
    assert.equal(siteDup.body.error, 'Site kodu olusturulurken cakisma oldu.');

    const gen = fakeRes();
    handleSiteMutationError(new Error('APARTMENT_LOGIN_GENERATION_FAILED'), gen, 'Genel');
    assert.equal(gen.statusCode, 500);
    assert.equal(gen.body.error, 'Daire kullanicisi hesabi uretilemedi.');
  });
});

describe('members: handleUserMutationError / handleDeviceMutationError', () => {
  let originalConsoleError;

  beforeEach(() => {
    originalConsoleError = console.error;
    console.error = () => {};
  });

  afterEach(() => {
    console.error = originalConsoleError;
  });

  it('bilinen çakışmalar 409; beklenmeyen hata genel mesaj + error_id (ham mesaj yok)', () => {
    const dup = new FakeDatabaseError('duplicate key value violates unique constraint "users_email_key"', '23505');
    dup.constraint = 'users_email_key';
    const dupRes = fakeRes();
    handleUserMutationError(dup, dupRes, 'Genel');
    assert.equal(dupRes.statusCode, 409);
    assert.equal(dupRes.body.error, 'Bu e-posta zaten kayitli.');

    const unexpected = fakeRes();
    handleUserMutationError(new FakeDatabaseError('password authentication failed for user "kapi"', '28P01'), unexpected, 'Kullanici guncellenemedi.');
    assert.equal(unexpected.statusCode, 500);
    assert.equal(unexpected.body.error, 'Kullanici guncellenemedi.');
    assert.match(unexpected.body.error_id, /^[0-9a-f]{8}$/);
    assert.equal(JSON.stringify(unexpected.body).includes('password authentication'), false);

    const devDup = new FakeDatabaseError('duplicate key', '23505');
    devDup.constraint = 'devices_device_uid_key';
    const devRes = fakeRes();
    handleDeviceMutationError(devDup, devRes, 'Genel');
    assert.equal(devRes.statusCode, 409);

    const devUnexpected = fakeRes();
    handleDeviceMutationError(new Error('boom: secret detail'), devUnexpected, 'Cihaz kaydedilemedi.');
    assert.equal(devUnexpected.statusCode, 500);
    assert.equal(devUnexpected.body.error, 'Cihaz kaydedilemedi.');
    assert.equal(JSON.stringify(devUnexpected.body).includes('secret detail'), false);
  });
});
