#!/bin/bash
# Build by-date/ and albums/ hardlink trees next to originals/, where every photo is stored once.
# Safe to rerun: existing links are skipped. Nothing in originals/ is modified.
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
exec 9>"$ICLOUD_LOCK_FILE"
flock -n 9 || { echo "Backup still running, exiting"; exit 0; }

LOG=$ICLOUD_ROOT/organize.log
DRY=0
case $DRY_RUN in true|1) DRY=1;; esac   # DRY_RUN=true ./organize.sh -> count only, create nothing
PROGRESS_EVERY=${PROGRESS_EVERY:-1000} # log a progress line every N files

# Writes to the log file, and to the terminal too when run interactively
log() {
  local msg
  msg="$(date '+%F %T') $*"
  echo "$msg" >> "$LOG"
  if [ -t 1 ]; then echo "$msg"; fi
}

# returns 0 = created, 1 = already existed, 2 = failed
link_one() {
  [ -e "$2" ] && return 1
  [ "$DRY" = 1 ] && return 0
  mkdir -p "${2%/*}" && ln "$1" "$2" || return 2
}

link_account() {
  local base="$1" src="$1/originals" t0=$SECONDS
  local d_new=0 d_have=0 d_fail=0 a_new=0 a_have=0 a_fail=0 a_miss=0
  local ym f line album name file total i

  [ -d "$src" ] || { log "[$base] ERROR: $src not found"; return 1; }
  log "[$base] starting (dry=$DRY)"

  # --- by-date/YYYY/MM (uses file modification time) ---
  log "[$base] by-date: counting files..."
  total=$(find "$src" -type f | wc -l)
  log "[$base] by-date: $total files to check"
  i=0
  while IFS= read -r -d '' ym && IFS= read -r -d '' f; do
    link_one "$f" "$base/by-date/$ym/${f##*/}"
    case $? in
      0) ((d_new++));;
      1) ((d_have++));;
      *) ((d_fail++)); if ((d_fail <= 20)); then log "[$base] FAILED to link: $f"; fi;;
    esac
    ((i++))
    if ((i % PROGRESS_EVERY == 0)); then
      log "[$base] by-date: $i/$total (new=$d_new existing=$d_have failed=$d_fail) $((SECONDS - t0))s elapsed"
    fi
  done < <(find "$src" -type f -printf '%TY/%Tm\0%p\0')
  log "[$base] by-date done: new=$d_new existing=$d_have failed=$d_fail"

  # --- albums/<Album>/ (from the album list the backup script writes) ---
  # An entry is stored at originals/<entry> when it exists only in an album, otherwise at originals/<name>.
  if [ -s "$base/albums.txt" ]; then
    total=$(grep -c '/' "$base/albums.txt")
    log "[$base] albums: $total entries to check"
    i=0
    while IFS= read -r line; do
      [[ $line == */* ]] || continue          # skip entries not inside an album folder
      album="${line%/*}"; name="${line##*/}"
      ((i++))
      if [ -f "$src/$line" ]; then file="$src/$line"
      elif [ -f "$src/$name" ]; then file="$src/$name"
      else file=""
      fi
      if [ -z "$file" ]; then
        ((a_miss++))
        if ((a_miss <= 20)); then log "[$base] not in originals: $line"; fi
      else
        link_one "$file" "$base/albums/$album/$name"
        case $? in
          0) ((a_new++));;
          1) ((a_have++));;
          *) ((a_fail++)); if ((a_fail <= 20)); then log "[$base] FAILED to link: $line"; fi;;
        esac
      fi
      if ((i % PROGRESS_EVERY == 0)); then
        log "[$base] albums: $i/$total (new=$a_new existing=$a_have failed=$a_fail not-in-originals=$a_miss) $((SECONDS - t0))s elapsed"
      fi
    done < "$base/albums.txt"
    log "[$base] albums done: new=$a_new existing=$a_have failed=$a_fail not-in-originals=$a_miss"
  else
    log "[$base] albums.txt missing or empty; skipped albums"
  fi

  log "[$base] finished in $((SECONDS - t0))s"
  [ "$d_fail" -eq 0 ] && [ "$a_fail" -eq 0 ]
}

log "=== link run started ==="
overall=0
for account in $ICLOUD_ACCOUNTS; do
  link_account "$ICLOUD_ROOT/${account%%=*}" || overall=1
done
log "=== link run finished: exit $overall, ${SECONDS}s total ==="
exit $overall
