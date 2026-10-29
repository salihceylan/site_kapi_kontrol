#!/bin/bash
# Zamanlanmis veritabani yedegi + sifreli yapilandirma/firmware yedegi + dis kopya hazirligi.
#
#   daily/    kapi_<YYYYmmdd_HHMM>.sql.gz   pg_dump (docker exec) -> gzip. YALNIZ EN SON gunluk yedek duz kalir;
#             onceki gunlukler sifreli (.sql.gz.enc) hale getirilir                              (7 adet tutulur)
#   weekly/   ISO haftasinin ilk yedegi, SIFRELI (.sql.gz.enc)                                   (4 adet)
#   monthly/  ayin ilk yedegi, SIFRELI (.sql.gz.enc)                                             (6 adet)
#   config/   kapi_config_<TS>.tgz.enc     .env + nginx sitesi + MQTT yapilandirmasi + data/public + roller + silinen hesap listesi
#             kapi_firmware_<TS>.tgz.enc   server/firmware (OTA ikilileri; YALNIZ icerik degisince yeni arsiv, son 5 tutulur)
#             kapi_documents_<TS>.tgz.enc  belge deposu (DOCUMENTS_DIR/sites; _tmp HARIC; DB dokumunden SONRA; YALNIZ icerik degisince;
#                                          son 5 tutulur, en yenisi disinda 210 gunden eskiler silinir)
#             kapi_work_attachments_<TS>.tgz.enc  is takibi fotograf ekleri (DOCUMENTS_DIR/work_attachments) + geri bildirim ekleri
#                                          (DOCUMENTS_DIR/feedback_attachments) AYNI gorsel-ek arsivinde; belgelerden AYRI arsiv: kendi boyut
#                                          siniri, ozeti ve tutma adedi; DB dokumunden SONRA; YALNIZ icerik degisince; son 5 tutulur, en yenisi
#                                          disinda 210 gunden eskiler silinir)
#   offsite/  kapi_<TS>.sql.gz.enc + config/firmware/belge/fotograf arsivleri (YALNIZ sifreli; offsite_push.sh gonderir)    (7 adet)
#
# Disk tasarrufu: ayni sifreli icerik (offsite/ <-> daily/ <-> weekly/ <-> monthly/ <-> config/) diskte BIR KEZ tutulur; diger adlar sert bagdir
# (common.sh link_or_copy; bag kurulamazsa kopya). Dosyalar yerinde degistirilmedigi icin bir adin silinmesi (tutma kurali) digerlerini etkilemez.
# Tutma adetleri ortam/kapi-ops.env ile degisir: KEEP_DAILY KEEP_WEEKLY KEEP_MONTHLY KEEP_OFFSITE KEEP_FIRMWARE KEEP_DOCUMENTS
# KEEP_WORK_ATTACHMENTS (en az 1).
# En yeni kopya HER ZAMAN korunur (her tutma kurali en az 1 yuva birakir; yalniz yuva sayisini asan ESKI kopyalar silinir).
#
# Sifreleme: openssl enc -aes-256-cbc -pbkdf2 -iter 200000; anahtar ~/.config/kapi-backup.key (600), ASLA yazdirilmaz.
# Dosya adlari Europe/Istanbul saatiyle. Cron: sunucu UTC; 03:30 Istanbul = 00:30 UTC (Turkiye yaz saati uygulamaz).
# Cikis kodu: 0 basarili, 1 yedek basarisiz, 2 yedek tamam ama sifreli kopya/yapilandirma/firmware/belge/fotograf arsivi basarisiz,
# 75 kilit alinamadi.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG=backup
# shellcheck source=common.sh
. "$HERE/common.sh"
reexec_low_priority "$@"
acquire_lock heavy 900

WARNINGS=""
REASON=""
warn() { WARNINGS="${WARNINGS:+$WARNINGS; }$1"; log "UYARI: $1"; }

# Sayisal ayar dogrulamasi: int_or_default ADI VARSAYILAN EN_AZ ; gecersizse varsayilan + uyari
int_or_default() {
  local name="$1" def="$2" min="$3" val
  val="${!name:-}"
  if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge "$min" ]; then return 0; fi
  [ -n "$val" ] && warn "$name='$val' gecersiz (sayi >= $min olmali); varsayilan $def kullanildi"
  printf -v "$name" '%s' "$def"
}
int_or_default KEEP_DAILY 7 1
int_or_default KEEP_WEEKLY 4 1
int_or_default KEEP_MONTHLY 6 1
int_or_default KEEP_OFFSITE 7 1
int_or_default KEEP_FIRMWARE 5 1
int_or_default KEEP_DOCUMENTS 5 1
int_or_default DOCUMENTS_MAX_AGE_DAYS 210 1
int_or_default DOCUMENTS_BACKUP_MAX_MB 3000 1
int_or_default KEEP_WORK_ATTACHMENTS 5 1
int_or_default WORK_ATTACHMENTS_MAX_AGE_DAYS 210 1
int_or_default WORK_ATTACHMENTS_BACKUP_MAX_MB 3000 1
int_or_default MIN_DUMP_BYTES 8000 1000
int_or_default MIN_TABLES 30 1
REQUIRED_TABLES="${REQUIRED_TABLES:-users sites site_memberships audit_log}"
STATUS_FILE="$OPS_STATE/backup.status"

DAILY="$BACKUP_ROOT/daily"
WEEKLY="$BACKUP_ROOT/weekly"
MONTHLY="$BACKUP_ROOT/monthly"
CONFIGD="$BACKUP_ROOT/config"
OFFSITE="$BACKUP_ROOT/offsite"

TS="$(ts_local)"
# Saat ileri alinmis (gelecek tarihli) dosyalar saklama yuvalarini isgal etmesin
FUTURE_LIMIT="$(TZ=$LOCAL_TZ date -d '+1 day' +%Y%m%d_%H%M)"
OUT="$DAILY/kapi_${TS}.sql.gz"
TMP_DUMP="$DAILY/.kapi_${TS}.sql.gz.part"
CFG_OUT="$CONFIGD/kapi_config_${TS}.tgz.enc"
CFG_TMP="$CONFIGD/.kapi_config_${TS}.tgz.enc.part"
FW_OUT="$CONFIGD/kapi_firmware_${TS}.tgz.enc"
FW_TMP="$CONFIGD/.kapi_firmware_${TS}.tgz.enc.part"
DOC_OUT="$CONFIGD/kapi_documents_${TS}.tgz.enc"
DOC_TMP="$CONFIGD/.kapi_documents_${TS}.tgz.enc.part"
WA_OUT="$CONFIGD/kapi_work_attachments_${TS}.tgz.enc"
WA_TMP="$CONFIGD/.kapi_work_attachments_${TS}.tgz.enc.part"
OFF_DB="$OFFSITE/kapi_${TS}.sql.gz.enc"
STAGE=""
ERRF="$OPS_STATE/backup.pgdump.err"
START_EPOCH="$(now_epoch)"

