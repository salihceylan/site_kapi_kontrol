#!/bin/bash
# SALT-OKUNUR canli sunucu denetimi (degerler maskelenir; hicbir sey degistirmez).
set -u
cd /var/www/site_kapi_kontrol/server || { echo "server dizini yok"; exit 1; }
echo "== dizin (server/)"; ls -A | tr '\n' ' '; echo
echo "== .env anahtarlari (DEGER YOK)"; grep -v '^\s*#' .env 2>/dev/null | grep -v '^\s*$' | sed -E 's/=.*/=<maskeli>/' | sort | tr '\n' ' '; echo
echo "== kritik uzunluklar"
for k in JWT_SECRET COMPANY_API_KEY CORS_ORIGINS MQTT_PASSWORD DB_PASSWORD SMTP_PASSWORD; do
  v=$(grep -E "^$k=" .env 2>/dev/null | head -1 | cut -d= -f2-); echo "$k uzunluk=${#v}"
done
echo "== guvenli degerler"; grep -E '^(NODE_ENV|JWT_EXPIRES_IN|PORT|PUBLIC_BASE_URL|PUBLIC_APP_URL|FIRMWARE_DIR|DB_HOST|MQTT_SYNC_REQUIRED)=' .env 2>/dev/null
echo "== pm2"; pm2 status 2>&1 | head -12
pm2 describe kapi-api 2>/dev/null | grep -E "status|restarts|uptime|script path|exec cwd|interpreter|node.js version" | head -10
echo "== docker"; docker ps --format '{{.Names}} | {{.Status}} | {{.Ports}}' 2>&1 | head -5
echo "== nodemailer surumu"; node -e "console.log(require('./node_modules/nodemailer/package.json').version)" 2>&1 | head -2
echo "== son migration dosyalari"; ls migrations 2>/dev/null | tail -6 | tr '\n' ' '; echo
echo "== uzak-yalniz artik dosyalar"; ls -1 src/services/membership_routes.js apply_014.js migrations/apply_020.js scripts/trigger_ota_wroom.js 2>&1 | head -6
echo "== firmware dizini"; ls -A firmware 2>&1 | tr '\n' ' '; echo; for d in firmware/*; do [ -d "$d" ] && echo "$d: $(ls -A "$d" | tr '\n' ' ')"; done
echo "== veri/qr dizinleri"; ls -d data qrcodes qrs uploads 2>&1 | tr '\n' ' '; echo
echo "== yedek dizini"; ls -la ~/backups 2>&1 | head -6
echo "== disk"; df -h /var/www | tail -1
echo "== api yerel saglik"; curl -s -m 5 http://127.0.0.1:8080/health | head -c 300; echo
echo "== pm2 son loglar (hata satirlari)"; pm2 logs kapi-api --lines 15 --nostream 2>&1 | tail -n 15 | cut -c1-200
