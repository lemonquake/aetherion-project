"""Make game-ready copies of the r7 downloads (Lawless Sub): Sketchfab cars, store, factory, playground and street
props, plus the new Poly Haven furniture / store / factory models.

    blender -b --factory-startup -P tools/blender/process_r7.py [-- name ... | --list | --ph | --sf]

Sketchfab sources: tools/cache/sketchfab/<src>/<src>.glb -> game/assets/models/r7/<name>.gltf (+ .bin, textures/,
sources/<name>.json with the original credits and the modifications). Poly Haven ids go through process_props.py's own
`process()` (same budgets, atlas and output: game/assets/models/polyhaven/<id>.gltf); that script is loaded, not
changed, so its existing outputs stay as they are.

Conventions of every processed model (the same as the Poly Haven furniture the dresser places):
- metres, +Y up, origin at the centre of the floor footprint (bounding-box centre in X/Z, lowest point at y = 0),
- FRONT faces +Z in Godot (Blender -Y): a car's bonnet, a fridge's doors, a pump's display, a hoop's board.
  A prop placed with yaw 0 faces +Z; backed against a wall at -Z it faces into the room.
- one material (an atlas) wherever the source allows; textures 1024 px cells (512 px for small props),
- triangle budgets: cars <= 8k, big set pieces <= 15k, small props <= 2k.
ModelLib generates LODs when it loads a model (ImporterMesh.generate_lods), so none are stored here.

Check renders: work/lemondev/r7/assets/models/<name>.png (a 1.8 m figure stands beside the model; a red ball marks
its front).
"""
import bpy, os, sys, re, json, math, hashlib
import numpy as np
from mathutils import Vector, Matrix, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CACHE = os.path.join(ROOT, 'tools', 'cache', 'sketchfab')
OUT = os.path.join(ROOT, 'game', 'assets', 'models', 'r7')
TEX = os.path.join(OUT, 'textures')
PREV = os.path.join(ROOT, 'work', 'lemondev', 'r7', 'assets', 'models')

# process_props.py runs main() when executed; load its functions without that last call.
_pp_path = os.path.join(HERE, 'process_props.py')
_pp_code = re.sub(r'\nmain\(\)\s*$', '\n', open(_pp_path, encoding='utf-8').read())
P = {'__name__': 'process_props_lib', '__file__': _pp_path}
exec(compile(_pp_code, _pp_path, 'exec'), P)
P['PREV'] = os.path.join(ROOT, 'work', 'lemondev', 'r7', 'assets', 'props')
PH_TEX = P['TEX']

# ------------------------------------------------------------------ Poly Haven ids (CC0) downloaded for r7
# Per-model settings (keep / tree / tris) live in process_props.MODELS, so running either script gives the same copy.
PH_IDS = ['ArmChair_01', 'Sofa_01', 'sofa_02', 'CoffeeTable_01', 'dining_chair_02', 'dining_table', 'side_table_01',
          'modern_wooden_cabinet', 'ClassicNightstand_01', 'potted_plant_01', 'potted_plant_02', 'modern_arm_chair_01',
          'vintage_cabinet_01', 'WoodenTable_02', 'wooden_display_shelves_01', 'steel_frame_shelves_03', 'worn_metal_rack',
          'WetFloorSign_01', 'korean_public_payphone_01', 'security_camera_01', 'long_life_food', 'russian_food_cans_01',
          'bleach_bottle', 'multi_cleaner_bottle', 'industrial_storage_cart', 'modular_airduct_rectangular_01', 'Barrel_02',
          'industrial_pastic_container', 'old_military_compressor', 'industrial_caged_sconce', 'industrial_wall_lamp',
          'concrete_road_barrier_02', 'modular_street_seating', 'large_iron_gate', 'planter_box_01', 'garden_gnome']
PH = {k: P['MODELS'].get(k, {}) for k in PH_IDS}

