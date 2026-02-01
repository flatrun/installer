#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

log_section "Cleaning Up"

log "Cleaning apt cache..."
apt-get clean
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*

log "Cleaning temporary files..."
rm -rf /tmp/*
rm -rf /var/tmp/*

log "Cleaning SSH host keys (will be regenerated on first boot)..."
rm -f /etc/ssh/ssh_host_*

log "Cleaning logs..."
find /var/log -type f -name "*.log" -delete
find /var/log -type f -name "*.gz" -delete
journalctl --rotate
journalctl --vacuum-time=1s

log "Cleaning machine-id (will be regenerated)..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

log "Cleaning bash history..."
rm -f /root/.bash_history
rm -f /home/*/.bash_history

log "Zeroing free space for better compression..."
dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY

log "Cleanup complete"
