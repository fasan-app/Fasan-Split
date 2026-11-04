#!/usr/bin/env bash
# Fasan Split – browser end-to-end test of invitations (Nutzer 04.11.: „muss unter allen Bedingungen funktionieren“).
# Needs: a web build with --dart-define=FASAN_RELAYS=ws://127.0.0.1:7777 served at $E2E_BASE/Fasan-Split/, python3 with
# websockets, node with playwright. Local relay and local server only – nothing goes to foreign services.
# The admin creates a group and goes offline; three browsers join (normal, no service worker, no storage); the admin
# starts again and must have adopted all three. MPL-2.0
set -u
cd "$(dirname "$0")/../.."
export E2E_DIR="${E2E_DIR:-/tmp/fasan-e2e}" E2E_BASE="${E2E_BASE:-http://localhost:8765}"
mkdir -p "$E2E_DIR" && rm -f "$E2E_DIR"/*
modes="normal nosw nostorage"
FASAN_E2E_RELAY=ws://127.0.0.1:7777 FASAN_E2E_DIR="$E2E_DIR" FASAN_E2E_JOINERS=3 flutter test test/e2e_web_admin_test.dart > "$E2E_DIR/admin.log" 2>&1 &
admin=$!
fail=0
for m in $modes; do
  MODE=$m timeout 240 node tool/e2e/joiner.js > "$E2E_DIR/joiner-$m.log" 2>&1 || fail=1
  grep -E "^(OK|FAIL)" "$E2E_DIR/joiner-$m.log" || echo "FAIL mode=$m (kein Ergebnis)"
done
wait $admin || fail=1
cat "$E2E_DIR/admin.txt" 2>/dev/null; echo
tail -2 "$E2E_DIR/admin.log"
exit $fail