# ------------------------------------------------------------------ Sketchfab sources (CC-BY 4.0)
# src: cache folder. keep / drop: regexes on source object names. body: pack car, the body objects' name prefix (its
# wheels are the nearest ones; the car is turned back to its own frame). rot: degrees (X, Y, Z) applied after joining,
# chosen so the front ends up at Blender -Y. length (along the front axis) / height / scale: real size. tris: budget.
# glass: regex of material names made dark opaque glass. tex: atlas cell size.
GLASS = r'(?i)glass|window'
CAR_DROP = [r'(?i)seat', r'(?i)interior', r'(?i)dashboard', r'(?i)doorcard', r'(?i)steering', r'(?i)gearknob',
            r'(?i)rearview', r'(?i)engine', r'(?i)exhaust', r'(?i)suspension', r'(?i)transfer_case']
PACK_BODIES = r'^(Compact Body|Coupe Body|Hatchback Body|minivan body|Offroad Body|Pickup Body|Sedan Body|Sport body|SUV Body|Wagon Body)_'


def _pack(body, length, use):
    return dict(src='car_generic_pack', body=body, length=length, tris=8000, kind='car', use=use)


SF = {
    'car_compact': _pack('Compact Body', 3.9, 'street, parking'),
    'car_coupe': _pack('Coupe Body', 4.4, 'street, parking'),
    'car_hatchback': _pack('Hatchback Body', 4.1, 'street, parking, house'),
    'car_minivan': _pack('minivan body', 4.8, 'street, parking, house'),
    'car_offroad': _pack('Offroad Body', 4.4, 'street, parking, house'),
    'car_pickup': _pack('Pickup Body', 5.3, 'street, parking, factory, gas station'),
    'car_sedan': _pack('Sedan Body', 4.6, 'street, parking, house'),
    'car_sport': _pack('Sport body', 4.4, 'street, parking'),
    'car_suv': _pack('SUV Body', 4.7, 'street, parking, house'),
    'car_wagon': _pack('Wagon Body', 4.7, 'street, parking, house'),
    'car_burnt_a': dict(src='car_burned_out', keep=[r'^default001'], flip=True, length=4.4, tris=8000, kind='wreck', use='street, parking'),
    'car_burnt_b': dict(src='car_burned_out', keep=[r'^default002'], length=4.4, tris=8000, kind='wreck', use='street, parking'),
    'car_saloon_old': dict(src='car_corolla', length=4.3, tris=8000, kind='car', use='street, parking, house'),
    'car_sedan_80s': dict(src='car_negotiator', drop=CAR_DROP, length=4.9, tris=8000, kind='car', use='street, parking, house'),
    'car_sedan_80s_b': dict(src='car_fairheaven', drop=CAR_DROP, length=4.9, tris=8000, kind='car', use='street, parking, house'),
    'van_delivery': dict(src='car_shvan_van', drop=CAR_DROP, length=4.9, tris=8000, kind='car', use='street, parking, store, factory'),
    'car_pickup_old': dict(src='car_doutrive_pickup', drop=CAR_DROP, length=4.9, tris=8000, kind='car', use='street, parking, house, gas station'),
    'car_police_burnt': dict(src='car_police_burned', keep=[r'^Object004'], length=4.8, tris=8000, kind='wreck', use='street, barricade'),
    'car_police_flipped': dict(src='car_police_burned', keep=[r'^Object005'], length=4.8, tris=8000, kind='wreck', use='street, barricade'),
    'jeepney_painted': dict(src='jeepney', length=6.6, tris=15000, kind='vehicle', use='street (stalled on the avenue), terminal'),
    'store_display_case': dict(src='fridge_display', drop=[r'^Object_8'], rot=(0, 0, 180), height=1.3, tris=4000, kind='store', use='store'),
    'store_chiller': dict(src='grocery_case', rot=(0, 0, -90), height=2.0, tris=2000, kind='store', use='store'),
    'store_shelf_wall': dict(src='shelf_etagere', rot=(0, 0, 180), height=1.9, tris=2000, kind='store', use='store'),
    'forklift_a': dict(src='forklift', length=3.3, tris=4000, tex=256, kind='machine', use='factory, warehouse yard'),
    'forklift_b': dict(src='forklift_b', length=3.3, tris=4000, kind='machine', use='factory, warehouse yard'),
    'chem_tanks': dict(src='chemical_tank', height=5.6, tris=12000, kind='machine', use='factory yard'),
    'conveyor': dict(src='conveyor', height=0.9, tris=4000, kind='machine', use='factory floor'),
    'control_pedestal': dict(src='control_panel', height=1.6, tris=2000, kind='machine', use='factory floor'),
    'basketball_hoop': dict(src='basketball_hoop', rot=(0, 0, -90), height=3.95, tris=3000, kind='sport', use='court, clubhouse, playground'),
    'playground_slide': dict(src='slide_abandoned', rot=(0, 0, -90), height=2.1, tris=2000, kind='playground', use='playground, park'),
    'playground_set': dict(src='playground_abandoned', height=2.0, tris=4000, kind='playground', use='playground, park'),
    'traffic_light': dict(src='traffic_light', drop=[r'^Pedestrian'], height=5.4, tris=3000, kind='street', use='street (major intersection)'),
    'ped_signal': dict(src='traffic_light', keep=[r'^Pedestrian'], height=2.75, tris=2000, kind='street', use='street (zebra crossings)'),
    'gas_pump_old': dict(src='gas_pump', drop=[r'^Object_6'], height=1.98, tris=2000, kind='station', use='gas station'),
    'gas_pump_round': dict(src='gas_pump_b', height=1.6, tris=2000, kind='station', use='gas station'),
    'aircon_condenser': dict(src='aircon_condenser', height=0.85, tris=1200, kind='fixture', use='house (outside walls), store, office'),
}

