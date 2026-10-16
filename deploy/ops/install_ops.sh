#!/bin/bash
# VPS'te calistirilir (betikler ~/ops altina kopyalandiktan sonra):
#   bash ~/ops/install_ops.sh [--no-cron] [--remove-cron] [--accept-new-key] [--new-key]
#
# - ~/ops, ~/backups/scheduled/* dizinlerini 700 izinle olusturur
# - ~/.config/kapi-backup.key yoksa uretir (600; icerigi YAZDIRILMAZ). Anahtarin parmak izi (SHA-256) ~/ops/state/key.sha256
#   dosyasina kaydedilir; anahtar KAYBOLMUSSA ve kayit varsa SESSIZCE YENISI URETILMEZ (--new-key gerekir); anahtar DEGISMISSE
#   (parmak izi uyusmuyorsa) durulur (bilerek degistirdiyseniz --accept-new-key). healthcheck.sh ayrica her 5 dk'da denetler.
# - betiklerde sozdizimi denetimi (bash -n / node --check)
# - kullanici crontab'ina "# BEGIN kapi-ops ... # END kapi-ops" blogunu EKLER; mevcut baska satirlara dokunmaz
#   (onceki crontab ~/ops/state/crontab.before.<TS> dosyasina yedeklenir). "crontab -l" "no crontab" disinda bir hata verirse
#   VEYA BEGIN var END yoksa HICBIR SEY degistirilmeden durulur.
# Zamanlar sunucu saatiyle (UTC) yazilir; Turkiye UTC+3 (yaz saati yok): 03:30 Istanbul = 00:30 UTC.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG=install
# shellcheck source=common.sh
. "$HERE/common.sh"

NO_CRON=0; REMOVE_CRON=0; ACCEPT_KEY=0; NEW_KEY=0
for a in "$@"; do
  case "$a" in
    --no-cron) NO_CRON=1 ;;
    --remove-cron) REMOVE_CRON=1 ;;
    --accept-new-key) ACCEPT_KEY=1 ;;
    --new-key) NEW_KEY=1 ;;
    *) echo "bilinmeyen secenek: $a"; exit 64 ;;
  esac
done

