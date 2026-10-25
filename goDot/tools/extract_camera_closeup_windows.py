"""Bounded complete scan of source action bundles for close-up events."""
import hashlib
import json
from pathlib import Path
import zipfile
import UnityPy

ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads(Path('/tmp/city-charge-assets/manifest.json').read_text())
result = {'schema': 1, 'bundles': [], 'action_count': 0, 'windows': [], 'fade_windows': [], 'camera_events': {}}
with zipfile.ZipFile(ROOT / 'com.teamelo.dungeonchasers.apk') as archive:
    scene = next(a for a in manifest['assets'] if a['address'] == 'act')
    environment = UnityPy.Environment()
    for index in [scene['bundle'], *scene['deps']]:
        member = 'assets/yoo/DefaultPackage/' + manifest['bundles'][index]['hash'] + '.bundle'
        environment.load_file(archive.read(member))
    result['controllers'] = []
    for obj in environment.objects:
        if obj.type.name != 'MonoBehaviour': continue
        tree = obj.read_typetree()
        if 'SmoothFollowSpeed' not in tree and 'FollowTF' not in tree: continue
        result['controllers'].append({'source': f'{obj.assets_file.name}:{obj.path_id}', 'fields': tree})
    for bundle in manifest['bundles']:
        if 'actionenginecfg_action_actgroup_' not in bundle['name']: continue
        member = 'assets/yoo/DefaultPackage/' + bundle['hash'] + '.bundle'
        raw = archive.read(member)
        result['bundles'].append({'member': member, 'name': bundle['name'], 'sha256': hashlib.sha256(raw).hexdigest()})
        for obj in UnityPy.load(raw).objects:
            if obj.type.name != 'TextAsset': continue
            asset = obj.read()
            payload = asset.m_Script
            if isinstance(payload, bytes): payload = payload.decode('utf-8-sig')
            try: action = json.loads(payload)
            except (ValueError, TypeError): continue
            if not isinstance(action, dict) or 'Events' not in action: continue
            result['action_count'] += 1
            for event in action['Events']:
                event_type = event.get('EventType')
                if 'Camera' in str(event_type):
                    result['camera_events'][event_type] = result['camera_events'].get(event_type, 0) + 1
                if event_type not in ('EET_CameraCloseUpView', 11, 'EET_CameraFade'): continue
                kind = 'fade_windows' if event_type == 'EET_CameraFade' else 'windows'
                result[kind].append({'asset': asset.m_Name, 'action': action.get('ActId'), 'total_ms': action.get('TotalTime'), 'event': event, 'source': f'{obj.assets_file.name}:{obj.path_id}'})
out = ROOT / 'goDot/assets/data/camera_closeup.json'
out.write_text(json.dumps(result, indent=2) + '\n')
print(result['action_count'], 'actions;', len(result['windows']), 'close-up windows;', result['camera_events'])