# Downloaded but not processed, and why (also listed in docs/ASSET_MANIFEST.md).
DROPPED = {
    'jeepney_b': 'the file in the Objaverse mirror is not a jeepney (a 74k-triangle scan of loose rocks / debris)',
    'vending_outdoor': 'its textures are covered in a real soft-drink trademark (logos and script); not used',
}

# ------------------------------------------------------------------ helpers


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def glass_fix(m):
    b = P['principled'](m)
    if b is None:
        return
    for k in ('Base Color', 'Roughness', 'Metallic'):
        for l in list(b.inputs[k].links):
            m.node_tree.links.remove(l)
    b.inputs['Base Color'].default_value = (0.018, 0.024, 0.03, 1.0)
    b.inputs['Roughness'].default_value = 0.12
    b.inputs['Metallic'].default_value = 0.0


def bake_single(o, name, size):
    """One material left: still write its textures as files of at most `size` px (the source's are packed in the
    GLB) and rebuild it as base / ORM / normal, like the atlas."""
    m = o.data.materials[0] if o.data.materials else None
    b = P['principled'](m)
    img, _ = P['find_image'](b.inputs['Base Color']) if b is not None else (None, None)
    s = size
    if img is not None and img.image is not None:
        s = min(size, max(img.image.size[0], img.image.size[1], 64))
    base, orm, nor = P['sample'](m, (s, s))
    occ = m is not None and P['occlusion_socket'](m) is not None
    os.makedirs(TEX, exist_ok=True)
    bi = P['save_image'](name + '_diff', base, os.path.join(TEX, name + '_diff.jpg'), 'sRGB', 'JPEG')
    oi = P['save_image'](name + '_arm', orm, os.path.join(TEX, name + '_arm.jpg'), 'Non-Color', 'JPEG')
    ni = P['save_image'](name + '_nor_gl', nor, os.path.join(TEX, name + '_nor_gl.jpg'), 'Non-Color', 'JPEG')
    nm = P['new_material'](name, bi, oi, ni, occ, m is not None and not m.use_backface_culling)
    o.data.materials.clear()
    o.data.materials.append(nm)
    return '%d px textures' % s