cleanup() {
  rm -f -- "$TMP_DUMP" "$CFG_TMP" "$FW_TMP" "$DOC_TMP" "$WA_TMP" "$OFF_DB.part" 2>/dev/null
  [ -n "$STAGE" ] && rm -rf -- "$STAGE" 2>/dev/null
  true
}
trap cleanup EXIT

fail() { # fail <kod> <neden>
  local code="$1"
  REASON="$2"
  log "HATA: $REASON"
  write_status "$STATUS_FILE" "result=FAIL" "epoch=$(now_epoch)" "ts=$TS" "reason=$REASON" "notified=1"
  send_mail "[KAPI-OPS] SORUN: zamanlanmis veritabani yedegi basarisiz" "Yedek calismasi basarisiz oldu.
Zaman : $(stamp_local) (Europe/Istanbul)
Neden : $REASON
Gunluk: ~/ops/logs/backup.log
Onceki gecerli yedekler silinmedi. Elle: bash ~/ops/backup_db.sh" || true
  exit "$code"
}

# ---- saklama / yardimcilar ----------------------------------------------------------------
# keys_of <dizin> <onek>: dizindeki dosyalarin zaman damgasi anahtarlari (yeniden eskiye), GELECEK tarihliler haric
keys_of() {
  ls -1 "$1" 2>/dev/null \
    | sed -nE "s/^${2}_([0-9]{8}_[0-9]{4})\.(sql\.gz|tgz)(\.enc)?(\.sha256)?$/\1/p" \
    | sort -u -r | awk -v lim="$FUTURE_LIMIT" '$0 <= lim'
}

# prune_keep <dizin> <onek> <tutulacak-adet> [dis-kopya-gonderilmis-olmali=0]
prune_keep() {
  local dir="$1" prefix="$2" keep="$3" reqp="${4:-0}" n i key f unpushed
  local -a keys
  # EN YENI KOPYA HER ZAMAN KORUNUR: gecersiz/0 adet bile verilse en az 1 yuva kalir; anahtarlar yeniden eskiye siralidir ve dongu
  # keep'ten (>= 1) baslar, yani keys[0] (en yeni) asla silinmez. Gelecek tarihli dosyalar keys_of'ta zaten yoktur (silinmez).
  [[ "$keep" =~ ^[0-9]+$ ]] && [ "$keep" -ge 1 ] || keep=1
  mapfile -t keys < <(keys_of "$dir" "$prefix")
  n=${#keys[@]}
  [ "$n" -le "$keep" ] && return 0
  for ((i = keep; i < n; i++)); do
    key="${keys[$i]}"
    if [ "$reqp" = "1" ] && [ -r "$OFFSITE_CONF" ]; then
      unpushed=0
      for f in "$dir/${prefix}_${key}".*; do
        [ -e "$f" ] || continue
        case "$f" in *.enc) grep -qxF "$(basename "$f")" "$OPS_STATE/offsite.pushed" 2>/dev/null || unpushed=1 ;; esac
      done
      if [ "$unpushed" = "1" ]; then
        log "tutma: ${prefix}_${key} dis kopyaya henuz gonderilmedi, silinmedi"
        continue
      fi
    fi
    rm -f -- "$dir/${prefix}_${key}.sql.gz" "$dir/${prefix}_${key}.sql.gz.sha256" \
      "$dir/${prefix}_${key}.sql.gz.enc" "$dir/${prefix}_${key}.sql.gz.enc.sha256" \
      "$dir/${prefix}_${key}.tgz.enc" "$dir/${prefix}_${key}.tgz.enc.sha256"
    log "tutma kurali: silindi $(basename "$dir")/${prefix}_${key}.*"
  done
}

# Haftalik/aylik kopya: o doneme ait dosya yoksa ilk yedegi kopyala (kacirilan gunlere dayanikli) + sha256
promote() { # promote <kaynak-dosya>
  local src="$1" base prefix d dir period k existing kind
  base="$(basename "$src")"
  prefix="$(sed -E 's/^(kapi(_config)?)_[0-9]{8}_[0-9]{4}\..*/\1/' <<<"$base")"
  d="$(grep -oE '[0-9]{8}_[0-9]{4}' <<<"$base" | head -n1 | cut -c1-8)"
  [ -n "$d" ] || return 0
  for kind in weekly monthly; do
    if [ "$kind" = "weekly" ]; then dir="$WEEKLY"; period="$(date -d "$d" +%G-%V)"; else dir="$MONTHLY"; period="${d:0:6}"; fi
    existing=0
    while read -r k; do
      [ -n "$k" ] || continue
      if [ "$kind" = "weekly" ]; then
        [ "$(date -d "${k:0:8}" +%G-%V)" = "$period" ] && existing=1
      else
        [ "${k:0:6}" = "$period" ] && existing=1
      fi
    done < <(keys_of "$dir" "$prefix")
    if [ "$existing" -eq 0 ]; then
      link_or_copy "$src" "$dir/$base" && (cd "$dir" && sha256sum "$base" >"$base.sha256") && log "$kind kopya: $base ($period; sert bag/tek kopya)"
    fi
  done
}

