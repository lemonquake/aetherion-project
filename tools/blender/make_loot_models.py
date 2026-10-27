"""Builds the procedural loot models: weapon attachments, small items, ammunition boxes, loot boxes and three guns.

    python -I tools/make_loot_textures.py          (textures first)
    blender -b --factory-startup -P tools/blender/make_loot_models.py [-- id ...]

Writes game/assets/models/loot/<id>.glb (loot boxes also <id>_open.glb, with the lid open) and a check render per
model in work/loot_models/<id>.png. Everything is modelled here from code; textures come from tools/cache/loot_tex.

Conventions (Blender axes): +Y is the front (Godot -Z), +Z is up, sizes in metres. The game finds mount points from
each model's bounds, so attachments are modelled against a fixed interface:
  sights, cheek pads ... base (rail contact) at the bottom
  muzzle devices ....... the threaded end at the rear, bore along Y at z = 0
  grips, lights, lasers  rail clamp at the top
  magazines ............ the feed lips at the top
  stocks ............... the hinge at the front
Guns are centred on their bounds like the processed Sketchfab guns; their grip and fore-end positions are given in
game/data/weapons.json ("hold").
"""
import bpy, bmesh, os, sys, math, json
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEX = os.path.join(ROOT, 'tools', 'cache', 'loot_tex')
OUT = os.path.join(ROOT, 'game', 'assets', 'models', 'loot')
PREV = os.path.join(ROOT, 'work', 'loot_models')
INFO = {}
_MATS = {}
_IMGS = {}
RX = Matrix.Rotation(-math.pi / 2, 4, 'X')   # Z axis -> Y axis


# ------------------------------------------------------------------ scene, materials

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()
    _IMGS.clear()


def image(name):
    if name not in _IMGS:
        _IMGS[name] = bpy.data.images.load(os.path.join(TEX, name + '.png'))
    return _IMGS[name]


def mat(name, color=(0.5, 0.5, 0.5), rough=0.6, metal=0.0, tex=None, alpha=1.0):
    key = name
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if tex:
        tn = nt.nodes.new('ShaderNodeTexImage')
        tn.image = image(tex)
        nt.links.new(tn.outputs['Color'], bsdf.inputs['Base Color'])
    if alpha < 1.0:
        bsdf.inputs['Alpha'].default_value = alpha
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            m.blend_method = 'BLEND'
    _MATS[key] = m
    return m


def M(kind):
    """Shared material palette."""
    table = {
        'blued': dict(tex='metal_black', rough=0.42, metal=0.85),
        'parker': dict(tex='metal_dark', rough=0.55, metal=0.7),
        'steel': dict(color=(0.55, 0.56, 0.58), rough=0.35, metal=0.9),
        'galv': dict(tex='metal_galv', rough=0.5, metal=0.8),
        'alu': dict(tex='metal_black', rough=0.5, metal=0.6),
        'olive': dict(tex='metal_olive', rough=0.6, metal=0.4),
        'red_steel': dict(tex='metal_red', rough=0.45, metal=0.5),
        'polymer': dict(tex='polymer_black', rough=0.7),
        'tan': dict(tex='polymer_tan', rough=0.7),
        'rubber': dict(tex='rubber', rough=0.9),
        'tape': dict(tex='tape_black', rough=0.35),
        'walnut': dict(tex='wood_walnut', rough=0.55),
        'rawwood': dict(tex='wood_raw', rough=0.8),
        'greenwood': dict(tex='wood_green', rough=0.7),
        'glass': dict(color=(0.08, 0.12, 0.1), rough=0.05, alpha=0.35),
        'lens_red': dict(color=(0.5, 0.05, 0.04), rough=0.1, alpha=0.6),
        'lens_clear': dict(color=(0.55, 0.7, 0.85), rough=0.05, alpha=0.1),
        'lens_light': dict(color=(0.85, 0.85, 0.8), rough=0.1),
        'brass': dict(tex='brass', rough=0.35, metal=0.9),
        'shell_red': dict(tex='shell_red', rough=0.5),
        'shell_yellow': dict(tex='shell_yellow', rough=0.5),
        'white': dict(tex='plastic_white', rough=0.45),
        'blue': dict(tex='plastic_blue', rough=0.45),
        'grey': dict(tex='plastic_grey', rough=0.5),
        'foam': dict(tex='foam_black', rough=0.95),
        'foam_grey': dict(tex='foam_grey', rough=0.95),
        'navy': dict(tex='nylon_navy', rough=0.85),
        'nylon_olive': dict(tex='nylon_olive', rough=0.85),
        'nylon_black': dict(tex='nylon_black', rough=0.85),
        'nylon_grey': dict(tex='nylon_grey', rough=0.85),
        'cardboard': dict(tex='cardboard', rough=0.9),
        'balikbayan': dict(tex='balikbayan', rough=0.9),
        'tapebrown': dict(color=(0.55, 0.4, 0.22), rough=0.3),
        'bandage': dict(tex='bandage', rough=0.95),
        'pills': dict(tex='pill_label', rough=0.4),
        'battery': dict(tex='battery_wrap', rough=0.35, metal=0.2),
        'splint_o': dict(tex='splint_orange', rough=0.8),
        'splint_b': dict(tex='splint_blue', rough=0.8),
        'medlid': dict(tex='medkit_lid', rough=0.45),
        'ammocan': dict(tex='ammocan', rough=0.6, metal=0.4),
        'cooler': dict(tex='cooler', rough=0.45),
        'dark': dict(color=(0.02, 0.02, 0.02), rough=0.9),
    }
    return mat(kind, **table[kind])


# ------------------------------------------------------------------ mesh helpers

def obj(name, bm, material, uv='box', uv_scale=4.0, smooth=False):
    if uv == 'box':
        box_uv(bm, uv_scale)
    elif uv == 'cyl':
        cyl_uv(bm)
    elif callable(uv):
        uv(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(material)
    return o


def box_uv(bm, s):
    layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            c = l.vert.co
            if ax == 0:
                l[layer].uv = (c.y * s, c.z * s)
            elif ax == 1:
                l[layer].uv = (c.x * s, c.z * s)
            else:
                l[layer].uv = (c.x * s, c.y * s)


def cyl_uv(bm, axis=1):
    """Wrap label around a cylinder along `axis` (u = angle, v = position along the axis)."""
    layer = bm.loops.layers.uv.verify()
    vs = [v.co[axis] for v in bm.verts]
    lo, hi = min(vs), max(vs)
    other = [i for i in range(3) if i != axis]
    for f in bm.faces:
        side = abs(f.normal[axis]) < 0.5
        us = []
        for l in f.loops:
            c = l.vert.co
            a = math.atan2(-c[other[0]], c[other[1]]) / (2 * math.pi) + 0.5
            us.append(a)
        # Keep each face on one side of the seam.
        if side and max(us) - min(us) > 0.5:
            us = [u + 1.0 if u < 0.5 else u for u in us]
        for l, u in zip(f.loops, us):
            c = l.vert.co
            if side:
                l[layer].uv = (u, (c[axis] - lo) / max(hi - lo, 1e-6))
            else:
                l[layer].uv = (c[other[0]] * 4 + 0.5, c[other[1]] * 4 + 0.5)


def bevel(bm, off, segs=2):
    if off <= 0:
        return
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=off, offset_type='OFFSET', segments=segs, profile=0.5,
                    affect='EDGES', clamp_overlap=True)


