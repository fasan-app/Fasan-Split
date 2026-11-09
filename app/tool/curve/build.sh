#!/usr/bin/env bash
# Rebuilds web_extra/fasan-curve.js (fast secp256k1 for the browser) from entry.js and the pinned @noble/curves (package-lock.json).
# Needs node, npm and esbuild (npm i -D esbuild@0.24.0 or a global one). The result is committed; CI does not rebuild it. MPL-2.0
set -euo pipefail
cd "$(dirname "$0")"
npm ci --ignore-scripts --no-audit --no-fund
ESB=$(command -v esbuild || echo ./node_modules/.bin/esbuild)
[ -x "$ESB" ] || { npm install --no-save esbuild@0.24.0 --ignore-scripts; ESB=./node_modules/.bin/esbuild; }
"$ESB" entry.js --bundle --minify --format=iife --target=es2020 --legal-comments=none --outfile=../../web_extra/fasan-curve.js
cat node_modules/@noble/curves/LICENSE > ../../web_extra/fasan-curve.LICENSE.txt
echo >> ../../web_extra/fasan-curve.LICENSE.txt
echo "Also bundled: @noble/hashes (same license, same author)." >> ../../web_extra/fasan-curve.LICENSE.txt
rm -rf node_modules
echo "built web_extra/fasan-curve.js"
