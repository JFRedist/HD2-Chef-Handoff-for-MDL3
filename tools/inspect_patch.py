#!/usr/bin/env python3
"""Read-only inspector for Helldivers 2 patch archives (the files mod managers deploy as 9ba626afa44a3aa3.patch_N).

  python3 -I tools/inspect_patch.py <patch file> [<out dir>]

Lists the type rows and entries. With an out dir it also writes every entry there (<id>.<type>.main, .gpu, .stream)
and, for Lua resources, the source text as <id>.lua. Nothing read from an archive is ever executed: run it on a
package you did not build with the file in its own directory and the script somewhere else."""
import os
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hd2patch as hp  # noqa: E402

KNOWN_TYPES = {
    0xeac0b497876adedf: 'material',
    0xcd4238c6a0c69e32: 'texture',
    0xe0a48d0be9a7453f: 'unit',
    hp.LUA_TYPE: 'lua',
    0x0d972bab10b40fd3: 'strings (a guess: 15 of them, one per language)',
    0x504b55235d21440e: 'wwise_stream',
    0x535a7bd3e650d799: 'wwise_bank',
    0xaf32095c82f2b070: 'wwise_dep',
}


def main(argv):
    if not argv:
        sys.exit(__doc__)
    path = argv[0]
    out = argv[1] if len(argv) > 1 else None
    header, entries = hp.read_archive(path)
    d = open(path, 'rb').read()
    magic, ntypes, n = struct.unpack_from('<III', d, 0)
    print('%s: %d bytes, %d type rows, %d entries' % (os.path.basename(path), len(d), ntypes, n))
    print('header after the counts: %s' % header.hex())
    for i in range(ntypes):
        _, tid, count, a, b = struct.unpack_from('<QQQII', d, 72 + 32 * i)
        print('  type %016x %-12s count=%d alignment=%d/%d' % (tid, KNOWN_TYPES.get(tid, '?'), count, a, b))
    if out:
        os.makedirs(out, exist_ok=True)
    for i, e in enumerate(entries):
        print('  entry %3d: id=%016x type=%016x main=%d gpu=%d stream=%d' % (
            i, e['fid'], e['tid'], len(e['data']), len(e['gpu']), len(e['stream'])))
        if e['tid'] == hp.LUA_TYPE:
            head = e['data'][8:8 + 70].split(b'\n', 1)[0]
            print('             lua header line: %r' % head.decode('utf-8', 'replace'))
        if out:
            stem = os.path.join(out, '%016x.%016x' % (e['fid'], e['tid']))
            with open(stem + '.main', 'wb') as f:
                f.write(e['data'])
            if e['gpu']:
                with open(stem + '.gpu', 'wb') as f:
                    f.write(e['gpu'])
            if e['stream']:
                with open(stem + '.stream', 'wb') as f:
                    f.write(e['stream'])
            if e['tid'] == hp.LUA_TYPE:
                with open(os.path.join(out, '%016x.lua' % e['fid']), 'wb') as f:
                    f.write(hp.lua_source(e['data']))


if __name__ == '__main__':
    main(sys.argv[1:])