# Duz (sifresiz) yedegi sifreli hale getir: dogrula (cozulen icerigin sha256'si ayni) sonra duz dosyayi kaldir.
SCHEME_FILE="$OPS_STATE/enc_scheme_since"
[ -s "$SCHEME_FILE" ] || now_epoch >"$SCHEME_FILE"
SCHEME_SINCE="$(num "$(cat "$SCHEME_FILE" 2>/dev/null)" 0)"
demote_plain() { # demote_plain <duz-dosya>
  local f="$1" enc="$1.enc" want got off
  [ -f "$f" ] || return 0
  # sifreli duzene gecis ANINDAN ONCE olusmus dosyalara dokunulmaz (mevcut yedekler silinmez)
  [ "$(stat -c %Y "$f")" -ge "$SCHEME_SINCE" ] || return 0
  want="$(sha256sum "$f" | cut -d' ' -f1)"
  if [ ! -e "$enc" ]; then
    # Tekillestirme: dis kopya hazirlik dizininde ayni dokumun sifreli kopyasi varsa ve cozulen icerigi duz yedekle AYNIYSA
    # yeniden sifreleme + ikinci kopya yerine ona sert bag kurulur (ayni icerik diskte bir kez). Aksi halde eski yol: sifrele + dogrula.
    off="$OFFSITE/$(basename "$enc")"
    if [ "$(dirname "$enc")" != "$OFFSITE" ] && [ -f "$off" ]        && [ "$(dec_cmd -in "$off" 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$want" ]        && link_or_copy "$off" "$enc"; then
      log "sifreli kopya dis kopya hazirlik dizinindekiyle birlestirildi (sert bag): $(basename "$enc")"
    else
      if ! enc_file "$f" "$enc.part"; then rm -f -- "$enc.part"; warn "sifreleme basarisiz, duz kopya korundu: $(basename "$f")"; return 1; fi
      got="$(dec_cmd -in "$enc.part" 2>/dev/null | sha256sum | cut -d' ' -f1)"
      if [ "$got" != "$want" ]; then rm -f -- "$enc.part"; warn "sifreli kopya dogrulanamadi, duz kopya korundu: $(basename "$f")"; return 1; fi
      mv -- "$enc.part" "$enc"
      chmod 600 "$enc"
    fi
  fi
  (cd "$(dirname "$enc")" && sha256sum "$(basename "$enc")" >"$(basename "$enc").sha256")
  rm -f -- "$f" "$f.sha256"
  log "sifrelendi (duz kopya kaldirildi): $(basename "$f")"
}

key_fingerprint_ok() {
  local stored cur
  cur="$(key_sha)"
  [ -n "$cur" ] || { REASON="sifreleme anahtari yok ($KEY_FILE); install_ops.sh calistirin"; return 1; }
  stored="$(cat "$OPS_STATE/key.sha256" 2>/dev/null)"
  if [ -z "$stored" ]; then
    printf '%s\n' "$cur" >"$OPS_STATE/key.sha256"
    printf '%s %s ilk-kayit\n' "$(now_epoch)" "${cur:0:12}" >>"$OPS_STATE/key.history"
    log "anahtar parmak izi ilk kez kaydedildi (${cur:0:12})"
  elif [ "$stored" != "$cur" ]; then
    REASON="sifreleme anahtari DEGISMIS (parmak izi uyusmuyor): yeni dosyalar eski anahtarla acilmaz. Bilerek degistirdiyseniz: bash ~/ops/install_ops.sh --accept-new-key"
    return 1
  fi
  return 0
}

log "=== yedek basliyor: $TS ==="

# ---- on kosullar -------------------------------------------------------------------------
mkdir -p "$DAILY" "$WEEKLY" "$MONTHLY" "$CONFIGD" "$OFFSITE" || fail 1 "yedek dizinleri olusturulamadi"
chmod 700 "$BACKUP_ROOT" "$DAILY" "$WEEKLY" "$MONTHLY" "$CONFIGD" "$OFFSITE" 2>/dev/null
db_running || fail 1 "veritabani kapsayicisi calismiyor veya yanit vermiyor ($DB_CONTAINER)"

# yarim kalmis (24 saatten eski) artiklari suprur
find "$DAILY" "$WEEKLY" "$MONTHLY" "$CONFIGD" "$OFFSITE" -maxdepth 1 -type f \( -name '.kapi_*.part' -o -name 'kapi_*.part' \) -mmin +1440 -delete 2>/dev/null
find "$OPS_HOME" -maxdepth 1 -type d -name 'tmp.*' -mmin +1440 -exec rm -rf -- {} + 2>/dev/null
find "$OPS_HOME" -maxdepth 1 -type f -name 'sftp.*' -mmin +1440 -delete 2>/dev/null

# disk esigi: en az 500 MB ve (son dump + son yapilandirma) x saklama adedi x 3
prev_plain=""; prev_cfg=""
prev_key="$(keys_of "$DAILY" kapi | head -n1)"
if [ -n "$prev_key" ]; then
  for f in "$DAILY/kapi_${prev_key}.sql.gz" "$DAILY/kapi_${prev_key}.sql.gz.enc"; do
    [ -f "$f" ] && { prev_plain="$(basename "$f")"; break; }
  done
fi
prev_cfg_key="$(keys_of "$CONFIGD" kapi_config | head -n1)"
[ -n "$prev_cfg_key" ] && prev_cfg="kapi_config_${prev_cfg_key}.tgz.enc"
last_dump=0; last_cfg=0
[ -n "$prev_plain" ] && last_dump="$(num "$(stat -c %s "$DAILY/$prev_plain" 2>/dev/null)" 0)"
[ -n "$prev_cfg" ] && last_cfg="$(num "$(stat -c %s "$CONFIGD/$prev_cfg" 2>/dev/null)" 0)"
need_mb=$(((3 * (last_dump + last_cfg) * (KEEP_DAILY + KEEP_WEEKLY + KEEP_MONTHLY + KEEP_OFFSITE)) / 1048576 + 1))
[ "$need_mb" -lt 500 ] && need_mb=500
avail_mb="$(df -P -BM "$BACKUP_ROOT" | awk 'NR==2{gsub(/M/,"",$4); print $4}')"
[ "${avail_mb:-0}" -ge "$need_mb" ] || fail 1 "yetersiz disk alani (${avail_mb:-?} MB bos, gereken >= $need_mb MB)"
if [ -e "$OUT" ]; then
  log "ATLANDI: bu dakika icin yedek zaten var ($OUT)"
  exit 0
fi

# ---- 1. pg_dump -> gzip ------------------------------------------------------------------
log "[1/9] pg_dump ($DB_NAME) -> gzip"
nolock timeout --foreground 900 docker exec "$DB_CONTAINER" pg_dump -U postgres -d "$DB_NAME" --lock-wait-timeout=60s 2>"$ERRF" | gzip -6 >"$TMP_DUMP"
rc=("${PIPESTATUS[@]}")
if [ "${rc[0]}" -ne 0 ] || [ "${rc[1]}" -ne 0 ]; then
  fail 1 "pg_dump/gzip hata kodu (pg_dump=${rc[0]} gzip=${rc[1]}); ilk hata satiri: $(head -n1 "$ERRF" | cut -c1-120)"
fi
chmod 600 "$TMP_DUMP"

