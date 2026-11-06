#!/usr/bin/env python3
"""Checks Shared/Localizable.xcstrings against the Swift source.

Run from the repo root: python3 Tools/Localization/check.py

Fails (exit 1) when
  * a localizable literal in the source has no catalog key,
  * a plain literal reaches the screen without a key (`return "..."`, a
    ternary or `??` of literals, an implicit-return `case x: "..."`),
  * a symbolic key's defaultValue differs from its en value,
  * a catalog key is missing a language in LANGS, or
  * a translation's format specifiers do not match its key.

Literals count as localizable when they are the first argument of a SwiftUI
text API (Text, Button, Label, Section, navigationTitle, alert, ...) or of
String(localized:). Interpolations are compared loosely (%@ and %lld match
each other), because the type of an interpolated expression is not visible
without the compiler.

Escape hatches, for values that are stored data or developer-only:
  // l10n-ignore                      on the line itself
  // l10n-ignore-begin ... -end       around a block
"""
import json
import os
import re
import sys

ROOT = os.getcwd()
DIRS = ['Recharge', 'Shared', 'RechargeWatch', 'RechargeWidget', 'RechargeWatchWidget']
SKIP_PATHS = ('Recharge/Debug/',)
# Languages every key must carry. Empty until the translation runs land.
LANGS = ['fr', 'cs', 'th', 'de', 'es', 'it', 'zh-Hans']
UI_FUNCS = {'Text', 'Button', 'Label', 'Section', 'Toggle', 'TextField', 'navigationTitle', 'accessibilityLabel',
            'alert', 'DatePicker', 'Stepper', 'Link', 'configurationDisplayName', 'description', 'eyebrow',
            'confirmationDialog', 'Picker', 'LocalizedStringKey', 'accessibilityHint', 'accessibilityValue',
            'SecureField', 'primaryButton', 'navigationSubtitle', 'Menu', 'ProgressView', 'ContentUnavailableView'}
IGNORED = {'0'}
ID_LIKE = re.compile(r'^[a-z0-9_.\-/:]+$')


def parse_literal(src, i):
    """src[i] == '"'. Returns (end_index_after, segments) where segments are ('lit', str) or ('interp', expr)."""
    assert src[i] == '"'
    if src.startswith('"""', i):
        j = src.index('"""', i + 3)
        return j + 3, None
    i += 1
    segs = []; buf = ''
    while True:
        c = src[i]
        if c == '"':
            if buf: segs.append(('lit', buf))
            return i + 1, segs
        if c == '\\':
            n = src[i + 1]
            if n == '(':
                if buf: segs.append(('lit', buf)); buf = ''
                depth = 1; j = i + 2; expr = ''
                while depth:
                    ch = src[j]
                    if ch == '"':
                        k, _ = parse_literal(src, j)
                        expr += src[j:k]; j = k; continue
                    if ch == '(': depth += 1
                    elif ch == ')':
                        depth -= 1
                        if depth == 0: break
                    expr += ch; j += 1
                segs.append(('interp', expr.strip()))
                i = j + 1; continue
            if n == 'u':
                j = src.index('}', i)
                buf += chr(int(src[i + 3:j], 16)); i = j + 1; continue
            buf += {'n': '\n', 't': '\t', '"': '"', '\\': '\\', "'": "'", '0': '\0'}[n]
            i += 2; continue
        buf += c; i += 1


def line_ignores(src):
    """Set of 1-based line numbers that sit under an l10n-ignore marker."""
    skipped = set()
    inside = False
    for n, line in enumerate(src.split('\n'), 1):
        if 'l10n-ignore-begin' in line:
            inside = True
        if inside or 'l10n-ignore' in line:
            skipped.add(n)
        if 'l10n-ignore-end' in line:
            inside = False
    return skipped


