#!/bin/bash
# Sunucu ici izleme (cron: her 5 dk). Kontroller: API sagligi (yerel + genel), PM2 kapi-api (+ yeniden baslama),
# Postgres kapsayicisi + sorgu, disk, bellek, son yedek yasi + son yedek/geri yukleme/dis kopya durumu,
# sifreleme anahtari parmak izi, TLS sertifika bitisi (origin / kenar / MQTT / ev otomasyonu 443+8884), MQTT TCP uclari.
#
# Uyari tekillestirme (durum dosyasi ~/ops/state/health.state): ayni sorun icin
#   - gecici kesintilere karsi ardisik N basarisizlik (cogu kontrol icin 2) sonrasi,
#   - durum degisince (yeni sorun / WARN<->CRIT) hemen,
#   - degismediyse REMIND_HOURS (6) saatte bir hatirlatma,
#   - duzeldi postasi ancak ART ARDA 2 basarili calismadan sonra (titresim/flapping onlemi)
# TEK e-posta gonderir. E-posta: sunucunun SMTP ayari (server/.env) + alici = aktif super_user hesaplar
# (kapi-ops.env icinde ALERT_EMAIL ile degistirilebilir). Gonderilemezse ~/ops/logs/alerts.log + ~/ops/state/ALERT_UNSENT.
#
# Olay (EVENT) kurali: kapi-api yeniden baslamalari TEK BASINA posta uretmez (normal dagitim = 1 yeniden baslama);
#   son 60 dk'da >= PM2_EVENT_MIN (3) yeniden baslama varsa "OLAY" postasi gider (olaylar arasi en az 30 dk);
#   >= PM2_LOOP_RESTARTS (6) ise CRIT "pm2_loop" (cokme dongusu) olur ve ayrica OLAY uretilmez.
#
# Olu adam anahtari: ~/.config/kapi-ops.env icinde HEARTBEAT_URL varsa, her BASARIYLA tamamlanan calismanin sonunda
# bu adrese GET atilir (healthchecks.io / UptimeRobot heartbeat). Adres gunluge yazilmaz. Tanimsizsa sessiz.
#
# Disk: doluluk esikleri varsayilan %70 uyari / %85 kritik (DISK_WARN / DISK_CRIT ile degisir) + inode. Gunluk buyume hizi: gunde en fazla
#   bir ornek (~/ops/state/disk.hist), hiz (GB/gun) ~/ops/state/disk_growth.state'e yazilir; bu hizla doluma DISK_GROWTH_DAYS (30) gunden az
#   kaldiysa "disk_growth" WARN olur (mevcut uyari kanali; tek seferlik sicramalara karsi son ornek ile 7 gunluk ortalamanin KUCUGU kullanilir).
# Haftalik rapor: her PAZARTESI (Istanbul, saat >= WEEKLY_REPORT_HOUR=8) en buyuk 10 tablo (pg_total_relation_size, onceki haftaya gore degisim)
#   + yedek / belge deposu / PM2 gunluk dizin boyutlari ozeti: ~/ops/logs/weekly_report.log'a yazilir ve ayni e-posta kanaliyla gonderilir.
#   SIR ICERMEZ (yalniz tablo adi, boyut, satir sayisi tahmini).
#
# Kullanim:
#   healthcheck.sh                  normal (cron)
#   healthcheck.sh --dry-run -v     kontrolleri yap ve yazdir; e-posta YOK, durum/sayac dosyalari degismez
#   healthcheck.sh --test-alert     alicilara test e-postasi gonder (durum ve sayac dosyalari degismez)
#   healthcheck.sh --weekly-report  haftalik raporu gunu beklemeden simdi uret ve gonder (--dry-run ile: yalniz ekrana yazdir)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG=healthcheck
# shellcheck source=common.sh
. "$HERE/common.sh"
renice -n 10 $$ >/dev/null 2>&1 || true

DRY=0; VERBOSE=0; TEST=0; WEEKLY_FORCE=0
for a in "$@"; do
  case "$a" in
    --dry-run|--status) DRY=1; VERBOSE=1 ;;
    -v|--verbose) VERBOSE=1 ;;
    --test-alert) TEST=1 ;;
    --weekly-report) WEEKLY_FORCE=1 ;;
    *) echo "bilinmeyen secenek: $a"; exit 64 ;;
  esac
done
# Durum/sayac dosyalarini YALNIZ normal calismada yaz (--dry-run ve --test-alert sayaclari ilerletmez)
PERSIST=1
{ [ "$DRY" -eq 1 ] || [ "$TEST" -eq 1 ]; } && PERSIST=0

exec 8>"$OPS_LOCKS/healthcheck.lock"
flock -n 8 || { [ "$VERBOSE" -eq 1 ] && echo "baska bir healthcheck calisiyor"; exit 0; }

# ---- yapilandirma (kapi-ops.env ile gecersiz kilinabilir) -------------------------------
API_LOCAL_URL="${API_LOCAL_URL:-http://127.0.0.1:8080/health}"
API_PUBLIC_URL="${API_PUBLIC_URL:-https://api.gudeteknoloji.com.tr/health}"
TLS_API_HOST="${TLS_API_HOST:-api.gudeteknoloji.com.tr}"
MQTT_LOCAL="${MQTT_LOCAL:-127.0.0.1:8883}"
MQTT_PUBLIC="${MQTT_PUBLIC:-mqtt.gudeteknoloji.com.tr:8883}"
CHECK_MQTT_PUBLIC="${CHECK_MQTT_PUBLIC:-1}"
# Ayni sunucudaki ev otomasyonu: nginx (443) ve EMQX (8884) ayni Let's Encrypt sertifikasini sunar; EMQX yenilenen
# dosyayi almazsa yalniz 8884 eski kalir (yenileme kancasi: /etc/letsencrypt/renewal-hooks/deploy/60-emqx-evotomasyon-cert.sh)
TLS_EV_HOST="${TLS_EV_HOST:-evotomasyon.gudeteknoloji.com.tr}"
TLS_EV_MQTT_PORT="${TLS_EV_MQTT_PORT:-8884}"
CHECK_EV_TLS="${CHECK_EV_TLS:-1}"
SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-178.210.161.55}"
PM2_APP="${PM2_APP:-kapi-api}"
PM2_LOOP_RESTARTS="$(num "${PM2_LOOP_RESTARTS:-6}" 6)"
PM2_EVENT_MIN="$(num "${PM2_EVENT_MIN:-3}" 3)"
EVENT_MIN_GAP="$(num "${EVENT_MIN_GAP:-1800}" 1800)"
DISK_WARN="$(num "${DISK_WARN:-70}" 70)"
DISK_CRIT="$(num "${DISK_CRIT:-85}" 85)"
DISK_GROWTH_DAYS="$(num "${DISK_GROWTH_DAYS:-30}" 30)"          # 0 = buyume hizi uyarisi kapali
WEEKLY_REPORT_HOUR="$(num "${WEEKLY_REPORT_HOUR:-8}" 8)"        # pazartesi bu saatten (Istanbul) sonraki ilk calismada
BACKUP_MAX_AGE_H="$(num "${BACKUP_MAX_AGE_H:-26}" 26)"
RESTORE_MAX_AGE_D="$(num "${RESTORE_MAX_AGE_D:-40}" 40)"
TLS_WARN_DAYS="$(num "${TLS_WARN_DAYS:-14}" 14)"
TLS_WARN_DAYS_MQTT="$(num "${TLS_WARN_DAYS_MQTT:-21}" 21)"
TLS_CRIT_DAYS="$(num "${TLS_CRIT_DAYS:-7}" 7)"
REMIND_HOURS="$(num "${REMIND_HOURS:-6}" 6)"
MAIL_RETRY_SECS="$(num "${MAIL_RETRY_SECS:-1800}" 1800)"
HEARTBEAT_URL="${HEARTBEAT_URL:-}"

