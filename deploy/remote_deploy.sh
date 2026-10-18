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
  echo "[1/5] kod yedegi (.env ve data dahil; firmware/public/node_modules ve node_modules.old_* haric)"
  tar -czf "$BK/server_code.tgz" --exclude='server/node_modules' --exclude='server/node_modules.old_*' --exclude='server/firmware' --exclude='server/public' -C "$BASE" server
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
  # Yasal belgeler (server/legal/*.md): /public/legal-documents ve /legal/:id bu dizinden okur.
  if [ -d "$STAGE/legal" ]; then
    mkdir -p "$APP/legal"
    cp -a "$STAGE/legal/." "$APP/legal/"
    echo "yasal belgeler yerlestirildi: $(ls "$APP/legal" | wc -l) dosya"
  else
    echo "UYARI: pakette legal/ yok (yasal belge uclari bos donecek)"
  fi
  cp -a "$STAGE/package.json" "$STAGE/package-lock.json" "$STAGE/ecosystem.config.cjs" "$STAGE/.env.example" "$APP/"
  mv "$APP/node_modules" "$APP/node_modules.old_$TS"
  mv "$STAGE/node_modules" "$APP/node_modules"
  echo "kod + bagimliliklar yerlestirildi; PM2 yeniden baslatiliyor"
  pm2 restart kapi-api --update-env
  sleep 12
  if health_ok; then
    echo "ACTIVATE_OK"
    curl -fsS -m 10 http://127.0.0.1:8080/health | head -c 400; echo
    prune_old_node_modules || true      # yalniz BASARILI aktivasyondan sonra; geri alma yolunda hicbir sey silinmez
  else
    echo "SAGLIK KONTROLU BASARISIZ"
    pm2 logs kapi-api --lines 40 --nostream 2>&1 | tail -n 40 | cut -c1-220
    rollback
    exit 4
  fi
}

# .env guvenlik ayarlari (SIR YAZDIRMAZ; yalniz anahtar adi ve uzunluk). prepare'den SONRA calistirilir; sonra pm2 restart gerekir.
# Idempotent: ayarlar zaten varsa degistirmez; JWT sirri yalniz <32 karakterse ve JWT_SECRET_PREVIOUS tanimli degilse doner.
# Kullanici onayi: 2026-10-16 ("Hepsini uygula"). Geri alma: cp $BK/env.before_envset $APP/.env && pm2 restart kapi-api --update-env
envset() {
  [ -d "$BK" ] || { echo "HATA: yedek klasoru yok (once prepare)"; exit 2; }
  cd "$APP"
  # orijinal .env yedegi yalniz BIR kez alinir (ikinci calistirmada ezilmez)
  [ -f "$BK/env.before_envset" ] || cp -p .env "$BK/env.before_envset"
  chmod 600 "$BK/env.before_envset" .env
  # tanimsiz anahtar grep'i 1 doner; set -e + pipefail altinda betigi durdurmasin
  getv() { grep -m1 "^$1=" .env | cut -d= -f2- | sed -e "s/^[\"']//" -e "s/[\"']\$//" || true; }
  setv() {
    if grep -q "^$1=" .env; then
      sed -i "s|^$1=.*|$1=$2|" .env
    else
      printf '%s=%s\n' "$1" "$2" >> .env
    fi
  }
  setv NODE_ENV production
  setv LISTEN_HOST 127.0.0.1
  setv TRUST_PROXY loopback,cloudflare
  setv JWT_EXPIRES_IN 30d
  OLD=$(getv JWT_SECRET)
  PREV=$(getv JWT_SECRET_PREVIOUS)
  if [ "${#OLD}" -lt 32 ] && [ -z "$PREV" ]; then
    NEW=$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n')
    # duyuru e-postasi imzasi/ozetleri ayri sirdan turetilir; tanimli degilse eski JWT sirrini ona tasi (abonelikten cik baglantilari bozulmasin)
    if [ -z "$(getv ANNOUNCEMENT_EMAIL_SECRET)" ]; then
      setv ANNOUNCEMENT_EMAIL_SECRET "$OLD"
      echo "ANNOUNCEMENT_EMAIL_SECRET tanimli degildi: eski JWT sirrinden tasindi"
    fi
    setv JWT_SECRET_PREVIOUS "$OLD"
    setv JWT_SECRET_PREVIOUS_UNTIL "$(date -u -d '+30 days' +%Y-%m-%dT%H:%M:%SZ)"
    setv JWT_SECRET "$NEW"
    echo "JWT_SECRET dondurulmus (eski uzunluk ${#OLD}, yeni uzunluk ${#NEW}); eski sir 30 gun yalniz dogrulama icin gecerli"
  else
    echo "JWT_SECRET dondurulmedi (uzunluk ${#OLD}, previous tanimli: $([ -n "$PREV" ] && echo evet || echo hayir))"
  fi
  unset OLD NEW PREV
  chmod 600 .env
  echo "-- .env anahtar durumu (yalniz ad/uzunluk):"
  for k in NODE_ENV LISTEN_HOST TRUST_PROXY JWT_EXPIRES_IN JWT_SECRET JWT_SECRET_PREVIOUS JWT_SECRET_PREVIOUS_UNTIL ANNOUNCEMENT_EMAIL_SECRET; do
    v=$(getv "$k"); printf '   %s: %s\n' "$k" "$([ -z "$v" ] && echo YOK || echo "tanimli (${#v} karakter)")"
  done
  echo ENVSET_OK
}

# Eski bagimlilik dizinleri: yalniz EN SON 2 `node_modules.old_*` kalir (geri alma icin yeterli; her biri ~300 MB). Guvenlik: yalniz $APP'in
# DOGRUDAN altindaki, adi ^node_modules.old_[A-Za-z0-9_]+$ desenine uyan, sembolik baglanti OLMAYAN dizinler; TS adlari sabit genislikli
# (YYYYmmdd_HHMMSS) oldugundan ada gore ters siralama = yeniden eskiye. Bu dagitimin olusturdugu node_modules.old_$TS her zaman korunur.
prune_old_node_modules() {
  local keep=2 n=0 name d
  while IFS= read -r name; do
    n=$((n + 1))
    [ "$n" -gt "$keep" ] || continue
    [ "$name" != "node_modules.old_$TS" ] || continue
    d="$APP/$name"
    { [ -d "$d" ] && [ ! -L "$d" ]; } || continue
    rm -rf -- "$d" && echo "eski bagimlilik dizini silindi: $name"
  done < <(cd "$APP" && ls -1 | grep -E '^node_modules\.old_[A-Za-z0-9_]+$' | sort -r)
  return 0
}

case "$PHASE" in
  prepare) prepare ;;
  envset) envset ;;
  activate) activate ;;
  rollback) rollback ;;
  *) echo "bilinmeyen asama"; exit 1 ;;
esac
