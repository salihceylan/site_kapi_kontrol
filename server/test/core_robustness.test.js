import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';

// Dayanıklılık (donma/kilitlenme önleme) ayarları: DB havuzu sınırları/zaman aşımları, havuz hata
// dinleyicisi ve MQTT köprüsünün düzgün kapanması. DB'ye veya broker'a BAĞLANMAZ.
process.env.DB_HOST = '127.0.0.1';
process.env.DB_PORT = '1';
process.env.DB_NAME = 'x';
process.env.DB_USER = 'x';
process.env.DB_PASSWORD = 'x';

const { pool } = await import('../src/db.js');
const { stopMqttBridge, __setMqttClientForTests } = await import('../src/mqtt_bridge.js');

after(async () => {
  await pool.end().catch(() => {});
});

describe('DB havuzu dayanıklılığı', () => {
  it('bağlantı sayısı sınırlı ve bağlantı/sorgu zaman aşımları tanımlı', () => {
    assert.ok(pool.options.max >= 2 && pool.options.max <= 50, `max=${pool.options.max}`);
    assert.ok(pool.options.connectionTimeoutMillis >= 1000, 'connectionTimeoutMillis tanımsız');
    assert.ok(pool.options.idleTimeoutMillis > 0, 'idleTimeoutMillis tanımsız');
    assert.ok(pool.options.statement_timeout >= 1000, 'statement_timeout tanımsız');
    assert.ok(pool.options.query_timeout > pool.options.statement_timeout, 'query_timeout > statement_timeout olmalı');
    assert.equal(pool.options.keepAlive, true);
  });

  it('açık kalmış transaction sunucu tarafında kapatılır ve saat dilimi korunur', () => {
    assert.match(String(pool.options.options), /idle_in_transaction_session_timeout=\d+/);
    assert.match(String(pool.options.options), /timezone=Europe\/Istanbul/);
  });

  it('boştaki istemci hatası süreci düşürmez (pool error dinleyicisi var)', () => {
    assert.ok(pool.listenerCount('error') >= 1);
    assert.doesNotThrow(() => pool.emit('error', Object.assign(new Error('bağlantı koptu'), { code: '57P01' })));
  });

  it('veritabanı yokken bağlantı denemesi sonsuza dek beklemez (hızlı hata)', async () => {
    const started = Date.now();
    await assert.rejects(() => pool.query('SELECT 1'));
    assert.ok(Date.now() - started < 8000, 'bağlantı hatası çok geç döndü');
  });
});

describe('MQTT köprüsü düzgün kapanma', () => {
  it('istemci yokken hemen çözülür', async () => {
    __setMqttClientForTests(null);
    await stopMqttBridge();
  });

  it('istemciyi zorla kapatır ve geri çağrıyı bekler', async () => {
    let called = null;
    __setMqttClientForTests({
      connected: true,
      end(force, opts, cb) {
        called = { force, opts };
        cb();
      },
    });
    await stopMqttBridge();
    assert.deepEqual(called, { force: true, opts: {} });
    __setMqttClientForTests(null);
  });

  it('end() fırlatsa bile asla reddetmez', async () => {
    __setMqttClientForTests({
      end() {
        throw new Error('kapanamadı');
      },
    });
    await stopMqttBridge();
    __setMqttClientForTests(null);
  });
});
