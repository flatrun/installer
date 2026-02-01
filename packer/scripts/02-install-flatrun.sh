#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

FLATRUN_VERSION="${FLATRUN_VERSION:-latest}"
AGENT_REPO="flatrun/agent"
UI_REPO="flatrun/ui"
INSTALL_DIR="/opt/flatrun"
CONFIG_DIR="/etc/flatrun"
DEPLOYMENTS_DIR="/opt/flatrun/deployments"

log_section "Installing FlatRun Agent"

log "Version: $FLATRUN_VERSION"

if [ "$FLATRUN_VERSION" = "latest" ]; then
    log "Fetching latest release version..."
    FLATRUN_VERSION=$(curl -sL "https://api.github.com/repos/$AGENT_REPO/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
    if [ -z "$FLATRUN_VERSION" ] || [ "$FLATRUN_VERSION" = "null" ]; then
        log "ERROR: Could not determine latest version"
        exit 1
    fi
    log "Latest version: $FLATRUN_VERSION"
fi

ARCH=$(dpkg --print-architecture)
case $ARCH in
    amd64) ARCH_NAME="amd64" ;;
    arm64) ARCH_NAME="arm64" ;;
    *)
        log "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

log "Downloading FlatRun Agent..."
TARBALL="flatrun-agent-${FLATRUN_VERSION}-linux-${ARCH_NAME}.tar.gz"
AGENT_URL="https://github.com/$AGENT_REPO/releases/download/v$FLATRUN_VERSION/$TARBALL"
TMP_DIR=$(mktemp -d)

if curl -fsSL "$AGENT_URL" -o "$TMP_DIR/$TARBALL"; then
    tar -xzf "$TMP_DIR/$TARBALL" -C "$TMP_DIR"
    cp "$TMP_DIR/flatrun-agent-${FLATRUN_VERSION}-linux-${ARCH_NAME}" "$INSTALL_DIR/bin/flatrun-agent"
    chmod +x "$INSTALL_DIR/bin/flatrun-agent"
    ln -sf "$INSTALL_DIR/bin/flatrun-agent" /usr/local/bin/flatrun-agent
    log "Agent binary installed"
else
    log "WARNING: Could not download agent binary, will need manual installation"
fi

log "Downloading FlatRun UI..."
UI_VERSION=$(curl -sL "https://api.github.com/repos/$UI_REPO/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
if [ -z "$UI_VERSION" ] || [ "$UI_VERSION" = "null" ]; then
    UI_VERSION="$FLATRUN_VERSION"
fi

UI_DIR="$DEPLOYMENTS_DIR/ui"
mkdir -p "$UI_DIR/html"

UI_URL="https://github.com/$UI_REPO/releases/download/v${UI_VERSION}/flatrun-ui-v${UI_VERSION}.zip"
if curl -fsSL "$UI_URL" -o "$TMP_DIR/ui.zip"; then
    unzip -qo "$TMP_DIR/ui.zip" -d "$TMP_DIR/ui"
    if [ -d "$TMP_DIR/ui/dist" ]; then
        cp -r "$TMP_DIR/ui/dist"/* "$UI_DIR/html/"
    else
        cp -r "$TMP_DIR/ui"/* "$UI_DIR/html/"
    fi
    log "UI bundle installed"
else
    log "WARNING: Could not download UI bundle"
fi

rm -rf "$TMP_DIR"

log "Creating UI container configuration..."
cat > "$UI_DIR/nginx.conf" << 'NGINXCONF'
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

cat > "$UI_DIR/docker-compose.yml" << 'COMPOSE'
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

log "Creating default configuration..."
JWT_SECRET=$(openssl rand -hex 32)
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
  jwt_secret: ${JWT_SECRET}

logging:
  level: info
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

echo "$FLATRUN_VERSION" > "$INSTALL_DIR/version"

log "FlatRun installation complete"
