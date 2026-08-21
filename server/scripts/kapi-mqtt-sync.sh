#!/bin/sh
set -eu

APP_DIR="${KAPI_APP_DIR:-/var/www/site_kapi_kontrol/server}"

cd "$APP_DIR"

node scripts/sync_mqtt_acl.js

if systemctl reload mosquitto; then
  exit 0
fi

systemctl restart mosquitto