STATE_FILE="$OPS_STATE/health.state"
NOW="$(now_epoch)"
RUN_OK=1

declare -A S_LEVEL S_SINCE S_FAILS S_ALERTED S_LAST S_OKS     # onceki durum
declare -A N_LEVEL N_SINCE N_FAILS N_ALERTED N_LAST N_OKS     # yeni durum
declare -A R_LEVEL R_MSG R_NEED R_REMIND R_PRE                # bu calismanin sonuclari
ORDER=()

# durum dosyasini yukle: her alan dogrulanir (bozuk satir betigi cokertmez)
if [ -r "$STATE_FILE" ]; then
  while IFS='|' read -r n lv sn fl al ls ok; do
    [[ "${n:-}" =~ ^[a-z0-9_]+$ ]] || continue
    case "${lv:-}" in OK|WARN|CRIT) ;; *) lv=OK ;; esac
    S_LEVEL[$n]="$lv"
    S_SINCE[$n]="$(num "${sn:-}" "$NOW")"
    S_FAILS[$n]="$(num "${fl:-}" 0)"
    S_ALERTED[$n]="$(num "${al:-}" 0)"
    S_LAST[$n]="$(num "${ls:-}" 0)"
    S_OKS[$n]="$(num "${ok:-}" 0)"
  done <"$STATE_FILE"
fi

fmt_dur() { # saniye -> okunur
  local s
  s="$(num "${1:-0}" 0)"
  if [ "$s" -lt 120 ]; then echo "${s} sn"
  elif [ "$s" -lt 7200 ]; then echo "$((s / 60)) dk"
  elif [ "$s" -lt 172800 ]; then echo "$((s / 3600)) sa $(((s % 3600) / 60)) dk"
  else echo "$((s / 86400)) gun"; fi
}

# result <ad> <OK|WARN|CRIT|EVENT> <mesaj> [ardisik-basarisizlik=2] [hatirlatma-saat] [onceden-bildirildi=0]
result() {
  local n="$1"
  ORDER+=("$n")
  R_LEVEL[$n]="$2"
  R_MSG[$n]="$3"
  R_NEED[$n]="$(num "${4:-2}" 2)"
  R_REMIND[$n]="$(num "${5:-$REMIND_HOURS}" "$REMIND_HOURS")"
  R_PRE[$n]="${6:-0}"
}

