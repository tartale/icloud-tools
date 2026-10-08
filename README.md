# icloud-tools

Scripts that wrap [rclone](https://rclone.org) to back up iCloud Photos to a local disk (built for a Synology NAS).

## Scripts

| Script | What it does |
| --- | --- |
| `backup.sh` | For each account, `rclone copy`s `PrimarySync/All Photos` into `$ICLOUD_ROOT/<name>/originals/`, then copies photos that exist only in albums to `originals/<Album>/`, once per photo. Writes `albums.csv`. Safe to run from cron; skips if a run is already active. |
| `organize.sh` | Builds `by-date/YYYY/MM/` (by file mtime) and `albums/<Album>/` hardlink trees beside `originals/`. Rerunnable; never modifies `originals/`. |
| `lint.sh` | Runs `shellcheck` over every script. |
| `config.sh` | Shared settings, sourced by the two scripts above. |

`backup.sh` and `organize.sh` share one lock, so they never run at the same time.

## Layout

Every photo and video is stored once, under `originals/`. `by-date/` and `albums/` are hardlinks into it, so they cost no extra space.

```
$ICLOUD_ROOT/<name>/
  originals/        # one copy of everything
  by-date/YYYY/MM/  # hardlinks
  albums/<Album>/   # hardlinks
  albums.csv        # path,size,mtime,stored: each album entry and the originals/ file it links to
```

A photo is the same photo when its file name, size and modification time all match. A photo in several albums is downloaded once; a different photo that merely shares a name (and even a size) is kept separately. If two different photos share a name in the same month, `by-date/` links the second as `<name>-<size>.<ext>`.

## Configuration

Set in the environment; defaults are in `config.sh`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ICLOUD_ROOT` | `/volume1/icloud/photos` | Destination root and log directory |
| `ICLOUD_ACCOUNTS` | `tom=tom.photos.icloud marissa=marissa.photos.icloud` | Space-separated `<name>=<rclone remote>` pairs |
| `ICLOUD_RCLONE` | `/usr/bin/rclone` | rclone binary |
| `ICLOUD_RCLONE_CONF` | `/volume1/homes/admin/.config/rclone/rclone.conf` | rclone config with the iCloud remotes |
| `ICLOUD_LOCK_FILE` | `/tmp/rclone-icloudphotos.lock` | Shared lock |
| `DRY_RUN` | `false` | `true`/`1`: `backup.sh` passes `--dry-run` to rclone; `organize.sh` counts only and creates nothing |
| `PROGRESS_EVERY` | `1000` | `organize.sh` progress-log interval |

Logs: `$ICLOUD_ROOT/backup.log`, `$ICLOUD_ROOT/organize.log`. Run from a terminal, both scripts also print their status lines there, and `backup.sh` shows rclone's live transfer progress; from cron they only write the log.
