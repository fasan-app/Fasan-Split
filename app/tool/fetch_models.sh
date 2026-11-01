#!/usr/bin/env bash
# Holt die Modelle der Bon-Erkennung aus dem öffentlichen Repo Fasan-Karte (fester Commit) und prüft die Prüfsummen.
# Herkunft und Lizenzen: assets/models/DATEIEN.txt. Lokal: liegt Fasan-Karte daneben, wird von dort kopiert.
set -euo pipefail
cd "$(dirname "$0")/.."
REF=a35441733798cd63d59c4d4e34f398f308eb5270
BASE="https://raw.githubusercontent.com/fasan-app/Fasan-Karte/$REF/site/vendor"
mkdir -p assets/models
holen() { # name pfad sha256
  local ziel="assets/models/$1"
  if [ ! -f "$ziel" ] || [ "$(sha256sum "$ziel" | cut -d' ' -f1)" != "$3" ]; then
    if [ -f "../../fasan-karte/site/vendor/$2" ]; then cp "../../fasan-karte/site/vendor/$2" "$ziel"; else curl -fsSL --retry 3 -o "$ziel" "$BASE/$2"; fi
  fi
  echo "$3  $ziel" | sha256sum -c -
}
holen det.onnx paddle/det.onnx d7fe3ea74652890722c0f4d02458b7261d9f5ae6c92904d05707c9eb155c7924
holen rec-latin.onnx paddle/rec-latin.onnx 497dbed20b7fd86334c9deb5082c2958982a316bb16e3589ebc6502cd85cae79
holen dict-latin.txt paddle/dict-latin.txt 7274e68c7675355e45dd75c360c83faa0d0624de33a704c799a7da8897662201
holen uvdoc.onnx uvdoc/uvdoc.onnx bf9dbff2d8cd537ae2b8911c85ca3603cac5de50afc45361bd773d5230a30d05
