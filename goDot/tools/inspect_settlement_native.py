"""Extract bounded static settlement evidence from an explicitly supplied APK.

Address annotations come from caller-supplied Cpp2IL metadata. They are file
offsets, mapped to virtual addresses through the APK ELF's own PT_LOAD records.
The script checks matching native/metadata inputs before using the annotations.
It neither launches the APK nor changes a REA session.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM


METHOD = re.compile(
    r'\[Address\(RVA = "0x[0-9A-F]+", Offset = "0x([0-9A-F]+)", Length = "0x([0-9A-F]+)"\)\]'
    r'\s*(?:\[[^\n]+\]\s*)+([^\n]+)')
FIELD = re.compile(r'\[FieldOffset\(Offset = "(0x[0-9A-F]+)"\)\]\s*'
                   r'\[Token[^\n]+\]\s*([^\n]+)')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inspect(args):
    with zipfile.ZipFile(args.apk) as archive:
        native = archive.read('lib/arm64-v8a/libil2cpp.so')
        metadata = archive.read('assets/bin/Data/Managed/Metadata/global-metadata.dat')
    hashes = {'native': digest(native), 'metadata': digest(metadata)}
    for key, filename in [('native', 'libil2cpp.so'), ('metadata', 'global-metadata.dat')]:
        if digest((args.native_source / filename).read_bytes()) != hashes[key]:
            raise ValueError('The supplied address-source native/metadata does not match the APK: ' + key)
    phoff = struct.unpack_from('<Q', native, 32)[0]
    entsize, count = struct.unpack_from('<HH', native, 54)
    segments = []
    for i in range(count):
        typ, flags, off, va, pa, filesz, memsz, align = struct.unpack_from(
            '<IIQQQQQQ', native, phoff + i * entsize)
        if typ == 1:
            segments.append({'offset': off, 'filesz': filesz, 'va': va, 'flags': flags})

    def virtual(offset):
        return next(s['va'] + offset - s['offset'] for s in segments
                    if s['offset'] <= offset < s['offset'] + s['filesz'])

    result = {'evidence_type': 'static ARM64 disassembly and Cpp2IL metadata; no execution',
              'apk': str(args.apk), 'apk_sha256': digest(args.apk.read_bytes()),
              'member_sha256': hashes, 'matching_source_directory': str(args.native_source),
              'stubs': str(args.stubs), 'segments': segments, 'methods': [], 'fields': {}}
    symbols, methods = {}, []
    for path in sorted(args.stubs.rglob('*.cs')):
        text = path.read_text()
        if path.stem in ['RogueRunData', 'RogueStableData', 'RogueConfigData', 'ATGameManager', 'RogueRunManager']:
            result['fields'][path.stem] = {
                'source': str(path), 'sha256': digest(text.encode()),
                'fields': [{'offset': off, 'declaration': decl.strip()} for off, decl in FIELD.findall(text)],
                'scope': 'Nested classes retain source order; consult supplied source for owner.'}
        for off, length, declaration in METHOD.findall(text):
            off, length = int(off, 16), int(length, 16)
            try:
                va = virtual(off)
            except StopIteration:
                continue
            name = path.stem + '.' + declaration.strip()
            symbols.setdefault(va, name)
            if any(re.search(p, name + ' @' + hex(off)) for p in args.pattern):
                methods.append((off, length, va, name, path, digest(text.encode())))
    md, seen = Cs(CS_ARCH_ARM64, CS_MODE_ARM), set()
    for off, length, va, name, path, stub_hash in methods:
        if off in seen:
            continue
        seen.add(off)
        instructions = []
        for ins in md.disasm(native[off:off + length], va):
            row = {'file_offset': hex(off + ins.address - va), 'va': hex(ins.address),
                   'bytes': ins.bytes.hex(), 'opcode': ins.mnemonic, 'operands': ins.op_str}
            if ins.mnemonic in ('b', 'bl') and ins.op_str.startswith('#'):
                row['callee'] = symbols.get(int(ins.op_str[1:], 16), '')
            instructions.append(row)
        result['methods'].append({'name': name, 'stub': str(path), 'stub_sha256': stub_hash,
                                  'file_offset': hex(off), 'va': hex(va), 'length': hex(length),
                                  'bytes_sha256': digest(native[off:off + length]),
                                  'instructions': instructions})
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    if args.text:
        lines = [result['evidence_type'], json.dumps(hashes), 'APK ' + result['apk_sha256']]
        for method in result['methods']:
            lines += ['', method['name'], 'file=' + method['file_offset'] + ' VA=' + method['va'] +
                      ' length=' + method['length'] + ' sha256=' + method['bytes_sha256']]
            for ins in method['instructions']:
                lines.append(ins['file_offset'] + ' ' + ins['va'] + ' ' + ins['bytes'] + ' ' +
                             ins['opcode'] + ' ' + ins['operands'] +
                             (' ; ' + ins['callee'] if ins.get('callee') else ''))
        args.text.write_text('\n'.join(lines) + '\n')
    print(json.dumps({'output': str(args.output), 'methods': len(result['methods']), **hashes}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--native-source', type=Path, required=True)
    parser.add_argument('--stubs', type=Path, required=True)
    parser.add_argument('--pattern', action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--text', type=Path)
    inspect(parser.parse_args())
