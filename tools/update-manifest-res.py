#!/usr/bin/env python3
"""Puts src/DBDesignerFork.manifest into src/DBDesignerFork.res.

The .res file holds the icon and the version info of the program and is
linked by DBDesignerFork.lpr ({$R src/DBDesignerFork.res}). This script
replaces (or adds) the manifest resource (type 24 = RT_MANIFEST, name 1) and
leaves every other resource as it is. Run it from the project directory
after a change of the manifest:

    python tools/update-manifest-res.py
"""
import os
import struct

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(HERE, 'src', 'DBDesignerFork.res')
MANIFEST = os.path.join(HERE, 'src', 'DBDesignerFork.manifest')
RT_MANIFEST = 24


def read_id(b, i):
    """a resource type or name: an ordinal (FFFF nnnn) or a UTF-16 string"""
    if b[i:i + 2] == b'\xff\xff':
        return struct.unpack('<H', b[i + 2:i + 4])[0], i + 4
    j = i
    while b[j:j + 2] != b'\0\0':
        j += 2
    return b[i:j].decode('utf-16le'), j + 2


def entries(b):
    i = 0
    while i < len(b):
        data_size, header_size = struct.unpack('<II', b[i:i + 8])
        rtype, j = read_id(b, i + 8)
        size = (header_size + data_size + 3) & ~3
        yield rtype, b[i:i + size].ljust(size, b'\0')
        i += size


def manifest_entry(data):
    header = struct.pack('<II', len(data), 32)
    header += struct.pack('<HH', 0xFFFF, RT_MANIFEST) + struct.pack('<HH', 0xFFFF, 1)
    # DataVersion, MemoryFlags (MOVEABLE | PURE | DISCARDABLE), LanguageId (en-US),
    # Version, Characteristics
    header += struct.pack('<IHHII', 0, 0x1030, 0x0409, 0, 0)
    entry = header + data
    return entry.ljust((len(entry) + 3) & ~3, b'\0')


def main():
    res = open(RES, 'rb').read()
    manifest = open(MANIFEST, 'rb').read()
    out = b''.join(e for rtype, e in entries(res) if rtype != RT_MANIFEST)
    out += manifest_entry(manifest)
    open(RES, 'wb').write(out)
    print('%s: %d bytes, manifest %d bytes' % (os.path.relpath(RES, HERE), len(out), len(manifest)))


if __name__ == '__main__':
    main()
