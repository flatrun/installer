#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_section() {
    echo ""
    echo "=============================================="
    echo " $*"
    echo "=============================================="
}

wait_for_apt() {
    local max_wait=300
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if [ $waited -ge $max_wait ]; then
            log "ERROR: Timed out waiting for apt locks"
            exit 1
        fi
        log "Waiting for apt locks to be released..."
        sleep 5
        waited=$((waited + 5))
    done
}

apt_update() {
    wait_for_apt
    apt-get update -qq
}

apt_install() {
    wait_for_apt
    apt-get install -y -qq "$@"
}

create_user_if_not_exists() {
    local username=$1
    if ! id "$username" &>/dev/null; then
        useradd -r -s /bin/false "$username"
        log "Created user: $username"
    fi
}

enable_service() {
    systemctl daemon-reload
    systemctl enable "$1"
    log "Enabled service: $1"
}

start_service() {
    systemctl start "$1"
    log "Started service: $1"
}
