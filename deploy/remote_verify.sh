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
echo "== sema varlik kontrolleri 085-111 (canli DB, yalniz okuma; kosullar remote_rehearse_schema.sh ile AYNI; SORUNLU = eksik nesne)"
# Her 085-111 migration'inin nesneleri (tablo / sutun / indeks / kisit / tetikleyici / islev) varlik + (088 / 090) kisitlarin DOGRULANMIS olmasi. Salt okunur.
tb() { echo "(select count(*) from information_schema.tables where table_schema='public' and table_name in ($1))=$2"; }
cl() { echo "(select count(*) from information_schema.columns where table_schema='public' and (table_name||'.'||column_name) in ($1))=$2"; }
ix() { echo "(select count(*) from pg_indexes where schemaname='public' and indexname in ($1))=$2"; }
ks() { echo "(select count(*) from pg_constraint where connamespace='public'::regnamespace and conname in ($1))=$2"; }
tg() { echo "(select count(*) from pg_trigger where not tgisinternal and tgname in ($1))=$2"; }
fn() { echo "(select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in ($1))=$2"; }
# 085-111 yardimcilari: kd = kisit tanimi METIN icerir (position: LIKE joker karakteri yok), kv = adi verilen kisitlar DOGRULANMIS (NOT VALID degil), fm = islev govdesi surum isareti tasir.
kd() { echo "(select count(*) from pg_constraint where connamespace='public'::regnamespace and conname='$1' and position('$2' in pg_get_constraintdef(oid)) > 0)=1"; }
kv() { echo "(select count(*) from pg_constraint where connamespace='public'::regnamespace and conname in ($1) and convalidated)=$2"; }
fm() { echo "(select count(*) from pg_proc where pronamespace='public'::regnamespace and proname='$1' and position('-- $2:' in prosrc) > 0)=1"; }
SEMA_N=0; SEMA_BAD=0
sema() {
  local label="$1" r
  r="$(q1 "select $2")"
  SEMA_N=$((SEMA_N + 1))
  if [ "$r" = "t" ]; then echo "OK      $label"; else SEMA_BAD=$((SEMA_BAD + 1)); echo "SORUNLU $label (sonuc: ${r:-<bos>})"; fi
}
# 085 (kalici deneme sinirlari): tablo + 7 sutun + PK / 3 CHECK + zaman indeksi.
sema "085 kalici deneme sinirlari (auth_attempt_limits)" "$(tb "'auth_attempt_limits'" 1) and $(cl "'auth_attempt_limits.scope','auth_attempt_limits.target','auth_attempt_limits.fail_count','auth_attempt_limits.window_started_at','auth_attempt_limits.locked_until','auth_attempt_limits.lock_level','auth_attempt_limits.updated_at'" 7) and $(ks "'pk_auth_attempt_limits','chk_auth_attempt_limits_scope','chk_auth_attempt_limits_target','chk_auth_attempt_limits_counters'" 4) and $(ix "'idx_auth_attempt_limits_updated'" 1)"
# 088 (alacak iadesi): 2 tablo, account_movements.refund_id, 15 CHECK/tekil + 10 FK, 10 indeks, 5 tetikleyici, 2 islev (surum isareti fr:), hareket / defter CHECK'leri 'refund' (+ 'liability_transfer') kabul eder ve DOGRULANMIS (NOT VALID kalmamali).
sema "088 alacak iadesi (finance_refunds, iade hareketi, kaynak CHECK)" "$(tb "'finance_refunds','finance_refund_counters'" 2) and $(cl "'account_movements.refund_id'" 1) and $(ks "'chk_finance_refunds_party','chk_finance_refunds_amount','chk_finance_refunds_status','chk_finance_refunds_requester','chk_finance_refunds_method','chk_finance_refunds_text','chk_finance_refunds_resolved','chk_finance_refunds_rejected','chk_finance_refunds_approved','chk_finance_refunds_reversed','chk_finance_refunds_receipt','chk_finance_refunds_keys','uq_finance_refunds_idempotency','chk_finance_refund_counters_last','chk_finance_refund_counters_year'" 15) and $(ks "'finance_refunds_site_code_fkey','finance_refunds_apartment_id_fkey','finance_refunds_requested_by_fkey','finance_refunds_resolved_by_fkey','finance_refunds_reversed_by_fkey','finance_refunds_pay_account_id_fkey','finance_refunds_ledger_entry_id_fkey','finance_refunds_reversal_ledger_entry_id_fkey','finance_refund_counters_site_code_fkey','account_movements_refund_id_fkey'" 10) and $(ix "'idx_finance_refunds_site_status','idx_finance_refunds_apartment','idx_finance_refunds_requested_by','idx_finance_refunds_resolved_by','idx_finance_refunds_reversed_by','uq_finance_refunds_ledger','uq_finance_refunds_reversal_ledger','idx_finance_refunds_pay_account','uq_finance_refunds_receipt','uq_account_movements_refund'" 10) and $(tg "'trg_finance_refunds_guard','trg_finance_refunds_no_truncate','trg_finance_refund_counters_guard','trg_finance_refund_counters_no_truncate','trg_account_movements_check_refund'" 5) and $(fn "'trg_finance_refunds_guard','trg_account_movements_check_refund'" 2) and $(fm trg_finance_refunds_guard fr) and $(fm trg_account_movements_check_refund fr) and $(kd chk_account_movements_kind refund) and $(kd chk_account_movements_sign refund) and $(kd chk_account_movements_source refund_id) and $(kd chk_ledger_entries_source refund) and $(kd chk_ledger_entries_source liability_transfer) and $(kv "'chk_account_movements_kind','chk_account_movements_sign','chk_account_movements_source','chk_ledger_entries_source'" 4)"
# 089 (kiraci borcunun malike devri): tablo, 11 kisit (7 CHECK/tekil + 4 FK), 3 indeks, 3 tetikleyici, kontrol islevi (surum isareti fl:).
sema "089 kiraci borcunun malike devri (finance_liability_transfers)" "$(tb "'finance_liability_transfers'" 1) and $(ks "'chk_finance_liability_transfers_parties','chk_finance_liability_transfers_total','chk_finance_liability_transfers_count','chk_finance_liability_transfers_reason','chk_finance_liability_transfers_hash','chk_finance_liability_transfers_key','uq_finance_liability_transfers_idempotency','finance_liability_transfers_site_code_fkey','finance_liability_transfers_apartment_id_fkey','finance_liability_transfers_created_by_fkey','finance_liability_transfers_reverses_fkey'" 11) and $(ix "'idx_finance_liability_transfers_apartment','uq_finance_liability_transfers_reverses','idx_finance_liability_transfers_created_by'" 3) and $(tg "'trg_finance_liability_transfers_immutable','trg_finance_liability_transfers_no_truncate','trg_finance_liability_transfers_check'" 3) and $(fn "'trg_finance_liability_transfers_check'" 1) and $(fm trg_finance_liability_transfers_check fl)"
# 090 (demirbas / fon tahakkukunun dayanagi): fee_runs 2 sutun, CHECK (DOGRULANMIS) + board_decisions'a bilesik FK, kismi indeks.
sema "090 fon tahakkuku dayanagi (fee_runs.decision_id / decision_reason)" "$(cl "'fee_runs.decision_id','fee_runs.decision_reason'" 2) and $(ks "'chk_fee_runs_decision','fee_runs_decision_fkey'" 2) and $(kv "'chk_fee_runs_decision'" 1) and $(kd fee_runs_decision_fkey board_decisions) and $(ix "'idx_fee_runs_decision'" 1)"
# 091 (aidat dagitim tabani person_count): db.js bu adimin hatasini YALNIZ loglar (acilisi durdurmaz); kisit person_count icermiyorsa prova burada yakalar. Eski kume (land_share) korunur.
sema "091 aidat dagitim kisiti (person_count)" "$(kd chk_fee_definitions_distribution person_count) and $(kd chk_fee_definitions_distribution land_share)"
# 096 (is kaydi <-> ekipman bagi, fotograf etiketi): 2 sutun, FK + CHECK, kismi indeks, olay turu kisiti equipment_changed kabul eder.
sema "096 is kaydi ekipman bagi + fotograf once/sonra etiketi" "$(cl "'work_items.equipment_id','work_item_attachments.phase'" 2) and $(ks "'work_items_equipment_id_fkey','chk_work_item_attachments_phase'" 2) and $(ix "'idx_work_items_equipment'" 1) and $(kd chk_work_item_events_type equipment_changed)"
# 097 (Drive dosya kaydi <-> kaynak kayit): 2 sutun, CHECK (bilerek NOT VALID; eski satirlar NULL/NULL), kismi indeks.
sema "097 drive dosyasi kaynak baglantisi (source_type / source_id)" "$(cl "'drive_files.source_type','drive_files.source_id'" 2) and $(ks "'chk_drive_files_source'" 1) and $(ix "'idx_drive_files_source'" 1)"
# 098 (teklif karsilastirma): equipment_quotes 3 yeni sutun + 2 CHECK.
sema "098 teklif karsilastirma alanlari (equipment_quotes)" "$(cl "'equipment_quotes.delivery_days','equipment_quotes.note','equipment_quotes.vat_included'" 3) and $(ks "'chk_equipment_quotes_delivery','chk_equipment_quotes_note'" 2)"
# 099 (onayli teklif revizyonu): 3 sutun, 4 CHECK + tekil + bilesik FK, halef tekil indeksi, degismezlik tetikleyicisi ve islevi (surum isareti eqq:).
sema "099 onayli teklif revizyonu (equipment_quotes degismezlik)" "$(cl "'equipment_quotes.revision_no','equipment_quotes.previous_id','equipment_quotes.revision_reason'" 3) and $(ks "'chk_equipment_quotes_revision_no','chk_equipment_quotes_revision_reason','chk_equipment_quotes_previous_self','chk_equipment_quotes_revision','uq_equipment_quotes_site_id','equipment_quotes_previous_fkey'" 6) and $(ix "'uq_equipment_quotes_previous'" 1) and $(tg "'trg_equipment_quotes_locked'" 1) and $(fn "'trg_equipment_quotes_locked'" 1) and $(fm trg_equipment_quotes_locked eqq)"
# 100 (is takibi kategorileri): tablo, 6 kisit, 4 indeks; work_items kategori CHECK'i yeni anahtar kumesine gecti (eski chk_work_items_category YOK, chk_work_items_category_key VAR ve k_<ad> kalibini icerir).
sema "100 is takibi kategorileri (work_categories)" "$(tb "'work_categories'" 1) and $(ks "'work_categories_site_code_fkey','work_categories_created_by_fkey','chk_work_categories_key','chk_work_categories_label_length','chk_work_categories_sort_order','chk_work_categories_system_key','chk_work_items_category_key'" 7) and $(ks "'chk_work_items_category'" 0) and $(kd chk_work_items_category_key '{1,38}') and $(ix "'uq_work_categories_site_key','uq_work_categories_site_label','idx_work_items_site_category','idx_work_item_attachments_site_sha256'" 4)"
# 102 (site menu yerlesimi): tablo + 4 sutun + CHECK ve iki FK (satir iceri-baglantili; adlar PostgreSQL varsayilani).
sema "102 site menu yerlesimi (site_menu_layouts)" "$(tb "'site_menu_layouts'" 1) and $(cl "'site_menu_layouts.site_code','site_menu_layouts.compact_modules','site_menu_layouts.updated_by','site_menu_layouts.updated_at'" 4) and $(ks "'chk_site_menu_layouts_size','site_menu_layouts_site_code_fkey','site_menu_layouts_updated_by_fkey'" 3)"
# 103 (geri bildirim): 2 tablo, 12 CHECK + 3 FK, 5 indeks.
sema "103 geri bildirim (feedback_reports / feedback_attachments)" "$(tb "'feedback_reports','feedback_attachments'" 2) and $(ks "'chk_feedback_reports_role','chk_feedback_reports_screen_name','chk_feedback_reports_screen_route','chk_feedback_reports_message','chk_feedback_reports_app_version','chk_feedback_reports_platform','chk_feedback_attachments_file_name','chk_feedback_attachments_mime','chk_feedback_attachments_size','chk_feedback_attachments_status','chk_feedback_attachments_ready','chk_feedback_attachments_sha256','feedback_reports_site_code_fkey','feedback_reports_user_code_fkey','feedback_attachments_feedback_id_fkey'" 15) and $(ix "'idx_feedback_reports_site','idx_feedback_reports_user_created','idx_feedback_attachments_feedback','idx_feedback_attachments_uploading','uq_feedback_attachments_storage_key'" 5)"
# 110 (kontrol izi): 2 yan tablo, 6 FK, 4 indeks (gider ve dekont satirlari degismez; iz ayri tablodadir).
sema "110 kontrol izi (expense_check_marks / payment_notice_check_marks)" "$(tb "'expense_check_marks','payment_notice_check_marks'" 2) and $(ks "'expense_check_marks_expense_id_fkey','expense_check_marks_site_code_fkey','expense_check_marks_checked_by_fkey','payment_notice_check_marks_notice_id_fkey','payment_notice_check_marks_site_code_fkey','payment_notice_check_marks_checked_by_fkey'" 6) and $(ix "'idx_expense_check_marks_site','idx_expense_check_marks_by','idx_payment_notice_check_marks_site','idx_payment_notice_check_marks_by'" 4)"
# 111 (is kaydi <-> firma yonlendirmesi): work_items 5 sutun, 2 CHECK, durum kisiti firmada kabul eder.
sema "111 is kaydi firma yonlendirmesi (work_items.vendor_*, firmada durumu)" "$(cl "'work_items.vendor_name','work_items.vendor_contact','work_items.vendor_phone','work_items.vendor_amount_kurus','work_items.vendor_referred_at'" 5) and $(ks "'chk_work_items_vendor','chk_work_items_firmada_vendor'" 2) and $(kd chk_work_items_status firmada)"
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
echo "== ozet (sema varlik 085-111)"; if [ "$SEMA_BAD" = 0 ]; then echo "SEMA_085_111_OK ($SEMA_N/$SEMA_N)"; else echo "SEMA_085_111_SORUNLU ($SEMA_BAD/$SEMA_N eksik)"; fi
