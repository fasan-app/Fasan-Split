#!/usr/bin/env bash
# Builds assets/fonts/FasanEmoji.ttf: a subset of Noto Color Emoji (SIL OFL 1.1, github.com/google/fonts ofl/notocoloremoji,
# COLRv1) with only the symbols used in lib/ (speisen, categories, reactions). Run again when new symbols are added.
# Needs: python3 with fonttools (pyftsubset), a sparse checkout of google/fonts with ofl/notocoloremoji. MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=${1:?Pfad zu NotoColorEmoji-Regular.ttf}
python3 - > /tmp/fasan-emoji-cps.txt <<'PY'
import glob
cs = set()
for f in glob.glob('lib/**/*.dart', recursive=True):
    cs |= {ord(c) for c in open(f, encoding='utf-8').read() if ord(c) >= 0x2600 and ord(c) != 0xFEFF}
cs |= {0xFE0F, 0x200D}
print('\n'.join('U+%04X' % c for c in sorted(cs)))
PY
pyftsubset "$SRC" --unicodes-file=/tmp/fasan-emoji-cps.txt --drop-tables+=SVG --layout-features='*' --output-file=assets/fonts/FasanEmoji.ttf
ls -la assets/fonts/FasanEmoji.ttf
