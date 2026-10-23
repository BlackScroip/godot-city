#!/usr/bin/env python3
"""Convert recovered Unity YAML into glTF scenes without altering the source.

Run with Recovery/AssetAnalysis/venv/bin/python. Geometry, skinning and sampled
TRS animation are real recovered data. Unity-only behavior is recorded, not
silently represented as an equivalent Godot implementation.
"""
import argparse
import collections
import functools
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import traceback
from types import SimpleNamespace

import numpy as np
import yaml

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'goDot/assets'
REPORTS = ROOT / 'goDot/reports'
SOURCE = ROOT / 'RecoveredUnity/ExportedProject/Assets'
OFFLINE = ROOT / 'OfflineUnity/Assets'
RESOURCE = SOURCE / '_00002_Resource'
VERSION = 'unity-glb-13'
HEADER = re.compile(r'^--- !u!(\d+) &(-?\d+)(?: stripped)?\s*$', re.M)
SPEC = importlib.util.spec_from_file_location('recovered_mesh_decoder', ROOT / 'Recovery/Tools/repair_offline_meshes.py')
REPAIR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPAIR)
INDEX = {}
DEPENDENCIES = set()
WARNINGS = []
MEDIA = {'textures': {}, 'audio': {}, 'fonts': {}}


def warn(kind, **kwargs):
    WARNINGS.append(dict(kind=kind, **kwargs))


@functools.lru_cache(maxsize=32768)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(path):
    return str(path.relative_to(ROOT))


@functools.lru_cache(maxsize=24)
def load_documents(path):
    path = Path(path)
    text = path.read_text()
    marks = list(HEADER.finditer(text))
    result = []
    for number, match in enumerate(marks):
        end = marks[number + 1].start() if number + 1 < len(marks) else len(text)
        chunk = text[match.end():end]
        if path.suffix == '.anim':
            fields = list(re.finditer(r'^  ([A-Za-z_][A-Za-z_0-9]*):', chunk, re.M))
            wanted = {'m_Name', 'm_RotationCurves', 'm_PositionCurves', 'm_ScaleCurves',
                      'm_AnimationClipSettings', 'm_SampleRate', 'm_Events'}
            selected = ['AnimationClip:\n']
            for i, field in enumerate(fields):
                if field[1] in wanted:
                    selected.append(chunk[field.start():fields[i+1].start() if i+1 < len(fields) else len(chunk)])
            chunk = ''.join(selected)
        doc = yaml.load(chunk, Loader=yaml.CSafeLoader)
        result.append((int(match[1]), int(match[2]), next(iter(doc.values()))))
    return result


def body(path):
    return load_documents(str(path))[0][2]


def material_surface(material, mat):
    props = mat.get('m_SavedProperties', {})
    def values(name):
        result = props.get(name, {})
        return {key: value for row in result for key, value in row.items()} if isinstance(result, list) else result
    floats, colors = values('m_Floats'), values('m_Colors')
    color = colors.get('_BaseColor', colors.get('_Color', {}))
    rgba = [max(0.0, min(1.0, float(color.get(key, 1)))) for key in 'rgba']
    # Unity's serialized inspector colors are sRGB; glTF factors are linear.
    material['pbrMetallicRoughness']['baseColorFactor'] = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in rgba[:3]] + rgba[3:]
    keywords = set(mat.get('m_ValidKeywords', [])) | set(str(mat.get('m_ShaderKeywords', '')).split())
    cutout = bool(floats.get('_Cutout', 0) or floats.get('_AlphaClip', 0) or floats.get('_AlphaClipEnable', 0) or floats.get('_Mode') == 1 or keywords.intersection({'CUTOUT', '_ALPHATEST_ON', '_ALPHACLIP_ON'}))
    blend = floats.get('_Mode') in (2, 3) or floats.get('_Surface') == 1 or rgba[3] < 1 or floats.get('_ZWrite') == 0 or bool(keywords.intersection({'_ALPHABLEND_ON', '_ALPHAPREMULTIPLY_ON', 'TRANSPARENCY'}))
    material.pop('alphaMode', None)
    material.pop('alphaCutoff', None)
    if cutout:
        material.update(alphaMode='MASK', alphaCutoff=max(0.0, min(1.0, float(floats.get('_Cutoff', 0.5)))))
    elif blend:
        material['alphaMode'] = 'BLEND'
    material.setdefault('extras', {})['colorFactorSpace'] = 'Unity inspector sRGB converted to glTF linear RGB; alpha unchanged'


def refresh_materials(data):
    count = 0
    for material in data.get('materials', []):
        source = material.get('extras', {}).get('unitySource')
        if source and (ROOT / source).is_file():
            material_surface(material, body(ROOT / source))
            count += 1
    return count


def resolve(ref):
    guid = (ref or {}).get('guid')
    path = INDEX.get(guid)
    if path:
        DEPENDENCIES.add(path)
    return path


def index_assets():
    # Prefer repaired offline mesh copies; other source assets retain original
    # controllers, animation events, shaders and serialized behavior evidence.
    for root in (SOURCE, OFFLINE):
        for meta in root.rglob('*.meta'):
            match = re.search(r'^guid: ([0-9a-f]{32})$', meta.read_text(), re.M)
            path = meta.with_suffix('')
            if match and path.is_file() and (root == SOURCE or path.suffix == '.asset' or match[1] not in INDEX):
                INDEX[match[1]] = path


def xyzw(value, default=(0, 0, 0, 1)):
    return [float(value.get(k, default[i])) for i, k in enumerate('xyzw')]


def xyz(value, default=(0, 0, 0)):
    return [float(value.get(k, default[i])) for i, k in enumerate('xyz')]


def trs_matrix(node):
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    rotation = np.array([[1-2*y*y-2*z*z, 2*x*y-2*z*w, 2*x*z+2*y*w],
                         [2*x*y+2*z*w, 1-2*x*x-2*z*z, 2*y*z-2*x*w],
                         [2*x*z-2*y*w, 2*y*z+2*x*w, 1-2*x*x-2*y*y]], dtype=np.float64)
    result = np.eye(4)
    result[:3, :3] = rotation @ np.diag(node.get('scale', [1, 1, 1]))
    result[:3, 3] = node.get('translation', [0, 0, 0])
    return result


def copy_media(path, group):
    if str(path) in MEDIA[group]:
        return ROOT / 'goDot' / MEDIA[group][str(path)]['path'].removeprefix('res://')
    sha = digest(path)
    suffix = path.suffix.lower()
    target = OUT / group / (sha[:20] + suffix)
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        shutil.copyfile(path, target)
    MEDIA[group][str(path)] = dict(path='res://' + str(target.relative_to(ROOT / 'goDot')), sha256=sha)
    return target


