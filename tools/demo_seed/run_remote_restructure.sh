#!/bin/bash
# Demo sitesinin aile yapisini SUNUCUDA (VPS) yeniden duzenler (restructure_families.mjs):
#   1) pg_dump yedegi, 2) yedekten gecici DB, 3) PROVA: yeniden yapilandirma + cleanup provasi (kisi/bag tablolari ayni mi), 4) --prod ile canli.
#
# On kosul: tools/demo_seed klasoru sunucuya kopyalandi (ornegin ~/demo_seed), server/node_modules kurulu (/var/www/site_kapi_kontrol/server),
# ve seed.mjs'in kimlik dosyasi (creds_prod.json) sunucuda (parolalar oradan alinir):
#   scp -r tools/demo_seed <kullanici>@<sunucu>:~/demo_seed
#   scp G:\site\demo_hesaplar\creds_prod.json <kullanici>@<sunucu>:~/demo_seed/out/creds_prod.json
#
# Kullanim (sunucuda, uygulamayi calistiran isletim sistemi kullanicisiyla):
#   bash run_remote_restructure.sh --prev-creds ~/demo_seed/out/creds_prod.json [--site Cenk] [--creds-out ~/demo_seed/out/creds_restructured.json] [--prod] [--skip-rehearsal] [--force]
#   --prev-creds      seed.mjs kimlik JSON'u (ZORUNLU: eski hesaplarin parolalari buradan gelir)
#   --prod            provadan sonra CANLI veritabanina da uygular (bayraksiz yalniz yedek + prova)
#   --skip-rehearsal  prova adimini atlar (yalniz yedek + canli; ONERILMEZ)
#   --force           tohum korumalarini asar (ONERILMEZ; --ensure-composition icin ZORUNLU: onceki restructure batch'i kayitli oldugundan)
#   --extra "<bayraklar>"  restructure_families.mjs'e aynen iletilen ek bayraklar (birden cok kez verilebilir). EXTRA_ARGS ortam degiskeni de ayni isi gorur.
#
# Her ailede cocuk + yasli (ikinci tur; ilk restructure turu CANLIDA calismis olmali; --prev-creds = o turun creds_restructured.json'u):
#   bash run_remote_restructure.sh --prev-creds ~/demo_seed/out/creds_restructured.json --force --extra "--ensure-composition" --prod --skip-rehearsal --creds-out ~/demo_seed/out/creds_composition.json
#   (once --prod'suz calistirip proyi gorun; ayni bayraklarla gecici DB'de de uygulanir ve cleanup provasi yapilir)
#
# .env dosyasi source EDILMEZ: DATABASE_URL node + dotenv ile okunur (parola ekrana yazilmaz). E-posta GONDERILMEZ (davet / bildirim yazilmaz).
# Geri alma: node cleanup.mjs --batch <demo-restructure-...> --yes --allow-target <canli veritabani adi>   (seed batch'inden ONCE; SUPERUSER gerekir).
# Hedef korumasi: araclar yalniz yerel (loopback + izinli ad) ya da --allow-target <ad> ile onaylanmis veritabanina yazar; bu betik provada $RDB, canlida $DB_NAME icin kendisi verir.
set -uo pipefail

SITE="Cenk"
PREV=""
CREDS_OUT=""
PROD=0
FORCE=0
SKIP_REH=0
EXTRA_FLAGS="${EXTRA_ARGS:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --extra) [ $# -ge 2 ] || { echo "HATA: --extra bir deger ister"; exit 2; }; EXTRA_FLAGS="$EXTRA_FLAGS $2"; shift 2 ;;
    --site) SITE="$2"; shift 2 ;;
    --prev-creds) PREV="$2"; shift 2 ;;
    --creds-out) CREDS_OUT="$2"; shift 2 ;;
    --prod) PROD=1; shift ;;
    --force) FORCE=1; shift ;;
    --skip-rehearsal) SKIP_REH=1; shift ;;
    *) echo "Bilinmeyen bayrak: $1"; exit 2 ;;
  esac