def yaw_residual(o):
    """Degrees to turn about Z so the footprint's main axis (area-weighted face centres) lies along Y; within +-45."""
    me = o.data
    n = len(me.polygons)
    c = np.empty(n * 3, np.float32)
    me.polygons.foreach_get('center', c)
    a = np.empty(n, np.float32)
    me.polygons.foreach_get('area', a)
    xy = c.reshape(-1, 3)[:, :2].astype(np.float64)
    w = a.astype(np.float64) / max(float(a.sum()), 1e-9)
    m = (xy * w[:, None]).sum(0)
    d = xy - m
    cov = (d * w[:, None]).T @ d
    vals, vecs = np.linalg.eigh(cov)
    v = vecs[:, int(np.argmax(vals))]
    phi = math.degrees(math.atan2(v[1], v[0]))
    r = 90.0 - phi
    while r > 45.0:
        r -= 90.0
    while r <= -45.0:
        r += 90.0
    return r


def reduce(o, budget):
    """Down to the triangle budget without smearing the textures: first merge coincident vertices and dissolve
    near-flat faces inside each UV island / material (planar decimation keeps every UV seam and material border),
    then collapse what is still over the budget."""
    t0 = tris(o)
    P['select_only']([o])
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.object.mode_set(mode='OBJECT')
    m = o.modifiers.new('planar', 'DECIMATE')
    m.decimate_type = 'DISSOLVE'
    m.angle_limit = math.radians(4.0)
    m.delimit = {'UV', 'MATERIAL', 'SEAM', 'SHARP'}
    bpy.ops.object.modifier_apply(modifier=m.name)
    tr = o.modifiers.new('tri', 'TRIANGULATE')
    bpy.ops.object.modifier_apply(modifier=tr.name)
    t1 = tris(o)
    if t1 > budget:
        P['decimate'](o, budget)
    return 'reduced to its %s-triangle budget (%s -> %s by merging and dissolving flat faces within UV islands, %s after collapsing)' % (
        format(budget, ','), format(t0, ','), format(t1, ','), format(tris(o), ','))


def select_pack_car(cfg):
    """Keeps one car of the turntable pack (its body parts and the four wheels nearest to it) and turns it back from
    its place on the turntable to its own frame."""
    objs = meshes()
    groups = {}
    for o in objs:
        m = re.match(PACK_BODIES, o.name)
        if m:
            groups.setdefault(m.group(1), []).append(o)
    centres = {k: v[0].matrix_world.to_translation() for k, v in groups.items()}
    mine = groups[cfg['body']]
    c = centres[cfg['body']]
    keep = list(mine)
    for o in objs:
        if o in mine or re.match(PACK_BODIES, o.name) or not o.name.startswith('Wheel'):
            continue
        t = o.matrix_world.to_translation()
        near = min(centres, key=lambda k: (centres[k] - t).xy.length)
        if near == cfg['body'] and (c - t).xy.length < 3.5:
            keep.append(o)
    ang = mine[0].matrix_world.to_euler('XYZ').z
    M = (Matrix.Translation(c) @ Matrix.Rotation(ang, 4, 'Z')).inverted()
    for o in objs:
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    for o in keep:
        o.matrix_world = M @ o.matrix_world
    return 'one car of the pack (%s, %d wheels) turned back to its own frame' % (cfg['body'], sum(1 for o in keep if o.name.startswith('Wheel')))


