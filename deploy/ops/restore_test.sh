#!/bin/bash
# Geri yukleme KANITI: yedegi gecici bir veritabanina (kapi_restoretest_<TS>) yukler, tablo/satir sayilarini
# canli veritabaniyla karsilastirir (canli taraf YALNIZ OKUMA: default_transaction_read_only=on, lock_timeout=5s,
# statement_timeout=60s), gecici DB'yi siler.
#
# Varsayilan olarak IKI dosya sinanir: (1) en son gunluk (duz) yedek, (2) en son SIFRELI dis kopya (offsite/*.sql.gz.enc;
# sifre cozulur). Boylece sifreleme anahtari ve sifreli kopyalar da geri yuklenebilirlik acisindan kanitlanir.
#
# Belge deposu tutarliligi (YALNIZ varsayilan calismada): geri yuklenen veritabanindaki 'ready' belge surumlerinin (aktif belgeler) storage_key'leri,
# en son sifreli belge arsivinin (config/kapi_documents_*.tgz.enc) icinde olmali; eksik varsa FAIL. Belge modulu hic kullanilmadiysa atlanir.
#
# Kullanim:  bash ~/ops/restore_test.sh [--file <yedek.sql.gz | yedek.sql.gz.enc>]
# Cikis kodu: 0 PASS, 1 FAIL, 64 kullanim hatasi, 75 kilit alinamadi.
# Canli veritabanina hicbir YAZMA yapilmaz; yalnizca kendi olusturdugu kapi_restoretest_* veritabani silinir.
# Guvenlik: yedek dosyasi yuklenmeden once taranir; \connect, DROP/CREATE/ALTER DATABASE ve beklenmeyen psql
# meta-komutlari iceriyorsa REDDEDILIR (aksi halde psql baska/canli veritabanina baglanip islem yapabilirdi).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG=restore_test
# shellcheck source=common.sh
. "$HERE/common.sh"
reexec_low_priority "$@"
acquire_lock heavy 900

STATUS_FILE="$OPS_STATE/restore_test.status"
MIN_TABLES="$(num "${MIN_TABLES:-30}" 30)"
KEY_TABLES="${KEY_TABLES:-users sites site_memberships}"
DB_PAT='^kapi_[0-9]{8}_[0-9]{4}\.sql\.gz$'
ENC_PAT='^kapi_[0-9]{8}_[0-9]{4}\.sql\.gz\.enc$'
RDB_RE='^kapi_restoretest_[0-9]{8}_[0-9]{6}$'
ERRF="$OPS_STATE/restore_test.psql.err"
START="$(now_epoch)"
RUN_TS="$(TZ=$LOCAL_TZ date +%Y%m%d_%H%M%S)"
REPORT="$OPS_LOGS/restore_test_${RUN_TS}.txt"
WORK=""
RDB=""
CREATED=0
CHECK_DOCS=0
DOC_ARCHIVE=""
DOC_LIST=""

# Yalnizca KENDI olusturdugu kapi_restoretest_<TS> veritabanini siler (ad deseni dogrulanir).
drop_temp_db() {
  local left
  if [ "$CREATED" -eq 1 ] && [[ "$RDB" =~ $RDB_RE ]]; then
    dpsql -qc "DROP DATABASE IF EXISTS \"$RDB\" WITH (FORCE)" >/dev/null 2>&1 </dev/null
    left="$(dpsql -Atc "select count(*) from pg_database where datname='$RDB'" 2>/dev/null </dev/null)"
    if [ "$left" = "0" ]; then log "gecici veritabani silindi: $RDB"; else log "UYARI: gecici veritabani silinemedi: $RDB (elle: DROP DATABASE \"$RDB\")"; fi
    CREATED=0
  fi
}
# trap, gecici dizinden ONCE kurulur (mktemp ile trap arasinda artik kalmasin)
cleanup() {
  drop_temp_db
  [ -n "$WORK" ] && rm -rf -- "$WORK" 2>/dev/null
  true
}
trap cleanup EXIT
WORK="$(mktemp -d "$OPS_HOME/tmp.XXXXXX")" || { echo "gecici dizin olusturulamadi"; exit 1; }
DOC_LIST="$WORK/docs.list"

FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || { echo "--file bir yol ister"; exit 64; }; FILES+=("$2"); shift 2 ;;
    *) echo "bilinmeyen secenek: $1"; exit 64 ;;
  esac
done

fail_all() { # fail_all <neden> [dosya]
  local reason="$1" f="${2:-?}"
  log "HATA: $reason"
  write_status "$STATUS_FILE" "result=FAIL" "epoch=$(now_epoch)" "file=$(basename "$f")" "reason=$reason" "notified=1"
  send_mail "[KAPI-OPS] SORUN: geri yukleme testi BASARISIZ" "Yedekten geri yukleme testi basarisiz oldu.
Zaman : $(stamp_local) (Europe/Istanbul)
Yedek : $(basename "$f")
Neden : $reason
Rapor : $REPORT
Bu, yedegin gercekten geri yuklenemeyebilecegi anlamina gelir: el kitabindaki 'Sorun giderme' bolumune bakin." || true
  exit 1
}

# Yedek dosyasi guvenlik taramasi (stdin: acik SQL). 0 = temiz, 3 = reddedildi (neden stdout'a yazilir)
scan_dump() {
  awk '
    incopy { if ($0 == "\\.") incopy = 0; next }
    /^COPY .* FROM stdin;$/ { incopy = 1; next }
    {
      l = tolower($0)
      if (l ~ /^[ \t]*\\/) {
        if (l ~ /^\\(restrict|unrestrict)( |$)/) next
        print "psql meta-komutu: " substr($0, 1, 30); exit 3
      }
      if (l ~ /^[ \t]*(drop|create|alter)[ \t]+database[ \t]/) { print "veritabani seviyesi komut: " substr($0, 1, 30); exit 3 }
    }'
}

{
  echo "Geri yukleme testi  : $(stamp_local) (Europe/Istanbul)"
} >"$REPORT"