done
[ -n "$PREV" ] && [ -f "$PREV" ] || { echo "HATA: --prev-creds <creds_prod.json> gerekli ve dosya bulunmali"; exit 2; }

SEED_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${APP_DIR:-/var/www/site_kapi_kontrol/server}"
ENVF="${KAPI_ENV_FILE:-$APP_DIR/.env}"
DBC="${PG_CONTAINER:-site_kapi_kontrol_postgres}"
PSQL="docker exec -i $DBC psql -U postgres"
STAMP="$(date +%Y%m%d_%H%M%S)"
BK="${BACKUP_DIR:-$HOME/backups/demo_restructure_$STAMP}"
RDB="demo_restr_rehearsal_$STAMP"
OUT="$SEED_DIR/out"
mkdir -p "$BK" "$OUT"
chmod 700 "$BK"
[ -n "$CREDS_OUT" ] || CREDS_OUT="$OUT/creds_restructured_$STAMP.json"
EXTRA=""
[ "$FORCE" = 1 ] && EXTRA="--force"
# ek bayraklar (--extra / EXTRA_ARGS): kelime bolunerek iletilir; yalniz restructure_families.mjs bayraklari verin
[ -n "${EXTRA_FLAGS// /}" ] && EXTRA="$EXTRA $EXTRA_FLAGS"
case " $EXTRA " in *" --ensure-composition "*) echo "Mod: --ensure-composition (her haneye en az 1 cocuk + 1 yasli; yalniz EKLER)"; case " $EXTRA " in *" --force "*) ;; *) echo "UYARI: onceki restructure batch'i kayitli oldugundan --force gerekir; arac --force'suz DURUR." ;; esac ;; esac

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
echo "[1/4] pg_dump yedegi -> $BK/db_before_restructure.dump"
docker exec "$DBC" pg_dump -U postgres -Fc "$DB_NAME" > "$BK/db_before_restructure.dump" || { echo "HATA: pg_dump basarisiz"; exit 3; }
chmod 600 "$BK/db_before_restructure.dump"
SIZE=$(stat -c %s "$BK/db_before_restructure.dump" 2>/dev/null || wc -c < "$BK/db_before_restructure.dump")
[ "${SIZE:-0}" -gt 10000 ] || { echo "HATA: yedek cok kucuk ($SIZE bayt)"; exit 3; }
echo "   yedek boyutu: $SIZE bayt"

# kisi / bag tablolarinin icerik ozeti + tum tablolarin satir sayisi (prova karsilastirmasi)
digest() {
  # $1 = veritabani
  for t in users site_people apartment_residencies apartment_memberships site_memberships apartments notification_preferences apartment_admin_delegations site_team_duties; do
    $PSQL -d "$1" -Atc "SELECT '$t' || '|' || count(*) || '|' || md5(COALESCE(string_agg(x::text, '|' ORDER BY x::text), '')) FROM $t x"
  done
  $PSQL -d "$1" -Atc "SELECT table_name || '|' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text
    FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name <> 'demo_seed_registry' ORDER BY 1"
}

