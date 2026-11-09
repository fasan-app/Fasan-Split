#!/usr/bin/env python3
# Fasan Split – moves texts written in the code (`de ? 'Deutsch' : 'English'`) into the language tables
# lib/l10n/strings_de.dart / strings_en.dart (Aufgabe „Sprachdateien getrennt vom Code“, docs/ARCHITEKTUR.md step 6).
# Handles members of the form `String get name => de ? '…' : '…';` and `String name(args) => de ? '…' : '…';` with $x / ${expr}
# interpolation (→ {0}, {1} … plus the expressions as arguments). Anything else is left alone and listed, so nothing is changed
# by guessing. Usage: tool/l10n_migrate.py <prefix> <file.dart> …   (prefix = key group, e.g. s, collab). MPL-2.0
import re, sys

LIT = r"'((?:[^'\\]|\\.)*)'"
MEMBER = re.compile(r"^(\s*)(String (?:get (\w+)|(\w+)\(([^)]*)\))) => de \? " + LIT + r" : " + LIT + r";\s*$")
INTERP = re.compile(r"\$\{([^{}]*)\}|\$([A-Za-z_]\w*)")

def split(lit, exprs):
    def rep(m):
        e = m.group(1) or m.group(2)
        if e not in exprs: exprs.append(e)
        return '{%d}' % exprs.index(e)
    return INTERP.sub(rep, lit)

def main(prefix, files):
    de_add, en_add, skipped = [], [], []
    for path in files:
        out = []
        raw = open(path).read().split('\n')
        lines, i = [], 0
        while i < len(raw):  # `=> de` / `? '…'` / `: '…';` on three lines → one line
            if raw[i].rstrip().endswith('=> de') and i + 2 < len(raw) and raw[i + 1].strip().startswith('? ') and raw[i + 2].strip().startswith(': '):
                lines.append(raw[i].rstrip() + ' ' + raw[i + 1].strip() + ' ' + raw[i + 2].strip()); i += 3
            else:
                lines.append(raw[i]); i += 1
        for line in lines:
            m = MEMBER.match(line)
            if not m:
                if "de ? '" in line: skipped.append(f'{path}: {line.strip()[:110]}')
                out.append(line); continue
            indent, decl, gname, fname, _params, de, en = m.groups()
            name = gname or fname
            exprs = []
            de2, en2 = split(de, exprs), split(en, exprs)
            if '{' in de.replace('${', '') or '{' in en.replace('${', ''):  # literal braces would clash with {0}
                skipped.append(f'{path}: {name} (geschweifte Klammer im Text)'); out.append(line); continue
            key = f'{prefix}.{name}'
            de_add.append(f"  '{key}': '{de2}',"); en_add.append(f"  '{key}': '{en2}',")
            args = ', [' + ', '.join(exprs) + ']' if exprs else ''
            out.append(f"{indent}{decl} => text('{key}'{args});")
        open(path, 'w').write('\n'.join(out))
    for lang, add in (('de', de_add), ('en', en_add)):
        p = f'lib/l10n/strings_{lang}.dart'
        s = open(p).read().rstrip()
        assert s.endswith('};'), p
        s = s[:-2].rstrip() + f'\n  // --- moved from the code by tool/l10n_migrate.py ({prefix}) ---\n' + '\n'.join(add) + '\n};\n'
        open(p, 'w').write(s)
    print(f'{len(de_add)} Texte verschoben, {len(skipped)} übrig:')
    for s in skipped: print('  ', s)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2:])