# restore_one <dosya> : 0 = PASS, 1 = FAIL (FAIL_REASON dolu). Sonuc degiskenleri: R_*
restore_one() {
  local f="$1" plain="" errors first rows_line keyfail rc docs_reason has_docs nready nmissing
  FAIL_REASON=""
  R_TABLES_R=0; R_TABLES_L=0; R_ROWS_R=0; R_ROWS_L=0; R_ERR=0
  [ -f "$f" ] && [ -r "$f" ] || { FAIL_REASON="yedek dosyasi okunamiyor: $f"; return 1; }
  {
    echo
    echo "--- $(basename "$f") ($(human_bytes "$(stat -c %s "$f")"), degisim: $(TZ=$LOCAL_TZ date -d "@$(stat -c %Y "$f")" '+%Y-%m-%d %H:%M'))"
  } >>"$REPORT"
  log "[1/5] yedek butunlugu: $(basename "$f")"
  case "$f" in
    *.enc)
      [ -s "$KEY_FILE" ] || { FAIL_REASON="sifreli yedek icin anahtar yok ($KEY_FILE)"; return 1; }
      plain="$WORK/decrypted.sql.gz"
      dec_cmd -in "$f" -out "$plain" 2>/dev/null || { FAIL_REASON="sifre cozme basarisiz (yanlis anahtar veya bozuk dosya)"; return 1; }
      ;;
    *.gz) plain="$f" ;;
    *) FAIL_REASON="desteklenmeyen uzanti (beklenen .sql.gz veya .sql.gz.enc)"; return 1 ;;
  esac
  # AES-CBC kimlik dogrulamasizdir: yanlis anahtar bazen hata vermeden cop uretir. Gercek dogrulayici gzip -t ve icerik taramasidir.
  gzip -t "$plain" 2>/dev/null || { FAIL_REASON="gzip -t basarisiz (bozuk dosya veya yanlis anahtar)"; return 1; }
  if [ -r "$f.sha256" ]; then
    (cd "$(dirname "$f")" && sha256sum -c --status "$(basename "$f").sha256") || { FAIL_REASON="sha256 uyusmuyor (yedek degismis/bozulmus)"; return 1; }
    log "   sha256 dogrulandi"
  fi
  gzip -dc "$plain" | scan_dump >"$WORK/scan.out"
  rc=${PIPESTATUS[1]}
  if [ "$rc" -ne 0 ]; then FAIL_REASON="yedek dosyasi REDDEDILDI (guvenlik taramasi): $(head -n1 "$WORK/scan.out" | cut -c1-80)"; return 1; fi

  RDB="kapi_restoretest_$(TZ=$LOCAL_TZ date +%Y%m%d_%H%M%S)"
  [[ "$RDB" =~ $RDB_RE ]] || { FAIL_REASON="gecici veritabani adi gecersiz"; return 1; }
  log "[2/5] gecici veritabani: $RDB"
  dpsql -qc "CREATE DATABASE \"$RDB\"" >/dev/null 2>&1 </dev/null || { FAIL_REASON="gecici veritabani olusturulamadi"; RDB=""; return 1; }
  CREATED=1

  log "[3/5] yedek yukleniyor"
  gzip -dc "$plain" | dpsql -q -d "$RDB" -v ON_ERROR_STOP=0 >/dev/null 2>"$ERRF"
  errors="$(grep -c 'ERROR:' "$ERRF" 2>/dev/null || true)"; errors="$(num "$errors" 0)"
  R_ERR="$errors"
  log "   yukleme hatasi: $errors"
  if [ "$errors" -gt 0 ]; then
    first="$(grep -m3 'ERROR:' "$ERRF" | cut -c1-140 | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/<e-posta>/g' | tr '\n' '|')"
    echo "Yukleme hatalari (ilk 3): $first" >>"$REPORT"
  fi

  log "[4/5] tablo/satir sayilari (yedek ve canli; canli taraf salt okunur)"
  dpsql -d "$RDB" -q -A -t -f - <"$WORK/count.sql" >"$WORK/rest.txt" 2>"$WORK/rest.err" || { FAIL_REASON="yedek veritabaninda sayim sorgusu basarisiz"; return 1; }
  dpsql_ro -d "$DB_NAME" -q -A -t -f - <"$WORK/count.sql" >"$WORK/live.txt" 2>"$WORK/live.err" || { FAIL_REASON="canli veritabaninda (salt okunur) sayim sorgusu basarisiz: $(head -n1 "$WORK/live.err" | cut -c1-100)"; return 1; }

  log "[5/5] karsilastirma"
  awk -F'|' -v mintables="$MIN_TABLES" -v keys="$KEY_TABLES" '
    NR == FNR { live[$1] = $2; next }
    { rest[$1] = $2 }
    END {
      n = split(keys, K, " ")
      printf "%-34s %12s %12s  %s\n", "TABLO", "YEDEK", "CANLI", "DURUM"
      for (t in live) all[t] = 1
      for (t in rest) all[t] = 1
      cnt = 0
      for (t in all) names[++cnt] = t
      for (i = 1; i <= cnt; i++) for (j = i + 1; j <= cnt; j++) if (names[j] < names[i]) { x = names[i]; names[i] = names[j]; names[j] = x }
      for (i = 1; i <= cnt; i++) {
        t = names[i]
        inl = (t in live); inr = (t in rest)
        if (inl && inr) {
          if (live[t] == rest[t]) st = "ESIT"
          else if (live[t] > rest[t]) st = "canli +" (live[t] - rest[t]) " (yedekten sonra eklenen)"
          else st = "canli -" (rest[t] - live[t]) " (yedekten sonra silinen/suresi dolan)"
        } else if (inl) st = "yalniz canlida (yedekten sonra olusan tablo/yapi)"
        else st = "yalniz yedekte (yedekten sonra kaldirilmis)"
        printf "%-34s %12s %12s  %s\n", t, (inr ? rest[t] : "-"), (inl ? live[t] : "-"), st
        if (substr(t, 1, 1) != "~") {
          if (inr) { tr++; rr += rest[t] }
          if (inl) { tl++; rl += live[t] }
          if (inl && inr && live[t] != rest[t]) diff++
        } else if (inl && inr && live[t] != rest[t]) sdiff = sdiff " " t
      }
      keyfail = ""
      for (i = 1; i <= n; i++) { k = K[i]; if ((k in live) && live[k] > 0 && ((!(k in rest)) || rest[k] == 0)) keyfail = keyfail " " k }
      printf "RESULT tables_restored=%d tables_live=%d rows_restored=%d rows_live=%d tables_with_row_diff=%d struct_diff=[%s] keyfail=[%s]\n", tr, tl, rr, rl, diff, sdiff, keyfail
    }' "$WORK/live.txt" "$WORK/rest.txt" >"$WORK/compare.txt"

  grep -v '^RESULT ' "$WORK/compare.txt" | tee -a "$REPORT"
  rows_line="$(grep '^RESULT ' "$WORK/compare.txt")"
  R_TABLES_R="$(num "$(sed -n 's/.*tables_restored=\([0-9]*\).*/\1/p' <<<"$rows_line")" 0)"
  R_TABLES_L="$(num "$(sed -n 's/.*tables_live=\([0-9]*\).*/\1/p' <<<"$rows_line")" 0)"
  R_ROWS_R="$(num "$(sed -n 's/.*rows_restored=\([0-9]*\).*/\1/p' <<<"$rows_line")" 0)"
  R_ROWS_L="$(num "$(sed -n 's/.*rows_live=\([0-9]*\).*/\1/p' <<<"$rows_line")" 0)"
  keyfail="$(sed -n 's/.*keyfail=\[\(.*\)\]$/\1/p' <<<"$rows_line" | xargs)"
  {
    echo "Tablo (yedek/canli)        : $R_TABLES_R / $R_TABLES_L"
    echo "Toplam satir (yedek/canli) : $R_ROWS_R / $R_ROWS_L   (yedek-sonrasi canli degisikligi normaldir)"
    echo "Yukleme hatasi             : $errors"
  } | tee -a "$REPORT"

  # belge deposu tutarliligi (veritabani hala yukluyken): DB'deki hazir surumler arsivde olmali
  docs_reason=""
  if [ "$CHECK_DOCS" -eq 1 ]; then
    has_docs="$(dpsql -d "$RDB" -Atc "select to_regclass('public.document_versions') is not null" 2>/dev/null </dev/null)"
    if [ "$has_docs" = "t" ]; then
      dpsql -d "$RDB" -At -c "select 'sites/' || v.storage_key from document_versions v join documents d on d.id = v.document_id where v.status = 'ready' and d.status = 'active' order by 1" 2>/dev/null </dev/null | LC_ALL=C sort >"$WORK/db.keys"
      nready="$(num "$(wc -l <"$WORK/db.keys")" 0)"
      if [ "$nready" -eq 0 ]; then
        echo "Belge tutarliligi          : DB'de hazir belge surumu yok (atlandi)" | tee -a "$REPORT"
      elif [ -z "$DOC_ARCHIVE" ]; then
        docs_reason="veritabaninda $nready hazir belge surumu var ama sifreli belge arsivi (config/kapi_documents_*) yok"
      else
        nmissing="$(num "$(LC_ALL=C comm -23 "$WORK/db.keys" "$DOC_LIST" | wc -l)" 0)"
        echo "Belge tutarliligi          : DB hazir surum $nready, arsivde eksik $nmissing" | tee -a "$REPORT"
        [ "$nmissing" -eq 0 ] || docs_reason="belge arsivinde eksik dosya: $nmissing / $nready (DB'de var, arsivde yok; yedek anindan sonra kalici silinmis olabilir, degilse belge yedegi eksik)"
      fi
    else
      echo "Belge tutarliligi          : document_versions tablosu yok (atlandi)" | tee -a "$REPORT"
    fi
  fi

  drop_temp_db   # gecici veritabanini HEMEN sil (sonraki dosya icin)
  [ "$errors" -eq 0 ] || { FAIL_REASON="yukleme sirasinda $errors hata (rapor: $REPORT)"; return 1; }
  [ "$R_TABLES_R" -ge "$MIN_TABLES" ] || { FAIL_REASON="yuklenen tablo sayisi az ($R_TABLES_R < $MIN_TABLES)"; return 1; }
  [ "$R_ROWS_R" -gt 0 ] || { FAIL_REASON="yuklenen veritabaninda hic satir yok"; return 1; }
  [ -z "$keyfail" ] || { FAIL_REASON="kritik tablo(lar) yedekte bos ama canlida dolu: $keyfail"; return 1; }
  [ -z "$docs_reason" ] || { FAIL_REASON="$docs_reason"; return 1; }
  return 0
}