def scan(path):
    """Yields (line, kind, segs, prefix). kind is a UI function name, 'String', or None for a bare literal."""
    src = open(path).read()
    out = []
    stack = []  # (funcname, argtext_since_last_comma, argindex)
    i = 0; n = len(src)
    line = 1
    line_start = 0
    while i < n:
        c = src[i]
        if c == '\n': line += 1; line_start = i + 1
        if src.startswith('//', i):
            j = src.find('\n', i); i = n if j < 0 else j; continue
        if src.startswith('/*', i):
            j = src.index('*/', i); line += src[i:j].count('\n'); i = j + 2; continue
        if c == '"':
            end, segs = parse_literal(src, i)
            if segs is not None:
                prefix = src[line_start:i]
                ctx = None
                if stack:
                    fn, argtxt, idx = stack[-1]
                    if fn == 'String' and argtxt.strip().startswith('localized:'):
                        ctx = 'String'
                    elif fn in UI_FUNCS and idx == 0 and not re.match(r'\s*[a-zA-Z_]+\s*:', argtxt):
                        ctx = fn
                    elif fn in UI_FUNCS and idx == 0 and re.match(r'\s*titleKey\s*:', argtxt):
                        ctx = fn
                out.append((line, ctx, segs, prefix))
            line += src[i:end].count('\n')
            if stack:
                f, a, k = stack[-1]; stack[-1] = (f, a + src[i:end], k)
            i = end; continue
        if c == '(':
            m = re.search(r'([A-Za-z_][A-Za-z_0-9]*)\s*$', src[max(0, i - 60):i])
            stack.append((m.group(1) if m else '', '', 0)); i += 1; continue
        if c == ')':
            if stack: stack.pop()
            i += 1; continue
        if c == ',' and stack:
            f, a, k = stack[-1]; stack[-1] = (f, '', k + 1); i += 1; continue
        if stack:
            f, a, k = stack[-1]; stack[-1] = (f, a + c, k)
        i += 1
    return out


def loose(key):
    return re.sub(r'%(\d+\$)?(lld|@|lf|f)', '%*', key)


def to_key(segs):
    has_interp = any(kind == 'interp' for kind, _ in segs)
    return ''.join((v.replace('%', '%%') if has_interp else v) if kind == 'lit' else '%@' for kind, v in segs)


def leaks_to_screen(prefix, text, prev_line):
    """True when a bare literal in this position becomes visible text with no key."""
    if not re.search(r'[A-Za-z]', text) or text.strip() == '--':
        return False
    if ID_LIKE.match(text) or '://' in text or text.startswith('?'):
        return False
    p = prefix.rstrip()
    if re.search(r'verbatim:\s*$', p) or re.search(r'(localized|defaultValue):\s*$', p):
        return False
    if re.search(r'\breturn$', p):
        return True
    if re.search(r'(\?\?|\?)$', p):
        return True
    if p.endswith(':') and '?' in p and not re.search(r'[(,]\s*\w+:$', p):
        return True
    if p.endswith(':') and re.match(r'^\s*(case\b.*|default)\s*:$', p):
        return True
    if p.strip() == '':
        prev = prev_line.strip()
        if re.match(r'^(case\b.*|default)\s*:$', prev):
            return True
        if prev.endswith('?') or re.match(r'^\?', p.strip() or prev):
            return True
    if p.strip() == ':':
        return True
    return False


def specs(value, subs=None):
    found = []
    auto = 0
    for m in re.finditer(r'%(?:(\d+)\$)?(lld|@|lf|%)|%#@(\w+)@', value):
        if m.group(2) == '%':
            continue
        if m.group(3):
            found.append((subs[m.group(3)]['argNum'], 'lld'))
            continue
        if m.group(1):
            pos = int(m.group(1))
        else:
            auto += 1
            pos = auto
        found.append((pos, m.group(2)))
    return sorted(set(found))


