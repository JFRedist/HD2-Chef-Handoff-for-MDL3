"""Tests for tools/hd2patch.py and tools/pack.py.

  python3 -I -m unittest discover -s tests -v

The hash vectors come from published ids (Chef Shared Loader's documentation, the MDL repository) and from the patch
files of two mods known to load in the game. To also rebuild real mod patches byte for byte, point HD2_FIXTURE_PATCHES
at one or more Lua-only patch files (os.pathsep separated); those tests are skipped without it."""
import json
import os
import struct
import sys
import tempfile
import unittest
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import hd2patch as hp  # noqa: E402
import pack  # noqa: E402


class HashTests(unittest.TestCase):
    VECTORS = {
        'boot': 0xF476DF93691895FA,                                         # Chef Shared Loader README
        'mods/chef_shared_loader/core_1': 0xC27789387E64579A,               # Chef Shared Loader README
        'core/wwise/lua/wwise_flow_callbacks': 0x7251FDD9BB62480A,          # MDL repository tests
        'mods/test_author/battlefield5_kill_feedback': 0x93E5D0431533CBC9,  # entry id in a working mod's patch
        'mods/miao/BF5_kill_feedback': 0xD6943546EB766CAC,                  # entry id in a working mod's patch
    }

    def test_vectors(self):
        for name, want in self.VECTORS.items():
            self.assertEqual(hp.resource_hash(name), want, name)

    def test_all_tail_lengths(self):
        # names of every length 0..17 hash without error and differ from each other
        seen = {hp.resource_hash('x' * n) for n in range(18)}
        self.assertEqual(len(seen), 18)


class ArchiveTests(unittest.TestCase):
    def build(self, entries, **kw):
        td = tempfile.TemporaryDirectory()
        self.addCleanup(td.cleanup)
        path = os.path.join(td.name, hp.PATCH_NAME)
        data = hp.write_lua_archive(path, entries, **kw)
        return path, data

    def test_layout(self):
        e1 = (hp.resource_hash('mods/a/b'), hp.lua_resource('-- HD2-Addon: mods/a/b\nreturn {}\n'))
        e2 = (hp.resource_hash('mods/a/c'), hp.lua_resource(b'x' * 33))
        path, data = self.build([e1, e2])
        magic, ntypes, n = struct.unpack_from('<III', data, 0)
        self.assertEqual((magic, ntypes, n), (hp.MAGIC, 1, 2))
        self.assertEqual(len(data) % 16, 0)
        self.assertEqual(struct.unpack_from('<I', data, 32)[0], len(data), 'the size field')
        for i in range(n):
            row = struct.unpack_from('<7Q6I', data, 72 + 32 + 80 * i)
            self.assertEqual(row[2] % 16, 0, 'entry data starts on 16 bytes')
        header, got = hp.read_archive(path)
        self.assertEqual([(e['fid'], e['data']) for e in got], [e1, e2])
        self.assertEqual(hp.lua_source(got[0]['data']), b'-- HD2-Addon: mods/a/b\nreturn {}\n')
        for ext in ('.gpu_resources', '.stream'):
            self.assertEqual(os.path.getsize(path + ext), 0)

    def test_header_is_kept_apart_from_size(self):
        hdr = bytearray(60)
        hdr[0:4] = b'\x01\x02\x03\x04'
        path, data = self.build([(1, hp.lua_resource(b'a'))], header=bytes(hdr))
        self.assertEqual(data[12:16], b'\x01\x02\x03\x04')
        self.assertEqual(struct.unpack_from('<I', data, 32)[0], len(data))

    def test_bad_header_length(self):
        with self.assertRaises(ValueError):
            self.build([(1, hp.lua_resource(b'a'))], header=bytes(59))

    def test_lua_source_rejects_bytecode_and_bad_lengths(self):
        with self.assertRaises(ValueError):
            hp.lua_source(struct.pack('<II', 1, 1) + b'a')
        with self.assertRaises(ValueError):
            hp.lua_source(struct.pack('<II', 5, 2) + b'a')