# ---- sayim betigi ------------------------------------------------------------------------
cat >"$WORK/count.sql" <<'SQL'
\set QUIET on
select string_agg(format('select %L as t, count(*)::bigint as n from public.%I', c.relname, c.relname), ' union all ' order by c.relname) as q
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','p') \gset
\pset format unaligned
\pset tuples_only on
:q
union all select '~indexes', count(*) from pg_indexes where schemaname = 'public'
union all select '~constraints', count(*) from pg_constraint c join pg_namespace n on n.oid = c.connamespace where n.nspname = 'public'
union all select '~triggers', count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and not t.tgisinternal
union all select '~sequences', count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'S'
order by 1;
SQL

db_running || fail_all "veritabani kapsayicisi calismiyor veya yanit vermiyor" "${FILES[0]:-}"

# test edilecek dosyalar
if [ "${#FILES[@]}" -eq 0 ]; then
  latest="$(ls -1 "$BACKUP_ROOT/daily" 2>/dev/null | grep -E "$DB_PAT" | sort | tail -n1)"
  [ -n "$latest" ] || fail_all "daily/ icinde duz yedek yok"
  FILES+=("$BACKUP_ROOT/daily/$latest")
  CHECK_DOCS=1
  latest_enc="$(ls -1 "$BACKUP_ROOT/offsite" 2>/dev/null | grep -E "$ENC_PAT" | sort | tail -n1)"
  if [ -n "$latest_enc" ] && [ -s "$KEY_FILE" ]; then
    FILES+=("$BACKUP_ROOT/offsite/$latest_enc")
  else
    log "bilgi: sifreli dis kopya dosyasi veya anahtar yok; yalniz duz yedek sinanacak"
  fi
