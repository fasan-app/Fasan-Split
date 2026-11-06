#!/usr/bin/env python3
# Fasan Split – second half of tool/l10n_migrate.py: texts written inline in screens, `X ? 'Deutsch' : 'English'` where X is the
# language flag (`de`, `t.de`, `s.de`, `S.of(context).de`), become `trLang(X ? 'de' : 'en', 'key', [args])` with the texts in
# lib/l10n/strings_*.dart. Same meaning, no guessing: only single-quoted literals on one line; everything else is listed. MPL-2.0
import re, sys, os

LIT = r"'((?:[^'\\]|\\.)*)'"
FLAG = r"((?:S\.of\([\w.]+\)\.|\b[a-z]\w*\.)?\bde)"
INLINE = re.compile(FLAG + r" \? " + LIT + r" : " + LIT)
INTERP = re.compile(r"\$\{([^{}]*)\}|\$([A-Za-z_]\w*)")  # Dart: $a.b interpolates only a

def slug(en, used):
    words = re.findall(r"[A-Za-z]+", en)[:4] or ['text']
    base = words[0].lower() + ''.join(w.capitalize() for w in words[1:])
    k, n = base, 2
    while k in used: k, n = f'{base}{n}', n + 1
    used.add(k); return k

def main(files):
    de_add, en_add, left = [], [], []
    existing = set(re.findall(r"^  '([^']+)':", open('lib/l10n/strings_de.dart').read(), re.M))
    for path in files:
        group = os.path.splitext(os.path.basename(path))[0]
        used = {k.split('.', 1)[1] for k in existing if k.startswith(group + '.')}; src = open(path).read(); lines = src.split('\n'); changed = False
        for i, line in enumerate(lines):
            if line.lstrip().startswith('//'): continue
            def rep(m):
                flag, de, en = m.groups()
                exprs = []
                def sub(mm):
                    e = mm.group(1) or mm.group(2)
                    if e not in exprs: exprs.append(e)
                    return '{%d}' % exprs.index(e)
                if '{' in de.replace('${', '') or '{' in en.replace('${', ''): return m.group(0)
                # a quote inside ${…} ends the literal early in the pattern: leave such texts alone (unbalanced ${ = cut off)
                if any(x.count('${') != x.count('}') for x in (de, en)): return m.group(0)
                de2, en2 = INTERP.sub(sub, de), INTERP.sub(sub, en)
                key = f'{group}.{slug(en2, used)}'
                de_add.append(f"  '{key}': '{de2}',"); en_add.append(f"  '{key}': '{en2}',")
                args = ', [' + ', '.join(exprs) + ']' if exprs else ''
                return f"trLang({flag} ? 'de' : 'en', '{key}'{args})"
            new = INLINE.sub(rep, line)
            if new != line: lines[i] = new; changed = True
            if re.search(r"\bde\s*\?\s*'(?!de' : 'en')", lines[i]) or lines[i].rstrip().endswith(('de ?', '? de')): left.append(f'{path}:{i+1}: {lines[i].strip()[:100]}')
        if changed:
            out = '\n'.join(lines)
            if "l10n/tr.dart" not in out:
                rel = os.path.relpath('lib/l10n/tr.dart', os.path.dirname(path))
                out = re.sub(r"^(import '[^']+';\n)(?!import)", r"\1import '" + rel + "' show trLang;\n", out, count=1, flags=re.M) if False else out
                first = re.search(r"^import .*$", out, re.M)
                out = out[:first.start()] + f"import '{rel}' show trLang;\n" + out[first.start():]
            open(path, 'w').write(out)
    for lang, add in (('de', de_add), ('en', en_add)):
        p = f'lib/l10n/strings_{lang}.dart'
        s = open(p).read().rstrip()
        s = s[:-2].rstrip() + '\n  // --- moved from the screens by tool/l10n_inline.py ---\n' + '\n'.join(add) + '\n};\n'
        open(p, 'w').write(s)
    print(f'{len(de_add)} Texte verschoben, {len(left)} Stellen übrig:')
    for l in left: print('  ', l)

if __name__ == '__main__':
    main(sys.argv[1:])
