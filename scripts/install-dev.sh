#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="FlatRun Dev"
source "$SCRIPT_DIR/lib.sh"

BUILDS_DIR="${BUILDS_DIR:-/installer/builds}"

# --- Source path detection ---

detect_source_paths() {
    if [ -d "/src/agent" ]; then
        AGENT_DIR="/src/agent"
        UI_DIR="/src/ui"
    elif [ -d "$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)/agent" ]; then
        local project_root
        project_root="$(cd "$SCRIPT_DIR/../.." && pwd)"
        AGENT_DIR="$project_root/agent"
        UI_DIR="$project_root/ui"
    else
        log_error "Cannot find source directories."
        log_error "Checked: /src/agent (Vagrant) and ../../agent (direct checkout)"
        exit 1
    fi
    log "Agent source: $AGENT_DIR"
    log "UI source:    $UI_DIR"
}

# --- Build dependencies ---

check_dependencies() {
    log "Checking dependencies..."

    export PATH=$PATH:/usr/local/go/bin

    if ! command -v go &> /dev/null; then
        log_error "Go is not installed. Please install Go 1.21+"
        exit 1
    fi

    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js 18+"
        exit 1
    fi

    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install npm"
        exit 1
    fi

    if ! command -v docker &> /dev/null || ! docker info &> /dev/null 2>&1; then
        log_error "Docker is not installed or not running"
        exit 1
    fi

    log "All dependencies found"
}

# --- Build ---

build_agent() {
    log "Building FlatRun Agent..."
    cd "$AGENT_DIR"

    if [ ! -f "go.mod" ]; then
        log_error "go.mod not found in $AGENT_DIR"
        exit 1
    fi

    go build -o "$AGENT_DIR/flatrun-agent" ./cmd/agent

    if [ ! -f "$AGENT_DIR/flatrun-agent" ]; then
        log_error "Agent build failed"
        exit 1
    fi

    log "Agent built successfully"
}

build_ui() {
    log "Building FlatRun UI..."
    cd "$UI_DIR"

    if [ ! -f "package.json" ]; then
        log_error "package.json not found in $UI_DIR"
        exit 1
    fi

    [ ! -d "node_modules" ] && npm install
    npm run build

    if [ ! -d "dist" ]; then
        log_error "UI build failed - dist directory not found"
        exit 1
    fi

    log "UI built successfully"
}

# --- Install from pre-built artifacts ---

