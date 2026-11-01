#!/usr/bin/env python3
"""Helldivers 2 patch archives: the resource hash and a writer/reader for Lua-only patches.

Everything here follows the on-disk layout of patch files that are known to load in the game (checked byte for byte
against mod packages that work in game, see tests/test_hd2patch.py):

    72-byte header     u32 magic 0xF0000011, u32 type count, u32 entry count, then 60 bytes of engine metadata
    32-byte type rows  u64 0, u64 type id, u64 entry count, u32 16, u32 alignment
    80-byte entry rows u64 id, u64 type, u64 data offset, u64 stream offset, u64 gpu offset, u64 0, u64 0,
                       u32 data size, u32 stream size, u32 gpu size, u32 16, u32 alignment, u32 index
    data               every entry starts on a 16-byte boundary; the file ends on one

A Lua resource's data is `u32 length, u32 2` followed by the source text (2 = plain source, not bytecode).
The resource id is the 64-bit MurmurHash64A of the resource name.

Only the standard library is used. Nothing read from an archive is ever executed."""
import struct

MAGIC = 0xF0000011
LUA_TYPE = 0xA14E8DFA2CD117E2
PATCH_NAME = '9ba626afa44a3aa3.patch_0'     # the archive name mod managers deploy Lua mods under

_MASK = (1 << 64) - 1
_M = 0xC6A4A7935BD1E995


def resource_hash(name):
    """MurmurHash64A (seed 0) of the UTF-8 resource name, as the game's resource ids are made."""
    data = name.encode('utf-8')
    h = (len(data) * _M) & _MASK
    end = len(data) // 8 * 8
    for (k,) in struct.iter_unpack('<Q', data[:end]):
        k = (k * _M) & _MASK
        k ^= k >> 47
        k = (k * _M) & _MASK
        h = ((h ^ k) * _M) & _MASK
    tail = data[end:]
    if tail:
        h = ((h ^ int.from_bytes(tail, 'little')) * _M) & _MASK
    h ^= h >> 47
    h = (h * _M) & _MASK
    h ^= h >> 47
    return h


def lua_resource(source):
    """The data of a Lua resource holding plain source text."""
    if isinstance(source, str):
        source = source.encode('utf-8')
    return struct.pack('<II', len(source), 2) + source


def default_header():
    """The 60 bytes after the entry counts (all zero but the file-size field, which write_lua_archive fills in)."""
    return bytes(60)


def _align(n, a=16):
    return -n % a


def write_lua_archive(path, entries, header=None):
    """Writes `path` (+ empty .gpu_resources and .stream) holding the Lua resources `entries`, a list of
    (resource id, resource data from lua_resource). `header` is the 60 bytes after the counts (default: zeros);
    its file-size field (offset 20 of the 60) is set to the size of the file written, as the packagers of working
    mods do. Returns the bytes of the main file."""
    header = bytearray(default_header() if header is None else header)
    if len(header) != 60:
        raise ValueError('the header after the counts is 60 bytes, got %d' % len(header))
    n = len(entries)
    head = struct.pack('<III', MAGIC, 1, n) + bytes(header)
    head += struct.pack('<QQQII', 0, LUA_TYPE, n, 16, 16)
    cursor = len(head) + 80 * n
    rows, body = bytearray(), bytearray()
    for i, (fid, data) in enumerate(entries):
        pad = _align(cursor)
        body += bytes(pad)
        cursor += pad
        rows += struct.pack('<7Q6I', fid, LUA_TYPE, cursor, 0, 0, 0, 0, len(data), 0, 0, 16, 16, i)
        body += data
        cursor += len(data)
    out = bytearray(head + rows + body)
    out += bytes(_align(len(out)))
    struct.pack_into('<I', out, 12 + 20, len(out))          # the size field
    with open(path, 'wb') as f:
        f.write(out)
    with open(path + '.gpu_resources', 'wb') as f:
        pass
    with open(path + '.stream', 'wb') as f:
        pass
    return bytes(out)


def read_archive(path):
    """-> (header bytes after the counts, [dict(fid, tid, data, gpu, stream)]) for any patch archive."""
    with open(path, 'rb') as f:
        d = f.read()

    def side(ext):
        try:
            with open(path + ext, 'rb') as f:
                return f.read()
        except FileNotFoundError:
            return b''
    gpu, stream = side('.gpu_resources'), side('.stream')
    magic, ntypes, n = struct.unpack_from('<III', d, 0)
    if magic != MAGIC:
        raise ValueError('not a patch archive (magic %#x)' % magic)
    out = []
    for i in range(n):
        (fid, tid, off, soff, goff, _u1, _u2, size, ssize, gsize, _a, _b, _i) = struct.unpack_from(
            '<7Q6I', d, 72 + 32 * ntypes + 80 * i)
        out.append(dict(fid=fid, tid=tid, data=d[off:off + size], gpu=gpu[goff:goff + gsize],
                        stream=stream[soff:soff + ssize]))
    return d[12:72], out


def lua_source(data):
    """The source text inside a Lua resource's data."""
    length, kind = struct.unpack_from('<II', data, 0)
    if kind != 2 or length != len(data) - 8:
        raise ValueError('not a plain-source Lua resource (length %d, kind %d, %d bytes)' % (length, kind, len(data)))
    return data[8:]
