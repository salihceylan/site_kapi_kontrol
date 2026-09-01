import paramiko

host = "178.210.161.55"
port = 22667
user = "salihceylan"
password = "Fingon08."

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    ssh.connect(host, port=port, username=user, password=password, timeout=10)
    
    print("=== DEVICE RUNTIME STATUS VIA NODE ===")
    node_cmd = """node -e "
const { pool } = require('./src/db.js');
pool.query('SELECT device_uid, mqtt_connected, firmware_version, ota_status, ota_last_version, last_seen_at, last_event, last_event_detail FROM device_runtime_status ORDER BY last_seen_at DESC LIMIT 10;')
  .then(r => { console.table(r.rows); process.exit(0); })
  .catch(e => { console.error(e); process.exit(1); });
" """
    stdin, stdout, stderr = ssh.exec_command(f"cd /var/www/site_kapi_kontrol/server && {node_cmd}")
    print(stdout.read().decode('utf-8', errors='ignore').encode('ascii', 'replace').decode('ascii'))
    print(stderr.read().decode('utf-8', errors='ignore').encode('ascii', 'replace').decode('ascii'))
    
    print("=== AUDIT / OTA LOGS IN NGINX ACCESS LOG ===")
    stdin, stdout, stderr = ssh.exec_command('tail -n 50 /var/log/nginx/access.log | grep -E "(manifest|firmware)" || true')
    print(stdout.read().decode('utf-8', errors='ignore'))

    print("=== PM2 ERROR LOGS ===")
    stdin, stdout, stderr = ssh.exec_command('pm2 logs kapi-api --lines 50 --nostream')
    print(stdout.read().decode('utf-8', errors='ignore'))

finally:
    ssh.close()