tcp_open() { # host port
  [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$2" =~ ^[0-9]+$ ]] || return 1
  timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

cert_days() { # host port sni -> gun sayisi | ERR
  local end epoch
  end="$(echo | timeout 12 openssl s_client -servername "$3" -connect "$1:$2" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
  [ -n "$end" ] || { echo ERR; return; }
  epoch="$(date -d "$end" +%s 2>/dev/null)" || { echo ERR; return; }
  echo $(((epoch - $(date +%s)) / 86400))
}

# ---- kontroller -----------------------------------------------------------------------------
check_api() {
  local out code json
  out="$(curl -sS -m 10 -w '\n%{http_code}' "$API_LOCAL_URL" 2>/dev/null)"
  code="$(tail -n1 <<<"$out")"
  json="$(sed '$d' <<<"$out")"
  if [ "$code" = "200" ] && grep -q '"ok":true' <<<"$json" && grep -q '"database":"connected"' <<<"$json"; then
    result api OK "HTTP 200, veritabani bagli" 2
    if grep -q '"configured":true' <<<"$json"; then
      if grep -q '"connected":true' <<<"$json"; then
        result mqtt_bridge OK "API MQTT koprusu bagli" 2
      else
        result mqtt_bridge WARN "API'nin MQTT koprusu bagli degil (son hata: $(sed -n 's/.*"last_error":"\([^"]*\)".*/\1/p' <<<"$json" | head -c 60))" 2
      fi
    fi
  else
    result api CRIT "yerel saglik ucu basarisiz (HTTP ${code:-000}); PM2/Node/veritabani sorunu olabilir" 2
  fi
}

check_api_public() {
  local out code json
  out="$(curl -sS -m 15 -w '\n%{http_code}' "$API_PUBLIC_URL" 2>/dev/null)"
  code="$(tail -n1 <<<"$out")"
  json="$(sed '$d' <<<"$out")"
  if [ "$code" = "200" ] && grep -q '"ok":true' <<<"$json"; then
    result api_public OK "genel adres HTTP 200" 2
  else
    result api_public CRIT "genel adres (nginx/Cloudflare dahil) HTTP ${code:-000}" 2
  fi
}

check_pm2() {
  local line st restarts unstable up pid prev_r hist cutoff base delta=0 loop_crit=0
  # pm2 (gerekirse daemon'u baslatabilir): kilit tanimlayicilari cocuga MIRAS BIRAKILMAZ (nolock)
  line="$(nolock timeout --foreground 30 pm2 jlist 2>/dev/null | node -e '
let s = "";
process.stdin.on("data", (d) => (s += d)).on("end", () => {
  const i = s.indexOf("[");
  let a = [];
  try { a = JSON.parse(s.slice(i)); } catch (e) {}
  const p = a.find((x) => x.name === process.argv[1]);
  if (!p) { console.log("NOTFOUND"); return; }
  const e = p.pm2_env || {};
  console.log(["OK", e.status, e.restart_time, e.unstable_restarts || 0, Math.floor((Date.now() - e.pm_uptime) / 1000), p.pid || 0].join(" "));
});' "$PM2_APP" 2>/dev/null)"
  if [ -z "$line" ] || [ "$line" = "NOTFOUND" ]; then
    result pm2 CRIT "PM2 '$PM2_APP' sureci okunamadi/bulunamadi" 2
    return
  fi
  read -r _ st restarts unstable up pid <<<"$line"
  restarts="$(num "${restarts:-}" 0)"; unstable="$(num "${unstable:-}" 0)"; up="$(num "${up:-}" 0)"
  if [ "$st" != "online" ]; then
    result pm2 CRIT "PM2 '$PM2_APP' durumu: ${st:-?}" 2
  elif [ "$unstable" -gt 0 ]; then
    result pm2 WARN "PM2 '$PM2_APP' kararsiz yeniden baslama sayisi: $unstable" 1
  else
    result pm2 OK "online, calisma suresi $(fmt_dur "$up"), yeniden baslama sayaci $restarts" 2
  fi
  prev_r="$(num "$(awk -v a="$PM2_APP" '$1==a {print $2}' "$OPS_STATE/pm2.last" 2>/dev/null)" "")"
  hist="$OPS_STATE/pm2.hist"
  cutoff=$((NOW - 3600))
  base="$(num "$(awk -v c="$cutoff" '$1>=c {print $2; exit}' "$hist" 2>/dev/null)" "")"
  if [ -n "$base" ] && [ "$restarts" -ge "$base" ]; then
    delta=$((restarts - base))
  fi
  if [ "$delta" -ge "$PM2_LOOP_RESTARTS" ]; then
    loop_crit=1
    result pm2_loop CRIT "son 60 dk'da $delta yeniden baslama (cokme dongusu olabilir)" 1
  else
    result pm2_loop OK "son 60 dk'da $delta yeniden baslama" 1
  fi
  # Yeniden baslama OLAYI: dongu varken ayrica uretilmez; tek basina (dagitim) posta gondermez, yalniz gunluge yazilir
  if [ -n "$prev_r" ] && [ "$restarts" -gt "$prev_r" ] && [ "$loop_crit" -eq 0 ]; then
    if [ "$delta" -ge "$PM2_EVENT_MIN" ]; then
      result pm2_restart EVENT "$PM2_APP son 60 dk'da $delta kez yeniden basladi (sayac $prev_r -> $restarts). Dagitim degilse: pm2 logs $PM2_APP --err --lines 80" 1
    else
      result pm2_restart OK "yeniden basladi (sayac $prev_r -> $restarts; dagitim olabilir), son 60 dk'da $delta" 1
      [ "$PERSIST" -eq 1 ] && log "bilgi: $PM2_APP yeniden basladi (sayac $prev_r -> $restarts), son 60 dk'da $delta; esik altinda, posta yok"
    fi
  else
    result pm2_restart OK "yeniden baslama yok" 1
  fi
  if [ "$PERSIST" -eq 1 ]; then
    printf '%s %s\n' "$PM2_APP" "$restarts" >"$OPS_STATE/pm2.last"
    printf '%s %s\n' "$NOW" "$restarts" >>"$hist"
    tail -n 400 "$hist" >"$hist.tmp" && mv "$hist.tmp" "$hist"
  fi
}

check_postgres() {
  local q cnt maxc
  if ! db_running; then
    result postgres CRIT "kapsayici calismiyor veya docker yanit vermiyor ($DB_CONTAINER)" 2
    return
  fi
  q="$(nolock timeout --foreground 20 docker exec -e PGCONNECT_TIMEOUT=5 -e PGOPTIONS='-c default_transaction_read_only=on -c lock_timeout=3s -c statement_timeout=10s' \
    "$DB_CONTAINER" psql -U postgres -X -d "$DB_NAME" -At -F '|' -c "select 1, (select count(*) from pg_stat_activity), current_setting('max_connections')::int" 2>/dev/null)"
  if [ "${q%%|*}" != "1" ]; then
    result postgres CRIT "kapsayici calisiyor ama sorgu yanit vermiyor (20 sn)" 2
    return
  fi
  cnt="$(num "$(cut -d'|' -f2 <<<"$q")" 0)"; maxc="$(num "$(cut -d'|' -f3 <<<"$q")" 100)"
  [ "$maxc" -gt 0 ] || maxc=100
  if [ "$((cnt * 100 / maxc))" -ge 80 ]; then
    result postgres WARN "baglanti sayisi yuksek: $cnt / $maxc" 2
  else
    result postgres OK "sorgu yanitliyor, baglanti $cnt/$maxc" 2
  fi
}

check_disk() {
  local use iuse
  use="$(num "$(df -P / | awk 'NR==2{gsub(/%/,"",$5); print $5}')" 0)"
  iuse="$(num "$(df -Pi / | awk 'NR==2{gsub(/%/,"",$5); print $5}')" 0)"
  if [ "$use" -ge "$DISK_CRIT" ]; then result disk CRIT "disk %$use dolu (>= %$DISK_CRIT)" 1
  elif [ "$use" -ge "$DISK_WARN" ]; then result disk WARN "disk %$use dolu (>= %$DISK_WARN)" 1
  elif [ "$iuse" -ge 90 ]; then result disk WARN "inode kullanimi %$iuse" 1
  else result disk OK "disk %$use dolu (bos: $(df -Ph / | awk 'NR==2{print $4}')), inode %$iuse" 1; fi
}

# Gunluk disk buyume hizi (GB/gun). Ornek dosyasi disk.hist: "epoch kullanilan_KB" (gunde en fazla 1 satir, son 60 gun).
# Hiz = simdiki kullanim - "onceki olcum" (en yeni >= 20 saat eski ornek); ikinci olarak 7 gunluk ortalama. Uyari icin KUCUK olan
# kullanilir (tek seferlik sicrama = dagitim yedegi / imaj indirme alarm uretmesin; surekli buyume uretsin).
check_disk_growth() {
  local hist="$OPS_STATE/disk.hist" used avail last_ep out r1 r7 eff days msg
  read -r used avail < <(df -Pk / | awk 'NR==2{print $3, $4}')
  used="$(num "${used:-}" 0)"; avail="$(num "${avail:-}" 0)"
  if [ "$used" -le 0 ]; then result disk_growth OK "disk kullanimi okunamadi, buyume hizi hesaplanmadi" 2; return; fi
  out="$(awk -v now="$NOW" -v used="$used" -v avail="$avail" '
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $1 + 0 <= now + 0 { n++; e[n] = $1 + 0; u[n] = $2 + 0 }
    END {
      r1 = "NA"; r7 = "NA"; eff = "NA"; days = -1
      for (i = n; i >= 1; i--) if (now - e[i] >= 72000) { r1 = (used - u[i]) / ((now - e[i]) / 86400); break }
      for (i = 1; i <= n; i++) if (now - e[i] <= 648000) { if (now - e[i] >= 72000) r7 = (used - u[i]) / ((now - e[i]) / 86400); break }
      if (r1 != "NA") { eff = r1; if (r7 != "NA" && r7 < r1) eff = r7; if (eff > 0) days = int(avail / eff) }
      printf "%s %s %s %s\n", (r1 == "NA" ? "NA" : sprintf("%.3f", r1 / 1048576)), (r7 == "NA" ? "NA" : sprintf("%.3f", r7 / 1048576)), (eff == "NA" ? "NA" : sprintf("%.3f", eff / 1048576)), (days < 0 ? "NONE" : days)
    }' "$hist" 2>/dev/null)"
  read -r r1 r7 eff days <<<"${out:-NA NA NA NONE}"
  days="$(num "${days:-}" -1)"        # NONE/gecersiz -> -1 (buyume yok)
  if [ "${r1:-NA}" = "NA" ]; then
    msg="gunluk buyume hizi icin henuz en az 1 gunluk olcum yok"
    result disk_growth OK "$msg" 2
  else
    msg="gunluk $(printf '%+.2f' "$r1") GB/gun (7 gun ort.: ${r7} GB/gun)"
    if [ "$DISK_GROWTH_DAYS" -gt 0 ] && [ "$days" -ge 0 ] && [ "$days" -lt "$DISK_GROWTH_DAYS" ]; then
      result disk_growth WARN "disk $msg; bu hizla doluma yaklasik $days gun kaldi (esik $DISK_GROWTH_DAYS gun)" 2 24
    elif [ "$days" -ge 0 ]; then
      result disk_growth OK "disk $msg; bu hizla doluma yaklasik $days gun" 2
    else
      result disk_growth OK "disk $msg; buyume yok/azaliyor" 2
    fi
  fi
  # gunde en fazla bir ornek + durum dosyasi (yalniz normal calisma)
  if [ "$PERSIST" -eq 1 ]; then
    last_ep="$(num "$(tail -n1 "$hist" 2>/dev/null | cut -d' ' -f1)" 0)"
    if [ "$((NOW - last_ep))" -ge 82800 ]; then
      printf '%s %s\n' "$NOW" "$used" >>"$hist"
      tail -n 60 "$hist" >"$hist.tmp" && mv "$hist.tmp" "$hist"
      write_status "$OPS_STATE/disk_growth.state" "epoch=$NOW" "used_gb=$(awk -v k="$used" 'BEGIN{printf "%.2f", k/1048576}')" \
        "avail_gb=$(awk -v k="$avail" 'BEGIN{printf "%.2f", k/1048576}')" "rate_gb_day=${r1:-NA}" "rate7_gb_day=${r7:-NA}" "days_left=$days"
      log "disk ornegi: kullanilan $(awk -v k="$used" 'BEGIN{printf "%.2f", k/1048576}') GB, buyume ${r1:-NA} GB/gun (7 gun ort. ${r7:-NA}), doluma ${days} gun (-1 = buyume yok)"
    fi
  fi
}

check_memory() {
  local total avail stot sfree pct swp
  total="$(num "$(awk '/^MemTotal:/{print $2}' /proc/meminfo)" 1)"
  avail="$(num "$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)" 0)"
  stot="$(num "$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)" 0)"
  sfree="$(num "$(awk '/^SwapFree:/{print $2}' /proc/meminfo)" 0)"
  [ "$total" -gt 0 ] || total=1
  pct=$((avail * 100 / total))
  swp=0
  [ "$stot" -gt 0 ] && swp=$(((stot - sfree) * 100 / stot))
  if [ "$pct" -lt 5 ]; then result memory CRIT "kullanilabilir bellek %$pct ($((avail / 1024)) MB)" 2
  elif [ "$pct" -lt 10 ]; then result memory WARN "kullanilabilir bellek %$pct ($((avail / 1024)) MB)" 2
  elif [ "$swp" -ge 80 ]; then result memory WARN "takas (swap) kullanimi %$swp" 2
  else result memory OK "bellek bos %$pct ($((avail / 1024)) MB), takas %$swp" 2; fi
}

check_backups() {
  local newest="" newest_m=0 f m age_h res reason pre
  # saati ileri alinmis (gelecek tarihli) dosyalar "taze yedek" gibi gorunmesin: mtime <= simdi+5 dk
  for f in "$BACKUP_ROOT/daily"/kapi_[0-9]*_[0-9]*.sql.gz "$BACKUP_ROOT/daily"/kapi_[0-9]*_[0-9]*.sql.gz.enc; do
    [ -f "$f" ] || continue
    m="$(num "$(stat -c %Y "$f" 2>/dev/null)" 0)"
    [ "$m" -le "$((NOW + 300))" ] || continue
    if [ "$m" -gt "$newest_m" ]; then newest_m="$m"; newest="$f"; fi
  done
  if [ -z "$newest" ]; then
    result backup_age CRIT "zamanlanmis yedek hic yok ($BACKUP_ROOT/daily)" 1
  else
    age_h=$(((NOW - newest_m) / 3600))
    if [ "$age_h" -ge "$BACKUP_MAX_AGE_H" ]; then
      result backup_age CRIT "son yedek $age_h saat once ($(basename "$newest")); esik $BACKUP_MAX_AGE_H sa" 1
    else
      result backup_age OK "son yedek $age_h saat once ($(basename "$newest"))" 1
    fi
  fi
  res="$(status_get "$OPS_STATE/backup.status" result)"
  reason="$(status_get "$OPS_STATE/backup.status" reason)"
  pre=0; [ "$(status_get "$OPS_STATE/backup.status" notified)" = "1" ] && [ ! -e "$OPS_STATE/MAIL_FAILED" ] && pre=1
  case "$res" in
    FAIL) result backup_run CRIT "son yedek calismasi BASARISIZ: ${reason:-bilinmiyor}" 1 "$REMIND_HOURS" "$pre" ;;
    WARN) result backup_run WARN "son yedek uyarili tamamlandi: ${reason:-}" 1 ;;
    *) result backup_run OK "son yedek calismasi basarili" 1 ;;
  esac
}