def main():
    catalog = json.load(open(os.path.join(ROOT, 'Shared', 'Localizable.xcstrings')))['strings']
    by_loose = {loose(k): k for k in catalog}
    problems = []
    used = set()
    for d in DIRS:
        for dirpath, _, files in os.walk(os.path.join(ROOT, d)):
            for name in sorted(files):
                if not name.endswith('.swift'):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT)
                if rel.startswith(SKIP_PATHS):
                    continue
                src_lines = open(path).read().split('\n')
                # A symbolic key carries its English twice: the catalog's en
                # value and the call's defaultValue. They must be the same text.
                for m in re.finditer(r'localized:\s*"([^"]+)",\s*defaultValue:\s*"([^"]*)"', open(path).read()):
                    en = catalog.get(m.group(1), {}).get('localizations', {}).get('en', {}).get('stringUnit', {}).get('value')
                    if en != m.group(2):
                        problems.append(f'{rel}: defaultValue {m.group(2)!r} differs from the en value {en!r} of "{m.group(1)}"')
                skipped = line_ignores(open(path).read())
                for line, ctx, segs, prefix in scan(path):
                    if line in skipped:
                        continue
                    key = to_key(segs)
                    if ctx:
                        stripped = re.sub(r'%(\d+\$)?(lld|@|lf)', '', key).replace('%%', '%')
                        if not re.search(r'[A-Za-z]', stripped) or key in IGNORED:
                            continue
                        if loose(key) in by_loose:
                            used.add(by_loose[loose(key)])
                        else:
                            problems.append(f'{rel}:{line}: no catalog key for {key!r}')
                        continue
                    prev = src_lines[line - 2] if line >= 2 else ''
                    text = ''.join(v for kind, v in segs if kind == 'lit')
                    if leaks_to_screen(prefix, text, prev):
                        problems.append(f'{rel}:{line}: literal reaches the screen without a key: {key!r}')
    for key, entry in catalog.items():
        if key not in used and loose(key) not in {loose(u) for u in used}:
            problems.append(f'"{key}": no source uses this key')
        if entry.get('extractionState') != 'manual':
            problems.append(f'"{key}": extractionState is not manual')
        locs = entry.get('localizations', {})
        if 'en' not in locs:
            problems.append(f'"{key}": missing en')
        for lang in ['en'] + LANGS:
            loc = locs.get(lang)
            if loc is None:
                if lang != 'en':
                    problems.append(f'"{key}": missing {lang}')
                continue
            want = specs(key)
            if 'variations' in loc:
                values = [u['stringUnit']['value'] for u in loc['variations']['plural'].values()]
                bad = [v for v in values if specs(v) and specs(v) != want]
            else:
                subs = loc.get('substitutions') or {}
                outer = loc['stringUnit']['value']
                bad = []
                if not subs:
                    bad = [] if specs(outer) == want else [outer]
                # A plural variant may carry the other arguments itself, so a
                # substituted sentence is judged as the outer value plus each
                # variant of each substitution.
                for sub in subs.values():
                    for unit in sub.get('variations', {}).get('plural', {}).values():
                        variant = unit['stringUnit']['value'].replace('%arg', f"%{sub['argNum']}$lld")
                        if sorted(set(specs(outer, subs)) | set(specs(variant))) != want:
                            bad.append(unit['stringUnit']['value'])
            for v in bad:
                problems.append(f'"{key}" [{lang}]: format specifiers differ in "{v}"')
    for key, entry in catalog.items():
        for lang, loc in entry.get('localizations', {}).items():
            units = [loc] + list(loc.get('variations', {}).get('plural', {}).values())
            for unit in units:
                value = unit.get('stringUnit', {}).get('value', '')
                for name in re.findall(r'%(?:\d+\$)?#@(\w+)@', value):
                    if name not in loc.get('substitutions', {}):
                        problems.append(f'"{key}" [{lang}]: plural token {name!r} has no substitution')
    for p in problems:
        print(p)
    print(f'{len(catalog)} keys, {len(LANGS)} languages, {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
