"""Turn the downloaded Sketchfab weapon and gear models into game-ready GLBs.

    blender -b --factory-startup -P tools/blender/process_items.py [-- id ...]

Reads tools/cache/sketchfab/<src>/<src>.glb and writes game/assets/models/items/<id>.glb plus a side-view check
render in work/items/<id>.png (a red ball marks the muzzle / front).

Every model is joined into one object, re-oriented so its front points along Blender +Y (Godot -Z) with +Z up,
scaled to its real overall length, centred on its bounding box, decimated to a triangle budget, and its textures
are reduced to 1024 px. Guns are oriented automatically: the long axis is the bore, the thinner end is the muzzle,
and the side the grip and magazine hang from is down; `flip` / `upflip` / `rot` override that where it guesses wrong.
Each output folder gets a source.json carrying the original credits and the modifications.
"""
import bpy, bmesh, os, sys, json, math
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'tools', 'cache', 'sketchfab')
OUT = os.path.join(ROOT, 'game', 'assets', 'models', 'items')
PREV = os.path.join(ROOT, 'work', 'items')

# length: overall length in metres along the front axis (guns: muzzle to butt).
ITEMS = {
    'pistol_45': dict(src='pistol_1911', length=0.216, gun=True, tris=9000),
    'revolver_357': dict(src='revolver_357', length=0.29, gun=True, tris=8000),
    'shotgun_pump': dict(src='shotgun_870', length=1.0, gun=True, tris=10000),
    'smg_9': dict(src='smg_mp5', length=0.68, gun=True, tris=10000, keep=['Object_9'], rot=(-10, 0, 0)),
    'machine_pistol': dict(src='smg_uzi', length=0.47, gun=True, tris=8000),
    'rifle_556': dict(src='rifle_m16', length=1.0, gun=True, tris=12000),
    'rifle_762': dict(src='rifle_ak', length=0.88, gun=True, tris=12000),
    'sight_reddot': dict(src='sight_reddot', length=0.09, gun=False, tris=4000),
    'sight_holo': dict(src='sight_holo', length=0.1, gun=False, tris=4000),
    'scope_4x': dict(src='scope_acog', length=0.16, gun=False, tris=5000),
    'flashlight': dict(src='flashlight_tactical', length=0.15, gun=True, tris=4000, flip=True),
    'helmet_light': dict(src='helmet_light', length=0.29, gun=False, tris=6000),
    'helmet_heavy': dict(src='helmet_heavy', length=0.31, gun=False, tris=7000),
    'vest_light': dict(src='vest_military', length=0.62, gun=False, tris=9000),
    'vest_heavy': dict(src='vest_combat', length=0.66, gun=False, tris=10000),
    'first_aid': dict(src='first_aid_kit', length=0.26, gun=False, tris=4000),
    'radio': dict(src='walkie_talkie', length=0.21, gun=False, tris=3000),
    # 2026-10-27 weapon variety (see tools/patches/p83_weapon_sources.py).
    'rifle_scar': dict(src='rifle_scar', length=0.89, gun=True, tris=12000),
    'rifle_m416': dict(src='rifle_m416', length=0.84, gun=True, tris=12000),
    'rifle_m762': dict(src='rifle_m762', length=0.9, gun=True, tris=12000),
    'dmr_mini14': dict(src='dmr_mini14', length=0.95, gun=True, tris=10000),
    'dmr_sks': dict(src='dmr_sks', length=1.02, gun=True, tris=10000),
    'bolt_kar98': dict(src='bolt_kar98', length=1.11, gun=True, tris=10000),
    'smg_ump45': dict(src='smg_ump45', length=0.69, gun=True, tris=10000, flip=True),
    'smg_vector': dict(src='smg_vector_c', length=0.62, gun=True, tris=10000),
    'smg_tommy': dict(src='smg_tommy', length=0.81, gun=True, tris=10000),
    'lmg_m249': dict(src='lmg_m249', length=1.04, gun=True, tris=12000),
    'shotgun_saiga': dict(src='shotgun_saiga', length=0.97, gun=True, tris=10000),
    'pistol_deagle': dict(src='pistol_deagle', length=0.27, gun=True, tris=9000, drop=['BulletCase', 'Bullet_low']),
}


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def join_all(keep=None, drop=None):
    for o in list(bpy.context.scene.objects):
        if drop and o.type == 'MESH' and any(o.name.startswith(d) for d in drop):
            bpy.data.objects.remove(o, do_unlink=True)
    if keep:
        for o in list(bpy.context.scene.objects):
            if o.type == 'MESH' and o.name not in keep:
                bpy.data.objects.remove(o, do_unlink=True)
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    # Bake parent transforms into each mesh before joining.
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    for x in list(bpy.context.scene.objects):
        if x != o:
            bpy.data.objects.remove(x, do_unlink=True)
    o.name = 'item'
    return o


def verts(o):
    return [v.co.copy() for v in o.data.vertices]


