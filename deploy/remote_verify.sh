#!/bin/bash
# Dagitim sonrasi dogrulama (sunucunun KENDI loopback'i uzerinden, az sayida istek; sir yazdirmaz).
set -u
DBC=site_kapi_kontrol_postgres
q() { docker exec "$DBC" psql -U postgres -d site_kapi_kontrol -t -A -c "$1" 2>&1 | head -12; }
echo "== cihazlar (uid | hardware_type | online)"; q "select device_uid || ' | ' || coalesce(hardware_type,'-') || ' | ' || coalesce(is_online::text,'-') from devices order by device_uid"
echo "== yeni kolonlar/indeks"
q "select 'users.updated_at' where exists (select 1 from information_schema.columns where table_name='users' and column_name='updated_at')"
q "select 'door_access_logs.client_log_id' where exists (select 1 from information_schema.columns where table_name='door_access_logs' and column_name='client_log_id')"
q "select indexname from pg_indexes where tablename='door_access_logs' and indexname like '%client_log%'"
q "select column_default from information_schema.columns where table_name='sites' and column_name='geofence_radius_meters'"
echo "== /health"; curl -s -m 8 http://127.0.0.1:8080/health | head -c 300; echo
echo "== sirket ucu anahtarsiz (401 beklenir)"; curl -s -m 8 -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/api/company/labeled-devices
echo "== login bos govde (400/401 + JSON hata)"; curl -s -m 8 -X POST -H 'Content-Type: application/json' -d '{}' -w "\nHTTP %{http_code}\n" http://127.0.0.1:8080/auth/login | head -c 300
echo "== bozuk JSON (400 + errorId yok / guvenli mesaj)"; curl -s -m 8 -X POST -H 'Content-Type: application/json' -d '{bozuk' -w "\nHTTP %{http_code}\n" http://127.0.0.1:8080/auth/login | head -c 300
echo "== OTA manifest (200 + sha256/hedef alanlari)"; curl -s -m 8 "http://127.0.0.1:8080/firmware/esp32-c3/manifest.json?current_version=3.0.0&uid=D4C771A172E0" | head -c 420; echo
echo "== pm2"; pm2 status 2>&1 | grep -E "kapi-api" | cut -c1-160
echo "== mosquitto + acl"; systemctl is-active mosquitto; grep -c "logs" /etc/mosquitto/acl
