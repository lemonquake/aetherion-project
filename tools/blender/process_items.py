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
PREV = os.path.join(ROOT, 'work', 'lemondev', 'r5', 'items')

# length: overall length in metres along the front axis (guns: muzzle to butt).
ITEMS = {
    # objs: {part: [substrings of source object names]}; boxes: {part: [[u0, u1, v0, v1], ...]} (see split_boxes); parts
    # are the pieces the first-person animations move: mag, slide, bolt, pump, cylinder, barrel, cover.
    'pistol_9': dict(src='pistol_92fs', length=0.217, gun=True, tris=9000, boxes={'slide': [[0.0, 1.0, 0.72, 1.0]]}, cut=['slide']),
    'pistol_45': dict(src='pistol_1911', length=0.216, gun=True, tris=9000, boxes={'slide': [[0.0, 1.0, 0.72, 1.0]]}, cut=['slide']),
    'revolver_357': dict(src='revolver_nagant', length=0.235, gun=True, tris=9000, drop=['Chain'], upflip=True, rot=(12, 0, 0),
                         objs={'cylinder': ['Drum', 'Case', 'Projectile']}),
    'shotgun_pump': dict(src='shotgun_870', length=1.0, gun=True, tris=10000, boxes={'pump': [[0.16, 0.37, 0.5, 0.72]]}, cut=['pump']),
    'smg_9': dict(src='smg_mp5', length=0.68, gun=True, tris=10000, keep=['Object_9'], rot=(-10, 0, 0), boxes={'mag': [[0.24, 0.42, 0.0, 0.55]]}, cut=['mag']),
    'machine_pistol': dict(src='smg_microuzi', length=0.27, gun=True, tris=8000, drop=['shell'],
                           objs={'mag': ['magazine'], 'slide': ['slide']}),
    'rifle_556': dict(src='rifle_m16', length=1.0, gun=True, tris=12000,
                      objs={'mag': ['MAGAZINE'], 'bolt': ['CHANRIGN HANDLE', 'BOLT CARRIER']}),
    'rifle_762': dict(src='rifle_ak', length=0.88, gun=True, tris=12000, boxes={'mag': [[0.45, 0.62, 0.0, 0.5]]}),
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
    'rifle_scar': dict(src='rifle_scar', length=0.89, gun=True, tris=12000, drop=['Icosphere'], boxes={'mag': [[0.44, 0.58, 0.0, 0.48]]}),
    'rifle_m416': dict(src='rifle_m416', length=0.84, gun=True, tris=12000, boxes={'mag': [[0.42, 0.56, 0.0, 0.48]]}),
    'rifle_m762': dict(src='rifle_beryl_tt', length=0.94, gun=True, tris=12000, drop=['Icosphere'], boxes={'mag': [[0.48, 0.63, 0.0, 0.5]]}),
    'dmr_mini14': dict(src='dmr_mini14', length=0.95, gun=True, tris=10000, boxes={'mag': [[0.44, 0.58, 0.05, 0.55]]}, cut=['mag']),
    'dmr_sks': dict(src='dmr_sks', length=1.02, gun=True, tris=10000),
    'bolt_kar98': dict(src='bolt_kar98', length=1.11, gun=True, tris=10000, boxes={'bolt': [[0.62, 0.78, 0.45, 0.7]]}),
    'smg_ump45': dict(src='smg_ump45', length=0.69, gun=True, tris=10000, flip=True, objs={'mag': ['mazagine']}),
    'smg_vector': dict(src='smg_vector_c', length=0.62, gun=True, tris=10000, objs={'mag': ['Magazine']}),
    'smg_tommy': dict(src='smg_thompson', length=0.81, gun=True, tris=12000, boxes={'mag': [[0.42, 0.485, 0.0, 0.84]]}, cut=['mag']),
    'lmg_m249': dict(src='lmg_m249', length=1.04, gun=True, tris=12000, boxes={'mag': [[0.48, 0.58, 0.25, 0.56]]}, cut=['mag']),
    'shotgun_saiga': dict(src='shotgun_saiga', length=0.97, gun=True, tris=10000, boxes={'mag': [[0.39, 0.5, 0.0, 0.52]]}, cut=['mag']),
    'pistol_deagle': dict(src='pistol_deagle', length=0.27, gun=True, tris=9000, drop=['BulletCase', 'Bullet_low'],
                          objs={'slide': ['Slide_low_Slide', 'FrontSight_low', 'RearSight_low', 'Safety_low', 'BoltMain',
                                          'BoltAdd', 'SlidePart', 'BoltButton', 'BoltBack'],
                                'mag': ['_Magazine_0']}),
    # 2026-10-28 (r5): downloaded models replace the code-built S686, Sumpak and SLR and the decimated Poly Haven
    # P92 / M24 stand-ins, and the blocky UZI, Tommy, Beryl and revolver.
    'shotgun_double': dict(src='shotgun_db_schris', length=1.05, gun=True, tris=9000, boxes={'barrel': [[0.0, 0.62, 0.55, 1.0]]}, cut=['barrel']),
    'sumpak': dict(src='shotgun_pipe_ph', length=0.95, gun=True, tris=4000, boxes={'barrel': [[0.0, 0.38, 0.85, 1.0]]}, cut=['barrel']),
    'marksman_308': dict(src='rifle_fal', length=1.09, gun=True, tris=12000, boxes={'mag': [[0.52, 0.61, 0.0, 0.5]]}, cut=['mag']),
    'bolt_308': dict(src='bolt_m24', length=1.09, gun=True, tris=12000,
                     drop=['Scope', 'BIpod Mount', 'Bipod', '7.62x51', 'Sling Mount'],
                     objs={'mag': ['Magazine'], 'bolt': ['Charging Handle', 'Bolt_Bolt Back']}),
}


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _drop_match(name, pats):
    return any(name.startswith(d) or ('*' + d) in ('*' + name) for d in pats)


