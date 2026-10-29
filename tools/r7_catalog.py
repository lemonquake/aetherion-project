"""Writes game/data/r7_props.json: every r7 prop in ModelLib.PROPS (the "r7" section of game/src/world/model_lib.gd)
with its real footprint, height, front axis, collision and suggested use, measured from the processed glTF files.

    python -I tools/r7_catalog.py

Sizes are the model's bounds in Godot axes (metres): footprint = [x, z], height = y. Every model stands with its
origin at the floor centre and its front facing +Z (a prop placed with yaw 0 faces +Z), except where "front" says
otherwise. "col" lists boxes [centre x, y, z, size x, y, z] for props whose PROPS entry has no collision box
(no_collide) because one box over their whole bounds would wall off the space under them: add these with
map.sink.col_box (the posts / legs).
"""
import json
import os
import re
import struct

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, 'game')
LIB = os.path.join(GAME, 'src', 'world', 'model_lib.gd')
OUT = os.path.join(GAME, 'data', 'r7_props.json')

USE = {
    'armchair': 'house (sala)', 'armchair_modern': 'house (sala), clubhouse, office', 'sofa_classic': 'house (sala)',
    'sofa_leather': 'house (sala), clubhouse, office lobby', 'coffee_table': 'house (sala)',
    'dining_chair': 'house (dining)', 'dining_table': 'house (dining), clubhouse', 'side_table': 'house (sala, bedroom)',
    'plant_stand': 'house (sala, porch)', 'tv_cabinet': 'house (sala)', 'nightstand_classic': 'house (bedroom)',
    'china_cabinet': 'house (dining)', 'potted_plant': 'house, office, clubhouse, porch',
    'potted_plant2': 'house, office, store counter', 'garden_gnome': 'house (front yard)',
    'planter_box': 'house (front yard), street, clubhouse', 'iron_gate': 'house (driveway gate), guardhouse',
    'display_shelves': 'store, house', 'steel_shelves3': 'store (stock room), factory, garage',
    'metal_rack': 'store (stock room), garage, factory', 'wet_floor_sign': 'store, office, clubhouse',
    'payphone': 'store (outside wall), street, gas station', 'security_camera': 'store, gas station, guardhouse (wall)',
    'food_tins': 'store (shelves), house (kitchen)', 'food_cans': 'store (shelves), house (kitchen)',
    'bleach': 'store (shelves), house (toilet)', 'cleaner_bottle': 'store (shelves), house (kitchen)',
    'storage_cart': 'factory', 'airduct': 'factory, store (ceiling)', 'drum_plastic2': 'factory, gas station',
    'tote_box': 'factory, store (stock room)', 'compressor': 'factory, garage, gas station',
    'sconce_caged': 'factory, store (wall light)', 'wall_lamp_industrial': 'factory, house (outside wall)',
    'barrier2': 'street, parking, gas station', 'street_bench': 'street, park, playground, clubhouse',
    'car_compact': 'street, parking', 'car_coupe': 'street, parking', 'car_hatchback': 'street, parking, house',
    'car_minivan': 'street, parking, house', 'car_offroad': 'street, parking, house',
    'car_pickup': 'street, parking, factory, gas station', 'car_sedan': 'street, parking, house',
    'car_sport': 'street, parking', 'car_suv': 'street, parking, house', 'car_wagon': 'street, parking, house',
    'car_saloon_old': 'street, parking, house', 'car_sedan_80s': 'street, parking, house',
    'car_sedan_80s_b': 'street, parking, house', 'car_pickup_old': 'street, parking, house, gas station',
    'van_delivery': 'street, parking, store (loading), factory', 'car_burnt_a': 'street, parking (wreck)',
    'car_burnt_b': 'street, parking (wreck)', 'car_police_burnt': 'street, barricade (wreck)',
    'car_police_flipped': 'street, barricade (wreck on its roof)',
    'jeepney_painted': 'street (stalled on the avenue), terminal', 'forklift_a': 'factory, warehouse yard',
    'forklift_b': 'factory, warehouse yard', 'store_display_case': 'store (counter)', 'store_chiller': 'store (wall)',
    'store_shelf_wall': 'store (wall)', 'chem_tanks': 'factory yard', 'conveyor': 'factory floor',
    'control_pedestal': 'factory floor', 'basketball_hoop': 'court, clubhouse, playground',
    'playground_slide': 'playground, park', 'playground_set': 'playground, park',
    'traffic_light': 'street (major intersection corner)', 'ped_signal': 'street (zebra crossing kerb)',
    'gas_pump_old': 'gas station (island)', 'gas_pump_round': 'gas station (island)',
    'aircon_condenser': 'house (outside wall), store, office (wall bracket)',
}
# Where the front is not simply +Z.
FRONT = {
    'display_shelves': '+X (open side; the source faces sideways: rotate yaw -90 deg to face +Z)',
    'basketball_hoop': '+Z (the board and rim overhang toward +Z, the post stands at the back)',
    'traffic_light': '+Z (the arm with the signal heads reaches toward +Z: stand the post at the kerb, arm over the road)',
    'playground_set': '+Z (a scattered set: monkey bars, swings, see-saw)',
    'car_police_flipped': '+Z (lying on its roof)',
    'airduct': 'none (a 1.8 m straight duct section running along Z; repeat it every 1.8 m)',
    'iron_gate': '+Z (a flat double gate 2.95 m wide in the XY plane)',
    'security_camera': '+Z (mount its back, -Z, on a wall)',
    'sconce_caged': '+Z (mount its back on a wall)', 'wall_lamp_industrial': '+Z (mount its back on a wall)',
    'aircon_condenser': '+Z (fan side; the bracket goes against the wall at -Z)',
}
LICENCE_SF = 'CC-BY-4.0 (credited in data/credits.json)'


