"""Game-ready copies of the Hidden Forest (r27) models: Aztec statues and jungle trees from Sketchfab (CC-BY 4.0, the
credits go with them), rocks, roots, ferns and shrubs from Poly Haven (CC0).

    blender -b --factory-startup -P tools/blender/process_hf.py [-- name ... | --list]

Sources: tools/cache/sketchfab/<src>/<src>.glb, game/assets/thirdparty/polyhaven/models/<id>/<id>_1k.gltf.
Output: game/assets/models/hf/<name>.gltf (+ .bin, textures/), sources/<name>.json (credits, modifications) and
work/hf/models/<name>.png (a check render). Also work/hf/models/sizes.json: every model's size, which the map's draft
script reads to give props their collision footprints.

Conventions (as tools/blender/process_props.py, whose functions this loads): metres, +Y up in Godot, the origin at
the centre of the footprint with the lowest point at y = 0; front toward +Z in Godot. Statues and trees are scaled to
the size they stand in the map (h: height in metres). Opaque models get one material (an atlas); foliage keeps its
alpha (cut out, glTF MASK) so leaves stay leaves, and is thinned: whole leaves dropped at random, survivors enlarged.
ModelLib and Terrain3D generate LODs at load, so none are stored.
"""
import bpy, os, sys, re, json, math, hashlib, zlib
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SF = os.path.join(ROOT, 'tools', 'cache', 'sketchfab')
PHM = os.path.join(ROOT, 'game', 'assets', 'thirdparty', 'polyhaven', 'models')
OUT = os.path.join(ROOT, 'game', 'assets', 'models', 'hf')
PREV = os.path.join(ROOT, 'work', 'hf', 'models')

_pp_path = os.path.join(HERE, 'process_props.py')
_pp_code = re.sub(r'\nmain\(\)\s*$', '\n', open(_pp_path, encoding='utf-8').read())
P = {'__name__': 'process_props_lib', '__file__': _pp_path}
exec(compile(_pp_code, _pp_path, 'exec'), P)
P['OUT'] = OUT
P['TEX'] = os.path.join(OUT, 'textures')
P['PREV'] = PREV

LEAF = r'(?i)leaf|leaves|frond|foliage|fern|shrub|nettle|periwinkle|weed|celandine|grass|banana|plant'

