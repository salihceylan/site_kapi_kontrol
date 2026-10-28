#!/bin/bash
# Demo sitesinde ARACI OLMAYAN her aileye (daire) bir arac ekler SUNUCUDA (VPS) (add_vehicles.mjs):
#   1) pg_dump yedegi, 2) yedekten gecici DB, 3) PROVA: arac ekleme + cleanup provasi (tum tablo satir sayilari ve vehicles icerigi ayni mi), 4) --prod ile canli.
#
# On kosul: tools/demo_seed klasoru sunucuya kopyalandi (ornegin ~/demo_seed), server/node_modules kurulu (/var/www/site_kapi_kontrol/server):
#   scp -r tools/demo_seed <kullanici>@<sunucu>:~/demo_seed
#
# Kullanim (sunucuda, uygulamayi calistiran isletim sistemi kullanicisiyla):
#   bash run_remote_vehicles.sh [--site Cenk] [--seed N] [--prod] [--skip-rehearsal] [--force]
#   --prod            provadan sonra CANLI veritabanina da uygular (bayraksiz yalniz yedek + prova)
#   --skip-rehearsal  prova adimini atlar (yalniz yedek + canli; ONERILMEZ)
#   --force           demo tohum korumasini asar (ONERILMEZ)
#
# Idempotent: zaten aktif araci olan daireye dokunulmaz; ikinci calistirma bir sey eklemez.
# .env dosyasi source EDILMEZ: DATABASE_URL node + dotenv ile okunur (parola ekrana yazilmaz). E-posta / bildirim GONDERILMEZ (yalniz vehicles + demo_seed_registry).
# Geri alma: node cleanup.mjs --batch <demo-vehicles-...> --yes --allow-target <canli veritabani adi>   (tohum / yeniden yapilandirma batch'inden ONCE; SUPERUSER gerekir).
# Hedef korumasi: araclar yalniz yerel (loopback + izinli ad) ya da --allow-target <ad> ile onaylanmis veritabanina yazar; bu betik provada $RDB, canlida $DB_NAME icin kendisi verir.
set -uo pipefail

SITE="Cenk"
SEED=""
PROD=0
FORCE=0
SKIP_REH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --site) SITE="$2"; shift 2 ;;
    --seed) SEED="$2"; shift 2 ;;
    --prod) PROD=1; shift ;;
    --force) FORCE=1; shift ;;
    --skip-rehearsal) SKIP_REH=1; shift ;;
    *) echo "Bilinmeyen bayrak: $1"; exit 2 ;;
  esac
done

SEED_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${APP_DIR:-/var/www/site_kapi_kontrol/server}"
ENVF="${KAPI_ENV_FILE:-$APP_DIR/.env}"
DBC="${PG_CONTAINER:-site_kapi_kontrol_postgres}"
PSQL="docker exec -i $DBC psql -U postgres"
STAMP="$(date +%Y%m%d_%H%M%S)"
BK="${BACKUP_DIR:-$HOME/backups/demo_vehicles_$STAMP}"
RDB="demo_veh_rehearsal_$STAMP"
OUT="$SEED_DIR/out"
mkdir -p "$BK" "$OUT"
chmod 700 "$BK"
EXTRA=""
[ "$FORCE" = 1 ] && EXTRA="$EXTRA --force"
[ -n "$SEED" ] && EXTRA="$EXTRA --seed $SEED"

[ -d "$APP_DIR/node_modules" ] || { echo "HATA: $APP_DIR/node_modules yok"; exit 2; }
[ -f "$ENVF" ] || { echo "HATA: $ENVF yok"; exit 2; }

