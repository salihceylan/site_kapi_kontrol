// Tek bir cihaza OTA kontrol komutu (ota_check) gonderir.
//
// Kullanim:   node scripts/trigger_ota.js <CIHAZ_UID>
// Ortam (server/.env veya kabuk):
//   MQTT_URL        ornek: mqtts://mqtt.example.com:8883   (yoksa MQTT_HOST + MQTT_PORT[8883] kullanilir)
//   MQTT_USER       broker kullanicisi (api_bridge)
//   MQTT_PASSWORD   broker parolasi (asla koda yazilmaz)
//   MQTT_ALLOW_INSECURE_TLS=1   YALNIZCA gelistirme: sertifika dogrulamasini kapatir (varsayilan: dogrulama ACIK)
//
// Hedef cihaz zorunludur (varsayilan UID yok): yanlis cihaza kazara komut gitmesin.
import 'dotenv/config';
import mqtt from 'mqtt';

function resolveBrokerUrl() {
  const explicit = String(process.env.MQTT_URL || '').trim();
  if (explicit) {
    return explicit;
  }
  const host = String(process.env.MQTT_HOST || '').trim();
  if (!host) {
    return '';
  }
  const port = Number(process.env.MQTT_PORT || 8883);
  return `mqtts://${host}:${port}`;
}

const rawUid = String(process.argv[2] || '').trim().toUpperCase();
if (!/^[0-9A-F]{6,32}$/.test(rawUid)) {
  console.error('Kullanim: node scripts/trigger_ota.js <CIHAZ_UID>   (UID 6-32 haneli onaltilik olmali)');
  process.exit(2);
}
const targetUid = rawUid;

const brokerUrl = resolveBrokerUrl();
const username = String(process.env.MQTT_USER || '').trim();
const password = String(process.env.MQTT_PASSWORD || '');
if (!brokerUrl || !username || !password) {
  console.error('MQTT_URL (veya MQTT_HOST), MQTT_USER ve MQTT_PASSWORD ortam degiskenleri tanimli olmali.');
  process.exit(2);
}

const allowInsecureTls = process.env.MQTT_ALLOW_INSECURE_TLS === '1';
if (allowInsecureTls) {
  console.warn('UYARI: MQTT_ALLOW_INSECURE_TLS=1 -> TLS sertifika dogrulamasi KAPALI (yalnizca gelistirme icin).');
}

const client = mqtt.connect(brokerUrl, {
  clientId: `trigger_ota_${Date.now()}`,
  username,
  password,
  rejectUnauthorized: !allowInsecureTls,
  connectTimeout: 10000,
  reconnectPeriod: 0,
});

client.on('connect', () => {
  console.log('Broker baglandi, OTA kontrol komutu gonderiliyor ->', targetUid);
  client.publish(
    `device/${targetUid}/cmd`,
    JSON.stringify({ action: 'ota_check' }),
    { qos: 1 },
    (err) => {
      if (err) {
        console.error('Hata:', err.message || err);
        process.exitCode = 1;
      } else {
        console.log('OTA kontrol komutu basariyla yayinlandi!');
      }
      client.end(false, () => process.exit(process.exitCode || 0));
    },
  );
});

client.on('error', (err) => {
  console.error('MQTT Hata:', err.message || err);
  process.exit(1);
});