# name: src (sf:<cache name> or ph:<id>), h (height after scaling; omit to keep the source's scale), tris (budget for
# the opaque parts), leaves (budget for the cut-out leaves), grow (largest enlargement of kept leaves), keep (regexes
# on object names: only those objects), rot (degrees about X, Y, Z in Blender after import, to stand it up / face it
# front), purpose (for the credits)
MODELS = {
    # ---------------------------------------------------------------- Aztec stone (Sketchfab, CC-BY 4.0)
    'serpent_stele': dict(src='sf:hf_aztec_statue', h=2.9, tris=6000, purpose='carved stele with a serpent head'),
    'effigy': dict(src='sf:hf_aztec_effigy', h=1.9, tris=5000, purpose='death-god effigy statue'),
    'atlantean': dict(src='sf:hf_aztec_statue_scan', h=3.6, tris=5000, purpose='warrior column statue (atlante)'),
    'sun_stone': dict(src='sf:hf_calendar_stone', h=3.8, tris=7000, purpose='the sun stone, standing in its frame'),
    'jaguar': dict(src='sf:hf_jaguar', h=2.3, tris=6000, purpose='jaguar statue on its plinth'),
    'olmec_head': dict(src='sf:hf_olmec_head', h=2.7, tris=7000, purpose='colossal stone head'),
    'stone_figure': dict(src='sf:hf_olmec_cc0', h=1.6, tris=3000, purpose='green stone figure'),
    'tribal_pillar': dict(src='sf:hf_tribal_pillar', h=3.8, tris=5000, purpose='carved jungle pillar'),
    'serpent_head': dict(src='sf:hf_xiuhcoatl', h=2.2, tris=6000, purpose='fire serpent head sculpture'),
    # ---------------------------------------------------------------- jungle (Sketchfab, CC-BY 4.0)
    'buttress_trunk': dict(src='sf:hf_jungle_tree_b', h=5.5, tris=7000, purpose='buttress-rooted jungle trunk'),
    'root_arch': dict(src='sf:hf_liana_tree', h=10.0, tris=12000, purpose='strangler fig root arch'),
    'ceiba': dict(src='sf:hf_ceiba', h=33.0, tris=9000, leaves=26000, grow=5.0, leaf=r'(?i)leaf', purpose='ceiba (kapok), the canopy giant'),
    'taro': dict(src='sf:hf_taro', h=1.7, tris=600, leaves=2400, grow=1.0, purpose='taro (elephant ear)'),
    'exotic_plant': dict(src='sf:hf_pink_plant', h=1.3, tris=600, leaves=2400, grow=1.0, purpose='exotic broadleaf plant'),
    'banana_tree': dict(src='sf:hf_banana_tree', h=5.0, tris=1500, leaves=3000, grow=1.2, purpose='banana tree'),
    'brazier_column': dict(src='sf:hf_column_brazier', h=1.4, tris=2500, purpose='stone column brazier'),
    'brazier_bowl': dict(src='sf:hf_brazier_bowl', h=0.7, tris=1500, purpose='brazier bowl'),
    'banana': dict(src='sf:hf_banana_plant2', h=3.2, tris=2000, leaves=4000, grow=1.4, purpose='banana plant'),
    # ---------------------------------------------------------------- rocks, roots, logs (Poly Haven, CC0)
    'mossrock_1': dict(src='ph:rock_moss_set_01', keep=[r'_rock01$'], tris=2400),
    'mossrock_2': dict(src='ph:rock_moss_set_01', keep=[r'_rock02$'], tris=2400),
    'mossrock_3': dict(src='ph:rock_moss_set_01', keep=[r'_rock04$'], tris=2400),
    'mossrock_4': dict(src='ph:rock_moss_set_01', keep=[r'_rock05$'], tris=2400),
    'mossrock_5': dict(src='ph:rock_moss_set_01', keep=[r'_rock06$'], tris=2400),
    'mossrock_s1': dict(src='ph:rock_moss_set_02', keep=[r'_rock09$'], tris=1200),
    'mossrock_s2': dict(src='ph:rock_moss_set_02', keep=[r'_rock11$'], tris=1200),
    'mossrock_s3': dict(src='ph:rock_moss_set_02', keep=[r'_rock13$'], tris=1200),
    'cliff_face_1': dict(src='ph:rock_face_01', h=7.0, tris=4000),
    'cliff_face_2': dict(src='ph:rock_face_02', h=6.0, tris=4000),
    'boulder_split': dict(src='ph:namaqualand_boulder_02', h=2.2, tris=3000),
    'root_cluster': dict(src='ph:root_cluster_01', tris=3000),
    'root_flat': dict(src='ph:root_cluster_02', tris=2500),
    'stump_1': dict(src='ph:tree_stump_01', tris=2000),
    'stump_2': dict(src='ph:tree_stump_02', tris=2000),
    'log_1': dict(src='ph:dead_tree_trunk', tris=3000),
    'log_2': dict(src='ph:dead_tree_trunk_02', tris=3000),
    # ---------------------------------------------------------------- ground cover (Poly Haven, CC0): Terrain3D plants
    'fern_a': dict(src='ph:fern_02', keep=[r'_b$'], leaves=900, grow=1.25),
    'fern_b': dict(src='ph:fern_02', keep=[r'_c$'], leaves=900, grow=1.25),
    'shrub_leafy': dict(src='ph:shrub_04', leaves=1400, grow=1.2, scale=2.2),
    'shrub_tall': dict(src='ph:shrub_01', keep=[r'_a$'], leaves=1200, grow=1.3),
    'shrub_wiry': dict(src='ph:shrub_02', keep=[r'_a$'], leaves=1200, grow=1.3),
    'nettle': dict(src='ph:nettle_plant', keep=[r'_tall_a_LOD0$'], leaves=1400, grow=1.15, scale=3.0),
    'periwinkle': dict(src='ph:periwinkle_plant', keep=[r'_01_LOD0$'], leaves=1800, grow=1.15, scale=2.0),
    'weed_leaves': dict(src='ph:weed_plant_02', keep=[r'_a_LOD0$'], leaves=3000, grow=1.0, scale=3.0),
    'canopy_tree': dict(src='ph:jacaranda_tree', tris=6000, leaves=16000, grow=3.5, leaf=r'(?i)leaves', purpose='broadleaf canopy tree'),
}


def src_path(src):
    kind, name = src.split(':', 1)
    if kind == 'sf':
        return os.path.join(SF, name, name + '.glb')
    for suf in ('_1k.gltf', '.gltf', '_2k.gltf'):
        p = os.path.join(PHM, name, name + suf)
        if os.path.exists(p):
            return p
    return None


