#!/bin/bash
# Shared functions for FlatRun installer scripts

INSTALL_DIR="${INSTALL_DIR:-/opt/flatrun}"
CONFIG_DIR="${CONFIG_DIR:-/etc/flatrun}"
DEPLOYMENTS_DIR="${DEPLOYMENTS_DIR:-/opt/flatrun/deployments}"
LOG_PREFIX="${LOG_PREFIX:-FlatRun}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[${LOG_PREFIX}]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[${LOG_PREFIX}]${NC} $*"
}

log_error() {
    echo -e "${RED}[${LOG_PREFIX}]${NC} $*"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

install_docker() {
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        log "Docker is already installed and running"
        return 0
    fi

    log "Installing Docker..."

    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true
}
EOF

    systemctl enable docker
    systemctl start docker
    log "Docker installed successfully"
}

create_directories() {
    log "Creating directories..."
    mkdir -p "$INSTALL_DIR"/bin
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DEPLOYMENTS_DIR"
    mkdir -p /var/log/flatrun
}

create_config() {
    local log_level="${1:-info}"
    local jwt_secret
    jwt_secret=$(openssl rand -hex 32)
    log "Creating configuration..."
    if [ ! -f "$CONFIG_DIR/config.yml" ]; then
        cat > "$CONFIG_DIR/config.yml" << EOF
deployments_path: $DEPLOYMENTS_DIR
docker_socket: unix:///var/run/docker.sock

api:
  host: 0.0.0.0
  port: 8090
  enable_cors: true
  allowed_origins:
    - "*"

auth:
  enabled: true
  jwt_secret: ${jwt_secret}

logging:
  level: ${log_level}
  format: json

domain:
  auto_subdomain: true
  auto_ssl: true

nginx:
  enabled: true
  container_name: nginx
  image: nginx:alpine
  config_path: $DEPLOYMENTS_DIR/nginx/conf.d

certbot:
  enabled: true
  image: certbot/certbot
  staging: false
EOF
        chmod 600 "$CONFIG_DIR/config.yml"
    else
        log_warn "Configuration file already exists, skipping"
    fi
}

wait_for_agent() {
    local retries=30
    for i in $(seq 1 $retries); do
        if curl -sf http://localhost:8090/api/health > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    log_error "Agent did not become healthy after ${retries}s"
    return 1
}

deploy_infrastructure() {
    log "Deploying infrastructure..."

    wait_for_agent || return 1

    if flatrun-agent setup infra nginx --config "$CONFIG_DIR/config.yml"; then
        log "Nginx infrastructure deployed"
    else
        log_error "Failed to deploy nginx infrastructure"
        return 1
    fi
}

deploy_ui() {
    local ui_dir="$DEPLOYMENTS_DIR/ui"
    local html_src="${1:-$ui_dir/html}"

    mkdir -p "$ui_dir/html"

    if [ "$html_src" != "$ui_dir/html" ] && [ -d "$html_src" ]; then
        cp -r "$html_src"/* "$ui_dir/html/"
    fi

    cat > "$ui_dir/nginx.conf" << 'NGINXCONF'
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    location /api {
        proxy_pass http://host.docker.internal:8090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINXCONF

    cat > "$ui_dir/docker-compose.yml" << 'COMPOSE'
name: ui
services:
  ui:
    image: nginx:alpine
    container_name: flatrun-ui
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    extra_hosts:
      - "host.docker.internal:host-gateway"
COMPOSE

    log "Starting UI container..."
    docker compose -f "$ui_dir/docker-compose.yml" up -d
}

configure_systemd() {
    log "Configuring systemd service..."
    cat > /etc/systemd/system/flatrun-agent.service << EOF
[Unit]
Description=FlatRun Agent
Documentation=https://github.com/flatrun/agent
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
Group=root
ExecStart=${INSTALL_DIR}/bin/flatrun-agent --config ${CONFIG_DIR}/config.yml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=flatrun-agent
Environment=HOME=/root
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable flatrun-agent
}

stop_existing() {
    log "Stopping existing FlatRun services..."
    systemctl stop flatrun-agent 2>/dev/null || true
    pkill -f flatrun-agent 2>/dev/null || true
    docker compose -f "$DEPLOYMENTS_DIR/ui/docker-compose.yml" down 2>/dev/null || true
}

create_docker_networks() {
    log "Creating Docker networks..."
    docker network create proxy 2>/dev/null || true
    docker network create database 2>/dev/null || true
}

get_public_ip() {
    local ip
    ip=$(curl -s --connect-timeout 2 http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address 2>/dev/null || \
         curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || \
         curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || \
         hostname -I | awk '{print $1}')
    echo "$ip"
}
