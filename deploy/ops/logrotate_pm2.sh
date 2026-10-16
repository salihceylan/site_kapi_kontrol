#!/bin/bash
# PM2 gunlukleri (kapi-api-out.log / kapi-api-error.log) icin KULLANICI duzeyinde logrotate.
#
# Neden bu yol: PM2 gunluk dosyalarini ekleme kipinde (O_APPEND) acik tutar; `copytruncate` dosyayi kopyalayip
# kisaltir, kapi-api'ye SINYAL GONDERMEZ ve onu YENIDEN BASLATMAZ. (pm2-logrotate modulu PM2 daemon'una yeni bir
# surec ekler ve butun uygulamalarin gunluklerini etkiler; bu yuzden kullanilmadi. Sadece kapi-api dosyalari ele alinir,
# ev-api vb. diger projelerin gunluklerine DOKUNULMAZ.)
#
# Kullanim: bash ~/ops/logrotate_pm2.sh [--debug]     (--debug: hicbir sey degistirmeden ne yapacagini gosterir)
# Cron: gunde bir kez. Kural: haftalik veya 20 MB'i asinca don, 8 eski dosya tut, sikistir.
# dateformat saniyeyi icerir: ayni gun iki kez donme (haftalik + boyut esigi) "hedef dosya zaten var" cakismasi yapmaz.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG=logrotate
# shellcheck source=common.sh
. "$HERE/common.sh"

PM2_LOG_DIR="${PM2_LOG_DIR:-$HOME/.pm2/logs}"
CONF="$OPS_HOME/logrotate-pm2.conf"
STATE="$OPS_STATE/logrotate.state"

cat >"$CONF" <<EOF
"$PM2_LOG_DIR/kapi-api-out.log" "$PM2_LOG_DIR/kapi-api-error.log" {
    weekly
    maxsize 20M
    rotate 8
    compress
    delaycompress
    copytruncate
    missingok
    notifempty
    dateext
    dateformat -%Y%m%d-%H%M%S
}
EOF
chmod 600 "$CONF"

if [ "${1:-}" = "--debug" ]; then
  /usr/sbin/logrotate -d -s "$STATE" "$CONF" 2>&1
  exit $?
fi

out="$(/usr/sbin/logrotate -s "$STATE" "$CONF" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then
  log "logrotate tamam"
else
  log "UYARI: logrotate hata kodu $rc: $(echo "$out" | tail -n 2 | tr '\n' ' ' | cut -c1-200)"
fi
trim_log
exit "$rc"
