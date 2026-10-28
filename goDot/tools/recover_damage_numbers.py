"""Extract the shipped damage glyphs and dodge caption without executing the APK."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr
from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


def recover(apk, output):
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(apk) as archive:
        manifest = archive.read(next(n for n in archive.namelist() if n.startswith(
            'assets/yoo/DefaultPackage/DefaultPackage_') and n.endswith('.bytes')))
        assets, bundles = manifest_records(manifest)
        asset = next(a for a in assets if a['address'] == 'PopEffect_Damage')
        deps, edges = package_dependencies(manifest, asset['address'])
        pending, seen, objects = [asset['bundle'], *deps], set(), []
        env = UnityPy.Environment()
        while pending:
            index = pending.pop()
            if index in seen:
                continue
            seen.add(index)
            pending.extend(edges[index])
            loaded = env.load_file(archive.read('assets/yoo/DefaultPackage/' + bundles[index]['hash'] + '.bundle'))
            for cab in loaded.files.values():
                if hasattr(cab, 'objects'):
                    objects.extend(cab.objects.values())
        glyphs = {}
        for obj in objects:
            if obj.type.name != 'MonoBehaviour':
                continue
            tree = obj.read_typetree()
            if obj.path_id == -4280675585639441827:
                (output/'source_font.json').write_text(json.dumps({
                    'asset_name': tree['m_Name'], 'path_id': str(obj.path_id),
                    'face': tree['m_FaceInfo'], 'source_guid': tree['m_SourceFontFileGUID']}, indent=2)+'\n')
                pointer = tree.get('m_SourceFontFile')
                if pointer and pointer['m_PathID']:
                    font = PPtr(**pointer, assetsfile=obj.assets_file).deref().read_typetree()
                    if font.get('m_FontData'):
                        (output/'source_font.ttf').write_bytes(bytes(font['m_FontData']))
                        print('Source font:', font['m_Name'])
            name = tree.get('m_Name', '')
            if name not in ['spriteatlas_damagetext_group', 'spriteatlas_bufftext_group']:
                continue
            atlas = PPtr(**tree['spriteSheet'], assetsfile=obj.assets_file).deref().read().image
            by_id = {g['m_Index']: g for g in tree['m_SpriteGlyphTable']}
            for char in tree['m_SpriteCharacterTable']:
                key = char['m_Name']
                if name == 'spriteatlas_bufftext_group' and key != 'buff_shanbi':
                    continue
                glyph = by_id[char['m_GlyphIndex']]
                rect = glyph['m_GlyphRect']
                x, y, w, h = (rect[k] for k in ['m_X', 'm_Y', 'm_Width', 'm_Height'])
                atlas.crop((x, atlas.height-y-h, x+w, atlas.height-y)).save(output/(key+'.png'))
                glyphs[key] = {'width': w, 'height': h, 'scale': char['m_Scale'], 'metrics': glyph['m_Metrics']}
        result = {'apk_sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
                  'asset': asset, 'glyphs': glyphs,
                  'evidence': 'Static Unity TMP sprite tables and texture pixels; no APK runtime observation.'}
        (output/'glyphs.json').write_text(json.dumps(result, indent=2)+'\n')
        print('Extracted', len(glyphs), 'glyphs')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    recover(args.apk, args.output)
