#!/usr/bin/env python3
"""Packs Lua addons into a mod-manager zip (Arsenal / HD2 Mod Manager).

  python3 tools/pack.py <mod.json> <out dir> [--header-from <a Lua patch from a working install>]

mod.json (the same shape Chef Shared Loader's own simulator reads, so its tools/modsim/modsim.py can run it too):

  {
    "name": "My Mod",                          shown in the mod manager
    "version": "0.1.0",
    "guid": "<a uuid of your own>",
    "description": "What it does. Needs Chef Shared Loader 1.0.0 or newer.",
    "thumbnail": "thumbnail.png",              optional, copied next to the manifest as its icon
    "lua": [ {"resource": "mods/you/my_mod", "file": "my_mod.lua"} ],
    "options": [                               optional: one ticked-by-default folder per option
      {"folder": "fast", "name": "Fast", "description": "...", "addon": "mods/you/my_mod", "table": "{ fast = true }"}
    ]
  }

Every Lua file's first line must be its header ("-- HD2-Addon: mods/you/my_mod", "-- HD2-Boot: ..." or
"-- HD2-Lang: ...") and name the same resource as the "resource" key. The output is byte for byte the same on every
run: sorted entries, fixed timestamps."""
import json
import os
import re
import shutil
import sys
import tempfile
import uuid
import zipfile

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hd2patch as hp  # noqa: E402

ZIP_DATE = (2026, 11, 1, 0, 0, 0)
HEADER_RE = re.compile(r'^-- HD2-(Addon|Boot|Lang): (mods/[\w\-]+(?:/[\w\-]+)+)$')
MAX_LUA = 4 * 1024 * 1024               # Chef Shared Loader skips a Lua resource over 4 MB


def die(msg):
    sys.exit('pack: ' + msg)


def read_lua(path, resource, quiet=False):
    with open(path, 'rb') as f:
        raw = f.read()
    src = raw.replace(b'\r\n', b'\n')
    if src.startswith(b'\xef\xbb\xbf'):
        src = src[3:]
    if src != raw and not quiet:
        print('pack: %s: normalized line endings / BOM (the header line has to be exactly its text)' % path)
    if len(src) > MAX_LUA:
        die('%s is %d bytes; a loader skips a Lua resource over %d' % (path, len(src), MAX_LUA))
    first = src.split(b'\n', 1)[0].decode('utf-8', 'replace')
    m = HEADER_RE.match(first)
    if not m:
        die('%s: the first line must be "-- HD2-Addon: mods/<you>/<name>" (or HD2-Boot / HD2-Lang), got %r' % (path, first))
    if m.group(2) != resource:
        die('%s: its header names %s but the spec says resource %s' % (path, m.group(2), resource))
    return src


def zip_dir(src, dest):
    paths = []
    for root, dirs, files in os.walk(src):
        dirs.sort()
        paths += [os.path.join(root, f) for f in sorted(files)]
    paths.sort(key=lambda p: os.path.relpath(p, src).replace(os.sep, '/'))
    with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED) as z:
        for full in paths:
            info = zipfile.ZipInfo(os.path.relpath(full, src).replace(os.sep, '/'), ZIP_DATE)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(full, 'rb') as f:
                z.writestr(info, f.read(), compresslevel=9)


def build(spec_path, out, header=None):
    with open(spec_path, encoding='utf-8') as f:
        spec = json.load(f)
    for key in ('name', 'version', 'guid', 'lua'):
        if key not in spec:
            die('mod.json needs "%s"' % key)
    uuid.UUID(spec['guid'])
    base = os.path.dirname(os.path.abspath(spec_path))
    stage = os.path.join(out, 'pack')
    shutil.rmtree(stage, ignore_errors=True)

    entries = []
    for item in spec['lua']:
        src = read_lua(os.path.join(base, item['file']), item['resource'])
        entries.append((hp.resource_hash(item['resource']), hp.lua_resource(src)))
    core = os.path.join(stage, 'core')
    os.makedirs(core)
    hp.write_lua_archive(os.path.join(core, hp.PATCH_NAME), entries, header)

    options = [{'Name': spec['name'] + ' (core)', 'Description': 'The mod itself. Keep this ticked.',
                'Include': ['core']}]
    for o in spec.get('options', []):
        folder = os.path.join(stage, o['folder'])
        os.makedirs(folder)
        text = ('-- HD2-Options: %s\nreturn %s\n' % (o['addon'], o['table'])).encode()
        hp.write_lua_archive(os.path.join(folder, hp.PATCH_NAME),
                             [(hp.resource_hash(o['addon'] + '/options/' + o['folder']), hp.lua_resource(text))], header)
        options.append({'Name': o['name'], 'Description': o.get('description', ''), 'Include': [o['folder']]})

    manifest = {'Version': 1, 'Guid': spec['guid'], 'Name': '%s %s' % (spec['name'], spec['version']),
                'Description': spec.get('description') or 'Needs Chef Shared Loader 1.0.0 or newer.',
                'Options': options}
    if spec.get('thumbnail'):
        shutil.copy(os.path.join(base, spec['thumbnail']), os.path.join(stage, 'thumbnail.png'))
        manifest['IconPath'] = 'thumbnail.png'
    with open(os.path.join(stage, 'manifest.json'), 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write('\n')

    dest = os.path.join(out, '%s-%s.zip' % (spec['name'].replace(' ', '-'), spec['version']))
    zip_dir(stage, dest)
    shutil.rmtree(stage)
    verify(dest, spec, base)
    return dest


def verify(dest, spec, base):
    """Opens the finished zip again and checks every Lua resource round-trips to the source it was built from."""
    with zipfile.ZipFile(dest) as z, tempfile.TemporaryDirectory() as td:
        z.extractall(td)
        _, got = hp.read_archive(os.path.join(td, 'core', hp.PATCH_NAME))
    want = {hp.resource_hash(i['resource']): read_lua(os.path.join(base, i['file']), i['resource'], quiet=True)
            for i in spec['lua']}
    if sorted(e['fid'] for e in got) != sorted(want):
        die('verify: the core patch holds different resources than the spec')
    for e in got:
        if hp.lua_source(e['data']) != want[e['fid']]:
            die('verify: resource %016x does not round-trip' % e['fid'])


def main(argv):
    header = None
    args = list(argv)
    if '--header-from' in args:
        i = args.index('--header-from')
        with open(args[i + 1], 'rb') as f:
            header = f.read(72)[12:72]
        del args[i:i + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    os.makedirs(args[1], exist_ok=True)
    print(build(args[0], args[1], header))


if __name__ == '__main__':
    main(sys.argv[1:])
