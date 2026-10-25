"""Extract bounded camp configuration and ARM64 call evidence from the APK.

Requires UnityPy and capstone. Cpp2IL address stubs are optional; their offsets
are mapped through ELF PT_LOAD segments rather than treated as virtual addresses.
This performs static inspection only and never launches the package.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

import UnityPy
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM


class Reader:
    def __init__(self, data):
        self.data, self.offset = data, 0

    def number(self, fmt):
        value = struct.unpack_from('<' + fmt, self.data, self.offset)[0]
        self.offset += struct.calcsize(fmt)
        return value

    def string(self):
        size = self.number('H')
        value = self.data[self.offset:self.offset + size].decode('utf-8')
        self.offset += size
        return value

    def array(self, read):
        return [read() for _ in range(self.number('H'))]


def manifest_records(payload):
    reader = Reader(payload)
    reader.number('I')
    reader.string()
    for _ in range(3):
        reader.number('B')
    for _ in range(2):
        reader.number('i')
    for _ in range(4):
        reader.string()
    assets = []
    for _ in range(reader.number('i')):
        address, path, guid = [reader.string() for _ in range(3)]
        tags = reader.array(reader.string)
        bundle = reader.number('i')
        deps = reader.array(lambda: reader.number('i'))
        assets.append(dict(address=address, path=path, bundle=bundle))
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
        bundles.append(dict(name=name, hash=digest))
    assert reader.offset == len(payload)
    return assets, bundles


def extract(apk, stubs):
    result = {'apk_sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
              'evidence_type': 'static package configuration and ARM64 disassembly',
              'tables': {}, 'methods': []}
    names = {'RogueConfigData', 'MaterialData', 'MonsterWorkData', 'UnlockData',
             'CharTalentLevelData', 'TalentTreeData', 'TalentTreeLevelData',
             'CatMealData', 'WeaponData', 'MonsterPartnerData'}
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(n for n in archive.namelist() if n.startswith(
            'assets/yoo/DefaultPackage/DefaultPackage_') and n.endswith('.bytes'))
        payload = archive.read(manifest_name)
        result['manifest'] = {'member': manifest_name, 'sha256': hashlib.sha256(payload).hexdigest()}
        assets, bundles = manifest_records(payload)
        selected = [a for a in assets if a['address'] in names]
        for bundle_index in sorted({a['bundle'] for a in selected}):
            bundle = bundles[bundle_index]
            member = 'assets/yoo/DefaultPackage/' + bundle['hash'] + '.bundle'
            data = archive.read(member)
            for obj in UnityPy.load(data).objects:
                if obj.type.name != 'TextAsset':
                    continue
                asset = obj.read()
                if asset.m_Name not in names:
                    continue
                payload = asset.m_Script
                if isinstance(payload, bytes):
                    payload = payload.decode('utf-8-sig')
                parsed = json.loads(payload)
                if asset.m_Name == 'RogueConfigData':
                    parsed = {k: v for k, v in parsed.items() if any(
                        term in k for term in ['MainCity', 'MonsterWork', 'CharaExp',
                                               'CharaUpgrade', 'CharaLevelUp', 'BlessingExp'])}
                result['tables'][asset.m_Name] = {
                    'member': member, 'bundle_name': bundle['name'],
                    'bundle_sha256': hashlib.sha256(data).hexdigest(),
                    'path_id': obj.path_id, 'data': parsed}
        native = archive.read('lib/arm64-v8a/libil2cpp.so')
    result['native_sha256'] = hashlib.sha256(native).hexdigest()
    if not stubs.exists():
        result['native_limit'] = 'No Cpp2IL address stubs supplied.'
        return result
    phoff = struct.unpack_from('<Q', native, 32)[0]
    entsize, count = struct.unpack_from('<HH', native, 54)
    segments = []
    for i in range(count):
        typ, flags, off, va, pa, filesz, memsz, align = struct.unpack_from(
            '<IIQQQQQQ', native, phoff + i * entsize)
        if typ == 1:
            segments.append((off, off + filesz, va))

    def virtual(offset):
        return next(va + offset - lo for lo, hi, va in segments if lo <= offset < hi)

    def file_offset(address):
        return next(lo + address - va for lo, hi, va in segments if va <= address < va + hi - lo)

    literal_va = 0x1258A30
    literal_offset = file_offset(literal_va)
    result['offline_time_divisor'] = {
        'va': hex(literal_va), 'file_offset': hex(literal_offset),
        'float64': struct.unpack_from('<d', native, literal_offset)[0],
        'scope': 'Literal loaded by CalcMonsterWorkOfflineProgress; this APK version only',
    }
    result['metadata_fields'] = {}
    field_pattern = re.compile(r'\[FieldOffset\(Offset = "(0x[0-9A-F]+)"\)\]\s*'
                               r'\[Token[^\n]+\]\s*([^\n]+)')
    pattern = re.compile(r'\[Address\(RVA = "0x[0-9A-F]+", Offset = "0x([0-9A-F]+)", Length = "0x([0-9A-F]+)"\)\]\s*(?:\[[^\n]+\]\s*)+([^\n]+)')
    symbols, methods = {}, []
    selection = {
        'RogueMainCityManager': ['UpgradeMainCityLevel', 'SetSpecialEnvUnitUnlockState'],
        'ATGameManager': ['MonsterWork_', 'CalcMonsterWorkOfflineProgress', 'Update_MonsterWorkCampTime',
                          'CaculateGameResultCharaUpgradeItemGet', 'CharaToNextLevelNeedCharaUpgradeItemCount',
                          'CheckIsUnlockCharaUpgradeItemUse', 'ExcuteCharaUpgradeAndBreakUp'],
        'MonsterWorkData': ['GetCostTiem', 'GetQueueMaxCount', 'GetCompletedQueueCount'],
        'ATPanel_MonsterWork': ['<RegisterItem>b__43_6', '<RegisterItem>b__43_8', 'GetList'],
        'EnvUnit_Special_MonsterWork': ['<RegisterItem>b__4'],
        'RogueRunManager': ['HandleBattleResult'],
        'ATPanel_MainCityDeveloper': ['RedDotActive', 'OnClickBuild'],
    }
    for file in sorted(stubs.rglob('*.cs')):
        text = file.read_text()
        if file.stem in ('RogueStableData', 'RogueRunData', 'RogueMainCityManager', 'RogueConfigData'):
            result['metadata_fields'][file.stem] = {
                'source': str(file), 'sha256': hashlib.sha256(text.encode()).hexdigest(),
                'fields': [{'offset': offset, 'declaration': declaration.strip()}
                           for offset, declaration in field_pattern.findall(text)],
                'scope': 'Contains nested-class layouts; consult declarations for the owning class',
            }
        for off, length, declaration in pattern.findall(text):
            offset, length = int(off, 16), int(length, 16)
            try:
                address = virtual(offset)
            except StopIteration:
                continue
            if address not in symbols or 'get {' in symbols[address] or 'set {' in symbols[address]:
                symbols[address] = file.stem + '.' + declaration.strip()
            if any(s in declaration for s in selection.get(file.stem, [])):
                methods.append((file, offset, length, declaration.strip(), address))
    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    seen = set()
    for file, offset, length, declaration, address in methods:
        if offset in seen:
            continue
        seen.add(offset)
        instructions = []
        for ins in md.disasm(native[offset:offset + length], address):
            row = {'file_offset': hex(offset + ins.address - address),
                   'va': hex(ins.address), 'opcode': ins.mnemonic,
                   'operands': ins.op_str}
            if ins.mnemonic in ('b', 'bl') and ins.op_str.startswith('#'):
                row['callee'] = symbols.get(int(ins.op_str[1:], 16), '')
            instructions.append(row)
        result['methods'].append({'class': file.stem, 'declaration': declaration,
                                  'stub': str(file), 'file_offset': hex(offset),
                                  'va': hex(address), 'length': length,
                                  'instructions': instructions})
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', required=True, type=Path)
    parser.add_argument('--stubs', type=Path, default=Path('/tmp/city-ads-addresses/DiffableCs/Assembly-CSharp'))
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.apk, args.stubs)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'apk_sha256': result['apk_sha256'],
                      'tables': list(result['tables']), 'method_count': len(result['methods'])}))
