#!/bin/bash
# Dagitim sonrasi dogrulama (sunucunun KENDI loopback'i uzerinden, az sayida istek; sir yazdirmaz).
set -u
DBC=site_kapi_kontrol_postgres
ENVF="${KAPI_ENV_FILE:-/var/www/site_kapi_kontrol/server/.env}"
q() { docker exec "$DBC" psql -U postgres -d site_kapi_kontrol -t -A -c "$1" 2>&1 | head -12; }
q1() { docker exec "$DBC" psql -U postgres -d site_kapi_kontrol -t -A -c "$1" 2>/dev/null | head -n 1; }
# .env degeri (YAZDIRMA: bazi anahtarlar sirdir; yalniz karar icin kullan, ekrana basma)
envval() { grep -m1 "^$1=" "$ENVF" 2>/dev/null | cut -d= -f2- | tr -d '' | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"; }
# kimliksiz istek: beklenen 401 (kimlik dogrulama kapisi); yontem, yol ve istege bagli JSON govde
expect401() {
  local label="$1" method="$2" path="$3" body="${4:-{\}}" code
  if [ "$method" = GET ]; then
    code="$(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://127.0.0.1:8080$path")"
  else
    code="$(curl -s -m 8 -X "$method" -H 'Content-Type: application/json' -d "$body" -o /dev/null -w '%{http_code}' "http://127.0.0.1:8080$path")"
  fi
  if [ "$code" = "401" ]; then echo "OK      $label: 401"; else echo "SORUNLU $label: HTTP ${code:-000} (401 beklenir)"; fi
}
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
echo "== yeni uclar (satisa hazirlik)"
echo -n "app-config: "; curl -s -m 8 -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/public/app-config
echo -n "yasal belge listesi: "; curl -s -m 8 http://127.0.0.1:8080/public/legal-documents | head -c 160; echo
echo -n "/legal/privacy: "; curl -s -m 8 -o /dev/null -w "%{http_code} %{content_type}\n" http://127.0.0.1:8080/legal/privacy
echo -n "/legal/account-deletion: "; curl -s -m 8 -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/legal/account-deletion
echo -n "istemci hata raporu (bos govde, 400 beklenir; 5xx OLMAMALI): "; curl -s -m 8 -X POST -H 'Content-Type: application/json' -d '{}' -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/public/client-errors
echo -n "hesap silme kimliksiz (401 beklenir): "; curl -s -m 8 -X POST -H 'Content-Type: application/json' -d '{}' -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/me/account-deletion/preview
echo -n "platform-config kimliksiz (401 beklenir): "; curl -s -m 8 -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/admin/platform-config
echo "== yeni tablolar 038-041 (25 beklenir: bulk_import_runs 1 + belgeler 3 + finans 4b 19 + push 2)"
echo "bulunan: $(q1 "select count(*) from information_schema.tables where table_schema='public' and table_name in ('bulk_import_runs','documents','document_versions','announcement_attachments','finance_settings','late_fee_runs','late_fee_run_lines','receipt_counters','receipts','receipt_print_events','finance_accounts','expense_categories','finance_suppliers','expenses','expense_voids','expense_documents','account_movements','account_transfers','account_reconciliations','finance_reminder_runs','finance_reminder_items','finance_reminder_apartments','finance_reminder_exclusions','push_devices','push_outbox')")"
# TEMEL modüller (AGENTS.md Kural 25; catalog.js core:true) HER sitede açık olmalıdır: açık olmayan site varsa SORUNLU basılır. Liste
# catalog.js ile aynı tutulur (server/test/core_modules.test.js denetler); yeni bir modül temel yapılırsa buraya da eklenir.
CORE_MODULES="people announcements finance survey neighbor_board equipment annual_report drive_storage"
echo "== site_modules: temel moduller her sitede acik olmali (SORUNLU = acik olmayan site var)"
total_sites="$(q1 "select count(*) from sites")"
core_sql=""
for m in $CORE_MODULES; do
  core_sql="$core_sql${core_sql:+,}'$m'"
  n="$(q1 "select count(*) from sites s where exists (select 1 from site_modules m where m.site_code = s.site_code and m.module_code = '$m' and m.enabled)")"
  if [ -n "$n" ] && [ "$n" = "$total_sites" ]; then echo "OK      $m: $n/$total_sites sitede acik"; else echo "SORUNLU $m: acik site ${n:-?} / toplam site ${total_sites:-?}"; fi
