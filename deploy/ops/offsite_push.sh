#!/bin/bash
# Dis kopya: YALNIZCA sifreli (.enc, OpenSSL "Salted__" basligi dogrulanir) yedekleri sunucu disina gonderir.
#
# Yapilandirma dosyasi YOKSA sessizce atlanir (durum: UNCONFIGURED -> healthcheck "dis kopya yapilandirilmadi" uyarisi verir).
# Yapilandirma: ~/.config/kapi-offsite.env  (ornek: deploy/ops/kapi-offsite.env.example)
#   OFFSITE_METHOD=rsync|sftp|rclone        (varsayilan rsync)
#   OFFSITE_TARGET=kullanici@host:/yol      (rsync/sftp)  |  uzakuc:yol  (rclone)  |  /yerel/baglanmis/dizin (rsync)
#   OFFSITE_SSH_PORT=22
#   OFFSITE_SSH_KEY=/home/salihceylan/.ssh/kapi_offsite   (parolasiz, yalniz bu is icin anahtar)
#   OFFSITE_PRUNE_DAYS=210                  (varsayilan 210; 0 = uzak tarafta hic silme)
#
# Saklama: dis kopyalar EN FAZLA OFFSITE_PRUNE_DAYS (varsayilan 210 gun) tutulur; gonderim basarili olduktan sonra uzak taraftaki
# bu yastan eski gunluk-veritabani ve yapilandirma dosyalari silinir (rsync: yerel dizin veya ssh uzerinden; rclone: `rclone delete
# --min-age`). sftp-only hedeflerde uzak budama YAPILAMAZ: eski dosyalari elle silmeniz gerekir. Firmware arsivleri (kapi_firmware_*)
# budanmaz (degismedikce tek yedek kopyadir). Belge deposu (kapi_documents_*) ve is takibi fotograf (kapi_work_attachments_*) arsivleri her turun
# EN YENISI HARIC ayni yastan (210 gun) sonra silinir: en yeni arsiv yasi ne olursa olsun korunur (kume degismediyse tek geri yukleme kopyasidir).
# Fotograf arsivleri (her biri 3000 MB'a kadar) ayrica ADETLE sinirlidir: uzak tarafta en yeni KEEP_WORK_ATTACHMENTS (kapi-ops.env, varsayilan 5,
# en az 1) disindakiler YASINA BAKILMADAN silinir (rsync yerel / ssh ve rclone dallarinda; sftp-only hedefte elle). Belge arsivi tutmasi DEGISMEDI.
# OFFSITE_PRUNE_DAYS=0 ise uzak tarafta HIC silme yapilmaz (yas ve adet kurali birlikte kapanir).
#
# Not: offsite/ icindeki dosyalar daily/weekly/monthly/config ile SERT BAG paylasir (backup_db.sh; diskte tek kopya). Bu betik yalniz
# OKUR (rsync/sftp/rclone kaynagi); dosyalari yerinde degistirmez, yerel tutma budamasi backup_db.sh'tadir (KEEP_OFFSITE, gonderilmemisi silmez).
#
# Kullanim: bash ~/ops/offsite_push.sh [--all] [--check]
#   --all    daha once gonderilmis olanlari da yeniden gonder
#   --check  baglanti/yetki denemesi (dosya gondermez; rsync icin kuru calistirma)
# Cikis kodu: 0 basarili/atlandi, 1 basarisiz, 75 kilit.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG=offsite
# shellcheck source=common.sh
. "$HERE/common.sh"
reexec_low_priority "$@"

STATUS_FILE="$OPS_STATE/offsite.status"
PUSHED_LIST="$OPS_STATE/offsite.pushed"
OFFSITE_DIR="$BACKUP_ROOT/offsite"
ALL=0; CHECK=0
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    --check) CHECK=1 ;;
    *) echo "bilinmeyen secenek: $a"; exit 64 ;;
  esac
done

if [ ! -r "$OFFSITE_CONF" ]; then
  write_status "$STATUS_FILE" "result=UNCONFIGURED" "epoch=$(now_epoch)"
  log "dis kopya yapilandirilmadi ($OFFSITE_CONF yok): atlandi"
  exit 0