def gather(cfg):
    """Imported meshes -> {role: object}. Skinned meshes are baked in their rest pose and armatures removed; objects
    named in cfg['objs'] become their role's part, everything else is 'body'."""
    drop, keep = cfg.get('drop'), cfg.get('keep')
    for o in list(bpy.context.scene.objects):
        if o.type == 'MESH' and drop and _drop_match(o.name, drop):
            bpy.data.objects.remove(o, do_unlink=True)
    if keep:
        for o in list(bpy.context.scene.objects):
            if o.type == 'MESH' and o.name not in keep:
                bpy.data.objects.remove(o, do_unlink=True)
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        for m in list(o.modifiers):
            with bpy.context.temp_override(object=o, active_object=o):
                try:
                    bpy.ops.object.modifier_apply(modifier=m.name)
                except RuntimeError:
                    o.modifiers.remove(m)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    # Bake parent transforms into each mesh before joining.
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for x in list(bpy.context.scene.objects):
        if x.type != 'MESH':
            bpy.data.objects.remove(x, do_unlink=True)
    groups = {}
    for o in objs:
        role = 'body'
        for r, pats in (cfg.get('objs') or {}).items():
            if any(pt in o.name for pt in pats):
                role = r
                break
        groups.setdefault(role, []).append(o)
    parts = {}
    for role, os_ in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in os_:
            o.select_set(True)
        bpy.context.view_layer.objects.active = os_[0]
        if len(os_) > 1:
            bpy.ops.object.join()
        o = bpy.context.view_layer.objects.active
        o.name = role
        o.data.name = role
        parts[role] = o
    return parts


def join_all(keep=None, drop=None):
    parts = gather({'keep': keep, 'drop': drop})
    objs = list(parts.values())
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = 'item'
    return o


def verts(o):
    return [v.co.copy() for v in o.data.vertices]


def extent(vs):
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def orient(o, cfg):
    M = orient_matrix(verts(o), cfg)
    o.data.transform(M)
    o.data.update()