# ---- 2. butunluk dogrulamasi -------------------------------------------------------------
log "[2/9] dogrulama (gzip -t, boyut esigi, bitis isareti, beklenen tablolar, kullanici sayisi)"
gzip -t "$TMP_DUMP" 2>/dev/null || fail 1 "gzip -t basarisiz (bozuk arsiv)"
size="$(stat -c %s "$TMP_DUMP")"
[ "$size" -ge "$MIN_DUMP_BYTES" ] || fail 1 "yedek cok kucuk ($size bayt < $MIN_DUMP_BYTES)"
info="$(gzip -dc "$TMP_DUMP" | awk '
  /^CREATE TABLE public\./ { t=$3; sub(/^public\./,"",t); tables[t]=1; n++ }
  /^COPY public\./         { c=$2; sub(/^public\./,"",c); copy[c]=1 }
  /^COPY public\.users /   { inu=1; next }
  inu && $0 == "\\."       { inu=0 }
  inu                      { u++ }
  /^-- PostgreSQL database dump complete/ { done=1 }
  END { printf "N=%d\nDONE=%d\nU=%d\n", n, done+0, u+0; for (t in tables) printf "T:%s\n", t; for (c in copy) printf "C:%s\n", c }')"
n_tables="$(printf '%s\n' "$info" | sed -n 's/^N=//p')"
done_mark="$(printf '%s\n' "$info" | sed -n 's/^DONE=//p')"
n_users="$(num "$(printf '%s\n' "$info" | sed -n 's/^U=//p')" 0)"
[ "${done_mark:-0}" = "1" ] || fail 1 "dokumun sonunda 'dump complete' isareti yok (kesik yedek)"
[ "${n_tables:-0}" -ge "$MIN_TABLES" ] || fail 1 "tablo sayisi beklenenden az (${n_tables:-0} < $MIN_TABLES)"
for t in $REQUIRED_TABLES; do
  printf '%s\n' "$info" | grep -qx "T:$t" || fail 1 "beklenen tablo yedekte yok: $t"
done
printf '%s\n' "$info" | grep -qx "C:users" || fail 1 "users tablosunun veri bolumu (COPY) yok"
if [ "$n_users" -eq 0 ] && [ "${ALLOW_EMPTY_USERS:-0}" != "1" ]; then
  fail 1 "users tablosunda 0 satir: bos/hatali veritabani yedegi olabilir (bilerek ise ALLOW_EMPTY_USERS=1)"
fi
prev_users="$(num "$(status_get "$STATUS_FILE" users 2>/dev/null)" 0)"
if [ "$prev_users" -gt 0 ] && [ "$((n_users * 2))" -lt "$prev_users" ]; then
  warn "kullanici sayisi onceki yedegin yarisindan az ($n_users < $prev_users/2)"
fi
if [ -n "$prev_plain" ]; then
  prev_size="$last_dump"
  if [ "$prev_size" -gt 0 ] && [ "$((size * 2))" -lt "$prev_size" ]; then
    warn "yedek boyutu onceki yedegin yarisindan kucuk ($size < $prev_size/2)"
  fi
fi
mv -- "$TMP_DUMP" "$OUT"
(cd "$DAILY" && sha256sum "kapi_${TS}.sql.gz" >"kapi_${TS}.sql.gz.sha256")
sha="$(cut -d' ' -f1 "$DAILY/kapi_${TS}.sql.gz.sha256")"
log "   tamam: kapi_${TS}.sql.gz $(human_bytes "$size") tablo=$n_tables kullanici=$n_users sha256=${sha:0:16}..."

# ---- 3. sifreli kopya (dis kopya + haftalik/aylik + eski gunluklerin yerine) -------------
ENC_RESULT="OK"
log "[3/9] sifreli kopya (anahtar parmak izi + sifre cozme dogrulamasi)"
if key_fingerprint_ok; then
  if enc_file "$OUT" "$OFF_DB.part" && [ "$(dec_cmd -in "$OFF_DB.part" 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$sha" ]; then
    mv -- "$OFF_DB.part" "$OFF_DB"
    chmod 600 "$OFF_DB"
    log "   tamam: offsite/kapi_${TS}.sql.gz.enc (sifre cozulen icerigin sha256'si duz yedekle ayni)"
  else
    rm -f -- "$OFF_DB.part"
    ENC_RESULT="FAIL"
    REASON="${REASON:-sifreli veritabani kopyasi uretilemedi/dogrulanamadi}"
  fi
else
  ENC_RESULT="FAIL"
fi
[ "$ENC_RESULT" = "FAIL" ] && log "HATA: $REASON"

# ---- 4. haftalik / aylik kopyalar (sifreli) ------------------------------------------------
log "[4/9] haftalik/aylik kopyalar (sifreli)"
[ "$ENC_RESULT" = "OK" ] && promote "$OFF_DB"