fi

acquire_lock heavy 900
load_env_file "$OFFSITE_CONF"
METHOD="${OFFSITE_METHOD:-rsync}"
TARGET="${OFFSITE_TARGET:-}"
PORT="${OFFSITE_SSH_PORT:-22}"
SSHKEY="${OFFSITE_SSH_KEY:-}"
PRUNE_DAYS="$(num "${OFFSITE_PRUNE_DAYS:-210}" 210)"
# fotograf arsivleri uzak tarafta en yeni N (backup_db.sh ile ayni ayar ve varsayilan; gecersiz / < 1 ise 5)
WA_KEEP="$(num "${KEEP_WORK_ATTACHMENTS:-5}" 5)"
[ "$WA_KEEP" -ge 1 ] || WA_KEEP=5
WORKF=""
trap '[ -n "$WORKF" ] && rm -f -- "$WORKF"' EXIT

fail() {
  log "HATA: $1"
  write_status "$STATUS_FILE" "result=FAIL" "epoch=$(now_epoch)" "method=$METHOD" "reason=$1" "notified=1"
  send_mail "[KAPI-OPS] SORUN: dis kopya gonderimi basarisiz" "Sifreli yedeklerin dis kopyaya gonderimi basarisiz.
Zaman : $(stamp_local) (Europe/Istanbul)
Yontem: $METHOD
Neden : $1
Gunluk: ~/ops/logs/offsite.log
Yerel yedekler etkilenmedi. Dis kopya yapilandirmasini ve hedefin erisilebilirligini kontrol edin: bash ~/ops/offsite_push.sh --check" || true
  exit 1
}

if [ -z "$TARGET" ]; then
  write_status "$STATUS_FILE" "result=UNCONFIGURED" "epoch=$(now_epoch)"
  log "OFFSITE_TARGET bos: atlandi"
  exit 0
fi
case "$METHOD" in rsync|sftp|rclone) ;; *) fail "gecersiz OFFSITE_METHOD: $METHOD" ;; esac
[[ "$PORT" =~ ^[0-9]+$ ]] || fail "gecersiz OFFSITE_SSH_PORT"