def orient_matrix(vs, cfg):
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
    if cfg.get('pre_rot'):
        # The source is tilted (a revolver lying at an angle): straighten it before the axes are guessed.
        rx, ry, rz = cfg['pre_rot']
        P = Matrix.Rotation(math.radians(rz), 4, 'Z') @ Matrix.Rotation(math.radians(ry), 4, 'Y') @ Matrix.Rotation(math.radians(rx), 4, 'X')
        return orient_matrix([P @ v for v in vs], dict(cfg, pre_rot=None)) @ P
    if cfg.get('rot'):
        rx, ry, rz = cfg['rot']
        M = Matrix.Rotation(math.radians(rz), 4, 'Z') @ Matrix.Rotation(math.radians(ry), 4, 'Y') @ Matrix.Rotation(math.radians(rx), 4, 'X') @ M
    return M


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


def split_boxes(parts, cfg):
    """Moves pieces of the body into moving parts by region. Boxes are [u0, u1, v0, v1]: u runs along the gun from the
    muzzle (0) to the butt (1), v from the lowest point (0) to the top (1). A loose piece goes when its centre is in a
    box and most of its vertices are; with 'cut' the body's faces are taken one by one by their centres (for models
    welded into one piece)."""
    allv = [v for o in parts.values() for v in verts(o)]
    lo, hi = extent(allv)
    L, H = hi.y - lo.y, hi.z - lo.z

    def inside(p, boxes):
        u, v = (hi.y - p.y) / L, (p.z - lo.z) / H
        return any(b[0] <= u <= b[1] and b[2] <= v <= b[3] for b in boxes)

    cut = set(cfg.get('cut', []))
    for role, boxes in (cfg.get('boxes') or {}).items():
        body = parts['body']
        bm = bmesh.new()
        bm.from_mesh(body.data)
        bm.faces.ensure_lookup_table()
        take = set()
        if role in cut:
            for f in bm.faces:
                if inside(f.calc_center_median(), boxes):
                    take.add(f.index)
        else:
            seen = set()
            for f in bm.faces:
                if f.index in seen:
                    continue
                comp, stack = [], [f]
                seen.add(f.index)
                while stack:
                    g = stack.pop()
                    comp.append(g)
                    for e in g.edges:
                        for h in e.link_faces:
                            if h.index not in seen:
                                seen.add(h.index)
                                stack.append(h)
                vs = {v.index: v.co for g in comp for v in g.verts}
                c = sum(vs.values(), Vector()) / len(vs)
                share = sum(1 for co in vs.values() if inside(co, boxes)) / len(vs)
                if inside(c, boxes) and share >= 0.7:
                    take.update(g.index for g in comp)
        bm.free()
        if not take:
            print('[items]   %s: nothing in the %s boxes' % (cfg.get('src'), role))
            continue
        part = body.copy()
        part.data = body.data.copy()
        bpy.context.scene.collection.objects.link(part)
        for ob, keep_taken in ((part, True), (body, False)):
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bm.faces.ensure_lookup_table()
            dead = [f for f in bm.faces if (f.index in take) != keep_taken]
            bmesh.ops.delete(bm, geom=dead, context='FACES')
            bm.to_mesh(ob.data)
            bm.free()
            ob.data.update()
        if role in parts:
            bpy.ops.object.select_all(action='DESELECT')
            parts[role].select_set(True)
            part.select_set(True)
            bpy.context.view_layer.objects.active = parts[role]
            bpy.ops.object.join()
        else:
            part.name = role
            part.data.name = role
            parts[role] = part


PART_COLORS = {'mag': (0.95, 0.75, 0.1), 'slide': (0.2, 0.8, 1.0), 'bolt': (1.0, 0.3, 0.9), 'pump': (0.3, 1.0, 0.3),
               'cylinder': (1.0, 0.45, 0.1), 'barrel': (0.5, 0.5, 1.0), 'cover': (0.9, 0.2, 0.2), 'rounds': (0.9, 0.9, 0.3)}


