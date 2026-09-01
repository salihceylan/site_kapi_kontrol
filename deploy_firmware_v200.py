import hashlib
import json
import os
import paramiko

bin_path = r"g:\site\site_kapi_kontrol\cihaz_kontrol\.pio\build\lolin_c3_mini\firmware.bin"

if not os.path.exists(bin_path):
    print("firmware.bin bulunamadi!")
    exit(1)

with open(bin_path, "rb") as f:
    data = f.read()
    md5 = hashlib.md5(data).hexdigest()
    sha256 = hashlib.sha256(data).hexdigest()
    file_size = len(data)

print(f"Firmware Boyut: {file_size} bytes")
print(f"MD5: {md5}")
print(f"SHA256: {sha256}")

manifest = {
    "enabled": True,
    "version": "2.0.0",
    "filename": "firmware.bin",
    "md5": md5,
    "sha256": sha256,
    "notes": "AHBU firmware v2.0.0 (WDT fix, 24h offline log, instant MQTT sync)",
    "interval_hours": 1,
    "force": True
}

manifest_json = json.dumps(manifest, indent=2)

host = "178.210.161.55"
port = 22667
user = "salihceylan"
password = "Fingon08."

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(host, port=port, username=user, password=password, timeout=10)

remote_dir = "/var/www/site_kapi_kontrol/server/firmware/esp32-c3"
ssh.exec_command(f"mkdir -p {remote_dir}")
import time
time.sleep(1)

sftp = ssh.open_sftp()

print("Firmware yukleniyor...")
sftp.put(bin_path, f"{remote_dir}/firmware.bin")

print("Manifest yaziliyor...")
with sftp.file(f"{remote_dir}/manifest.json", "w") as f:
    f.write(manifest_json)

sftp.close()

stdin, stdout, stderr = ssh.exec_command(f"ls -la {remote_dir} && cat {remote_dir}/manifest.json")
print("\n--- VPS Guncel Firmware Dosyalari ---")
print(stdout.read().decode('utf-8', errors='ignore'))

# MQTT ile cihaza anında 'ota_check' tetikleme komutu gönder
trigger_cmd = """node -e "
const mqtt = require('mqtt');
const fs = require('fs');
const client = mqtt.connect('mqtts://mqtt.gudeteknoloji.com.tr:8883', {
  username: 'kapi-api-backend',
  password: 'ApiBackendMqttSecretPassword2026!',
  rejectUnauthorized: false
});
client.on('connect', () => {
  console.log('MQTT baglandi, cihazlara OTA kontrol emri gonderiliyor...');
  client.publish('device/B86D72A172E0/cmd', JSON.stringify({ action: 'ota_check', reason: 'v200_deploy' }), { qos: 1 }, () => {
    console.log('B86D72A172E0 cihazina OTA emri iletildi.');
    setTimeout(() => process.exit(0), 1000);
  });
});
" """

stdin, stdout, stderr = ssh.exec_command(f"cd /var/www/site_kapi_kontrol/server && {trigger_cmd}")
print("\n--- OTA Tetikleme Sonucu ---")
print(stdout.read().decode('utf-8', errors='ignore'))

ssh.close()
print("\nTum islemler tamamlandi!")