fi

# belge arsivi listesi (yalniz varsayilan calismada)
if [ "$CHECK_DOCS" -eq 1 ]; then
  doc_name="$(ls -1 "$BACKUP_ROOT/config" 2>/dev/null | grep -E '^kapi_documents_[0-9]{8}_[0-9]{4}\.tgz\.enc$' | sort | tail -n1)"
  if [ -n "$doc_name" ]; then
    DOC_ARCHIVE="$BACKUP_ROOT/config/$doc_name"
    [ -s "$KEY_FILE" ] || fail_all "belge arsivi var ama sifreleme anahtari yok" "$DOC_ARCHIVE"
    dec_cmd -in "$DOC_ARCHIVE" 2>/dev/null | tar -tzf - 2>/dev/null | grep -v '/$' | sed 's#^\./##' | LC_ALL=C sort >"$DOC_LIST"
    [ -s "$DOC_LIST" ] || fail_all "belge arsivi cozulemedi veya bos ($doc_name)" "$DOC_ARCHIVE"
    log "belge arsivi: $doc_name ($(wc -l <"$DOC_LIST") dosya)"
  else
    log "bilgi: belge arsivi yok (belge modulu kullanilmamis olabilir)"
  fi
fi

tested=""
for f in "${FILES[@]}"; do
  if ! restore_one "$f"; then
    fail_all "$FAIL_REASON" "$f"
  fi
  log "   PASS: $(basename "$f") (tablo $R_TABLES_R, satir $R_ROWS_R yedek / $R_ROWS_L canli)"
  tested="${tested:+$tested,}$(basename "$f")"
  last_tr="$R_TABLES_R"; last_tl="$R_TABLES_L"; last_rr="$R_ROWS_R"; last_rl="$R_ROWS_L"
done

secs="$(($(now_epoch) - START))"
write_status "$STATUS_FILE" "result=PASS" "epoch=$(now_epoch)" "file=$tested" "files_tested=${#FILES[@]}" "tables_restored=$last_tr" "tables_live=$last_tl" "rows_restored=$last_rr" "rows_live=$last_rl" "errors=0" "secs=$secs"
{
  echo
  echo "SONUC: PASS (${#FILES[@]} dosya, ${secs}s)"
} | tee -a "$REPORT"
log "=== GERI YUKLEME TESTI: PASS (${#FILES[@]} dosya sinandi: $tested; ${secs}s) ==="
echo "RAPOR: $REPORT"
# eski raporlari buda (son 12)
ls -1t "$OPS_LOGS"/restore_test_*.txt 2>/dev/null | tail -n +13 | xargs -r rm -f --
trim_log
exit 0