def preview_parts(parts, path, length):
    """Two side views: textured, and with every moving part in its own flat colour. A grid marks tenths of the length
    (u from the muzzle) and of the height (v from the bottom), for writing region boxes."""
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.render.resolution_x = 1000
    scn.render.resolution_y = 500
    scn.world = bpy.data.worlds.new('w') if scn.world is None else scn.world
    scn.world.color = (0.5, 0.52, 0.55)
    cam_data = bpy.data.cameras.new('cam')
    cam_data.type = 'ORTHO'
    lo, hi = extent([v for o in parts.values() for v in verts(o)])
    ortho = max(length * 1.1, (hi.z - lo.z) * 2.3)
    cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new('cam', cam_data)
    scn.collection.objects.link(cam)
    # Look from the gun's left side (-X) toward +X: front (+Y) appears on the right, up (+Z) up.
    cam.location = (-length * 3.0, 0, 0)
    cam.rotation_euler = (math.radians(90), 0, math.radians(-90))
    scn.camera = cam
    base = os.path.splitext(path)[0]
    scn.display.shading.color_type = 'TEXTURE'
    scn.render.filepath = base + '.png'
    bpy.ops.render.render(write_still=True)
    saved = []
    for role, o in parts.items():
        if role in PART_COLORS:
            m = bpy.data.materials.new('pv_' + role)
            m.diffuse_color = PART_COLORS[role] + (1.0,)
            saved.append((o, [sl.material for sl in o.material_slots]))
            for sl in o.material_slots:
                sl.material = m
    scn.display.shading.color_type = 'MATERIAL'
    scn.render.filepath = base + '_parts.png'
    bpy.ops.render.render(write_still=True)
    for o, mats in saved:
        for sl, m in zip(o.material_slots, mats):
            sl.material = m
    bpy.data.objects.remove(cam, do_unlink=True)
    return {'length': length, 'lo': list(lo), 'hi': list(hi), 'ortho': ortho, 'res': [1000, 500]}


def process(item_id, cfg):
    clear()
    src = os.path.join(SRC, cfg['src'], cfg['src'] + '.glb')
    bpy.ops.import_scene.gltf(filepath=src)
    parts = gather(cfg)
    M = orient_matrix([v for o in parts.values() for v in verts(o)], cfg)
    for o in parts.values():
        o.data.transform(M)
    lo, hi = extent([v for o in parts.values() for v in verts(o)])
    k = cfg['length'] / max(hi.y - lo.y, 1e-6)
    c = (lo + hi) * 0.5
    for o in parts.values():
        o.data.transform(Matrix.Scale(k, 4) @ Matrix.Translation(-c))
        o.data.update()
    split_boxes(parts, cfg)
    before = sum(tris(o) for o in parts.values())
    ratio = min(1.0, cfg.get('tris', 10000) / max(before, 1))
    for o in parts.values():
        t = tris(o)
        decimate(o, max(int(t * ratio), min(t, 400)))
    after = sum(tris(o) for o in parts.values())
    shrink_images()
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    view = preview_parts(parts, os.path.join(PREV, item_id + '.png'), cfg['length'])
    json.dump(view, open(os.path.join(PREV, item_id + '.view.json'), 'w'))
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts.values():
        o.select_set(True)
    dst = os.path.join(OUT, item_id + '.glb')
    bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
                              export_image_format='JPEG', export_jpeg_quality=88)
    meta = json.load(open(os.path.join(SRC, cfg['src'], 'source.json'), encoding='utf-8'))
    meta['files'] = {item_id + '.glb': ''}
    moving = sorted(r for r in parts if r != 'body')
    meta['modifications'] = ('Re-oriented (front along -Z in Godot), scaled to %.3f m overall, centred, decimated %d -> %d '
                             'triangles, textures reduced to 1024 px JPEG%s (tools/blender/process_items.py).'
                             % (cfg['length'], before, after,
                                '; moving parts kept as separate meshes: ' + ', '.join(moving) if moving else ''))
    meta['processed_from'] = 'tools/cache/sketchfab/%s/%s.glb' % (cfg['src'], cfg['src'])
    rec = os.path.join(OUT, 'sources')
    os.makedirs(rec, exist_ok=True)
    json.dump(meta, open(os.path.join(rec, item_id + '.json'), 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
    print('[items] %-16s %6d -> %6d tris  parts %s' % (item_id, before, after, ','.join(sorted(parts))))


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
