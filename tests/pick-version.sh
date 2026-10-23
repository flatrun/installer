#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib.sh

releases=tests/fixtures/agent-releases.json
failed=0

expect() {
    local channel=$1 want=$2 got
    got=$(pick_version "$channel" < "$releases" || true)
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

exit $failed
