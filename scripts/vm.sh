#!/bin/bash
set -euo pipefail

VM_NAME="flatrun-test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$INSTALLER_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[vm]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[vm]${NC} $*"; }
log_error() { echo -e "${RED}[vm]${NC} $*"; }

# --- Backend detection ---

BACKEND=""

detect_backend() {
    if [ -n "$BACKEND" ]; then
        return
    fi

    if command -v multipass &> /dev/null; then
        BACKEND="multipass"
    elif command -v vagrant &> /dev/null; then
        BACKEND="vagrant"
    else
        log_error "No VM backend found. Install one of:"
        log_error "  multipass:  brew install multipass  (macOS/Linux)"
        log_error "  vagrant:    apt install vagrant virtualbox  (Linux)"
        exit 1
    fi

    log "Using backend: $BACKEND"
}

# --- Multipass ---

mp_vm_exists() {
    multipass list --format csv 2>/dev/null | grep -q "^${VM_NAME},"
}

mp_vm_running() {
    multipass list --format csv 2>/dev/null | grep -q "^${VM_NAME},Running"
}

mp_create() {
    log "Creating Ubuntu 22.04 VM (multipass)..."
    multipass launch 22.04 \
        --name "$VM_NAME" \
        --cpus 2 \
        --memory 2G \
        --disk 20G \
        --network en0

    log "Mounting installer directory..."
    multipass mount "$INSTALLER_DIR" "${VM_NAME}:/installer"
    log "VM ready!"
}

mp_start() {
    if ! mp_vm_exists; then
        mp_create
        return
    fi
    if ! mp_vm_running; then
        log "Starting VM..."
        multipass start "$VM_NAME"
    fi
    log "VM is running"
}

mp_get_ip() {
    multipass info "$VM_NAME" --format csv | tail -1 | cut -d',' -f3
}

mp_exec() {
    multipass exec "$VM_NAME" -- "$@"
}

mp_ssh() {
    multipass shell "$VM_NAME"
}

mp_stop() {
    if mp_vm_running; then
        log "Stopping VM..."
        multipass stop "$VM_NAME"
    else
        log "VM is not running"
    fi
}

mp_destroy() {
    if mp_vm_exists; then
        log "Destroying VM..."
        multipass delete "$VM_NAME"
        multipass purge
        log "VM destroyed"
    else
        log "VM does not exist"
    fi
}

mp_status() {
    if mp_vm_exists; then
        multipass info "$VM_NAME"
    else
        log "No VM found. Run '$0 up' to create one."
    fi
}

# --- Vagrant ---

vg_start() {
    log "Starting VM (vagrant)..."
    cd "$INSTALLER_DIR"
    vagrant up
    log "VM is running"
}

vg_get_ip() {
    echo "192.168.56.10"
}

vg_exec() {
    cd "$INSTALLER_DIR"
    vagrant ssh -c "sudo $*"
}

vg_ssh() {
    cd "$INSTALLER_DIR"
    vagrant ssh
}

vg_stop() {
    cd "$INSTALLER_DIR"
    vagrant halt
}

vg_destroy() {
    cd "$INSTALLER_DIR"
    vagrant destroy -f
}

vg_status() {
    cd "$INSTALLER_DIR"
    vagrant status
}

# --- Unified interface ---

vm_start() {
    case "$BACKEND" in
        multipass) mp_start ;;
        vagrant)   vg_start ;;
    esac
}

vm_get_ip() {
    case "$BACKEND" in
        multipass) mp_get_ip ;;
        vagrant)   vg_get_ip ;;
    esac
}

vm_exec() {
    case "$BACKEND" in
        multipass) mp_exec sudo "$@" ;;
        vagrant)   vg_exec "$@" ;;
    esac
}

vm_ssh() {
    case "$BACKEND" in
        multipass) mp_ssh ;;
        vagrant)   vg_ssh ;;
    esac
}

vm_stop() {
    case "$BACKEND" in
        multipass) mp_stop ;;
        vagrant)   vg_stop ;;
    esac
}

vm_destroy() {
    case "$BACKEND" in
        multipass) mp_destroy ;;
        vagrant)   vg_destroy ;;
    esac
}

vm_status() {
    case "$BACKEND" in
        multipass) mp_status ;;
        vagrant)   vg_status ;;
    esac
}

# --- Commands ---

print_access_info() {
    local ip
    ip=$(vm_get_ip)
    echo ""
    echo -e "  Welcome page: ${GREEN}http://${ip}${NC}"
    echo -e "  Dashboard:    ${GREEN}http://${ip}:8080${NC}"
    echo -e "  Agent API:    ${GREEN}http://${ip}:8090/api${NC}"
}

cmd_up() {
    vm_start
}

cmd_install() {
    vm_start
    log "Running production installer..."
    vm_exec /installer/scripts/install.sh
    print_access_info
}

cmd_dev() {
    local builds="${INSTALLER_DIR}/builds"

    if [ ! -f "$builds/flatrun-agent" ]; then
        log_error "Missing: builds/flatrun-agent"
        echo ""
        log "Place pre-built artifacts in installer/builds/:"
        log "  cd agent && GOOS=linux GOARCH=amd64 go build -o ../installer/builds/flatrun-agent ./cmd/agent"
        log "  cd ui && npm run build && cp -r dist ../installer/builds/ui-dist  (optional)"
        exit 1
    fi

    vm_start
    log "Running dev installer..."
    vm_exec /installer/scripts/install-dev.sh
    print_access_info
}

cmd_ssh() {
    vm_start
    vm_ssh
}

cmd_reset() {
    vm_destroy
    vm_start
}

show_usage() {
    echo "Usage: $0 [--backend multipass|vagrant] <command>"
    echo ""
    echo "Commands:"
    echo "  up        Create and start the VM"
    echo "  install   Run the production installer in the VM"
    echo "  dev       Build from source and install in the VM"
    echo "  ssh       SSH into the VM"
    echo "  stop      Stop the VM"
    echo "  destroy   Delete the VM"
    echo "  status    Show VM info"
    echo "  reset     Destroy and recreate the VM"
    echo ""
    echo "Backend is auto-detected (multipass preferred). Override with --backend."
    echo ""
    echo "Examples:"
    echo "  $0 up                         # Create VM"
    echo "  $0 dev                        # Build + install from source"
    echo "  $0 install                    # Test production installer"
    echo "  $0 --backend vagrant dev      # Force Vagrant backend"
    echo "  $0 ssh                        # SSH in to inspect"
    echo "  $0 destroy                    # Clean up"
}

main() {
    # Parse --backend flag
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backend)
                BACKEND="$2"
                if [[ "$BACKEND" != "multipass" && "$BACKEND" != "vagrant" ]]; then
                    log_error "Unknown backend: $BACKEND (use 'multipass' or 'vagrant')"
                    exit 1
                fi
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done

    detect_backend

    local cmd="${1:-help}"

    case "$cmd" in
        up)       cmd_up ;;
        install)  cmd_install ;;
        dev)      cmd_dev ;;
        ssh)      cmd_ssh ;;
        stop)     vm_stop ;;
        destroy)  vm_destroy ;;
        status)   vm_status ;;
        reset)    cmd_reset ;;
        help|--help|-h) show_usage ;;
        *)
            log_error "Unknown command: $cmd"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
