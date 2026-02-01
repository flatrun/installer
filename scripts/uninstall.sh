#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[FlatRun]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[FlatRun]${NC} $*"
}

log_error() {
    echo -e "${RED}[FlatRun]${NC} $*"
}

if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

echo ""
echo -e "${YELLOW}WARNING: This will uninstall FlatRun and remove all configuration.${NC}"
echo -e "${YELLOW}Your deployments in /opt/flatrun/deployments will NOT be removed.${NC}"
echo ""
read -p "Are you sure you want to continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Uninstall cancelled"
    exit 0
fi

log "Stopping FlatRun Agent..."
systemctl stop flatrun-agent 2>/dev/null || true
systemctl disable flatrun-agent 2>/dev/null || true

log "Stopping UI container..."
docker compose -f /opt/flatrun/deployments/ui/docker-compose.yml down 2>/dev/null || true

log "Removing systemd service..."
rm -f /etc/systemd/system/flatrun-agent.service
systemctl daemon-reload

log "Removing FlatRun files..."
rm -rf /opt/flatrun/bin /opt/flatrun/version
rm -rf /etc/flatrun
rm -rf /var/log/flatrun
rm -f /usr/local/bin/flatrun-agent

log "Removing MOTD..."
rm -f /etc/update-motd.d/99-flatrun

echo ""
log "FlatRun has been uninstalled."
log_warn "Note: /opt/flatrun/deployments directory has been preserved."
log_warn "Note: Docker networks (proxy, database) have been preserved."
echo ""
