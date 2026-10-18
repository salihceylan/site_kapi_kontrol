#!/bin/bash
# Ortak yardimcilar: diger ops betikleri tarafindan `source` edilir. SIR ICERMEZ, sir YAZDIRMAZ.
# Kurulum konumu (VPS): ~/ops/common.sh

OPS_HOME="${OPS_HOME:-$HOME/ops}"
OPS_STATE="$OPS_HOME/state"
OPS_LOGS="$OPS_HOME/logs"
OPS_LOCKS="$OPS_HOME/locks"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/backups/scheduled}"
APP_DIR="${KAPI_APP_DIR:-/var/www/site_kapi_kontrol/server}"
APP_ENV_FILE="$APP_DIR/.env"
DB_CONTAINER="${KAPI_DB_CONTAINER:-site_kapi_kontrol_postgres}"
KEY_FILE="${KAPI_BACKUP_KEY:-$HOME/.config/kapi-backup.key}"
OPS_CONF="${KAPI_OPS_CONF:-$HOME/.config/kapi-ops.env}"
OFFSITE_CONF="${KAPI_OFFSITE_CONF:-$HOME/.config/kapi-offsite.env}"
LOCAL_TZ="Europe/Istanbul"
PBKDF2_ITER=200000

# $HOME/bin ve $HOME/.local/bin: kullanici dizinine kurulan araclar (ornegin rclone) icin.
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LC_ALL=C
umask 077

mkdir -p "$OPS_STATE" "$OPS_LOGS" "$OPS_LOCKS" 2>/dev/null
LOG_TAG="${LOG_TAG:-ops}"
LOG_FILE="${LOG_FILE:-$OPS_LOGS/${LOG_TAG}.log}"

now_epoch() { date +%s; }
ts_local() { TZ="$LOCAL_TZ" date '+%Y%m%d_%H%M'; }
stamp_local() { TZ="$LOCAL_TZ" date '+%Y-%m-%d %H:%M:%S'; }

# Gunluk satiri: hem ekrana hem dosyaya. Parola/e-posta/token YAZMAYIN.
log() {
  local line
  line="$(stamp_local) [$LOG_TAG] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true
}

# Gunluk dosyasi buyurse son N satiri tut.
trim_log() {
  local f="${1:-$LOG_FILE}" max="${2:-1048576}" keep="${3:-3000}" size
  [ -f "$f" ] || return 0
  size=$(stat -c %s "$f" 2>/dev/null || echo 0)
  if [ "$size" -gt "$max" ]; then
    tail -n "$keep" "$f" >"$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
  fi
}

# Sayisal dogrulama: num <deger> <varsayilan>
num() {
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then printf '%s' "$1"
  elif [ $# -ge 2 ]; then printf '%s' "$2"      # acikca verilen varsayilan (bos dize dahil) aynen doner
  else printf '0'; fi
}

# KEY=VALUE dosyasi yukler. source/eval KULLANMAZ (bosluklu degerler komut olarak calismaz).
load_env_file() {
  local f="$1" line k v
  [ -r "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    k="${line%%=*}"
    v="${line#*=}"
    [[ "$k" =~ ^[A-Z][A-Z0-9_]*$ ]] || continue
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    export "$k=$v"
  done <"$f"
}

# Uygulama .env dosyasindan SIR OLMAYAN bir anahtari okur (yalniz izinli adlar).
app_env_get() {
  local key="$1"
  case "$key" in
    DB_NAME|DB_HOST|DB_PORT|DB_USER|PORT|MQTT_HOST|MQTT_PORT|MQTT_CONNECT_HOST|DOCUMENTS_DIR|DOCUMENTS_STORAGE_DIR) ;;
    *) return 1 ;;
  esac
  [ -r "$APP_ENV_FILE" ] || return 1
  grep -m1 "^${key}=" "$APP_ENV_FILE" | cut -d= -f2- | tr -d '\r' | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"
}

load_env_file "$OPS_CONF"