def cube(name, size, loc=(0, 0, 0), material=None, bev=0.0015, segs=2, rot=None, uv='box', uv_scale=4.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bevel(bm, min(bev, min(size) * 0.45), segs)
    if rot:
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return obj(name, bm, material, uv=uv, uv_scale=uv_scale)


def cyl(name, r, depth, loc=(0, 0, 0), material=None, axis='Y', segs=24, r2=None, bev=0.0, uv='box', smooth=True, rot=None):
    """Cylinder (or cone with r2) centred on loc, along axis."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=depth)
    bevel(bm, bev, 2)
    if axis == 'Y':
        bmesh.ops.transform(bm, matrix=RX, verts=bm.verts)
    elif axis == 'X':
        bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.pi / 2, 4, 'Y'), verts=bm.verts)
    if rot:
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return obj(name, bm, material, uv=uv, smooth=smooth)


def lathe(name, profile, material, loc=(0, 0, 0), axis='Y', segs=32, uv='cyl', smooth=True, rot=None):
    """Surface of revolution. profile: [(radius, along)] from one end to the other; closed with caps if r starts/ends 0."""
    bm = bmesh.new()
    verts = [bm.verts.new((r, 0.0, h)) for r, h in profile]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=(0, 0, 1), angle=2 * math.pi, steps=segs, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if axis == 'Y':
        bmesh.ops.transform(bm, matrix=RX, verts=bm.verts)
    elif axis == 'X':
        bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.pi / 2, 4, 'Y'), verts=bm.verts)
    if rot:
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    ax = {'Y': 1, 'X': 0, 'Z': 2}[axis]
    return obj(name, bm, material, uv=(lambda b: cyl_uv(b, ax)) if uv == 'cyl' else uv, smooth=smooth)


def profile(name, pts, thick, material, x=0.0, bev=0.002, uv='box', uv_scale=4.0):
    """Side silhouette pts [(y, z)] extruded across X (thickness), centred on x."""
    bm = bmesh.new()
    vs = [bm.verts.new((x - thick / 2, y, z)) for y, z in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [g for g in ext['geom'] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(thick, 0, 0), verts=nv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bevel(bm, bev, 2)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    return obj(name, bm, material, uv=uv, uv_scale=uv_scale)


def sweep(name, path, r, material, segs=8, closed=False):
    """Round tube along a polyline (trigger guards, handles, straps, wire)."""
    bm = bmesh.new()
    rings = []
    pts = [Vector(p) for p in path]
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        t = (b - a).normalized()
        n = t.orthogonal().normalized()
        bn = t.cross(n).normalized()
        ring = []
        for k in range(segs):
            ang = 2 * math.pi * k / segs
            ring.append(bm.verts.new(p + (n * math.cos(ang) + bn * math.sin(ang)) * r))
        rings.append(ring)
    # Keep rings from twisting: re-align each ring's start to the previous one.
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
    if closed:
        r0, r1 = rings[-1], rings[0]
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
    else:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj(name, bm, material, smooth=True)


def arc(c, radius, a0, a1, n=10, plane='YZ'):
    out = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        if plane == 'YZ':
            out.append((c[0], c[1] + math.cos(a) * radius, c[2] + math.sin(a) * radius))
        elif plane == 'XZ':
            out.append((c[0] + math.cos(a) * radius, c[1], c[2] + math.sin(a) * radius))
        else:
            out.append((c[0] + math.cos(a) * radius, c[1] + math.sin(a) * radius, c[2]))
    return out


def side_h(c, n, w, d):
    """Horizontal texture coordinate (-0.5..0.5) on a vertical face, increasing to the viewer's right."""
    if abs(n.y) >= abs(n.x):
        return -c.x / w if n.y > 0 else c.x / w
    return c.y / d if n.x > 0 else -c.y / d


def label_box(name, size, loc, material, top_region=(0, 0.5, 1, 1), side_region=(0, 0, 1, 0.5), bev=0.0015):
    """Box whose top shows the upper half of the texture and whose sides show the lower half."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bevel(bm, min(bev, min(size) * 0.4), 1)
    sx, sy, sz = size
    layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            c = l.vert.co
            if ax == 2:
                u0, v0, u1, v1 = top_region
                l[layer].uv = (u0 + (c.x / sx + 0.5) * (u1 - u0), v0 + (c.y / sy + 0.5) * (v1 - v0))
            else:
                u0, v0, u1, v1 = side_region
                h = side_h(c, n, sx, sy)
                l[layer].uv = (u0 + (h + 0.5) * (u1 - u0), v0 + (c.z / sz + 0.5) * (v1 - v0))
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return obj(name, bm, material, uv=None)


def cut(target, cutters):
    """Boolean difference (ports, slots), applied."""
    for c in cutters:
        m = target.modifiers.new('cut', 'BOOLEAN')
        m.operation = 'DIFFERENCE'
        m.object = c
        try:
            m.solver = 'EXACT'
        except Exception:
            pass
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
    target.modifiers.clear()
    target.data = me
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)
    return target


def rail_clamp(prefix, length, width=0.024, top=0.0, mat_=None, below=True):
    """Picatinny clamp: a block whose top (or bottom) face is the rail contact."""
    h = 0.011
    z = top - h / 2 if below else top + h / 2
    return [cube(prefix + '_clamp', (width, length, h), (0, 0, z), mat_ or M('alu'), bev=0.0012),
            cube(prefix + '_screw', (0.006, 0.008, 0.008), (width / 2 + 0.002, 0, z), M('steel'), bev=0.001)]


# ------------------------------------------------------------------ attachments: sights

def scope_tube(mag, length, r, obj_r, eye_r, axis_h, turret=True, base_len=None):
    parts = []
    z = axis_h
    obj_len = length * 0.22
    eye_len = length * 0.24
    tube_len = length - obj_len - eye_len
    y0 = -length / 2
    # eyepiece (rear) -> tube -> objective bell (front)
    prof = [(0.0, 0.0), (eye_r * 0.82, 0.0), (eye_r, 0.004), (eye_r, eye_len * 0.7), (r * 1.02, eye_len), (r, eye_len + 0.002),
            (r, eye_len + tube_len), (r * 1.05, eye_len + tube_len + 0.004), (obj_r, eye_len + tube_len + obj_len * 0.55),
            (obj_r, length - 0.003), (obj_r * 0.9, length), (0.0, length)]
    parts.append(lathe('tube', prof, M('blued'), loc=(0, y0, z)))
    parts.append(cyl('lens_f', obj_r * 0.86, 0.002, (0, length / 2 + 0.0005, z), M('glass'), segs=32))
    parts.append(cyl('lens_r', eye_r * 0.7, 0.002, (0, -length / 2 - 0.0005, z), M('glass'), segs=32))
    if turret:
        ty = y0 + eye_len + tube_len * 0.5
        parts.append(cube('saddle', (r * 2.3, tube_len * 0.28, r * 1.6), (0, ty, z), M('blued'), bev=0.003))
        parts.append(cyl('turret_t', r * 0.72, r * 1.1, (0, ty, z + r * 1.25), M('blued'), axis='Z', segs=20, bev=0.0008))
        parts.append(cyl('turret_s', r * 0.72, r * 1.1, (r * 1.25, ty, z), M('blued'), axis='X', segs=20, bev=0.0008))
    # rings and base
    base_len = base_len or tube_len * 0.95
    for k, fy in enumerate([y0 + eye_len + tube_len * 0.12, y0 + eye_len + tube_len * 0.88]):
        parts.append(lathe('ring%d' % k, [(0, -0.007), (r * 1.22, -0.007), (r * 1.22, 0.007), (0, 0.007)], M('parker'), loc=(0, fy, z), segs=24))
        parts.append(cube('riser%d' % k, (r * 1.4, 0.014, z - r), (0, fy, (z - r) / 2 + 0.006), M('parker'), bev=0.001))
    parts.append(cube('base', (0.022, base_len, 0.008), (0, y0 + eye_len + tube_len * 0.5, 0.004), M('parker'), bev=0.001))
    return parts


def m_scope_2x():
    # Compact 2x tube with an integrated cantilever mount.
    L, r = 0.115, 0.0135
    z = 0.034
    p = [(0, 0), (0.017, 0), (0.0175, 0.02), (r, 0.03), (r, 0.085), (0.019, 0.095), (0.019, L), (0, L)]
    parts = [lathe('tube', p, M('blued'), loc=(0, -L / 2, z))]
    parts.append(cyl('lens_f', 0.0165, 0.002, (0, L / 2 + 0.0005, z), M('glass')))
    parts.append(cyl('lens_r', 0.0145, 0.002, (0, -L / 2 - 0.0005, z), M('glass')))
    parts.append(profile('mount', [(-0.03, 0.0), (0.03, 0.0), (0.028, 0.012), (0.02, z - r + 0.002), (-0.02, z - r + 0.002), (-0.028, 0.012)], 0.024, M('parker')))
    parts.append(cyl('knob', 0.007, 0.009, (0.0175, 0.005, z), M('blued'), axis='X', segs=16))
    INFO['scope_2x'] = {'axis': z}
    return parts


def m_scope_3x():
    # Prism scope: squat body, short objective, rubber eye cup.
    z = 0.038
    parts = [profile('body', [(-0.045, 0.006), (0.045, 0.006), (0.05, 0.03), (0.042, 0.06), (-0.04, 0.06), (-0.05, 0.03)], 0.042, M('polymer'), bev=0.004)]
    parts.append(lathe('obj', [(0, 0), (0.0175, 0), (0.0185, 0.025), (0.0185, 0.03), (0, 0.03)], M('blued'), loc=(0, 0.045, z)))
    parts.append(lathe('eye', [(0, 0), (0.017, 0), (0.019, 0.016), (0.0155, 0.022), (0, 0.022)], M('rubber'), loc=(0, -0.071, z)))
    parts.append(cyl('lens_f', 0.016, 0.002, (0, 0.0755, z), M('glass')))
    parts.append(cyl('lens_r', 0.0135, 0.002, (0, -0.072, z), M('glass')))
    parts.append(cube('base', (0.024, 0.07, 0.008), (0, 0, 0.004), M('parker')))
    parts.append(cyl('knob', 0.009, 0.01, (0, 0.0, 0.064), M('blued'), axis='Z', segs=16))
    parts.append(cyl('knob2', 0.009, 0.01, (0.026, 0.0, z), M('blued'), axis='X', segs=16))
    INFO['scope_3x'] = {'axis': z}
    return parts


def m_scope_6x():
    axis = 0.05
    parts = scope_tube(6, 0.31, 0.015, 0.024, 0.02, axis)
    INFO['scope_6x'] = {'axis': axis}
    return parts


def m_scope_8x():
    axis = 0.056
    parts = scope_tube(8, 0.36, 0.015, 0.028, 0.0205, axis)
    # sunshade and side focus wheel
    parts.append(lathe('shade', [(0.0275, 0), (0.029, 0), (0.029, 0.05), (0.0275, 0.05)], M('blued'), loc=(0, 0.18, axis)))
    parts.append(cyl('wheel', 0.02, 0.006, (-0.022, -0.0, axis), M('blued'), axis='X', segs=24))
    INFO['scope_8x'] = {'axis': axis}
    return parts


def m_sight_reddot():
    # Tube red dot (Aimpoint style) on a low mount: see-through lenses.
    z = 0.03
    L = 0.075
    p = [(0.0145, 0), (0.0175, 0), (0.0175, L), (0.0145, L), (0.0145, 0.0001)]
    parts = [lathe('tube', p, M('alu'), loc=(0, -L / 2, z), uv='box')]
    parts.append(cyl('lens', 0.0145, 0.0015, (0, L / 2 - 0.004, z), M('lens_clear')))
    parts.append(cube('mount', (0.026, 0.05, z - 0.017 + 0.004), (0, 0, (z - 0.017 + 0.004) / 2), M('alu'), bev=0.0015))
    parts.append(cyl('knob', 0.008, 0.012, (0.022, -0.005, z), M('alu'), axis='X', segs=16))
    parts.append(cyl('knob2', 0.007, 0.01, (0, 0.0, z + 0.022), M('alu'), axis='Z', segs=16))
    INFO['sight_reddot'] = {'axis': z}
    return parts


def m_sight_holo():
    # Holographic sight: box battery housing with an open window hood on top.
    z = 0.034
    parts = [cube('housing', (0.04, 0.09, 0.02), (0, 0, 0.012), M('polymer'), bev=0.003)]
    for sx in (-1, 1):
        parts.append(cube('hood_side%d' % sx, (0.005, 0.07, 0.032), (sx * 0.0195, 0.004, 0.036), M('polymer'), bev=0.0015))
    parts.append(cube('hood_top', (0.044, 0.07, 0.005), (0, 0.004, 0.0535), M('polymer'), bev=0.0015))
    parts.append(cube('window_f', (0.034, 0.002, 0.03), (0, 0.035, z), M('lens_clear')))
    parts.append(cube('buttons', (0.03, 0.012, 0.006), (0, -0.04, 0.024), M('rubber'), bev=0.002))
    INFO['sight_holo'] = {'axis': z}
    return parts


# ------------------------------------------------------------------ attachments: muzzle, grips, lasers, mags, stocks

def m_suppressor(r, L, collar):
    p = [(0.0, 0.0), (collar * 0.7, 0.0), (collar, 0.003), (collar, 0.02), (r * 0.9, 0.024), (r, 0.03), (r, L - 0.006),
         (r * 0.94, L), (0.004, L), (0.004, L - 0.004), (0.0, L - 0.004)]
    parts = [lathe('can', p, M('blued'))]
    parts.append(cyl('bore', 0.0045, 0.002, (0, L + 0.0002, 0), M('dark'), segs=12))
    # wrench flats as two shallow rings
    parts.append(lathe('band', [(r * 1.01, 0.04), (r * 1.015, 0.04), (r * 1.015, 0.046), (r * 1.01, 0.046)], M('parker')))
    return parts


def m_compensator():
    L, r = 0.06, 0.011
    body = lathe('body', [(0, 0), (0.008, 0), (0.008, 0.008), (r, 0.01), (r, L - 0.003), (r * 0.9, L), (0.0045, L), (0, L - 0.002)], M('parker'))
    # three ports on top and a brake slot through each side
    cutters = []
    for k, y in enumerate([0.022, 0.034, 0.046]):
        cutters.append(cube('port%d' % k, (0.009, 0.0045, 0.01), (0, y, r), M('dark'), bev=0.0))
        cutters.append(cube('side%d' % k, (0.03, 0.0045, 0.008), (0, y, 0), M('dark'), bev=0.0))
    cut(body, cutters)
    return [body, cyl('bore', 0.0045, 0.002, (0, L + 0.0002, 0), M('dark'), segs=12)]


def m_flash_hider():
    L, r = 0.055, 0.0105
    parts = [lathe('collar', [(0, 0), (0.009, 0), (r, 0.004), (r, 0.018), (0.0, 0.018)], M('parker'))]
    for k in range(5):
        a = 2 * math.pi * k / 5 + math.pi / 2
        parts.append(cube('prong%d' % k, (0.005, L - 0.018, 0.0035), (math.cos(a) * (r - 0.002), 0.018 + (L - 0.018) / 2, math.sin(a) * (r - 0.002)),
                          M('parker'), bev=0.0008, rot=Matrix.Rotation(a + math.pi / 2, 4, 'Y')))
    return parts


def m_choke():
    L, r = 0.045, 0.0125
    p = [(0.0, 0.0), (0.011, 0.0), (0.011, 0.006)]
    for k in range(6):
        y = 0.008 + k * 0.005
        p += [(r, y), (r, y + 0.0028), (r * 0.94, y + 0.0035)]
    p += [(r * 0.94, L - 0.004), (r * 0.9, L), (0.009, L), (0.0, L - 0.002)]
    parts = [lathe('choke', p, M('steel'), segs=32)]
    parts.append(cyl('bore', 0.0085, 0.002, (0, L + 0.0002, 0), M('dark'), segs=16))
    return parts


def m_grip_vertical():
    parts = rail_clamp('g', 0.045)
    ridges = [(0.0, -0.011), (0.0125, -0.011)]
    for k in range(4):
        z = -0.02 - k * 0.019
        ridges += [(0.0135, z), (0.0118, z - 0.009)]
    ridges += [(0.0135, -0.1), (0.012, -0.104), (0.0, -0.104)]
    parts.append(lathe('grip', [(r, z) for r, z in ridges], M('polymer'), axis='Z', uv='box'))
    return parts


def m_grip_angled():
    parts = rail_clamp('g', 0.07)
    parts.append(profile('wedge', [(0.035, -0.011), (-0.035, -0.011), (-0.03, -0.022), (0.005, -0.05), (0.025, -0.05), (0.037, -0.03)], 0.022, M('polymer'), bev=0.003))
    return parts


def m_grip_half():
    parts = rail_clamp('g', 0.05)
    parts.append(profile('stub', [(0.026, -0.011), (-0.026, -0.011), (-0.02, -0.042), (0.006, -0.047), (0.022, -0.03)], 0.024, M('polymer'), bev=0.004))
    return parts


def m_laser():
    parts = rail_clamp('l', 0.04)
    parts.append(cube('housing', (0.028, 0.068, 0.026), (0, 0.006, -0.024), M('polymer'), bev=0.004))
    parts.append(cyl('lens', 0.0062, 0.003, (0.006, 0.0405, -0.024), M('lens_red'), segs=16))
    parts.append(cyl('lens2', 0.0045, 0.003, (-0.007, 0.0405, -0.024), M('glass'), segs=16))
    parts.append(cube('switch', (0.012, 0.012, 0.006), (0, -0.03, -0.012), M('rubber'), bev=0.002))
    return parts


def m_weapon_light():
    # Rail-mounted light: clamp on top, body along the barrel, bezel and lens at the front, paddle switch at the rear.
    z = -0.026
    parts = rail_clamp('wl', 0.03)
    parts.append(cube('neck', (0.02, 0.03, 0.012), (0, -0.005, -0.014), M('alu'), bev=0.002))
    parts.append(lathe('body', [(0.0, 0.0), (0.012, 0.0), (0.014, 0.006), (0.014, 0.058), (0.0175, 0.066), (0.0175, 0.085), (0.0, 0.085)], M('alu'), loc=(0, -0.04, z), uv='box'))
    parts.append(cyl('lens', 0.0145, 0.002, (0, 0.0455, z), M('lens_light'), segs=24))
    for sx in (-1, 1):
        parts.append(cube('paddle%d' % sx, (0.004, 0.018, 0.016), (sx * 0.015, -0.035, z + 0.002), M('polymer'), bev=0.001))
    return parts


def mag_body(name, h, w, d, curve=0.0, ribs=True, material=None, base=True):
    """Magazine: top at z = 0, body going down (and forward with curve)."""
    n = 6
    pts_f, pts_b = [], []
    for i in range(n + 1):
        t = i / n
        z = -t * h
        y = curve * t * t
        pts_f.append((d / 2 + y, z))
        pts_b.append((-d / 2 + y, z))
    pts = pts_b + list(reversed(pts_f))
    parts = [profile(name, pts, w, material or M('polymer'), bev=0.0015)]
    if base:
        yb = curve
        parts.append(cube(name + '_base', (w + 0.004, d + 0.008, 0.008), (0, yb, -h - 0.003), M('polymer'), bev=0.002))
    if ribs:
        for k in range(3):
            t = 0.25 + k * 0.2
            parts.append(cube(name + '_rib%d' % k, (w + 0.0015, d * 0.75, 0.003), (0, curve * t * t, -t * h), material or M('polymer'), bev=0.0006))
    return parts


def pull_tab(y, z, w):
    return [sweep('tab', [(0, y - 0.01, z), (0, y - 0.018, z - 0.02), (0, y + 0.0, z - 0.032), (0, y + 0.018, z - 0.02), (0, y + 0.01, z)], 0.003, M('nylon_black'))]


def m_mag_ext_light():
    return mag_body('mag', 0.24, 0.024, 0.033, 0.0, material=M('parker'))


def m_mag_quick_light():
    parts = mag_body('mag', 0.13, 0.024, 0.033, 0.0, material=M('parker'))
    return parts + pull_tab(0.0, -0.137, 0.024)


def m_mag_extquick_light():
    parts = mag_body('mag', 0.24, 0.024, 0.033, 0.0, material=M('parker'))
    return parts + pull_tab(0.0, -0.247, 0.024)


def m_mag_ext_rifle():
    return mag_body('mag', 0.24, 0.024, 0.062, 0.07, material=M('polymer'))


def m_mag_quick_rifle():
    # Two magazines clamped side by side ("jungle style").
    a = mag_body('mag_a', 0.18, 0.024, 0.062, 0.045, material=M('polymer'))
    b = mag_body('mag_b', 0.18, 0.024, 0.062, 0.045, material=M('polymer'))
    for o in b:
        o.location.x += 0.03
        o.location.z -= 0.0
    clamp = [cube('clamp%d' % k, (0.06, 0.05, 0.012), (0.015, 0.012 + 0.02 * k, -0.06 - 0.06 * k), M('alu'), bev=0.002) for k in range(2)]
    return a + b + clamp


def m_mag_extquick_rifle():
    parts = mag_body('mag', 0.24, 0.024, 0.062, 0.07, material=M('tan'))
    return parts + pull_tab(0.07, -0.25, 0.024)


def m_mag_ext_sniper():
    return mag_body('mag', 0.1, 0.03, 0.085, 0.0, ribs=False, material=M('parker'))


def m_stock_tactical():
    # Collapsible stock: hinge block at the front (y = 0), tube and buffer pad going back.
    parts = [cube('hinge', (0.03, 0.03, 0.04), (0, -0.015, 0), M('alu'), bev=0.003)]
    parts.append(cyl('tube', 0.0125, 0.2, (0, -0.12, 0.002), M('alu'), segs=20))
    parts.append(profile('butt', [(-0.17, 0.035), (-0.23, 0.04), (-0.245, 0.03), (-0.245, -0.09), (-0.235, -0.1), (-0.205, -0.1), (-0.17, -0.03)], 0.036, M('polymer'), bev=0.004))
    parts.append(cube('pad', (0.038, 0.012, 0.13), (0, -0.25, -0.025), M('rubber'), bev=0.004))
    parts.append(cube('lever', (0.008, 0.03, 0.01), (0, -0.2, -0.055), M('polymer'), bev=0.002))
    return parts


def m_cheek_pad():
    parts = [cube('pad', (0.046, 0.13, 0.026), (0, 0, 0.015), M('foam'), bev=0.008, segs=3)]
    for k, y in enumerate([-0.04, 0.04]):
        parts.append(cube('strap%d' % k, (0.05, 0.02, 0.003), (0, y, 0.029), M('nylon_black'), bev=0.001))
        for sx in (-1, 1):
            parts.append(cube('strap%d_%d' % (k, sx), (0.003, 0.02, 0.03), (sx * 0.025, y, 0.013), M('nylon_black'), bev=0.001))
    return parts


def m_bullet_loops():
    # Elastic sleeve mounted on the right side of a stock (inner face at x = 0), holding five shells.
    parts = [cube('sleeve', (0.012, 0.12, 0.07), (0.006, 0, 0), M('nylon_black'), bev=0.004)]
    for k in range(5):
        y = -0.044 + k * 0.022
        parts.append(cyl('shell%d' % k, 0.0105, 0.07, (0.017, y, 0.0), M('shell_red'), axis='Z', segs=14))
        parts.append(cyl('base%d' % k, 0.011, 0.012, (0.017, y, -0.036), M('brass'), axis='Z', segs=14))
    return parts


# ------------------------------------------------------------------ items

def m_battery():
    L, r = 0.0615, 0.0168
    p = [(0.0, 0.0), (r * 0.9, 0.0), (r, 0.0015), (r, L - 0.0015), (r * 0.92, L), (0.0045, L), (0.0045, L + 0.0015), (0.0, L + 0.0015)]
    parts = [lathe('cell', p, M('battery'), axis='Z')]
    return parts


def m_bandage():
    parts = [lathe('roll', [(0.0, 0.0), (0.03, 0.0), (0.031, 0.002), (0.031, 0.098), (0.03, 0.1), (0.0, 0.1)], M('bandage'), axis='X', uv='box')]
    parts.append(cube('tail', (0.096, 0.05, 0.002), (0.05, 0.03, -0.0295), M('bandage'), bev=0.0005))
    parts.append(cube('clip', (0.012, 0.016, 0.003), (0.07, 0.05, -0.028), M('steel'), bev=0.0005))
    return parts


def m_painkillers():
    p = [(0.0, 0.0), (0.017, 0.0), (0.018, 0.002), (0.018, 0.058), (0.015, 0.062), (0.0, 0.062)]
    parts = [lathe('bottle', p, M('pills'), axis='Z')]
    cap = [(0.0, 0.058), (0.0185, 0.058)]
    for k in range(8):
        z = 0.06 + k * 0.002
        cap += [(0.0195 if k % 2 == 0 else 0.0188, z)]
    cap += [(0.0185, 0.077), (0.0, 0.077)]
    parts.append(lathe('cap', cap, M('white'), axis='Z', uv='box'))
    return parts


def m_splint():
    # A rolled foam-and-aluminium splint: orange outside, blue inside.
    parts = [lathe('roll_o', [(0.03, 0.0), (0.04, 0.0), (0.041, 0.003), (0.041, 0.107), (0.04, 0.11), (0.03, 0.11)], M('splint_o'), axis='X', uv='box')]
    parts.append(lathe('roll_i', [(0.025, 0.002), (0.03, 0.002), (0.03, 0.108), (0.025, 0.108)], M('splint_b'), axis='X', uv='box'))
    parts.append(cube('flap', (0.105, 0.04, 0.004), (0.0, 0.03, 0.035), M('splint_o'), bev=0.001, rot=Matrix.Rotation(0.5, 4, 'X')))
    return parts


def m_backpack(size, material, big):
    w, d, h = size
    parts = [cube('body', (w, d, h), (0, 0, h / 2), material, bev=0.05, segs=4, uv_scale=3.0)]
    parts.append(cube('pocket', (w * 0.78, d * 0.35, h * 0.38), (0, d * 0.5, h * 0.3), material, bev=0.035, segs=3, uv_scale=3.0))
    parts.append(cube('zip', (w * 0.82, 0.006, 0.006), (0, d * 0.5 + d * 0.17, h * 0.49), M('rubber'), bev=0.002))
    parts.append(sweep('handle', [(-0.03, -d * 0.2, h - 0.01), (-0.025, -d * 0.2, h + 0.025), (0.025, -d * 0.2, h + 0.025), (0.03, -d * 0.2, h - 0.01)], 0.008, M('nylon_black')))
    for sx in (-1, 1):
        x = sx * w * 0.24
        strap = [(x, -d * 0.5 - 0.005, h * 0.88), (x, -d * 0.5 - 0.035, h * 0.7), (x * 1.1, -d * 0.5 - 0.04, h * 0.4), (x * 1.3, -d * 0.5 - 0.02, h * 0.12)]
        parts.append(sweep('strap%d' % sx, strap, 0.011, M('nylon_black'), segs=6))
    if big:
        parts.append(cube('lid', (w * 0.96, d * 0.92, 0.09), (0, 0, h + 0.02), material, bev=0.035, segs=3))
        parts.append(cyl('mat', 0.06, w * 1.1, (0, 0.0, h + 0.125), M('foam_grey'), axis='X', segs=24))
        for sx in (-1, 1):
            parts.append(cube('bottle_pocket%d' % sx, (0.05, d * 0.6, h * 0.3), (sx * (w / 2 + 0.02), 0, h * 0.2), material, bev=0.02, segs=2))
            parts.append(cube('compress%d' % sx, (0.012, d * 0.9, 0.02), (sx * (w / 2 + 0.002), 0, h * 0.62), M('nylon_black'), bev=0.003))
    return parts


def m_ammo(item_id, size, shells=False):
    sx, sy, sz = size
    mtl = mat('label_' + item_id, tex=item_id, rough=0.75)
    parts = [label_box('box', size, (0, 0, sz / 2), mtl)]
    return parts


def m_frag_grenade():
    """M67-style frag: a 64 mm ball body, fuze head, spoon and pull ring. Bore axis irrelevant; stands upright."""
    body = mat('grenade_body', tex='grenade_body', rough=0.7)
    metal = M('steel')
    parts = [lathe('body', [(0.0, 0.0), (0.02, 0.002), (0.03, 0.012), (0.032, 0.03), (0.03, 0.048), (0.022, 0.06), (0.012, 0.064), (0.0, 0.064)], body, axis='Z')]
    parts.append(cyl('fuze', 0.009, 0.022, (0, 0, 0.074), metal, axis='Z', segs=16))
    parts.append(cube('spoon', (0.012, 0.004, 0.07), (0.0, 0.026, 0.05), metal, rot=Matrix.Rotation(math.radians(-14), 4, 'X')))
    ring = sweep('ring', [(0.018 + 0.011 * math.cos(a), 0.0, 0.08 + 0.011 * math.sin(a)) for a in [i * math.tau / 12 for i in range(12)]], 0.0015, metal, closed=True)
    parts.append(ring)
    return parts


# ------------------------------------------------------------------ guns

def m_shotgun_double():
    parts = []
    # Barrels: bore axis at z = 0, muzzle at y = +0.49.
    for k, sx in enumerate((-0.0122, 0.0122)):
        parts.append(cyl('barrel%d' % k, 0.0118, 0.6, (sx, 0.19, 0.0), M('blued'), segs=20))
        parts.append(cyl('muzzle%d' % k, 0.0088, 0.002, (sx, 0.4905, 0.0), M('dark'), segs=16))
    parts.append(cube('rib', (0.008, 0.6, 0.006), (0, 0.19, 0.0125), M('blued'), bev=0.001))
    parts.append(cube('rib_under', (0.01, 0.6, 0.008), (0, 0.19, -0.011), M('blued'), bev=0.001))
    parts.append(cyl('bead', 0.0022, 0.004, (0, 0.48, 0.0175), M('brass'), axis='Z', segs=10))
    # Fore-end
    parts.append(profile('forend', [(0.05, -0.006), (0.27, -0.006), (0.28, -0.016), (0.26, -0.034), (0.07, -0.038), (0.045, -0.03)], 0.046, M('walnut')))
    # Action
    parts.append(profile('action', [(-0.115, 0.016), (-0.11, 0.019), (-0.02, 0.016), (-0.01, -0.012), (-0.02, -0.036), (-0.11, -0.036), (-0.122, -0.01)], 0.044, M('blued'), bev=0.003))
    parts.append(cube('lever', (0.01, 0.035, 0.005), (0.004, -0.122, 0.024), M('blued'), bev=0.001, rot=Matrix.Rotation(0.25, 4, 'Z')))
    parts.append(cube('safety', (0.008, 0.012, 0.004), (0, -0.14, 0.02), M('blued'), bev=0.001))
    parts.append(sweep('guard', [(0, -0.03, -0.036), (0, -0.04, -0.06), (0, -0.07, -0.068), (0, -0.1, -0.06), (0, -0.115, -0.04)], 0.0035, M('blued')))
    for k, y in enumerate([-0.055, -0.075]):
        parts.append(cube('trigger%d' % k, (0.005, 0.006, 0.022), (0, y, -0.047), M('blued'), bev=0.001, rot=Matrix.Rotation(-0.25, 4, 'X')))
    # Stock (semi-pistol grip)
    parts.append(profile('stock', [(-0.105, 0.017), (-0.2, 0.004), (-0.47, 0.003), (-0.48, -0.004), (-0.48, -0.128), (-0.47, -0.132),
                                   (-0.25, -0.07), (-0.2, -0.085), (-0.165, -0.08), (-0.13, -0.042), (-0.11, -0.036)], 0.04, M('walnut'), bev=0.004))
    parts.append(profile('pad', [(-0.48, 0.003), (-0.497, 0.003), (-0.497, -0.13), (-0.48, -0.13)], 0.042, M('rubber'), bev=0.002))
    return parts


def m_sumpak():
    parts = []
    # Barrel pipe slides inside the receiver pipe; firing pin (a nail) fixed in the rear block.
    parts.append(cyl('outer', 0.017, 0.36, (0, 0.08, 0.0), M('galv'), segs=18))
    parts.append(cyl('inner', 0.0135, 0.45, (0, 0.205, 0.0), M('galv'), segs=18))
    parts.append(cyl('bore', 0.0105, 0.002, (0, 0.431, 0.0), M('dark'), segs=14))
    parts.append(cyl('cap', 0.02, 0.03, (0, -0.115, 0.0), M('galv'), segs=18, bev=0.002))
    parts.append(cyl('nail', 0.0025, 0.03, (0, -0.135, 0.0), M('steel'), segs=8))
    # Front handle: a block clamped to the barrel pipe
    parts.append(profile('fhandle', [(0.3, -0.012), (0.38, -0.012), (0.38, -0.03), (0.36, -0.09), (0.33, -0.09), (0.31, -0.03)], 0.03, M('rawwood'), bev=0.003))
    parts.append(lathe('clamp', [(0.0145, 0.0), (0.0165, 0.0), (0.0165, 0.012), (0.0145, 0.012)], M('steel'), loc=(0, 0.33, 0), uv='box'))
    # Rear grip: a plank cut to a pistol grip, wired and taped to the pipe
    parts.append(profile('grip', [(-0.14, 0.022), (0.02, 0.0), (0.02, -0.03), (-0.08, -0.03), (-0.09, -0.13), (-0.13, -0.13), (-0.15, -0.03), (-0.155, 0.01)], 0.036, M('rawwood'), bev=0.003))
    for k, y in enumerate([-0.06, 0.0, 0.17]):
        parts.append(lathe('tape%d' % k, [(0.0, 0.0), (0.0185, 0.0), (0.0185, 0.03), (0.0, 0.03)], M('tape'), loc=(0, y, 0), uv='box'))
    parts.append(sweep('band', [(0, 0.33, -0.02), (0, 0.2, -0.026), (0, 0.05, -0.03), (0, -0.04, -0.034)], 0.003, M('rubber'), segs=6))
    return parts


def m_marksman_308():
    parts = []
    parts.append(cyl('barrel', 0.0095, 0.42, (0, 0.3, 0.012), M('blued'), segs=18))
    parts.append(lathe('flash', [(0.0, 0.0), (0.0115, 0.0), (0.012, 0.004), (0.012, 0.045), (0.0108, 0.05), (0.004, 0.05), (0.0, 0.048)], M('blued'), loc=(0, 0.5, 0.012), uv='box'))
    parts.append(cube('fsight', (0.004, 0.006, 0.024), (0, 0.535, 0.032), M('blued'), bev=0.0008))
    parts.append(cyl('gas', 0.0085, 0.11, (0, 0.135, -0.008), M('blued'), segs=14))
    parts.append(cube('gaslock', (0.014, 0.02, 0.03), (0, 0.19, 0.002), M('blued'), bev=0.002))
    # Stock
    parts.append(profile('stock', [(0.175, 0.002), (-0.13, 0.004), (-0.2, 0.0), (-0.31, 0.008), (-0.545, 0.0), (-0.548, -0.14),
                                   (-0.53, -0.146), (-0.3, -0.078), (-0.24, -0.092), (-0.2, -0.074), (-0.16, -0.046), (0.0, -0.034),
                                   (0.17, -0.026), (0.18, -0.012)], 0.052, M('walnut'), bev=0.004))
    parts.append(profile('handguard', [(0.06, 0.004), (0.165, 0.004), (0.165, 0.016), (0.155, 0.026), (0.07, 0.026), (0.06, 0.016)], 0.034, M('polymer'), bev=0.003))
    parts.append(profile('buttplate', [(-0.545, 0.002), (-0.558, 0.002), (-0.56, -0.142), (-0.548, -0.142)], 0.054, M('parker'), bev=0.001))
    # Receiver
    parts.append(profile('receiver', [(-0.13, 0.005), (0.06, 0.005), (0.06, 0.03), (0.0, 0.036), (-0.1, 0.036), (-0.13, 0.03)], 0.034, M('parker'), bev=0.002))
    parts.append(cube('oprod', (0.008, 0.14, 0.01), (0.019, 0.1, 0.014), M('parker'), bev=0.001))
    parts.append(cube('ophandle', (0.018, 0.016, 0.012), (0.026, 0.02, 0.016), M('parker'), bev=0.002))
    parts.append(cube('rsight', (0.022, 0.016, 0.022), (0, -0.11, 0.046), M('parker'), bev=0.002))
    parts.append(cyl('rsight_knob', 0.006, 0.008, (0.014, -0.11, 0.042), M('parker'), axis='X', segs=12))
    # Magazine and trigger group
    parts += mag_body('mag', 0.085, 0.03, 0.085, 0.012, ribs=False, material=M('parker'))
    for o in parts[-2:]:
        o.location += Vector((0, -0.01, -0.034))
    parts.append(sweep('guard', [(0, -0.07, -0.036), (0, -0.08, -0.06), (0, -0.11, -0.066), (0, -0.14, -0.058), (0, -0.145, -0.045)], 0.004, M('parker')))
    parts.append(cube('trigger', (0.005, 0.006, 0.024), (0, -0.1, -0.046), M('parker'), bev=0.001, rot=Matrix.Rotation(-0.25, 4, 'X')))
    for k, y in enumerate([0.12, -0.38]):
        parts.append(sweep('swivel%d' % k, arc((0, y, -0.04 if k == 0 else -0.115), 0.008, 0, math.pi * 2, 12, 'YZ'), 0.0018, M('steel'), closed=True))
    return parts


# ------------------------------------------------------------------ loot boxes (closed + open)

def hinge_open(lid_parts, hinge_y, hinge_z, angle, axis='X', hinge_x=0.0):
    """Rotates lid objects about a hinge line (along X at y/z, or along Y at x/z)."""
    if axis == 'X':
        piv = Vector((0, hinge_y, hinge_z))
        R = Matrix.Rotation(angle, 4, 'X')
    else:
        piv = Vector((hinge_x, 0, hinge_z))
        R = Matrix.Rotation(angle, 4, 'Y')
    T = Matrix.Translation(piv) @ R @ Matrix.Translation(-piv)
    for o in lid_parts:
        o.matrix_world = T @ o.matrix_world


def shell(name, w, d, h, t, material, bev=0.004):
    """Open-topped box made of five panels (so an open box shows its inside)."""
    return [cube(name + '_floor', (w, d, t), (0, 0, t / 2), material, bev=bev),
            cube(name + '_front', (w, t, h), (0, d / 2 - t / 2, h / 2), material, bev=bev),
            cube(name + '_back', (w, t, h), (0, -d / 2 + t / 2, h / 2), material, bev=bev),
            cube(name + '_left', (t, d - 2 * t, h), (-w / 2 + t / 2, 0, h / 2), material, bev=bev),
            cube(name + '_right', (t, d - 2 * t, h), (w / 2 - t / 2, 0, h / 2), material, bev=bev)]


def lb_balikbayan():
    w, d, h = 0.46, 0.46, 0.6
    body = shell('box', w, d, h, 0.006, M('balikbayan'), bev=0.002)
    for o in body:
        bm = bmesh.new(); bm.from_mesh(o.data)
        layer = bm.loops.layers.uv.verify()
        for f in bm.faces:
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for l in f.loops:
                c = o.matrix_world @ l.vert.co
                if ax == 2:
                    l[layer].uv = (c.x / w + 0.5, c.y / d + 0.5)
                else:
                    l[layer].uv = (side_h(c, n, w, d) + 0.5, c.z / h)
        bm.to_mesh(o.data); bm.free()
    flaps = []
    for k, (sy, fd) in enumerate(((1, d / 2), (-1, d / 2))):
        flaps.append(cube('flap_y%d' % k, (w - 0.004, fd, 0.005), (0, sy * fd / 2, h + 0.0035 + k * 0.004), M('cardboard'), bev=0.001))
    for k, sx in enumerate((1, -1)):
        flaps.append(cube('flap_x%d' % k, (w / 2, d - 0.01, 0.005), (sx * w / 4, 0, h - 0.0015), M('cardboard'), bev=0.001))
    tape = cube('tape', (0.06, d + 0.004, 0.0015), (0, 0, h + 0.009), M('tapebrown'), bev=0.0)
    tape2 = cube('tape2', (0.06, 0.0015, 0.12), (0, d / 2 + 0.003, h - 0.05), M('tapebrown'), bev=0.0)
    tape3 = cube('tape3', (0.06, 0.0015, 0.12), (0, -d / 2 - 0.003, h - 0.05), M('tapebrown'), bev=0.0)

    def opener():
        bpy.data.objects.remove(tape, do_unlink=True)
        hinge_open([flaps[0]], d / 2, h, -2.2)
        hinge_open([flaps[1]], -d / 2, h, 2.0)
        hinge_open([flaps[2]], 0, h, 1.9, axis='Y', hinge_x=w / 2)
        hinge_open([flaps[3]], 0, h, -2.3, axis='Y', hinge_x=-w / 2)
        tape2.location.z += 0.0
    return body + flaps + [tape, tape2, tape3], opener


def lb_storage_bin():
    w, d, h = 0.6, 0.4, 0.3
    body = shell('bin', w, d, h, 0.006, M('grey'), bev=0.003)
    rim = [cube('rim_f', (w + 0.02, 0.012, 0.012), (0, d / 2 + 0.004, h - 0.006), M('grey')), cube('rim_b', (w + 0.02, 0.012, 0.012), (0, -d / 2 - 0.004, h - 0.006), M('grey')),
           cube('rim_l', (0.012, d, 0.012), (-w / 2 - 0.004, 0, h - 0.006), M('grey')), cube('rim_r', (0.012, d, 0.012), (w / 2 + 0.004, 0, h - 0.006), M('grey'))]
    lid = [cube('lid', (w + 0.03, d + 0.03, 0.018), (0, 0, h + 0.009), M('blue'), bev=0.005),
           cube('lid_rib', (w * 0.7, d * 0.6, 0.008), (0, 0, h + 0.021), M('blue'), bev=0.003)]
    clips = [cube('clip%d' % k, (0.07, 0.01, 0.04), (sx * w * 0.25, d / 2 + 0.012, h - 0.01), M('blue'), bev=0.002) for k, sx in enumerate((-1, 1))]

    def opener():
        # Lid lifted off and leaned against the back.
        hinge_open(lid, -d / 2 - 0.015, h + 0.018, -1.75)
        for c in clips:
            c.rotation_euler.x = -0.6
    return body + rim + lid + clips, opener


def lb_ammo_can():
    w, d, h = 0.29, 0.155, 0.17
    body = shell('can', w, d, h, 0.003, M('ammocan'), bev=0.002)
    lid = [cube('lid', (w + 0.008, d + 0.008, 0.022), (0, 0, h + 0.008), M('ammocan'), bev=0.003),
           sweep('handle', [(-0.05, 0.0, h + 0.02), (-0.045, 0.0, h + 0.032), (0.045, 0.0, h + 0.032), (0.05, 0.0, h + 0.02)], 0.005, M('olive'))]
    latch = cube('latch', (0.04, 0.012, 0.06), (w / 2 + 0.006, 0, h - 0.015), M('olive'), bev=0.002)

    def opener():
        hinge_open(lid, 0, h + 0.01, 1.85, axis='Y', hinge_x=-w / 2 - 0.004)
        latch.rotation_euler.y = 0.9
        latch.location.x += 0.015
    return body + lid + [latch], opener


def lb_footlocker():
    w, d, h = 0.8, 0.42, 0.34
    body = shell('trunk', w, d, h, 0.012, M('greenwood'), bev=0.003)
    trim = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            trim.append(cube('corner%d%d' % (sx, sy), (0.05, 0.05, 0.05), (sx * (w / 2 - 0.02), sy * (d / 2 - 0.02), 0.025), M('steel'), bev=0.004))
        trim.append(sweep('handle%d' % sx, [(sx * (w / 2 + 0.004), -0.06, h * 0.6), (sx * (w / 2 + 0.02), -0.05, h * 0.55), (sx * (w / 2 + 0.02), 0.05, h * 0.55), (sx * (w / 2 + 0.004), 0.06, h * 0.6)], 0.006, M('steel')))
    lid = [cube('lid', (w + 0.012, d + 0.012, 0.06), (0, 0, h + 0.03), M('greenwood'), bev=0.006)]
    for sx in (-1, 1):
        lid.append(cube('lidcorner%d' % sx, (0.05, d + 0.016, 0.03), (sx * (w / 2 - 0.02), 0, h + 0.045), M('steel'), bev=0.003))
    hasp = cube('hasp', (0.05, 0.012, 0.07), (0, d / 2 + 0.008, h + 0.01), M('steel'), bev=0.002)
    lid.append(hasp)

    def opener():
        hinge_open(lid, -d / 2 - 0.006, h, -1.9)
    return body + trim + lid, opener


def lb_toolbox():
    w, d, h = 0.5, 0.22, 0.2
    body = shell('tb', w, d, h, 0.004, M('red_steel'), bev=0.002)
    lid = [cube('lid', (w + 0.006, d + 0.006, 0.05), (0, 0, h + 0.025), M('red_steel'), bev=0.006),
           sweep('handle', [(-0.1, 0, h + 0.05), (-0.09, 0, h + 0.075), (0.09, 0, h + 0.075), (0.1, 0, h + 0.05)], 0.007, M('polymer'))]
    latches = [cube('latch%d' % sx, (0.03, 0.01, 0.04), (sx * w * 0.35, d / 2 + 0.006, h), M('steel'), bev=0.002) for sx in (-1, 1)]
    tray = cube('tray', (w - 0.02, d - 0.02, 0.04), (0, 0, h - 0.03), M('red_steel'), bev=0.002)

    def opener():
        hinge_open(lid, -d / 2 - 0.003, h, -1.95)
    return body + lid + latches + [tray], opener


def lb_medcase():
    w, d, h = 0.42, 0.3, 0.1
    body = shell('mc', w, d, h, 0.005, M('white'), bev=0.003)
    lid = [label_box('lid', (w + 0.008, d + 0.008, 0.045), (0, 0, h + 0.0225), M('medlid'), top_region=(0, 0, 1, 1), side_region=(0.0, 0.0, 0.1, 0.1))]
    lid.append(sweep('handle', [(-0.06, d / 2 + 0.004, h + 0.01), (-0.05, d / 2 + 0.03, h + 0.0), (0.05, d / 2 + 0.03, h + 0.0), (0.06, d / 2 + 0.004, h + 0.01)], 0.007, M('white')))
    latches = [cube('latch%d' % sx, (0.035, 0.012, 0.03), (sx * w * 0.32, d / 2 + 0.006, h + 0.005), M('grey'), bev=0.002) for sx in (-1, 1)]

    def opener():
        hinge_open(lid, -d / 2 - 0.004, h, -1.95)
    return body + lid + latches, opener


def lb_riflecase():
    w, d, h = 1.12, 0.36, 0.06
    body = shell('rc', w, d, h, 0.006, M('polymer'), bev=0.004)
    foam = [cube('foam', (w - 0.03, d - 0.03, 0.03), (0, 0, 0.02), M('foam'), bev=0.004)]
    lid = [cube('lid', (w + 0.01, d + 0.01, 0.07), (0, 0, h + 0.035), M('polymer'), bev=0.01)]
    for k in range(5):
        lid.append(cube('rib%d' % k, (0.02, d * 0.8, 0.008), (-0.4 + k * 0.2, 0, h + 0.072), M('polymer'), bev=0.003))
    latches = [cube('latch%d' % k, (0.045, 0.014, 0.05), (x, d / 2 + 0.008, h + 0.0), M('steel'), bev=0.003) for k, x in enumerate((-0.35, 0.0, 0.35))]
    handle = sweep('handle', [(-0.08, d / 2 + 0.006, h - 0.01), (-0.07, d / 2 + 0.04, h - 0.02), (0.07, d / 2 + 0.04, h - 0.02), (0.08, d / 2 + 0.006, h - 0.01)], 0.01, M('polymer'))

    def opener():
        hinge_open(lid, -d / 2 - 0.005, h, -1.9)
        for l in latches:
            l.rotation_euler.x = 0.9
    return body + foam + lid + latches + [handle], opener


def lb_cooler():
    w, d, h = 0.6, 0.38, 0.34
    body = shell('cooler', w, d, h, 0.03, M('cooler'), bev=0.012)
    for o in body:
        bm = bmesh.new(); bm.from_mesh(o.data)
        layer = bm.loops.layers.uv.verify()
        for f in bm.faces:
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for l in f.loops:
                c = o.matrix_world @ l.vert.co
                l[layer].uv = (side_h(c, n, w, d) + 0.5, c.z / h * 0.5)
        bm.to_mesh(o.data); bm.free()
    lid = [cube('lid', (w + 0.01, d + 0.01, 0.06), (0, 0, h + 0.03), M('white'), bev=0.015, segs=3)]
    for sx in (-1, 1):
        lid.append(sweep('handle%d' % sx, [(sx * (w / 2 + 0.004), -0.08, h - 0.03), (sx * (w / 2 + 0.04), -0.07, h - 0.06), (sx * (w / 2 + 0.04), 0.07, h - 0.06), (sx * (w / 2 + 0.004), 0.08, h - 0.03)], 0.01, M('white')))
    lid_only = lid[:1]

    def opener():
        hinge_open(lid_only, -d / 2 - 0.005, h, -1.85)
    return body + lid, opener


# ------------------------------------------------------------------ registry

ATTACH = {
    'scope_2x': m_scope_2x, 'scope_3x': m_scope_3x, 'scope_6x': m_scope_6x, 'scope_8x': m_scope_8x,
    'sight_reddot': m_sight_reddot, 'sight_holo': m_sight_holo,
    'suppressor_light': lambda: m_suppressor(0.0165, 0.15, 0.0095), 'suppressor_rifle': lambda: m_suppressor(0.0205, 0.18, 0.0135),
    'compensator': m_compensator, 'flash_hider': m_flash_hider, 'choke': m_choke,
    'grip_vertical': m_grip_vertical, 'grip_angled': m_grip_angled, 'grip_half': m_grip_half, 'laser_sight': m_laser, 'weapon_light': m_weapon_light,
    'mag_ext_light': m_mag_ext_light, 'mag_quick_light': m_mag_quick_light, 'mag_extquick_light': m_mag_extquick_light,
    'mag_ext_rifle': m_mag_ext_rifle, 'mag_quick_rifle': m_mag_quick_rifle, 'mag_extquick_rifle': m_mag_extquick_rifle,
    'mag_ext_sniper': m_mag_ext_sniper, 'stock_tactical': m_stock_tactical, 'cheek_pad': m_cheek_pad, 'bullet_loops': m_bullet_loops,
}
ITEMS = {
    'battery': m_battery, 'bandage': m_bandage, 'painkillers': m_painkillers, 'splint': m_splint,
    'backpack_small': lambda: m_backpack((0.3, 0.17, 0.42), M('navy'), False),
    'backpack_large': lambda: m_backpack((0.34, 0.24, 0.6), M('nylon_olive'), True),
    'ammo_9x19': lambda: m_ammo('ammo_9x19', (0.115, 0.075, 0.04)),
    'ammo_45acp': lambda: m_ammo('ammo_45acp', (0.125, 0.08, 0.045)),
    'ammo_357': lambda: m_ammo('ammo_357', (0.1, 0.07, 0.042)),
    'ammo_12buck': lambda: m_ammo('ammo_12buck', (0.125, 0.065, 0.072), True),
    'ammo_12slug': lambda: m_ammo('ammo_12slug', (0.11, 0.065, 0.072), True),
    'ammo_556': lambda: m_ammo('ammo_556', (0.12, 0.085, 0.036)),
    'ammo_762x39': lambda: m_ammo('ammo_762x39', (0.13, 0.07, 0.045)),
    'ammo_308': lambda: m_ammo('ammo_308', (0.11, 0.075, 0.042)),
    'ammo_50ae': lambda: m_ammo('ammo_50ae', (0.1, 0.07, 0.045)),
    'frag_grenade': lambda: m_frag_grenade(),
}
GUNS = {'shotgun_double': m_shotgun_double, 'sumpak': m_sumpak, 'marksman_308': m_marksman_308}
BOXES = {
    'lootbox_balikbayan': lb_balikbayan, 'lootbox_bin': lb_storage_bin, 'lootbox_ammocan': lb_ammo_can,
    'lootbox_footlocker': lb_footlocker, 'lootbox_toolbox': lb_toolbox, 'lootbox_medcase': lb_medcase,
    'lootbox_riflecase': lb_riflecase, 'lootbox_cooler': lb_cooler,
}


# ------------------------------------------------------------------ export and preview

def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in bpy.context.scene.objects:
        if o.type != 'MESH':
            continue
        for v in o.data.vertices:
            c = o.matrix_world @ v.co
            lo = Vector((min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)))
            hi = Vector((max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z)))
    return lo, hi


def tri_count():
    n = 0
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            n += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return n


def export(path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
                              export_image_format='AUTO')


def preview(path, view='side'):
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'TEXTURE'
    scn.render.resolution_x = 640
    scn.render.resolution_y = 480
    scn.render.film_transparent = False
    if scn.world is None:
        scn.world = bpy.data.worlds.new('w')
    lo, hi = bounds()
    c = (lo + hi) / 2
    size = max((hi - lo).length, 0.05)
    cam_data = bpy.data.cameras.new('cam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = size * 1.15
    cam = bpy.data.objects.new('cam', cam_data)
    scn.collection.objects.link(cam)
    # Three-quarter view from the front-left, slightly above (front is +Y).
    d = Vector((-1.0, 0.85, 0.6)).normalized() if view == '34' else Vector((-1.0, 0.0, 0.15)).normalized()
    cam.location = c + d * size * 3
    cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scn.camera = cam
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)


def build(item_id, fn, kind):
    reset()
    res = fn()
    opener = None
    if isinstance(res, tuple):
        res, opener = res
    lo, hi = bounds()
    tris = tri_count()
    rec = INFO.setdefault(item_id, {})
    rec.update({'kind': kind, 'size': [round(hi.x - lo.x, 4), round(hi.y - lo.y, 4), round(hi.z - lo.z, 4)],
                'min': [round(lo.x, 4), round(lo.y, 4), round(lo.z, 4)], 'tris': tris})
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    export(os.path.join(OUT, item_id + '.glb'))
    preview(os.path.join(PREV, item_id + '.png'), 'side' if kind == 'gun' else '34')
    if opener:
        opener()
        export(os.path.join(OUT, item_id + '_open.glb'))
        preview(os.path.join(PREV, item_id + '_open.png'), '34')
    print('[loot] %-22s %-10s %6d tris  size %s' % (item_id, kind, tris, rec['size']))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    groups = [(ATTACH, 'attachment'), (ITEMS, 'item'), (GUNS, 'gun'), (BOXES, 'lootbox')]
    for table, kind in groups:
        for item_id, fn in table.items():
            if argv and item_id not in argv:
                continue
            try:
                build(item_id, fn, kind)
            except Exception as e:
                import traceback
                traceback.print_exc()
                print('[loot] FAILED %s: %s' % (item_id, e))
    if not argv:
        json.dump(INFO, open(os.path.join(PREV, 'models.json'), 'w'), indent=1)
        src = {
            'title': 'Procedural loot models (attachments, items, ammunition boxes, loot boxes, three guns)',
            'source': 'Made for this project by tools/blender/make_loot_models.py and tools/make_loot_textures.py',
            'authors': ['Aetherion Project (generated)'], 'license': 'Project-owned', 'attribution_required': False,
            'url': '../tools/blender/make_loot_models.py',
            'kind': 'model', 'modifications': 'none (generated); printed labels use the Barlow and Share Tech Mono fonts (SIL OFL 1.1, shipped in game/assets/fonts)',
            'files': {k + '.glb': '' for t, _ in groups for k in t},
        }
        json.dump(src, open(os.path.join(OUT, 'source.json'), 'w'), indent=2)


main()