class PackTests(unittest.TestCase):
    def spec(self, td, source=None, resource='mods/me/test_mod', **extra):
        src = source if source is not None else '-- HD2-Addon: mods/me/test_mod\nreturn {}\n'
        with open(os.path.join(td, 'test_mod.lua'), 'w', newline='') as f:
            f.write(src)
        spec = {'name': 'Test Mod', 'version': '1.2.3', 'guid': 'b37ef307-a850-474f-b117-fa15df949d3f',
                'lua': [{'resource': resource, 'file': 'test_mod.lua'}]}
        spec.update(extra)
        path = os.path.join(td, 'mod.json')
        with open(path, 'w') as f:
            json.dump(spec, f)
        return path

    def test_zip_contents_and_determinism(self):
        with tempfile.TemporaryDirectory() as td:
            spec = self.spec(td, options=[{'folder': 'fast', 'name': 'Fast', 'description': 'd',
                                           'addon': 'mods/me/test_mod', 'table': '{ fast = true }'}])
            out1, out2 = os.path.join(td, 'o1'), os.path.join(td, 'o2')
            os.makedirs(out1)
            os.makedirs(out2)
            z1, z2 = pack.build(spec, out1), pack.build(spec, out2)
            with open(z1, 'rb') as f1, open(z2, 'rb') as f2:
                self.assertEqual(f1.read(), f2.read(), 'the same bytes on every build')
            self.assertEqual(os.path.basename(z1), 'Test-Mod-1.2.3.zip')
            with zipfile.ZipFile(z1) as z:
                names = sorted(z.namelist())
                self.assertEqual(names, ['core/9ba626afa44a3aa3.patch_0', 'core/9ba626afa44a3aa3.patch_0.gpu_resources',
                                         'core/9ba626afa44a3aa3.patch_0.stream', 'fast/9ba626afa44a3aa3.patch_0',
                                         'fast/9ba626afa44a3aa3.patch_0.gpu_resources',
                                         'fast/9ba626afa44a3aa3.patch_0.stream', 'manifest.json'])
                manifest = json.loads(z.read('manifest.json'))
            self.assertEqual(manifest['Version'], 1)
            self.assertEqual(manifest['Name'], 'Test Mod 1.2.3')
            self.assertEqual([o['Include'] for o in manifest['Options']], [['core'], ['fast']])

    def test_crlf_is_normalized(self):
        with tempfile.TemporaryDirectory() as td:
            spec = self.spec(td, source='-- HD2-Addon: mods/me/test_mod\r\nreturn {}\r\n')
            out = os.path.join(td, 'o')
            os.makedirs(out)
            zpath = pack.build(spec, out)
            with zipfile.ZipFile(zpath) as z:
                z.extractall(os.path.join(td, 'x'))
            _, entries = hp.read_archive(os.path.join(td, 'x', 'core', hp.PATCH_NAME))
            self.assertEqual(hp.lua_source(entries[0]['data']), b'-- HD2-Addon: mods/me/test_mod\nreturn {}\n')

    def test_header_must_match_resource(self):
        with tempfile.TemporaryDirectory() as td:
            spec = self.spec(td, resource='mods/me/other_name')
            out = os.path.join(td, 'o')
            os.makedirs(out)
            with self.assertRaises(SystemExit):
                pack.build(spec, out)

    def test_missing_header_is_refused(self):
        with tempfile.TemporaryDirectory() as td:
            spec = self.spec(td, source='return {}\n')
            out = os.path.join(td, 'o')
            os.makedirs(out)
            with self.assertRaises(SystemExit):
                pack.build(spec, out)

    def test_the_probe_package_builds(self):
        with tempfile.TemporaryDirectory() as td:
            zpath = pack.build(os.path.join(ROOT, 'probe', 'mod.json'), td)
            with zipfile.ZipFile(zpath) as z:
                z.extractall(os.path.join(td, 'x'))
            _, entries = hp.read_archive(os.path.join(td, 'x', 'core', hp.PATCH_NAME))
            self.assertEqual(entries[0]['fid'], hp.resource_hash('mods/jfredist/bfv_chef_probe'))
            src = hp.lua_source(entries[0]['data'])
            self.assertTrue(src.startswith(b'-- HD2-Addon: mods/jfredist/bfv_chef_probe\n'))
            with open(os.path.join(ROOT, 'probe', 'bfv_chef_probe.lua'), 'rb') as f:
                self.assertEqual(src, f.read())


@unittest.skipUnless(os.environ.get('HD2_FIXTURE_PATCHES'), 'set HD2_FIXTURE_PATCHES to Lua-only patch files')
class FixtureTests(unittest.TestCase):
    def test_rebuild_byte_for_byte(self):
        for path in os.environ['HD2_FIXTURE_PATCHES'].split(os.pathsep):
            with self.subTest(path=path):
                with open(path, 'rb') as f:
                    original = f.read()
                header, entries = hp.read_archive(path)
                with tempfile.TemporaryDirectory() as td:
                    out = os.path.join(td, hp.PATCH_NAME)
                    rebuilt = hp.write_lua_archive(out, [(e['fid'], e['data']) for e in entries])
                self.assertEqual(rebuilt, original)


if __name__ == '__main__':
    unittest.main()
