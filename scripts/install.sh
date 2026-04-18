#!/bin/bash
set -euo pipefail

INSTALLER_BASE_URL="${INSTALLER_BASE_URL:-https://raw.githubusercontent.com/flatrun/installer/main/scripts}"

if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/lib.sh"
else
    LIB_CONTENT="$(curl -fsSL "$INSTALLER_BASE_URL/lib.sh")"
    eval "$LIB_CONTENT"
fi

FLATRUN_VERSION="${FLATRUN_VERSION:-latest}"
AGENT_REPO="flatrun/agent"

check_os() {
    if ! command -v apt-get &> /dev/null; then
        log_error "This installer only supports Debian/Ubuntu systems"
        exit 1
    fi
}

install_dependencies() {
    log "Installing dependencies..."
    apt-get update -qq
    apt-get install -y -qq curl jq
}

get_version() {
    if [ "$FLATRUN_VERSION" = "latest" ]; then
        log "Fetching latest version..."
        FLATRUN_VERSION=$(curl -sL "https://api.github.com/repos/$AGENT_REPO/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
        if [ -z "$FLATRUN_VERSION" ] || [ "$FLATRUN_VERSION" = "null" ]; then
            log_error "Could not determine latest version"
            exit 1
        fi
    fi
    log "Installing FlatRun v$FLATRUN_VERSION"
}

download_agent() {
    log "Downloading FlatRun Agent..."
    local arch
    arch=$(dpkg --print-architecture)
    case $arch in
        amd64) arch="amd64" ;;
        arm64) arch="arm64" ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac

    local tarball="flatrun-agent-${FLATRUN_VERSION}-linux-${arch}.tar.gz"
    local url="https://github.com/$AGENT_REPO/releases/download/v$FLATRUN_VERSION/$tarball"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    if ! curl -fsSL "$url" -o "$tmp_dir/$tarball"; then
        log_error "Failed to download agent binary"
        rm -rf "$tmp_dir"
        exit 1
    fi

    tar -xzf "$tmp_dir/$tarball" -C "$tmp_dir"
    cp "$tmp_dir/flatrun-agent-${FLATRUN_VERSION}-linux-${arch}" "$INSTALL_DIR/bin/flatrun-agent"
    chmod +x "$INSTALL_DIR/bin/flatrun-agent"
    ln -sf "$INSTALL_DIR/bin/flatrun-agent" /usr/local/bin/flatrun-agent
    rm -rf "$tmp_dir"
}

download_ui() {
    log "Deploying FlatRun UI..."
    deploy_ui
    echo "$FLATRUN_VERSION" > "$INSTALL_DIR/version"
}

print_success() {
    local ip
    ip=$(get_public_ip)

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  FlatRun installed successfully!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "  Complete setup at: ${BLUE}http://${ip}:8080/setup${NC}"
    echo ""
    echo -e "  Version: ${FLATRUN_VERSION}"
    echo -e "  Config:  ${CONFIG_DIR}/config.yml"
    echo -e "  Logs:    journalctl -u flatrun-agent -f"
    echo ""
    echo -e "${GREEN}============================================${NC}"
}

main() {
    echo ""
    echo -e "${BLUE}"
    echo "  _____ _       _   ____              "
    echo " |  ___| | __ _| |_|  _ \ _   _ _ __  "
    echo " | |_  | |/ _\` | __| |_) | | | | '_ \ "
    echo " |  _| | | (_| | |_|  _ <| |_| | | | |"
    echo " |_|   |_|\__,_|\__|_| \_\\\\__,_|_| |_|"
    echo -e "${NC}"
    echo " Container Orchestration Made Simple"
    echo ""

    check_root
    check_os
    install_dependencies
    install_docker
    get_version
    create_directories
    stop_existing
    download_agent
    download_ui
    create_config
    create_docker_networks
    configure_systemd
    systemctl start flatrun-agent
    deploy_infrastructure
    print_success
}

main "$@"
