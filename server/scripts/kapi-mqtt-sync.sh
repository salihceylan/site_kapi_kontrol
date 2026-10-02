#!/bin/bash
# Mosquitto ACL/passwd senkronu. Sudoers sarmalayicisi tarafindan root olarak calistirilir.
#
# GUVENLIK: Bu betik root olarak calisirken uygulama dizinindeki scripts/sync_mqtt_acl.js'i de root olarak
# calistirir. Uygulama kullanicisinin yazabildigi bir dizinden root olarak betik calistirmak yetki yukseltmedir;
# bu nedenle sudoers'ta bu betigin root sahipli kopyasi (orn. /usr/local/sbin/kapi-mqtt-sync) tanimlanmali
# ve APP_DIR dizini/betikleri "diger" kullanicilarca yazilabilir olmamalidir (asagida kontrol edilir).
set -euo pipefail
umask 027

DEFAULT_APP_DIR="/var/www/site_kapi_kontrol/server"
APP_DIR="${KAPI_APP_DIR:-$DEFAULT_APP_DIR}"

fail() {
  echo "HATA: $1" >&2
  exit 1
}

# root iken ortamdan gelen dizine guvenme (yalnizca acikca izin verilirse ozel dizin kullanilir).
if [ "$(id -u)" -eq 0 ] && [ "$APP_DIR" != "$DEFAULT_APP_DIR" ] && [ "${KAPI_ALLOW_CUSTOM_APP_DIR:-0}" != "1" ]; then
  fail "root olarak yalnizca ${DEFAULT_APP_DIR} kullanilabilir (ozel dizin icin KAPI_ALLOW_CUSTOM_APP_DIR=1)."
fi

case "$APP_DIR" in
  /*) ;;
  *) fail "APP_DIR mutlak yol olmali." ;;
esac
case "$APP_DIR" in
  *..*|*[[:space:]]*) fail "APP_DIR gecersiz karakter iceriyor." ;;
esac

[ -d "$APP_DIR" ] || fail "APP_DIR bulunamadi."
APP_DIR="$(cd "$APP_DIR" && pwd -P)"
[ -f "$APP_DIR/scripts/sync_mqtt_acl.js" ] || fail "APP_DIR gecerli bir uygulama dizini degil (scripts/sync_mqtt_acl.js yok)."

# Calistirilacak dosyalar baskalarince yazilabilir olmamali.
for target in "$APP_DIR/scripts/sync_mqtt_acl.js" "$APP_DIR/src/mqtt_acl_sync.js" "$APP_DIR/src/db.js"; do
  if [ -e "$target" ] && [ -n "$(find "$target" -maxdepth 0 -perm /o+w 2>/dev/null)" ]; then
    fail "${target} herkes tarafindan yazilabilir durumda; izinleri duzeltin."
  fi
done

NODE_BIN="$(command -v node || true)"
[ -n "$NODE_BIN" ] || fail "node bulunamadi."

# Betige yalnizca gerekli ortam degiskenleri gecirilir (JWT_SECRET, SMTP_*, COMPANY_API_KEY vb. gecmez).
ENV_ARGS=(
  "PATH=$(dirname "$NODE_BIN"):/usr/local/bin:/usr/bin:/bin"
  "HOME=${HOME:-/root}"
  "LANG=${LANG:-C.UTF-8}"
  "NODE_ENV=${NODE_ENV:-production}"
)
while IFS= read -r name; do
  case "$name" in
    DB_*|PG*|MQTT_*|MOSQUITTO_*|KAPI_*|TZ|LC_*)
      ENV_ARGS+=("${name}=${!name}")
      ;;
  esac
done < <(compgen -e)

cd "$APP_DIR"

env -i "${ENV_ARGS[@]}" "$NODE_BIN" scripts/sync_mqtt_acl.js

if systemctl reload mosquitto; then
  exit 0
fi

systemctl restart mosquitto
