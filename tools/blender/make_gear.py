"""Player outfits: every wearable piece, skinned to the character rig, in one glTF (no downloads).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/make_gear.py
    (then bash tools/import.sh; check renders go to work/gear/)

Input: game/assets/models/sleep/characters/stranger.glb (the hooded body and its 24-bone rig).
Output: game/assets/models/gear/gear.glb - the rig plus one mesh per piece:
  body_head      the original skin (head, neck, hands) with its own textured material
  skin_*         bare skin under clothes, per region (torso, upperarm, forearm, thigh, shin, feet)
  <slot>_<item>  garments and gear for the slots listed in cosmetics.json
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, kdtree
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.normpath(os.path.join(ROOT, 'game', 'assets', 'models', 'sleep', 'characters', 'stranger.glb'))
OUT_DIR = os.path.normpath(os.path.join(ROOT, 'game', 'assets', 'models', 'gear'))
CHECK_DIR = os.path.normpath(os.path.join(ROOT, 'work', 'gear'))

# texture array layers (tools/make_gear_textures.py)
SKIN, COTTON, DENIM, LEATHER, NYLON, CANVAS, RUBBER, PLASTIC, CAMO, STRIPES, KNIT, MESH, SACK, PLAID, QUILT, METAL = range(16)

ARM_BONES = ['upper_arm.L', 'forearm.L', 'hand.L', 'upper_arm.R', 'forearm.R', 'hand.R']
LEG_BONES = ['thigh.L', 'shin.L', 'foot.L', 'toe.L', 'thigh.R', 'shin.R', 'foot.R', 'toe.R']
TORSO_BONES = ['hips', 'spine', 'chest', 'neck', 'shoulder.L', 'shoulder.R', 'root']

# True anatomical centerline of the arms in Stranger's mesh (wrist oval is centered at y=+0.002, z=1.456).
ARM_AXIS_Y = 0.002
ARM_AXIS_Z = 1.456

meta = {}   # piece -> {tris, slot}


# ------------------------------------------------------------------ setup

def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    body = bpy.data.objects['Stranger']
    for o in list(bpy.data.objects):
        if o not in (arm, body):
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    if arm.animation_data:
        arm.animation_data_clear()
    return arm, body


def bone_seg(arm, body, name):
    b = arm.data.bones[name]
    inv = body.matrix_world.inverted() @ arm.matrix_world
    return inv @ b.head_local, inv @ b.tail_local


def group_names(body):
    return {g.index: g.name for g in body.vertex_groups}


def closest_on_seg(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return a + ab * t, t


def dominant(v, dl, gn):
    best, bw = None, -1.0
    for gi, w in v[dl].items():
        if w > bw and gi in gn:
            best, bw = gn[gi], w
    return best


def bone_t(arm, body, v, name):
    a, b = bone_seg(arm, body, name)
    _, t = closest_on_seg(v.co, a, b)
    return t


def connected_components(bm, face_pred=None):
    """Return list of lists of BMFace for each connected component matching face_pred."""
    bm.faces.ensure_lookup_table()
    valid = set(f.index for f in bm.faces if (face_pred is None or face_pred(f)))
    seen = set()
    comps = []
    for f in bm.faces:
        if f.index not in valid or f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        comp = []
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index in valid and nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        comps.append(comp)
    return comps


# ------------------------------------------------------------------ fitting & sculpting

def fit_bmesh(bm, arm, body, limb=1.0, torso=1.0, legs=None, offset=0.0, torso_y=None, waist_taper=0.0, wrist_match=False):
    """Scale each vertex toward or away from its anatomical centerline, blended by bone weights, then offset along normal."""
    gn = group_names(body)
    dl = bm.verts.layers.deform.active
    segs = {n: bone_seg(arm, body, n) for n in gn.values() if n in arm.data.bones}
    legs = limb if legs is None else legs
    if torso_y is None:
        ys = [v.co.y for v in bm.verts]
        torso_y = sum(ys) / max(len(ys), 1)
    bm.normal_update()
    new = {}
    for v in bm.verts:
        p = v.co.copy()
        acc = Vector((0, 0, 0))
        wsum = 0.0
        for gi, w in v[dl].items():
            n = gn.get(gi)
            if n is None or w <= 0.0:
                continue
            if n in ARM_BONES:
                # Scale around the true anatomical arm centerline (matching the wrist center of body_head)
                c = Vector((p.x, ARM_AXIS_Y, ARM_AXIS_Z))
                f = limb
                if wrist_match and abs(p.x) > 0.60:
                    # Smoothly blend forearm cuff/wrist radius to match body_head wrist at abs(x)=0.73
                    tw = max(0.0, min(1.0, (abs(p.x) - 0.60) / 0.13))
                    f = limb * (1.0 - tw) + 0.88 * tw
                q = c + (p - c) * f
            elif n in LEG_BONES:
                c, _ = closest_on_seg(p, *segs[n])
                q = c + (p - c) * legs
                # Prevent loose leg meshes from crossing the inner-thigh midline (x=0)
                if p.x > 0.004 and q.x < 0.005:
                    q.x = 0.005
                elif p.x < -0.004 and q.x > -0.005:
                    q.x = -0.005
            else:
                c = Vector((0.0, torso_y, p.z))
                tf = torso
                if waist_taper > 0.0 and p.z < 1.22:
                    # Athletic waist taper so torso/shirts tuck cleanly inside pants waistband at z=1.00
                    wt = max(0.0, min(1.0, (1.22 - p.z) / 0.28))
                    tf = torso * (1.0 - waist_taper * wt)
                q = Vector((c.x + (p.x - c.x) * tf, c.y + (p.y - c.y) * tf, p.z))
            acc += q * w
            wsum += w
        co = acc / wsum if wsum > 0 else p
        new[v] = co + v.normal * offset
    for v, co in new.items():
        v.co = co
    bm.normal_update()


def extract(body, mats, keep_face=None, weld=True):
    """A bmesh with the body's faces of the named materials, welded along seams so smoothing/fitting never cracks."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    if weld:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
    names = [m.name for m in body.data.materials]
    kill = []
    for f in bm.faces:
        if names[f.material_index] not in mats or (keep_face and not keep_face(f, bm)):
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.normal_update()
    return bm


def clean_upper_shell(body, include_waistband=True, include_cuffs=True, include_collar=True, extend_wrist=True):
    """Build a 100% clean, manifold upper-body + sleeve bmesh from Stranger WITHOUT the kangaroo pocket or hood."""
    names = [m.name for m in body.data.materials]
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
    bm.faces.ensure_lookup_table()

    mi_black = names.index('Hoodie black')
    mi_rib = names.index('Hoodie rib')

    keep_faces = set()
    # From Hoodie black: keep ONLY the main torso+sleeve component (~3556 faces), dropping the 500-face kangaroo
    # pocket and the 3323-face outer hood.
    for comp in connected_components(bm, lambda f: f.material_index == mi_black):
        if len(comp) > 3400:
            keep_faces.update(f.index for f in comp)

    # From Hoodie rib: keep waistband, wrist cuffs, and crew-neck collar, dropping the 1024-face hood rim (z > 1.60).
    for comp in connected_components(bm, lambda f: f.material_index == mi_rib):
        zs = [v.co.z for f in comp for v in f.verts]
        xs = [abs(v.co.x) for f in comp for v in f.verts]
        zmax = max(zs)
        xmin = min(xs)
        if zmax < 1.05 and include_waistband:
            keep_faces.update(f.index for f in comp)
        elif xmin > 0.55 and include_cuffs:
            keep_faces.update(f.index for f in comp)
        elif 1.44 < zmax < 1.56 and xmin < 0.20 and include_collar:
            keep_faces.update(f.index for f in comp)

    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep_faces], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    # Weld waistband, cuffs, and collar to the main torso shell
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0015)

    # Smooth out the stomach crease where the kangaroo pocket sat (z=1.02..1.25, y < -0.05, abs(x) < 0.17)
    stomach_vs = [v for v in bm.verts if 0.98 < v.co.z < 1.30 and abs(v.co.x) < 0.18 and v.co.y < -0.04 and not v.is_boundary]
    for _ in range(6):
        bmesh.ops.smooth_vert(bm, verts=stomach_vs, factor=0.55, use_axis_x=True, use_axis_y=True, use_axis_z=True)

    # Also lightly relax arm/shoulder vertices for clean cylindrical limb contours
    arm_vs = [v for v in bm.verts if 0.20 < abs(v.co.x) < 0.68 and not v.is_boundary]
    for _ in range(2):
        bmesh.ops.smooth_vert(bm, verts=arm_vs, factor=0.35, use_axis_x=False, use_axis_y=True, use_axis_z=True)

    # Smooth the collar-to-chest seam so include_collar=True has a seamless transition
    if include_collar:
        col_vs = [v for v in bm.verts if 1.40 < v.co.z < 1.52 and abs(v.co.x) < 0.14 and not v.is_boundary]
        for _ in range(3):
            bmesh.ops.smooth_vert(bm, verts=col_vs, factor=0.45, use_axis_x=True, use_axis_y=True, use_axis_z=True)

    # Ensure upper-chest/collar vertices are weighted to chest+neck (never 'head' from Stranger's hood rib!)
    dl_c = bm.verts.layers.deform.active
    if dl_c is not None and 'head' in body.vertex_groups and 'chest' in body.vertex_groups and 'neck' in body.vertex_groups:
        head_gi = body.vertex_groups['head'].index
        neck_gi = body.vertex_groups['neck'].index
        chest_gi = body.vertex_groups['chest'].index
        for v in bm.verts:
            if v.co.z > 1.36 and abs(v.co.x) < 0.18:
                hw = v[dl_c].get(head_gi, 0.0)
                nw = v[dl_c].get(neck_gi, 0.0)
                if hw > 0.0 or nw > 0.25:
                    if head_gi in v[dl_c]:
                        del v[dl_c][head_gi]
                    cw = v[dl_c].get(chest_gi, 0.0) + hw + max(0.0, nw - 0.18)
                    v[dl_c][chest_gi] = min(1.0, max(0.82, cw))
                    v[dl_c][neck_gi] = min(0.18, nw + hw * 0.25)

    # Extend wrist cuffs from abs(x)=0.706 to abs(x)=0.734 so they meet body_head's wrist oval seamlessly
    if extend_wrist and include_cuffs:
        for v in bm.verts:
            ax = abs(v.co.x)
            if ax > 0.62:
                sx = 1.0 if v.co.x > 0 else -1.0
                t = (ax - 0.62) / (0.706 - 0.62)
                new_ax = 0.62 + t * (0.734 - 0.62)
                v.co.x = sx * new_ax
                # Conform wrist center toward body_head wrist center (y=+0.002, z=1.456)
                blend = max(0.0, min(1.0, (ax - 0.64) / 0.066))
                dy = v.co.y - 0.005
                dz = v.co.z - 1.457
                v.co.y = 0.002 + dy * (1.0 - 0.35 * blend)
                v.co.z = 1.456 + dz * (1.0 - 0.35 * blend)

    bm.normal_update()
    return bm


def cut(bm, co, no):
    """Cut the mesh along a plane and drop everything on the side the normal points to."""
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, dist=0.0001, plane_co=Vector(co), plane_no=Vector(no).normalized(), clear_outer=True)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')


def cut_neck_only(bm, co, no, max_x=0.135):
    """Cut ONLY the central neck/collar region (abs(x) < max_x) without touching the shoulders or arms!"""
    sub_faces = [f for f in bm.faces if all(abs(v.co.x) < max_x for v in f.verts) and any(v.co.z > 1.38 for v in f.verts)]
    sub_edges = list({e for f in sub_faces for e in f.edges})
    sub_verts = list({v for f in sub_faces for v in f.verts})
    geom = sub_verts + sub_edges + sub_faces
    if not geom:
        return
    bmesh.ops.bisect_plane(bm, geom=geom, dist=0.0001, plane_co=Vector(co), plane_no=Vector(no).normalized(), clear_outer=True)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')


def cut_arm(arm, body, bm, bone_side, t):
    """Cut both arms across bone bone_side % side at fraction t along it, dropping the far part."""
    for side in ('L', 'R'):
        a, b = bone_seg(arm, body, bone_side % side)
        p = a.lerp(b, t)
        d = (b - a).normalized()
        # Only bisect arm geometry (abs(x) > 0.16)
        sub_faces = [f for f in bm.faces if any((v.co.x > 0.15 if side == 'L' else v.co.x < -0.15) for v in f.verts)]
        sub_edges = list({e for f in sub_faces for e in f.edges})
        sub_verts = list({v for f in sub_faces for v in f.verts})
        geom = sub_verts + sub_edges + sub_faces
        if geom:
            bmesh.ops.bisect_plane(bm, geom=geom, dist=0.0001, plane_co=p, plane_no=d, clear_outer=True)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')


def add_boundary_rim(bm, z_min=-10.0, z_max=10.0, x_min=0.0, x_max=10.0, depth=0.005):
    """Turn boundary edges inward along -normal and split the fold edge so outer surface normals never bend."""
    bm.normal_update()
    b_edges = [e for e in bm.edges if e.is_boundary and all(
        z_min <= v.co.z <= z_max and x_min <= abs(v.co.x) <= x_max for v in e.verts
    )]
    if not b_edges:
        return
    # Record pre-extrusion outward normals by coordinate so extruded vertices move along exact surface normals
    orig_norms = {}
    for e in b_edges:
        for v in e.verts:
            if v.normal.length > 1e-6:
                orig_norms[(round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))] = v.normal.normalized()
    res = bmesh.ops.extrude_edge_only(bm, edges=b_edges)
    ext_verts = [ele for ele in res['geom'] if isinstance(ele, bmesh.types.BMVert)]
    for v in ext_verts:
        key = (round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))
        n = orig_norms.get(key, v.normal)
        if n.length > 1e-6:
            v.co -= n.normalized() * depth
    try:
        bmesh.ops.split_edges(bm, edges=[e for e in b_edges if e.is_valid])
    except Exception:
        pass
    bm.normal_update()


def keep_by_region(bm, region_of_vertex, want):
    """Keep the faces whose vertices mostly belong to region `want`, with zero gaps between regions."""
    kill = []
    for f in bm.faces:
        votes = {}
        for v in f.verts:
            r = region_of_vertex(v)
            votes[r] = votes.get(r, 0) + 1
        best = max(votes.items(), key=lambda kv: (kv[1], kv[0] == region_of_vertex(f.verts[0])))[0]
        if best != want:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')