# ---- 5. yapilandirma yedegi (sifreli) ----------------------------------------------------
CFG_RESULT="OK"
config_backup() {
  [ -r "$APP_ENV_FILE" ] || { REASON=".env okunamiyor"; return 1; }
  STAGE="$(mktemp -d "$OPS_HOME/tmp.XXXXXX")" || { REASON="gecici dizin olusturulamadi"; return 1; }
  chmod 700 "$STAGE"
  {
    echo "kapi yapilandirma yedegi"
    echo "zaman_istanbul=$(stamp_local)"
    echo "sunucu=$(hostname)"
    echo "postgres=$(dpsql -d "$DB_NAME" -Atc 'show server_version' 2>/dev/null </dev/null)"
    echo "node=$(node -v 2>/dev/null)"
    echo "db_yedegi=kapi_${TS}.sql.gz"
    echo "icerik=server/.env, nginx sitesi, MQTT broker yapilandirmasi (ozel anahtarlar HARIC), kapi-mqtt-sync, server/data, server/public, server/ecosystem.config.cjs, globals.sql (roller), deleted_accounts.csv, crontab.txt"
    echo "firmware=ayri arsiv: kapi_firmware_*.tgz.enc"
    echo "belgeler=ayri arsiv: kapi_documents_*.tgz.enc (DOCUMENTS_DIR/sites; geri yukleme sonrasi: node scripts/documents_fsck.mjs)"
    echo "fotograflar=ayri arsiv: kapi_work_attachments_*.tgz.enc (DOCUMENTS_DIR/work_attachments; is takibi fotograf ekleri)"
    echo "geri_yukleme=docs/OPERASYON_YEDEK_IZLEME.md"
  } >"$STAGE/INFO.txt"
  nolock timeout --foreground 120 docker exec "$DB_CONTAINER" pg_dumpall -U postgres --globals-only >"$STAGE/globals.sql" 2>/dev/null </dev/null || { REASON="pg_dumpall --globals-only basarisiz"; return 1; }
  crontab -l >"$STAGE/crontab.txt" 2>/dev/null || true
  # Silinmis hesaplar (yedekten donuste yeniden uygulanir): YALNIZ user_code + zaman, kisisel veri YOK
  {
    echo "user_code,deleted_at_utc"
    dpsql_ro -d "$DB_NAME" -At -F, -c "select target_id, to_char(created_at at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') from audit_log where action = 'account.deleted' order by id" 2>/dev/null </dev/null | grep -E '^[0-9]+,[0-9T:Z-]+$'
  } >"$STAGE/deleted_accounts.csv" || true
  local base srv p mf
  base="$(dirname "$APP_DIR")"; srv="$(basename "$APP_DIR")"
  local -a items=("$srv/.env")
  for p in data public ecosystem.config.cjs; do
    [ -e "$APP_DIR/$p" ] && items+=("$srv/$p")
  done
  local -a nginx_args=()
  if [ -r /etc/nginx/sites-available/api.gudeteknoloji.com.tr ]; then
    nginx_args=(-C /etc/nginx/sites-available api.gudeteknoloji.com.tr)
  else
    warn "nginx sitesi okunamadi, yapilandirma yedegine girmedi"
  fi
  # MQTT broker yapilandirmasi (okunabilen dosyalar; ozel anahtar dizini HARIC) + ACL esitleme sarmalayicisi
  local -a mqtt_args=()
  for mf in mosquitto/mosquitto.conf mosquitto/acl mosquitto/passwd mosquitto/conf.d; do
    [ -r "/etc/$mf" ] && mqtt_args+=("$mf")
  done
  [ "${#mqtt_args[@]}" -gt 0 ] && mqtt_args=(-C /etc "${mqtt_args[@]}")
  local -a wrapper_args=()
  [ -r /usr/local/bin/kapi-mqtt-sync ] && wrapper_args=(-C /usr/local/bin kapi-mqtt-sync)
  tar -czf - -C "$STAGE" . -C "$base" "${items[@]}" "${nginx_args[@]}" "${mqtt_args[@]}" "${wrapper_args[@]}" 2>"$OPS_STATE/backup.tar.err" \
    | enc_file /dev/stdin "$CFG_TMP"
  local r=("${PIPESTATUS[@]}")
  if [ "${r[0]}" -gt 1 ] || [ "${r[1]}" -ne 0 ]; then
    REASON="yapilandirma arsivi/sifreleme hata kodu (tar=${r[0]} openssl=${r[1]})"
    return 1
  fi
  chmod 600 "$CFG_TMP"
  local listing
  listing="$(dec_cmd -in "$CFG_TMP" 2>/dev/null | tar -tzf - 2>/dev/null)"
  printf '%s\n' "$listing" | grep -qx "$srv/\.env" || { REASON="yapilandirma yedegi dogrulamasi basarisiz (.env arsivde yok)"; return 1; }
  printf '%s\n' "$listing" | grep -q 'globals\.sql$' || { REASON="yapilandirma yedegi dogrulamasi basarisiz (globals.sql yok)"; return 1; }
  printf '%s\n' "$listing" | grep -q 'deleted_accounts\.csv$' || { REASON="yapilandirma yedegi dogrulamasi basarisiz (deleted_accounts.csv yok)"; return 1; }
  mv -- "$CFG_TMP" "$CFG_OUT"
  log "   tamam: kapi_config_${TS}.tgz.enc $(human_bytes "$(stat -c %s "$CFG_OUT")") (arsiv girdisi: $(printf '%s\n' "$listing" | wc -l), silinmis hesap kaydi: $(($(wc -l <"$STAGE/deleted_accounts.csv") - 1)))"
  return 0
}
log "[5/9] sifreli yapilandirma yedegi"
if [ "$ENC_RESULT" != "OK" ]; then
  CFG_RESULT="FAIL"
  log "ATLANDI: anahtar sorunu nedeniyle sifreli yapilandirma yedegi alinmadi"
elif ! config_backup; then
  CFG_RESULT="FAIL"
  log "HATA: $REASON"
else
  link_or_copy "$CFG_OUT" "$OFFSITE/kapi_config_${TS}.tgz.enc" || warn "yapilandirma arsivi dis kopya dizinine baglanamadi/kopyalanamadi"
  promote "$CFG_OUT"
fi

# ---- 6. firmware (OTA ikilileri) arsivi: yalniz icerik degisince --------------------------
FW_RESULT="OK"
firmware_backup() {
  local fdir="$APP_DIR/firmware" hash prev listing
  [ -d "$fdir" ] || { log "   firmware dizini yok: atlandi"; return 0; }
  hash="$(cd "$APP_DIR" && find firmware -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1)"
  [ -n "$hash" ] || { REASON="firmware ozeti hesaplanamadi"; return 1; }
  prev="$(cat "$OPS_STATE/firmware.sha256" 2>/dev/null)"
  if [ "$hash" = "$prev" ] && ls "$CONFIGD"/kapi_firmware_*.tgz.enc >/dev/null 2>&1; then
    log "   firmware degismedi: yeni arsiv yok"
    return 0
  fi
  tar -czf - -C "$(dirname "$APP_DIR")" "$(basename "$APP_DIR")/firmware" 2>"$OPS_STATE/backup.tar.err" | enc_file /dev/stdin "$FW_TMP"
  local r=("${PIPESTATUS[@]}")
  if [ "${r[0]}" -gt 1 ] || [ "${r[1]}" -ne 0 ]; then
    REASON="firmware arsivi/sifreleme hata kodu (tar=${r[0]} openssl=${r[1]})"
    return 1
  fi
  listing="$(dec_cmd -in "$FW_TMP" 2>/dev/null | tar -tzf - 2>/dev/null)"
  printf '%s\n' "$listing" | grep -q '/firmware/' || { REASON="firmware arsivi dogrulamasi basarisiz"; return 1; }
  chmod 600 "$FW_TMP"
  mv -- "$FW_TMP" "$FW_OUT"
  link_or_copy "$FW_OUT" "$OFFSITE/kapi_firmware_${TS}.tgz.enc" || warn "firmware arsivi dis kopya dizinine baglanamadi/kopyalanamadi"
  printf '%s\n' "$hash" >"$OPS_STATE/firmware.sha256"
  log "   tamam: kapi_firmware_${TS}.tgz.enc $(human_bytes "$(stat -c %s "$FW_OUT")") (dosya: $(printf '%s\n' "$listing" | grep -vc '/$'))"
  return 0
}
log "[6/9] firmware (OTA ikilileri) sifreli arsivi"
if [ "$ENC_RESULT" != "OK" ]; then
  FW_RESULT="FAIL"
  log "ATLANDI: anahtar sorunu nedeniyle firmware arsivi alinmadi"
