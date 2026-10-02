#!/bin/bash
# Canli sunucu dagitimi (AGENTS.md kural 8). Iki asamali: prepare (canliya DOKUNMAZ) ve activate (canliya alir + saglik + otomatik geri alma).
# Kullanim: bash remote_deploy.sh <TS> prepare|activate|rollback
set -euo pipefail
TS="$1"
PHASE="$2"
BASE=/var/www/site_kapi_kontrol
APP="$BASE/server"
BK="$HOME/backups/kapi_$TS"
STAGE="$HOME/kapi_stage_$TS"
PKG="$HOME/kapi_deploy_$TS.tgz"
DBC=site_kapi_kontrol_postgres

health_ok() {
  curl -fsS -m 10 http://127.0.0.1:8080/health 2>/dev/null | grep -q '"ok":true'
}

rollback() {
  echo "=== GERI ALMA basliyor (yedek: $BK) ==="
  cd "$APP"
  tar -xzf "$BK/server_code.tgz" --exclude='server/data' -C "$BASE"
  if [ -d "$APP/node_modules.old_$TS" ]; then
    rm -rf "$APP/node_modules"
    mv "$APP/node_modules.old_$TS" "$APP/node_modules"
  fi
  pm2 restart kapi-api --update-env
  sleep 10
  if health_ok; then echo "GERI ALMA TAMAM: /health ok"; else echo "UYARI: geri almadan sonra /health HATALI"; fi
}

prepare() {
  mkdir -p "$BK"
  chmod 700 "$BK"
  echo "[1/5] kod yedegi (.env ve data dahil; firmware/public/node_modules haric)"
  tar -czf "$BK/server_code.tgz" --exclude='server/node_modules' --exclude='server/firmware' --exclude='server/public' -C "$BASE" server
  chmod 600 "$BK/server_code.tgz"
  echo "[2/5] veritabani yedegi (pg_dump)"
  docker exec "$DBC" pg_dump -U postgres -d site_kapi_kontrol | gzip > "$BK/db.sql.gz"
  chmod 600 "$BK/db.sql.gz"
  if [ ! -s "$BK/db.sql.gz" ] || [ "$(stat -c %s "$BK/db.sql.gz")" -lt 2000 ]; then
    echo "HATA: DB yedegi bos/kucuk"
    exit 3
  fi
  echo "[3/5] paket aciliyor"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  tar xzf "$PKG" -C "$STAGE"
  echo "[4/5] sozdizimi kontrolu (node --check)"
  cd "$STAGE"
  find src scripts -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -print0 | xargs -0 -n1 node --check
  echo "[5/5] bagimliliklar (staged npm ci --omit=dev)"
  npm ci --omit=dev --no-audit --no-fund 2>&1 | tail -3
  node -e "console.log('nodemailer', require('./node_modules/nodemailer/package.json').version)"
  ls -l "$BK"
  echo PREPARE_OK
}

activate() {
  [ -d "$STAGE/node_modules" ] || { echo "HATA: hazirlik (prepare) yapilmamis"; exit 2; }
  cd "$APP"
  # COMPANY_API_KEY: yeni kod sirket uclarini X-Company-Key ile yetkilendirir; tanimsizsa sirket araci calismaz
  if ! grep -q '^COMPANY_API_KEY=.\{24,\}' .env; then
    KEY=$(node -e "console.log(require('crypto').randomBytes(36).toString('base64url'))")
    sed -i '/^COMPANY_API_KEY=/d' .env
    printf '\nCOMPANY_API_KEY=%s\n' "$KEY" >> .env
    echo "COMPANY_API_KEY tanimlandi (uzunluk ${#KEY})"
  else
    echo "COMPANY_API_KEY zaten tanimli"
  fi
  chmod 600 .env
  cp -a "$STAGE/src/." "$APP/src/"
  cp -a "$STAGE/scripts/." "$APP/scripts/"
  cp -a "$STAGE/migrations/." "$APP/migrations/"
  cp -a "$STAGE/package.json" "$STAGE/package-lock.json" "$STAGE/ecosystem.config.cjs" "$STAGE/.env.example" "$APP/"
  mv "$APP/node_modules" "$APP/node_modules.old_$TS"
  mv "$STAGE/node_modules" "$APP/node_modules"
  echo "kod + bagimliliklar yerlestirildi; PM2 yeniden baslatiliyor"
  pm2 restart kapi-api --update-env
  sleep 12
  if health_ok; then
    echo "ACTIVATE_OK"
    curl -fsS -m 10 http://127.0.0.1:8080/health | head -c 400; echo
  else
    echo "SAGLIK KONTROLU BASARISIZ"
    pm2 logs kapi-api --lines 40 --nostream 2>&1 | tail -n 40 | cut -c1-220
    rollback
    exit 4
  fi
}

case "$PHASE" in
  prepare) prepare ;;
  activate) activate ;;
  rollback) rollback ;;
  *) echo "bilinmeyen asama"; exit 1 ;;
esac