def keep_by_vertex(bm, pred, frac=0.5):
    """Delete faces whose vertices mostly fail pred(v)."""
    kill = [f for f in bm.faces if sum(1 for v in f.verts if pred(v)) < len(f.verts) * frac]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')


# ------------------------------------------------------------------ hard-surface & procedural primitives

class Builder:
    """Procedural gear builder: geometry in body space, bound to one bone or custom weights; faces carry a spec."""

    def __init__(self, bone):
        self.bm = bmesh.new()
        self.bone = bone
        self.specs = []
        self.spec_layer = self.bm.faces.layers.int.new('spec')
        self.cur = 0

    def spec(self, layer, rough, color, mask=1.0, tile=0.12):
        self.specs.append((layer, rough, color, mask, tile))
        self.cur = len(self.specs) - 1
        return self

    def _face(self, verts):
        try:
            f = self.bm.faces.new(verts)
            f[self.spec_layer] = self.cur
            return f
        except ValueError:
            return None

    def quad_strip(self, rings, closed=True, cap_start=False, cap_end=False):
        vs = [[self.bm.verts.new(p) for p in ring] for ring in rings]
        n = len(rings[0])
        for i in range(len(vs) - 1):
            for j in range(n if closed else n - 1):
                k = (j + 1) % n
                self._face([vs[i][j], vs[i][k], vs[i + 1][k], vs[i + 1][j]])
        if cap_start and len(vs[0]) >= 3:
            self._face(list(reversed(vs[0])))
        if cap_end and len(vs[-1]) >= 3:
            self._face(vs[-1])
        return vs

    def ellipsoid(self, c, r, phi0=0.0, phi1=math.pi, theta0=0.0, theta1=2 * math.pi, segs=28, rings=14, closed=None):
        closed = abs(theta1 - theta0 - 2 * math.pi) < 1e-6 if closed is None else closed
        rr = []
        for i in range(rings + 1):
            ph = phi0 + (phi1 - phi0) * i / rings
            ring = []
            cnt = segs if closed else segs + 1
            for j in range(cnt):
                th = theta0 + (theta1 - theta0) * j / segs
                ring.append(Vector((
                    c.x + r.x * math.sin(ph) * math.sin(th),
                    c.y - r.y * math.sin(ph) * math.cos(th),
                    c.z + r.z * math.cos(ph)
                )))
            rr.append(ring)
        return self.quad_strip(rr, closed=closed)

    def shell(self, c, r, thick, **kw):
        outer = self.ellipsoid(c, r, **kw)
        ri = Vector((max(r.x - thick, 0.005), max(r.y - thick, 0.005), max(r.z - thick, 0.005)))
        inner = self.ellipsoid(c, ri, **kw)
        inner_faces = set()
        for ring in inner:
            for v in ring:
                inner_faces.update(v.link_faces)
        for f in inner_faces:
            f.normal_flip()
        for idx in (0, -1):
            a = outer[idx]
            b = inner[idx]
            if a[0].co == a[min(1, len(a) - 1)].co:
                continue
            closed = kw.get('closed')
            n = len(a)
            for j in range(n if closed or (closed is None and len(a) > 2) else n - 1):
                k = (j + 1) % n
                if k == 0 and closed is False:
                    break
                self._face([a[j], b[j], b[k], a[k]] if idx == 0 else [a[k], b[k], b[j], a[j]])
        return outer

    def tube(self, pts, radius, segs=12, cap=True, radii=None):
        rings = []
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
            s = d.cross(ref).normalized()
            u = s.cross(d).normalized()
            rad = radii[i] if radii else radius
            rx, ry = (rad if isinstance(rad, tuple) else (rad, rad))
            rings.append([p + s * (math.cos(2 * math.pi * j / segs) * rx) + u * (math.sin(2 * math.pi * j / segs) * ry) for j in range(segs)])
        return self.quad_strip(rings, closed=True, cap_start=cap, cap_end=cap)

    def ring(self, c, axis, radius, width, thick, segs=20, flare=0.0, ry_scale=1.0):
        a = axis.normalized()
        ref = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((1, 0, 0))
        s = a.cross(ref).normalized()
        u = s.cross(a).normalized()
        def circ(cc, rad):
            return [cc + s * (math.cos(2 * math.pi * j / segs) * rad) + u * (math.sin(2 * math.pi * j / segs) * rad * ry_scale) for j in range(segs)]
        rings = [
            circ(c - a * width * 0.5, radius),
            circ(c + a * width * 0.5, radius + flare),
            circ(c + a * width * 0.5, radius + flare + thick),
            circ(c - a * width * 0.5, radius + thick),
        ]
        vs = self.quad_strip(rings, closed=True)
        for j in range(segs):
            k = (j + 1) % segs
            self._face([vs[3][j], vs[3][k], vs[0][k], vs[0][j]])
        return vs

    def box(self, c, size, rot=None, bevel=0.0):
        rot = rot or Matrix.Identity(3)
        h = Vector(size) * 0.5
        if bevel > 0.0:
            # Rounded box via 4 vertical profile rings
            rings = []
            for iz, (zf, rf) in enumerate([(-1.0, 0.72), (-0.75, 1.0), (0.75, 1.0), (1.0, 0.72)]):
                ring = []
                for ang in [0.25, 0.75, 1.25, 1.75]:
                    # 3 points per corner for smooth rounded bevels
                    for da in (-0.12, 0.0, 0.12):
                        th = (ang + da) * math.pi
                        px = math.copysign(max(abs(math.cos(th)), 0.707) * h.x * rf, math.cos(th))
                        py = math.copysign(max(abs(math.sin(th)), 0.707) * h.y * rf, math.sin(th))
                        pz = zf * h.z
                        ring.append(c + rot @ Vector((px, py, pz)))
                rings.append(ring)
            return self.quad_strip(rings, closed=True, cap_start=True, cap_end=True)
        corners = [Vector((sx * h.x, sy * h.y, sz * h.z)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        vs = [self.bm.verts.new(c + rot @ p) for p in corners]
        for q in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]:
            self._face([vs[i] for i in q])
        return vs

    def disc(self, c, axis, radius, segs=16):
        a = axis.normalized()
        ref = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((1, 0, 0))
        s = a.cross(ref).normalized()
        u = s.cross(a).normalized()
        vs = [self.bm.verts.new(c + (s * math.cos(2 * math.pi * j / segs) + u * math.sin(2 * math.pi * j / segs)) * radius) for j in range(segs)]
        self._face(vs)
        return vs


# ------------------------------------------------------------------ writing objects

def make_object(name, bm, arm, body, specs, face_spec=None, uv_scale=6.0, bone=None, bone_weights=None, keep_uv=True):
    """Turn a bmesh into a smooth-shaded, outward-normal skinned object with UVMap, Layer UV2, and Col attribute."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    for poly in me.polygons:
        poly.use_smooth = True

    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = body.matrix_world.copy()
    ob.parent = arm
    ob.matrix_parent_inverse = arm.matrix_world.inverted()
    mod = ob.modifiers.new('Armature', 'ARMATURE')
    mod.object = arm

    if bone_weights is not None:
        for g in list(ob.vertex_groups):
            ob.vertex_groups.remove(g)
        vgs = {}
        for bname, _ in bone_weights:
            vgs[bname] = ob.vertex_groups.new(name=bname)
        all_vi = list(range(len(me.vertices)))
        for bname, w in bone_weights:
            vgs[bname].add(all_vi, w, 'REPLACE')
    elif bone is not None:
        for g in list(ob.vertex_groups):
            ob.vertex_groups.remove(g)
        vg = ob.vertex_groups.new(name=bone)
        vg.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
    else:
        for g in body.vertex_groups:
            if g.name not in ob.vertex_groups:
                ob.vertex_groups.new(name=g.name)

    if not me.uv_layers or not keep_uv:
        for u in list(me.uv_layers):
            me.uv_layers.remove(u)
        uv = me.uv_layers.new(name='UVMap')
        for poly in me.polygons:
            n = poly.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            spec = specs[face_spec[poly.index]] if face_spec and poly.index < len(face_spec) else specs[0]
            tile = spec[4] if len(spec) > 4 else 0.12
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                if ax == 0:
                    uv.data[li].uv = (co.y / tile, co.z / tile)
                elif ax == 1:
                    uv.data[li].uv = (co.x / tile, co.z / tile)
                else:
                    uv.data[li].uv = (co.x / tile, co.y / tile)
    else:
        uv = me.uv_layers[0]
        uv.name = 'UVMap'
        for d in uv.data:
            d.uv = (d.uv[0] * uv_scale, d.uv[1] * uv_scale)
        while len(me.uv_layers) > 1:
            me.uv_layers.remove(me.uv_layers[1])

    lay = me.uv_layers.new(name='Layer')
    col = me.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='CORNER')
    for poly in me.polygons:
        s = specs[face_spec[poly.index]] if face_spec and poly.index < len(face_spec) else specs[0]
        for li in poly.loop_indices:
            lay.data[li].uv = (s[0] + 0.5, s[1])
            c = s[2]
            col.data[li].color = (c[0], c[1], c[2], s[3])
    me.color_attributes.active_color = col
    mat = bpy.data.materials.get('gear')
    if mat is None:
        mat = bpy.data.materials.new('gear')
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsdf:
            vc = nt.nodes.new('ShaderNodeVertexColor')
            vc.layer_name = 'Col'
            nt.links.new(vc.outputs['Color'], bsdf.inputs['Base Color'])
            nt.links.new(vc.outputs['Alpha'], bsdf.inputs['Alpha'])
    me.materials.clear()
    me.materials.append(mat)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    meta[name] = {'tris': tris}
    return ob


def derived(name, bm, arm, body, layer, rough, color, mask=1.0, uv_scale=6.0, **kw):
    ob = make_object(name, bm, arm, body, [(layer, rough, color, mask)], uv_scale=uv_scale)
    bm.free()
    return ob


def hard(name, b, arm, body, bone_weights=None):
    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
    fs = b.bm.faces.layers.int.get('spec')
    face_spec = [f[fs] for f in b.bm.faces]
    ob = make_object(name, b.bm, arm, body, b.specs, face_spec=face_spec, bone=b.bone, bone_weights=bone_weights, keep_uv=False)
    b.bm.free()
    return ob


# ------------------------------------------------------------------ building all pieces

def build_body_head(arm, body, gn):
    """Clean head, neck, eyes, and hands from Stranger's Human skin material:
    - removes stray ankle fragments and floating wrist flaps,
    - extends neck base downward into torso and wrist base inward into forearm so seams are 100% watertight,
    - curls fingers into a natural anatomical tactical grip pose.
    """
    bmh = extract(body, {'Human skin'}, weld=True)
    # Remove stray ankle triangles (z < 1.0) and floating forearm skin flaps (0.50 < abs(x) < 0.728)
    bad_verts = [v for v in bmh.verts if v.co.z < 1.0 or (0.50 < abs(v.co.x) < 0.728)]
    bmesh.ops.delete(bmh, geom=bad_verts, context='VERTS')
    bmesh.ops.delete(bmh, geom=[v for v in bmh.verts if not v.link_faces], context='VERTS')

    # Curl fingers gently around knuckle line (abs(x) > 0.782) for a natural tactical grip / relaxed hand contour
    for v in bmh.verts:
        ax = abs(v.co.x)
        if ax > 0.780 and v.co.z > 1.30:
            sx = 1.0 if v.co.x > 0 else -1.0
            if v.co.y < -0.044:
                # Thumb: slight inward/downward opposition
                t = max(0.0, min(1.0, (ax - 0.775) / 0.055))
                ang = t * math.radians(18.0)
                piv = Vector((sx * 0.775, -0.045, 1.435))
                rel = v.co - piv
                ca, sa = math.cos(ang), math.sin(ang)
                v.co = piv + Vector((rel.x * ca + sx * rel.z * sa, rel.y + 0.004 * t, -sx * rel.x * sa + rel.z * ca))
            else:
                # Four fingers: progressive curl around knuckle pivot
                t = max(0.0, min(1.0, (ax - 0.780) / 0.064))
                ang = (t ** 1.25) * math.radians(28.0)
                piv = Vector((sx * 0.782, v.co.y, 1.442))
                rel = v.co - piv
                ca, sa = math.cos(ang), math.sin(ang)
                v.co = piv + Vector((rel.x * ca + sx * rel.z * sa, rel.y, -sx * rel.x * sa + rel.z * ca))

    # Taper lower neck base (z < 1.505) gently inward toward neck axis (0, -0.035) so it never pokes through shirts/torso
    for v in bmh.verts:
        if abs(v.co.x) < 0.14 and 1.36 < v.co.z < 1.505:
            t_in = max(0.0, min(1.0, (1.505 - v.co.z) / 0.052))
            s_in = 1.0 - 0.26 * (t_in ** 1.15)
            v.co.x *= s_in
            v.co.y = -0.035 + (v.co.y + 0.035) * s_in

    # Extend neck bottom boundary loop downward and inward into upper chest so neck never shows a gap or pokes out
    neck_edges = [e for e in bmh.edges if e.is_boundary and all(abs(v.co.x) < 0.14 and 1.38 < v.co.z < 1.56 for v in e.verts)]
    if neck_edges:
        res = bmesh.ops.extrude_edge_only(bmh, edges=neck_edges)
        ext_vs = [ele for ele in res['geom'] if isinstance(ele, bmesh.types.BMVert)]
        dl = bmh.verts.layers.deform.active
        chest_gi = body.vertex_groups['chest'].index
        neck_gi = body.vertex_groups['neck'].index
        for v in ext_vs:
            v.co.z -= 0.032
            v.co.x *= 0.76
            v.co.y = -0.035 + (v.co.y + 0.035) * 0.76
            v[dl].clear()
            v[dl][chest_gi] = 0.75
            v[dl][neck_gi] = 0.25

    # Extend wrist boundary loops inward to abs(x)=0.700 so wrist plugs deep inside skin_forearm and sleeves
    for side, sx in (('L', 1.0), ('R', -1.0)):
        w_edges = [e for e in bmh.edges if e.is_boundary and all(
            (v.co.x * sx > 0.720 and v.co.x * sx < 0.748 and v.co.z > 1.35) for v in e.verts
        )]
        if w_edges:
            res = bmesh.ops.extrude_edge_only(bmh, edges=w_edges)
            ext_vs = [ele for ele in res['geom'] if isinstance(ele, bmesh.types.BMVert)]
            dl = bmh.verts.layers.deform.active
            fore_gi = body.vertex_groups['forearm.' + side].index
            hand_gi = body.vertex_groups['hand.' + side].index
            for v in ext_vs:
                v.co.x = sx * 0.702
                v.co.y = ARM_AXIS_Y + (v.co.y - ARM_AXIS_Y) * 0.94
                v.co.z = ARM_AXIS_Z + (v.co.z - ARM_AXIS_Z) * 0.94
                v[dl].clear()
                v[dl][fore_gi] = 0.75
                v[dl][hand_gi] = 0.25

    bmh.normal_update()
    me = bpy.data.meshes.new('body_head')
    bmh.to_mesh(me)
    bmh.free()
    for poly in me.polygons:
        poly.use_smooth = True
    ob = bpy.data.objects.new('body_head', me)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = body.matrix_world.copy()
    ob.parent = arm
    ob.matrix_parent_inverse = arm.matrix_world.inverted()
    ob.modifiers.new('Armature', 'ARMATURE').object = arm
    for g in body.vertex_groups:
        ob.vertex_groups.new(name=g.name)
    me.materials.clear()
    me.materials.append(body.data.materials['Human skin'])
    meta['body_head'] = {'tris': sum(len(p.vertices) - 2 for p in me.polygons)}
    return ob


def torso_center_y(y, scale):
    cy = -0.025
    return cy + (y - cy) * scale


def build_closed_shoe_bmesh(body, loose=1.0, height_top=0.105):
    """Build a smooth closed-toe shoe/boot upper + rubber sole over the foot so no bare toes ever appear on shoes."""
    bm_ref = extract(body, {'Sneaker', 'Sneaker sole'}, weld=True)
    dl_ref = bm_ref.verts.layers.deform.active
    kd = kdtree.KDTree(len(bm_ref.verts))
    ref_weights = []
    for idx, v in enumerate(bm_ref.verts):
        kd.insert(v.co, idx)
        ref_weights.append(dict(v[dl_ref].items()))
    kd.balance()

    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    fl = bm.faces.layers.int.new('spec')

    segs = 28
    # Slices from top of ankle collar down to flat sole bottom:
    # (z, cy, cx_abs, rx, ry_front, ry_back, is_sole)
    slices = [
        (height_top,        0.016, 0.104, 0.043, 0.048, 0.048, 0),
        (height_top - 0.012, 0.016, 0.104, 0.046, 0.051, 0.051, 0),
        (0.075,             0.012, 0.106, 0.045, 0.062, 0.054, 0),
        (0.052,            -0.012, 0.112, 0.048, 0.112, 0.078, 0),
        (0.036,            -0.042, 0.118, 0.052, 0.145, 0.106, 0),
        (0.022,            -0.054, 0.120, 0.054, 0.152, 0.120, 0),
        (0.017,            -0.055, 0.120, 0.056, 0.154, 0.122, 1),
        (-0.010,           -0.055, 0.120, 0.057, 0.155, 0.123, 1),
        (-0.010,           -0.055, 0.120, 0.008, 0.020, 0.016, 1),
    ]

    for side_sx in (-1.0, 1.0):
        # Slight natural outward foot splay (~7 degrees)
        ang = side_sx * math.radians(7.0)
        ca, sa = math.cos(ang), math.sin(ang)
        rings = []
        for z, cy, cx_abs, rx, ry_f, ry_b, _ in slices:
            s = loose if rx > 0.015 else 1.0
            cx = side_sx * cx_abs
            ring = []
            for j in range(segs):
                th = 2.0 * math.pi * j / segs
                ux = math.sin(th) * (rx * s)
                cs = math.cos(th)
                ry = (ry_f if cs >= 0.0 else ry_b) * s
                uy = -cs * ry
                # Rotate (ux, uy) by foot splay around ankle/foot center
                wx = cx + ux * ca - uy * sa
                wy = cy + ux * sa + uy * ca
                # Arch the instep/toe-box crown slightly in the middle slices
                wz = z
                if 0.030 < z < 0.070 and cs > 0.0:
                    wz += 0.006 * (cs ** 1.5) * (1.0 - abs(math.sin(th)))
                v = bm.verts.new((wx, wy, wz))
                _, r_idx, _ = kd.find(v.co)
                for gi, w in ref_weights[r_idx].items():
                    v[dl][gi] = w
                ring.append(v)
            rings.append(ring)

        for i in range(len(rings) - 1):
            spec_val = slices[i + 1][6]
            r0, r1 = rings[i], rings[i + 1]
            for j in range(segs):
                k = (j + 1) % segs
                try:
                    f = bm.faces.new([r0[j], r0[k], r1[k], r1[j]])
                    f[fl] = spec_val
                except ValueError:
                    pass

    bm_ref.free()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    return bm, fl


def main():
    arm, body = setup()
    gn = group_names(body)
    names = [m.name for m in body.data.materials]
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(CHECK_DIR, exist_ok=True)

    # Head landmarks and skin tone sampling
    bm0 = bmesh.new()
    bm0.from_mesh(body.data)
    dl0 = bm0.verts.layers.deform.active
    head_vs = [v.co.copy() for v in bm0.verts if dominant(v, dl0, gn) == 'head' and v.co.z > 1.50 and
               any(names[f.material_index] == 'Human skin' for f in v.link_faces)]
    hx = [v.x for v in head_vs]
    hy = [v.y for v in head_vs]
    hz = [v.z for v in head_vs]
    # Cranium center above the ears (z=1.70..1.80) so hats/helmets/hair fit the skull, not the nose+ears bounding box!
    cran_vs = [v for v in head_vs if v.z > 1.70]
    cran_c = Vector((0.0, -0.037, 1.705))
    cran_r = Vector((0.080, 0.101, 0.095))
    head_c = Vector(((min(hx) + max(hx)) / 2, (min(hy) + max(hy)) / 2, (min(hz) + max(hz)) / 2))
    head_r = Vector(((max(hx) - min(hx)) / 2, (max(hy) - min(hy)) / 2, (max(hz) - min(hz)) / 2))
    top = max(hz)
    torso_vs = [v.co.y for v in bm0.verts if dominant(v, dl0, gn) in ('spine', 'chest')]
    torso_y = sum(torso_vs) / max(len(torso_vs), 1)

    skin_col = (0.485, 0.218, 0.132)
    img = next((i for i in bpy.data.images), None)
    if img and img.size[0] > 0:
        px = list(img.pixels)
        w, h = img.size
        # De-shadow the baked dark hood vignette on the head/face UV island (u < 0.215, 0.55 < v < 0.88)
        # using local Retinex decomposition (detail = pixel / local_blur) so eyes, brows, nostrils & lips stay crisp
        # while the face skin tone matches the hands, neck, and body 100%.
        ref_srgb = (0.675, 0.468, 0.372)
        u_max = min(int(0.235 * w), w)
        v_min = max(int(0.52 * h), 0)
        v_max = min(int(0.91 * h), h)
        rad = max(int(0.022 * w), 4)
        # Compute local blurred RGB inside the head UV box
        horiz = {}
        for y in range(v_min, v_max):
            for x in range(0, u_max):
                x0, x1 = max(0, x - rad), min(u_max - 1, x + rad)
                cnt_x = x1 - x0 + 1
                sr = sg = sb = 0.0
                row_off = y * w
                for xx in range(x0, x1 + 1):
                    idx = (row_off + xx) * 4
                    sr += px[idx]
                    sg += px[idx + 1]
                    sb += px[idx + 2]
                horiz[(x, y)] = (sr / cnt_x, sg / cnt_x, sb / cnt_x)
        for y in range(v_min, v_max):
            v_coord = y / float(h)
            if v_coord < 0.55 or v_coord > 0.885:
                continue
            wy = min(1.0, (v_coord - 0.55) / 0.035, (0.885 - v_coord) / 0.035)
            for x in range(0, u_max):
                u_coord = x / float(w)
                if u_coord > 0.212:
                    continue
                wx = min(1.0, (0.212 - u_coord) / 0.025)
                mask = max(0.0, min(1.0, wx * wy))
                if mask <= 0.0:
                    continue
                y0, y1 = max(v_min, y - rad), min(v_max - 1, y + rad)
                cnt_y = y1 - y0 + 1
                br = bg = bb = 0.0
                for yy in range(y0, y1 + 1):
                    hr, hg, hb = horiz[(x, yy)]
                    br += hr
                    bg += hg
                    bb += hb
                br /= cnt_y
                bg /= cnt_y
                bb /= cnt_y
                if br < ref_srgb[0] * 0.98:
                    idx = (y * w + x) * 4
                    for k, bval in enumerate((br, bg, bb)):
                        orig = px[idx + k]
                        ratio = max(0.22, min(1.22, orig / max(bval, 0.045)))
                        restored = min(1.0, ref_srgb[k] * ratio)
                        px[idx + k] = orig * (1.0 - mask) + restored * mask
        img.pixels = px
        img.update()
        try:
            img.pack()
        except Exception:
            pass
        # Compute linear vertex color for bare skin so 0.86 * skin_col matches srgb_to_linear(ref_srgb)
        def srgb_to_lin(c):
            return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        skin_col = tuple(min(1.0, srgb_to_lin(ref_srgb[k]) / 0.86) for k in range(3))
    bm0.free()
    print('[gear] cranium', tuple(round(x, 3) for x in cran_c), 'radii', tuple(round(x, 3) for x in cran_r), 'skin_lin', skin_col)

    # ---------------- 1. body_head (head, neck, eyes, hands)
    ob_head = build_body_head(arm, body, gn)

    # Build BVHTree of actual head/neck surface from body_head for exact fitting of hair, helmets, goggles, masks & neck collars
    bm_head_bvh = bmesh.new()
    bm_head_bvh.from_mesh(ob_head.data)
    bmesh.ops.delete(bm_head_bvh, geom=[v for v in bm_head_bvh.verts if abs(v.co.x) > 0.25 or v.co.z < 1.43], context='VERTS')
    bvh_head = BVHTree.FromBMesh(bm_head_bvh)
    bm_head_bvh.free()

    def head_r_at(center, dir_u, fallback=0.085):
        u = dir_u.normalized()
        hit, _, _, _ = bvh_head.ray_cast(center + u * 0.26, -u, 0.26)
        if hit is not None:
            return (hit - center).length
        return fallback

    def conform_neck_collar(bm, radial_extra=0.0):
        """Gently match ONLY the top collar boundary loop (z > 1.465) to body_head's neck without collapsing the chest."""
        for v in bm.verts:
            if v.is_boundary and v.co.z > 1.465 and abs(v.co.x) < 0.115:
                neck_c = Vector((0.0, -0.035, v.co.z))
                dx = v.co.x - neck_c.x
                dy = v.co.y - neck_c.y
                th = math.atan2(dx, -dy)
                dir_xy = Vector((math.sin(th), -math.cos(th), 0.0)).normalized()
                r_neck = head_r_at(Vector((0.0, -0.035, max(1.482, v.co.z))), dir_xy, fallback=0.058) + radial_extra
                v.co.x = neck_c.x + dir_xy.x * r_neck
                v.co.y = neck_c.y + dir_xy.y * r_neck
        bm.normal_update()

    # ---------------- 2. bare skin under clothes (watertight, unified fit before region split, zero decimation)
    def arm_region(v, dl):
        d = dominant(v, dl, gn)
        if d in ('forearm.L', 'forearm.R', 'hand.L', 'hand.R') or (abs(v.co.x) > 0.44 and v.co.z > 1.30):
            return 'skin_forearm'
        if abs(v.co.x) > 0.092 and v.co.z > 1.20:
            return 'skin_upperarm'
        return 'skin_torso'

    # Keep a reference KDTree of skin_torso so shirts can guarantee strict >= 4 mm radial clearance everywhere
    bm_skin_torso_ref = clean_upper_shell(body, include_waistband=True, include_cuffs=True, include_collar=False, extend_wrist=True)
    fit_bmesh(bm_skin_torso_ref, arm, body, limb=0.76, torso=0.88, offset=-0.002, torso_y=torso_y, waist_taper=0.16, wrist_match=True)
    kd_skin_torso = kdtree.KDTree(len(bm_skin_torso_ref.verts))
    skin_torso_pts = []
    for idx, v in enumerate(bm_skin_torso_ref.verts):
        kd_skin_torso.insert(v.co, idx)
        skin_torso_pts.append((v.co.copy(), v.normal.copy()))
    kd_skin_torso.balance()
    bm_skin_torso_ref.free()

    for rname in ('skin_torso', 'skin_upperarm', 'skin_forearm'):
        bm = clean_upper_shell(body, include_waistband=True, include_cuffs=True, include_collar=False, extend_wrist=True)
        # Fit the ENTIRE unified shell first so boundary vertices & normals match 100% across torso/upperarm/forearm!
        fit_bmesh(bm, arm, body, limb=0.76, torso=0.88, offset=-0.002, torso_y=torso_y, waist_taper=0.16, wrist_match=True)
        dl = bm.verts.layers.deform.active
        keep_by_region(bm, lambda v: arm_region(v, dl), rname)
        derived(rname, bm, arm, body, SKIN, 0.55, skin_col, 1.0, uv_scale=3.0)

    for rname in ('skin_thigh', 'skin_shin'):
        bm = extract(body, {'Jeans dark'}, weld=True)
        leg_vs = [v for v in bm.verts if not v.is_boundary]
        for _ in range(3):
            bmesh.ops.smooth_vert(bm, verts=leg_vs, factor=0.4, use_axis_x=True, use_axis_y=True, use_axis_z=False)
        # Fit the entire leg shell first so the knee boundary between skin_thigh and skin_shin is 100% seamless
        fit_bmesh(bm, arm, body, limb=0.84, legs=0.84, torso=0.88, offset=-0.002, torso_y=torso_y)
        dl = bm.verts.layers.deform.active
        keep_by_region(bm, lambda v: 'skin_shin' if dominant(v, dl, gn) in ('shin.L', 'shin.R', 'foot.L', 'foot.R') else 'skin_thigh', rname)
        if rname == 'skin_thigh':
            # Only exposed below shorts hem (z=0.60); trim above z=0.72 so upper thigh/hip skin never clips shorts in sprint
            cut(bm, (0, 0, 0.72), (0, 0, 1))
        derived(rname, bm, arm, body, SKIN, 0.55, skin_col, 1.0, uv_scale=3.0)

    bm = extract(body, {'Sneaker', 'Sneaker sole'}, weld=True)
    fit_bmesh(bm, arm, body, limb=0.82, legs=0.82, offset=-0.004, torso_y=torso_y)
    # Reshape Sneaker tongue/heel into a sleek anatomical bare foot resting flat on the tsinelas footbed (z=0.011)
    foot_smooth_vs = [v for v in bm.verts if not v.is_boundary and v.co.z < 0.085]
    for _ in range(6):
        bmesh.ops.smooth_vert(bm, verts=foot_smooth_vs, factor=0.55, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    for v in bm.verts:
        if v.co.z < 0.012:
            v.co.z = 0.011
        elif v.co.z < 0.085 and v.co.y < -0.01:
            # Press down puffed sneaker tongue to a low anatomical foot dorsum slope
            max_dorsum_z = 0.026 + max(0.0, (v.co.y + 0.185) * 0.28)
            if v.co.z > max_dorsum_z:
                v.co.z = v.co.z * 0.25 + max_dorsum_z * 0.75
    # Extend ankle top loop up by 2.8 cm into skin_shin so bare ankles never show a gap
    ankle_edges = [e for e in bm.edges if e.is_boundary and all(v.co.z > 0.07 for v in e.verts)]
    if ankle_edges:
        res = bmesh.ops.extrude_edge_only(bm, edges=ankle_edges)
        for ele in res['geom']:
            if isinstance(ele, bmesh.types.BMVert):
                ele.co.z += 0.028
    bm.normal_update()
    # Build KDTree of skin_feet so boots_tsinelas inherits the exact same foot+toe+shin weights as skin_feet!
    dl_feet = bm.verts.layers.deform.active
    kd_feet = kdtree.KDTree(len(bm.verts))
    feet_weights = []
    for idx, v in enumerate(bm.verts):
        kd_feet.insert(v.co, idx)
        feet_weights.append(dict(v[dl_feet].items()))
    kd_feet.balance()
    derived('skin_feet', bm, arm, body, SKIN, 0.55, skin_col, 1.0, uv_scale=3.0)

    # ---------------- 3. inner shirts (over skin, under jackets; tapered waist tucks cleanly inside pants)
    def shirt(name, sleeve, limb, torso, layer, rough, col, uvs=7.0, hem=0.96, collar=True):
        bm = clean_upper_shell(body, include_waistband=False, include_cuffs=(sleeve is None or sleeve[0] == 'fore'), include_collar=False, extend_wrist=True)
        cut(bm, (0, 0, hem), (0, 0, -1))
        if sleeve == 'tank':
            # Clean full-mesh armhole bisection on both shoulders (never tears back faces)
            for sx in (-1, 1):
                cut(bm, (sx * 0.148, 0, 1.34), (sx * 0.94, 0, 0.34))
        elif sleeve:
            cut_arm(arm, body, bm, 'upper_arm.%s' if sleeve[0] == 'upper' else 'forearm.%s', sleeve[1])
        fit_bmesh(bm, arm, body, limb=limb, torso=torso, offset=0.003, torso_y=torso_y, waist_taper=0.18, wrist_match=(sleeve is not None and sleeve[0] == 'fore'))
        if sleeve == 'tank':
            # Scoop front neckline cleanly after fitting and ensure strict outward clearance over skin_torso
            for v in bm.verts:
                if abs(v.co.x) < 0.088 and v.co.y < torso_y and v.co.z > 1.42:
                    w = 1.0 - (abs(v.co.x) / 0.088) ** 2
                    v.co.z -= 0.022 * w
        # Guarantee every vertex of shirt_* sits at least 4.5 mm outside skin_torso so zero skin ever pokes through
        bm.normal_update()
        for v in bm.verts:
            if v.co.z > 1.15 and abs(v.co.x) < 0.22:
                co_s, idx_s, dist_s = kd_skin_torso.find(v.co)
                _, n_s = skin_torso_pts[idx_s]
                if n_s.length > 1e-6:
                    n_u = n_s.normalized()
                    signed_d = (v.co - co_s).dot(n_u)
                    if signed_d < 0.0045:
                        v.co += n_u * (0.0045 - signed_d)
        bm.normal_update()
        if sleeve != 'tank':
            add_boundary_rim(bm, z_min=1.20, z_max=1.55, x_min=0.14, x_max=0.75, depth=0.003)
        return derived(name, bm, arm, body, layer, rough, col, 1.0, uv_scale=uvs)

    shirt('shirt_tee', ('upper', 0.52), 0.82, 0.91, COTTON, 0.88, (0.92, 0.92, 0.90), collar=True)
    shirt('shirt_tank', 'tank', 0.80, 0.90, COTTON, 0.88, (0.90, 0.90, 0.88), collar=False)
    shirt('shirt_longsleeve', ('fore', 0.96), 0.80, 0.91, KNIT, 0.92, (0.50, 0.52, 0.55), uvs=9.0, collar=True)
    shirt('shirt_jersey', 'tank', 0.84, 0.92, MESH, 0.78, (0.95, 0.95, 0.95), uvs=8.0, hem=0.95, collar=False)
    shirt('shirt_polo', ('upper', 0.46), 0.84, 0.91, PLAID, 0.88, (1.0, 1.0, 1.0), uvs=4.0, collar=True)

    # ---------------- 4. jackets (outermost torso layer: torso >= 1.01, offset = 0.006 so jackets sit cleanly over pants waist)
    bm_h = clean_upper_shell(body, include_waistband=True, include_cuffs=True, include_collar=False, extend_wrist=True)
    fl_h = bm_h.faces.layers.int.new('spec')
    mi_rib = names.index('Hoodie rib')
    for f in bm_h.faces:
        f[fl_h] = 1 if f.material_index == mi_rib else 0
    fit_bmesh(bm_h, arm, body, limb=0.98, torso=1.02, offset=0.006, torso_y=torso_y, waist_taper=0.0)
    add_boundary_rim(bm_h, z_min=0.88, z_max=1.56, x_min=0.0, x_max=0.75, depth=0.008)
    make_object('jacket_hoodie', bm_h, arm, body, [
        (COTTON, 0.92, (1, 1, 1), 1.0),
        (KNIT, 0.95, (1, 1, 1), 1.0),
    ], face_spec=[f[fl_h] for f in bm_h.faces], uv_scale=6.0)
    bm_h.free()

    bm_hood = extract(body, {'Hoodie black', 'Hoodie rib', 'Hood lining', 'Hoodie drawstring'}, weld=True)
    mi_lining = names.index('Hood lining')
    hood_faces = set()
    for comp in connected_components(bm_hood):
        zs = [v.co.z for f in comp for v in f.verts]
        mats_in_comp = {f.material_index for f in comp}
        if (mi_lining in mats_in_comp) or (max(zs) > 1.60 and min(zs) > 1.40):
            hood_faces.update(f.index for f in comp)
    bmesh.ops.delete(bm_hood, geom=[f for f in bm_hood.faces if f.index not in hood_faces], context='FACES')
    bmesh.ops.delete(bm_hood, geom=[v for v in bm_hood.verts if not v.link_faces], context='VERTS')
    fl_hd = bm_hood.faces.layers.int.new('spec')
    for f in bm_hood.faces:
        f[fl_hd] = {'Hoodie black': 0, 'Hoodie rib': 1, 'Hood lining': 2, 'Hoodie drawstring': 3}[names[f.material_index]]
    fit_bmesh(bm_hood, arm, body, limb=0.98, torso=1.02, offset=0.006, torso_y=torso_y)
    make_object('jacket_hoodie_hood', bm_hood, arm, body, [
        (COTTON, 0.92, (1, 1, 1), 1.0),
        (KNIT, 0.95, (1, 1, 1), 1.0),
        (COTTON, 0.95, (0.32, 0.32, 0.34), 0.0),
        (COTTON, 0.80, (0.85, 0.85, 0.82), 0.0),
    ], face_spec=[f[fl_hd] for f in bm_hood.faces], uv_scale=6.0)
    bm_hood.free()

    def jacket(name, layer, rough, col, cut_hem=0.94, loose=1.01, open_front=False, uvs=6.0, quilt_baffles=False):
        bm = clean_upper_shell(body, include_waistband=(cut_hem < 0.96), include_cuffs=True, include_collar=False, extend_wrist=True)
        if cut_hem > 0.91:
            cut(bm, (0, 0, cut_hem), (0, 0, -1))
        cut_arm(arm, body, bm, 'forearm.%s', 0.95)
        if open_front:
            geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
            bmesh.ops.bisect_plane(bm, geom=geom, dist=0.0001, plane_co=Vector((0.042, 0, 0)), plane_no=Vector((1, 0, 0)))
            geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
            bmesh.ops.bisect_plane(bm, geom=geom, dist=0.0001, plane_co=Vector((-0.042, 0, 0)), plane_no=Vector((1, 0, 0)))
            kill = [f for f in bm.faces if abs(f.calc_center_median().x) < 0.042 and f.calc_center_median().y < torso_y and f.calc_center_median().z < 1.54]
            bmesh.ops.delete(bm, geom=kill, context='FACES')
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        fit_bmesh(bm, arm, body, limb=loose, torso=max(loose, 1.01), offset=0.006, torso_y=torso_y, waist_taper=0.0)
        if quilt_baffles:
            # Puffer jacket sculpted horizontal baffle ridges
            for v in bm.verts:
                if 0.96 < v.co.z < 1.48:
                    puff = 0.0045 * abs(math.sin((v.co.z - 0.95) * math.pi / 0.085))
                    v.co += v.normal * puff
        add_boundary_rim(bm, z_min=0.88, z_max=1.56, x_min=0.0, x_max=0.75, depth=0.008)
        return derived(name, bm, arm, body, layer, rough, col, 1.0, uv_scale=uvs)

    jacket('jacket_bomber', NYLON, 0.48, (0.32, 0.36, 0.24), cut_hem=0.95, loose=1.01)
    jacket('jacket_denim', DENIM, 0.85, (0.32, 0.42, 0.62), cut_hem=0.95, loose=1.01, open_front=True)
    jacket('jacket_flannel', PLAID, 0.88, (1.0, 1.0, 1.0), cut_hem=0.93, loose=1.01, open_front=True, uvs=4.0)
    jacket('jacket_puffer', QUILT, 0.65, (0.75, 0.20, 0.18), cut_hem=0.94, loose=1.04, quilt_baffles=True)
    jacket('jacket_field', CAMO, 0.88, (1.0, 1.0, 1.0), cut_hem=0.91, loose=1.02, uvs=3.0)

    # Bomber knit collar and fitted wrist cuffs (aligned to true arm centerline ARM_AXIS_Y, ARM_AXIS_Z)
    b = Builder('neck').spec(KNIT, 0.92, (0.15, 0.15, 0.14), 1.0, 0.04)
    b.ring(Vector((0.0, -0.022, 1.502)), Vector((0, -0.18, 1)), 0.066, 0.036, 0.008, segs=24, ry_scale=0.95)
    hard('jacket_bomber_collar', b, arm, body)
    for side in ('L', 'R'):
        sx = 1.0 if side == 'L' else -1.0
        b = Builder('forearm.' + side).spec(KNIT, 0.92, (0.15, 0.15, 0.14), 1.0, 0.04)
        cuff_c = Vector((sx * 0.695, ARM_AXIS_Y, ARM_AXIS_Z))
        b.ring(cuff_c, Vector((sx, 0, 0)), 0.035, 0.048, 0.008, segs=20, ry_scale=0.84)
        hard('jacket_bomber_cuff_' + side, b, arm, body)

    # Denim / field jacket chest & tactical pockets (flush with the chest contour)
    for name, layer, col, is_field in (('jacket_denim_pockets', DENIM, (0.30, 0.40, 0.60), False),
                                       ('jacket_field_pockets', CAMO, (1, 1, 1), True)):
        b = Builder('chest').spec(layer, 0.85, col, 1.0, 0.05)
        for sx in (-1, 1):
            rot = Matrix.Rotation(sx * math.radians(-10.0), 3, 'Z') @ Matrix.Rotation(math.radians(8.0), 3, 'X')
            b.box(Vector((sx * 0.078, -0.156, 1.350)), (0.068, 0.014, 0.078), rot, bevel=0.003)
            b.box(Vector((sx * 0.078, -0.159, 1.384)), (0.072, 0.016, 0.020), rot, bevel=0.002)
            if is_field:
                rot_l = Matrix.Rotation(sx * math.radians(-12.0), 3, 'Z')
                b.box(Vector((sx * 0.088, -0.150, 1.135)), (0.078, 0.016, 0.090), rot_l, bevel=0.003)
                b.box(Vector((sx * 0.088, -0.153, 1.175)), (0.082, 0.018, 0.022), rot_l, bevel=0.002)
        hard(name, b, arm, body)

    # ---------------- 5. pants (smooth anatomy, waist torso=0.98 sits cleanly over shirts and under jackets)
    def cinch_waist_top(bm):
        for v in bm.verts:
            if v.co.z > 0.975:
                t = min(1.0, (v.co.z - 0.975) / 0.045)
                s = 1.0 - 0.09 * t
                v.co.x *= s
                v.co.y = torso_y + (v.co.y - torso_y) * s
        bm.normal_update()

    def pants(name, layer, rough, col, loose=1.00, uvs=6.0):
        bm = extract(body, {'Jeans dark'}, weld=True)
        leg_vs = [v for v in bm.verts if not v.is_boundary]
        for _ in range(2):
            bmesh.ops.smooth_vert(bm, verts=leg_vs, factor=0.30, use_axis_x=True, use_axis_y=True, use_axis_z=False)
        fit_bmesh(bm, arm, body, limb=loose, legs=loose, torso=0.98, offset=0.003, torso_y=torso_y)
        cinch_waist_top(bm)
        # Turn the top waistband rim (z > 0.95) and ankle cuffs (z < 0.12) inward so there is never a gap against the shirt
        add_boundary_rim(bm, z_min=0.94, z_max=1.05, x_min=0.0, x_max=0.30, depth=0.026)
        add_boundary_rim(bm, z_min=0.05, z_max=0.14, x_min=0.0, x_max=0.30, depth=0.008)
        return derived(name, bm, arm, body, layer, rough, col, 1.0, uv_scale=uvs)

    pants('pants_jeans', DENIM, 0.85, (0.22, 0.28, 0.42), loose=1.01)
    pants('pants_cargo', CANVAS, 0.88, (0.55, 0.50, 0.36), loose=1.04)
    pants('pants_track', NYLON, 0.55, (0.12, 0.14, 0.20), loose=1.02)
    pants('pants_camo', CAMO, 0.88, (1, 1, 1), loose=1.03, uvs=3.0)

    # Basketball shorts: clean mid-thigh cut at z=0.55 with turned-in hem rim and snug closed waistband
    bm = extract(body, {'Jeans dark'}, weld=True)
    leg_vs = [v for v in bm.verts if not v.is_boundary]
    for _ in range(2):
        bmesh.ops.smooth_vert(bm, verts=leg_vs, factor=0.30, use_axis_x=True, use_axis_y=True, use_axis_z=False)
    ta, tb = bone_seg(arm, body, 'thigh.L')
    cut(bm, ta.lerp(tb, 0.62), (0, 0, -1))
    fit_bmesh(bm, arm, body, limb=1.03, legs=1.03, torso=0.98, offset=0.004, torso_y=torso_y)
    cinch_waist_top(bm)
    add_boundary_rim(bm, z_min=0.94, z_max=1.05, x_min=0.0, x_max=0.30, depth=0.026)
    add_boundary_rim(bm, z_min=0.50, z_max=0.65, x_min=0.0, x_max=0.30, depth=0.012)
    derived('pants_shorts', bm, arm, body, MESH, 0.75, (0.90, 0.90, 0.92), 1.0, uv_scale=7.0)

    # Cargo pockets on outer thighs (beveled tactical bellows pockets)
    for side in ('L', 'R'):
        ta, tb = bone_seg(arm, body, 'thigh.' + side)
        sx = 1 if side == 'L' else -1
        b = Builder('thigh.' + side).spec(CANVAS, 0.88, (0.50, 0.46, 0.33), 1.0, 0.05)
        p = ta.lerp(tb, 0.48) + Vector((sx * 0.088, -0.012, 0.0))
        rot = Matrix.Rotation(sx * math.radians(5.0), 3, 'Y')
        b.box(p, (0.026, 0.135, 0.165), rot, bevel=0.004)
        b.box(p + Vector((sx * 0.004, 0, 0.082)), (0.032, 0.142, 0.028), rot, bevel=0.003)
        hard('pants_cargo_pocket_' + side, b, arm, body)

    # ---------------- 6. footwear (closed-toe sneakers/boots so no bare toes ever appear inside shoes!)
    bm, fl = build_closed_shoe_bmesh(body, loose=1.00, height_top=0.105)
    fs = [f[fl] for f in bm.faces]
    make_object('boots_sneakers', bm, arm, body, [
        (CANVAS, 0.75, (0.90, 0.90, 0.90), 1.0, 0.06),
        (RUBBER, 0.65, (0.95, 0.95, 0.93), 0.0, 0.06),
    ], face_spec=fs, keep_uv=False)
    bm.free()

    bm, fl = build_closed_shoe_bmesh(body, loose=1.03, height_top=0.115)
    fs = [f[fl] for f in bm.faces]
    make_object('boots_combat', bm, arm, body, [
        (LEATHER, 0.45, (0.12, 0.11, 0.10), 1.0, 0.06),
        (RUBBER, 0.78, (0.08, 0.08, 0.08), 0.0, 0.06),
    ], face_spec=fs, keep_uv=False)
    bm.free()

    bm, fl = build_closed_shoe_bmesh(body, loose=1.05, height_top=0.115)
    fs = [f[fl] for f in bm.faces]
    make_object('boots_rubber', bm, arm, body, [
        (RUBBER, 0.32, (0.20, 0.35, 0.18), 1.0, 0.06),
        (RUBBER, 0.50, (0.12, 0.12, 0.12), 0.0, 0.06),
    ], face_spec=fs, keep_uv=False)
    bm.free()

    # Boot shafts (smooth, tucked over trouser cuffs with solid top rims)
    for name, top_z, grow, layer, rough, col in (
        ('boots_combat_shaft', 0.26, 0.006, LEATHER, 0.45, (0.12, 0.11, 0.10)),
        ('boots_rubber_shaft', 0.39, 0.009, RUBBER, 0.32, (0.20, 0.35, 0.18)),
    ):
        bm = extract(body, {'Jeans dark'}, weld=True)
        cut(bm, (0, 0, top_z), (0, 0, 1))
        fit_bmesh(bm, arm, body, limb=1.01, legs=1.01, torso=1.0, offset=grow, torso_y=torso_y)
        add_boundary_rim(bm, z_min=top_z - 0.03, z_max=top_z + 0.03, x_min=0.0, x_max=0.30, depth=0.008)
        derived(name, bm, arm, body, layer, rough, col, 1.0, uv_scale=6.0)

    # Tsinelas: contoured footbed matching exact foot angle (+ang) & inheriting skin_feet's exact bone weights via KDTree
    for side in ('L', 'R'):
        sx = 1.0 if side == 'L' else -1.0
        b = Builder('foot.' + side).spec(RUBBER, 0.68, (0.20, 0.40, 0.75), 1.0, 0.05)
        heel = Vector((sx * 0.105, 0.068, 0.004))
        toe = Vector((sx * 0.136, -0.192, 0.004))
        mid = heel.lerp(toe, 0.52)
        ang = math.atan2(toe.x - heel.x, -(toe.y - heel.y))
        rot = Matrix.Rotation(ang, 3, 'Z')
        b.box(mid, (0.094, (toe - heel).length + 0.008, 0.013), rot, bevel=0.004)
        b.spec(RUBBER, 0.55, (0.92, 0.92, 0.90), 0.0, 0.05)
        post = heel.lerp(toe, 0.76) + rot @ Vector((-sx * 0.010, 0, 0.006))
        b.tube([post, post + Vector((0, 0.006, 0.024))], 0.004, segs=8)
        for ss in (-1, 1):
            side_pt = heel.lerp(toe, 0.44) + rot @ Vector((ss * 0.045, 0, 0.006))
            apex = (post + side_pt) * 0.5 + Vector((ss * 0.006, 0.008, 0.032))
            b.tube([post + Vector((0, 0.006, 0.022)), apex, side_pt], 0.005, segs=10)
        # Transfer exact bone weights from skin_feet so the flip-flop sole deforms identically with the bare foot
        dl_ts = b.bm.verts.layers.deform.verify()
        for v in b.bm.verts:
            _, r_idx, _ = kd_feet.find(v.co)
            for gi, w in feet_weights[r_idx].items():
                v[dl_ts][gi] = w
        bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
        fs_ts = b.bm.faces.layers.int.get('spec')
        face_spec_ts = [f[fs_ts] for f in b.bm.faces]
        make_object('boots_tsinelas_' + side, b.bm, arm, body, b.specs, face_spec=face_spec_ts, keep_uv=False)
        b.bm.free()

    # ---------------- 7. gloves (matched to our curled-finger body_head hands, zero boundary spikes or fingertip poke-through)
    def glove(name, layer, rough, col, off, knuckles=None):
        bm = extract(body, {'Human skin'}, weld=True)
        bad_v = [v for v in bm.verts if v.co.z < 1.25 or abs(v.co.x) < 0.722]
        bmesh.ops.delete(bm, geom=bad_v, context='VERTS')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        # Apply the exact same finger curl as body_head so gloves wrap the curled fingers with 0 clipping
        for v in bm.verts:
            ax = abs(v.co.x)
            if ax > 0.780 and v.co.z > 1.30:
                sx = 1.0 if v.co.x > 0 else -1.0
                if v.co.y < -0.044:
                    t = max(0.0, min(1.0, (ax - 0.775) / 0.055))
                    ang = t * math.radians(18.0)
                    piv = Vector((sx * 0.775, -0.045, 1.435))
                    rel = v.co - piv
                    ca, sa = math.cos(ang), math.sin(ang)
                    v.co = piv + Vector((rel.x * ca + sx * rel.z * sa, rel.y + 0.004 * t, -sx * rel.x * sa + rel.z * ca))
                else:
                    t = max(0.0, min(1.0, (ax - 0.780) / 0.064))
                    ang = (t ** 1.25) * math.radians(28.0)
                    piv = Vector((sx * 0.782, v.co.y, 1.442))
                    rel = v.co - piv
                    ca, sa = math.cos(ang), math.sin(ang)
                    v.co = piv + Vector((rel.x * ca + sx * rel.z * sa, rel.y, -sx * rel.x * sa + rel.z * ca))
        if knuckles:
            for sx in (-1, 1):
                cut(bm, (sx * knuckles, 0, 0), (sx, 0, 0))
        bm.normal_update()
        # Smoothly inflate outward along vertex normals + slight axial fingertip clearance so skin never pokes through
        for v in bm.verts:
            sx = 1.0 if v.co.x > 0 else -1.0
            tip_t = max(0.0, min(1.0, (abs(v.co.x) - 0.775) / 0.065)) if not knuckles else 0.0
            v.co += v.normal * off + Vector((sx * 0.0028 * tip_t, -0.0012 * tip_t, -0.0022 * tip_t))
        bm.normal_update()
        return derived(name, bm, arm, body, layer, rough, col, 1.0, uv_scale=8.0)

    knuckle_x = 0.792
    glove('gloves_tactical', NYLON, 0.58, (0.12, 0.12, 0.13), 0.0030)
    glove('gloves_fingerless', LEATHER, 0.55, (0.18, 0.12, 0.08), 0.0028, knuckles=knuckle_x)
    glove('gloves_work', CANVAS, 0.85, (0.75, 0.62, 0.40), 0.0036)
    glove('gloves_wraps', COTTON, 0.92, (0.92, 0.92, 0.90), 0.0026, knuckles=knuckle_x + 0.004)

    for side in ('L', 'R'):
        sx = 1.0 if side == 'L' else -1.0
        # Snug leather gauntlet cuff around actual wrist
        b = Builder('forearm.' + side).spec(CANVAS, 0.85, (0.70, 0.58, 0.38), 1.0, 0.04)
        cuff_c = Vector((sx * 0.712, ARM_AXIS_Y, ARM_AXIS_Z))
        b.ring(cuff_c, Vector((-sx, 0, 0)), 0.032, 0.046, 0.005, segs=20, flare=0.005, ry_scale=0.84)
        hard('gloves_work_cuff_' + side, b, arm, body)

        # Contoured hard carbon-knuckle plate on dorsal hand
        b = Builder('hand.' + side).spec(PLASTIC, 0.35, (0.14, 0.14, 0.15), 1.0, 0.04)
        b.box(Vector((sx * 0.772, 0.002, 1.469)), (0.026, 0.066, 0.009), bevel=0.003)
        hard('gloves_tactical_knuckle_' + side, b, arm, body)

    # ---------------- 8. elbow and knee pads (BVHTree-conformed to actual sleeve/trouser surfaces, closed manifold shells)
    bm_arm_in = clean_upper_shell(body, include_waistband=False, include_cuffs=True, include_collar=False, extend_wrist=True)
    fit_bmesh(bm_arm_in, arm, body, limb=0.80, torso=0.91, offset=0.002, torso_y=torso_y, wrist_match=True)
    # Find the exact geometric center of the elbow mesh slice at x = 0.44..0.50
    eb_vs = [v.co for v in bm_arm_in.verts if 0.44 < v.co.x < 0.50]
    elbow_cy = (min(p.y for p in eb_vs) + max(p.y for p in eb_vs)) * 0.5 if eb_vs else ARM_AXIS_Y
    elbow_cz = (min(p.z for p in eb_vs) + max(p.z for p in eb_vs)) * 0.5 if eb_vs else ARM_AXIS_Z
    dl_arm = bm_arm_in.verts.layers.deform.active
    kd_arm = kdtree.KDTree(len(bm_arm_in.verts))
    arm_weights = []
    for idx, v in enumerate(bm_arm_in.verts):
        kd_arm.insert(v.co, idx)
        arm_weights.append(dict(v[dl_arm].items()))
    kd_arm.balance()
    bvh_elbow_in = BVHTree.FromBMesh(bm_arm_in)
    bm_arm_in.free()

    bm_arm_out = clean_upper_shell(body, include_waistband=False, include_cuffs=True, include_collar=False, extend_wrist=True)
    fit_bmesh(bm_arm_out, arm, body, limb=1.02, torso=1.02, offset=0.006, torso_y=torso_y, wrist_match=True)
    bvh_elbow_out = BVHTree.FromBMesh(bm_arm_out)
    bm_arm_out.free()

    bm_leg_out = extract(body, {'Jeans dark'}, weld=True)
    fit_bmesh(bm_leg_out, arm, body, limb=1.03, legs=1.03, torso=0.98, offset=0.004, torso_y=torso_y)
    kn_vs = [v.co for v in bm_leg_out.verts if 0.49 < v.co.z < 0.54 and v.co.x > 0.02]
    knee_cx = (min(p.x for p in kn_vs) + max(p.x for p in kn_vs)) * 0.5 if kn_vs else 0.100
    knee_cy = (min(p.y for p in kn_vs) + max(p.y for p in kn_vs)) * 0.5 if kn_vs else 0.010
    dl_leg = bm_leg_out.verts.layers.deform.active
    kd_leg = kdtree.KDTree(len(bm_leg_out.verts))
    leg_weights = []
    for idx, v in enumerate(bm_leg_out.verts):
        kd_leg.insert(v.co, idx)
        leg_weights.append(dict(v[dl_leg].items()))
    kd_leg.balance()
    bvh_knee_out = BVHTree.FromBMesh(bm_leg_out)
    bm_leg_out.free()

    def sample_limb_r(bvh, center, axis_v, dir_v, fallback_r):
        """Cast outward from the limb centerline so rays hit ONLY this limb's surface and never cross to the other leg."""
        d_u = dir_v.normalized()
        perp = axis_v.cross(d_u).normalized()
        best = fallback_r * 0.72
        max_r = fallback_r * 1.26
        for dz in (-0.010, 0.0, 0.010):
            c_pt = center + axis_v * dz
            for dp in (-0.12, 0.0, 0.12):
                ray_d = (d_u + perp * dp).normalized()
                hit, _, _, _ = bvh.ray_cast(c_pt, ray_d, max_r)
                if hit is not None:
                    r_val = (hit - c_pt).length
                    if r_val > best:
                        best = r_val
        return min(best, max_r)

    def stitch_open_shell(b, vs_o, vs_i):
        """Close all 4 perimeter boundary edges between outer and inner open quad strips."""
        rings_n = len(vs_o)
        segs_n = len(vs_o[0])
        for j in range(segs_n - 1):
            b._face([vs_o[0][j], vs_o[0][j + 1], vs_i[0][j + 1], vs_i[0][j]])
            b._face([vs_o[-1][j + 1], vs_o[-1][j], vs_i[-1][j], vs_i[-1][j + 1]])
        for i in range(rings_n - 1):
            b._face([vs_o[i + 1][0], vs_o[i][0], vs_i[i][0], vs_i[i + 1][0]])
            b._face([vs_o[i][-1], vs_o[i + 1][-1], vs_i[i + 1][-1], vs_i[i][-1]])

    def build_conformed_strap(b, bvh, center, axis_v, u_vec, v_vec, width, thick, fallback_r, segs=24):
        outer, inner = [], []
        for dz in (-width * 0.5, width * 0.5):
            ro, ri = [], []
            c_slice = center + axis_v * dz
            for j in range(segs):
                th = 2.0 * math.pi * j / segs
                dir_u = (u_vec * math.cos(th) + v_vec * math.sin(th)).normalized()
                r_base = sample_limb_r(bvh, c_slice, axis_v, dir_u, fallback_r) + 0.0015
                ro.append(c_slice + dir_u * (r_base + thick))
                ri.append(c_slice + dir_u * r_base)
            outer.append(ro)
            inner.append(ri)
        vs_o = b.quad_strip(outer, closed=True)
        vs_i = b.quad_strip(inner, closed=True)
        for r in vs_i:
            for vt in r:
                for f in vt.link_faces:
                    f.normal_flip()
        for j in range(segs):
            k = (j + 1) % segs
            b._face([vs_o[0][j], vs_o[0][k], vs_i[0][k], vs_i[0][j]])
            b._face([vs_o[-1][k], vs_o[-1][j], vs_i[-1][j], vs_i[-1][k]])

    def pad(prefix, kind, is_elbow, fallback_r, length, layer, rough, col, strap_col, suffix=''):
        bvh = (bvh_elbow_out if suffix == '_over' else bvh_elbow_in) if is_elbow else bvh_knee_out
        for side in ('L', 'R'):
            sx = 1.0 if side == 'L' else -1.0
            if is_elbow:
                c = Vector((sx * 0.470, elbow_cy, elbow_cz))
                a = Vector((1.0, 0.0, 0.0))
                u = Vector((0.0, 0.96, -0.28)).normalized()
                v = a.cross(u).normalized()
                bweights = [('upper_arm.' + side, 0.5), ('forearm.' + side, 0.5)]
                bone_primary = 'forearm.' + side
            else:
                c = Vector((sx * knee_cx, knee_cy, 0.515))
                a = Vector((0.0, 0.0, 1.0))
                u = Vector((0.0, -1.0, 0.0))
                v = a.cross(u).normalized()
                bweights = [('thigh.' + side, 0.5), ('shin.' + side, 0.5)]
                bone_primary = 'shin.' + side

            b = Builder(bone_primary)
            if kind == 'knit':
                b.spec(layer, rough, col, 1.0, 0.04)
                segs, rings = 24, 8
                outer, inner = [], []
                for i in range(rings + 1):
                    zt = (i / rings - 0.5) * length
                    c_sl = c + a * zt
                    ro, ri = [], []
                    for j in range(segs):
                        th = 2.0 * math.pi * j / segs
                        dir_u = (u * math.cos(th) + v * math.sin(th)).normalized()
                        r_b = sample_limb_r(bvh, c_sl, a, dir_u, fallback_r) + 0.0015
                        ro.append(c_sl + dir_u * (r_b + 0.0055))
                        ri.append(c_sl + dir_u * r_b)
                    outer.append(ro)
                    inner.append(ri)
                vs_o = b.quad_strip(outer, closed=True)
                vs_i = b.quad_strip(inner, closed=True)
                for r in vs_i:
                    for vt in r:
                        for f in vt.link_faces:
                            f.normal_flip()
                for j in range(segs):
                    k = (j + 1) % segs
                    b._face([vs_o[0][j], vs_o[0][k], vs_i[0][k], vs_i[0][j]])
                    b._face([vs_o[-1][k], vs_o[-1][j], vs_i[-1][j], vs_i[-1][k]])
            else:
                # Conformed elastic straps wrapping 100% outside the sleeve/pant circumference above & below the joint
                b.spec(NYLON, 0.85, strap_col, 0.0, 0.04)
                for dz in (-length * 0.34, length * 0.34):
                    build_conformed_strap(b, bvh, c + a * dz, a, u, v, 0.016, 0.0035, fallback_r, segs=24)
                # Molded foam/neoprene backing cushion (closed watertight perimeter)
                b.spec(layer, rough, col, 1.0, 0.05)
                segs, rings = 18, 10
                span = math.pi * (0.82 if kind == 'foam' else 0.72)
                thick = 0.009 if kind != 'foam' else 0.012
                outer, inner = [], []
                for i in range(rings + 1):
                    zt = (i / rings - 0.5) * length
                    c_sl = c + a * zt
                    arch = 1.0 - 0.32 * (2 * i / rings - 1) ** 2
                    ro, ri = [], []
                    for j in range(segs + 1):
                        th = (j / segs - 0.5) * span
                        dir_u = (u * math.cos(th) + v * math.sin(th)).normalized()
                        r_b = sample_limb_r(bvh, c_sl, a, dir_u, fallback_r) + 0.0015
                        ro.append(c_sl + dir_u * (r_b + thick * arch))
                        ri.append(c_sl + dir_u * r_b)
                    outer.append(ro)
                    inner.append(ri)
                vs_o = b.quad_strip(outer, closed=False)
                vs_i = b.quad_strip(inner, closed=False)
                for r in vs_i:
                    for vt in r:
                        for f in vt.link_faces:
                            f.normal_flip()
                stitch_open_shell(b, vs_o, vs_i)
                if kind in ('hard', 'skate'):
                    # Contoured hard polymer impact cap over the center of the pad (closed watertight perimeter)
                    cap_col = col if kind == 'skate' else (0.16, 0.17, 0.18)
                    cap_mask = 1.0 if kind == 'skate' else 0.4
                    b.spec(PLASTIC, 0.32, cap_col, cap_mask, 0.05)
                    cap_o, cap_i = [], []
                    for i in range(rings + 1):
                        zt = (i / rings - 0.5) * (length * 0.72)
                        c_sl = c + a * zt
                        arch = 1.0 - 0.45 * (2 * i / rings - 1) ** 2
                        ro, ri = [], []
                        for j in range(segs + 1):
                            th = (j / segs - 0.5) * (span * 0.75)
                            dir_u = (u * math.cos(th) + v * math.sin(th)).normalized()
                            r_b = sample_limb_r(bvh, c_sl, a, dir_u, fallback_r) + 0.0015
                            ro.append(c_sl + dir_u * (r_b + thick + 0.0055 * arch))
                            ri.append(c_sl + dir_u * (r_b + thick * 0.85))
                        cap_o.append(ro)
                        cap_i.append(ri)
                    vs_co = b.quad_strip(cap_o, closed=False)
                    vs_ci = b.quad_strip(cap_i, closed=False)
                    for r in vs_ci:
                        for vt in r:
                            for f in vt.link_faces:
                                f.normal_flip()
                    stitch_open_shell(b, vs_co, vs_ci)
                    b.spec(METAL, 0.25, (0.75, 0.75, 0.78), 0.0, 0.02)
                    for sx_r in (-1, 1):
                        for sy_r in (-1, 1):
                            th = sx_r * span * 0.24
                            zt = sy_r * length * 0.22
                            c_sl = c + a * zt
                            dir_u = (u * math.cos(th) + v * math.sin(th)).normalized()
                            r_b = sample_limb_r(bvh, c_sl, a, dir_u, fallback_r) + 0.0015
                            b.box(c_sl + dir_u * (r_b + thick + 0.0045), (0.006, 0.006, 0.006))
            # Transfer exact per-vertex bone weights from the underlying sleeve/trousers so pads deform identically when bending!
            dl_pad = b.bm.verts.layers.deform.verify()
            kd_ref = kd_arm if is_elbow else kd_leg
            w_ref = arm_weights if is_elbow else leg_weights
            for vt in b.bm.verts:
                _, r_idx, _ = kd_ref.find(vt.co)
                for gi, w in w_ref[r_idx].items():
                    vt[dl_pad][gi] = w
            bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
            fs_pad = b.bm.faces.layers.int.get('spec')
            face_spec_pad = [f[fs_pad] for f in b.bm.faces]
            make_object('%s_%s_%s%s' % (prefix, kind, side, suffix), b.bm, arm, body, b.specs, face_spec=face_spec_pad, keep_uv=False)
            b.bm.free()

    for r, suf in ((0.045, ''), (0.056, '_over')):
        pad('elbow', 'hard', True, r, 0.11, NYLON, 0.75, (0.22, 0.24, 0.22), (0.12, 0.12, 0.12), suf)
        pad('elbow', 'foam', True, r, 0.12, RUBBER, 0.65, (0.20, 0.22, 0.25), (0.12, 0.12, 0.12), suf)
        pad('elbow', 'skate', True, r, 0.11, NYLON, 0.75, (0.85, 0.22, 0.18), (0.12, 0.12, 0.12), suf)
        pad('elbow', 'knit', True, r, 0.13, KNIT, 0.90, (0.35, 0.35, 0.38), (0.2, 0.2, 0.2), suf)

    kr = 0.068
    pad('knee', 'hard', False, kr, 0.14, NYLON, 0.75, (0.22, 0.24, 0.22), (0.12, 0.12, 0.12))
    pad('knee', 'foam', False, kr, 0.15, RUBBER, 0.65, (0.20, 0.22, 0.25), (0.12, 0.12, 0.12))
    pad('knee', 'skate', False, kr, 0.14, NYLON, 0.75, (0.85, 0.22, 0.18), (0.12, 0.12, 0.12))
    pad('knee', 'knit', False, kr, 0.16, KNIT, 0.90, (0.35, 0.35, 0.38), (0.2, 0.2, 0.2))

    # ---------------- 9. hair (BVHTree skull-conformed with smooth feather-tapered hairline, zero swimming-cap rim)
    def skull_point(dir_unit, extra):
        d_u = dir_unit.normalized()
        el_r = 1.0 / math.sqrt(
            (d_u.x / cran_r.x) ** 2 +
            (d_u.y / cran_r.y) ** 2 +
            (d_u.z / cran_r.z) ** 2
        )
        r_hit = head_r_at(cran_c, d_u, fallback=el_r)
        base_r = max(el_r * 0.98, min(el_r * 1.08, r_hit)) + 0.0024
        return cran_c + d_u * (base_r + extra)

    def build_hair_dome(b, extra_thick, front_phi=0.35, temple_phi=0.44, ear_phi=0.40, back_phi=0.58, segs=32, rings=14):
        outer, inner = [], []
        for i in range(rings + 1):
            t = i / rings
            ro, ri = [], []
            for j in range(segs):
                th = 2.0 * math.pi * j / segs
                cs = math.cos(th)
                sn = abs(math.sin(th))
                front_w = max(0.0, cs) ** 1.6
                back_w = max(0.0, -cs) ** 1.3
                temple_w = max(0.0, math.sin(2.0 * abs(th))) if cs > 0 else 0.0
                phi_max = math.pi * (
                    front_phi * front_w +
                    ear_phi * (sn ** 1.8) * (1.0 - 0.4 * back_w) +
                    back_phi * back_w +
                    0.05 * temple_w
                )
                ph = max(0.002, t * phi_max)
                dir_u = Vector((math.sin(ph) * math.sin(th), -math.sin(ph) * math.cos(th), math.cos(ph))).normalized()
                # Smoothly feather hair thickness down to 1.5 mm at the hairline edge (t=1.0) so it never flares like a cap
                feather = math.cos(t * math.pi * 0.5) ** 0.65
                crown_lift = 1.0 + 0.25 * max(0.0, dir_u.z)
                taper = max(0.0015, extra_thick * crown_lift * feather)
                ro.append(skull_point(dir_u, taper))
                ri.append(skull_point(dir_u, 0.0002))
            outer.append(ro)
            inner.append(ri)
        vs_o = b.quad_strip(outer, closed=True)
        vs_i = b.quad_strip(inner, closed=True)
        for r in vs_i:
            for vt in r:
                for f in vt.link_faces:
                    f.normal_flip()
        for j in range(segs):
            k = (j + 1) % segs
            b._face([vs_o[-1][k], vs_i[-1][k], vs_i[-1][j], vs_o[-1][j]])

    b = Builder('head').spec(COTTON, 0.88, (0.10, 0.08, 0.06), 1.0, 0.04)
    build_hair_dome(b, extra_thick=0.0075, front_phi=0.36, temple_phi=0.44, ear_phi=0.41, back_phi=0.58)
    hard('hair_short', b, arm, body)

    b = Builder('head').spec(COTTON, 0.94, (0.12, 0.10, 0.08), 1.0, 0.03)
    build_hair_dome(b, extra_thick=0.0042, front_phi=0.35, temple_phi=0.42, ear_phi=0.39, back_phi=0.56)
    hard('hair_buzz', b, arm, body)

    # Mohawk: ultra-close buzzed scalp + upright tapered sagittal fan blade (not a round sausage tube!)
    b = Builder('head').spec(COTTON, 0.94, (0.12, 0.10, 0.08), 1.0, 0.03)
    build_hair_dome(b, extra_thick=0.0032, front_phi=0.34, temple_phi=0.40, ear_phi=0.38, back_phi=0.54)
    b.spec(COTTON, 0.86, (0.10, 0.08, 0.06), 1.0, 0.04)
    fan_rings = []
    for i in range(15):
        u = i / 14.0
        ph = -0.35 + 1.30 * u
        dir_u = Vector((0.0, -math.sin(ph), math.cos(ph))).normalized()
        arch = math.sin(u * math.pi) ** 0.65
        base_pt = skull_point(dir_u, 0.0005)
        top_pt = skull_point(dir_u, 0.006 + 0.032 * arch)
        mid_pt = base_pt.lerp(top_pt, 0.55)
        w_base = 0.013 * (0.65 + 0.35 * arch)
        w_mid = 0.009 * (0.60 + 0.40 * arch)
        w_top = 0.0035
        fan_rings.append([
            base_pt + Vector((-w_base, 0, 0)),
            mid_pt + Vector((-w_mid, 0, 0)),
            top_pt + Vector((-w_top, 0, 0)),
            top_pt + Vector((w_top, 0, 0)),
            mid_pt + Vector((w_mid, 0, 0)),
            base_pt + Vector((w_base, 0, 0)),
        ])
    b.quad_strip(fan_rings, closed=True, cap_start=True, cap_end=True)
    hard('hair_mohawk', b, arm, body)

    b = Builder('head').spec(COTTON, 0.88, (0.10, 0.08, 0.06), 1.0, 0.04)
    build_hair_dome(b, extra_thick=0.0065, front_phi=0.35, temple_phi=0.43, ear_phi=0.41, back_phi=0.56)
    bun_dir = Vector((0.0, 0.88, 0.47)).normalized()
    bun_c = skull_point(bun_dir, 0.022)
    b.ellipsoid(bun_c, Vector((0.030, 0.032, 0.030)), segs=18, rings=10)
    b.spec(RUBBER, 0.7, (0.08, 0.08, 0.08), 0.0, 0.02)
    b.ring(skull_point(bun_dir, 0.006), bun_dir, 0.022, 0.009, 0.004, segs=16)
    hard('hair_bun', b, arm, body)

    # ---------------- 10. headwear (fitted to skull surface so brow line is at z=1.705 above the eyes!)
    # Knit beanie (contoured skull watch cap with integrated folded rib cuff — no cylindrical temple step)
    b = Builder('head').spec(KNIT, 0.94, (0.18, 0.22, 0.32), 1.0, 0.035)
    segs_b, rings_b = 32, 14
    b_out, b_in = [], []
    for i in range(rings_b + 1):
        t = i / rings_b
        ro, ri = [], []
        # Folded rib cuff thickens smoothly over the bottom 32% of the beanie
        cuff_bump = 0.0040 * (1.0 / (1.0 + math.exp(-(t - 0.66) * 28.0)))
        for j in range(segs_b):
            th = 2.0 * math.pi * j / segs_b
            frontness = math.cos(th)
            phi_max = math.pi * (0.50 - 0.04 * max(0.0, frontness) + 0.03 * max(0.0, -frontness))
            ph = max(0.002, t * phi_max)
            dir_u = Vector((math.sin(ph) * math.sin(th), -math.sin(ph) * math.cos(th), math.cos(ph))).normalized()
            slouch = 0.010 * max(0.0, dir_u.z)
            ro.append(skull_point(dir_u, 0.0055 + slouch + cuff_bump))
            ri.append(skull_point(dir_u, 0.0010))
        b_out.append(ro)
        b_in.append(ri)
    vs_bo = b.quad_strip(b_out, closed=True)
    vs_bi = b.quad_strip(b_in, closed=True)
    for r in vs_bi:
        for vt in r:
            for f in vt.link_faces:
                f.normal_flip()
    for j in range(segs_b):
        k = (j + 1) % segs_b
        b._face([vs_bo[-1][k], vs_bi[-1][k], vs_bi[-1][j], vs_bo[-1][j]])
    hard('helmet_beanie', b, arm, body)

    # Ball cap with curved sandwich bill
    b = Builder('head').spec(CANVAS, 0.82, (0.90, 0.88, 0.82), 1.0, 0.05)
    cap_c = cran_c + Vector((0, 0.002, 0.008))
    cap_r = cran_r + Vector((0.006, 0.007, 0.008))
    b.shell(cap_c, cap_r, 0.004, phi0=0.0, phi1=math.pi * 0.49, segs=28, rings=12)
    b.spec(PLASTIC, 0.5, (0.20, 0.20, 0.22), 1.0, 0.02)
    b.ellipsoid(cap_c + Vector((0, 0, cap_r.z + 0.002)), Vector((0.010, 0.010, 0.005)), segs=12, rings=6)
    b.spec(CANVAS, 0.80, (0.88, 0.86, 0.80), 1.0, 0.05)
    visor_rings = []
    for j in range(15):
        u = (j / 14.0 - 0.5) * 2.0
        arch = (1.0 - u * u) * 0.018
        vx = u * 0.076
        vy0 = cap_c.y - cap_r.y * math.sqrt(max(0.15, 1.0 - (u * 0.72) ** 2)) + 0.010
        vy1 = vy0 - 0.068 * (1.0 - 0.22 * u * u)
        vz0 = 1.706 + arch * 0.45
        vz1 = 1.692 + arch
        visor_rings.append([
            Vector((vx, vy0, vz0 + 0.003)),
            Vector((vx, vy1, vz1 + 0.0025)),
            Vector((vx, vy1, vz1 - 0.0025)),
            Vector((vx, vy0, vz0 - 0.003)),
        ])
    b.quad_strip(visor_rings, closed=True, cap_start=True, cap_end=True)
    hard('helmet_cap', b, arm, body)

    # Combat helmet (PASGT / FAST ballistic shell sitting cleanly on the brow at z=1.705, NVG shroud, side rails, cheek-hugging chinstrap)
    b = Builder('head').spec(CAMO, 0.82, (1.0, 1.0, 1.0), 1.0, 0.09)
    hc = cran_c + Vector((0, 0.002, 0.008))
    hr = cran_r + Vector((0.014, 0.015, 0.014))
    segs, rings = 32, 14
    outer, inner = [], []
    for i in range(rings + 1):
        t = i / rings
        ro, ri = [], []
        for j in range(segs):
            th = 2.0 * math.pi * j / segs
            frontness = math.cos(th)
            sideness = abs(math.sin(th))
            phi_max = math.pi * (0.53 - 0.07 * max(0.0, frontness) + 0.04 * sideness - 0.02 * min(0.0, frontness))
            ph = t * phi_max
            flare = 1.0 + 0.06 * (t ** 2) * (0.6 * sideness + 0.4 * max(0.0, -frontness))
            px = math.sin(ph) * math.sin(th)
            py = -math.sin(ph) * math.cos(th)
            pz = math.cos(ph)
            ro.append(Vector((hc.x + hr.x * px * flare, hc.y + hr.y * py * flare, hc.z + hr.z * pz)))
            ri.append(Vector((hc.x + (hr.x - 0.009) * px * flare, hc.y + (hr.y - 0.009) * py * flare, hc.z + (hr.z - 0.009) * pz)))
        outer.append(ro)
        inner.append(ri)
    vs_out = b.quad_strip(outer, closed=True)
    vs_in = b.quad_strip(inner, closed=True)
    for r in vs_in:
        for vt in r:
            for f in vt.link_faces:
                f.normal_flip()
    b.spec(RUBBER, 0.65, (0.14, 0.15, 0.14), 0.0, 0.04)
    for j in range(segs):
        k = (j + 1) % segs
        b._face([vs_out[-1][k], vs_in[-1][k], vs_in[-1][j], vs_out[-1][j]])
    b.spec(PLASTIC, 0.42, (0.16, 0.17, 0.16), 0.0, 0.04)
    b.box(Vector((0.0, hc.y - hr.y * 0.96, 1.742)), (0.044, 0.016, 0.040), Matrix.Rotation(math.radians(-16), 3, 'X'), bevel=0.003)
    b.spec(METAL, 0.30, (0.28, 0.29, 0.28), 0.0, 0.03)
    b.box(Vector((0.0, hc.y - hr.y * 0.99, 1.742)), (0.028, 0.012, 0.026), Matrix.Rotation(math.radians(-16), 3, 'X'))
    b.spec(PLASTIC, 0.45, (0.18, 0.19, 0.18), 0.0, 0.04)
    for sx in (-1, 1):
        rot_r = Matrix.Rotation(sx * math.radians(10), 3, 'Y') @ Matrix.Rotation(math.radians(-8), 3, 'X')
        b.box(Vector((sx * (hr.x + 0.001), hc.y - 0.010, 1.712)), (0.010, 0.088, 0.020), rot_r, bevel=0.002)
    # Surface-conformed Y-chinstrap hugging the actual cheek/jaw surface (no airborne rear rods!)
    b.spec(NYLON, 0.85, (0.16, 0.16, 0.15), 0.0, 0.04)
    chin_pt = Vector((0.0, -0.130, 1.568))
    for sx in (-1, 1):
        strap_pts = []
        for y_t, z_t in ((-0.055, 1.688), (-0.072, 1.648), (-0.088, 1.612), (-0.106, 1.584)):
            c_st = Vector((0.0, y_t, z_t))
            d_st = Vector((sx, -0.35, -0.15)).normalized()
            r_st = head_r_at(c_st, d_st, fallback=0.064) + 0.0025
            strap_pts.append(c_st + d_st * r_st)
        strap_pts.append(chin_pt)
        b.tube(strap_pts, 0.0038, segs=8)
    b.box(chin_pt, (0.034, 0.020, 0.012), bevel=0.003)
    hard('helmet_combat', b, arm, body)

    # Hard hat
    b = Builder('head').spec(PLASTIC, 0.28, (0.95, 0.75, 0.10), 1.0, 0.08)
    hh_c = cran_c + Vector((0, 0.002, 0.010))
    hh_r = cran_r + Vector((0.010, 0.012, 0.014))
    b.shell(hh_c, hh_r, 0.005, phi0=0.0, phi1=math.pi * 0.48, segs=28, rings=12)
    b.ring(Vector((hh_c.x, hh_c.y, 1.710)), Vector((0, 0, 1)), hh_r.x * 0.97, 0.005, 0.009, segs=28, flare=0.005, ry_scale=hh_r.y / hh_r.x)
    ridge = [Vector((0.0, hh_c.y - (hh_r.y + 0.003) * math.sin(ph), hh_c.z + (hh_r.z + 0.005) * math.cos(ph)))
             for ph in [i * 0.14 - 0.56 for i in range(9)]]
    b.tube(ridge, (0.014, 0.006), segs=10)
    b.box(Vector((0.0, hh_c.y - hh_r.y - 0.018, 1.708)), (0.115, 0.044, 0.006), Matrix.Rotation(math.radians(8), 3, 'X'), bevel=0.002)
    hard('helmet_hardhat', b, arm, body)

    # Full-face motorcycle helmet (extends down to z=1.545 to fully enclose chin & jaw, visor strictly outside liner)
    b = Builder('head').spec(PLASTIC, 0.18, (0.75, 0.12, 0.12), 1.0, 0.10)
    mc = Vector((0.0, -0.042, 1.676))
    mr = Vector((0.108, 0.136, 0.136))
    b.shell(mc, mr, 0.014, phi0=0.0, phi1=math.pi * 0.82, segs=32, rings=16)
    b.spec(METAL, 0.08, (0.05, 0.06, 0.08), 0.0, 0.08)
    b.ellipsoid(mc + Vector((0, -0.003, 0.003)), mr + Vector((0.003, 0.004, 0.003)),
                phi0=math.pi * 0.34, phi1=math.pi * 0.55, theta0=-math.pi * 0.34, theta1=math.pi * 0.34, segs=24, rings=10, closed=False)
    b.spec(RUBBER, 0.65, (0.10, 0.10, 0.11), 0.0, 0.04)
    b.box(Vector((0.0, mc.y - mr.y + 0.014, 1.592)), (0.044, 0.014, 0.020), bevel=0.003)
    hard('helmet_moto', b, arm, body)

    # ---------------- 11. face gear (BVHTree-conformed to exact facial & cranium contours, zero floating straps!)
    def build_head_strap(b, z_level, width, thick=0.003, tilt_y=0.0, segs=28):
        """Build an elastic strap that hugs the exact 3D contour of body_head around the skull/nape."""
        outer, inner = [], []
        c0 = Vector((0.0, -0.036, z_level))
        for dz in (-width * 0.5, width * 0.5):
            ro, ri = [], []
            for j in range(segs):
                th = 2.0 * math.pi * j / segs
                cs, sn = math.cos(th), math.sin(th)
                c_pt = Vector((c0.x, c0.y, z_level + dz - cs * tilt_y))
                dir_u = Vector((sn, -cs, 0.0)).normalized()
                r_h = head_r_at(c_pt, dir_u, fallback=0.078) + 0.0012
                ro.append(c_pt + dir_u * (r_h + thick))
                ri.append(c_pt + dir_u * r_h)
            outer.append(ro)
            inner.append(ri)
        vs_o = b.quad_strip(outer, closed=True)
        vs_i = b.quad_strip(inner, closed=True)
        for r in vs_i:
            for vt in r:
                for f in vt.link_faces:
                    f.normal_flip()
        for j in range(segs):
            k = (j + 1) % segs
            b._face([vs_o[0][j], vs_o[0][k], vs_i[0][k], vs_i[0][j]])
            b._face([vs_o[-1][k], vs_o[-1][j], vs_i[-1][j], vs_i[-1][k]])

    # Bandana (conformed to nose bridge, cheeks, jaw, and nape with solid cloth thickness)
    b = Builder('head').spec(COTTON, 0.88, (0.75, 0.18, 0.16), 1.0, 0.06)
    segs_ban = 28
    ban_out, ban_in = [], []
    for iz, z_base in enumerate((1.652, 1.616, 1.576, 1.536)):
        ro, ri = [], []
        for j in range(segs_ban):
            th = 2.0 * math.pi * j / segs_ban
            cs, sn = math.cos(th), math.sin(th)
            zz = z_base - 0.022 * max(0.0, -cs)
            if iz == 3 and cs > 0.15:
                zz -= 0.042 * ((cs - 0.15) / 0.85) ** 1.3
            c_pt = Vector((0.0, -0.036, max(1.525, zz)))
            dir_u = Vector((sn, -cs, 0.0)).normalized()
            r_h = head_r_at(c_pt, dir_u, fallback=0.072)
            # Drape slightly looser below the chin on the bottom two rings while staying tight over the nose/cheeks/nape
            drape = 0.0022 + (0.006 * max(0.0, cs) * (iz / 3.0))
            pt_o = Vector((c_pt.x + dir_u.x * (r_h + drape + 0.003), c_pt.y + dir_u.y * (r_h + drape + 0.003), zz))
            pt_i = Vector((c_pt.x + dir_u.x * (r_h + drape), c_pt.y + dir_u.y * (r_h + drape), zz))
            ro.append(pt_o)
            ri.append(pt_i)
        ban_out.append(ro)
        ban_in.append(ri)
    vs_bo = b.quad_strip(ban_out, closed=True)
    vs_bi = b.quad_strip(ban_in, closed=True)
    for r in vs_bi:
        for vt in r:
            for f in vt.link_faces:
                f.normal_flip()
    for j in range(segs_ban):
        k = (j + 1) % segs_ban
        b._face([vs_bo[0][j], vs_bo[0][k], vs_bi[0][k], vs_bi[0][j]])
        b._face([vs_bo[-1][k], vs_bo[-1][j], vs_bi[-1][j], vs_bo[-1][k]])
    # Back knot resting flush against the nape
    nape_r = head_r_at(Vector((0.0, -0.036, 1.605)), Vector((0.0, 1.0, 0.0)), fallback=0.075)
    b.ellipsoid(Vector((0.0, -0.036 + nape_r + 0.010, 1.605)), Vector((0.016, 0.014, 0.014)), segs=12, rings=6)
    hard('face_bandana', b, arm, body)

    # Tactical ballistic goggles (flush cranium strap + contoured goggle frame)
    b = Builder('head')
    b.spec(RUBBER, 0.65, (0.14, 0.14, 0.15), 0.0, 0.04)
    build_head_strap(b, 1.686, 0.020, thick=0.0035, segs=28)
    b.spec(PLASTIC, 0.42, (0.20, 0.22, 0.20), 1.0, 0.04)
    for sx in (-1, 1):
        rot_g = Matrix.Rotation(sx * math.radians(-14), 3, 'Z')
        b.box(Vector((sx * 0.034, -0.136, 1.686)), (0.068, 0.028, 0.044), rot_g, bevel=0.005)
    b.box(Vector((0.0, -0.144, 1.690)), (0.024, 0.022, 0.018), bevel=0.003)
    b.spec(METAL, 0.10, (0.06, 0.08, 0.10), 0.0, 0.04)
    for sx in (-1, 1):
        rot_g = Matrix.Rotation(sx * math.radians(-14), 3, 'Z')
        b.box(Vector((sx * 0.034, -0.148, 1.686)), (0.056, 0.008, 0.032), rot_g, bevel=0.002)
    hard('face_goggles', b, arm, body)

    # Half-face twin-cartridge respirator (flush nape strap + contoured facepiece)
    b = Builder('head').spec(RUBBER, 0.55, (0.16, 0.17, 0.16), 1.0, 0.04)
    b.ellipsoid(Vector((0.0, -0.126, 1.608)), Vector((0.052, 0.044, 0.048)),
                phi0=math.pi * 0.18, phi1=math.pi * 0.85, theta0=-math.pi * 0.48, theta1=math.pi * 0.48, segs=20, rings=10, closed=False)
    b.spec(PLASTIC, 0.38, (0.12, 0.12, 0.13), 0.0, 0.03)
    b.box(Vector((0.0, -0.166, 1.602)), (0.032, 0.018, 0.032), bevel=0.004)
    for sx in (-1, 1):
        p0 = Vector((sx * 0.036, -0.144, 1.598))
        p1 = Vector((sx * 0.066, -0.154, 1.584))
        p2 = Vector((sx * 0.072, -0.156, 1.581))
        b.spec(PLASTIC, 0.40, (0.20, 0.22, 0.20), 1.0, 0.04)
        b.tube([p0, p1], 0.026, segs=18)
        b.spec(COTTON, 0.85, (0.88, 0.86, 0.82), 0.0, 0.04)
        b.tube([p1, p2], 0.024, segs=18)
    b.spec(NYLON, 0.85, (0.14, 0.14, 0.14), 0.0, 0.04)
    build_head_strap(b, 1.622, 0.014, thick=0.003, tilt_y=-0.012, segs=28)
    hard('face_respirator', b, arm, body)

    # Wrap-around sunglasses (temple arms conformed directly to actual temple surface)
    b = Builder('head').spec(PLASTIC, 0.25, (0.08, 0.08, 0.09), 1.0, 0.03)
    b.box(Vector((0.0, -0.146, 1.692)), (0.022, 0.008, 0.006))
    for sx in (-1, 1):
        rot_s = Matrix.Rotation(sx * math.radians(-12), 3, 'Z')
        b.spec(PLASTIC, 0.25, (0.08, 0.08, 0.09), 1.0, 0.03)
        b.box(Vector((sx * 0.034, -0.140, 1.686)), (0.052, 0.008, 0.030), rot_s, bevel=0.003)
        b.spec(METAL, 0.06, (0.03, 0.04, 0.05), 0.0, 0.03)
        b.box(Vector((sx * 0.034, -0.143, 1.686)), (0.044, 0.006, 0.024), rot_s, bevel=0.002)
        b.spec(PLASTIC, 0.25, (0.08, 0.08, 0.09), 1.0, 0.03)
        arm_pts = [Vector((sx * 0.058, -0.132, 1.689))]
        for y_t, z_t in ((-0.105, 1.690), (-0.075, 1.690), (-0.045, 1.688), (-0.020, 1.682)):
            c_t = Vector((0.0, y_t, z_t))
            r_t = head_r_at(c_t, Vector((sx, 0, 0)), fallback=0.072) + 0.0018
            arm_pts.append(Vector((sx * r_t, y_t, z_t)))
        b.tube(arm_pts, 0.003, segs=8)
    hard('face_sunglasses', b, arm, body)

    # ---------------- 12. backpacks (BVHTree-conformed straps that hug the shoulders, chest & ribcage with zero floating!)
    bm_torso_bvh = clean_upper_shell(body, include_waistband=True, include_cuffs=False, include_collar=False, extend_wrist=False)
    fit_bmesh(bm_torso_bvh, arm, body, limb=1.01, torso=1.01, offset=0.005, torso_y=torso_y, waist_taper=0.0)
    # Remove arms (abs(x) > 0.155) from bvh_torso so shoulder strap rays NEVER hit T-pose arms!
    bmesh.ops.delete(bm_torso_bvh, geom=[v for v in bm_torso_bvh.verts if abs(v.co.x) > 0.155], context='VERTS')
    bvh_torso = BVHTree.FromBMesh(bm_torso_bvh)
    bm_torso_bvh.free()

    back_y = 0.115

    def torso_surface_point(wx, wy, wz, clearance=0.0045):
        """Raycast purely in the sagittal YZ slice at fixed x=wx so straps hug the shoulder/chest and NEVER drift in X."""
        c_yz = Vector((wx, torso_y, 1.30))
        dir_yz = Vector((0.0, wy - torso_y, wz - 1.30)).normalized()
        orig = c_yz + dir_yz * 0.28
        hit, _, _, _ = bvh_torso.ray_cast(orig, -dir_yz, 0.28)
        if hit is not None:
            return Vector((wx, hit.y + dir_yz.y * clearance, hit.z + dir_yz.z * clearance))
        return Vector((wx, wy, wz))

    def smooth_strap_curve(pts, iters=3):
        out = [p.copy() for p in pts]
        for _ in range(iters):
            nxt = [out[0]]
            for i in range(1, len(out) - 1):
                nxt.append(out[i - 1] * 0.25 + out[i] * 0.50 + out[i + 1] * 0.25)
            nxt.append(out[-1])
            out = nxt
        return out

    def clamp_strap_outside_torso(pts, min_clear=0.004):
        for k in range(1, len(pts) - 1):
            p = pts[k]
            c_yz = Vector((p.x, torso_y, 1.30))
            dir_yz = Vector((0.0, p.y - torso_y, p.z - 1.30))
            if dir_yz.length < 1e-6:
                continue
            d_u = dir_yz.normalized()
            hit, _, _, _ = bvh_torso.ray_cast(c_yz + d_u * 0.28, -d_u, 0.28)
            if hit is not None:
                cur_r = dir_yz.length
                hit_r = Vector((0.0, hit.y - torso_y, hit.z - 1.30)).length
                if cur_r < hit_r + min_clear:
                    pts[k] = Vector((p.x, hit.y + d_u.y * min_clear, hit.z + d_u.z * min_clear))

    def shoulder_straps(b, col):
        b.spec(NYLON, 0.78, col, 0.0, 0.04)
        for sx in (-1, 1):
            # Sample 13 points in the sagittal plane around the shoulder/pectoral/underarm on the actual torso surface
            waypoints = [
                (sx * 0.076,  0.11, 1.43),
                (sx * 0.088,  0.09, 1.48),
                (sx * 0.096,  0.04, 1.51),
                (sx * 0.100, -0.02, 1.51),
                (sx * 0.104, -0.08, 1.48),
                (sx * 0.108, -0.13, 1.43),
                (sx * 0.112, -0.15, 1.38),
                (sx * 0.115, -0.15, 1.33),
                (sx * 0.118, -0.14, 1.28),
                (sx * 0.120, -0.11, 1.23),
                (sx * 0.122, -0.05, 1.19),
                (sx * 0.118,  0.01, 1.17),
                (sx * 0.105,  0.07, 1.16),
            ]
            raw = [Vector((sx * 0.072, back_y, 1.43))]
            for wx, wy, wz in waypoints:
                raw.append(torso_surface_point(wx, wy, wz, clearance=0.0045))
            raw.append(Vector((sx * 0.092, back_y, 1.16)))
            pts = smooth_strap_curve(raw, iters=2)
            clamp_strap_outside_torso(pts, min_clear=0.004)
            b.tube(pts, (0.016, 0.0055), segs=10, cap=False)

    # School backpack
    b = Builder('chest').spec(NYLON, 0.65, (0.18, 0.28, 0.52), 1.0, 0.07)
    b.box(Vector((0, back_y + 0.068, 1.29)), (0.26, 0.135, 0.35), bevel=0.012)
    b.box(Vector((0, back_y + 0.142, 1.22)), (0.21, 0.050, 0.17), bevel=0.008)
    b.spec(METAL, 0.30, (0.75, 0.75, 0.78), 0.0, 0.02)
    b.box(Vector((0, back_y + 0.070, 1.445)), (0.22, 0.115, 0.008))
    shoulder_straps(b, (0.12, 0.12, 0.14))
    hard('pack_school', b, arm, body)

    # Tactical assault pack with MOLLE webbing and sleeping mat roll
    b = Builder('chest').spec(CAMO, 0.85, (1.0, 1.0, 1.0), 1.0, 0.08)
    b.box(Vector((0, back_y + 0.082, 1.30)), (0.29, 0.165, 0.41), bevel=0.012)
    b.box(Vector((0, back_y + 0.175, 1.37)), (0.23, 0.055, 0.14), bevel=0.008)
    b.box(Vector((0, back_y + 0.175, 1.20)), (0.23, 0.055, 0.17), bevel=0.008)
    for sx in (-1, 1):
        b.box(Vector((sx * 0.162, back_y + 0.080, 1.26)), (0.048, 0.105, 0.21), bevel=0.006)
    b.spec(NYLON, 0.80, (0.22, 0.24, 0.18), 0.0, 0.04)
    b.tube([Vector((-0.14, back_y + 0.08, 1.525)), Vector((0.14, back_y + 0.08, 1.525))], 0.042, segs=16)
    for z in (1.16, 1.22, 1.34, 1.40):
        b.box(Vector((0, back_y + 0.205, z)), (0.21, 0.008, 0.016))
    shoulder_straps(b, (0.20, 0.22, 0.18))
    # Sternum strap across chest conformed to torso surface at z=1.36
    sternum_pts = [torso_surface_point(-0.112 + 0.224 * k / 8.0, -0.15, 1.36, clearance=0.005) for k in range(9)]
    b.tube(sternum_pts, (0.010, 0.004), segs=8)
    hard('pack_tactical', b, arm, body)

    # Rice sack (sako)
    b = Builder('chest').spec(SACK, 0.90, (0.95, 0.92, 0.85), 1.0, 0.09)
    b.ellipsoid(Vector((0, back_y + 0.095, 1.27)), Vector((0.155, 0.115, 0.21)), segs=22, rings=12)
    b.ring(Vector((0, back_y + 0.075, 1.475)), Vector((0, 0, 1)), 0.042, 0.045, 0.018, segs=16, flare=0.028)
    shoulder_straps(b, (0.55, 0.45, 0.30))
    hard('pack_sako', b, arm, body)

    # Sling bag (cross-body strap conformed to chest and flank surface)
    b = Builder('chest').spec(CANVAS, 0.82, (0.28, 0.24, 0.20), 1.0, 0.06)
    rot_sl = Matrix.Rotation(math.radians(24), 3, 'Y')
    b.box(Vector((-0.03, back_y + 0.065, 1.27)), (0.17, 0.105, 0.29), rot_sl, bevel=0.010)
    b.spec(NYLON, 0.78, (0.14, 0.14, 0.14), 0.0, 0.04)
    sling_wps = [
        (0.082,  0.10, 1.46),
        (0.094,  0.04, 1.51),
        (0.098, -0.03, 1.51),
        (0.088, -0.10, 1.46),
        (0.055, -0.15, 1.40),
        (0.005, -0.16, 1.34),
        (-0.045, -0.15, 1.29),
        (-0.090, -0.12, 1.24),
        (-0.118, -0.06, 1.19),
        (-0.118,  0.01, 1.17),
        (-0.105,  0.07, 1.16),
    ]
    raw_sl = [Vector((0.060, back_y + 0.01, 1.42))]
    for wx, wy, wz in sling_wps:
        raw_sl.append(torso_surface_point(wx, wy, wz, clearance=0.0045))
    raw_sl.append(Vector((-0.085, back_y + 0.01, 1.16)))
    pts_sl = smooth_strap_curve(raw_sl, iters=2)
    clamp_strap_outside_torso(pts_sl, min_clear=0.004)
    b.tube(pts_sl, (0.018, 0.0055), segs=10, cap=False)
    hard('pack_sling', b, arm, body)

    # ---------------- export
    bpy.data.objects.remove(body, do_unlink=True)
    bpy.ops.object.select_all(action='SELECT')
    out_glb = os.path.join(OUT_DIR, 'gear.glb')
    bpy.ops.export_scene.gltf(
        filepath=out_glb,
        export_format='GLB',
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_all_influences=False,
        export_texcoords=True,
        export_normals=True,
        export_attributes=True,
        export_materials='EXPORT',
        export_animations=False,
    )
    if img and img.size[0] > 0:
        try:
            img.filepath_raw = os.path.join(OUT_DIR, 'gear_generic_body.jpg')
            img.file_format = 'JPEG'
            img.save()
        except Exception:
            pass
    total = sum(v['tris'] for v in meta.values())
    with open(os.path.join(CHECK_DIR, 'meta.json'), 'w') as f:
        json.dump({'pieces': meta, 'total_tris': total, 'skin_color': skin_col}, f, indent=2)
    print('[gear] exported %d pieces, %d tris total -> %s' % (len(meta), total, out_glb))


if __name__ == '__main__':
    main()
