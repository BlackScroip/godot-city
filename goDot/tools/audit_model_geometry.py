"""Audit every migrated GLB's geometry without changing skeletons or topology."""
import json
from pathlib import Path
import struct
import math

ROOT = Path(__file__).resolve().parents[1]
DTYPES = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
records = []
errors = []

def accessor(data, binary, index):
    item = data['accessors'][index]
    view = data['bufferViews'][item['bufferView']]
    width = WIDTH[item['type']]
    record = struct.Struct('<' + DTYPES[item['componentType']] * width)
    offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
    stride = view.get('byteStride', record.size)
    return [record.unpack_from(binary, offset + i * stride) for i in range(item['count'])]

for path in sorted((ROOT / 'assets').rglob('*.glb')):
    raw = path.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    data = json.loads(raw[20:20+length])
    binary = raw[28+length:]
    row = {'path': str(path.relative_to(ROOT)), 'meshes': len(data.get('meshes', [])),
           'skins': len(data.get('skins', [])), 'animations': len(data.get('animations', [])),
           'vertices': 0, 'triangles': 0, 'zero_normals': 0, 'degenerate_triangles': 0, 'missing_normals': 0}
    for mesh in data.get('meshes', []):
        for primitive in mesh.get('primitives', []):
            attrs = primitive['attributes']
            points = accessor(data, binary, attrs['POSITION'])
            row['vertices'] += len(points)
            if not all(math.isfinite(v) for point in points for v in point): errors.append([row['path'], mesh.get('name'), 'nonfinite_positions'])
            if 'NORMAL' in attrs:
                normals = accessor(data, binary, attrs['NORMAL'])
                row['zero_normals'] += sum(sum(v*v for v in normal) < 0.0001 for normal in normals)
                if not all(math.isfinite(v) for normal in normals for v in normal): errors.append([row['path'], mesh.get('name'), 'nonfinite_normals'])
            else:
                row['missing_normals'] += 1
            if 'indices' in primitive:
                indices = [value[0] for value in accessor(data, binary, primitive['indices'])]
                if indices and max(indices) >= len(points):
                    errors.append([row['path'], mesh.get('name'), 'index_out_of_bounds'])
                elif primitive.get('mode', 4) == 4:
                    if len(indices) % 3:
                        errors.append([row['path'], mesh.get('name'), 'incomplete_triangle'])
                        continue
                    row['triangles'] += len(indices) // 3
                    for i in range(0, len(indices), 3):
                        a, b, c = (points[j] for j in indices[i:i+3])
                        u = [b[j]-a[j] for j in range(3)]
                        v = [c[j]-a[j] for j in range(3)]
                        cross = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
                        row['degenerate_triangles'] += sum(x*x for x in cross) < 1e-20
    records.append(row)
report = {'files': len(records), 'errors': errors, 'records': records,
          'limits': 'Static geometry validation. Degenerate triangles may be authored ribbons, shadows or collapsed skin geometry; no topology is deleted automatically.'}
(ROOT / 'reports/model-geometry-audit.json').write_text(json.dumps(report, indent=2))
print(json.dumps({'files': len(records), 'errors': len(errors), 'vertices': sum(x['vertices'] for x in records),
                  'zero_normals': sum(x['zero_normals'] for x in records), 'missing_normals': sum(x['missing_normals'] for x in records)}))
