#!/bin/bash
# Canli veritabani YEDEGINI gecici bir veritabanina yukleyip yeni kodun ensureDbSchema()'sini orada iki kez calistirir (canli DB'ye dokunmaz).
# Kullanim: bash remote_rehearse_schema.sh <TS>   (once remote_deploy.sh <TS> prepare calismis olmali)
set -u
TS="$1"
DBC=site_kapi_kontrol_postgres
RDB="kapi_rehearsal_${TS}"
STAGE="$HOME/kapi_stage_$TS"
BK="$HOME/backups/kapi_$TS"
ENVF=/var/www/site_kapi_kontrol/server/.env
PSQL="docker exec -i $DBC psql -U postgres"

cleanup() { $PSQL -qc "DROP DATABASE IF EXISTS \"$RDB\"" >/dev/null 2>&1; }
trap cleanup EXIT

[ -d "$STAGE/node_modules" ] || { echo "HATA: hazirlik yok"; exit 2; }
echo "[1/5] gecici veritabani: $RDB"
$PSQL -qc "CREATE DATABASE \"$RDB\"" || exit 3
echo "[2/5] yedek yukleniyor"
gunzip -c "$BK/db.sql.gz" | $PSQL -d "$RDB" -q -v ON_ERROR_STOP=0 >/dev/null 2>"$HOME/rehearse_restore_$TS.err"
echo "   yukleme uyarilari (ilk 3): $(head -n 3 "$HOME/rehearse_restore_$TS.err" | cut -c1-120 | tr '\n' '|')"
before_sites=$($PSQL -d "$RDB" -Atc "select count(*) from sites")
before_users=$($PSQL -d "$RDB" -Atc "select count(*) from users")
before_doors=$($PSQL -d "$RDB" -Atc "select count(*) from site_doors")
before_sm=$($PSQL -d "$RDB" -Atc "select count(*) from site_memberships")
before_am=$($PSQL -d "$RDB" -Atc "select count(*) from apartment_memberships where is_active")
echo "   once: sites=$before_sites users=$before_users doors=$before_doors site_memberships=$before_sm"
echo "[3/5] yeni ensureDbSchema (2 kez, ikinci tur no-op olmali)"
cd "$STAGE" || exit 4
export $(grep -E '^(DB_HOST|DB_PORT|DB_USER|DB_PASSWORD)=' "$ENVF" | xargs)
export DB_NAME="$RDB"
for i in 1 2; do
  node --input-type=module -e "const m = await import('./src/db.js'); await m.ensureDbSchema(); console.log('ENSURE_OK tur $i'); process.exit(0)" 2>&1 | cut -c1-220 | tail -n 6
done
echo "[4/5] dogrulama"
after_sites=$($PSQL -d "$RDB" -Atc "select count(*) from sites")
after_users=$($PSQL -d "$RDB" -Atc "select count(*) from users")
after_sm=$($PSQL -d "$RDB" -Atc "select count(*) from site_memberships")
after_am=$($PSQL -d "$RDB" -Atc "select count(*) from apartment_memberships where is_active")
typed=$($PSQL -d "$RDB" -Atc "select count(*) from sites where management_type='apartment_site'")
echo "   aktif daire uyeligi once/sonra: $before_am/$after_am"
echo "   sonra: sites=$after_sites (apartment_site=$typed) users=$after_users site_memberships=$after_sm"
echo "   tablolar: $($PSQL -d "$RDB" -Atc "select string_agg(table_name, ',') from information_schema.tables where table_schema='public' and table_name in ('site_modules','audit_log')")"
echo "   site_modules satir: $($PSQL -d "$RDB" -Atc "select count(*) from site_modules") (bilgi: canlida yonetici bir modulu degistirdiyse 0dan buyuk olur)"
q() { $PSQL -d "$RDB" -Atc "$1" 2>&1 | head -n 1; }
echo "   [031] tablolar: $(q "select string_agg(table_name, ',' order by table_name) from information_schema.tables where table_schema='public' and table_name in ('site_people','apartment_residencies','vehicles','platform_backfills')")"
echo "   [031] backfill: $(q "select coalesce(string_agg(code, ','), 'YOK') from platform_backfills")"
echo "   [031] tetikleyici: $(q "select count(*) from pg_trigger where tgname='trg_users_preserve_site_people' and not tgisinternal") (1 olmali)"
echo "   [031] kisi=$(q "select count(*) from site_people") (hesapli=$(q "select count(*) from site_people where user_code is not null")) iliski=$(q "select count(*) from apartment_residencies") (guncel=$(q "select count(*) from apartment_residencies where is_current")) origin_sync=$(q "select count(*) from apartment_residencies where origin='sync'") arac=$(q "select count(*) from vehicles")"
echo "   [031] aktif daire uyeligi=$(q "select count(*) from apartment_memberships where is_active") (kapi yetkisi satirlari DEGISMEMELI) toplam=$(q "select count(*) from apartment_memberships")"
echo "   [031] guncel iliski olmayan aktif uyelik (0 olmali): $(q "select count(*) from apartment_memberships am where am.is_active and exists (select 1 from apartments a where a.id=am.apartment_id and a.is_active) and not exists (select 1 from site_people p join apartment_residencies r on r.person_id=p.id and r.is_current where p.user_code=am.user_code and r.apartment_id=am.apartment_id)")"
echo "   [032] tablolar: $(q "select string_agg(table_name, ',' order by table_name) from information_schema.tables where table_schema='public' and table_name in ('announcements','announcement_recipients','notification_preferences','announcement_email_suppressions')") (4 olmali)"
echo "   [032] satirlar: duyuru=$(q "select count(*) from announcements") alici=$(q "select count(*) from announcement_recipients") tercih=$(q "select count(*) from notification_preferences") bastirma=$(q "select count(*) from announcement_email_suppressions") (hepsi 0 olmali)"
echo "   [032] sutunlar: $(q "select count(*) from information_schema.columns where table_name in ('announcements','announcement_recipients') and column_name in ('published_by','publish_attempts','next_attempt_at','email_requested_by','email_requested_at','email_hash','email_claimed_at','email_next_at')") (8 olmali)"
echo "   [032] katalog: duyuru modulu eski sayfa/uclar degismedi mi: $(q "select count(*) from site_modules")"
echo "   site_memberships CHECK: $($PSQL -d "$RDB" -Atc "select string_agg(conname, ',') from pg_constraint where conrelid='site_memberships'::regclass and contype='c'")"
echo "   rol dagilimi: $($PSQL -d "$RDB" -Atc "select string_agg(role||'='||n, ',') from (select role, count(*) n from site_memberships group by role) t")"
if [ "$before_sites" = "$after_sites" ] && [ "$before_users" = "$after_users" ] && [ "$before_sm" = "$after_sm" ] && [ "$before_am" = "$after_am" ] && [ "$typed" = "$after_sites" ]; then
  echo "PROVA_OK"
else
  echo "PROVA_SORUNLU"
fi
echo "[5/5] gecici veritabani siliniyor"