def extent(vs):
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def orient(o, cfg):
    vs = verts(o)
    lo, hi = extent(vs)
    ext = hi - lo
    axes = [0, 1, 2]
    long = max(axes, key=lambda a: ext[a])
    rest = [a for a in axes if a != long]
    up = max(rest, key=lambda a: ext[a]) if cfg.get('gun') else 2 if long != 2 else rest[1]
    if not cfg.get('gun') and long == 2:
        up = max(rest, key=lambda a: ext[a])
    # Muzzle: the end whose last 15% has the smaller cross-section (barrel vs stock/grip).
    span = ext[long]
    def section(sign):
        sel = [v for v in vs if (v[long] - lo[long] if sign < 0 else hi[long] - v[long]) < span * 0.15]
        if not sel:
            return 0.0
        a = max(v[up] for v in sel) - min(v[up] for v in sel)
        b = max(v[rest[0] if rest[0] != up else rest[1]] for v in sel) - min(v[rest[0] if rest[0] != up else rest[1]] for v in sel)
        return a * b
    front_sign = 1.0 if section(1) < section(-1) else -1.0
    if cfg.get('flip'):
        front_sign = -front_sign
    # Down: the side of the bore line with more material (grip, magazine, trigger guard).
    tip = [v for v in vs if (hi[long] - v[long] if front_sign > 0 else v[long] - lo[long]) < span * 0.1]
    bore = sum(v[up] for v in tip) / max(len(tip), 1)
    above = hi[up] - bore
    below = bore - lo[up]
    up_sign = 1.0 if below >= above else -1.0
    if not cfg.get('gun'):
        up_sign = 1.0
    if cfg.get('upflip'):
        up_sign = -up_sign
    Y = Vector((0, 0, 0)); Y[long] = front_sign
    Z = Vector((0, 0, 0)); Z[up] = up_sign
    X = Y.cross(Z)
    R = Matrix((X, Y, Z))  # rows: new axes in old coordinates
    M = R.to_4x4()
    o.data.transform(M)
    if cfg.get('rot'):
        rx, ry, rz = cfg['rot']
        o.data.transform(Matrix.Rotation(math.radians(rz), 4, 'Z') @ Matrix.Rotation(math.radians(ry), 4, 'Y') @ Matrix.Rotation(math.radians(rx), 4, 'X'))
    o.data.update()


def fit(o, length):
    lo, hi = extent(verts(o))
    s = length / max(hi.y - lo.y, 1e-6)
    o.data.transform(Matrix.Scale(s, 4))
    lo, hi = extent(verts(o))
    c = (lo + hi) * 0.5
    o.data.transform(Matrix.Translation(-c))
    o.data.update()


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def decimate(o, budget):
    t = tris(o)
    if t <= budget:
        return t
    m = o.modifiers.new('dec', 'DECIMATE')
    m.ratio = budget / t
    m.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier='dec')
    return tris(o)


def shrink_images(limit=1024):
    for img in bpy.data.images:
        if img.size[0] > limit or img.size[1] > limit:
            k = limit / max(img.size[0], img.size[1])
            img.scale(max(int(img.size[0] * k), 1), max(int(img.size[1] * k), 1))


def preview(o, path, length):
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'TEXTURE'
    scn.render.resolution_x = 900
    scn.render.resolution_y = 420
    scn.render.film_transparent = False
    scn.world = bpy.data.worlds.new('w') if scn.world is None else scn.world
    lo, hi = extent(verts(o))
    # Marker at the front end.
    bpy.ops.mesh.primitive_uv_sphere_add(radius=length * 0.03, location=(0, hi.y, 0))
    mk = bpy.context.active_object
    mat = bpy.data.materials.new('marker')
    mat.diffuse_color = (1, 0, 0, 1)
    mk.data.materials.append(mat)
    cam_data = bpy.data.cameras.new('cam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = length * 1.25
    cam = bpy.data.objects.new('cam', cam_data)
    scn.collection.objects.link(cam)
    # Look from the gun's left side (-X) toward +X: front (+Y) appears on the right, up (+Z) up.
    cam.location = (-length * 3.0, 0, 0)
    cam.rotation_euler = (math.radians(90), 0, math.radians(-90))
    scn.camera = cam
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(mk, do_unlink=True)
    bpy.data.objects.remove(cam, do_unlink=True)


def process(item_id, cfg):
    clear()
    src = os.path.join(SRC, cfg['src'], cfg['src'] + '.glb')
    bpy.ops.import_scene.gltf(filepath=src)
    o = join_all(cfg.get('keep'), cfg.get('drop'))
    orient(o, cfg)
    fit(o, cfg['length'])
    before = tris(o)
    after = decimate(o, cfg.get('tris', 10000))
    shrink_images()
    os.makedirs(os.path.join(OUT), exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    preview(o, os.path.join(PREV, item_id + '.png'), cfg['length'])
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    dst = os.path.join(OUT, item_id + '.glb')
    bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
                              export_image_format='JPEG', export_jpeg_quality=88)
    meta = json.load(open(os.path.join(SRC, cfg['src'], 'source.json'), encoding='utf-8'))
    meta['files'] = {item_id + '.glb': ''}
    meta['modifications'] = ('Joined into one mesh, re-oriented (front along -Z in Godot), scaled to %.3f m overall, centred, '
                             'decimated %d -> %d triangles, textures reduced to 1024 px JPEG (tools/blender/process_items.py).'
                             % (cfg['length'], before, after))
    meta['processed_from'] = 'tools/cache/sketchfab/%s/%s.glb' % (cfg['src'], cfg['src'])
    rec = os.path.join(OUT, 'sources')
    os.makedirs(rec, exist_ok=True)
    json.dump(meta, open(os.path.join(rec, item_id + '.json'), 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
    print('[items] %-16s %6d -> %6d tris  -> %s' % (item_id, before, after, dst))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    for item_id, cfg in ITEMS.items():
        if argv and item_id not in argv:
            continue
        try:
            process(item_id, cfg)
        except Exception as e:
            print('[items] FAILED %s: %s' % (item_id, e))


main()