elif ! firmware_backup; then
  FW_RESULT="FAIL"
  log "HATA: $REASON"
fi

# ---- 7. belge deposu (DOCUMENTS_DIR) arsivi: DB dokumunden SONRA, yalniz icerik degisince --------
# Dosyalar yazilir-silinmez ve adlari benzersizdir (bir surumun dosyasi BIR KEZ yazilir); dokumden sonra alindigi icin dosya kumesi DB'nin
# ust kumesidir (DB satiri olup dosyasi yedekte olmayan durum dogmaz). <kok>/sites ve <kok>/.instance (depolama kimligi) alinir: _tmp/ (yarim yuklemeler),
# _orphans/ (yetim karantinasi) ve work_attachments/ (is takibi fotograflari; adim 8, ayri arsiv) HARIC. .instance arsivde yoksa geri yuklenen dizin DB ile eslesmez ve bakim yetim temizligini reddeder (R16 P2-4); .instance yoksa HATA verilmez.
# Dizin yoksa / bos ise (modul kapali ya da hic kullanilmadiysa) HATA verilmez, atlanir. Arsiv sifrelidir (config/ + offsite/), 600 izinli.
DOC_RESULT="OK"
documents_backup() {
  local root hash prev listing nfiles sz_mb avail r
  local -a scope
  root="$(documents_root)"
  if [ ! -d "$root" ]; then
    log "   belge dizini yok ($root): atlandi (modul kapali/henuz kullanilmadi olabilir)"
    return 0
  fi
  if [ -L "$root" ]; then
    REASON="belge dizini bir sembolik baglanti ($root): yedek alinmadi"
    return 1
  fi
  if [ ! -d "$root/sites" ]; then
    log "   belge dizininde sites/ yok: atlandi"
    return 0
  fi
  nfiles="$(find "$root/sites" -type f 2>/dev/null | wc -l)"
  nfiles="$(num "$nfiles" 0)"
  if [ "$nfiles" -eq 0 ]; then
    log "   belge dizini bos: atlandi"
    return 0
  fi
  scope=(sites)
  if [ -f "$root/.instance" ] && [ ! -L "$root/.instance" ]; then scope+=(.instance); fi
  hash="$(cd "$root" && find "${scope[@]}" -type f -printf '%p\t%s\t%T@\n' 2>/dev/null | LC_ALL=C sort | sha256sum | cut -d' ' -f1)"
  [ -n "$hash" ] || { REASON="belge dizini ozeti hesaplanamadi"; return 1; }
  prev="$(cat "$OPS_STATE/documents.sha256" 2>/dev/null)"
  if [ "$hash" = "$prev" ] && ls "$CONFIGD"/kapi_documents_*.tgz.enc >/dev/null 2>&1; then
    log "   belge dizini degismedi ($nfiles dosya): yeni arsiv yok"
    return 0
  fi
  sz_mb="$(num "$(du -sm "$root/sites" 2>/dev/null | cut -f1)" 0)"
  if [ "$sz_mb" -gt "$DOCUMENTS_BACKUP_MAX_MB" ]; then
    REASON="belge dizini ${sz_mb} MB > sinir ${DOCUMENTS_BACKUP_MAX_MB} MB (DOCUMENTS_BACKUP_MAX_MB): tam arsiv stratejisi yetersiz, artimli yedege gecmek gerekir"
    return 1
  fi
  avail="$(df -P -BM "$CONFIGD" | awk 'NR==2{gsub(/M/,"",$4); print $4}')"
  if [ "$(num "$avail" 0)" -lt "$((sz_mb * 2 + 200))" ]; then
    REASON="belge arsivi icin yetersiz disk alani (${avail:-?} MB bos, gereken >= $((sz_mb * 2 + 200)) MB)"
    return 1
  fi
  tar -czf - -C "$root" "${scope[@]}" 2>"$OPS_STATE/backup.tar.err" | enc_file /dev/stdin "$DOC_TMP"
  r=("${PIPESTATUS[@]}")
  if [ "${r[0]}" -gt 1 ] || [ "${r[1]}" -ne 0 ]; then
    REASON="belge arsivi/sifreleme hata kodu (tar=${r[0]} openssl=${r[1]})"
    return 1
  fi
  listing="$(dec_cmd -in "$DOC_TMP" 2>/dev/null | tar -tzf - 2>/dev/null)"
  if [ "$(printf '%s\n' "$listing" | grep -vc '/$')" -lt 1 ] || printf '%s\n' "$listing" | grep -qE '(^/|\.\./)'; then
    REASON="belge arsivi dogrulamasi basarisiz (liste bos ya da guvensiz yol)"
    return 1
  fi
  chmod 600 "$DOC_TMP"
  mv -- "$DOC_TMP" "$DOC_OUT"
  link_or_copy "$DOC_OUT" "$OFFSITE/kapi_documents_${TS}.tgz.enc" || warn "belge arsivi dis kopya dizinine baglanamadi/kopyalanamadi"
  printf '%s\n' "$hash" >"$OPS_STATE/documents.sha256"
  log "   tamam: kapi_documents_${TS}.tgz.enc $(human_bytes "$(stat -c %s "$DOC_OUT")") (dosya: $(printf '%s\n' "$listing" | grep -vc '/$'), kaynak ${sz_mb} MB; _tmp ve _orphans haric; ${#scope[@]} kok oge: ${scope[*]})"
  return 0
}
log "[7/9] belge deposu (DOCUMENTS_DIR) sifreli arsivi"
if [ "$ENC_RESULT" != "OK" ]; then
  DOC_RESULT="FAIL"
  log "ATLANDI: anahtar sorunu nedeniyle belge arsivi alinmadi"
elif ! documents_backup; then
  DOC_RESULT="FAIL"
  log "HATA: $REASON"
fi