check_key() {
  local stored cur
  stored="$(cat "$OPS_STATE/key.sha256" 2>/dev/null)"
  cur="$(key_sha)"
  if [ -z "$cur" ]; then
    result backup_key CRIT "sifreleme anahtari dosyasi YOK ($KEY_FILE): sifreli yedekler acilamayabilir; yeni anahtar uretilmedi" 1
  elif [ -z "$stored" ]; then
    result backup_key WARN "anahtar parmak izi kayitli degil: bash ~/ops/install_ops.sh calistirin" 2 24
  elif [ "$cur" != "$stored" ]; then
    result backup_key CRIT "sifreleme anahtari DEGISMIS: eski sifreli yedekler eski anahtari ister. Bilerek degistirdiyseniz: bash ~/ops/install_ops.sh --accept-new-key" 1
  else
    result backup_key OK "anahtar parmak izi kayitla ayni" 1
  fi
}

check_restore_test() {
  local res ep age_d reason pre
  res="$(status_get "$OPS_STATE/restore_test.status" result)"
  ep="$(num "$(status_get "$OPS_STATE/restore_test.status" epoch)" 0)"
  reason="$(status_get "$OPS_STATE/restore_test.status" reason)"
  pre=0; [ "$(status_get "$OPS_STATE/restore_test.status" notified)" = "1" ] && [ ! -e "$OPS_STATE/MAIL_FAILED" ] && pre=1
  if [ -z "$res" ]; then
    result restore_test WARN "geri yukleme testi henuz hic calistirilmadi (bash ~/ops/restore_test.sh)" 1 24
  elif [ "$res" = "FAIL" ]; then
    result restore_test CRIT "son geri yukleme testi BASARISIZ: ${reason:-bilinmiyor}" 1 "$REMIND_HOURS" "$pre"
  else
    age_d=$(((NOW - ep) / 86400))
    if [ "$age_d" -gt "$RESTORE_MAX_AGE_D" ]; then
      result restore_test WARN "son basarili geri yukleme testi $age_d gun once (esik $RESTORE_MAX_AGE_D)" 1 24
    else
      result restore_test OK "son geri yukleme testi PASS, $age_d gun once" 1
    fi
  fi
}