chmod 700 "$OPS_HOME" "$OPS_STATE" "$OPS_LOGS" "$OPS_LOCKS"
mkdir -p "$HOME/backups" "$BACKUP_ROOT"/{daily,weekly,monthly,config,offsite} "$HOME/.config"
chmod 700 "$BACKUP_ROOT" "$BACKUP_ROOT"/{daily,weekly,monthly,config,offsite}
chmod 700 "$HERE"/*.sh
chmod 600 "$HERE"/*.mjs "$HERE"/*.example 2>/dev/null || true
log "dizinler hazir: $OPS_HOME, $BACKUP_ROOT"

for f in "$HERE"/*.sh; do bash -n "$f" || { log "SOZDIZIMI HATASI: $f"; exit 1; }; done
node --check "$HERE/ops_mail.mjs" || { log "SOZDIZIMI HATASI: ops_mail.mjs"; exit 1; }
log "sozdizimi denetimi tamam"

# ---- sifreleme anahtari ve parmak izi -----------------------------------------------------------
FP_FILE="$OPS_STATE/key.sha256"
STORED_FP="$(cat "$FP_FILE" 2>/dev/null || true)"
if [ ! -s "$KEY_FILE" ]; then
  if [ -n "$STORED_FP" ] && [ "$NEW_KEY" -ne 1 ]; then
    log "HATA: sifreleme anahtari YOK ($KEY_FILE) ama daha once kaydedilmis bir parmak izi var (${STORED_FP:0:12})."
    log "      Yeni anahtar SESSIZCE uretilmedi: eski sifreli yedekler yalnizca eski anahtarla acilir."
    log "      Eski anahtari parola yoneticinizden $KEY_FILE olarak geri koyun (chmod 600), ya da bilerek yeni anahtar icin --new-key kullanin."
    exit 1
  fi
  ( umask 077; openssl rand -base64 48 >"$KEY_FILE" )
  chmod 600 "$KEY_FILE"
  log "sifreleme anahtari OLUSTURULDU: $KEY_FILE (icerik yazdirilmaz)"
  echo ">>> ONEMLI: bu anahtari sunucu disinda guvenli bir yere kopyalayin (parola yoneticisi). Anahtar kaybolursa sifreli yedekler ACILAMAZ."
  STORED_FP=""
else
  chmod 600 "$KEY_FILE"
  log "sifreleme anahtari mevcut: $KEY_FILE"
fi
CUR_FP="$(key_sha)"
if [ -z "$STORED_FP" ]; then
  printf '%s\n' "$CUR_FP" >"$FP_FILE"
  printf '%s %s %s\n' "$(now_epoch)" "${CUR_FP:0:12}" "kaydedildi" >>"$OPS_STATE/key.history"
  log "anahtar parmak izi kaydedildi: ${CUR_FP:0:12}"
elif [ "$STORED_FP" != "$CUR_FP" ]; then
  if [ "$ACCEPT_KEY" -eq 1 ] || [ "$NEW_KEY" -eq 1 ]; then
    printf '%s\n' "$CUR_FP" >"$FP_FILE"
    printf '%s %s %s\n' "$(now_epoch)" "${CUR_FP:0:12}" "yeni-anahtar-kabul-edildi" >>"$OPS_STATE/key.history"
    log "UYARI: anahtar degisikligi KABUL EDILDI (eski ${STORED_FP:0:12} -> yeni ${CUR_FP:0:12}). Eski sifreli yedekler icin ESKI anahtari da saklayin."
  else
    log "HATA: sifreleme anahtari DEGISMIS (kayitli ${STORED_FP:0:12}, simdiki ${CUR_FP:0:12}). Hicbir sey yapilmadi."
    log "      Bilerek degistirdiyseniz: bash ~/ops/install_ops.sh --accept-new-key (eski anahtari saklayin!)."
    exit 1
  fi
fi
echo "anahtar parmak izi (kontrol icin, anahtar degil): ${CUR_FP:0:12}"

# ---- crontab ---------------------------------------------------------------------------------------
TS="$(TZ=$LOCAL_TZ date +%Y%m%d_%H%M%S)"
CRON_ERR="$(mktemp "$OPS_HOME/cronerr.XXXXXX")"
trap 'rm -f -- "$CRON_ERR"' EXIT
BEFORE=""
if BEFORE="$(crontab -l 2>"$CRON_ERR")"; then
  :
else
  if grep -qi 'no crontab for' "$CRON_ERR"; then
    BEFORE=""
  else
    log "HATA: crontab -l beklenmeyen hata verdi (crontab degistirilmedi): $(head -n1 "$CRON_ERR" | cut -c1-120)"
    exit 1
  fi
fi
printf '%s\n' "$BEFORE" >"$OPS_STATE/crontab.before.$TS"
chmod 600 "$OPS_STATE/crontab.before.$TS"

BEGIN='# BEGIN kapi-ops (install_ops.sh yonetir; elle duzenlemeyin)'
END='# END kapi-ops'
n_begin="$(printf '%s\n' "$BEFORE" | grep -cxF "$BEGIN" || true)"
n_end="$(printf '%s\n' "$BEFORE" | grep -cxF "$END" || true)"
if [ "$n_begin" != "$n_end" ] || [ "$n_begin" -gt 1 ]; then
  log "HATA: crontab'taki kapi-ops blogu tutarsiz (BEGIN=$n_begin END=$n_end). Hicbir sey degistirilmedi; crontab'i elle duzeltin: crontab -e"
  exit 1
fi
REST="$(printf '%s\n' "$BEFORE" | awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1; next} $0==e{skip=0; next} !skip{print}')"
REST="$(printf '%s\n' "$REST" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [ "$NO_CRON" -eq 1 ]; then
  log "--no-cron: crontab degistirilmedi"
  exit 0
fi

if [ "$REMOVE_CRON" -eq 1 ]; then
  printf '%s\n' "$REST" | crontab -
  log "kapi-ops blogu crontab'tan kaldirildi"
  exit 0
fi

BLOCK="$BEGIN
# Sunucu UTC; Istanbul = UTC+3 (yaz saati yok).
*/5 * * * * $OPS_HOME/healthcheck.sh >>$OPS_LOGS/cron_healthcheck.out 2>&1
30 0 * * * flock -n $OPS_LOCKS/cron_backup.lock nice -n 19 ionice -c3 $OPS_HOME/backup_db.sh >>$OPS_LOGS/cron_backup.out 2>&1
50 0 * * * flock -n $OPS_LOCKS/cron_offsite.lock nice -n 19 ionice -c3 $OPS_HOME/offsite_push.sh >>$OPS_LOGS/cron_offsite.out 2>&1
5 1 * * * flock -n $OPS_LOCKS/cron_logrotate.lock nice -n 19 ionice -c3 $OPS_HOME/logrotate_pm2.sh >>$OPS_LOGS/cron_logrotate.out 2>&1
15 1 2 * * flock -n $OPS_LOCKS/cron_restore.lock nice -n 19 ionice -c3 $OPS_HOME/restore_test.sh >>$OPS_LOGS/cron_restore.out 2>&1
$END"

if [ -n "$REST" ]; then
  printf '%s\n\n%s\n' "$REST" "$BLOCK" | crontab -
else
  printf '%s\n' "$BLOCK" | crontab -
fi
log "crontab guncellendi (onceki: $OPS_STATE/crontab.before.$TS)"
crontab -l