# ---- 8. is takibi fotograf ekleri (DOCUMENTS_DIR/work_attachments) + geri bildirim ekleri (DOCUMENTS_DIR/feedback_attachments) arsivi: DB dokumunden SONRA, yalniz icerik degisince ----------
# Kapanis: geri bildirim ekleri (feedback_attachments, 103) de bu arsive girer (ayni gorsel-ek niteligi; ayri arsiv/ayar/offsite degisikligi gerekmez; dosya iceren alt agaclar alinir,
# ikisi de bossa atlanir). Geri yukleme sonrasi dosyalar <DOCUMENTS_DIR>/feedback_attachments/<site | 1000000000>/<uuid> altina acilir.
# Belgelerden AYRI arsiv (kendi boyut siniri WORK_ATTACHMENTS_BACKUP_MAX_MB, ozeti, tutma adedi): fotograflar kapanan taleple birlikte kalir; ust sinir
# uygulamadaki site kotasidir (WORK_ATTACHMENTS_SITE_QUOTA_MB; sakin basina son 30 gun WORK_ATTACHMENTS_USER_QUOTA_MB). <kok>/work_attachments ve
# <kok>/.instance alinir; _tmp/ HARIC. Dis kopyada (offsite_push.sh) ve Windows'ta da en yeni KEEP_WORK_ATTACHMENTS arsiv tutulur.
# Dosya adlari benzersizdir (uuid) ve bir kez yazilir; dokumden sonra alindigi icin DB'deki hazir satirlarin dosyalari arsivdedir (aradaki dakikalarda
# kullanicinin sildigi fotograf haric; restore_test.sh bunu canli DB ile ayirt eder). Kok ya da work_attachments/ sembolik baglantiysa REDDEDILIR.
# Dizin yoksa / bossa (is takibi fotografi hic eklenmediyse) HATA verilmez, atlanir. Arsiv sifrelidir (config/ + offsite/), 600 izinli.
WA_RESULT="OK"
work_attachments_backup() {
  local root dir fdir hash prev listing nfiles nf sz_mb avail r sub
  local -a scope sizedirs
  root="$(documents_root)"
  dir="$root/work_attachments"
  fdir="$root/feedback_attachments"
  if [ -L "$root" ]; then
    REASON="belge dizini bir sembolik baglanti ($root): fotograf yedegi alinmadi"
    return 1
  fi
  if [ -L "$dir" ]; then
    REASON="fotograf dizini bir sembolik baglanti ($dir): yedek alinmadi"
    return 1
  fi
  if [ -L "$fdir" ]; then
    REASON="geri bildirim ek dizini bir sembolik baglanti ($fdir): yedek alinmadi"
    return 1
  fi
  # Gorsel-ek agaclari (is takibi fotograflari + geri bildirim ekleri): dosya iceren her alt agac ayni arsive girer.
  scope=()
  sizedirs=()
  nfiles=0
  for sub in work_attachments feedback_attachments; do
    [ -d "$root/$sub" ] || continue
    nf="$(num "$(find "$root/$sub" -type f 2>/dev/null | wc -l)" 0)"
    [ "$nf" -gt 0 ] || continue
    scope+=("$sub")
    sizedirs+=("$root/$sub")
    nfiles=$((nfiles + nf))
  done
  if [ "$nfiles" -eq 0 ]; then
    log "   fotograf / geri bildirim ek dizini yok ya da bos ($dir, $fdir): atlandi (henuz eklenmemis olabilir)"
    return 0
  fi
  if [ -f "$root/.instance" ] && [ ! -L "$root/.instance" ]; then scope+=(.instance); fi
  hash="$(cd "$root" && find "${scope[@]}" -type f -printf '%p\t%s\t%T@\n' 2>/dev/null | LC_ALL=C sort | sha256sum | cut -d' ' -f1)"
  [ -n "$hash" ] || { REASON="fotograf dizini ozeti hesaplanamadi"; return 1; }
  prev="$(cat "$OPS_STATE/work_attachments.sha256" 2>/dev/null)"
  if [ "$hash" = "$prev" ] && ls "$CONFIGD"/kapi_work_attachments_*.tgz.enc >/dev/null 2>&1; then
    log "   fotograf dizini degismedi ($nfiles dosya): yeni arsiv yok"
    return 0
  fi
  sz_mb="$(num "$(du -sm -- "${sizedirs[@]}" 2>/dev/null | awk '{s+=$1} END{print s+0}')" 0)"
  if [ "$sz_mb" -gt "$WORK_ATTACHMENTS_BACKUP_MAX_MB" ]; then
    REASON="fotograf + geri bildirim ek dizini ${sz_mb} MB > sinir ${WORK_ATTACHMENTS_BACKUP_MAX_MB} MB (WORK_ATTACHMENTS_BACKUP_MAX_MB): tam arsiv stratejisi yetersiz; site fotograf kotasini / siniri gozden gecirin ya da artimli yedege gecin"
    return 1
  fi
  avail="$(df -P -BM "$CONFIGD" | awk 'NR==2{gsub(/M/,"",$4); print $4}')"
  if [ "$(num "$avail" 0)" -lt "$((sz_mb * 2 + 200))" ]; then
    REASON="fotograf arsivi icin yetersiz disk alani (${avail:-?} MB bos, gereken >= $((sz_mb * 2 + 200)) MB)"
    return 1
  fi
  tar -czf - -C "$root" "${scope[@]}" 2>"$OPS_STATE/backup.tar.err" | enc_file /dev/stdin "$WA_TMP"
  r=("${PIPESTATUS[@]}")
  if [ "${r[0]}" -gt 1 ] || [ "${r[1]}" -ne 0 ]; then
    REASON="fotograf arsivi/sifreleme hata kodu (tar=${r[0]} openssl=${r[1]})"
    return 1
  fi
  listing="$(dec_cmd -in "$WA_TMP" 2>/dev/null | tar -tzf - 2>/dev/null)"
  if [ "$(printf '%s\n' "$listing" | grep -vc '/$')" -lt 1 ] || printf '%s\n' "$listing" | grep -qE '(^/|\.\./)'; then
    REASON="fotograf arsivi dogrulamasi basarisiz (liste bos ya da guvensiz yol)"
    return 1
  fi
  chmod 600 "$WA_TMP"
  mv -- "$WA_TMP" "$WA_OUT"
  link_or_copy "$WA_OUT" "$OFFSITE/kapi_work_attachments_${TS}.tgz.enc" || warn "fotograf arsivi dis kopya dizinine baglanamadi/kopyalanamadi"
  printf '%s\n' "$hash" >"$OPS_STATE/work_attachments.sha256"
  log "   tamam: kapi_work_attachments_${TS}.tgz.enc $(human_bytes "$(stat -c %s "$WA_OUT")") (dosya: $(printf '%s\n' "$listing" | grep -vc '/$'), kaynak ${sz_mb} MB; _tmp haric; ${#scope[@]} kok oge: ${scope[*]})"
  return 0
}
log "[8/9] is takibi fotograf ekleri (DOCUMENTS_DIR/work_attachments) sifreli arsivi"
if [ "$ENC_RESULT" != "OK" ]; then
  WA_RESULT="FAIL"
  log "ATLANDI: anahtar sorunu nedeniyle fotograf arsivi alinmadi"
