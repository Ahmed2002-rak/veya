#!/usr/bin/env bash
# backup_configs.sh — VEYA SD-card insurance
#
# Tars up everything that lives only on the card and is NOT in git:
#   - ~/.veya/           (bt_config, server_config, user_profile)
#   - ~/.bash_profile    (kiosk autostart trigger)
#   - /etc/systemd/system/getty@tty1.service.d/autologin.conf
#   - /etc/systemd/system/bt-agent.service
#
# Usage:
#   bash scripts/backup_configs.sh
#
# Output:
#   /home/pfe/veya/backups/veya_config_backup_YYYYMMDD.tar.gz
#
# Restore:
#   cd / && sudo tar -xzf /path/to/veya_config_backup_YYYYMMDD.tar.gz
#   (paths inside the archive are absolute from /)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$REPO_DIR/backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE="$BACKUP_DIR/veya_config_backup_${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

# Build the list of files/dirs that actually exist
TARGETS=()

add_if_exists() {
    if [ -e "$1" ]; then
        TARGETS+=("$1")
    else
        echo "  [skip] not found: $1"
    fi
}

echo "=== VEYA config backup ==="
echo "Timestamp : $TIMESTAMP"
echo ""
echo "Scanning for card-only files..."

add_if_exists "$HOME/.veya"
add_if_exists "$HOME/.bash_profile"
add_if_exists "/etc/systemd/system/bt-agent.service"
add_if_exists "/etc/systemd/system/getty@tty1.service.d/autologin.conf"

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "ERROR: No config files found — nothing to back up."
    exit 1
fi

echo ""
echo "Packing:"
for t in "${TARGETS[@]}"; do
    echo "  $t"
done
echo ""

# tar with absolute paths (strip leading / so it's portable, then restore with cd /)
tar -czf "$ARCHIVE" \
    --absolute-names \
    "${TARGETS[@]}" 2>/dev/null

echo "Saved to : $ARCHIVE"
echo "Size     : $(du -sh "$ARCHIVE" | cut -f1)"
echo ""
echo "--- Restore instructions ---"
echo "  scp pfe@raspberrypi.local:$ARCHIVE ."
echo "  # On the fresh Pi, as root:"
echo "  cd / && sudo tar -xzf $(basename "$ARCHIVE")"
echo ""
echo "IMPORTANT: copy this tarball OFF the Pi before the card dies."
echo "  scp $ARCHIVE your-laptop:~/veya-backups/"
