#!/bin/sh
set -eu
umask 077
test "$(id -u)" -eq 0 || { echo 'Run with sudo'; exit 1; }
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup=/srv/four-game-backups/pre-yandex-backup-$stamp
mkdir -p "$backup"
chmod 700 "$backup"
for unit in four-game-backup.service four-game-backup.timer; do
    if [ -f "/etc/systemd/system/$unit" ]; then cp "/etc/systemd/system/$unit" "$backup/$unit"; fi
done
if [ -d /usr/local/lib/four-game ]; then tar -czf "$backup/backup-tools-before.tgz" -C /usr/local/lib four-game; fi
if ! command -v rclone >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends rclone
fi
python3 -m unittest discover -s "$repo/scripts" -p test_backup_database.py -v
install -d -o root -g root -m 755 /usr/local/lib/four-game
install -o root -g root -m 644 "$repo/scripts/backup-database.py" /usr/local/lib/four-game/backup-database.py
install -o root -g root -m 700 "$repo/scripts/setup-yandex-backup.py" /usr/local/lib/four-game/setup-yandex-backup.py
install -o root -g root -m 644 "$repo/deploy/four-game-backup.service" /etc/systemd/system/four-game-backup.service
install -o root -g root -m 644 "$repo/deploy/four-game-backup.timer" /etc/systemd/system/four-game-backup.timer
systemd-analyze verify /etc/systemd/system/four-game-backup.service /etc/systemd/system/four-game-backup.timer
systemctl daemon-reload
# Enable cloud uploads only once credentials are present and a complete backup succeeds.
if [ -f /etc/four-game/yandex-rclone.conf ]; then
    systemctl start four-game-backup.service
    systemctl enable --now four-game-backup.timer
else
    printf 'Installed. To connect Yandex Disk, run:\nsudo python3 /usr/local/lib/four-game/setup-yandex-backup.py\n'
fi
printf 'BACKUP=%s\n' "$backup"
