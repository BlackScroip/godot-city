"""Inspect source native close-up controller and packaged action windows."""
from pathlib import Path
import re

# Reuse the established ELF mapping and exact Cpp2IL symbol map.
exec(Path('/tmp/city-monster-timing-disasm.py').read_text().split('wanted=')[0])
lines = ['APK camera close-up static ARM64 evidence']
for name in ('EventCameraCloseUpView', 'EventCameraFade', 'CameraCtrl_CloseUp', 'CameraCtrl_PlayerCtrl', 'BattleCameraMgr'):
    path = root / ('Teamelo/ActionEngine/' + name + '.cs')
    for off, length, decl in re.findall(r'\[Address\(RVA = "0x[0-9A-F]+", Offset = "0x([0-9A-F]+)", Length = "0x([0-9A-F]+)"\)\]\s*\[Token[^\n]+\]\s*([^\n]+)', path.read_text()):
        if name == 'BattleCameraMgr' and not any(n in decl for n in ('BindCurCtrl(', 'SetCameraFadeOffset(')): continue
        start, size = int(off,16), int(length,16)
        lines.append('\n' + name + ' ' + decl + ' file=' + off)
        for ins in md.disasm(data[start:start+size], va(start)):
            annotation = ''
            if ins.mnemonic in ('bl','b') and ins.op_str.startswith('#'):
                annotation = symbols.get(int(ins.op_str[1:],16),'')
            lines.append(f'{ins.address:x} {ins.mnemonic} {ins.op_str} ; {annotation}')
out = Path('/Users/hanyu/U3D/City/goDot/reports/APK_CAMERA_CLOSEUP_NATIVE.txt')
out.write_text('\n'.join(lines)+'\n')
print(out)
