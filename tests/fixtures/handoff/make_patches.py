#!/usr/bin/env python3
"""Writes a few game patch files for tests/test_handoff.lua into <outdir>/data/ (9ba626afa44a3aa3.patch_0 ...):
  patch_0  a Chef addon like Treasure Radar: `local chef = ...`, no HD2-Requires line
  patch_1  a Chef addon with the HD2-Requires line (and no `local chef = ...` near the top), an MDL3 addon (no chef at all),
           an addon that only talks about chef in comments, and the hand-off addon itself (handoff/chef_handoff.lua)
  patch_2  not a patch file (the layout of one, a Lua entry that is a Chef addon, but not the patch magic)
  patch_3  a patch whose Lua entry is bigger than 4 MB (never read)
  patch_4  a Chef addon whose `local chef = ...` is in the first 16 KB but after a long comment
  patch_5  more entries than a mod's patch has (5000): skipped
  patch_6  addons over 16 KB (0.2.4, NarrowHUD 1.0.6): a Chef addon with `local chef = ...` after 220 KB of data, one whose
           `local chef = ...` the 16 KB mark cuts in two, and an MDL3 addon whose HD2-Requires line and indented
           `local chef = ...` come after 16 KB (neither counts there)
usage: python3 -I make_patches.py <outdir>   (run from the repository root)"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'tools'))
import hd2patch as h

out = os.path.join(sys.argv[1], 'data')
os.makedirs(out, exist_ok=True)


def write(n, entries):
    h.write_lua_archive(os.path.join(out, '9ba626afa44a3aa3.patch_%d' % n),
                        [(h.resource_hash(name), h.lua_resource(src)) for name, src in entries])


write(0, [('mods/test/radar_like', b"-- HD2-Addon: mods/test/radar_like\n-- a radar\nlocal chef = ...\nif type(chef.own_log) == 'function' then end\nreturn {}\n")])
own = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'handoff', 'chef_handoff.lua'), 'rb').read()
write(1, [('mods/test/probe_like', b"-- HD2-Addon: mods/test/probe_like\n-- HD2-Requires: chef-shared-loader >= 1.0.0\nlocal c = ...\nreturn {}\n"),
          ('mods/test/mdl3_like', b"-- HD2-Addon: mods/test/mdl3_like\nlocal sr = rawget(_G, 'stingray')\nlocal loader = rawget(_G, 'CowboyBingusModLoader')\nreturn {}\n"),
          ('mods/test/comment_mention', b"-- HD2-Addon: mods/test/comment_mention\n-- Chef addons start with `local chef = ...` and ask for -- HD2-Requires: chef-shared-loader\n--   local chef = ...\nlocal x = 1\nreturn {}\n"),
          ('mods/jfredist/chef_handoff', own)])         # the hand-off addon itself must never count as made for Chef
import struct


def wrong_magic_patch(name):
    """a file with a patch's layout and one Lua entry that is a Chef addon, but not the patch magic: it must be ignored"""
    src = ("-- HD2-Addon: %s\nlocal chef = ...\nreturn {}\n" % name).encode()
    data = struct.pack('<II', len(src), 2) + src
    head = struct.pack('<III', 0xDEADBEEF, 1, 1) + b'\0' * 60
    entry = struct.pack('<7Q6I', 1234, 0xa14e8dfa2cd117e2, 72 + 32 + 80, 0, 0, 0, 0, len(data), 0, 0, 0, 0, 0)
    return head + b'\0' * 32 + entry + data


open(os.path.join(out, '9ba626afa44a3aa3.patch_2'), 'wb').write(wrong_magic_patch('mods/test/garbage_chef'))
big = b"-- HD2-Addon: mods/test/huge_chef\nlocal chef = ...\n" + b'-- padding\n' * 400000      # about 4.4 MB
write(3, [('mods/test/huge_chef', big)])
long_comment = b"-- HD2-Addon: mods/test/late_chef\n" + b'-- a long comment line to push the code down: ' * 1 + b'x' * 300 + b'\n'
long_comment = long_comment * 1 + (b'-- more comment ' + b'y' * 60 + b'\n') * 100 + b"local chef = ...\nreturn {}\n"
write(4, [('mods/test/late_chef', long_comment)])
many = [('mods/test/filler_%d' % i, b"-- HD2-Addon: mods/test/filler_%d\nlocal chef = ...\n" % i) for i in range(5000)]
write(5, many)
# like NarrowHUD 1.0.6: a big data table first, `local chef = ...` at about 220 KB
deep = (b"-- HD2-Addon: mods/test/deep_chef\nlocal DATA = {\n" + b'  { 1, 2, 3, "some data" },\n' * 8000 + b"}\n"
        + b"local chef = ...\nreturn {}\n")
# the first 16 KB read hold 8 bytes of the resource's own header and then the text: put `\nlocal chef` across that mark
head = b"-- HD2-Addon: mods/test/split_chef\n"
split = head + b'-- filler\n' * ((16384 - 8 - len(head) - 6) // 10)
split = split + b'-' * (16384 - 8 - 6 - len(split)) + b"\nlocal chef = ...\nreturn {}\n"
assert split.index(b"\nlocal chef") + 8 < 16384 < split.index(b"chef = ...") + 8 + 4
mdl3_big = (b"-- HD2-Addon: mods/test/deep_mdl3\nlocal sr = rawget(_G, 'stingray')\n" + b'-- notes\n' * 3000
            + b"-- HD2-Requires: chef-shared-loader\nlocal function f(...)\n  local chef = ...\nend\nreturn {}\n")
write(6, [('mods/test/deep_chef', deep), ('mods/test/split_chef', split), ('mods/test/deep_mdl3', mdl3_big)])
print('wrote', sorted(os.listdir(out)))