# --- 2-3) prova -------------------------------------------------------------------------------------------------------------------------------
if [ "$SKIP_REH" = 0 ]; then
  echo "[2/4] gecici veritabani: $RDB (yedekten)"
  $PSQL -qc "CREATE DATABASE \"$RDB\" OWNER \"$DB_USER\"" || exit 4
  trap '$PSQL -qc "DROP DATABASE IF EXISTS \"$RDB\" WITH (FORCE)" >/dev/null 2>&1; shred -u "$OUT/creds_restructure_rehearsal_$STAMP.json" 2>/dev/null' EXIT
  docker exec -i "$DBC" pg_restore -U postgres -d "$RDB" --no-owner --role="$DB_USER" < "$BK/db_before_restructure.dump" 2> "$BK/restore.err"
  echo "   yukleme uyarilari (ilk 3): $(head -n 3 "$BK/restore.err" | cut -c1-120 | tr '\n' '|')"
  REH_URL="$(mk_url "$RDB")"
  digest "$RDB" > "$BK/digest_before.txt"
  echo "[3/4] PROVA: yeniden yapilandirma gecici veritabaninda"
  (cd "$APP_DIR" && DATABASE_URL="$REH_URL" node "$SEED_DIR/restructure_families.mjs" --server-dir "$APP_DIR" --allow-target "$RDB" --site "$SITE" --prev-creds "$PREV" --creds-out "$OUT/creds_restructure_rehearsal_$STAMP.json" $EXTRA) | tee "$BK/rehearsal_restructure.log" | tail -n 40
  RC=${PIPESTATUS[0]}
  [ "$RC" = 0 ] || { echo "HATA: prova basarisiz (cikis $RC). Canliya GECILMEZ."; exit 5; }
  BATCH="$(grep -o 'batch=demo-restructure-[0-9]*' "$BK/rehearsal_restructure.log" | head -n 1 | cut -d= -f2)"
  [ -n "$BATCH" ] || { echo "HATA: prova batch kimligi bulunamadi"; exit 5; }
  echo "   prova batch: $BATCH"
  echo "   --- kayitli satirlar (tablo, islem) ---"
  $PSQL -d "$RDB" -Atc "SELECT table_name || ' ' || op || ' ' || count(*) FROM demo_seed_registry WHERE batch_id = '$BATCH' GROUP BY 1, 2 ORDER BY count(*) DESC LIMIT 14"
  echo "   --- cleanup provasi ---"
  (cd "$APP_DIR" && DATABASE_URL="$REH_URL" node "$SEED_DIR/cleanup.mjs" --server-dir "$APP_DIR" --allow-target "$RDB" --batch "$BATCH" --yes) | tail -n 8
  digest "$RDB" > "$BK/digest_after_cleanup.txt"
  if diff -q "$BK/digest_before.txt" "$BK/digest_after_cleanup.txt" >/dev/null; then
    echo "   cleanup SONRASI kisi/bag tablolari (icerik ozeti) ve tum tablo satir sayilari yedekle AYNI: OK"
  else
    echo "HATA: cleanup sonrasi fark var:"; diff "$BK/digest_before.txt" "$BK/digest_after_cleanup.txt" | head -n 20
    echo "Canliya GECILMEZ."; exit 6
  fi
fi

# --- 4) canli -----------------------------------------------------------------------------------------------------------------------------------
if [ "$PROD" = 1 ]; then
  echo "[4/4] CANLI: yeniden yapilandirma $DB_NAME veritabaninda (yedek: $BK/db_before_restructure.dump)"
  (cd "$APP_DIR" && DATABASE_URL="$PROD_URL" node "$SEED_DIR/restructure_families.mjs" --server-dir "$APP_DIR" --allow-target "$DB_NAME" --site "$SITE" --prev-creds "$PREV" --creds-out "$CREDS_OUT" $EXTRA) | tee "$BK/prod_restructure.log" | tail -n 45
  RC=${PIPESTATUS[0]}
  BATCH_PROD="$(grep -o 'batch=demo-restructure-[0-9]*' "$BK/prod_restructure.log" | head -n 1 | cut -d= -f2)"
  echo "   canli batch: $BATCH_PROD   cikis kodu: $RC"
  echo "   kimlik bilgileri: $CREDS_OUT (chmod 600). PDF icin: python3 $SEED_DIR/make_pdf.py --creds $CREDS_OUT --out $OUT/demo_hesaplar.pdf   (reportlab gerekir; yoksa dosyayi yerel makineye alip orada uretin)"
  echo "   KAPAT: kimlik dosyasini kopyaladiktan sonra sunucudan silin (shred -u $CREDS_OUT $PREV)."
  echo "   GERI ALMA: (cd $APP_DIR && DATABASE_URL=<canli-url> node $SEED_DIR/cleanup.mjs --server-dir $APP_DIR --batch $BATCH_PROD --yes --allow-target $DB_NAME)"
  exit "$RC"
else
  echo "[4/4] --prod verilmedi: canliya yazilmadi. Prova basarili ise: bash run_remote_restructure.sh --prev-creds $PREV --prod --skip-rehearsal"
fi
