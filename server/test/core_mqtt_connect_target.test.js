import test from 'node:test';
import assert from 'node:assert/strict';

import { resolveMqttConnectTarget } from '../src/mqtt_bridge.js';

test('MQTT_CONNECT_HOST yoksa köprü MQTT_HOST adresine bağlanır', () => {
  const t = resolveMqttConnectTarget({ MQTT_HOST: 'mqtt.example.com', MQTT_PORT: '8883' });
  assert.equal(t.connectHost, 'mqtt.example.com');
  assert.equal(t.url, 'mqtts://mqtt.example.com:8883');
  assert.equal(t.servername, 'mqtt.example.com');
});

test('MQTT_CONNECT_HOST varsa TCP adresi o olur, TLS sunucu adı MQTT_HOST kalır', () => {
  const t = resolveMqttConnectTarget({ MQTT_HOST: 'mqtt.example.com', MQTT_PORT: '8883', MQTT_CONNECT_HOST: ' 127.0.0.1 ' });
  assert.equal(t.url, 'mqtts://127.0.0.1:8883');
  assert.equal(t.connectHost, '127.0.0.1');
  assert.equal(t.servername, 'mqtt.example.com');
  assert.equal(t.host, 'mqtt.example.com');
});

test('MQTT_PORT yoksa varsayılan 8883 kullanılır, boş MQTT_CONNECT_HOST yok sayılır', () => {
  const t = resolveMqttConnectTarget({ MQTT_HOST: 'b.example.com', MQTT_CONNECT_HOST: '   ' });
  assert.equal(t.port, 8883);
  assert.equal(t.url, 'mqtts://b.example.com:8883');
});