def preview(o, path, title=''):
    """Auto-framed check render: the model, a 1.8 m figure to its right, a red ball at its front (+Z Godot)."""
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'TEXTURE'
    scn.display.shading.show_cavity = True
    scn.render.resolution_x = 640
    scn.render.resolution_y = 480
    scn.world = scn.world or bpy.data.worlds.new('w')
    scn.world.color = (0.42, 0.45, 0.5)
    lo, hi = P['bounds'](o)
    size = hi - lo
    extra = []
    fig = human(Vector((float(hi[0]) + 0.6, 0.0, 0.0)))
    extra += fig
    bpy.ops.mesh.primitive_uv_sphere_add(radius=max(0.03, float(max(size)) * 0.03),
                                         location=(0.0, float(lo[1]) - max(0.05, float(max(size)) * 0.04), float(hi[2]) * 0.5))
    ball = bpy.context.active_object
    mat = bpy.data.materials.new('marker')
    mat.diffuse_color = (1.0, 0.05, 0.05, 1.0)
    ball.data.materials.append(mat)
    extra.append(ball)
    lo2 = Vector((min(float(lo[0]), -0.3), float(lo[1]) - 0.2, 0.0))
    hi2 = Vector((float(hi[0]) + 0.9, float(hi[1]), max(float(hi[2]), 1.85)))
    c = (lo2 + hi2) / 2
    r = (hi2 - lo2).length * 0.5
    cam_data = bpy.data.cameras.new('cam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = r * 2.05
    cam_data.clip_end = r * 20
    cam = bpy.data.objects.new('cam', cam_data)
    scn.collection.objects.link(cam)
    d = Vector((0.9, -1.4, 0.7)).normalized()
    cam.location = c + d * r * 6
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    scn.camera = cam
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    # Top view (front = down in the image) for checking orientation.
    cam.location = c + Vector((0, 0, r * 6))
    cam.rotation_euler = (0, 0, 0)
    scn.render.filepath = path.replace('.png', '_top.png')
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    for e in extra:
        bpy.data.objects.remove(e, do_unlink=True)


def human(at):
    """A 1.8 m figure (legs, torso, head) standing at `at`; returns its objects."""
    out = []
    mat = bpy.data.materials.get('figure') or bpy.data.materials.new('figure')
    mat.diffuse_color = (0.1, 0.35, 0.9, 1.0)
    for size, z in (((0.34, 0.2, 0.86), 0.43), ((0.44, 0.24, 0.62), 1.17)):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(at.x, at.y, z))
        ob = bpy.context.active_object
        ob.scale = size
        ob.data.materials.append(mat)
        out.append(ob)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11, location=(at.x, at.y, 1.69))
    ob = bpy.context.active_object
    ob.data.materials.append(mat)
    out.append(ob)
    return out


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


# ------------------------------------------------------------------ one Sketchfab model