def source_meta(src):
    kind, name = src.split(':', 1)
    p = os.path.join(SF if kind == 'sf' else PHM, name, 'source.json')
    if os.path.exists(p):
        return json.load(open(p, encoding='utf-8'))
    return {'source': 'Sketchfab' if kind == 'sf' else 'Poly Haven', 'title': name}


def is_leaf_mat(m, pattern=None):
    if m is None:
        return False
    if pattern:
        return re.search(pattern, m.name) is not None
    if re.search(LEAF, m.name):
        return True
    b = P['principled'](m)
    return b is not None and b.inputs['Alpha'].is_linked


def process(name, cfg):
    src = src_path(cfg['src'])
    if src is None or not os.path.exists(src):
        print('[hf] MISSING', name, cfg['src'])
        return None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    notes = []
    # Images embedded in a .glb have no file name: give each its own, or resized copies overwrite one another.
    # The exporter names texture files after the images, and Sketchfab's are all Image_0, Image_1...: prefix them.
    for img in bpy.data.images:
        if not os.path.basename(img.filepath or ''):
            img.filepath = '//%s_%s.png' % (name, re.sub(r'\W+', '_', img.name))
        if not img.name.startswith(name + '_'):
            img.name = '%s_%s' % (name, img.name)
    if cfg.get('keep'):
        for ob in P['meshes']():
            if not any(re.search(p, ob.name) for p in cfg['keep']):
                bpy.data.objects.remove(ob, do_unlink=True)
        notes.append('kept %s of the set' % ', '.join(sorted(x.name for x in P['meshes']())))
    o = P['join_all'](name)
    before = P['tris'](o)
    if cfg.get('rot'):
        rx, ry, rz = [math.radians(v) for v in cfg['rot']]
        o.data.transform(Matrix.Rotation(rx, 4, 'X') @ Matrix.Rotation(ry, 4, 'Y') @ Matrix.Rotation(rz, 4, 'Z'))
    if cfg.get('scale'):
        o.data.transform(Matrix.Scale(cfg['scale'], 4))
        notes.append('scaled %gx (grown into a jungle-sized plant)' % cfg['scale'])
    lo, hi = P['bounds'](o)
    if cfg.get('h'):
        k = cfg['h'] / max(float(hi[2] - lo[2]), 1e-6)
        o.data.transform(Matrix.Scale(k, 4))
        notes.append('scaled to %.1f m tall' % cfg['h'])
    lo, hi = P['bounds'](o)
    c = (lo + hi) / 2
    o.data.transform(Matrix.Translation((-float(c[0]), -float(c[1]), -float(lo[2]))))
    # opaque parts and leaves apart
    mats = list(o.data.materials)
    lp = cfg.get('leaf')
    leafy = [i for i, m in enumerate(mats) if is_leaf_mat(m, lp) and cfg.get('leaves')]
    parts = P['split_by_material'](o) if leafy and len(mats) > 1 else [o]
    leaf_parts = []
    solid_parts = []
    for p in parts:
        m = p.data.materials[0] if p.data.materials else None
        (leaf_parts if (cfg.get('leaves') and is_leaf_mat(m, lp)) else solid_parts).append(p)
    if cfg.get('leaves') and not leaf_parts and len(parts) == 1:
        leaf_parts, solid_parts = parts, []
    t_leaf = sum(P['tris'](p) for p in leaf_parts)
    for p in leaf_parts:
        share = P['tris'](p) / max(t_leaf, 1)
        frac, grow = P['thin_islands'](p, max(int(cfg['leaves'] * share), 60), rng, cfg.get('grow', 1.5))
    if leaf_parts:
        notes.append('leaves thinned to %s triangles (whole leaves dropped, the rest enlarged up to %.1fx), kept cut out' %
                     (format(sum(P['tris'](p) for p in leaf_parts), ','), cfg.get('grow', 1.5)))
    t_solid = sum(P['tris'](p) for p in solid_parts)
    for p in solid_parts:
        share = P['tris'](p) / max(t_solid, 1)
        target = max(int(cfg.get('tris', 3000) * share), 80)
        # Scans often come as loose triangles: weld them first, or collapsing cannot join anything and tears holes.
        P['select_only']([p])
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        lo3, hi3 = P['bounds'](p)
        bpy.ops.mesh.remove_doubles(threshold=max(float(np.linalg.norm(hi3 - lo3)) * 2e-4, 1e-5))
        bpy.ops.object.mode_set(mode='OBJECT')
        mname = p.data.materials[0].name if p.data.materials else ''
        if re.search(r'(?i)branch|twig', mname):
            P['decimate'](p, max(target * 3, int(P['tris'](p) * 0.25)))
            P['thin_islands'](p, target, rng, 1.0)
        else:
            P['decimate'](p, target)
    if solid_parts and t_solid > cfg.get('tris', 3000):
        notes.append('decimated to %s triangles' % format(sum(P['tris'](p) for p in solid_parts), ','))
    # solid parts: one atlas material; leaves keep their own (cut-out) material
    so = None
    if solid_parts:
        P['select_only'](solid_parts)
        if len(solid_parts) > 1:
            bpy.ops.object.join()
        so = bpy.context.view_layer.objects.active
        for m in so.data.materials:
            if m:
                P['make_opaque'](m)
        lo2, hi2 = P['bounds'](so)
        tex = 512 if float(max(hi2 - lo2)) < 0.8 else 1024
        merged = P['merge_materials'](so, name, {}, tex)
        if merged:
            notes.append(merged)
        elif P['shrink_textures'](so, name, tex):
            notes.append('textures %d px' % tex)
    for p in leaf_parts:
        P['shrink_textures'](p, name + '_leaf', 1024)
    leaf_mats = {x.name for p in leaf_parts for x in p.data.materials if x}
    allp = ([so] if so else []) + leaf_parts
    P['select_only'](allp)
    if len(allp) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    after = P['tris'](o)
    lo, hi = P['bounds'](o)
    size = hi - lo
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, name + '.gltf')
    P['select_only']([o])
    bpy.ops.export_scene.gltf(filepath=dst, export_format='GLTF_SEPARATE', use_selection=True, export_yup=True, export_apply=True,
                              export_keep_originals=False, export_texture_dir='textures', export_image_format='AUTO',
                              export_jpeg_quality=88, export_animations=False, export_cameras=False, export_lights=False,
                              export_extras=False)
    # leaves: cut out (MASK), both sides
    js = json.load(open(dst, encoding='utf-8'))
    for m in js.get('materials', []):
        if m.get('name') in leaf_mats or (leaf_mats and re.search(LEAF, m.get('name', ''))):
            m['alphaMode'] = 'MASK'
            m['alphaCutoff'] = 0.45
            m['doubleSided'] = True
    json.dump(js, open(dst, 'w', encoding='utf-8'), indent=1)
    os.makedirs(PREV, exist_ok=True)
    P['preview'](o, os.path.join(PREV, name + '.png'))
    meta = source_meta(cfg['src'])
    text = '; '.join(notes) if notes else 're-exported'
    meta['modifications'] = '%s; %s -> %s triangles (tools/blender/process_hf.py).' % (text[0].upper() + text[1:], format(before, ','), format(after, ','))
    meta['processed_from'] = os.path.relpath(src, ROOT).replace('\\', '/')
    if cfg.get('purpose'):
        meta['purpose'] = cfg['purpose']
    files = {}
    for f in [name + '.gltf', name + '.bin']:
        files[f] = hashlib.sha256(open(os.path.join(OUT, f), 'rb').read()).hexdigest()
    meta['files'] = files
    rec = os.path.join(OUT, 'sources')
    os.makedirs(rec, exist_ok=True)
    json.dump(meta, open(os.path.join(rec, name + '.json'), 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
    # Blender (x, y, z up) -> Godot (x, y up, z): width x, height z, depth y
    sz = [round(float(size[0]), 3), round(float(size[2]), 3), round(float(size[1]), 3)]
    print('[hf] %-16s %9d -> %6d tris  %.2f x %.2f x %.2f m  %s' % (name, before, after, sz[0], sz[1], sz[2], text))
    return {'size': sz, 'tris': after, 'leaves': bool(leaf_parts)}


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if argv == ['--list']:
        print('[hf] ' + ' '.join(MODELS))
        return
    sizes_path = os.path.join(PREV, 'sizes.json')
    sizes = json.load(open(sizes_path)) if os.path.exists(sizes_path) else {}
    for name, cfg in MODELS.items():
        if argv and name not in argv:
            continue
        try:
            r = process(name, cfg)
            if r:
                sizes[name] = r
        except Exception as e:
            import traceback
            traceback.print_exc()
            print('[hf] FAILED %s: %s' % (name, e))
    os.makedirs(PREV, exist_ok=True)
    json.dump(sizes, open(sizes_path, 'w'), indent=1, sort_keys=True)


main()