SSH_OPTS=(-p "$PORT" -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
[ -n "$SSHKEY" ] && SSH_OPTS+=(-i "$SSHKEY" -o IdentitiesOnly=yes)

# Gonderilecek dosyalar: yalniz offsite/ icindeki sifreli dosyalar; basligi dogrula.
mapfile -t CANDIDATES < <(ls -1 "$OFFSITE_DIR" 2>/dev/null | grep -E '^kapi_.*\.enc$' | sort)
TO_SEND=()
for f in "${CANDIDATES[@]}"; do
  p="$OFFSITE_DIR/$f"
  if [ "$(head -c 8 "$p" 2>/dev/null)" != "Salted__" ]; then
    log "UYARI: $f sifreli degil gorunuyor; GONDERILMEDI"
    continue
  fi
  if [ "$ALL" -eq 0 ] && grep -qxF "$f" "$PUSHED_LIST" 2>/dev/null; then continue; fi
  TO_SEND+=("$f")
done

if [ "$CHECK" -eq 1 ] && [ "${#TO_SEND[@]}" -eq 0 ]; then
  # baglanti denemesi icin gonderilmis olsa bile mevcut sifreli dosyalardan birini kullan
  [ "${#CANDIDATES[@]}" -gt 0 ] || fail "offsite/ dizininde sifreli dosya yok (once backup_db.sh calistirin)"
  TO_SEND=("${CANDIDATES[0]}")
fi
if [ "$CHECK" -eq 0 ] && [ "${#TO_SEND[@]}" -eq 0 ]; then
  log "gonderilecek yeni sifreli dosya yok"
  write_status "$STATUS_FILE" "result=OK" "epoch=$(now_epoch)" "method=$METHOD" "pushed=0" "note=yeni_dosya_yok"
  exit 0
fi

# Uzak budama icin dosya adi kaliplari (firmware HARIC)
PRUNE_FIND_ARGS=(-maxdepth 1 -type f '(' -name 'kapi_[0-9]*.sql.gz.enc' -o -name 'kapi_config_*.tgz.enc' ')' -mtime "+$PRUNE_DAYS")

prune_remote() {
  [ "$PRUNE_DAYS" -gt 0 ] || { log "uzak budama kapali (OFFSITE_PRUNE_DAYS=0)"; return 0; }
  local hostpart rpath out
  case "$METHOD" in
    rsync)
      if [[ "$TARGET" == /* ]]; then
        # yerel/baglanmis dizin: kok dizini ve cok kisa yollari reddet
        [[ "$TARGET" =~ ^/[^/]+/[^/]+ ]] || { log "UYARI: hedef yol cok kisa, budama atlandi"; return 0; }
        find "$TARGET" "${PRUNE_FIND_ARGS[@]}" -print -delete 2>/dev/null | sed 's#.*/#uzak budama: silindi #' | while read -r l; do log "$l"; done
      else
        hostpart="${TARGET%%:*}"; rpath="${TARGET#*:}"
        [[ "$rpath" =~ ^[A-Za-z0-9_./~-]+$ ]] || { log "UYARI: uzak yol budama icin uygun degil, budama atlandi"; return 0; }
        out="$(nolock timeout 120 ssh "${SSH_OPTS[@]}" "$hostpart" "find '$rpath' -maxdepth 1 -type f \\( -name 'kapi_[0-9]*.sql.gz.enc' -o -name 'kapi_config_*.tgz.enc' \\) -mtime +$PRUNE_DAYS -print -delete" 2>&1)" \
          && { [ -z "$out" ] || printf '%s\n' "$out" | sed 's#.*/#uzak budama: silindi #' | while read -r l; do log "$l"; done; } \
          || log "UYARI: uzak budama basarisiz (gonderim etkilenmedi): $(tail -n1 <<<"$out" | cut -c1-120)"
      fi
      ;;
    rclone)
      out="$(nolock timeout 300 rclone delete "$TARGET" --include 'kapi_[0-9]*.sql.gz.enc' --include 'kapi_config_*.tgz.enc' --min-age "${PRUNE_DAYS}d" -v 2>&1)" \
        && { printf '%s\n' "$out" | grep -i 'deleted' | sed 's/^.*: /uzak budama: silindi /' | while read -r l; do log "$l"; done; } \
        || log "UYARI: uzak budama basarisiz (gonderim etkilenmedi): $(tail -n1 <<<"$out" | cut -c1-120)"
      ;;
    sftp)
      log "bilgi: sftp ile uzak budama yapilamaz; $PRUNE_DAYS gunden eski dosyalari hedefte elle silin"
      ;;
  esac
}