@functools.lru_cache(maxsize=256)
def decode_mesh(path):
    result = REPAIR.read_mesh(path)
    if result is None:
        return None
    mesh = result[1]['Mesh']
    handler = REPAIR.decode(mesh)
    handler.src.m_SubMeshes = [SimpleNamespace(**part) for part in mesh['m_SubMeshes']]
    handler.m_Use16BitIndices = mesh.get('m_IndexFormat', 0) == 0
    return mesh, handler


def builtin_mesh(ident):
    vertices, normals, uvs, triangles = [], [], [], []
    if ident == 10209:
        for row in range(11):
            for column in range(11):
                vertices.append([column-5, 0, row-5])
                normals.append([0, 1, 0])
                uvs.append([column/10, row/10])
        for row in range(10):
            for column in range(10):
                at = row*11+column
                triangles.extend([(at, at+11, at+1), (at+1, at+11, at+12)])
        name = 'UnityBuiltinPlane_10x10'
    elif ident == 10202:
        for normal, u, v in [([1,0,0],[0,1,0],[0,0,1]), ([-1,0,0],[0,0,1],[0,1,0]),
                             ([0,1,0],[0,0,1],[1,0,0]), ([0,-1,0],[1,0,0],[0,0,1]),
                             ([0,0,1],[1,0,0],[0,1,0]), ([0,0,-1],[0,1,0],[1,0,0])]:
            start = len(vertices)
            for a, b in [(-.5,-.5),(.5,-.5),(.5,.5),(-.5,.5)]:
                vertices.append([normal[i]*.5+u[i]*a+v[i]*b for i in range(3)])
                normals.append(normal)
                uvs.append([a+.5,b+.5])
            triangles.extend([(start,start+1,start+2),(start,start+2,start+3)])
        name = 'UnityBuiltinCube_1x1x1'
    else:
        return None
    handler = SimpleNamespace(m_Vertices=vertices, m_Normals=normals, m_Tangents=[], m_Colors=[],
                              m_UV0=uvs, m_UV1=[], m_BoneWeights=[], m_BoneIndices=[],
                              get_triangles=lambda: [triangles])
    return dict(m_Name=name, m_BindPose=[], m_Shapes={}), handler


