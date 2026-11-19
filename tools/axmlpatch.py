#!/usr/bin/env python3
# Insert <uses-library android:name="oplus.fwk" android:required="false"/>
# as the first child of <application> in a binary AndroidManifest.xml.
#
# Usage: axmlpatch.py in.xml out.xml [library_name]
import struct, sys

RES_STRING_POOL_TYPE = 0x0001
RES_XML_TYPE = 0x0003
RES_XML_START_NAMESPACE_TYPE = 0x0100
RES_XML_START_ELEMENT_TYPE = 0x0102
RES_XML_END_ELEMENT_TYPE = 0x0103

ANDROID_NS = "http://schemas.android.com/apk/res/android"


def read_chunks(data, off, end):
    chunks = []
    while off + 8 <= end:
        ctype, hsize, csize = struct.unpack_from('<HHI', data, off)
        if csize < 8 or off + csize > end:
            break
        chunks.append((ctype, hsize, csize, off))
        off += csize
    return chunks


def parse_string_pool(data, off):
    ctype, hsize, csize = struct.unpack_from('<HHI', data, off)
    assert ctype == RES_STRING_POOL_TYPE, "not a string pool"
    stringCount, styleCount, flags, stringsStart, stylesStart = struct.unpack_from('<IIIII', data, off + 8)
    utf8 = bool(flags & 0x100)
    strings = []
    for i in range(stringCount):
        o = struct.unpack_from('<I', data, off + hsize + i * 4)[0]
        p = off + stringsStart + o
        if utf8:
            n = data[p]; p += 1
            if n & 0x80:
                n = ((n & 0x7f) << 8) | data[p]; p += 1
            s = data[p:p + n].decode('utf-8', 'replace')
        else:
            n = struct.unpack_from('<H', data, p)[0]; p += 2
            s = data[p:p + n * 2].decode('utf-16-le', 'replace')
        strings.append(s)
    return dict(utf8=utf8, strings=strings, styleCount=styleCount,
                flags=flags, hsize=hsize, csize=csize, off=off)


def encode_string_pool(strings, utf8, flags):
    body = bytearray()
    offsets = []
    for s in strings:
        offsets.append(len(body))
        if utf8:
            b = s.encode('utf-8')
            if len(b) < 0x80:
                body.append(len(b))
            else:
                body.append((len(b) >> 8) | 0x80)
                body.append(len(b) & 0xFF)
            body += b
            body.append(0)
        else:
            b = s.encode('utf-16-le')
            body += struct.pack('<H', len(b) // 2)
            body += b
            body += b'\x00\x00'
    while len(body) % 4:
        body.append(0)
    header_size = 28
    count = len(strings)
    strings_start = header_size + count * 4
    out = bytearray()
    out += struct.pack('<HHI', RES_STRING_POOL_TYPE, header_size, 0)          # size fixed below
    out += struct.pack('<IIIII', count, 0, flags & ~1, strings_start, 0)      # sorted cleared
    for o in offsets:
        out += struct.pack('<I', o)
    out += body
    struct.pack_into('<I', out, 4, len(out))
    return bytes(out)


def build_uses_library(name_idx, attr_name_idx, attr_required_idx, value_idx, android_ns, line=1):
    out = bytearray()
    total = 16 + 20 + 20 * 2
    out += struct.pack('<HHI', RES_XML_START_ELEMENT_TYPE, 16, total)
    out += struct.pack('<iI', line, 0xFFFFFFFF)               # line, comment
    out += struct.pack('<II', 0xFFFFFFFF, name_idx)           # ns = none, name
    out += struct.pack('<HHHHHH', 20, 20, 2, 0, 0, 0)         # attrStart, attrSize, count, id, class, style
    # android:name = "oplus.fwk"
    out += struct.pack('<III', android_ns, attr_name_idx, value_idx)
    out += struct.pack('<HBBI', 8, 0, 0x03, value_idx)        # TYPE_STRING
    # android:required = false
    out += struct.pack('<III', android_ns, attr_required_idx, 0xFFFFFFFF)
    out += struct.pack('<HBBI', 8, 0, 0x12, 0)                # TYPE_INT_BOOLEAN
    # END_ELEMENT
    out += struct.pack('<HHI', RES_XML_END_ELEMENT_TYPE, 16, 24)
    out += struct.pack('<iI', line, 0xFFFFFFFF)
    out += struct.pack('<II', 0xFFFFFFFF, name_idx)
    return bytes(out)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    lib = sys.argv[3] if len(sys.argv) > 3 else "oplus.fwk"
    data = open(src, 'rb').read()
    mtype, header_size, file_size = struct.unpack_from('<HHI', data, 0)
    assert mtype == RES_XML_TYPE, "not an AXML"
    chunks = read_chunks(data, header_size, file_size)

    sp = None
    for c in chunks:
        if c[0] == RES_STRING_POOL_TYPE:
            sp = parse_string_pool(data, c[3]); break
    assert sp, "no string pool"
    strings = sp['strings']

    def sidx(s):
        if s in strings:
            return strings.index(s)
        strings.append(s)
        return len(strings) - 1

    name_el = sidx('uses-library')
    a_name = sidx('name')
    a_required = sidx('required')
    v_lib = sidx(lib)

    android_ns = None
    for t, h, s, o in chunks:
        if t == RES_XML_START_NAMESPACE_TYPE:
            prefix, uri = struct.unpack_from('<II', data, o + h)
            if 0 <= uri < len(strings) and strings[uri] == ANDROID_NS:
                android_ns = uri; break
    assert android_ns is not None, "android namespace not found"

    app_off = None
    for t, h, s, o in chunks:
        if t == RES_XML_START_ELEMENT_TYPE:
            ns, nm = struct.unpack_from('<II', data, o + h)
            if 0 <= nm < len(strings) and strings[nm] == 'application':
                app_off = o; break
    assert app_off is not None, "<application> not found"

    new_pool = encode_string_pool(strings, sp['utf8'], sp['flags'])
    node = build_uses_library(name_el, a_name, a_required, v_lib, android_ns)

    out = bytearray()
    out += struct.pack('<HHI', RES_XML_TYPE, 8, 0)
    for t, h, s, o in chunks:
        if sp['off'] == o:
            out += new_pool
        else:
            out += data[o:o + s]
        if o == app_off:
            out += node
    struct.pack_into('<I', out, 4, len(out))
    open(dst, 'wb').write(out)
    print("patched: added uses-library '%s' (strings %d -> %d)" % (lib, len(sp['strings']), len(strings)))


if __name__ == '__main__':
    main()
