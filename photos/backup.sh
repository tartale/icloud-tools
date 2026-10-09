#!/bin/bash
# Copy every photo and video from each iCloud account into <account>/originals/, plus the album listing.
# "All Photos" lands flat in originals/; photos that exist only in albums land in originals/<Album>/,
# once each (a photo is the same when file name, size and modification time match). albums.csv maps each album entry to its stored file.
# One lock for all accounts: they run one after the other, which is also gentler on Apple's rate limits
# The whole script lives in main so bash has parsed all of it before running any of it;
# editing the file mid-run then cannot corrupt that run.
main() {
  # Configuration comes from the environment only (see README)
  missing=()
  for v in ICLOUD_ROOT ICLOUD_ACCOUNTS; do [ -n "${!v:-}" ] || missing+=("$v"); done
  if ((${#missing[@]})); then echo "Missing required environment variables: ${missing[*]}" >&2; exit 2; fi
  DRY_RUN=${DRY_RUN:-false}
  exec 9>"${ICLOUD_LOCK_FILE:-/tmp/rclone-icloudphotos.lock}"
  flock -n 9 || { echo "Previous run still active, exiting"; exit 0; }

  TAB=$'\t'
  RCLONE=${ICLOUD_RCLONE:-rclone}
  CONF_OPTS=()
  if [ -n "${ICLOUD_RCLONE_CONF:-}" ]; then CONF_OPTS=(--config "$ICLOUD_RCLONE_CONF"); fi
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
      "${CONF_OPTS[@]}" "${RCLONE_OPTS[@]}" \
      --transfers 4 --checkers 8 \
      --retries 5 --low-level-retries 20 \
      --log-file "$LOG" --log-level INFO || rc=1

    # Full listing (modification time, size, path; tab-separated), taken after the copy above and sorted by path so that
    # the same photo always resolves to the same stored copy. Entries outside "All Photos" are album members.
    if ! $RCLONE lsf "${remote}:/PrimarySync" -R --files-only --format tsp --separator "$TAB" \
         "${CONF_OPTS[@]}" --log-file "$LOG" --log-level INFO > "$listing"; then
      log "[$remote] ERROR: listing failed; album-only photos not copied"
      rm -f "$listing"
      return 1
    fi

    # A photo is identified by file name + size + modification time. For each album entry, "stored" is where its file lives
    # in originals/: the All Photos copy if there is one, else the first album path holding that photo.
    # albums.csv records that; album_only lists the one path to download per photo that is only in albums.
    if ! LC_ALL=C sort -t "$TAB" -k3 "$listing" | awk -F "$TAB" -v albums="$dest/albums.csv.new" -v only="$album_only" '
      function csv(s) {
        if (s ~ /[",\n]/) { gsub(/"/, "\"\"", s); s = "\"" s "\"" }
        return s
      }
      {
        path = $3
        if (index(path, "All Photos/") == 1) { have[substr(path, 12) SUBSEP $2 SUBSEP $1] = 1; next }
        if (index(path, "/") > 0) { n++; mtime[n] = $1; size[n] = $2; entry[n] = path }
      }
      END {
        print "path,size,mtime,stored" > albums
        for (i = 1; i <= n; i++) {
          name = entry[i]; sub(/.*\//, "", name)
          key = name SUBSEP size[i] SUBSEP mtime[i]
          if (key in have) stored = name
          else {
            if (!(key in first)) { first[key] = entry[i]; print entry[i] > only }
            stored = first[key]
          }
          print csv(entry[i]) "," size[i] "," mtime[i] "," csv(stored) > albums
        }
        close(albums); close(only)
      }'; then
      log "[$remote] ERROR: could not build the album list"
      rm -f "$listing" "$dest/albums.csv.new" "$album_only"
      return 1
    fi
    [ -e "$album_only" ] || : > "$album_only"
    mv "$dest/albums.csv.new" "$dest/albums.csv"

    log "[$remote] copying $(wc -l < "$album_only") album-only photos (one copy each)"
    $RCLONE copy "${remote}:/PrimarySync" "$dest/originals" \
      --files-from-raw "$album_only" \
      "${CONF_OPTS[@]}" "${RCLONE_OPTS[@]}" \
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
  return "$overall"
}

main "$@"; exit