def process_sf(name, cfg):
    src = os.path.join(CACHE, cfg['src'], cfg['src'] + '.glb')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # process_props caches resampled pixels by image name; Sketchfab files all name theirs Image_0, Image_1, ...
    P['_px_cache'].clear()
    bpy.ops.import_scene.gltf(filepath=src)
    bpy.context.scene.frame_set(0)
    notes = []
    if cfg.get('body'):
        notes.append(select_pack_car(cfg))
    removed = []
    for ob in meshes():
        if cfg.get('keep') and not any(re.search(p, ob.name) for p in cfg['keep']):
            removed.append(ob.name)
            bpy.data.objects.remove(ob, do_unlink=True)
        elif cfg.get('drop') and any(re.search(p, ob.name) for p in cfg['drop']):
            removed.append(ob.name)
            bpy.data.objects.remove(ob, do_unlink=True)
    if removed:
        notes.append('removed %d source objects (%s)' % (len(removed), ', '.join(sorted(set(re.sub(r'_[^_]*_\d+$', '', x) for x in removed))[:8]) + (', ...' if len(removed) > 8 else '')))
    o = P['join_all'](name)
    before = tris(o)
    if cfg.get('kind') in ('car', 'wreck', 'vehicle', 'machine') and not cfg.get('rot'):
        # Vehicles: long axis along Y first (pack cars come in both frames), then `flip` turns it end for end.
        lo, hi = P['bounds'](o)
        if float(hi[0] - lo[0]) > float(hi[1] - lo[1]):
            o.data.transform(Matrix.Rotation(math.radians(90), 4, 'Z'))
        res = yaw_residual(o)
        if abs(res) > 2.0:
            o.data.transform(Matrix.Rotation(math.radians(res), 4, 'Z'))
            notes.append('straightened by %.1f deg (the source sits askew in its frame)' % res)
    if cfg.get('rot'):
        o.data.transform(Euler([math.radians(a) for a in cfg['rot']], 'XYZ').to_matrix().to_4x4())
    if cfg.get('flip'):
        o.data.transform(Matrix.Rotation(math.pi, 4, 'Z'))
    lo, hi = P['bounds'](o)
    size = hi - lo
    if 'length' in cfg:
        k = cfg['length'] / float(size[1])
    elif 'height' in cfg:
        k = cfg['height'] / float(size[2])
    else:
        k = cfg.get('scale', 1.0)
    if abs(k - 1.0) > 1e-3:
        o.data.transform(Matrix.Scale(k, 4))
        notes.append('scaled x%.4g to real size' % k)
    lo, hi = P['bounds'](o)
    c = (lo + hi) / 2
    o.data.transform(Matrix.Translation((-float(c[0]), -float(c[1]), -float(lo[2]))))
    lo, hi = P['bounds'](o)
    size = hi - lo
    notes.append('front turned to +Z (Godot), origin at the floor centre')
    b = cfg.get('tris', 2000)
    if tris(o) > b:
        notes.append(reduce(o, b))
        # Collapsing moves vertices: put the floor centre back on the origin.
        lo, hi = P['bounds'](o)
        c = (lo + hi) / 2
        o.data.transform(Matrix.Translation((-float(c[0]), -float(c[1]), -float(lo[2]))))
        lo, hi = P['bounds'](o)
        size = hi - lo
    glassy = [m.name for m in o.data.materials if m and re.search(cfg.get('glass', GLASS), m.name)]
    for m in o.data.materials:
        if m and m.name in glassy:
            glass_fix(m)
    if glassy:
        notes.append('glass made dark and opaque (%s)' % ', '.join(sorted(set(glassy))))
    for m in o.data.materials:
        if m:
            P['make_opaque'](m)
    if not o.data.uv_layers:
        # Flat-coloured source without UVs: every corner samples the middle of its material's atlas cell.
        lay = o.data.uv_layers.new(name='UVMap')
        lay.data.foreach_set('uv', np.full(len(o.data.loops) * 2, 0.5, np.float32))
        notes.append('UVs added (flat colours)')
    tex = cfg.get('tex', 512 if float(max(size)) < 0.6 else 1024)
    P['TEX'] = TEX
    merged = P['merge_materials'](o, name, cfg, tex)
    if merged:
        notes.append(merged)
    else:
        notes.append(bake_single(o, name, tex))
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, name + '.gltf')
    P['select_only']([o])
    bpy.ops.export_scene.gltf(filepath=dst, export_format='GLTF_SEPARATE', use_selection=True, export_yup=True, export_apply=True,
                              export_keep_originals=True, export_image_format='AUTO', export_jpeg_quality=90,
                              export_animations=False, export_cameras=False, export_lights=False, export_extras=False)
    os.makedirs(PREV, exist_ok=True)
    preview(o, os.path.join(PREV, name + '.png'), name)
    after = tris(o)
    mats = len(o.data.materials)
    meta = json.load(open(os.path.join(CACHE, cfg['src'], 'source.json'), encoding='utf-8'))
    meta['files'] = {f: sha(os.path.join(OUT, f)) for f in (name + '.gltf', name + '.bin')}
    for mm in o.data.materials:
        for n in mm.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image is not None:
                f = os.path.basename(n.image.filepath)
                if os.path.exists(os.path.join(TEX, f)):
                    meta['files']['textures/' + f] = sha(os.path.join(TEX, f))
    text = '%s; %s -> %s triangles, %d material%s, %.2f x %.2f x %.2f m (w x h x l) (tools/blender/process_r7.py)' % (
        '; '.join(notes), format(before, ','), format(after, ','), mats, '' if mats == 1 else 's', size[0], size[2], size[1])
    meta['modifications'] = text[0].upper() + text[1:] + '.'
    meta['processed_from'] = os.path.relpath(src, ROOT).replace('\\', '/')
    meta['prop'] = name
    rec = os.path.join(OUT, 'sources')
    os.makedirs(rec, exist_ok=True)
    json.dump(meta, open(os.path.join(rec, name + '.json'), 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
    stats = dict(name=name, src=cfg['src'], tris=after, tris_src=before, mats=mats,
                 size=[round(float(size[0]), 3), round(float(size[2]), 3), round(float(size[1]), 3)])
    print('[r7] %-20s %8d -> %6d tris  %d mat  %.2f x %.2f x %.2f m (w,h,l)  %s' % (name, before, after, mats, size[0], size[2], size[1], text))
    return stats


def render_sheet(names):
    """Same-scale check renders for the contact sheet: every processed model (r7 + the new Poly Haven copies) seen
    from the front-right at one fixed orthographic scale (9 m across), a 1.8 m figure beside it. Cells go to
    work/lemondev/r7/assets/sheet/<name>.png (tools: montage with work/lemondev/r7/assets/make_sheet.py)."""
    out = os.path.join(ROOT, 'work', 'lemondev', 'r7', 'assets', 'sheet')
    os.makedirs(out, exist_ok=True)
    items = [(n, os.path.join(OUT, n + '.gltf')) for n in SF]
    items += [(k, os.path.join(P['OUT'], k + '.gltf')) for k in PH_IDS]
    for name, path in items:
        if names and name not in names:
            continue
        if not os.path.exists(path):
            print('[r7-sheet] MISSING', path)
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        objs = meshes()
        lo = Vector((1e9, 1e9, 1e9))
        hi = -lo
        for o in objs:
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        human(Vector((hi.x + 0.45, 0.0, 0.0)))
        bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.002))
        g = bpy.context.active_object
        gm = bpy.data.materials.new('ground')
        gm.diffuse_color = (0.25, 0.26, 0.27, 1.0)
        g.data.materials.append(gm)
        scn = bpy.context.scene
        scn.render.engine = 'BLENDER_WORKBENCH'
        scn.display.shading.light = 'STUDIO'
        scn.display.shading.color_type = 'TEXTURE'
        scn.display.shading.show_cavity = True
        scn.display.shading.show_shadows = True
        scn.render.resolution_x = 360
        scn.render.resolution_y = 300
        scn.world = bpy.data.worlds.new('w')
        scn.world.color = (0.5, 0.53, 0.58)
        cd = bpy.data.cameras.new('cam')
        cd.type = 'ORTHO'
        cd.ortho_scale = 9.0
        cd.clip_end = 200
        cam = bpy.data.objects.new('cam', cd)
        scn.collection.objects.link(cam)
        d = Vector((0.75, -1.3, 0.55)).normalized()
        target = Vector((0.6, 0.0, 2.6))
        cam.location = target + d * 60
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        scn.camera = cam
        scn.render.filepath = os.path.join(out, name + '.png')
        bpy.ops.render.render(write_still=True)
        print('[r7-sheet] %s %.2f x %.2f x %.2f' % (name, hi.x - lo.x, hi.z - lo.z, hi.y - lo.y))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if '--sheet' in argv:
        render_sheet([a for a in argv if not a.startswith('--')])
        return
    if argv == ['--list']:
        print('[r7] sketchfab: ' + ' '.join(SF))
        print('[r7] polyhaven: ' + ' '.join(PH))
        return
    do_ph = '--sf' not in argv
    do_sf = '--ph' not in argv
    names = [a for a in argv if not a.startswith('--')]
    stats_path = os.path.join(ROOT, 'work', 'lemondev', 'r7', 'assets', 'process_stats.json')
    stats = json.load(open(stats_path)) if os.path.exists(stats_path) else {}
    if do_sf:
        for name, cfg in SF.items():
            if names and name not in names:
                continue
            try:
                stats[name] = process_sf(name, cfg)
            except Exception as e:
                import traceback
                traceback.print_exc()
                print('[r7] FAILED %s: %s' % (name, e))
    if do_ph:
        for mid, cfg in PH.items():
            if names and mid not in names:
                continue
            try:
                P['_px_cache'].clear()
                P['TEX'] = PH_TEX
                P['process'](mid, cfg)
            except Exception as e:
                import traceback
                traceback.print_exc()
                print('[r7] FAILED %s: %s' % (mid, e))
    os.makedirs(os.path.dirname(stats_path), exist_ok=True)
    json.dump(stats, open(stats_path, 'w'), indent=1)


main()