check_offsite() {
  local res ep age_h reason pre
  res="$(status_get "$OPS_STATE/offsite.status" result)"
  ep="$(num "$(status_get "$OPS_STATE/offsite.status" epoch)" 0)"
  reason="$(status_get "$OPS_STATE/offsite.status" reason)"
  pre=0; [ "$(status_get "$OPS_STATE/offsite.status" notified)" = "1" ] && [ ! -e "$OPS_STATE/MAIL_FAILED" ] && pre=1
  if [ ! -r "$OFFSITE_CONF" ] || [ -z "$res" ] || [ "$res" = "UNCONFIGURED" ]; then
    result offsite WARN "dis kopya yapilandirilmadi: yedekler yalniz bu sunucuda (~/.config/kapi-offsite.env yok)" 2 24
  elif [ "$res" = "FAIL" ]; then
    result offsite CRIT "dis kopya gonderimi BASARISIZ: ${reason:-bilinmiyor}" 1 "$REMIND_HOURS" "$pre"
  else
    age_h=$(((NOW - ep) / 3600))
    if [ "$age_h" -ge "$BACKUP_MAX_AGE_H" ]; then
      result offsite WARN "dis kopya $age_h saattir calismadi" 1
    else
      result offsite OK "dis kopya $age_h saat once calisti" 1
    fi
  fi
}

check_tls() {
  local d name host port sni desc warn_days spec
  local -a specs=("tls_origin|127.0.0.1|443|$TLS_API_HOST|nginx/Let's Encrypt (origin)"
                  "tls_edge|$TLS_API_HOST|443|$TLS_API_HOST|genel (Cloudflare kenar)"
                  "tls_mqtt|${MQTT_LOCAL%%:*}|${MQTT_LOCAL##*:}|${MQTT_PUBLIC%%:*}|MQTT (8883)")
  if [ "$CHECK_EV_TLS" = "1" ]; then
    specs+=("tls_ev_web|127.0.0.1|443|$TLS_EV_HOST|ev otomasyonu web/API (443)"
            "tls_ev_mqtt|127.0.0.1|$TLS_EV_MQTT_PORT|$TLS_EV_HOST|ev otomasyonu MQTT/EMQX ($TLS_EV_MQTT_PORT)")
  fi
  for spec in "${specs[@]}"; do
    IFS='|' read -r name host port sni desc <<<"$spec"
    d="$(cert_days "$host" "$port" "$sni")"
    warn_days="$TLS_WARN_DAYS"
    # MQTT sertifikalari icin daha erken uyar (cihazlar elle mudahale olmadan kopar)
    case "$name" in tls_mqtt|tls_ev_mqtt) warn_days="$TLS_WARN_DAYS_MQTT" ;; esac
    if [ "$d" = "ERR" ]; then
      result "$name" WARN "$desc sertifikasi okunamadi" 2
    elif [ "$d" -lt "$TLS_CRIT_DAYS" ]; then
      result "$name" CRIT "$desc sertifikasi $d gun sonra bitiyor" 1
    elif [ "$d" -lt "$warn_days" ]; then
      result "$name" WARN "$desc sertifikasi $d gun sonra bitiyor (esik $warn_days gun)" 1 24
    else
      result "$name" OK "$desc sertifikasi $d gun gecerli" 1
    fi
  done
}

check_mqtt() {
  local lh="${MQTT_LOCAL%%:*}" lp="${MQTT_LOCAL##*:}" ph="${MQTT_PUBLIC%%:*}" pp="${MQTT_PUBLIC##*:}" ip hint
  if tcp_open "$lh" "$lp"; then result mqtt_local OK "MQTT ${MQTT_LOCAL} acik" 2
  else result mqtt_local CRIT "MQTT ${MQTT_LOCAL} baglanti kabul etmiyor (broker durmus olabilir)" 2; fi
  if [ "$CHECK_MQTT_PUBLIC" = "1" ]; then
    if tcp_open "$ph" "$pp"; then
      result mqtt_public OK "MQTT genel adres ${MQTT_PUBLIC} acik" 2 24
    else
      ip="$(dig +short +time=3 +tries=1 "$ph" 2>/dev/null | head -n1)"
      hint=""
      if [ -n "$ip" ] && [ -n "$SERVER_PUBLIC_IP" ] && [ "$ip" != "$SERVER_PUBLIC_IP" ]; then
        hint=" -- DNS ${ip} sunucu IP'si (${SERVER_PUBLIC_IP}) degil: DNS proxy acik olabilir (MQTT icin 'DNS only' gerekir)"
      fi
      result mqtt_public WARN "MQTT genel adres ${MQTT_PUBLIC} disaridan ulasilamiyor${hint}" 2 24
    fi
  fi
}

run_checks() {
  check_api
  check_api_public
  check_pm2
  check_postgres
  check_disk
  check_disk_growth
  check_memory
  check_backups
  check_key
  check_restore_test
  check_offsite
  check_tls
  check_mqtt
}

# ---- haftalik kapasite raporu (pazartesi) --------------------------------------------------
# SIR ICERMEZ: yalniz tablo adi, boyut, satir sayisi tahmini ve dizin boyutlari. Tum sorgular salt okunur (dpsql_ro).
fmt_kb() { # KB -> okunur boyut | "yok"
  local k; k="$(num "${1:-}" "")"
  if [ -n "$k" ]; then human_bytes $((k * 1024)); else echo "yok/okunamadi"; fi
}
dir_kb() { # dizin -> KB | "" (yok/okunamadi)
  [ -d "$1" ] || return 0
  nolock timeout 60 du -sk -- "$1" 2>/dev/null | cut -f1
}