install_from_builds() {
    local agent_binary="${BUILDS_DIR}/flatrun-agent"
    local ui_dist="${BUILDS_DIR}/ui-dist"

    if [ ! -f "$agent_binary" ]; then
        log_error "Agent binary not found at $agent_binary"
        echo ""
        log_error "Place pre-built artifacts in installer/builds/:"
        log_error "  cd agent && GOOS=linux GOARCH=amd64 go build -o ../installer/builds/flatrun-agent ./cmd/agent"
        log_error "  cd ui && npm run build && cp -r dist ../installer/builds/ui-dist  (optional)"
        exit 1
    fi

    log "Installing agent binary..."
    cp "$agent_binary" "$INSTALL_DIR/bin/flatrun-agent"
    chmod +x "$INSTALL_DIR/bin/flatrun-agent"
    ln -sf "$INSTALL_DIR/bin/flatrun-agent" /usr/local/bin/flatrun-agent

    if [ -d "$ui_dist" ] && [ -f "$ui_dist/index.html" ]; then
        log "Deploying dashboard UI..."
        local ui_dir="$DEPLOYMENTS_DIR/ui"
        mkdir -p "$ui_dir/html"
        cp -r "$ui_dist"/* "$ui_dir/html/"
        deploy_ui
    else
        log_warn "Dashboard UI not found at $ui_dist (skipping)"
    fi
}

# --- Install from source ---

install_from_source() {
    log "Installing local binaries..."
    cp "$AGENT_DIR/flatrun-agent" "$INSTALL_DIR/bin/flatrun-agent"
    chmod +x "$INSTALL_DIR/bin/flatrun-agent"
    ln -sf "$INSTALL_DIR/bin/flatrun-agent" /usr/local/bin/flatrun-agent

    log "Deploying dashboard UI..."
    deploy_ui "$UI_DIR/dist"
}

# --- Run modes ---

start_agent() {
    log "Starting FlatRun Agent..."
    systemctl start flatrun-agent

    sleep 2
    if systemctl is-active --quiet flatrun-agent; then
        log "FlatRun Agent started successfully"
    else
        log_error "FlatRun Agent failed to start"
        journalctl -u flatrun-agent --no-pager -n 20
        exit 1
    fi
}

run_agent_foreground() {
    local ip
    ip=$(get_public_ip)

    log "Starting FlatRun Agent in foreground..."
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  FlatRun Dev Test Environment${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo -e "  Dashboard:    ${GREEN}http://${ip}:8080${NC}"
    echo -e "  Setup wizard: ${GREEN}http://${ip}:8080/setup${NC}"
    echo -e "  API endpoint: ${GREEN}http://${ip}:8090/api${NC}"
    echo ""
    echo -e "  Press Ctrl+C to stop"
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo ""

    cd "$INSTALL_DIR/bin"
    exec ./flatrun-agent --config "$CONFIG_DIR/config.yml"
}

# --- Utilities ---

reset_setup() {
    log "Resetting setup state..."
    rm -f "$DEPLOYMENTS_DIR/.flatrun/setup.json"
    rm -f "$DEPLOYMENTS_DIR/.flatrun/setup.db"
    rm -f "$DEPLOYMENTS_DIR/.flatrun/auth.db"
    rm -f "$CONFIG_DIR/config.yml"
    systemctl restart flatrun-agent 2>/dev/null || true
    log "Setup state cleared - visit :8080/setup to run the wizard again"
}

print_success() {
    local ip
    ip=$(get_public_ip)

    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  FlatRun Dev Environment${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo -e "  Dashboard:    ${GREEN}http://${ip}:8080${NC}"
    echo -e "  Agent API:    ${GREEN}http://${ip}:8090/api${NC}"
    echo ""
    echo -e "  View logs: ${YELLOW}sudo journalctl -u flatrun-agent -f${NC}"
    echo -e "  Reset:     ${YELLOW}sudo $0 reset${NC}"
    echo ""
    echo -e "${BLUE}============================================${NC}"
}

show_usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install   Install pre-built binaries and start as systemd service (default)"
    echo "  build     Build agent and UI from source only"
    echo "  run       Build from source, install, and run agent in foreground"
    echo "  reset     Clear setup state to re-run wizard"
    echo "  logs      Show agent logs"
    echo "  help      Show this help"
    echo ""
    echo "The 'install' command expects pre-built artifacts in builds/:"
    echo "  flatrun-agent    Pre-built agent binary (linux/amd64)"
    echo "  ui-dist/         Pre-built dashboard UI (npm run build output)"
    echo ""
    echo "The 'build' and 'run' commands compile from source. Paths auto-detected:"
    echo "  /src/agent + /src/ui      (Vagrant synced folders)"
    echo "  ../../agent + ../../ui    (direct checkout)"
    echo ""
    echo "Examples:"
    echo "  sudo $0                # Install pre-built artifacts + systemd"
    echo "  sudo $0 run            # Build from source + run foreground"
    echo "  $0 build               # Just compile (no root needed)"
    echo "  sudo $0 reset          # Re-run setup wizard"
}

main() {
    local cmd="${1:-install}"

    case "$cmd" in
        install)
            check_root
            install_docker
            stop_existing
            create_directories
            install_from_builds
            create_config "debug"
            create_docker_networks
            configure_systemd
            start_agent
            deploy_infrastructure
            print_success
            ;;
        build)
            detect_source_paths
            check_dependencies
            build_agent
            build_ui
            log "Build complete. Run 'sudo $0 run' to start in foreground."
            ;;
        run)
            check_root
            detect_source_paths
            check_dependencies
            build_agent
            build_ui
            stop_existing
            create_directories
            install_from_source
            create_config "debug"
            create_docker_networks
            configure_systemd
            start_agent
            deploy_infrastructure
            run_agent_foreground
            ;;
        reset)
            check_root
            reset_setup
            ;;
        logs)
            journalctl -u flatrun-agent -f
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