def read_r7_props():
    text = open(LIB, encoding='utf-8').read()
    start = text.index('# ---- r7 (Lawless Sub)')
    end = text.index('\n}', start)
    out = {}
    for line in text[start:end].splitlines():
        m = re.match(r'\s*"(\w+)": (\{.*\}),?\s*$', line)
        if not m:
            continue
        d = json.loads(m.group(2))
        out[m.group(1)] = d
    return out


def gltf_path(spec):
    if 'path' in spec:
        return os.path.join(GAME, spec['path'].replace('res://', '').replace('/', os.sep))
    return os.path.join(GAME, 'assets', 'models', 'polyhaven', spec['model'] + '.gltf')


def positions(path):
    """All vertex positions of a processed glTF (one node, identity transform), plus its triangle count."""
    j = json.load(open(path, encoding='utf-8'))
    base = os.path.dirname(path)
    bins = {}
    pts = []
    tris = 0
    for mesh in j['meshes']:
        for p in mesh['primitives']:
            acc = j['accessors'][p['attributes']['POSITION']]
            bv = j['bufferViews'][acc['bufferView']]
            buf = j['buffers'][bv['buffer']]
            if buf['uri'] not in bins:
                bins[buf['uri']] = open(os.path.join(base, buf['uri']), 'rb').read()
            data = bins[buf['uri']]
            off = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
            stride = bv.get('byteStride', 12)
            n = acc['count']
            a = np.frombuffer(data, np.uint8, count=stride * (n - 1) + 12, offset=off)
            idx = (np.arange(n)[:, None] * stride + np.arange(12)[None, :]).ravel()
            pts.append(a[idx].view(np.float32).reshape(n, 3))
            if 'indices' in p:
                tris += j['accessors'][p['indices']]['count'] // 3
            else:
                tris += n // 3
    return np.concatenate(pts), tris, sum(len(m['primitives']) for m in j['meshes'])


def ground_boxes(v, height):
    """Boxes over the clusters of geometry touching the ground (posts, legs), up to the model's height (max 3 m)."""
    low = v[v[:, 1] < 0.6]
    if len(low) == 0:
        return []
    cell = 0.25
    keys = {}
    for p in low:
        keys.setdefault((int(np.floor(p[0] / cell)), int(np.floor(p[2] / cell))), []).append(p)
    seen = set()
    boxes = []
    for k in keys:
        if k in seen:
            continue
        stack, comp = [k], []
        seen.add(k)
        while stack:
            c = stack.pop()
            comp.extend(keys[c])
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    nb = (c[0] + dx, c[1] + dz)
                    if nb in keys and nb not in seen:
                        seen.add(nb)
                        stack.append(nb)
        a = np.array(comp)
        lo, hi = a.min(0), a.max(0)
        sx, sz = max(float(hi[0] - lo[0]), 0.12), max(float(hi[2] - lo[2]), 0.12)
        h = min(height, 3.0)
        boxes.append([round(float(lo[0] + hi[0]) / 2, 3), round(h / 2, 3), round(float(lo[2] + hi[2]) / 2, 3),
                      round(sx, 3), round(h, 3), round(sz, 3)])
    return boxes


def main():
    props = read_r7_props()
    out = {'_doc': __doc__.strip().splitlines()[0] + ' Front axis: +Z unless "front" says otherwise. Units: metres.',
           'props': {}}
    for name, spec in props.items():
        path = gltf_path(spec)
        v, tris, surf = positions(path)
        lo, hi = v.min(0), v.max(0)
        size = hi - lo
        rec = {
            'source': spec.get('path', 'Poly Haven ' + spec.get('model', '')),
            'footprint': [round(float(size[0]), 2), round(float(size[2]), 2)],
            'height': round(float(size[1]), 2),
            # Bounds in the model's own frame. Sketchfab models sit on their floor centre; Poly Haven copies keep the
            # author's origin (usually within a few cm of it; wall lights and the duct are centred on their mount / axis).
            'bounds_min': [round(float(x), 3) for x in lo],
            'bounds_max': [round(float(x), 3) for x in hi],
            'front': FRONT.get(name, '+Z'),
            'use': USE.get(name, ''),
            'kind': spec.get('kind', ''),
            'static': bool(spec.get('static', False)),
            'mat': spec.get('mat', ''),
            'collision': 'none (decor)' if spec.get('no_collide') else 'box over the model bounds',
            'tris': tris,
            'surfaces': surf,
            'licence': LICENCE_SF if 'path' in spec else 'CC0-1.0 (Poly Haven)',
        }
        if spec.get('no_collide') and name in ('basketball_hoop', 'traffic_light', 'playground_set'):
            rec['col'] = ground_boxes(v, float(size[1]))
            rec['collision'] = 'none in PROPS; add the "col" post boxes with map.sink.col_box'
        out['props'][name] = rec
    json.dump(out, open(OUT, 'w', encoding='utf-8', newline='\n'), indent=1)
    print('wrote', OUT, len(out['props']), 'props')
    for n, r in out['props'].items():
        print('%-22s %5.2f x %5.2f  h %5.2f  %6d tris %d surf  %s' % (n, r['footprint'][0], r['footprint'][1], r['height'], r['tris'], r['surfaces'], ('col %d' % len(r['col'])) if 'col' in r else ''))


if __name__ == '__main__':
    main()
