#!/usr/bin/env python3
"""Fasan Split – compares two browser walks screenshot by screenshot (e.g. CanvasKit build against the --wasm build, or the app
against the browser): share of pixels that differ strongly. Exit 1 if a picture differs more than the limit (default 0.5 %).
Usage: compare-shots.py DIR_A DIR_B [limit_percent]. MPL-2.0"""
import os, sys
from PIL import Image, ImageChops

a, b = sys.argv[1], sys.argv[2]
limit = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
bad = 0
for f in sorted(os.listdir(a)):
    if not (f.startswith('screen-') and f.endswith('.png')) or not os.path.exists(os.path.join(b, f)):
        continue
    x, y = Image.open(os.path.join(a, f)).convert('RGB'), Image.open(os.path.join(b, f)).convert('RGB')
    if x.size != y.size:
        print(f'{f}: Größe {x.size} gegen {y.size}'); bad += 1; continue
    h = ImageChops.difference(x, y).convert('L').histogram()
    share = sum(h[40:]) * 100.0 / (x.width * x.height)
    flag = share > limit
    bad += flag
    if flag or '-v' in sys.argv:
        print(f'{f}: {share:.2f} % {"ZU GROSS" if flag else ""}')
print('abweichende Bilder:', bad)
sys.exit(1 if bad else 0)
