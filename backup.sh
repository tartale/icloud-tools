#!/bin/bash
# Copy each account's "All Photos" from iCloud with rclone, plus its album listing.
# One lock for all accounts: they run one after the other, which is also gentler on Apple's rate limits
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
exec 9>"$ICLOUD_LOCK_FILE"
flock -n 9 || { echo "Previous run still active, exiting"; exit 0; }

RCLONE=$ICLOUD_RCLONE
CONF=$ICLOUD_RCLONE_CONF
LOG=$ICLOUD_ROOT/backup.log

backup_account() {
  local remote="$1" dest="$2"
  local rc tmp="$2/albums.tmp"

  mkdir -p "$dest"

  $RCLONE copy "${remote}:/PrimarySync/All Photos" "$dest/All Photos" \
    --config "$CONF" \
    --transfers 4 --checkers 8 \
    --retries 5 --low-level-retries 20 \
    --log-file "$LOG" --log-level INFO
  rc=$?

  # Album membership list: replace the old one only if the listing succeeded
  if $RCLONE lsf "${remote}:/PrimarySync" -R --files-only \
       --config "$CONF" --log-file "$LOG" --log-level INFO > "$tmp"; then
    grep -v '^All Photos/' "$tmp" > "$dest/albums.txt" || true   # grep exits 1 if no albums; not an error
  else
    echo "$(date) [$remote] album listing failed" >> "$LOG"
  fi
  rm -f "$tmp"

  return $rc
}

overall=0
for account in $ICLOUD_ACCOUNTS; do
  backup_account "${account#*=}" "$ICLOUD_ROOT/${account%%=*}" || overall=1
done

exit $overall