# Belge deposu kokunun yolu (yol SIR DEGILDIR). Uygulamayla ayni cozum sirasi: DOCUMENTS_DIR, eski ad DOCUMENTS_STORAGE_DIR,
# yoksa ~/kapi-documents. KAPI_DOCUMENTS_DIR yalniz ops tarafi gecersiz kilmasidir (kapi-ops.env / deneme). Yol mutlak ve ".." icermeyen olmali.
documents_root() {
  local d
  d="${KAPI_DOCUMENTS_DIR:-}"
  [ -n "$d" ] || d="$(app_env_get DOCUMENTS_DIR 2>/dev/null)"
  [ -n "$d" ] || d="$(app_env_get DOCUMENTS_STORAGE_DIR 2>/dev/null)"
  [ -n "$d" ] || d="$HOME/kapi-documents"
  case "$d" in /*) ;; *) d="$HOME/kapi-documents" ;; esac
  case "$d" in *..*) d="$HOME/kapi-documents" ;; esac
  printf '%s' "${d%/}"
}

DB_NAME="${DB_NAME:-$(app_env_get DB_NAME 2>/dev/null)}"
DB_NAME="${DB_NAME:-site_kapi_kontrol}"
case "$DB_NAME" in *[!A-Za-z0-9_]*|'') DB_NAME="site_kapi_kontrol" ;; esac

# --- Takilma ve kilit sizintisi onlemleri --------------------------------------------------------
# Kilit dosya tanimlayicilari (8 = healthcheck, 9 = agir isler) cocuk surecler tarafindan MIRAS ALINMASIN:
# uzun omurlu/arka plana gecen bir cocuk (ornegin PM2 daemon'u) kilidi sonsuza kadar tutardi.
nolock() { "$@" 8>&- 9>&-; }

# docker komutlari icin zaman asimi (docker daemon'u takilirsa betik sonsuza kadar beklemesin).
DOCKER_TIMEOUT="${DOCKER_TIMEOUT:-600}"
dinspect() { nolock timeout --foreground 15 docker inspect "$@"; }
db_running() { [ "$(dinspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null)" = "true" ]; }

# Postgres: kapsayici icinden superuser (postgres) ile; sifre gerekmez. Zaman asimi + baglanti zaman asimi.
dpsql() { nolock timeout --foreground "$DOCKER_TIMEOUT" docker exec -i -e PGCONNECT_TIMEOUT=10 "$DB_CONTAINER" psql -U postgres -X "$@"; }
# Salt okunur + kilit ve sorgu zaman asimli oturum (canli veritabanina YAZMAZ, kilit bekleyip takilmaz).
dpsql_ro() {
  nolock timeout --foreground "$DOCKER_TIMEOUT" docker exec -i -e PGCONNECT_TIMEOUT=10 \
    -e PGOPTIONS='-c default_transaction_read_only=on -c lock_timeout=5s -c statement_timeout=60s' \
    "$DB_CONTAINER" psql -U postgres -X "$@"
}

# Sifreleme (anahtar dosyadan okunur, komut satirinda gorunmez)
enc_file() { nolock openssl enc -aes-256-cbc -pbkdf2 -iter "$PBKDF2_ITER" -salt -pass "file:$KEY_FILE" -in "$1" -out "$2"; }
dec_cmd() { nolock openssl enc -d -aes-256-cbc -pbkdf2 -iter "$PBKDF2_ITER" -pass "file:$KEY_FILE" "$@"; }
key_sha() { sha256sum "$KEY_FILE" 2>/dev/null | cut -d' ' -f1; }

# Kilit: ayni anda tek agir is (yedek / geri yukleme / dis kopya). $1 = kilit adi, $2 = bekleme sn.
acquire_lock() {
  local name="${1:-heavy}" wait="${2:-900}"
  exec 9>"$OPS_LOCKS/$name.lock"
  if ! flock -w "$wait" 9; then
    log "ATLANDI: baska bir ops isi calisiyor ($name kilidi ${wait}s icinde alinamadi)"
    exit 75
  fi
}

# Ayni betigi dusuk oncelikli calistir. Not: ionice -c3 (idle) yalnizca CFQ/BFQ I/O zamanlayicisinda etkilidir;
# mq-deadline/none kullanan diskte etkisizdir (zararsizdir). Asil koruma nice + kucuk veri boyutudur.
reexec_low_priority() {
  if [ -z "${KAPI_OPS_NICE:-}" ]; then
    export KAPI_OPS_NICE=1
    exec nice -n 19 ionice -c3 bash "$0" "$@"
  fi
}

# --- E-posta uyarisi ---------------------------------------------------------------------------
resolve_recipients() {
  local cache="$OPS_STATE/recipients" list
  if [ -n "${ALERT_EMAIL:-}" ]; then
    printf '%s\n' "$ALERT_EMAIL"
    return 0
  fi
  list=$(nolock timeout --foreground 20 docker exec -i -e PGCONNECT_TIMEOUT=10 \
    -e PGOPTIONS='-c default_transaction_read_only=on -c lock_timeout=5s -c statement_timeout=10s' \
    "$DB_CONTAINER" psql -U postgres -X -d "$DB_NAME" -Atc \
    "select email from users where role='super_user' and is_active and coalesce(email,'')<>'' and email not like '%@deleted.invalid' order by id" 2>/dev/null \
    | tr '\n' ',' | sed 's/,$//')
  if [ -n "$list" ]; then
    printf '%s\n' "$list" >"$cache" 2>/dev/null && chmod 600 "$cache" 2>/dev/null
    printf '%s\n' "$list"
  elif [ -s "$cache" ]; then
    cat "$cache"
  fi
}

# send_mail "konu" "govde"  -> 0 basarili, 1 basarisiz. Basarisizlikta yerel gunluge + bayrak dosyasina duser.
# Alici ve konu komut satirinda DEGIL ortam degiskeniyle (yalniz alt kabukta) gecer: `ps` ciktisinda gorunmez.
send_mail() {
  local subject="$1" body="$2" to out rc
  to="$(resolve_recipients)"
  {
    printf '%s | %s\n%s\n---\n' "$(stamp_local)" "$subject" "$body"
  } >>"$OPS_LOGS/alerts.log" 2>/dev/null
  trim_log "$OPS_LOGS/alerts.log" 524288 2000
  if [ -z "$to" ]; then
    out="alici bulunamadi"
    rc=1
  else
    out=$( { export OPS_MAIL_SUBJECT="$subject" OPS_MAIL_TO="$to"; printf '%s\n' "$body" | nolock timeout 60 node "$OPS_HOME/ops_mail.mjs"; } 2>&1 )
    rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    rm -f "$OPS_STATE/MAIL_FAILED" "$OPS_STATE/ALERT_UNSENT"
    log "e-posta gonderildi: $out"
    return 0
  fi
  log "UYARI: e-posta GONDERILEMEDI ($out); yerel gunluge ve bayrak dosyasina yazildi"
  {
    printf 'zaman=%s\nkonu=%s\nnedeni=%s\n---\n%s\n' "$(stamp_local)" "$subject" "$out" "$body"
  } >"$OPS_STATE/ALERT_UNSENT" 2>/dev/null
  printf '%s\n' "$(now_epoch)" >"$OPS_STATE/MAIL_FAILED" 2>/dev/null
  return 1
}

# Durum dosyasini atomik yaz (anahtar=deger satirlari).
write_status() {
  local file="$1"; shift
  local tmp="$file.tmp.$$"
  : >"$tmp"
  local kv
  for kv in "$@"; do printf '%s\n' "$kv" >>"$tmp"; done
  mv "$tmp" "$file"
}

status_get() { # status_get dosya anahtar
  [ -r "$1" ] || return 1
  grep -m1 "^$2=" "$1" | cut -d= -f2-
}

# Ayni icerigi ikinci kez diskte TUTMAMAK icin: sert bag (hard link) kur, olmazsa (farkli dosya sistemi vb.) kopyala.
# Hedef once ".part" adiyla olusur, sonra atomik tasinir. Dosyalar hicbir zaman yerinde degistirilmez (yalniz olusturulur/silinir/yeniden
# adlandirilir), bu yuzden ortak inode guvenlidir: bir adin silinmesi (tutma kurali) digerlerini etkilemez. Baglar yedek kokunun
# ICINDE kalir (BACKUP_ROOT altindaki dizinler arasi). Kaynak yoksa 1 doner.
link_or_copy() { # link_or_copy <kaynak> <hedef>
  local src="$1" dst="$2"
  [ -f "$src" ] || return 1
  [ "$src" -ef "$dst" ] && return 0       # zaten ayni dosya (ayni inode)
  rm -f -- "$dst.part"
  if ! ln -- "$src" "$dst.part" 2>/dev/null; then
    cp -p -- "$src" "$dst.part" || { rm -f -- "$dst.part"; return 1; }
  fi
  mv -f -- "$dst.part" "$dst" || { rm -f -- "$dst.part"; return 1; }
}

human_bytes() { # basit insan okur boyut
  awk -v b="$1" 'BEGIN{ s="B KB MB GB"; split(s,u," "); i=1; while (b>=1024 && i<4) { b/=1024; i++ } printf "%.1f %s", b, u[i] }'
}
