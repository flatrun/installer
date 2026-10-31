#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
DEPLOYMENTS_DIR="$task_tmp/deployments"
FLATRUN_UI_IMAGE="ghcr.io/flatrun/ui:test-placeholder"
real_docker=$(command -v docker)
docker() { printf '%s\n' "$*" >> "$task_tmp/docker-calls"; }

deploy_ui
compose_file="$DEPLOYMENTS_DIR/ui/docker-compose.yml"
"$real_docker" compose -f "$compose_file" config --format json > "$task_tmp/fresh.json"
jq -e '.services.ui.network_mode == "host" and .services.ui.environment.MANAGEMENT_LISTEN == "127.0.0.1:8080"' "$task_tmp/fresh.json" >/dev/null
grep -F 'listen ${MANAGEMENT_LISTEN};' "$DEPLOYMENTS_DIR/ui/nginx.conf" >/dev/null
grep -F 'proxy_pass ${AGENT_URL};' "$DEPLOYMENTS_DIR/ui/nginx.conf" >/dev/null
grep -F 'proxy_http_version 1.1;' "$DEPLOYMENTS_DIR/ui/nginx.conf" >/dev/null

cat > "$compose_file" <<'COMPOSE'
name: ui
services:
  ui:
    image: ghcr.io/flatrun/ui:previous-placeholder
    ports:
      - "127.0.0.1:18080:80"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      AGENT_URL: http://127.0.0.1:18090
  sidecar:
    image: busybox:stable
COMPOSE
cp "$compose_file" "$task_tmp/before.yml"
cp "$DEPLOYMENTS_DIR/ui/nginx.conf" "$task_tmp/before-nginx.conf"
deploy_ui
"$real_docker" compose -f "$compose_file" config --format json > "$task_tmp/upgraded.json"
jq -e '.services.ui.image == "ghcr.io/flatrun/ui:test-placeholder" and .services.sidecar.image == "busybox:stable"' "$task_tmp/upgraded.json" >/dev/null
sed 's|ghcr.io/flatrun/ui:previous-placeholder|ghcr.io/flatrun/ui:test-placeholder|' "$task_tmp/before.yml" > "$task_tmp/expected.yml"
cmp "$task_tmp/expected.yml" "$compose_file"
cmp "$task_tmp/before-nginx.conf" "$DEPLOYMENTS_DIR/ui/nginx.conf"
backup_files=("$compose_file".before-image-upgrade.*)
cmp "$task_tmp/before.yml" "${backup_files[0]}"
printf 'UI image upgrade and listener preservation passed\n'