WR_BODY=""; WR_SUMMARY=""
weekly_report_build() { # $1 = 1: tablo boyutlarini "onceki hafta" tabani olarak kaydet. -> WR_BODY, WR_SUMMARY
  local save="${1:-0}" prevf="$OPS_STATE/weekly_tables.prev" curf="$OPS_STATE/weekly_tables.cur"
  local rows dbsz dbtxt tbl top_line k d sched="" tot_k=0 bk_all docs pm2l pm2dir df_line gstate g1 g7 gd
  rows="$(DOCKER_TIMEOUT=45 dpsql_ro -d "$DB_NAME" -At -F '|' -c "select c.relname, pg_total_relation_size(c.oid), coalesce(s.n_live_tup, 0) from pg_class c join pg_namespace n on n.oid = c.relnamespace left join pg_stat_user_tables s on s.relid = c.oid where n.nspname = 'public' and c.relkind = 'r' order by 2 desc, 1 limit 10" 2>/dev/null </dev/null \
    | awk -F'|' 'NF == 3 && $1 ~ /^[A-Za-z0-9_]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/')"
  dbsz="$(num "$(DOCKER_TIMEOUT=45 dpsql_ro -d "$DB_NAME" -At -c 'select pg_database_size(current_database())' 2>/dev/null </dev/null | head -n1)" "")"
  if [ -n "$rows" ]; then
    tbl="$(printf '%s\n' "$rows" | awk -F'|' -v pf="$prevf" '
      function hb(b,   i, u) { split("B KB MB GB TB", u, " "); i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ } return sprintf("%.1f %s", b, u[i]) }
      BEGIN { while ((getline l < pf) > 0) { split(l, a, "|"); if (a[2] ~ /^[0-9]+$/) pb[a[1]] = a[2] } }
      {
        if ($1 in pb) { dl = $2 - pb[$1]; ch = (dl < 0 ? "-" : "+") hb(dl < 0 ? -dl : dl) } else ch = "yeni / ilk olcum"
        printf "  %2d. %-36s %10s  ~%d satir  (onceki haftaya gore: %s)\n", ++k, $1, hb($2), $3, ch
      }')"
    top_line="$(printf '%s\n' "$rows" | head -n1 | awk -F'|' '{printf "%s=%d bayt", $1, $2}')"
  else
    tbl="  (tablo boyutlari okunamadi: veritabani yanit vermedi)"
    top_line="tablo boyutu okunamadi"
  fi
  while read -r k d; do
    [ -n "${d:-}" ] || continue
    sched="${sched:+$sched, }$d $(fmt_kb "$k")"; tot_k=$((tot_k + $(num "$k" 0)))
  done < <(cd "$BACKUP_ROOT" 2>/dev/null && nolock timeout 60 du -sk daily weekly monthly config offsite 2>/dev/null)
  bk_all="$(dir_kb "$(dirname "$BACKUP_ROOT")")"
  docs="$(dir_kb "$(documents_root)")"
  pm2dir="${PM2_LOG_DIR:-$HOME/.pm2/logs}"; pm2l="$(dir_kb "$pm2dir")"
  df_line="$(df -Ph / | awk 'NR==2{printf "%s kullanilan, %s bos, doluluk %s", $3, $4, $5}')"
  g1="$(status_get "$OPS_STATE/disk_growth.state" rate_gb_day 2>/dev/null)"
  g7="$(status_get "$OPS_STATE/disk_growth.state" rate7_gb_day 2>/dev/null)"
  gd="$(status_get "$OPS_STATE/disk_growth.state" days_left 2>/dev/null)"
  gstate="son gunluk ornek: buyume ${g1:-?} GB/gun (7 gun ort.: ${g7:-?}); doluma kalan gun: ${gd:-?} (-1 = buyume yok)"
  if [ -n "$dbsz" ]; then dbtxt="$(fmt_kb $((dbsz / 1024)))"; else dbtxt="okunamadi"; fi
  WR_BODY="Haftalik kapasite raporu (healthcheck.sh)
Sunucu : $(hostname) ($SERVER_PUBLIC_IP)
Zaman  : $(stamp_local) (Europe/Istanbul)

DISK (/)
  $df_line
  $gstate

VERITABANI toplam boyut: $dbtxt
EN BUYUK 10 TABLO (yigin + indeks + TOAST; satir sayisi istatistik tahminidir)
$tbl

DIZIN BOYUTLARI
  yedekler (~/backups, dagitim yedekleri dahil): $(fmt_kb "$bk_all")
  zamanlanmis yedek (toplam $(fmt_kb "$tot_k"); sert bagli kopyalar yalniz bir kez sayilir): ${sched:-okunamadi}
  belge deposu: $(fmt_kb "$docs")
  PM2 gunlukleri (~/.pm2/logs): $(fmt_kb "$pm2l")

Ayrinti: ~/ops/logs/weekly_report.log   |   bu rapor: bash ~/ops/healthcheck.sh --weekly-report --dry-run"
  WR_SUMMARY="DB $dbtxt, en buyuk tablo $top_line, yedekler $(fmt_kb "$bk_all") (zamanlanmis $(fmt_kb "$tot_k")), belgeler $(fmt_kb "$docs"), PM2 gunlukleri $(fmt_kb "$pm2l"), disk: $df_line"
  if [ "$save" = "1" ] && [ -n "$rows" ]; then
    printf '%s\n' "$rows" | awk -F'|' '{print $1 "|" $2}' >"$curf" && mv -- "$curf" "$prevf"
  fi
}

weekly_report_maybe() { # alt kabukta cagrilir
  local today dow hour last
  today="$(TZ=$LOCAL_TZ date +%F)"; dow="$(TZ=$LOCAL_TZ date +%u)"; hour="$(TZ=$LOCAL_TZ date +%H)"
  last="$(cat "$OPS_STATE/weekly_report.last" 2>/dev/null)"
  if [ "$WEEKLY_FORCE" -ne 1 ]; then
    [ "$dow" = "1" ] || return 0
    [ "$((10#$hour))" -ge "$WEEKLY_REPORT_HOUR" ] || return 0
    [ "$last" != "$today" ] || return 0
  fi
  # once isaretle: rapor/posta hata verse bile ayni gun tekrar denenmez (5 dakikada bir posta yagmuru olmasin)
  printf '%s\n' "$today" >"$OPS_STATE/weekly_report.last"
  weekly_report_build 1
  log "haftalik rapor: $WR_SUMMARY"
  { printf '=== %s ===\n' "$(stamp_local)"; printf '%s\n' "$WR_BODY"; } >>"$OPS_LOGS/weekly_report.log" 2>/dev/null
  trim_log "$OPS_LOGS/weekly_report.log" 262144 1500
  send_mail "[KAPI-OPS] Haftalik kapasite raporu" "$WR_BODY" || true
}

# ---- degerlendirme (durum makinesi) ----------------------------------------------------
ITEMS_NEW=(); ITEMS_CHG=(); ITEMS_REM=(); ITEMS_REC=(); ITEMS_EVT=(); APPLY=()