done
# Seçmeli modüller varsayılan kapalıdır, ama ilk dağıtımdan sonra site yöneticileri talep ederek açar: açık site sayısı
# artık bilgidir (eskiden "0 beklenir" SORUNLU basıyordu). Dağıtım öncesi/sonrası sayı değişmemeli: değiştiyse bir
# migration modülü kendiliğinden açmış olabilir. Kataloktan kalkan eski kodlar (documents, card_payments; 083/084) listeden ayrıdır:
# satırları silinmez, katalog onları yok sayar.
echo "== site_modules: secmeli modullerin acik site sayisi (bilgi; dagitim oncesi/sonrasi ayni kalmali)"
echo "bilgi   $(q1 "select coalesce(string_agg(module_code || '=' || n, ' ' order by module_code), 'hicbiri') from (select module_code, count(*) n from site_modules where enabled and module_code not in ($core_sql, 'documents', 'card_payments') group by module_code) t")"
echo "bilgi   eski kodlu modul satiri (documents, card_payments; katalogda yok, yok sayilir; otomatik geri alma icin korunur): $(q1 "select count(*) from site_modules where module_code in ('documents','card_payments')")"
echo "== yeni uclar 038-041 kimliksiz (401 beklenir; 5xx OLMAMALI)"
expect401 "toplu yukleme sablon/spec" GET /manager/sites/1000000001/imports/spec
expect401 "toplu yukleme onizleme" POST /manager/sites/1000000001/imports/people/preview
expect401 "sakin belgeleri" GET /app/documents
expect401 "yonetici belgeleri" GET /manager/sites/1000000001/documents
expect401 "belge indirme" GET /app/documents/1/download
expect401 "push cihaz kaydi (PUT)" PUT /app/push/devices
expect401 "push cihaz listesi" GET /app/push/devices
expect401 "push durumu (super)" GET /admin/push/status
echo "== push: FCM hizmet hesabi dosyasi (yol ve icerik YAZDIRILMAZ)"
pe="$(envval PUSH_ENABLED)"; echo "PUSH_ENABLED: ${pe:-<tanimsiz: kapali>}"
fcm="$(envval FCM_SERVICE_ACCOUNT_FILE)"
case "$(echo "${pe:-0}" | tr 'A-Z' 'a-z')" in 1|true|yes|on) push_on=1 ;; *) push_on=0 ;; esac
if [ -z "$fcm" ]; then
  if [ "$push_on" = 1 ]; then echo "SORUNLU push ACIK ama FCM_SERVICE_ACCOUNT_FILE tanimsiz"; else echo "push kapali (FCM_SERVICE_ACCOUNT_FILE tanimsiz) - beklenen"; fi
elif [ ! -e "$fcm" ]; then
  echo "SORUNLU FCM_SERVICE_ACCOUNT_FILE tanimli ama dosya bulunamadi"
elif [ -L "$fcm" ] || [ ! -f "$fcm" ]; then
  echo "SORUNLU FCM dosyasi duz dosya degil (sembolik baglanti/dizin)"
else
  fmode="$(stat -c %a "$fcm")"; fowner="$(stat -c %U "$fcm")"; fdmode="$(stat -c %a "$(dirname "$fcm")")"
  if [ "$fmode" = "600" ]; then echo "OK      FCM dosyasi izni: 600 (sahip: $fowner)"; else echo "SORUNLU FCM dosyasi izni: $fmode (600 olmali)"; fi
  [ "$fowner" = "$(id -un)" ] || echo "SORUNLU FCM dosyasinin sahibi API kullanicisi degil ($fowner)"
  [ -r "$fcm" ] && echo "OK      FCM dosyasi API kullanicisi tarafindan okunabilir" || echo "SORUNLU FCM dosyasi bu kullanici tarafindan okunamiyor"
  echo "bilgi: FCM dizini izni: $fdmode (700 ya da 750 beklenir)"
fi
echo "== belge deposu (DOCUMENTS_DIR)"
dd="$(envval DOCUMENTS_DIR)"; dsrc="env(DOCUMENTS_DIR)"
[ -n "$dd" ] || { dd="$(envval DOCUMENTS_STORAGE_DIR)"; dsrc="env(DOCUMENTS_STORAGE_DIR)"; }
[ -n "$dd" ] || { dd="$HOME/kapi-documents"; dsrc="varsayilan"; }
echo "kaynak: $dsrc; yol: $dd"
if [ ! -d "$dd" ]; then
  echo "bilgi: belge dizini YOK (modul kapali / henuz kullanilmadi olabilir; uygulama ilk kullanimda 0700 olusturur)"
