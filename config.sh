# shellcheck shell=bash
# Shared settings, sourced by backup.sh and organize.sh. Every value can be
# overridden from the environment.

ICLOUD_ROOT=${ICLOUD_ROOT:-/volume1/icloud/photos}
ICLOUD_RCLONE=${ICLOUD_RCLONE:-/usr/bin/rclone}
ICLOUD_RCLONE_CONF=${ICLOUD_RCLONE_CONF:-/volume1/homes/admin/.config/rclone/rclone.conf}
ICLOUD_LOCK_FILE=${ICLOUD_LOCK_FILE:-/tmp/rclone-icloudphotos.lock}

# Space-separated "<name>=<rclone remote>" pairs. Photos land in $ICLOUD_ROOT/<name>.
ICLOUD_ACCOUNTS=${ICLOUD_ACCOUNTS:-"tom=tom.photos.icloud marissa=marissa.photos.icloud"}

# Unprefixed by convention; "true" or "1" means change nothing (rclone --dry-run, or organize.sh counting only).
DRY_RUN=${DRY_RUN:-false}
