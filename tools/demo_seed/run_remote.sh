#!/bin/bash
# Demo tohumunu SUNUCUDA (VPS) calistirir: 1) pg_dump yedegi, 2) yedekten gecici DB, 3) tohum + cleanup provasi gecici DB'de, 4) --prod ile canliya.
#
# On kosul: tools/demo_seed klasoru sunucuya kopyalandi (ornegin ~/demo_seed) ve server/node_modules kurulu (/var/www/site_kapi_kontrol/server).
#   scp -r tools/demo_seed <kullanici>@<sunucu>:~/demo_seed
#
# Kullanim (sunucuda, uygulamayi calistiran isletim sistemi kullanicisiyla; belge dosyalari PM2 kullanicisinin okuyabilecegi yere yazilir):
#   bash run_remote.sh [--site Cenk] [--creds-out ~/demo_seed/out/creds.json] [--prod] [--force] [--skip-rehearsal]
#   --prod            provadan sonra CANLI veritabanina da calistirir (bayraksiz yalniz prova + yedek)
#   --force           tohum korumalarini asar (sitede veri varsa; ONERILMEZ)
#   --skip-rehearsal  prova adimini atlar (yalniz yedek + canli; ONERILMEZ)
#
# .env dosyasi source EDILMEZ: DATABASE_URL node + dotenv ile okunur (parola ekrana yazilmaz).
# Geri alma: node cleanup.mjs --batch <id> --yes --allow-target <canli veritabani adi>   (DATABASE_URL ayni bicimde; SUPERUSER gerekir)
# Hedef korumasi: araclar yalniz yerel (loopback + izinli ad) ya da --allow-target <ad> ile onaylanmis veritabanina yazar; bu betik provada $RDB, canlida $DB_NAME icin kendisi verir.
set -uo pipefail

SITE="Cenk"
CREDS_OUT=""
PROD=0
FORCE=0
SKIP_REH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --site) SITE="$2"; shift 2 ;;
    --creds-out) CREDS_OUT="$2"; shift 2 ;;
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
BK="${BACKUP_DIR:-$HOME/backups/demo_seed_$STAMP}"
RDB="demo_seed_rehearsal_$STAMP"
OUT="$SEED_DIR/out"
mkdir -p "$BK" "$OUT"
chmod 700 "$BK"
[ -n "$CREDS_OUT" ] || CREDS_OUT="$OUT/creds_$STAMP.json"
EXTRA=""
[ "$FORCE" = 1 ] && EXTRA="--force"

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
echo "[1/4] pg_dump yedegi -> $BK/db_before_demo.dump"
docker exec "$DBC" pg_dump -U postgres -Fc "$DB_NAME" > "$BK/db_before_demo.dump" || { echo "HATA: pg_dump basarisiz"; exit 3; }
chmod 600 "$BK/db_before_demo.dump"
SIZE=$(stat -c %s "$BK/db_before_demo.dump" 2>/dev/null || wc -c < "$BK/db_before_demo.dump")
[ "${SIZE:-0}" -gt 10000 ] || { echo "HATA: yedek cok kucuk ($SIZE bayt)"; exit 3; }
echo "   yedek boyutu: $SIZE bayt"

counts() {
  # $1 = veritabani; cikti: tablo|satir sayisi (registry haric)
  $PSQL -d "$1" -Atc "SELECT table_name || '|' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text
    FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name <> 'demo_seed_registry' ORDER BY 1"
}

