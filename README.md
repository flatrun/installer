# FlatRun Installer

Installation and image-building scripts for FlatRun.

## Architecture

The installer sets up three services:

- **Agent** (`:8090`) — FlatRun agent API, runs as a systemd service
- **Nginx** (`:80`, `:443`) — Reverse proxy for deployments, runs as Docker container via `flatrun-agent setup infra nginx`
- **UI** (`:8080`) — Dashboard SPA, runs as Docker container with nginx serving static files and proxying `/api` to the agent

No system nginx is used — all HTTP traffic is handled by Docker containers.

## Scripts

```
scripts/
  lib.sh          Shared functions (Docker, config, UI deploy, systemd, networks)
  install.sh      Production installer (downloads from GitHub releases)
  install-dev.sh  Dev installer with subcommands (build, run, install, reset)
  vm.sh           VM lifecycle manager (multipass/Vagrant)
  uninstall.sh    Uninstaller
```

## Quick Install

Install FlatRun on any Ubuntu/Debian server:

```bash
curl -fsSL https://raw.githubusercontent.com/flatrun/installer/main/scripts/install.sh | sudo bash
```

With a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/flatrun/installer/main/scripts/install.sh | sudo FLATRUN_VERSION=0.1.5 bash
```

## Development Testing

### Using vm.sh (recommended)

`vm.sh` manages a test VM using multipass (macOS) or Vagrant (Linux) and runs the installer scripts inside it.

```bash
cd installer

# Test production installer (downloads from GitHub releases)
./scripts/vm.sh install

# Test dev installer (requires pre-built artifacts in builds/)
./scripts/vm.sh dev

# SSH into VM
./scripts/vm.sh ssh

# Other commands
./scripts/vm.sh stop
./scripts/vm.sh destroy
./scripts/vm.sh status
./scripts/vm.sh reset       # Destroy + recreate VM
```

Force a specific backend:

```bash
./scripts/vm.sh --backend vagrant install
./scripts/vm.sh --backend multipass dev
```

### Using install-dev.sh directly

Run inside a VM or server. Subcommands:

```bash
# Install from pre-built artifacts in builds/ + start as systemd service
sudo ./scripts/install-dev.sh install

# Build agent + UI from source only (no install)
./scripts/install-dev.sh build

# Build from source + install + run in foreground (Ctrl+C to stop)
sudo ./scripts/install-dev.sh run

# Reset setup wizard state
sudo ./scripts/install-dev.sh reset

# Tail agent logs
./scripts/install-dev.sh logs
```

Source paths are auto-detected:
- `/src/agent` + `/src/ui` (Vagrant synced folders)
- `../../agent` + `../../ui` (direct checkout)

### Pre-built artifacts for `vm.sh dev`

```bash
cd agent && GOOS=linux GOARCH=amd64 go build -o ../installer/builds/flatrun-agent ./cmd/agent
cd ui && npm run build && cp -r dist ../installer/builds/ui-dist
```

### Using Vagrant directly

```bash
cd installer
vagrant up
vagrant ssh

# Inside VM:
sudo /vagrant/scripts/install.sh              # production installer
sudo /vagrant/scripts/install-dev.sh run       # build from source + foreground
sudo /vagrant/scripts/install-dev.sh reset     # re-run setup wizard

# Destroy and start fresh
vagrant destroy -f && vagrant up
```

### Access FlatRun

- Dashboard: http://VM_IP:8080
- Setup wizard: http://VM_IP:8080/setup
- API: http://VM_IP:8090/api

## Building Cloud Images

### DigitalOcean

```bash
cd packer/builds
export DIGITALOCEAN_TOKEN="your-token-here"
packer init digitalocean.pkr.hcl
packer build -var "version=0.1.5" digitalocean.pkr.hcl
```

### AWS

```bash
cd packer/builds
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
packer init aws.pkr.hcl
packer build -var "version=0.1.5" aws.pkr.hcl
```

Provisioning scripts are shared across all platforms.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/flatrun/installer/main/scripts/uninstall.sh | sudo bash
```

Or manually:

```bash
sudo systemctl stop flatrun-agent
sudo docker compose -f /opt/flatrun/deployments/ui/docker-compose.yml down
sudo systemctl disable flatrun-agent
sudo rm -rf /opt/flatrun /etc/flatrun
sudo rm /etc/systemd/system/flatrun-agent.service
sudo systemctl daemon-reload
```

## Troubleshooting

```bash
sudo systemctl status flatrun-agent    # Service status
sudo journalctl -u flatrun-agent -f    # Agent logs
docker ps                              # Running containers
docker logs nginx                      # Nginx proxy logs
docker logs flatrun-ui                 # UI container logs
docker info                            # Docker status
docker network ls                      # Networks
```

## Prerequisites

- Ubuntu 22.04 or Debian 12+
- Root/sudo access
- Ports 80, 443, 8080, 8090 available
- Docker CE (installed automatically by install.sh)
