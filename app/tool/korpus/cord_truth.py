# Converts CORD v2 (naver-clova-ix/cord-v2, CC-BY-4.0) receipts into truth files for test/gate_test.dart (stage B, Korpus).
# Input: a folder with NNN.jpg + NNN.json (json has gt_parse). Output: next to each image a <name>.json with
#   posten (hundredths of the currency unit like the app: "60.000" Rp = 6000000), total, posten_detail [{name, menge, betrag}],
#   waehrung "IDR", dezimalen 0, quelle. Only receipts whose items add up to the total (or to the subtotal) get a truth, so the gate
#   never tests against a broken label. Usage: python3 -I cord_truth.py <in-folder> <out-folder>
import json, os, re, shutil, sys

def num(s):
    if s is None: return None
    s = str(s).strip().replace(' ', '')
    neg = s.startswith('-') or s.startswith('(')
    d = re.sub(r'[^0-9]', '', s)
    if not d: return None
    v = int(d)
    return -v if neg else v

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
kept = skipped = 0
for f in sorted(os.listdir(src)):
    if not f.endswith('.json'): continue
    j = json.load(open(os.path.join(src, f)))
    g = j.get('gt_parse', {})
    menu = g.get('menu', [])
    if isinstance(menu, dict): menu = [menu]
    items = []
    ok = True
    for m in menu:
        name = m.get('nm')
        if isinstance(name, list): name = ' '.join(name)
        price = num(m.get('price'))
        cnt = m.get('cnt')
        try:
            q = int(float(str(cnt).replace(',', '.'))) if cnt not in (None, '') else 1
        except ValueError:
            q = 1
        if not name or price is None: ok = False; break
        # amounts like the app counts them: hundredths of the currency unit (IDR has none: 60.000 Rp = 6000000)
        items.append({'name': str(name).strip(), 'menge': max(q, 1), 'betrag': price * 100})
    def first(x):
        return (x[0] if x else {}) if isinstance(x, list) else (x or {})
    total = num(first(g.get('total')).get('total_price'))
    total = total * 100 if total is not None else None
    if not ok or not items or total is None: skipped += 1; continue
    s = sum(i['betrag'] for i in items)
    sub = num(first(g.get('sub_total')).get('subtotal_price'))
    sub = sub * 100 if sub is not None else None
    if s != total and s != sub: skipped += 1; continue
    base = 'cord-' + j['meta']['split'] + '-' + f[:-5]
    truth = {'posten': [i['betrag'] for i in items], 'total': total, 'posten_detail': items, 'waehrung': 'IDR', 'dezimalen': 0,
             'quelle': 'CORD v2 (Clova AI, CC-BY-4.0), ' + j['meta']['split'] + '/' + f[:-5],
             'summe_ist_zwischensumme': s != total}
    json.dump(truth, open(os.path.join(dst, base + '.json'), 'w'), ensure_ascii=False, indent=1)
    shutil.copy(os.path.join(src, f[:-5] + '.jpg'), os.path.join(dst, base + '.jpg'))
    kept += 1
print(f'{kept} übernommen, {skipped} ohne stimmige Wahrheit übersprungen')