class Gltf:
    def __init__(self, target):
        self.target = target
        self.data = dict(asset=dict(version='2.0', generator=VERSION), scene=0,
                         scenes=[dict(nodes=[])], nodes=[], meshes=[], materials=[],
                         bufferViews=[], accessors=[], buffers=[dict(byteLength=0)])
        self.binary = bytearray()
        self.material_cache = {}
        self.geometry_cache = {}
        self.image_cache = {}
        self.position_bounds = []
        self.skin_count = 0
        self.animation_info = []
        self.markers = []
        self.unsupported = collections.Counter()
        self.current_source = None

    def accessor(self, values, kind, dtype='<f4', target=None, bounds=False):
        values = np.asarray(values, dtype=dtype)
        if not np.isfinite(values).all():
            raise ValueError('Non-finite glTF accessor')
        payload = values.tobytes()
        self.binary.extend(b'\0' * ((-len(self.binary)) % 4))
        view = dict(buffer=0, byteOffset=len(self.binary), byteLength=len(payload))
        if target:
            view['target'] = target
        self.binary.extend(payload)
        self.data['bufferViews'].append(view)
        component = {'<f4': 5126, '<u4': 5125, '<u2': 5123, '|u1': 5121}[np.dtype(dtype).str]
        result = dict(bufferView=len(self.data['bufferViews'])-1, componentType=component,
                      count=len(values), type=kind)
        if bounds:
            if values.ndim == 1:
                result.update(min=[float(values.min())], max=[float(values.max())])
            else:
                result.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        self.data['accessors'].append(result)
        return len(self.data['accessors'])-1

    def texture(self, path):
        if path in self.image_cache:
            return self.image_cache[path]
        target = copy_media(path, 'textures')
        self.data.setdefault('images', []).append(dict(uri=os.path.relpath(target, self.target.parent)))
        self.data.setdefault('textures', []).append(dict(source=len(self.data['images'])-1,
                                                        sampler=0))
        self.data['samplers'] = [dict(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497)]
        self.image_cache[path] = len(self.data['textures'])-1
        return self.image_cache[path]

    def material(self, ref):
        path = resolve(ref)
        key = str(path)
        if key in self.material_cache:
            return self.material_cache[key]
        mat = body(path) if path else {}
        props = mat.get('m_SavedProperties', {})
        tex = props.get('m_TexEnvs', {})
        floats = props.get('m_Floats', {})
        colors = props.get('m_Colors', {})
        if isinstance(tex, list):
            tex = {k: v for row in tex for k, v in row.items()}
        if isinstance(floats, list):
            floats = {k: v for row in floats for k, v in row.items()}
        if isinstance(colors, list):
            colors = {k: v for row in colors for k, v in row.items()}
        color = colors.get('_BaseColor', colors.get('_Color', {}))
        base = [max(0.0, min(1.0, float(color.get(k, 1)))) for k in 'rgba']
        pbr = dict(baseColorFactor=base, metallicFactor=0.0, roughnessFactor=0.8)
        material = dict(name=mat.get('m_Name', 'Default'), pbrMetallicRoughness=pbr,
                        doubleSided=True)
        for name in ('_BaseMap', '_MainTex', '_BaseColorMap', '_Albedo'):
            binding = tex.get(name, {})
            image = resolve(binding.get('m_Texture', {}))
            if image and image.suffix.lower() in ('.png', '.jpg', '.jpeg'):
                info = dict(index=self.texture(image))
                scale, offset = binding.get('m_Scale', {}), binding.get('m_Offset', {})
                sx, sy = float(scale.get('x', 1)), float(scale.get('y', 1))
                ox, oy = float(offset.get('x', 0)), float(offset.get('y', 0))
                if (sx, sy, ox, oy) != (1, 1, 0, 0):
                    info['extensions'] = {'KHR_texture_transform': dict(scale=[sx, sy], offset=[ox, 1-sy-oy])}
                    self.data.setdefault('extensionsUsed', [])
                    if 'KHR_texture_transform' not in self.data['extensionsUsed']:
                        self.data['extensionsUsed'].append('KHR_texture_transform')
                pbr['baseColorTexture'] = info
                break
        material['extras'] = dict(unitySource=identity(path) if path else None,
                                 shaderAppearance='PBR approximation; original shader not executable')
        material_surface(material, mat)
        self.data['materials'].append(material)
        self.material_cache[key] = len(self.data['materials'])-1
        return self.material_cache[key]

    def geometry(self, ref, materials, skinned=False):
        path = resolve(ref)
        builtin = None
        if not path and str(ref.get('guid', '')).startswith('0000000000000000'):
            builtin = builtin_mesh(ref.get('fileID'))
        if not path:
            if ref.get('fileID', 0) and not builtin:
                warn('missing_mesh', source=str(self.current_source), reference=ref)
            if not builtin:
                return None, None
        key = (str(path) if path else 'builtin:'+str(ref.get('fileID')), tuple(x.get('guid') for x in materials), skinned)
        if key in self.geometry_cache:
            return self.geometry_cache[key]
        result = builtin or decode_mesh(path)
        if result is None:
            warn('unsupported_mesh_format', path=identity(path))
            return None, None
        mesh, handler = result
        positions = np.asarray(handler.m_Vertices, dtype=np.float32)[:, :3]
        attrs = dict(POSITION=self.accessor(positions, 'VEC3', target=34962, bounds=True))
        normals = handler.m_Normals
        if normals and len(normals) == len(positions):
            attrs['NORMAL'] = self.accessor(np.asarray(normals)[:, :3], 'VEC3', target=34962)
        if handler.m_Tangents and len(handler.m_Tangents) == len(positions):
            tangents = np.asarray(handler.m_Tangents).copy()
            if tangents.shape[1] == 4:
                tangents[:, 3] *= -1
                attrs['TANGENT'] = self.accessor(tangents, 'VEC4', target=34962)
        for number in range(2):
            uv = getattr(handler, 'm_UV' + str(number), None)
            if uv and len(uv) == len(positions) and len(uv[0]) >= 2:
                uv = np.asarray(uv)[:, :2].copy()
                uv[:, 1] = 1-uv[:, 1]
                attrs['TEXCOORD_' + str(number)] = self.accessor(uv, 'VEC2', target=34962)
        if handler.m_Colors and len(handler.m_Colors) == len(positions):
            cols = np.asarray(handler.m_Colors)
            if cols.shape[1] in (3, 4):
                attrs['COLOR_0'] = self.accessor(np.clip(cols, 0, 1), 'VEC'+str(cols.shape[1]), target=34962)
        if skinned and handler.m_BoneWeights and handler.m_BoneIndices:
            weights = np.asarray(handler.m_BoneWeights, dtype=np.float64)
            weights /= np.maximum(weights.sum(axis=1, keepdims=True), 1e-20)
            attrs['WEIGHTS_0'] = self.accessor(weights, 'VEC4', target=34962)
            attrs['JOINTS_0'] = self.accessor(handler.m_BoneIndices, 'VEC4', '<u2', 34962)
        primitives = []
        triangles = handler.get_triangles()
        for number, faces in enumerate(triangles):
            if not faces:
                continue
            indices = np.asarray(faces, dtype=np.uint32).reshape(-1)
            primitive = dict(attributes=attrs.copy(), indices=self.accessor(indices, 'SCALAR', '<u4', 34963), mode=4)
            if materials:
                primitive['material'] = self.material(materials[min(number, len(materials)-1)])
            primitives.append(primitive)
        if not primitives:
            warn('empty_mesh', path=identity(path))
            return None, None
        output = dict(name=mesh['m_Name'], primitives=primitives,
                      extras=dict(unitySource=identity(path) if path else key[0], blendShapeCount=len(mesh.get('m_Shapes', {}).get('channels', []))))
        self.data['meshes'].append(output)
        info = dict(mesh=mesh, positions=positions, handler=handler)
        value = len(self.data['meshes'])-1, info
        self.geometry_cache[key] = value
        return value

    def prefab(self, path):
        self.current_source = path
        DEPENDENCIES.add(path)
        docs = load_documents(str(path))
        objects = {ident: (kind, value) for kind, ident, value in docs}
        games = {ident: value for kind, ident, value in docs if kind == 1}
        transforms = {ident: value for kind, ident, value in docs if kind in (4, 224)}
        nodes = {}
        game_to_transform = {}
        disabled = set()
        for ident, transform in transforms.items():
            game_id = transform['m_GameObject']['fileID']
            game = games.get(game_id, {})
            game_to_transform[game_id] = ident
            if not game.get('m_IsActive', 1):
                disabled.add(ident)
            node = dict(name=game.get('m_Name', 'Node'), translation=xyz(transform.get('m_LocalPosition', {})),
                        rotation=xyzw(transform.get('m_LocalRotation', {})),
                        scale=xyz(transform.get('m_LocalScale', {}), (1, 1, 1)),
                        extras=dict(unityFileID=str(ident), unityActive=bool(game.get('m_IsActive', 1))))
            nodes[ident] = len(self.data['nodes'])
            self.data['nodes'].append(node)
        roots, paths = [], {}

        def node_path(ident):
            if ident in paths:
                return paths[ident]
            parent = transforms[ident].get('m_Father', {}).get('fileID', 0)
            name = self.data['nodes'][nodes[ident]]['name']
            paths[ident] = (node_path(parent) + '/' if parent in transforms else '') + name
            return paths[ident]

        def active(ident):
            while ident in transforms:
                if ident in disabled:
                    return False
                ident = transforms[ident].get('m_Father', {}).get('fileID', 0)
            return True

        @functools.lru_cache(maxsize=None)
        def world(ident):
            parent = transforms[ident].get('m_Father', {}).get('fileID', 0)
            matrix = trs_matrix(self.data['nodes'][nodes[ident]])
            return world(parent) @ matrix if parent in transforms else matrix

        for ident, transform in transforms.items():
            parent = transform.get('m_Father', {}).get('fileID', 0)
            if parent in nodes:
                self.data['nodes'][nodes[parent]].setdefault('children', []).append(nodes[ident])
            else:
                roots.append(nodes[ident])
            node_path(ident)
        self.data['scenes'][0]['nodes'].extend(roots)
        renderer_by_game = {value['m_GameObject']['fileID']: value for kind, _, value in docs if kind == 23}
        for kind, ident, component in docs:
            game_id = component.get('m_GameObject', {}).get('fileID')
            transform_id = game_to_transform.get(game_id)
            if transform_id is None:
                continue
            if kind in (33, 137):
                renderer = component if kind == 137 else renderer_by_game.get(game_id, {})
                if not active(transform_id) or not renderer.get('m_Enabled', 1):
                    continue
                try:
                    mesh_index, info = self.geometry(component.get('m_Mesh', {}), renderer.get('m_Materials', []), kind == 137)
                    if mesh_index is None:
                        continue
                    node = self.data['nodes'][nodes[transform_id]]
                    node['mesh'] = mesh_index
                    positions = info['positions']
                    points = np.concatenate((positions.min(axis=0)[None, :], positions.max(axis=0)[None, :]), axis=0)
                    corners = np.asarray([[points[x, 0], points[y, 1], points[z, 2], 1] for x in range(2) for y in range(2) for z in range(2)])
                    transformed = (world(transform_id) @ corners.T).T[:, :3]
                    self.position_bounds.append((transformed.min(axis=0), transformed.max(axis=0)))
                    if kind == 137 and 'JOINTS_0' in self.data['meshes'][mesh_index]['primitives'][0]['attributes']:
                        bone_refs = component.get('m_Bones', [])
                        joints = [nodes.get(ref['fileID']) for ref in bone_refs]
                        for slot, joint in enumerate(joints):
                            if joint is not None:
                                continue
                            bone_indices = np.asarray(info['handler'].m_BoneIndices)
                            weights = np.asarray(info['handler'].m_BoneWeights)
                            if np.any(weights[bone_indices == slot] > 1e-6):
                                raise ValueError('Weighted skin joint references bone outside prefab')
                            joints[slot] = len(self.data['nodes'])
                            self.data['nodes'].append(dict(name='UnusedUnityBone_'+str(slot)))
                            parent = nodes.get(component.get('m_RootBone', {}).get('fileID'), roots[0])
                            self.data['nodes'][parent].setdefault('children', []).append(joints[slot])
                            self.unsupported['source_unweighted_null_bone'] += 1
                        bindposes = info['mesh']['m_BindPose']
                        if len(joints) != len(bindposes):
                            raise ValueError('Bone/BindPose count differs')
                        matrices = [[pose['e'+str(r)+str(c)] for c in range(4) for r in range(4)] for pose in bindposes]
                        skin = dict(joints=joints, inverseBindMatrices=self.accessor(matrices, 'MAT4'))
                        skeleton = nodes.get(component.get('m_RootBone', {}).get('fileID'))
                        if skeleton is not None:
                            skin['skeleton'] = skeleton
                        self.data.setdefault('skins', []).append(skin)
                        node['skin'] = len(self.data['skins'])-1
                        self.skin_count += 1
                except Exception as error:
                    warn('mesh_conversion_failed', source=identity(path), component=str(ident), error=str(error))
            elif kind in (64, 65, 135, 136, 146, 154, 156):
                marker = dict(kind=kind, fileID=str(ident), node=nodes[transform_id],
                              path=paths[transform_id], active=active(transform_id),
                              world_matrix=world(transform_id).reshape(16).tolist(), properties=component)
                self.markers.append(marker)
            elif kind not in (1, 4, 224, 23, 95, 108, 205):
                self.unsupported[str(kind)] += 1
        aliases = {}
        for ident, path_name in paths.items():
            parts = path_name.split('/')
            for start in range(len(parts)):
                aliases.setdefault('/'.join(parts[start:]), nodes[ident])
        aliases[''] = roots[0] if roots else 0
        return aliases

    def animation(self, path, name, aliases):
        DEPENDENCIES.add(path)
        clip = body(path)
        tracks = []
        duration = float(clip.get('m_AnimationClipSettings', {}).get('m_StopTime', 0))
        for field, target in [('m_PositionCurves', 'translation'), ('m_RotationCurves', 'rotation'), ('m_ScaleCurves', 'scale')]:
            for curve in clip.get(field, []):
                node = aliases.get(curve.get('path', ''))
                if node is None:
                    self.unsupported['animation_unbound_path'] += 1
                    continue
                keys = curve.get('curve', {}).get('m_Curve', [])
                if not keys:
                    continue
                duration = max(duration, max(float(key['time']) for key in keys))
                tracks.append((node, target, keys))
        if not tracks or duration <= 0:
            return
        rate = max(30, min(60, float(clip.get('m_SampleRate', 30))))
        times = np.linspace(0, duration, max(2, int(math.ceil(duration*rate))+1), dtype=np.float32)
        animation = dict(name=name, channels=[], samplers=[], extras=dict(unitySource=identity(path),
                         loop=bool(clip.get('m_AnimationClipSettings', {}).get('m_LoopTime', 0)),
                         events=clip.get('m_Events', []), sampledRate=rate))
        time_accessor = self.accessor(times, 'SCALAR', bounds=True)
        for node, target, keys in tracks:
            dimensions = 4 if target == 'rotation' else 3
            axes = 'xyzw'[:dimensions]
            result, cursor = [], 0
            for time in times:
                while cursor+1 < len(keys)-1 and float(keys[cursor+1]['time']) < float(time):
                    cursor += 1
                first = keys[cursor]
                second = keys[min(cursor+1, len(keys)-1)]
                t0, t1 = float(first['time']), float(second['time'])
                alpha = max(0, min(1, (float(time)-t0)/(t1-t0))) if t1 > t0 else 0
                value = []
                for axis in axes:
                    a, b = float(first['value'].get(axis, 0)), float(second['value'].get(axis, 0))
                    slope_a = float(first.get('outSlope', {}).get(axis, 0))
                    slope_b = float(second.get('inSlope', {}).get(axis, 0))
                    if not math.isfinite(slope_a) or not math.isfinite(slope_b):
                        v = a if alpha < 1 else b
                    else:
                        v = (2*alpha**3-3*alpha**2+1)*a + (alpha**3-2*alpha**2+alpha)*(t1-t0)*slope_a
                        v += (-2*alpha**3+3*alpha**2)*b + (alpha**3-alpha**2)*(t1-t0)*slope_b
                    value.append(v)
                if dimensions == 4:
                    magnitude = math.sqrt(sum(v*v for v in value))
                    value = [v/max(magnitude, 1e-20) for v in value]
                    if result and sum(a*b for a, b in zip(result[-1], value)) < 0:
                        value = [-v for v in value]
                result.append(value)
            output = self.accessor(result, 'VEC'+str(dimensions))
            animation['samplers'].append(dict(input=time_accessor, output=output, interpolation='LINEAR'))
            animation['channels'].append(dict(sampler=len(animation['samplers'])-1, target=dict(node=node, path=target)))
        self.data.setdefault('animations', []).append(animation)
        self.animation_info.append(dict(name=name, duration=duration, loop=animation['extras']['loop'], tracks=len(tracks)))
        for field in ('m_FloatCurves', 'm_EulerCurves', 'm_PPtrCurves'):
            if clip.get(field):
                self.unsupported[field] += len(clip[field])

    def save(self):
        self.target.parent.mkdir(parents=True, exist_ok=True)
        self.binary.extend(b'\0' * ((-len(self.binary)) % 4))
        self.data['buffers'][0]['byteLength'] = len(self.binary)
        payload = json.dumps(self.data, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()
        payload += b' ' * ((-len(payload)) % 4)
        header = struct.pack('<III', 0x46546c67, 2, 12+8+len(payload)+8+len(self.binary))
        self.target.write_bytes(header+struct.pack('<II', len(payload), 0x4e4f534a)+payload+
                                struct.pack('<II', len(self.binary), 0x004e4942)+self.binary)
        if self.position_bounds:
            low = np.min([item[0] for item in self.position_bounds], axis=0)
            high = np.max([item[1] for item in self.position_bounds], axis=0)
        else:
            low = high = np.zeros(3)
        return dict(path='res://' + str(self.target.relative_to(ROOT / 'goDot')), animations=self.animation_info,
                    bounds=dict(min=low.tolist(), max=high.tolist(), size=(high-low).tolist()),
                    meshes=len(self.data['meshes']), nodes=len(self.data['nodes']), skins=self.skin_count,
                    unsupported=dict(self.unsupported), bytes=self.target.stat().st_size)


def controller_animations(prefab):
    animations = []
    for kind, _, component in load_documents(str(prefab)):
        if kind != 95:
            continue
        controller = resolve(component.get('m_Controller', {}))
        if not controller:
            continue
        for state_kind, _, state in load_documents(str(controller)):
            if state_kind == 1102:
                path = resolve(state.get('m_Motion', {}))
                if path and path.suffix == '.anim':
                    animations.append((path, state['m_Name']))
    return animations


def defaults(animations):
    result = {}
    names = [item['name'] for item in animations]
    for target, hints in {'idle': ('_idle', '@idle', 'idle', 'inited'), 'run': ('_run', '@run', 'move_forward', 'moveforward', 'move', 'run'),
                          'attack': ('_attack1', '@attack1', 'attack1', 'attack')}.items():
        for hint in hints:
            match = next((name for name in names if name.lower() == hint or name.lower().endswith(hint)), None)
            if match:
                result[target] = match
                break
    return result


def normalize_animation_names(data, result):
    used = set()
    for number, animation in enumerate(data.get('animations', [])):
        original = animation.get('extras', {}).get('unityAnimationName', animation.get('name', 'animation'))
        base = re.sub(r'[^A-Za-z0-9_]+', '_', original).strip('_') or 'animation'
        # Godot removes these suffixes even after trailing duplicate numbers.
        if re.search(r'_(loop_mode|loop|cycle)$', re.sub(r'[0-9_]+$', '', base), re.I):
            base += '_clip'
        name, suffix = base, 2
        while name in used:
            name = base+'__'+str(suffix)
            suffix += 1
        used.add(name)
        animation.setdefault('extras', {}).setdefault('unityAnimationName', original)
        animation['name'] = name
        if number < len(result.get('animations', [])):
            result['animations'][number]['name'] = name
            result['animations'][number]['source_name'] = original
    result['default_animations'] = defaults(result.get('animations', []))


def write_glb(target, data, binary):
    data['asset']['generator'] = VERSION
    payload = json.dumps(data, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()
    payload += b' ' * ((-len(payload)) % 4)
    target.write_bytes(struct.pack('<III', 0x46546c67, 2, 28+len(payload)+len(binary))+
                       struct.pack('<II', len(payload), 0x4e4f534a)+payload+
                       struct.pack('<II', len(binary), 0x004e4942)+binary)


def collision_faces(ref):
    path = resolve(ref)
    decoded = decode_mesh(path) if path else builtin_mesh(ref.get('fileID'))
    if decoded is None:
        return None
    guid = ref.get('guid', 'builtin')
    ident = str(ref.get('fileID', 0))
    target = OUT / 'collisions' / (guid+'_'+ident+'.faces.json')
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        mesh, handler = decoded
        positions = np.asarray(handler.m_Vertices, dtype=np.float32)[:, :3]
        triangles = [face for group in handler.get_triangles() for face in group]
        indices = np.asarray(triangles, dtype=np.uint32).reshape(-1)
        if len(indices) == 0:
            return None
        faces = positions[indices].reshape(-1).tolist()
        target.write_text(json.dumps(dict(source_guid=guid, source_fileID=ident,
                          source=identity(path) if path else 'Unity builtin '+ident,
                          source_sha256=digest(path) if path else None,
                          coordinate_space='Unity native numeric xyz', faces=faces), separators=(',', ':')))
    return 'res://' + str(target.relative_to(ROOT / 'goDot'))


def enrich_environment(target, data, raw_markers=None):
    if target.parent.name != 'environments':
        return
    for node in data['nodes']:
        extra = node.setdefault('extras', {})
        file_id = extra.get('unityFileID')
        if file_id is not None:
            original = extra.setdefault('unityName', node['name'])
            safe = re.sub(r'[^A-Za-z0-9_]+', '_', original).strip('_') or 'Node'
            node['name'] = safe+'__u'+str(file_id).replace('-', 'n')
    marker_path = target.with_suffix('.markers.json')
    if raw_markers is None:
        raw_markers = json.loads(marker_path.read_text())['markers'] if marker_path.exists() else []
    for marker in raw_markers:
        marker['exported_node_name'] = data['nodes'][marker['node']]['name']
        if marker['kind'] == 64:
            ref = marker['properties'].get('m_Mesh', {})
            marker['mesh_guid'] = ref.get('guid')
            marker['mesh_fileID'] = str(ref.get('fileID', 0))
            resource = collision_faces(ref)
            if resource:
                marker['mesh_faces_path'] = resource
            elif ref.get('fileID', 0):
                warn('missing_collision_mesh', source=str(target), reference=ref)
    parents = {child: parent for parent, node in enumerate(data['nodes']) for child in node.get('children', [])}
    @functools.lru_cache(maxsize=None)
    def source_path(index):
        node = data['nodes'][index]
        name = node.get('extras', {}).get('unityName', node['name'])
        return (source_path(parents[index])+'/' if index in parents else '')+name
    @functools.lru_cache(maxsize=None)
    def world(index):
        matrix = trs_matrix(data['nodes'][index])
        return world(parents[index]) @ matrix if index in parents else matrix
    semantic = [dict(marker) for marker in semantic_markers() if marker['SceneName'] == target.stem]
    roots = {marker['Path'][0] for marker in semantic if marker.get('Path')}
    paths = collections.defaultdict(list)
    for index in range(len(data['nodes'])):
        parts = source_path(index).split('/')
        for number, part in enumerate(parts):
            if part in roots:
                paths['/'.join(parts[number:])].append(index)
    for marker in semantic:
        candidates = paths.get('/'.join(marker['Path']), [])
        if len(candidates) != 1:
            mapped_game_id = semantic_identity_maps().get(target.stem, {}).get(marker.get('SourceGameObjectId'))
            if mapped_game_id is not None:
                prefab = OFFLINE / 'Campaign/Recovered/Scenes' / (target.stem+'.prefab')
                transform_games = {str(ident): component['m_GameObject']['fileID']
                                   for kind, ident, component in load_documents(str(prefab)) if kind in (4, 224)}
                exact = [index for index in candidates if transform_games.get(data['nodes'][index].get('extras', {}).get('unityFileID')) == mapped_game_id]
                if len(exact) == 1:
                    candidates = exact
        if len(candidates) == 1:
            index = candidates[0]
            marker.update(node=index, exported_node_name=data['nodes'][index]['name'],
                          world_matrix=world(index).reshape(16).tolist(), world_position=world(index)[:3, 3].tolist())
        else:
            marker['binding_candidates'] = candidates
    marker_path.write_text(json.dumps(dict(coordinate_space='Unity native numeric xyz',
                            world_matrix_layout='row-major; transform local point by matrix times column vector',
                            exported_node_lookup='unique exported_node_name below imported scene root',
                            markers=raw_markers, semantic_markers=semantic), ensure_ascii=False))


@functools.lru_cache(maxsize=1)
def semantic_markers():
    return json.loads((OFFLINE / 'Campaign/Resources/CampaignMarkers.json').read_text())['Markers']


@functools.lru_cache(maxsize=1)
def semantic_identity_maps():
    source = json.loads((ROOT / 'Recovery/Reports/campaign-prefab-fileid-map.json').read_text())
    return {scene['name']: scene['sourceFileIdToPrefabFileId'] for scene in source['scenes']}


def convert_asset(prefab, target, animations=None, markers=False):
    DEPENDENCIES.clear()
    cache_file = target.with_suffix('.conversion.json')
    if cache_file.exists() and target.exists():
        previous = json.loads(cache_file.read_text())
        reusable = (not animations or previous['result'].get('skins', 0) > 0) and all(Path(key).exists() and digest(Path(key)) == value for key, value in previous.get('dependencies', {}).items())
        accepted = (VERSION, 'unity-glb-7', 'unity-glb-9', 'unity-glb-10', 'unity-glb-11', 'unity-glb-12')
        if reusable and previous.get('version') in accepted:
            if previous.get('version') != VERSION:
                payload = bytearray(target.read_bytes())
                json_length = struct.unpack_from('<I', payload, 12)[0]
                data = json.loads(payload[20:20+json_length])
                binary_start = 28+json_length
                if previous.get('version') == 'unity-glb-7':
                    seen = set()
                    for mesh in data['meshes']:
                        for primitive in mesh['primitives']:
                            index = primitive['indices']
                            if index in seen:
                                continue
                            seen.add(index)
                            accessor = data['accessors'][index]
                            view = data['bufferViews'][accessor['bufferView']]
                            width = 4 if accessor['componentType'] == 5125 else 2
                            start = binary_start+view.get('byteOffset', 0)+accessor.get('byteOffset', 0)
                            for offset in range(start, start+accessor['count']*width, 3*width):
                                a, b = offset+width, offset+2*width
                                payload[a:a+width], payload[b:b+width] = payload[b:b+width], payload[a:a+width]
                normalize_animation_names(data, previous['result'])
                refresh_materials(data)
                enrich_environment(target, data)
                write_glb(target, data, payload[binary_start:])
                previous['version'] = VERSION
                previous['dependencies'].update({str(path): digest(path) for path in DEPENDENCIES})
                previous['result']['bytes'] = target.stat().st_size
                cache_file.write_text(json.dumps(previous, ensure_ascii=False, indent=2))
            return previous['result']
    gltf = Gltf(target)
    aliases = gltf.prefab(prefab)
    seen = set()
    for animation_path, name in animations or []:
        if name not in seen:
            gltf.animation(animation_path, name, aliases)
            seen.add(name)
    result = gltf.save()
    normalize_animation_names(gltf.data, result)
    if markers:
        enrich_environment(target, gltf.data, gltf.markers)
    write_glb(target, gltf.data, gltf.binary)
    result['bytes'] = target.stat().st_size
    result.update(source=identity(prefab), source_sha256=digest(prefab), default_animations=defaults(result['animations']))
    if markers:
        marker_path = target.with_suffix('.markers.json')
        result['markers'] = 'res://' + str(marker_path.relative_to(ROOT / 'goDot'))
        result['colliders'] = len(gltf.markers)
    deps = {str(path): digest(path) for path in DEPENDENCIES}
    cache_file.write_text(json.dumps(dict(version=VERSION, dependencies=deps, result=result), ensure_ascii=False, indent=2))
    return result


def write_catalog(catalog):
    destination = OUT / 'catalog.json'
    if destination.exists():
        current = json.loads(destination.read_text())
        for group in ('characters', 'enemies', 'environments', 'weapons', 'audio'):
            merged = current.get(group, {}).copy()
            merged.update(catalog.get(group, {}))
            catalog[group] = merged
        current.update(catalog)
        catalog = current
    temporary = destination.with_suffix('.'+str(os.getpid())+'.tmp')
    temporary.write_text(json.dumps(catalog, ensure_ascii=False, indent=2))
    temporary.replace(destination)


def validate_outputs():
    records, failures = [], []
    totals = collections.Counter()
    collision_resources = set()
    for path in sorted(OUT.rglob('*.glb')):
        try:
            payload = path.read_bytes()
            magic, version, length = struct.unpack_from('<III', payload)
            assert magic == 0x46546c67 and version == 2 and length == len(payload), 'Invalid GLB header'
            json_length, json_type = struct.unpack_from('<II', payload, 12)
            assert json_type == 0x4e4f534a
            data = json.loads(payload[20:20+json_length])
            binary_start = 28+json_length
            binary_length, binary_type = struct.unpack_from('<II', payload, 20+json_length)
            assert binary_type == 0x004e4942 and binary_start+binary_length == length
            arrays = {}

            def read(index):
                if index in arrays:
                    return arrays[index]
                accessor = data['accessors'][index]
                view = data['bufferViews'][accessor['bufferView']]
                dimensions = {'SCALAR':1, 'VEC2':2, 'VEC3':3, 'VEC4':4, 'MAT4':16}[accessor['type']]
                dtype = {5126:'<f4', 5125:'<u4', 5123:'<u2', 5121:'|u1'}[accessor['componentType']]
                start = binary_start+view.get('byteOffset', 0)+accessor.get('byteOffset', 0)
                size = np.dtype(dtype).itemsize*dimensions*accessor['count']
                assert start+size <= binary_start+view.get('byteOffset', 0)+view['byteLength'], 'Accessor exceeds buffer view'
                result = np.frombuffer(payload, dtype=dtype, count=accessor['count']*dimensions, offset=start)
                assert np.isfinite(result).all(), 'Non-finite accessor'
                result = result.reshape(accessor['count'], dimensions)
                arrays[index] = result
                return result

            for index in range(len(data['accessors'])):
                read(index)
            for image in data.get('images', []):
                assert (path.parent / image['uri']).exists(), 'Missing texture '+image['uri']
            for mesh in data.get('meshes', []):
                for primitive in mesh['primitives']:
                    vertices = read(primitive['attributes']['POSITION'])
                    indices = read(primitive['indices'])
                    assert len(indices) % 3 == 0 and indices.max() < len(vertices), 'Invalid triangle index'
                    for index in primitive['attributes'].values():
                        assert len(read(index)) == len(vertices), 'Mismatched vertex attributes'
                    if 'WEIGHTS_0' in primitive['attributes']:
                        weights = read(primitive['attributes']['WEIGHTS_0'])
                        assert np.allclose(weights.sum(axis=1), 1, atol=1e-5), 'Non-normalized skin weights'
            for node in data.get('nodes', []):
                for child in node.get('children', []):
                    assert 0 <= child < len(data['nodes']), 'Missing child node'
                if 'skin' in node:
                    skin = data['skins'][node['skin']]
                    assert len(set(skin['joints'])) == len(skin['joints']), 'Duplicate skin joint'
                    assert len(read(skin['inverseBindMatrices'])) == len(skin['joints']), 'Skin matrix count differs'
                    for primitive in data['meshes'][node['mesh']]['primitives']:
                        joints = read(primitive['attributes']['JOINTS_0'])
                        assert joints.max() < len(skin['joints']), 'Skin joint index outside skeleton'
            names = [animation['name'] for animation in data.get('animations', [])]
            assert len(set(names)) == len(names), 'Duplicate animation name'
            for animation in data.get('animations', []):
                assert re.fullmatch(r'[A-Za-z0-9_]+', animation['name']), 'Unsafe animation name'
                assert not re.search(r'_(loop_mode|loop|cycle)$', re.sub(r'[0-9_]+$', '', animation['name']), re.I), 'Godot strips animation suffix'
                for sampler in animation['samplers']:
                    times = read(sampler['input'])[:, 0]
                    assert np.all(np.diff(times) > 0), 'Animation timestamps not strictly increasing'
                    assert len(times) == len(read(sampler['output'])), 'Animation sample count differs'
            if path.parent.name == 'environments':
                marker_data = json.loads(path.with_suffix('.markers.json').read_text())
                node_names = {node['name'] for node in data['nodes']}
                for marker in marker_data['markers']:
                    assert marker.get('exported_node_name') in node_names, 'Marker exported node missing'
                    assert len(marker['world_matrix']) == 16 and np.isfinite(marker['world_matrix']).all(), 'Invalid marker matrix'
                    if marker['kind'] == 64 and marker['properties'].get('m_Mesh', {}).get('fileID', 0):
                        resource = marker.get('mesh_faces_path')
                        assert resource, 'MeshCollider faces not exported'
                        if resource not in collision_resources:
                            collision_path = ROOT / 'goDot' / resource.removeprefix('res://')
                            faces = json.loads(collision_path.read_text())['faces']
                            assert len(faces) > 0 and len(faces) % 9 == 0 and np.isfinite(faces).all(), 'Invalid collider triangle data'
                            collision_resources.add(resource)
                totals['collider_markers'] += len(marker_data['markers'])
                totals['semantic_markers'] += len(marker_data.get('semantic_markers', []))
                totals['semantic_markers_bound'] += sum('exported_node_name' in marker for marker in marker_data.get('semantic_markers', []))
            record = dict(path=identity(path), bytes=len(payload), meshes=len(data.get('meshes', [])),
                          skins=len(data.get('skins', [])), animations=len(names), nodes=len(data['nodes']), textures=len(data.get('images', [])))
            assert record['meshes'] > 0, 'Scene contains no mesh'
            for key in ('meshes', 'skins', 'animations', 'nodes', 'textures', 'bytes'):
                totals[key] += record[key]
            records.append(record)
        except Exception as error:
            failures.append(dict(path=identity(path), error=str(error)))
    catalog = json.loads((OUT / 'catalog.json').read_text())
    for group in ('characters', 'enemies', 'weapons', 'environments'):
        for key, entry in catalog.get(group, {}).items():
            if not (ROOT / 'goDot' / entry['path'].removeprefix('res://')).exists():
                failures.append(dict(group=group, id=key, error='Missing catalog resource'))
    report = dict(converter=VERSION, checked=len(records)+len(failures), passed=len(records), failed=len(failures),
                  totals=dict(totals), failures=failures, records=records,
                  limitations=['Structural validation does not replace actual Godot rendering and gameplay verification.'])
    (REPORTS / 'assets-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    environment_records = [record for record in records if '/environments/' in record['path']]
    (REPORTS / 'assets-environments.json').write_text(json.dumps(dict(converter=VERSION, environments=len(environment_records),
                collider_resources=len(collision_resources), collider_markers=totals['collider_markers'],
                semantic_markers=totals['semantic_markers'], semantic_markers_bound=totals['semantic_markers_bound'],
                failures=[failure for failure in failures if '/environments/' in failure.get('path', '')],
                limitations=['Scene shaders are PBR approximations; lighting, particle and controller behavior need Godot runtime reconstruction.']), indent=2))
    print(json.dumps({key:value for key,value in report.items() if key not in ('records', 'failures')}), flush=True)
    if failures:
        print(json.dumps(failures, ensure_ascii=False), flush=True)
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--limit-environments', type=int, default=117)
    parser.add_argument('--skip-environments', action='store_true')
    parser.add_argument('--only-environments', action='store_true')
    parser.add_argument('--validate-only', action='store_true')
    parser.add_argument('--refresh-marker-sidecars', action='store_true')
    parser.add_argument('--refresh-materials', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    rules_source = OFFLINE / 'Environment/Resources/EnvironmentDatabase.json'
    rules_target = OUT / 'environment_rules.json'
    if rules_source.exists() and (not rules_target.exists() or digest(rules_source) != digest(rules_target)):
        shutil.copyfile(rules_source, rules_target)
    if args.validate_only:
        validate_outputs()
        return
    if args.refresh_materials:
        count = 0
        files = 0
        for target in sorted(OUT.rglob('*.glb')):
            payload = target.read_bytes()
            length = struct.unpack_from('<I', payload, 12)[0]
            data = json.loads(payload[20:20+length])
            count += refresh_materials(data)
            write_glb(target, data, payload[28+length:])
            cache_file = target.with_suffix('.conversion.json')
            if cache_file.exists():
                cache = json.loads(cache_file.read_text())
                cache['version'] = VERSION
                cache['result']['bytes'] = target.stat().st_size
                cache_file.write_text(json.dumps(cache, ensure_ascii=False, indent=2))
            files += 1
        catalog_file = OUT / 'catalog.json'
        catalog = json.loads(catalog_file.read_text())
        catalog['converter'] = VERSION
        for group in ('characters', 'enemies', 'environments', 'weapons'):
            for entry in catalog.get(group, {}).values():
                if isinstance(entry, dict) and entry.get('path'):
                    entry['bytes'] = (ROOT / 'goDot' / entry['path'].removeprefix('res://')).stat().st_size
        write_catalog(catalog)
        print(f'Refreshed {count} material instances in {files} GLBs; geometry/binary chunks unchanged', flush=True)
        return
    index_assets()
    if args.refresh_marker_sidecars:
        for target in sorted((OUT / 'environments').glob('*.glb')):
            payload = target.read_bytes()
            length = struct.unpack_from('<I', payload, 12)[0]
            enrich_environment(target, json.loads(payload[20:20+length]))
        print('Refreshed 117 environment marker sidecars', flush=True)
        return
    catalog_path = OUT / 'catalog.json'
    catalog = json.loads(catalog_path.read_text()) if catalog_path.exists() else {}
    catalog.update(version=1, converter=VERSION, coordinate_space='Unity native numeric xyz; no axis reflection',
                   conversion_matrix=[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                   triangle_winding='Source numeric index order retained; cross product agrees with recovered vertex normals', uv_v='1-v',
                   limitations=['Original Unity shaders require Godot equivalents.',
                                'Float/property animation curves, Animator transitions and MonoBehaviours require runtime reconstruction.',
                                'ParticleSystem components are not encoded by glTF.',
                                'BlendShape channel metadata retained; morph deltas not exported.'])
    for key in ('characters', 'enemies', 'environments', 'weapons'):
        catalog.setdefault(key, {})
    catalog['ui'] = {}
    for path in (OFFLINE / 'Offline/Resources/CampUI').glob('*.png'):
        target = OUT / 'ui' / path.name
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or digest(path) != digest(target):
            shutil.copyfile(path, target)
        catalog['ui'][path.stem] = 'res://assets/ui/'+path.name
    catalog['defaults'] = dict(character='res://assets/characters/character_1.glb', enemy='res://assets/enemies/enemy_11001.glb',
                               camp='res://assets/environments/EnvDesignMap_MainCity.glb',
                               environment='res://assets/environments/LevelMap_1010101.glb')
    if not args.only_environments:
        offline_catalog = body(OFFLINE / 'Offline/Resources/OfflineVisualCatalog.asset')
        chars = [row for row in json.loads((RESOURCE / 'MasterCfg/Luban_AT/CharData.json').read_text()) if row['available_state'] == 'Normal']
        for number, char in enumerate(chars):
            cfg = json.loads((RESOURCE / f'ActionEngineCfg/Unit/Player/PlayerActionCfg__{char["res_id"]}_.json').read_text())
            prefab = RESOURCE / 'Prefabs/BattleSys/Role/Player' / cfg['Prefab']
            result = convert_asset(prefab, OUT / 'characters' / f'character_{char["id"]}.glb', controller_animations(prefab))
            result.update(id=char['id'], name=char['name'], default_weapon=char['default_weapon'])
            result['weapon_socket'] = 'dummy_hand_r'
            catalog['characters'][str(char['id'])] = result
            write_catalog(catalog)
            print('CHARACTER', char['id'], result['meshes'], result['skins'], len(result['animations']), flush=True)
        combat_catalog = body(OFFLINE / 'Combat/Resources/CombatVisualCatalog.asset')
        for enemy in combat_catalog['enemies']:
            prefab = resolve(enemy['prefab'])
            animations = [(path, name) for ref, name in zip(enemy['animations'], enemy['animationNames']) if (path := resolve(ref))]
            result = convert_asset(prefab, OUT / 'enemies' / f'enemy_{enemy["id"]}.glb', animations)
            result['id'] = enemy['id']
            catalog['enemies'][str(enemy['id'])] = result
            write_catalog(catalog)
            print('ENEMY', enemy['id'], result['meshes'], result['skins'], len(result['animations']), flush=True)
        for weapon_id, ref in zip(offline_catalog['weaponIds'], offline_catalog['weaponPrefabs']):
            prefab = resolve(ref)
            result = convert_asset(prefab, OUT / 'weapons' / f'weapon_{weapon_id}.glb', controller_animations(prefab))
            catalog['weapons'][str(weapon_id)] = result
        font = SOURCE / '_00001_Media/FontNotBuild/AlibabaPuHuiTi-3-95-ExtraBold.otf'
        target = OUT / 'fonts/default.otf'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(font, target)
        fallback = SOURCE / '_00010_Plugins/_002_Tools/UGUICircularScrollView/Fonts/msyh.ttf'
        shutil.copyfile(fallback, OUT / 'fonts/default.ttf')
        catalog['font'] = 'res://assets/fonts/default.ttf'
        audio = body(OFFLINE / 'Audio/Resources/OfflineAudioCatalog.asset')
        catalog['audio'] = {}
        for path in (OFFLINE / 'Audio').rglob('*.ogg'):
            target = copy_media(path, 'audio')
            catalog['audio'][path.stem] = 'res://' + str(target.relative_to(ROOT / 'goDot'))
        write_catalog(catalog)
    if not args.skip_environments:
        campaign_catalog = body(OFFLINE / 'Campaign/Resources/CampaignVisualCatalog.asset')
        scene_ids = {}
        database = json.loads((OFFLINE / 'Campaign/Resources/CampaignDatabase.json').read_text())
        environment_settings = {}
        for stage in database.get('Nodes', []) + database.get('SupplementalEnvironments', []):
            if 'SceneName' in stage:
                scene_ids[stage['SceneName']] = stage.get('EnvironmentId', stage.get('Id'))
                environment_settings[stage['SceneName']] = stage
        environments = sorted(campaign_catalog['environments'], key=lambda x: (x['sceneName'] != 'EnvDesignMap_MainCity', x['sceneName']))
        for number, environment in enumerate(environments[:args.limit_environments]):
            prefab = resolve(environment['prefab'])
            name = environment['sceneName']
            result = convert_asset(prefab, OUT / 'environments' / (name+'.glb'), markers=True)
            result.update(scene_name=name)
            settings = environment_settings.get(name, {})
            result.update(player_start=settings.get('PlayerStart'), player_rotation=settings.get('PlayerRotation'),
                          camera_rotation=[settings.get('CameraX', 45), settings.get('CameraY', -45)])
            key = str(scene_ids.get(name) or (10000 if name == 'EnvDesignMap_MainCity' else re.search(r'(\d+)', name)[1] if re.search(r'(\d+)', name) else name))
            catalog['environments'][key] = result
            write_catalog(catalog)
            print('ENVIRONMENT', number+1, name, result['meshes'], result['colliders'], flush=True)
    catalog['defaults'] = dict(character='res://assets/characters/character_1.glb', enemy='res://assets/enemies/enemy_11001.glb',
                               camp='res://assets/environments/EnvDesignMap_MainCity.glb',
                               environment='res://assets/environments/LevelMap_1010101.glb')
    write_catalog(catalog)
    report = dict(converter=VERSION, counts={key: len(catalog.get(key, {})) for key in ('characters', 'enemies', 'environments', 'weapons', 'audio')},
                  warnings=WARNINGS, media=MEDIA, limitations=catalog['limitations'], source_unchanged=True)
    report_name = 'assets-environments.json' if args.only_environments else 'assets-conversion.json'
    (REPORTS / report_name).write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps(report['counts']), flush=True)


if __name__ == '__main__':
    main()
