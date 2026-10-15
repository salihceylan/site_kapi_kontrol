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
typed=$($PSQL -d "$RDB" -Atc "select count(*) from sites where management_type='apartment_site'")
echo "   sonra: sites=$after_sites (apartment_site=$typed) users=$after_users site_memberships=$after_sm"
echo "   tablolar: $($PSQL -d "$RDB" -Atc "select string_agg(table_name, ',') from information_schema.tables where table_schema='public' and table_name in ('site_modules','audit_log')")"
echo "   site_modules satir: $($PSQL -d "$RDB" -Atc "select count(*) from site_modules") (0 olmali)"
echo "   site_memberships CHECK: $($PSQL -d "$RDB" -Atc "select string_agg(conname, ',') from pg_constraint where conrelid='site_memberships'::regclass and contype='c'")"
echo "   rol dagilimi: $($PSQL -d "$RDB" -Atc "select string_agg(role||'='||n, ',') from (select role, count(*) n from site_memberships group by role) t")"
if [ "$before_sites" = "$after_sites" ] && [ "$before_users" = "$after_users" ] && [ "$before_sm" = "$after_sm" ] && [ "$typed" = "$after_sites" ]; then
  echo "PROVA_OK"
else
  echo "PROVA_SORUNLU"
fi
echo "[5/5] gecici veritabani siliniyor"