evaluate() {
  local n lvl msg prev since fails alerted last oks need rem last_ev
  for n in "${ORDER[@]}"; do
    lvl="${R_LEVEL[$n]}"; msg="${R_MSG[$n]}"
    prev="${S_LEVEL[$n]:-OK}"; since="${S_SINCE[$n]:-$NOW}"; fails="${S_FAILS[$n]:-0}"
    alerted="${S_ALERTED[$n]:-0}"; last="${S_LAST[$n]:-0}"; oks="${S_OKS[$n]:-0}"
    need="${R_NEED[$n]}"; rem=$((${R_REMIND[$n]} * 3600))
    case "$lvl" in
      OK)
        if [ "$alerted" = "1" ]; then
          oks=$((oks + 1))
          if [ "$oks" -ge 2 ]; then      # histerezis: duzeldi postasi art arda 2 basarili calismadan sonra
            ITEMS_REC+=("$n|$msg|$(fmt_dur $((NOW - since)))")
            APPLY+=("$n|recover")
          fi
          N_SINCE[$n]="$since"
        else
          oks=0
          N_SINCE[$n]="$NOW"
        fi
        N_LEVEL[$n]=OK; N_FAILS[$n]=0; N_ALERTED[$n]="$alerted"; N_LAST[$n]="$last"; N_OKS[$n]="$oks"
        ;;
      EVENT)
        last_ev="$last"
        N_LEVEL[$n]=OK; N_FAILS[$n]=0; N_ALERTED[$n]="$alerted"; N_LAST[$n]="$last_ev"; N_SINCE[$n]="$NOW"; N_OKS[$n]=0
        if [ $((NOW - last_ev)) -ge "$EVENT_MIN_GAP" ]; then
          ITEMS_EVT+=("$n|$msg"); APPLY+=("$n|event")
        elif [ "$PERSIST" -eq 1 ]; then
          log "olay bastirildi (son olaydan $(fmt_dur $((NOW - last_ev))) sonra, en az $(fmt_dur "$EVENT_MIN_GAP") gerekir): $n"
        fi
        ;;
      *)
        [ "$prev" = "OK" ] && [ "$alerted" != "1" ] && since="$NOW"
        fails=$((fails + 1))
        N_LEVEL[$n]="$lvl"; N_FAILS[$n]="$fails"; N_SINCE[$n]="$since"; N_ALERTED[$n]="$alerted"; N_LAST[$n]="$last"; N_OKS[$n]=0
        if [ "$fails" -ge "$need" ]; then
          if [ "$alerted" != "1" ]; then
            if [ "${R_PRE[$n]}" = "1" ]; then
              N_ALERTED[$n]=1; N_LAST[$n]="$NOW"      # betik kendisi zaten e-posta gonderdi
            else
              ITEMS_NEW+=("$lvl|$n|$msg"); APPLY+=("$n|alert")
            fi
          elif [ "$lvl" != "$prev" ] && [ "$prev" != "OK" ]; then
            ITEMS_CHG+=("$lvl|$n|$msg"); APPLY+=("$n|touch")
          elif [ $((NOW - last)) -ge "$rem" ]; then
            ITEMS_REM+=("$lvl|$n|$msg (sure: $(fmt_dur $((NOW - since))))"); APPLY+=("$n|touch")
          fi
        fi
        ;;
    esac
  done
}

apply_sent() {
  local a n act
  for a in "${APPLY[@]}"; do
    n="${a%%|*}"; act="${a##*|}"
    case "$act" in
      alert|touch) N_ALERTED[$n]=1; N_LAST[$n]="$NOW" ;;
      event) N_LAST[$n]="$NOW" ;;
      recover) N_ALERTED[$n]=0; N_LAST[$n]=0; N_SINCE[$n]="$NOW"; N_OKS[$n]=0 ;;
    esac
  done
}

save_state() {
  local tmp="$STATE_FILE.tmp.$$" n
  {
    for n in "${ORDER[@]}"; do
      printf '%s|%s|%s|%s|%s|%s|%s\n' "$n" "${N_LEVEL[$n]:-OK}" "${N_SINCE[$n]:-$NOW}" "${N_FAILS[$n]:-0}" "${N_ALERTED[$n]:-0}" "${N_LAST[$n]:-0}" "${N_OKS[$n]:-0}"
    done
  } >"$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -- "$tmp" "$STATE_FILE" || { rm -f -- "$tmp"; return 1; }
}

build_mail() { # -> SUBJECT, BODY
  local parts=() it lv n m dur sep=" "
  names() { local out="" it; for it in "$@"; do out="${out:+$out, }$(cut -d'|' -f2 <<<"$it")"; done; echo "$out"; }
  firsts() { local out="" it; for it in "$@"; do out="${out:+$out, }${it%%|*}"; done; echo "$out"; }
  [ "${#ITEMS_NEW[@]}" -gt 0 ] && parts+=("SORUN: $(names "${ITEMS_NEW[@]}")")
  [ "${#ITEMS_CHG[@]}" -gt 0 ] && parts+=("DEGISTI: $(names "${ITEMS_CHG[@]}")")
  [ "${#ITEMS_REC[@]}" -gt 0 ] && parts+=("DUZELDI: $(firsts "${ITEMS_REC[@]}")")
  [ "${#ITEMS_EVT[@]}" -gt 0 ] && parts+=("OLAY: $(firsts "${ITEMS_EVT[@]}")")
  [ "${#ITEMS_REM[@]}" -gt 0 ] && parts+=("HATIRLATMA: $(names "${ITEMS_REM[@]}")")
  SUBJECT="[KAPI-OPS]"
  for it in "${parts[@]}"; do SUBJECT="$SUBJECT$sep$it"; sep=" / "; done
  {
    echo "Sunucu : $(hostname) ($SERVER_PUBLIC_IP)"
    echo "Zaman  : $(stamp_local) (Europe/Istanbul)"
    echo
    if [ "${#ITEMS_NEW[@]}" -gt 0 ]; then
      echo "YENI SORUNLAR"
      for it in "${ITEMS_NEW[@]}"; do IFS='|' read -r lv n m <<<"$it"; echo "  [$lv] $n: $m"; done
      echo
    fi
    if [ "${#ITEMS_CHG[@]}" -gt 0 ]; then
      echo "SEVIYESI DEGISENLER"
      for it in "${ITEMS_CHG[@]}"; do IFS='|' read -r lv n m <<<"$it"; echo "  [$lv] $n: $m"; done
      echo
    fi
    if [ "${#ITEMS_EVT[@]}" -gt 0 ]; then
      echo "OLAYLAR (tek seferlik)"
      for it in "${ITEMS_EVT[@]}"; do IFS='|' read -r n m <<<"$it"; echo "  $n: $m"; done
      echo
    fi
    if [ "${#ITEMS_REM[@]}" -gt 0 ]; then
      echo "HATIRLATMA (hala devam ediyor)"
      for it in "${ITEMS_REM[@]}"; do IFS='|' read -r lv n m <<<"$it"; echo "  [$lv] $n: $m"; done
      echo
    fi
    if [ "${#ITEMS_REC[@]}" -gt 0 ]; then
      echo "DUZELDI"
      for it in "${ITEMS_REC[@]}"; do IFS='|' read -r n m dur <<<"$it"; echo "  $n: $m (sorun suresi: $dur)"; done
      echo
    fi
    echo "Su an acik tum sorunlar:"
    local any=0
    for n in "${ORDER[@]}"; do
      case "${R_LEVEL[$n]}" in WARN|CRIT) echo "  [${R_LEVEL[$n]}] $n: ${R_MSG[$n]}"; any=1 ;; esac
    done
    [ "$any" -eq 0 ] && echo "  (yok)"
    echo
    echo "Not: Bu e-posta sunucunun icinden gonderilir. Sunucu tamamen cokerse gelmez; disaridan izleme icin GitHub Actions"
    echo "uptime.yml / UptimeRobot / HEARTBEAT_URL kullanin (docs/OPERASYON_YEDEK_IZLEME.md)."
    echo "Sunucuda ayrintilar: bash ~/ops/healthcheck.sh --dry-run -v   |   gunluk: ~/ops/logs/healthcheck.log"
  } >"$OPS_STATE/last_mail_body.txt"
  BODY="$(cat "$OPS_STATE/last_mail_body.txt")"
}

