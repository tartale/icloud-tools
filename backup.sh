#!/bin/bash
# Copy every photo and video from each iCloud account into <account>/originals/, plus the album listing.
# "All Photos" lands flat in originals/; photos that exist only in albums land in originals/<Album>/.
# One lock for all accounts: they run one after the other, which is also gentler on Apple's rate limits
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
exec 9>"$ICLOUD_LOCK_FILE"
flock -n 9 || { echo "Previous run still active, exiting"; exit 0; }

RCLONE=$ICLOUD_RCLONE
CONF=$ICLOUD_RCLONE_CONF
LOG=$ICLOUD_ROOT/backup.log

# Writes to the log file, and to the terminal too when run interactively
log() {
  local msg
  msg="$(date '+%F %T') $*"
  echo "$msg" >> "$LOG"
  if [ -t 1 ]; then echo "$msg"; fi
}

# Interactive runs show rclone's live transfer progress; the log file gets INFO either way
RCLONE_OPTS=()
case $DRY_RUN in true|1) RCLONE_OPTS+=(--dry-run);; esac
if [ -t 1 ]; then RCLONE_OPTS+=(--progress); fi

backup_account() {
  local remote="$1" dest="$2"
  local rc=0 listing="$2/listing.tmp" album_only="$2/album-only.tmp"

  mkdir -p "$dest/originals"
  log "[$remote] copying All Photos (dry-run=$DRY_RUN)"

  $RCLONE copy "${remote}:/PrimarySync/All Photos" "$dest/originals" \
    --config "$CONF" "${RCLONE_OPTS[@]}" \
    --transfers 4 --checkers 8 \
    --retries 5 --low-level-retries 20 \
    --log-file "$LOG" --log-level INFO || rc=1

  # Full listing, taken after the copy above. Entries outside "All Photos" are album members.
  if ! $RCLONE lsf "${remote}:/PrimarySync" -R --files-only \
       --config "$CONF" --log-file "$LOG" --log-level INFO > "$listing"; then
    log "[$remote] ERROR: listing failed; album-only photos not copied"
    rm -f "$listing"
    return 1
  fi

  # Album membership list, and the members whose file name is not in "All Photos".
  awk -v albums="$dest/albums.txt" -v only="$album_only" '
    index($0, "All Photos/") == 1 { have[substr($0, 12)] = 1; next }
    { entries[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        print entries[i] > albums
        name = entries[i]; sub(/.*\//, "", name)
        if (!(name in have) && index(entries[i], "/") > 0) print entries[i] > only
      }
      close(albums); close(only)
    }' "$listing"
  [ -e "$dest/albums.txt" ] || : > "$dest/albums.txt"
  [ -e "$album_only" ] || : > "$album_only"

  log "[$remote] copying $(wc -l < "$album_only") album-only photos"
  $RCLONE copy "${remote}:/PrimarySync" "$dest/originals" \
    --files-from-raw "$album_only" \
    --config "$CONF" "${RCLONE_OPTS[@]}" \
    --transfers 4 --checkers 8 \
    --retries 5 --low-level-retries 20 \
    --log-file "$LOG" --log-level INFO || rc=1

  rm -f "$listing" "$album_only"
  log "[$remote] finished (exit $rc)"
  return $rc
}

log "=== backup run started ==="
overall=0
for account in $ICLOUD_ACCOUNTS; do
  backup_account "${account#*=}" "$ICLOUD_ROOT/${account%%=*}" || overall=1
done
log "=== backup run finished: exit $overall, ${SECONDS}s total ==="
exit $overall
