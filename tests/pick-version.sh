#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

releases=tests/fixtures/agent-releases.json
failed=0

expect() {
    local channel=$1 want=$2 got
    got=$(pick_version "$channel" < "$releases" || true)
    check "$channel" "$want" "$got"
}

# expect_with puts releases first, where GitHub lists the most recently created.
expect_with() {
    local extra=$1 channel=$2 want=$3 got
    got=$(jq --argjson extra "$extra" '$extra + .' "$releases" | pick_version "$channel" || true)
    check "$channel" "$want" "$got"
}

check() {
    local channel=$1 want=$2 got=$3
    if [ "$got" = "$want" ]; then
        echo "ok   $channel -> $got"
    else
        echo "FAIL $channel -> '$got', want '$want'"
        failed=1
    fi
}

expect beta 0.4.0-beta.11
expect stable 0.3.0
expect nightly ""
expect_with '[{"tag_name":"v0.3.1","prerelease":false,"draft":false}]' beta 0.4.0-beta.11
expect_with '[{"tag_name":"v0.3.1","prerelease":false,"draft":false}]' stable 0.3.1
expect_with '[{"tag_name":"v0.4.0","prerelease":false,"draft":false}]' beta 0.4.0
expect_with '[{"tag_name":"v0.4.0-beta.12","prerelease":true,"draft":true}]' beta 0.4.0-beta.11

exit $failed