# Belge / fotograf arsivleri (<onek>_*.tgz.enc): EN YENISI HARIC, PRUNE_DAYS'ten eskiler silinir. En yeni arsiv asla silinmez. <adet> > 0 ise ayrica
# en yeni <adet> disindakiler YASINA BAKILMADAN silinir (fotograf arsivleri; belge arsivlerinde adet 0 = yalniz yas kurali, eski davranis).
# prune_newest_kept_remote <onek> <etiket> [adet]; onek / adet yalniz bu betikteki sabitlerdir (kapi_documents | kapi_work_attachments), disaridan gelmez.
prune_newest_kept_remote() {
  [ "$PRUNE_DAYS" -gt 0 ] || return 0
  local prefix="$1" label="$2" keep="${3:-0}" hostpart rpath out script cutoff
  [[ "$prefix" =~ ^kapi_[a-z_]+$ ]] || return 0
  [[ "$keep" =~ ^[0-9]+$ ]] || keep=0
  # siralama: degisim zamani (yeniden eskiye); 1. dosya (en yeni) hep korunur
  script="cd \"\$1\" 2>/dev/null || exit 0
i=0
ls -1t ${prefix}_*.tgz.enc 2>/dev/null | while IFS= read -r f; do
  i=\$((i + 1))
  [ \"\$i\" -gt 1 ] || continue
  if [ $keep -gt 0 ] && [ \"\$i\" -gt $keep ]; then rm -f -- \"\$f\" && echo \"\$f\"; continue; fi
  if [ -n \"\$(find \"\$f\" -maxdepth 0 -mtime +$PRUNE_DAYS 2>/dev/null)\" ]; then rm -f -- \"\$f\" && echo \"\$f\"; fi
done"
  case "$METHOD" in
    rsync)
      if [[ "$TARGET" == /* ]]; then
        [[ "$TARGET" =~ ^/[^/]+/[^/]+ ]] || return 0
        out="$(sh -c "$script" sh "$TARGET" 2>/dev/null)"
      else
        hostpart="${TARGET%%:*}"; rpath="${TARGET#*:}"
        [[ "$rpath" =~ ^[A-Za-z0-9_./~-]+$ ]] || return 0
        out="$(printf '%s\n' "$script" | nolock timeout 120 ssh "${SSH_OPTS[@]}" "$hostpart" sh -s "'$rpath'" 2>/dev/null)"
      fi
      ;;
    rclone)
      cutoff="$(date -d "-${PRUNE_DAYS} days" '+%Y-%m-%d %H:%M:%S')"
      out="$(nolock timeout 120 rclone lsf "$TARGET" --files-only --include "${prefix}_*.tgz.enc" --format tp --separator '|' 2>/dev/null \
        | LC_ALL=C sort -r | {
            i=0
            while IFS='|' read -r t n; do
              i=$((i + 1))
              { [ "$i" -gt 1 ] && [ -n "$n" ]; } || continue
              if { [ "$keep" -gt 0 ] && [ "$i" -gt "$keep" ]; } || [[ "$t" < "$cutoff" ]]; then
                nolock timeout 60 rclone deletefile "$TARGET/$n" >/dev/null 2>&1 && echo "$n"
              fi
            done
          })"
      ;;
    *) return 0 ;;
  esac
  [ -z "$out" ] || printf '%s\n' "$out" | while read -r l; do log "uzak budama ($label): silindi $l"; done
}

SENT=0
case "$METHOD" in
  rsync)
    command -v rsync >/dev/null || fail "rsync yok"
    RSH="ssh ${SSH_OPTS[*]}"
    if [[ "$TARGET" == /* ]]; then
      mkdir -p -- "$TARGET" 2>/dev/null || fail "yerel hedef dizini olusturulamadi"
      RSYNC=(rsync -a --checksum --partial --chmod=F600,D700)
    else
      RSYNC=(rsync -a --checksum --partial --chmod=F600,D700 -e "$RSH")
    fi
    if [ "$CHECK" -eq 1 ]; then
      out="$(nolock timeout 120 "${RSYNC[@]}" --dry-run --itemize-changes "${TO_SEND[@]/#/$OFFSITE_DIR/}" "$TARGET/" 2>&1)" || fail "rsync baglanti denemesi basarisiz: $(echo "$out" | tail -n1 | cut -c1-140)"
      log "BAGLANTI TAMAM (rsync kuru calistirma, ${#TO_SEND[@]} dosya gonderilecek)"
      exit 0
    fi
    out="$(nolock timeout 900 "${RSYNC[@]}" "${TO_SEND[@]/#/$OFFSITE_DIR/}" "$TARGET/" 2>&1)" || fail "rsync basarisiz: $(echo "$out" | tail -n1 | cut -c1-140)"
    # dogrulama: saglama toplamiyla ikinci kuru calistirma hic fark gostermemeli
    diffout="$(nolock timeout 300 "${RSYNC[@]}" --dry-run --itemize-changes "${TO_SEND[@]/#/$OFFSITE_DIR/}" "$TARGET/" 2>&1)" || fail "gonderim dogrulamasi calistirilamadi"
    [ -z "$diffout" ] || fail "gonderim dogrulamasi basarisiz (hedefteki dosya farkli)"
    SENT="${#TO_SEND[@]}"
    ;;
  sftp)
    command -v sftp >/dev/null || fail "sftp yok"
    [[ "$TARGET" == *:* ]] || fail "sftp icin OFFSITE_TARGET kullanici@host:/yol biciminde olmali"
    HOSTPART="${TARGET%%:*}"; RPATH="${TARGET#*:}"
    WORKF="$(mktemp "$OPS_HOME/sftp.XXXXXX")"
    batch="$WORKF"
    SFTP_OPTS=("${SSH_OPTS[@]/#-p/-P}")
    if [ "$CHECK" -eq 1 ]; then
      printf 'ls -l %s\n' "$RPATH" >"$batch"
      nolock timeout 60 sftp "${SFTP_OPTS[@]}" -b "$batch" "$HOSTPART" >/dev/null 2>&1 || fail "sftp baglanti denemesi basarisiz"
      log "BAGLANTI TAMAM (sftp)"
      exit 0
    fi
    : >"$batch"
    for f in "${TO_SEND[@]}"; do printf 'put %s %s/%s\n' "$OFFSITE_DIR/$f" "$RPATH" "$f" >>"$batch"; done
    nolock timeout 900 sftp "${SFTP_OPTS[@]}" -b "$batch" "$HOSTPART" >/dev/null 2>"$OPS_STATE/offsite.sftp.err" || fail "sftp basarisiz: $(tail -n1 "$OPS_STATE/offsite.sftp.err" | cut -c1-140)"
    # boyut dogrulamasi
    printf 'ls -ln %s\n' "$RPATH" >"$batch"
    listing="$(nolock timeout 60 sftp "${SFTP_OPTS[@]}" -b "$batch" "$HOSTPART" 2>/dev/null)"
    for f in "${TO_SEND[@]}"; do
      want="$(stat -c %s "$OFFSITE_DIR/$f")"
      echo "$listing" | awk -v n="$f" -v s="$want" '$NF ~ n"$" && $5 == s {ok=1} END{exit ok?0:1}' || fail "sftp dogrulamasi: $f hedefte yok/boyut farkli"
    done
    SENT="${#TO_SEND[@]}"
    ;;
  rclone)
    command -v rclone >/dev/null || fail "rclone kurulu degil (kullanici dizinine kurulabilir: ~/bin/rclone)"
    if [ "$CHECK" -eq 1 ]; then
      nolock timeout 60 rclone lsd "${TARGET%%:*}:" >/dev/null 2>&1 || nolock timeout 60 rclone mkdir "$TARGET" >/dev/null 2>&1 || fail "rclone baglanti denemesi basarisiz"
      log "BAGLANTI TAMAM (rclone)"
      exit 0
    fi
    # YALNIZ dogrulanmis (Salted__) TO_SEND listesi gonderilir; dizin genelindeki --include ile baska dosya sizmaz
    WORKF="$(mktemp "$OPS_HOME/sftp.XXXXXX")"
    printf '%s\n' "${TO_SEND[@]}" >"$WORKF"
    nolock timeout 900 rclone copy "$OFFSITE_DIR" "$TARGET" --files-from "$WORKF" --ignore-existing >"$OPS_STATE/offsite.rclone.out" 2>&1 || fail "rclone copy basarisiz: $(tail -n1 "$OPS_STATE/offsite.rclone.out" | cut -c1-140)"
    nolock timeout 300 rclone check "$OFFSITE_DIR" "$TARGET" --files-from "$WORKF" --one-way >"$OPS_STATE/offsite.rclone.out" 2>&1 || fail "rclone check (dogrulama) basarisiz"
    SENT="${#TO_SEND[@]}"
    ;;
esac

for f in "${TO_SEND[@]}"; do grep -qxF "$f" "$PUSHED_LIST" 2>/dev/null || echo "$f" >>"$PUSHED_LIST"; done
# liste sisimesin: son 400 ad
[ -f "$PUSHED_LIST" ] && tail -n 400 "$PUSHED_LIST" >"$PUSHED_LIST.tmp" && mv "$PUSHED_LIST.tmp" "$PUSHED_LIST"
write_status "$STATUS_FILE" "result=OK" "epoch=$(now_epoch)" "method=$METHOD" "pushed=$SENT"
log "=== dis kopya BASARILI: $SENT dosya gonderildi ve dogrulandi ($METHOD) ==="
prune_remote
prune_newest_kept_remote kapi_documents "belge arsivi"
prune_newest_kept_remote kapi_work_attachments "fotograf arsivi" "$WA_KEEP"
trim_log
exit 0
