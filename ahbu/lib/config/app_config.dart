const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.gudeteknoloji.com.tr',
);

const String mqttHost = String.fromEnvironment(
  'MQTT_HOST',
  defaultValue: 'mqtt.gudeteknoloji.com.tr',
);

const int mqttPort = int.fromEnvironment('MQTT_PORT', defaultValue: 8883);

const String mqttAppUser = String.fromEnvironment(
  'MQTT_APP_USER',
  defaultValue: 'app_client',
);

const String mqttAppPassword = String.fromEnvironment(
  'MQTT_APP_PASSWORD',
  defaultValue: 'Fingon08.',
);

const String mqttSiteId = String.fromEnvironment(
  'MQTT_SITE_ID',
  defaultValue: '1',
);

const String mqttDoorId = String.fromEnvironment(
  'MQTT_DOOR_ID',
  defaultValue: 'ahbu',
);

const String esp32DeviceName = String.fromEnvironment(
  'ESP32_DEVICE_NAME',
  defaultValue: 'ahbu',
);