# --- 2-3) prova -------------------------------------------------------------------------------------------------------------------------------
if [ "$SKIP_REH" = 0 ]; then
  echo "[2/4] gecici veritabani: $RDB (yedekten)"
  $PSQL -qc "CREATE DATABASE \"$RDB\" OWNER \"$DB_USER\"" || exit 4
  trap '$PSQL -qc "DROP DATABASE IF EXISTS \"$RDB\" WITH (FORCE)" >/dev/null 2>&1' EXIT
  docker exec -i "$DBC" pg_restore -U postgres -d "$RDB" --no-owner --role="$DB_USER" < "$BK/db_before_demo.dump" 2> "$BK/restore.err"
  echo "   yukleme uyarilari (ilk 3): $(head -n 3 "$BK/restore.err" | cut -c1-120 | tr '\n' '|')"
  REH_URL="$(mk_url "$RDB")"
  counts "$RDB" > "$BK/counts_before.txt"
  echo "[3/4] PROVA: tohum gecici veritabaninda"
  (cd "$APP_DIR" && DATABASE_URL="$REH_URL" node "$SEED_DIR/seed.mjs" --server-dir "$APP_DIR" --allow-target "$RDB" --site "$SITE" --creds-out "$OUT/creds_rehearsal_$STAMP.json" $EXTRA) | tee "$BK/rehearsal_seed.log" | tail -n 40
  SEED_RC=${PIPESTATUS[0]}
  [ "$SEED_RC" = 0 ] || { echo "HATA: prova tohumu basarisiz (cikis $SEED_RC). Canliya GECILMEZ."; exit 5; }
  BATCH="$(grep -o 'batch=demo-[0-9]*' "$BK/rehearsal_seed.log" | head -n 1 | cut -d= -f2)"
  echo "   prova batch: $BATCH"
  echo "   --- kayitli satirlar (tablo bazinda ilk 12) ---"
  $PSQL -d "$RDB" -Atc "SELECT table_name || ' ' || count(*) FROM demo_seed_registry WHERE batch_id = '$BATCH' AND op = 'insert' GROUP BY 1 ORDER BY count(*) DESC LIMIT 12"
  echo "   --- cleanup provasi ---"
  (cd "$APP_DIR" && DATABASE_URL="$REH_URL" node "$SEED_DIR/cleanup.mjs" --server-dir "$APP_DIR" --allow-target "$RDB" --batch "$BATCH" --yes) | tail -n 8
  counts "$RDB" > "$BK/counts_after_cleanup.txt"
  if diff -q "$BK/counts_before.txt" "$BK/counts_after_cleanup.txt" >/dev/null; then
    echo "   cleanup SONRASI tum tablolar yedekle AYNI sayida satir: OK"
  else
    echo "HATA: cleanup sonrasi satir sayilari farkli:"; diff "$BK/counts_before.txt" "$BK/counts_after_cleanup.txt" | head -n 20
    echo "Canliya GECILMEZ."; exit 6
  fi
fi

# --- 4) canli -----------------------------------------------------------------------------------------------------------------------------------
if [ "$PROD" = 1 ]; then
  echo "[4/4] CANLI: tohum $DB_NAME veritabaninda (yedek: $BK/db_before_demo.dump)"
  (cd "$APP_DIR" && DATABASE_URL="$PROD_URL" node "$SEED_DIR/seed.mjs" --server-dir "$APP_DIR" --allow-target "$DB_NAME" --site "$SITE" --creds-out "$CREDS_OUT" $EXTRA) | tee "$BK/prod_seed.log" | tail -n 45
  RC=${PIPESTATUS[0]}
  BATCH_PROD="$(grep -o 'batch=demo-[0-9]*' "$BK/prod_seed.log" | head -n 1 | cut -d= -f2)"
  echo "   canli batch: $BATCH_PROD   cikis kodu: $RC"
  echo "   kimlik bilgileri: $CREDS_OUT (chmod 600). PDF icin: python3 $SEED_DIR/make_pdf.py --creds $CREDS_OUT --out $OUT/demo_hesaplar.pdf   (reportlab gerekir; yoksa dosyayi yerel makineye alip orada uretin)"
  echo "   KAPAT: kimlik dosyasini kopyaladiktan sonra sunucudan silin (shred -u $CREDS_OUT)."
  echo "   GERI ALMA: (cd $APP_DIR && DATABASE_URL=<canli-url> node $SEED_DIR/cleanup.mjs --server-dir $APP_DIR --batch $BATCH_PROD --yes --allow-target $DB_NAME)"
  exit "$RC"
else
  echo "[4/4] --prod verilmedi: canliya yazilmadi. Prova basarili ise: bash run_remote.sh --prod --skip-rehearsal"
fi