elif ! work_attachments_backup; then
  WA_RESULT="FAIL"
  log "HATA: $REASON"
fi

# ---- 9. eski duz yedekleri sifrele + tutma kurallari --------------------------------------
log "[9/9] tutma ve sifreleme: gunluk=$KEEP_DAILY haftalik=$KEEP_WEEKLY aylik=$KEEP_MONTHLY dis_kopya=$KEEP_OFFSITE firmware=$KEEP_FIRMWARE belge=$KEEP_DOCUMENTS fotograf=$KEEP_WORK_ATTACHMENTS"
if [ "$ENC_RESULT" = "OK" ]; then
  # en son (gelecek tarihli OLMAYAN) gunluk yedek duz kalir
  newest_plain="kapi_$(keys_of "$DAILY" kapi | head -n1).sql.gz"
  for f in "$DAILY"/kapi_[0-9]*_[0-9]*.sql.gz "$WEEKLY"/kapi_[0-9]*_[0-9]*.sql.gz "$MONTHLY"/kapi_[0-9]*_[0-9]*.sql.gz; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    fkey="$(sed -nE 's/^kapi_([0-9]{8}_[0-9]{4})\..*/\1/p' <<<"$b")"
    [[ "$fkey" > "$FUTURE_LIMIT" ]] && continue                  # gelecek tarihli dosyaya dokunma
    [ "$(dirname "$f")" = "$DAILY" ] && [ "$b" = "$newest_plain" ] && continue
    demote_plain "$f"
  done
fi
prune_keep "$DAILY" kapi "$KEEP_DAILY"
prune_keep "$WEEKLY" kapi "$KEEP_WEEKLY"
prune_keep "$MONTHLY" kapi "$KEEP_MONTHLY"
prune_keep "$CONFIGD" kapi_config "$((KEEP_DAILY + KEEP_WEEKLY))"
prune_keep "$WEEKLY" kapi_config "$KEEP_WEEKLY"
prune_keep "$MONTHLY" kapi_config "$KEEP_MONTHLY"
prune_keep "$CONFIGD" kapi_firmware "$KEEP_FIRMWARE"
prune_keep "$OFFSITE" kapi "$KEEP_OFFSITE" 1
prune_keep "$OFFSITE" kapi_config "$KEEP_OFFSITE" 1
prune_keep "$OFFSITE" kapi_firmware "$KEEP_FIRMWARE" 1
prune_keep "$CONFIGD" kapi_documents "$KEEP_DOCUMENTS"
prune_keep "$OFFSITE" kapi_documents "$KEEP_DOCUMENTS" 1
prune_keep "$CONFIGD" kapi_work_attachments "$KEEP_WORK_ATTACHMENTS"
prune_keep "$OFFSITE" kapi_work_attachments "$KEEP_WORK_ATTACHMENTS" 1
# belge ve fotograf arsivleri: her turun en yenisi disinda yas sinirindan (DOCUMENTS_MAX_AGE_DAYS / WORK_ATTACHMENTS_MAX_AGE_DAYS, 210 gun) eskiler silinir
# (silinmis belgeler / fotograflar gizlilik suresinden uzun yedekte kalmasin)
for age_spec in "kapi_documents:$DOCUMENTS_MAX_AGE_DAYS" "kapi_work_attachments:$WORK_ATTACHMENTS_MAX_AGE_DAYS"; do
  age_prefix="${age_spec%%:*}"
  age_days="${age_spec#*:}"
  for ddir in "$CONFIGD" "$OFFSITE"; do
    newest_arc="$(keys_of "$ddir" "$age_prefix" | head -n1)"
    while IFS= read -r oldf; do
      [ -n "$oldf" ] || continue
      [ "$(basename "$oldf")" = "${age_prefix}_${newest_arc}.tgz.enc" ] && continue
      rm -f -- "$oldf" && log "tutma kurali (yas > ${age_days} gun): silindi $(basename "$ddir")/$(basename "$oldf")"
    done < <(find "$ddir" -maxdepth 1 -type f -name "${age_prefix}_*.tgz.enc" -mtime "+$age_days" 2>/dev/null)
  done
done

dur="$(($(now_epoch) - START_EPOCH))"
if [ "$ENC_RESULT" = "FAIL" ] || [ "$CFG_RESULT" = "FAIL" ] || [ "$FW_RESULT" = "FAIL" ] || [ "$DOC_RESULT" = "FAIL" ] || [ "$WA_RESULT" = "FAIL" ]; then
  write_status "$STATUS_FILE" "result=FAIL" "epoch=$(now_epoch)" "ts=$TS" "file=kapi_${TS}.sql.gz" "bytes=$size" "tables=$n_tables" "users=$n_users" "reason=${REASON:-sifreli kopya/yapilandirma/firmware/belge/fotograf arsivi basarisiz} (duz veritabani yedegi TAMAM)" "notified=1"
  send_mail "[KAPI-OPS] SORUN: sifreli kopya/yapilandirma yedegi basarisiz (DB yedegi tamam)" "Veritabani yedegi alindi ve dogrulandi, ancak sifreli kopya, yapilandirma, firmware, belge deposu veya fotograf arsivi uretilemedi.
Zaman : $(stamp_local) (Europe/Istanbul)
Neden : ${REASON:-bilinmiyor}
Gunluk: ~/ops/logs/backup.log" || true
  log "=== yedek BITTI (kismi: sifreli kopya/yapilandirma basarisiz) ${dur}s ==="
  trim_log
  exit 2
fi
if [ -n "$WARNINGS" ]; then
  write_status "$STATUS_FILE" "result=WARN" "epoch=$(now_epoch)" "ts=$TS" "file=kapi_${TS}.sql.gz" "bytes=$size" "tables=$n_tables" "users=$n_users" "reason=$WARNINGS"
else
  write_status "$STATUS_FILE" "result=OK" "epoch=$(now_epoch)" "ts=$TS" "file=kapi_${TS}.sql.gz" "bytes=$size" "tables=$n_tables" "users=$n_users"
fi
log "=== yedek BASARILI: kapi_${TS}.sql.gz ($(human_bytes "$size"), tablo=$n_tables, kullanici=$n_users, ${dur}s) ==="
trim_log
exit 0