print_table() {
  local n
  printf '%-14s %-6s %s\n' "KONTROL" "SEVIYE" "AYRINTI"
  for n in "${ORDER[@]}"; do printf '%-14s %-6s %s\n' "$n" "${R_LEVEL[$n]}" "${R_MSG[$n]}"; done
}

# ---- ana akis ------------------------------------------------------------------------------
run_checks

if [ "$TEST" -eq 1 ]; then
  body="Bu bir TEST uyarisidir (healthcheck.sh --test-alert).
Sunucu: $(hostname)
Zaman : $(stamp_local) (Europe/Istanbul)

Mevcut kontrol sonuclari:
$(print_table)"
  if send_mail "[KAPI-OPS] TEST uyarisi" "$body"; then
    echo "TEST_ALERT_SENT"
    exit 0
  fi
  echo "TEST_ALERT_FAILED (ayrintilar: ~/ops/logs/healthcheck.log, ~/ops/state/ALERT_UNSENT)"
  exit 1
fi

evaluate
[ "$VERBOSE" -eq 1 ] && print_table

total_items=$((${#ITEMS_NEW[@]} + ${#ITEMS_CHG[@]} + ${#ITEMS_REM[@]} + ${#ITEMS_REC[@]} + ${#ITEMS_EVT[@]}))
bad=0; for n in "${ORDER[@]}"; do case "${R_LEVEL[$n]}" in WARN|CRIT) bad=$((bad + 1)) ;; esac; done

if [ "$DRY" -eq 1 ]; then
  echo
  echo "KURU CALISMA: gonderilecek bildirim ogesi: $total_items (yeni=${#ITEMS_NEW[@]} degisen=${#ITEMS_CHG[@]} hatirlatma=${#ITEMS_REM[@]} duzelen=${#ITEMS_REC[@]} olay=${#ITEMS_EVT[@]}); e-posta gonderilmedi, durum degismedi."
  [ "$total_items" -gt 0 ] && { build_mail; echo "--- e-posta onizleme ---"; echo "Konu: $SUBJECT"; echo "$BODY"; }
  if [ "$WEEKLY_FORCE" -eq 1 ]; then
    weekly_report_build 0
    echo; echo "--- haftalik rapor onizleme (gonderilmedi, taban kaydedilmedi) ---"; echo "$WR_BODY"
  fi
  exit 0
fi

if [ "$total_items" -gt 0 ]; then
  build_mail
  log "bildirim: $SUBJECT"
  skip=0
  if [ -r "$OPS_STATE/MAIL_FAILED" ]; then
    lastfail="$(num "$(cat "$OPS_STATE/MAIL_FAILED" 2>/dev/null)" 0)"
    if [ "$((NOW - lastfail))" -lt "$MAIL_RETRY_SECS" ]; then skip=1; log "son e-posta hatasi yakin zamanda ($((NOW - lastfail)) sn once): yeniden deneme ertelendi; uyari ALERT_UNSENT/alerts.log'ta"; fi
  fi
  if [ "$skip" -eq 0 ] && send_mail "$SUBJECT" "$BODY"; then
    apply_sent
  elif [ "$skip" -eq 1 ]; then
    printf '%s | (e-posta ertelendi) %s\n%s\n---\n' "$(stamp_local)" "$SUBJECT" "$BODY" >>"$OPS_LOGS/alerts.log"
  fi
fi

if ! save_state; then
  log "HATA: durum dosyasi yazilamadi ($STATE_FILE); disk dolu olabilir"
  RUN_OK=0
fi
printf 'epoch=%s\nnot_ok=%s\n' "$NOW" "$bad" >"$OPS_STATE/healthcheck.last" 2>/dev/null || RUN_OK=0
if [ "$bad" -gt 0 ]; then
  summary=""
  for n in "${ORDER[@]}"; do case "${R_LEVEL[$n]}" in WARN|CRIT) summary="$summary ${R_LEVEL[$n]}:$n" ;; esac; done
  # gunluk sismesin: ozet degistiyse veya son kayittan 1 saat gectiyse yaz
  prev_line="$(cat "$OPS_STATE/last_summary" 2>/dev/null)"
  prev_ep="$(num "${prev_line%%|*}" 0)"; prev_sum="${prev_line#*|}"
  if [ "$summary" != "$prev_sum" ] || [ "$((NOW - prev_ep))" -ge 3600 ]; then
    log "acik sorun:$summary"
    printf '%s|%s\n' "$NOW" "$summary" >"$OPS_STATE/last_summary"
  fi
else
  rm -f "$OPS_STATE/last_summary"
fi
trim_log
for f in "$OPS_LOGS"/cron_*.out; do [ -e "$f" ] && trim_log "$f" 262144 500; done

# Haftalik rapor (pazartesi veya --weekly-report): alt kabukta; hata durumunda saglik kontrolunun sonucunu etkilemez
( weekly_report_maybe ) || log "UYARI: haftalik rapor uretilemedi (ayrintilar icin: bash ~/ops/healthcheck.sh --weekly-report --dry-run)"

# Olu adam anahtari: yalniz BASARIYLA tamamlanan calismalarda ping (adres gunluge yazilmaz)
if [ -n "$HEARTBEAT_URL" ] && [ "$RUN_OK" -eq 1 ]; then
  if [[ "$HEARTBEAT_URL" =~ ^https?://[^[:space:]]+$ ]]; then
    nolock curl -fsS -m 10 -o /dev/null "$HEARTBEAT_URL" 2>/dev/null || log "UYARI: heartbeat gonderilemedi"
  else
    log "UYARI: HEARTBEAT_URL gecersiz (http:// veya https:// ile baslamali)"
  fi
fi
exit 0