# --- DATABASE_URL (parola ekrana yazilmaz) -----------------------------------------------------------------------------------------------
mk_url() {
  # $1 = veritabani adi (bos ise .env'deki DB_NAME)
  (cd "$APP_DIR" && node -e "
    require('dotenv').config({ path: process.argv[1] });
    const e = process.env; const enc = encodeURIComponent;
    const db = process.argv[2] || e.DB_NAME;
    process.stdout.write('postgres://' + enc(e.DB_USER) + ':' + enc(e.DB_PASSWORD || '') + '@' + (e.DB_HOST || '127.0.0.1') + ':' + (e.DB_PORT || 5432) + '/' + db);
  " "$ENVF" "$1")
}
PROD_URL="$(mk_url "")"
DB_NAME="$(cd "$APP_DIR" && node -e "require('dotenv').config({ path: process.argv[1] }); process.stdout.write(process.env.DB_NAME || '')" "$ENVF")"
[ -n "$DB_NAME" ] || { echo "HATA: DB_NAME okunamadi"; exit 2; }
DB_USER="$(cd "$APP_DIR" && node -e "require('dotenv').config({ path: process.argv[1] }); process.stdout.write(process.env.DB_USER || '')" "$ENVF")"
[ -n "$DB_USER" ] || { echo "HATA: DB_USER okunamadi"; exit 2; }
echo "Canli veritabani adi: $DB_NAME   (kapsayici: $DBC)"

# --- 1) yedek -------------------------------------------------------------------------------------------------------------------------------
echo "[1/4] pg_dump yedegi -> $BK/db_before_vehicles.dump"
docker exec "$DBC" pg_dump -U postgres -Fc "$DB_NAME" > "$BK/db_before_vehicles.dump" || { echo "HATA: pg_dump basarisiz"; exit 3; }
chmod 600 "$BK/db_before_vehicles.dump"
SIZE=$(stat -c %s "$BK/db_before_vehicles.dump" 2>/dev/null || wc -c < "$BK/db_before_vehicles.dump")
[ "${SIZE:-0}" -gt 10000 ] || { echo "HATA: yedek cok kucuk ($SIZE bayt)"; exit 3; }
echo "   yedek boyutu: $SIZE bayt"

# vehicles icerik ozeti + tum tablolarin satir sayilari (prova karsilastirmasi)
digest() {
  # $1 = veritabani
  $PSQL -d "$1" -Atc "SELECT 'vehicles|' || count(*) || '|' || md5(COALESCE(string_agg(x::text, '|' ORDER BY x.id), '')) FROM vehicles x"
  $PSQL -d "$1" -Atc "SELECT table_name || '|' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text
    FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name <> 'demo_seed_registry' ORDER BY 1"
}

# --- 2-3) prova -------------------------------------------------------------------------------------------------------------------------------
if [ "$SKIP_REH" = 0 ]; then
  echo "[2/4] gecici veritabani: $RDB (yedekten)"
  $PSQL -qc "CREATE DATABASE \"$RDB\" OWNER \"$DB_USER\"" || exit 4
  trap '$PSQL -qc "DROP DATABASE IF EXISTS \"$RDB\" WITH (FORCE)" >/dev/null 2>&1; rm -f "$OUT/vehicles-report-rehearsal-$STAMP.json"' EXIT
  docker exec -i "$DBC" pg_restore -U postgres -d "$RDB" --no-owner --role="$DB_USER" < "$BK/db_before_vehicles.dump" 2> "$BK/restore.err"
  echo "   yukleme uyarilari (ilk 3): $(head -n 3 "$BK/restore.err" | cut -c1-120 | tr '\n' '|')"
  REH_URL="$(mk_url "$RDB")"
  digest "$RDB" > "$BK/digest_before.txt"
  echo "[3/4] PROVA: arac ekleme gecici veritabaninda"
  (cd "$APP_DIR" && DATABASE_URL="$REH_URL" node "$SEED_DIR/add_vehicles.mjs" --server-dir "$APP_DIR" --allow-target "$RDB" --site "$SITE" --report-out "$OUT/vehicles-report-rehearsal-$STAMP.json" $EXTRA) | tee "$BK/rehearsal_vehicles.log" | tail -n 40
  RC=${PIPESTATUS[0]}
  [ "$RC" = 0 ] || { echo "HATA: prova basarisiz (cikis $RC). Canliya GECILMEZ."; exit 5; }
  BATCH="$(grep -o 'batch=demo-vehicles-[0-9]*' "$BK/rehearsal_vehicles.log" | head -n 1 | cut -d= -f2)"
  if grep -q "TAMAM:" "$BK/rehearsal_vehicles.log"; then
    echo "   prova batch: $BATCH"
    echo "   --- cleanup provasi ---"
    (cd "$APP_DIR" && DATABASE_URL="$REH_URL" node "$SEED_DIR/cleanup.mjs" --server-dir "$APP_DIR" --allow-target "$RDB" --batch "$BATCH" --yes) | tail -n 6
    digest "$RDB" > "$BK/digest_after_cleanup.txt"
    if diff -q "$BK/digest_before.txt" "$BK/digest_after_cleanup.txt" >/dev/null; then
      echo "   cleanup SONRASI vehicles icerigi ve tum tablo satir sayilari yedekle AYNI: OK"
    else
      echo "HATA: cleanup sonrasi fark var:"; diff "$BK/digest_before.txt" "$BK/digest_after_cleanup.txt" | head -n 20
      echo "Canliya GECILMEZ."; exit 6
    fi
  else
    echo "   prova: eklenecek arac yok (her dairede arac var ya da atlandi); cleanup provasi gerekmedi."
  fi
fi

# --- 4) canli -----------------------------------------------------------------------------------------------------------------------------------
if [ "$PROD" = 1 ]; then
  REPORT="$OUT/vehicles-report-$STAMP.json"
  echo "[4/4] CANLI: arac ekleme $DB_NAME veritabaninda (yedek: $BK/db_before_vehicles.dump)"
  (cd "$APP_DIR" && DATABASE_URL="$PROD_URL" node "$SEED_DIR/add_vehicles.mjs" --server-dir "$APP_DIR" --allow-target "$DB_NAME" --site "$SITE" --report-out "$REPORT" $EXTRA) | tee "$BK/prod_vehicles.log" | tail -n 45
  RC=${PIPESTATUS[0]}
  BATCH_PROD="$(grep -o 'batch=demo-vehicles-[0-9]*' "$BK/prod_vehicles.log" | head -n 1 | cut -d= -f2)"
  echo "   canli batch: $BATCH_PROD   cikis kodu: $RC"
  echo "   rapor (sifre/kimlik YOK): $REPORT"
  echo "   YEREL MAKINEDE plaka onizlemesi (PNG): scp <sunucu>:$REPORT out/ && python make_plate_previews.py --report out/$(basename "$REPORT")   (pip install pillow)"
  echo "   GERI ALMA: (cd $APP_DIR && DATABASE_URL=<canli-url> node $SEED_DIR/cleanup.mjs --server-dir $APP_DIR --batch $BATCH_PROD --yes --allow-target $DB_NAME)"
  exit "$RC"
else
  echo "[4/4] --prod verilmedi: canliya yazilmadi. Prova basarili ise: bash run_remote_vehicles.sh --prod --skip-rehearsal"
fi
