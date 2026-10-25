"""Read original NodeCanvas JSON from the AI bundle in the supplied APK."""

import argparse
import hashlib
import json
import struct
import zipfile

import UnityPy


class Reader:
    def __init__(self, data):
        self.data = data
        self.offset = 0

    def number(self, kind):
        value = struct.unpack_from('<' + kind, self.data, self.offset)[0]
        self.offset += struct.calcsize(kind)
        return value

    def string(self):
        length = self.number('H')
        value = self.data[self.offset:self.offset + length].decode('utf-8')
        self.offset += length
        return value

    def array(self, read):
        return [read() for _ in range(self.number('H'))]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apk', required=True)
args = parser.parse_args()
with zipfile.ZipFile(args.apk) as archive:
    member = next(name for name in archive.namelist() if name.startswith('assets/yoo/DefaultPackage/DefaultPackage_') and name.endswith('.bytes'))
    manifest = archive.read(member)
    reader = Reader(manifest)
    reader.number('I')
    reader.string()
    for _ in range(3):
        reader.number('B')
    for _ in range(2):
        reader.number('i')
    for _ in range(4):
        reader.string()
    for _ in range(reader.number('i')):
        for _ in range(3):
            reader.string()
        reader.array(reader.string)
        reader.number('i')
        reader.array(lambda: reader.number('i'))
    bundles = []
    for _ in range(reader.number('i')):
        name = reader.string()
        reader.number('I')
        digest = reader.string()
        reader.string()
        reader.number('q')
        reader.number('B')
        reader.array(reader.string)
        reader.array(lambda: reader.number('i'))
        bundles.append((name, digest))
    assert reader.offset == len(manifest), 'Unexpected manifest layout'
    candidates = [(name, digest) for name, digest in bundles if name.endswith('nodecanvasres_ai.bundle')]
    assert len(candidates) == 1, 'Expected one AI bundle'
    name, digest = candidates[0]
    bundle_member = 'assets/yoo/DefaultPackage/' + digest + '.bundle'
    payload = archive.read(bundle_member)
    graphs = {}
    for obj in UnityPy.load(payload).objects:
        if obj.type.name != 'MonoBehaviour':
            continue
        tree = obj.read_typetree()
        serialized = tree.get('_serializedGraph')
        if serialized:
            assert tree['m_Name'] not in graphs, 'Duplicate graph name'
            graphs[tree['m_Name']] = {
                'path_id': str(obj.path_id),
                'serialized_sha256': hashlib.sha256(serialized.encode('utf-8')).hexdigest(),
                'graph': json.loads(serialized),
            }
    print(json.dumps({
        'manifest_member': member,
        'manifest_sha256': hashlib.sha256(manifest).hexdigest(),
        'bundle_name': name,
        'bundle_member': bundle_member,
        'bundle_sha256': hashlib.sha256(payload).hexdigest(),
        'graphs': graphs,
    }))