else
  if [ -L "$dd" ]; then echo "SORUNLU belge dizini sembolik baglanti (uygulama 503 verir)"; fi
  dmode="$(stat -c %a "$dd")"; downer="$(stat -c %U "$dd")"
  if [ "$dmode" = "700" ]; then echo "OK      dizin izni: 700 (sahip: $downer)"; else echo "SORUNLU dizin izni: $dmode (700 olmali)"; fi
  [ "$downer" = "$(id -un)" ] || echo "SORUNLU dizin sahibi API kullanicisi degil ($downer)"
  if [ -w "$dd" ]; then echo "OK      dizin yazilabilir"; else echo "SORUNLU dizin yazilamiyor"; fi
  if [ -d "$dd/_tmp" ]; then if [ -w "$dd/_tmp" ]; then echo "OK      _tmp yazilabilir"; else echo "SORUNLU _tmp yazilamiyor"; fi; else echo "bilgi: _tmp henuz yok (ilk yuklemede olusur)"; fi
  case "$(readlink -f "$dd")" in /var/www/site_kapi_kontrol*) echo "SORUNLU belge dizini depo/kod dizini icinde (yedek ve geri almaya karisir)" ;; /tmp/*) echo "SORUNLU belge dizini /tmp altinda (kalici degil)" ;; esac
  avail_kb="$(df -Pk "$dd" | awk 'NR==2{print $4}')"; minfree="$(envval DOCUMENTS_MIN_FREE_BYTES)"; minfree="${minfree:-2147483648}"
  case "$minfree" in ''|*[!0-9]*) minfree=2147483648 ;; esac
  if [ "$((avail_kb * 1024))" -ge "$minfree" ]; then echo "OK      bos alan: $((avail_kb / 1024)) MB (esik $((minfree / 1048576)) MB)"; else echo "SORUNLU bos alan $((avail_kb / 1024)) MB < esik $((minfree / 1048576)) MB (yukleme 503 DOCUMENT_STORAGE_FULL verir)"; fi
  nfiles="$(find "$dd/sites" -type f 2>/dev/null | wc -l)"
  echo "bilgi: dosya sayisi $nfiles, boyut $(du -sm "$dd" 2>/dev/null | cut -f1) MB"
  badf="$(find "$dd/sites" -type f ! -perm 600 2>/dev/null | wc -l)"; badd="$(find "$dd" -type d ! -perm 700 2>/dev/null | wc -l)"
  if [ "$badf" = "0" ] && [ "$badd" = "0" ]; then echo "OK      dosya modu 600 / dizin modu 700 (sapma yok)"; else echo "SORUNLU izin sapmasi: dosya(!=600) $badf, dizin(!=700) $badd"; fi
  if [ "$nfiles" -gt 0 ] && ! ls "$HOME"/backups/scheduled/config/kapi_documents_*.tgz.enc >/dev/null 2>&1; then echo "UYARI   belge dosyalari var ama sifreli belge yedegi (config/kapi_documents_*) henuz yok: bash ~/ops/backup_db.sh"; fi
fi
echo -n "belge/push log uyarilari (pm2, son 150 satir): "; pm2 logs kapi-api --lines 150 --nostream 2>&1 | grep -E "\[documents\]|\[push\]" | tail -n 4 | cut -c1-170 | tr '\n' '|'; echo
echo "== 8080 dinleme adresi (127.0.0.1 beklenir, LISTEN_HOST ayarliysa)"; ss -ltn | grep -E ":8080 " | awk '{print $4}'
echo "== ENV uyarilari (pm2 log, yalniz [ENV] satirlari; TRUST_PROXY/GUVENLIK uyarisi kalmamali)"; pm2 logs kapi-api --lines 80 --nostream 2>&1 | grep -E "\[ENV\]" | tail -n 8 | cut -c1-170
echo "== pm2"; pm2 status 2>&1 | grep -E "kapi-api" | cut -c1-160
echo "== mosquitto + acl"; systemctl is-active mosquitto; grep -c "logs" /etc/mosquitto/acl
