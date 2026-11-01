#!/usr/bin/env python3
"""Extracts the enemy tier table of the MDL3 build (HD2_EVENT_TYPE_MAP: unit resource id -> light / medium / heavy /
flying) from its Lua source and writes it as a Lua table for the Chef side.

  python3 -I tools/extract_tiers.py <the build's Lua, e.g. extracted with tools/inspect_patch.py> [--insert probe/bfv_chef_probe.lua]

Without --insert the Lua block is printed. With it, the block between the lines
    -- @@BEGIN tiers@@
    -- @@END tiers@@
of the given file is replaced. The ids are the same 64-bit resource ids that chef.unit_kind(unit) gives (lower case hex
here, upper case in the MDL3 build): the build's own comment says its event type "is the same 64-bit resource type
rendered as sixteen hexadecimal digits"."""
import collections
import re
import sys

ROW = re.compile(r'^\s*\["([0-9A-Fa-f]{16})"\]\s*=\s*\{\s*runtime_type\s*=\s*"(\d+)",\s*kind\s*=\s*"(\w+)"')


def extract(text):
    tiers = {}
    for line in text.split('\n'):
        m = ROW.match(line)
        if m:
            k = m.group(1).lower()
            if k in tiers and tiers[k] != m.group(3):
                raise SystemExit('two tiers for %s' % k)
            tiers[k] = m.group(3)
    return tiers


def render(tiers):
    out = ['-- @@BEGIN tiers@@',
           '-- The four feedback tiers of the MDL3 build, %d unit resource ids (from its HD2_EVENT_TYPE_MAP, by' % len(tiers),
           '-- tools/extract_tiers.py: %s). Used only to say which unit kinds seen are already classified.' %
           ', '.join('%d %s' % (n, t) for t, n in sorted(collections.Counter(tiers.values()).items())),
           'local TIERS = {']
    items = ["['%s']='%s'" % (k, tiers[k]) for k in sorted(tiers)]
    for i in range(0, len(items), 3):
        out.append('  ' + ', '.join(items[i:i + 3]) + ',')
    out.append('}')
    out.append('-- @@END tiers@@')
    return '\n'.join(out)


def main(argv):
    if not argv:
        sys.exit(__doc__)
    with open(argv[0], encoding='utf-8', errors='replace') as f:
        tiers = extract(f.read())
    if not tiers:
        sys.exit('no tier rows found in ' + argv[0])
    block = render(tiers)
    if '--insert' in argv:
        target = argv[argv.index('--insert') + 1]
        with open(target, encoding='utf-8') as f:
            src = f.read()
        pat = re.compile(r'^-- @@BEGIN tiers@@.*?^-- @@END tiers@@', re.S | re.M)
        if len(pat.findall(src)) != 1:
            sys.exit('%s needs exactly one @@BEGIN tiers@@ ... @@END tiers@@ block' % target)
        with open(target, 'w', encoding='utf-8', newline='\n') as f:
            f.write(pat.sub(lambda m: block, src))
        print('%d tiers written into %s' % (len(tiers), target))
    else:
        print(block)


if __name__ == '__main__':
    main(sys.argv[1:])
