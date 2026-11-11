#!/usr/bin/env bash
# Browser end-to-end of hidden bills (Paket G): phone side test/e2e_web_hidden_test.dart, browser tool/e2e/hidden.js. Needs the same setup as run.sh.
# Local relay on 7777, web server on 8765, web build with FASAN_RELAYS=ws://127.0.0.1:7777. Local only. MPL-2.0
set -u
cd "$(dirname "$0")/../.."
export E2E_DIR="${E2E_DIR:-/tmp/fasan-e2e-hidden}" E2E_BASE="${E2E_BASE:-http://localhost:8765}"
mkdir -p "$E2E_DIR" && rm -f "${E2E_DIR:?}"/*
FASAN_E2E_RELAY=ws://127.0.0.1:7777 FASAN_E2E_DIR="$E2E_DIR" flutter test test/e2e_web_hidden_test.dart > "$E2E_DIR/phone.log" 2>&1 &
phone=$!
timeout 600 node tool/e2e/hidden.js > "$E2E_DIR/browser.log" 2>&1; browser=$?
wait $phone || true
grep -E "^(OK|FAIL)" "$E2E_DIR/browser.log" || echo "FAIL (kein Ergebnis)"; tail -2 "$E2E_DIR/phone.log"
exit $browser
