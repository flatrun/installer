#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

log_section "Configuring Systemd Service"

log "Creating systemd service file..."
cat > /etc/systemd/system/flatrun-agent.service << 'EOF'
[Unit]
Description=FlatRun Agent
Documentation=https://github.com/flatrun/agent
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/flatrun/bin/flatrun-agent --config /etc/flatrun/config.yml
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

log "Reloading systemd daemon..."
systemctl daemon-reload

log "Enabling FlatRun Agent service..."
systemctl enable flatrun-agent

log_section "Configuring MOTD"

cat > /etc/update-motd.d/99-flatrun << 'EOF'
#!/bin/bash

PUBLIC_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address 2>/dev/null || \
            curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || \
            curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || \
            hostname -I | awk '{print $1}')

cat << MOTD

  _____ _       _   ____
 |  ___| | __ _| |_|  _ \ _   _ _ __
 | |_  | |/ _\` | __| |_) | | | | '_ \
 |  _| | | (_| | |_|  _ <| |_| | | | |
 |_|   |_|\__,_|\__|_| \_\\\\__,_|_| |_|

 Container Orchestration Made Simple

 ─────────────────────────────────────────────────

 Complete setup at: http://${PUBLIC_IP}:8080/setup

 Documentation: https://flatrun.dev/docs
 Support: https://github.com/flatrun/agent/issues

 ─────────────────────────────────────────────────

MOTD
EOF

chmod +x /etc/update-motd.d/99-flatrun

log "Disabling default MOTD components..."
chmod -x /etc/update-motd.d/10-help-text 2>/dev/null || true
chmod -x /etc/update-motd.d/50-motd-news 2>/dev/null || true
chmod -x /etc/update-motd.d/88-esm-announce 2>/dev/null || true
chmod -x /etc/update-motd.d/91-contract-ua-esm-status 2>/dev/null || true

log "Systemd and MOTD configuration complete"
