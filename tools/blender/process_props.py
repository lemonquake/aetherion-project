"""Make game-ready copies of the Poly Haven furniture, clutter and plant models.

    blender -b --factory-startup -P tools/blender/process_props.py [-- id ... | --list]

Processes every Poly Haven id named in ModelLib.PROPS (game/src/world/model_lib.gd) and Dresser.ITEM_MODELS, reading
game/assets/thirdparty/polyhaven/models/<id>/<id>_<res>.gltf and writing game/assets/models/polyhaven/<id>.gltf (+ .bin),
sources/<id>.json (credits and modifications, read by tools/fetch_assets.py --manifest) and a check render in
work/props/<id>.png.

Instanced props cost one draw call per material, per MultiMesh cell and per render pass, and a MultiMesh draws every
instance in its cell at one LOD, so each model is:
- cut down to one variant where Poly Haven ships several side by side (a row of wine bottles, clean and dirty boots),
  and re-centred on it; mis-scaled sources are fixed (steel_frame_shelves_01 is authored 10x too large),
- decimated to a triangle budget by size (1k under 30 cm up to 4k for large furniture; the game targets phones too),
- thinned if it is foliage: a tree's leaves are modelled one by one (no alpha), so each becomes the two-triangle
  rhombus inside its outline, whole leaves and twigs are dropped at random and the survivors enlarged so the canopy
  keeps its coverage (about 12k triangles a tree); plants drop whole blades,
- given one opaque material: several materials are packed into one atlas (base colour, normal, occlusion /
  roughness / metallic) with the UVs moved into their cells. The 1k textures carry no alpha, so blend / mask /
  transmission modes are dropped (a blended material would be drawn in the transparent pass, without a depth
  pre-pass),
- kept at 1024 px textures (512 px for props under 50 cm). Unchanged textures stay the Poly Haven files (the .gltf
  points at them); new ones go to game/assets/models/polyhaven/textures/.
"""
import bpy, bmesh, os, sys, json, math, re, zlib, hashlib
import numpy as np
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'game', 'assets', 'thirdparty', 'polyhaven', 'models')
OUT = os.path.join(ROOT, 'game', 'assets', 'models', 'polyhaven')
TEX = os.path.join(OUT, 'textures')
PREV = os.path.join(ROOT, 'work', 'props')

# Item visuals the dresser loads by Poly Haven id (Dresser.ITEM_MODELS).
ITEM_IDS = ['small_plastic_torch', 'medical_tape', 'medical_box', 'ammo_box', 'service_pistol', 'bolt_action_rifle_7_62']

# keep: regexes for the mesh objects of the variant to keep (re-centred on it). scale: fix for a mis-scaled source.
# drop: materials whose faces are removed (hidden inside an opaque part). tint: linear RGB for a material's base
# colour (glass colour comes from volume absorption, lost once it is opaque). tris: budget override.
# tree: per-part budgets (leaves / twigs / trunk, matched by material name). foliage: blade-thinning budget.
MODELS = {
    'wine_bottles_01': dict(keep=[r'_bordeaux$'], drop=[r'_wine_'], tint={'glass_orange': (0.20, 0.08, 0.02)}),
    'rubber_boots': dict(keep=[r'_dirt']),
    'vintage_suitcase': dict(keep=[r'_01_']),
    'metal_trash_can': dict(keep=[r'_rust']),
    'exterior_aircon_unit': dict(keep=[r'_rusted$']),
    'fire_hydrant': dict(keep=[r'_aged$']),
    'compost_bags': dict(keep=[r'_standing$']),
    'old_military_crate': dict(keep=[r'_a$']),
    'mounted_fluorescent_lights': dict(keep=[r'_d$']),
    'service_pistol': dict(keep=[r'_a$']),
    'steel_frame_shelves_01': dict(scale=0.1),
    'grass_medium_01': dict(keep=[r'_large_a_'], foliage=2500),
    'shrub_02': dict(keep=[r'_a$'], foliage=4000),
    'weed_plant_02': dict(keep=[r'_a_'], foliage=2000),
    'tree_small_02': dict(tree=dict(leaves=7000, twigs=2000, trunk=3000)),
    'island_tree_01': dict(tree=dict(leaves=7000, twigs=2000, trunk=3000)),
    'island_tree_02': dict(tree=dict(leaves=7000, twigs=2000, trunk=3000)),
    # Thousands of these hold down roof sheets.
    'old_tyre': dict(tris=900),
    'ship_pinnace': dict(tris=25000),
}


def model_ids():
    text = open(os.path.join(ROOT, 'game', 'src', 'world', 'model_lib.gd'), encoding='utf-8').read()
    ids = re.findall(r'"model": "(\w+)"', text)
    return sorted(set(ids + ITEM_IDS))


def source_path(mid):
    for suf in ('_1k.gltf', '_2k.gltf', '.gltf'):
        p = os.path.join(SRC, mid, mid + suf)
        if os.path.exists(p):
            return p
    return None


# ------------------------------------------------------------------ mesh helpers

def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def select_only(objs, active=None):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


def join_all(name):
    objs = meshes()
    for o in objs:
        world = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = world
    for o in list(bpy.context.scene.objects):
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    select_only(objs)
    bpy.ops.object.make_single_user(object=True, obdata=True)
    for o in objs:
        # Props are rigid; shape keys would also block applying the decimate modifier.
        if o.data.shape_keys:
            o.shape_key_clear()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


def arr_co(me):
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get('co', co)
    return co.reshape(-1, 3)


def bounds(o):
    co = arr_co(o.data)
    return co.min(0), co.max(0)


def topology(me):
    """Per-vertex island labels (connected components) and per-face / per-loop index arrays."""
    nv, ne, nl, nf = len(me.vertices), len(me.edges), len(me.loops), len(me.polygons)
    ev = np.empty(ne * 2, np.int64)
    me.edges.foreach_get('vertices', ev)
    ev = ev.reshape(-1, 2)
    lab = np.arange(nv)
    while True:
        m = np.minimum(lab[ev[:, 0]], lab[ev[:, 1]])
        new = lab.copy()
        np.minimum.at(new, ev[:, 0], m)
        np.minimum.at(new, ev[:, 1], m)
        for _ in range(4):
            new = new[new]
        if np.array_equal(new, lab):
            break
        lab = new
    _, lab = np.unique(lab, return_inverse=True)
    lv = np.empty(nl, np.int64)
    me.loops.foreach_get('vertex_index', lv)
    ls = np.empty(nf, np.int64)
    me.polygons.foreach_get('loop_start', ls)
    return {'vlab': lab, 'n': int(lab.max()) + 1 if nv else 0, 'lv': lv, 'flab': lab[lv[ls]] if nf else np.zeros(0, np.int64)}


def island_centres(co, vlab, n):
    cnt = np.bincount(vlab, minlength=n).astype(np.float64)
    return np.stack([np.bincount(vlab, co[:, k], n) for k in range(3)], 1) / np.maximum(cnt, 1)[:, None]


def delete_faces(o, mask):
    """Removes the faces where mask is True (and anything left loose)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    doomed = [bm.faces[i] for i in np.nonzero(mask)[0]]
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()


def decimate(o, budget):
    t = tris(o)
    if t <= budget:
        return t
    m = o.modifiers.new('dec', 'DECIMATE')
    m.ratio = budget / t
    m.use_collapse_triangulate = True
    select_only([o])
    bpy.ops.object.modifier_apply(modifier=m.name)
    return tris(o)


def thin_islands(o, budget, rng, grow_cap):
    """Drops whole islands (blades, twigs) at random and enlarges the survivors to keep the coverage."""
    me = o.data
    total = tris(o)
    if total <= budget:
        return 1.0, 1.0
    tp = topology(me)
    keep_frac = budget / total
    keep = rng.random(tp['n']) < keep_frac
    grow = min(1.0 / math.sqrt(keep_frac), grow_cap)
    co = arr_co(me)
    cv = island_centres(co, tp['vlab'], tp['n'])[tp['vlab']]
    me.vertices.foreach_set('co', (cv + (co - cv) * grow).astype(np.float32).ravel())
    delete_faces(o, ~keep[tp['flab']])
    return keep_frac, grow


def leaf_diamonds(o, budget, rng, grow_cap=3.0):
    """Every modelled leaf (an island cut to the leaf's outline) becomes the rhombus between its outline's extremes
    along and across its main UV axis: two triangles that stay inside the leaf. A random share is kept, enlarged so the
    canopy keeps its coverage."""
    me = o.data
    tp = topology(me)
    n = tp['n']
    co = arr_co(me)
    nl = len(me.loops)
    uv = np.empty(nl * 2, np.float32)
    me.uv_layers.active.data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2).astype(np.float64)
    nf = len(me.polygons)
    pn = np.empty(nf * 3, np.float32)
    me.polygons.foreach_get('normal', pn)
    pn = pn.reshape(-1, 3)
    pa = np.empty(nf, np.float32)
    me.polygons.foreach_get('area', pa)
    li = tp['vlab'][tp['lv']]
    cnt = np.maximum(np.bincount(li, minlength=n), 1)
    du = uv[:, 0] - (np.bincount(li, uv[:, 0], n) / cnt)[li]
    dv = uv[:, 1] - (np.bincount(li, uv[:, 1], n) / cnt)[li]
    th = 0.5 * np.arctan2(2 * np.bincount(li, du * dv, n), np.bincount(li, du * du, n) - np.bincount(li, dv * dv, n))
    ca, sa = np.cos(th)[li], np.sin(th)[li]
    along = du * ca + dv * sa
    across = -du * sa + dv * ca

    def arg_min(key):
        order = np.lexsort((key, li))
        first = np.ones(len(order), bool)
        first[1:] = li[order][1:] != li[order][:-1]
        res = np.full(n, -1, np.int64)
        res[li[order][first]] = order[first]
        return res

    corners = np.stack([arg_min(along), arg_min(across), arg_min(-along), arg_min(-across)], 1)
    ok = np.all(corners >= 0, 1)
    for a, b in [(0, 1), (1, 2), (2, 3), (3, 0), (0, 2), (1, 3)]:
        ok &= tp['lv'][corners[:, a]] != tp['lv'][corners[:, b]]
    P = co[tp['lv'][corners]].astype(np.float64)
    quad_area = 0.5 * np.linalg.norm(np.cross(P[:, 2] - P[:, 0], P[:, 3] - P[:, 1]), axis=1)
    leaf_area = np.bincount(tp['flab'], pa, n)
    cover = float(quad_area[ok].sum() / max(leaf_area[ok].sum(), 1e-9))
    keep_frac = min(1.0, budget / (2.0 * max(int(ok.sum()), 1)))
    keep = ok & (rng.random(n) < keep_frac)
    grow = min(math.sqrt(1.0 / (keep_frac * max(cover, 0.1))), grow_cap)
    c = island_centres(co, tp['vlab'], n)
    nrm = np.stack([np.bincount(tp['flab'], pn[:, k] * pa, n) for k in range(3)], 1)
    U = uv[corners[keep]]
    P = P[keep]
    C = c[keep][:, None, :]
    P = C + (P - C) * grow
    qn = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    flip = (qn * nrm[keep]).sum(1) < 0
    P[flip] = P[flip][:, ::-1]
    U[flip] = U[flip][:, ::-1]
    cards = len(P)
    new = bpy.data.meshes.new(me.name + '_leaves')
    new.from_pydata([tuple(p) for p in P.reshape(-1, 3)], [], [tuple(range(i * 4, i * 4 + 4)) for i in range(cards)])
    lay = new.uv_layers.new(name=me.uv_layers.active.name)
    lay.data.foreach_set('uv', U.reshape(-1).astype(np.float32))
    for m in me.materials:
        new.materials.append(m)
    o.data = new
    return int(ok.sum()), cards, grow


def split_by_material(o):
    select_only([o])
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='MATERIAL')
    bpy.ops.object.mode_set(mode='OBJECT')
    parts = meshes()
    for p in parts:
        # Each part keeps every slot; leave it only the one its faces use.
        used = {pl.material_index for pl in p.data.polygons}
        if len(used) == 1 and len(p.data.materials) > 1:
            m = p.data.materials[used.pop()]
            p.data.materials.clear()
            p.data.materials.append(m)
            p.data.polygons.foreach_set('material_index', np.zeros(len(p.data.polygons), np.int64))
    return parts


# ------------------------------------------------------------------ materials and textures

_px_cache = {}


def to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def pixels(img, size):
    """Image as (h, w, 4) float32 resampled to size (w, h); rows bottom-up, values as stored (sRGB stays encoded)."""
    key = (img.name, size)
    if key in _px_cache:
        return _px_cache[key]
    w, h = img.size
    a = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(a)
    a = a.reshape(h, w, 4)
    tw, th = size
    if (w, h) != (tw, th):
        if w % tw == 0 and h % th == 0:
            a = a.reshape(th, h // th, tw, w // tw, 4).mean((1, 3))
        else:
            ys = (np.arange(th) * h // th).clip(0, h - 1)
            xs = (np.arange(tw) * w // tw).clip(0, w - 1)
            a = a[ys][:, xs]
    _px_cache[key] = a
    return a


def link_src(sock):
    if not sock.is_linked:
        return None, None
    l = sock.links[0]
    n, s = l.from_node, l.from_socket
    while n.type == 'REROUTE':
        if not n.inputs[0].is_linked:
            return None, None
        l = n.inputs[0].links[0]
        n, s = l.from_node, l.from_socket
    return n, s


def find_image(sock, depth=0):
    """(image node, output socket name) feeding sock, through Separate Color / Math / Mix / Normal Map nodes."""
    n, s = link_src(sock)
    if n is None or depth > 6:
        return None, None
    if n.type == 'TEX_IMAGE':
        return n, s.name
    if n.type == 'SEPARATE_COLOR':
        img, _ = find_image(n.inputs['Color'], depth + 1)
        return img, s.name
    if n.type in ('MATH', 'MIX', 'MIX_RGB', 'NORMAL_MAP'):
        for i in n.inputs:
            if i.is_linked:
                img, out = find_image(i, depth + 1)
                if img is not None:
                    return img, out
    return None, None


def channel(sock, size, default):
    img, out = find_image(sock)
    w, h = size
    if img is None or img.image is None:
        v = sock.default_value if not sock.is_linked else default
        return np.full((h, w), float(v), np.float32)
    return pixels(img.image, size)[..., {'Red': 0, 'Green': 1, 'Blue': 2, 'Alpha': 3}.get(out, 0)]


def principled(m):
    if not m or not m.use_nodes:
        return None
    return next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)


def occlusion_socket(m):
    if not m or not m.use_nodes:
        return None
    for n in m.node_tree.nodes:
        if n.type == 'GROUP' and n.node_tree and n.node_tree.name in ('glTF Material Output', 'glTF Settings') and 'Occlusion' in n.inputs:
            return n.inputs['Occlusion']
    return None


def signature(m):
    b = principled(m)
    if b is None:
        return m.name if m else '-'
    parts = []
    for k in ('Base Color', 'Roughness', 'Metallic', 'Normal'):
        img, out = find_image(b.inputs[k])
        v = b.inputs[k].default_value
        parts.append('%s:%s' % (img.image.name if img is not None and img.image else tuple(round(x, 3) for x in (v if hasattr(v, '__len__') else [v])), out))
    return '|'.join(parts)


def sample(m, size, tint=None):
    """Material as texture arrays at size: base colour (sRGB), orm (occlusion, roughness, metallic), normal."""
    w, h = size
    b = principled(m)
    base = np.ones((h, w, 4), np.float32)
    orm = np.ones((h, w, 4), np.float32)
    nor = np.zeros((h, w, 4), np.float32)
    nor[...] = (0.5, 0.5, 1.0, 1.0)
    if b is None:
        base[..., :3] = 0.5
        orm[..., 1] = 0.7
        orm[..., 2] = 0.0
        return base, orm, nor
    img, out = find_image(b.inputs['Base Color'])
    if img is not None and img.image is not None:
        base[..., :3] = pixels(img.image, size)[..., :3]
    else:
        base[..., :3] = [to_srgb(c) for c in b.inputs['Base Color'].default_value[:3]]
    if tint:
        base[..., :3] *= np.array([to_srgb(c) for c in tint], np.float32) / max(float(base[..., :3].mean()), 1e-3)
        base[..., :3] = base[..., :3].clip(0, 1)
    orm[..., 1] = channel(b.inputs['Roughness'], size, 0.5)
    orm[..., 2] = channel(b.inputs['Metallic'], size, 0.0)
    occ = occlusion_socket(m)
    if occ is not None:
        orm[..., 0] = channel(occ, size, 1.0)
    n_img, _ = find_image(b.inputs['Normal'])
    if n_img is not None and n_img.image is not None:
        nor[..., :3] = pixels(n_img.image, size)[..., :3]
    return base, orm, nor


def save_image(name, arr, path, colorspace, fmt):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.colorspace_settings.name = colorspace
    img.pixels.foreach_set(np.ascontiguousarray(arr, np.float32).ravel())
    img.filepath_raw = path
    img.file_format = fmt
    img.save(filepath=path, quality=90)
    img.filepath = path
    img.reload()
    return img


def new_material(name, base_img, orm_img, nor_img, occlusion, double_sided):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != 'OUTPUT_MATERIAL':
            nt.nodes.remove(n)
    out = next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL')
    b = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(b.outputs['BSDF'], out.inputs['Surface'])
    tb = nt.nodes.new('ShaderNodeTexImage')
    tb.image = base_img
    nt.links.new(tb.outputs['Color'], b.inputs['Base Color'])
    to = nt.nodes.new('ShaderNodeTexImage')
    to.image = orm_img
    sep = nt.nodes.new('ShaderNodeSeparateColor')
    nt.links.new(to.outputs['Color'], sep.inputs['Color'])
    nt.links.new(sep.outputs['Green'], b.inputs['Roughness'])
    nt.links.new(sep.outputs['Blue'], b.inputs['Metallic'])
    if occlusion:
        g = bpy.data.node_groups.get('glTF Material Output')
        if g is None:
            from io_scene_gltf2.blender.com.material_helpers import create_settings_group
            g = create_settings_group('glTF Material Output')
        gn = nt.nodes.new('ShaderNodeGroup')
        gn.node_tree = g
        nt.links.new(sep.outputs['Red'], gn.inputs['Occlusion'])
    tn = nt.nodes.new('ShaderNodeTexImage')
    tn.image = nor_img
    nm = nt.nodes.new('ShaderNodeNormalMap')
    nt.links.new(tn.outputs['Color'], nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'], b.inputs['Normal'])
    m.use_backface_culling = not double_sided
    m.surface_render_method = 'DITHERED'
    return m


def make_opaque(m):
    """Blend / mask / transmission come out OPAQUE. Returns True if the material had any."""
    b = principled(m)
    if b is None:
        return False
    a = b.inputs['Alpha']
    t = b.inputs['Transmission Weight']
    changed = a.is_linked or a.default_value < 1.0 or t.default_value > 0.0 or m.surface_render_method == 'BLENDED'
    for l in list(a.links):
        m.node_tree.links.remove(l)
    a.default_value = 1.0
    t.default_value = 0.0
    m.surface_render_method = 'DITHERED'
    return changed


def tint_for(cfg, mid, m):
    return cfg.get('tint', {}).get(re.sub(r'^%s_' % re.escape(mid), '', m.name)) if m else None


def merge_materials(o, mid, cfg, tex_size):
    """Packs all materials into one atlas (one draw call). Returns a description, or '' if there was one already."""
    me = o.data
    mats = list(me.materials)
    nf = len(me.polygons)
    fm = np.empty(nf, np.int64)
    me.polygons.foreach_get('material_index', fm)
    used = sorted(set(fm.tolist()))
    # Same textures and factors under different names (covered_car / covered_car.001) share one cell.
    sig = {}
    cell_of = {}
    for i in used:
        s = signature(mats[i]) + '|' + str(tint_for(cfg, mid, mats[i]))
        cell_of[i] = sig.setdefault(s, len(sig))
    ncell = len(sig)
    if ncell <= 1:
        if len(mats) > 1:
            keep = mats[used[0]]
            me.materials.clear()
            me.materials.append(keep)
            me.polygons.foreach_set('material_index', np.zeros(nf, np.int64))
        return ''
    # Cells by share of surface area: big ones at full size in a row, small ones at a quarter below them.
    pa = np.empty(nf, np.float32)
    me.polygons.foreach_get('area', pa)
    weight = np.zeros(ncell)
    for i in used:
        weight[cell_of[i]] += pa[fm == i].sum()
    weight /= max(weight.sum(), 1e-9)
    T = tex_size
    S = max(T // 4, 64)
    ranked = [int(c) for c in np.argsort(-weight)]
    big = [c for c in ranked if weight[c] >= 0.15] or ranked[:1]
    small = [c for c in ranked if c not in big]
    W = T * len(big)
    per_row = max(W // S, 1)
    rows = (len(small) + per_row - 1) // per_row
    H = T + rows * S
    rect = {}
    for k, c in enumerate(big):
        rect[c] = (k * T, rows * S, T, T)
    for k, c in enumerate(small):
        rect[c] = ((k % per_row) * S, (rows - 1 - k // per_row) * S, S, S)
    A_base = np.ones((H, W, 4), np.float32)
    A_orm = np.ones((H, W, 4), np.float32)
    A_nor = np.zeros((H, W, 4), np.float32)
    A_nor[...] = (0.5, 0.5, 1.0, 1.0)
    rep = {}
    for i in used:
        rep.setdefault(cell_of[i], i)
    any_occ = False
    double = False
    pad_of = {}
    for c, i in rep.items():
        x0, y0, cw, ch = rect[c]
        pad = max(cw // 128, 2)
        pad_of[c] = pad
        b, orm, nor = sample(mats[i], (cw - 2 * pad, ch - 2 * pad), tint_for(cfg, mid, mats[i]))
        any_occ |= occlusion_socket(mats[i]) is not None
        double |= not mats[i].use_backface_culling
        for dst, src in ((A_base, b), (A_orm, orm), (A_nor, nor)):
            dst[y0:y0 + ch, x0:x0 + cw] = np.pad(src, ((pad, pad), (pad, pad), (0, 0)), mode='edge')
    # UVs into the cells. Faces that tile are shifted by whole tiles first; what still falls outside is clamped.
    nl = len(me.loops)
    uv = np.empty(nl * 2, np.float32)
    lay = me.uv_layers.active
    lay.data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2).astype(np.float64)
    lt = np.empty(nf, np.int64)
    me.polygons.foreach_get('loop_total', lt)
    lface = np.repeat(np.arange(nf), lt)
    fmin = np.full((nf, 2), np.inf)
    np.minimum.at(fmin, lface, uv)
    uv -= np.floor(fmin[lface] + 1e-4)
    clamped = int(((uv < -1e-3) | (uv > 1 + 1e-3)).any(1).sum())
    uv = uv.clip(0.0, 1.0)
    cl = np.array([cell_of.get(i, 0) for i in range(len(mats))])[fm[lface]]
    r = np.array([rect[c] for c in range(ncell)], np.float64)
    p = np.array([pad_of[c] for c in range(ncell)], np.float64)[cl]
    uv[:, 0] = (r[cl, 0] + p + uv[:, 0] * (r[cl, 2] - 2 * p)) / W
    uv[:, 1] = (r[cl, 1] + p + uv[:, 1] * (r[cl, 3] - 2 * p)) / H
    lay.data.foreach_set('uv', uv.astype(np.float32).ravel())
    os.makedirs(TEX, exist_ok=True)
    bi = save_image(mid + '_atlas_diff', A_base, os.path.join(TEX, mid + '_atlas_diff.jpg'), 'sRGB', 'JPEG')
    oi = save_image(mid + '_atlas_arm', A_orm, os.path.join(TEX, mid + '_atlas_arm.jpg'), 'Non-Color', 'JPEG')
    ni = save_image(mid + '_atlas_nor_gl', A_nor, os.path.join(TEX, mid + '_atlas_nor_gl.jpg'), 'Non-Color', 'JPEG')
    m = new_material(mid, bi, oi, ni, any_occ, double)
    me.materials.clear()
    me.materials.append(m)
    me.polygons.foreach_set('material_index', np.zeros(nf, np.int64))
    return '%d materials packed into one %dx%d atlas%s' % (len(used), W, H, ' (%d tiling UV corners clamped)' % clamped if clamped else '')


def shrink_textures(o, mid, size):
    """Writes size-px copies of the model's textures that are larger and points the material at them."""
    done = {}
    for m in o.data.materials:
        if not m or not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type != 'TEX_IMAGE' or n.image is None:
                continue
            img = n.image
            if img.name not in done:
                if max(img.size) <= size:
                    done[img.name] = img
                    continue
                w, h = img.size
                k = size / max(w, h)
                a = pixels(img, (max(int(w * k), 1), max(int(h * k), 1)))
                base = re.sub(r'_[124]k$', '', os.path.splitext(os.path.basename(img.filepath))[0])
                path = os.path.join(TEX, '%s_%d.jpg' % (base, size))
                os.makedirs(TEX, exist_ok=True)
                done[img.name] = save_image(img.name + '_%d' % size, a, path, img.colorspace_settings.name, 'JPEG')
            n.image = done[img.name]
    return sum(1 for k, v in done.items() if v.name != k)


# ------------------------------------------------------------------ preview

def preview(o, path):
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'TEXTURE'
    scn.render.resolution_x = 520
    scn.render.resolution_y = 520
    scn.world = scn.world or bpy.data.worlds.new('w')
    lo, hi = bounds(o)
    c = Vector(((lo + hi) / 2).tolist())
    r = float(np.linalg.norm(hi - lo)) * 0.5
    cam_data = bpy.data.cameras.new('cam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = r * 2.1
    cam_data.clip_end = r * 10
    cam = bpy.data.objects.new('cam', cam_data)
    scn.collection.objects.link(cam)
    d = Vector((1.0, -1.3, 0.8)).normalized()
    cam.location = c + d * r * 4
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    scn.camera = cam
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)


# ------------------------------------------------------------------ one model

def budget_for(cfg, size):
    if 'tris' in cfg:
        return cfg['tris']
    L = float(max(size))
    return 1000 if L < 0.3 else 1800 if L < 0.6 else 3000 if L < 1.2 else 4000


def process(mid, cfg, render_before=False):
    src = source_path(mid)
    if src is None:
        print('[props] MISSING %s' % mid)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    rng = np.random.default_rng(zlib.crc32(mid.encode()))
    notes = []
    if cfg.get('keep'):
        dropped = 0
        for ob in meshes():
            if not any(re.search(p, ob.name) for p in cfg['keep']):
                bpy.data.objects.remove(ob, do_unlink=True)
                dropped += 1
        notes.append('kept one variant (%s) of the set, removed %d other objects, re-centred on it' % (', '.join(sorted(x.name for x in meshes())), dropped))
    o = join_all(mid)
    before = tris(o)
    if render_before:
        os.makedirs(PREV, exist_ok=True)
        preview(o, os.path.join(PREV, mid + '_before.png'))
    if cfg.get('scale'):
        o.data.transform(Matrix.Scale(cfg['scale'], 4))
        notes.append('scaled by %g (the source is authored at the wrong scale)' % cfg['scale'])
    if cfg.get('keep'):
        lo, hi = bounds(o)
        c = (lo + hi) / 2
        o.data.transform(Matrix.Translation((-float(c[0]), -float(c[1]), 0.0)))
    if cfg.get('drop'):
        fm = np.empty(len(o.data.polygons), np.int64)
        o.data.polygons.foreach_get('material_index', fm)
        bad = [i for i, m in enumerate(o.data.materials) if m and any(re.search(p, m.name) for p in cfg['drop'])]
        names = ', '.join(o.data.materials[i].name for i in bad)
        delete_faces(o, np.isin(fm, bad))
        notes.append('removed the hidden faces of %s' % names)
    lo, hi = bounds(o)
    size = hi - lo
    if cfg.get('tree'):
        tb = cfg['tree']
        parts = split_by_material(o)
        out = []
        for p in parts:
            name = p.data.materials[0].name if p.data.materials else ''
            t0 = tris(p)
            if 'leaves' in name:
                n_leaves, kept, grow = leaf_diamonds(p, tb['leaves'], rng)
                out.append('leaves: %d modelled leaves (%d triangles) -> %d two-triangle leaves enlarged %.1fx' % (n_leaves, t0, kept, grow))
            elif 'branch' in name or 'twig' in name:
                decimate(p, max(tb['twigs'] * 3, int(t0 * 0.25)))
                frac, grow = thin_islands(p, tb['twigs'], rng, 1.0)
                out.append('twigs: %d -> %d triangles (decimated, %.0f%% kept)' % (t0, tris(p), frac * 100))
            else:
                decimate(p, tb['trunk'])
                out.append('trunk: %d -> %d triangles' % (t0, tris(p)))
        select_only(parts)
        if len(parts) > 1:
            bpy.ops.object.join()
        o = bpy.context.view_layer.objects.active
        o.name = mid
        notes.extend(out)
    elif cfg.get('foliage'):
        frac, grow = thin_islands(o, cfg['foliage'], rng, 1.6)
        if frac < 1.0:
            notes.append('thinned to %.0f%% of its blades / leaves, survivors enlarged %.2fx' % (frac * 100, grow))
    else:
        b = budget_for(cfg, size)
        if tris(o) > b:
            decimate(o, b)
            notes.append('decimated to its %s-triangle budget' % format(b, ','))
    after = tris(o)
    L = float(max(size))
    tex = 512 if L < 0.5 else 1024
    opaque = [m.name for m in o.data.materials if m and make_opaque(m)]
    merged = merge_materials(o, mid, cfg, tex)
    if merged:
        notes.append(merged)
    elif tex < 1024 and shrink_textures(o, mid, tex):
        notes.append('textures %d px' % tex)
    if opaque:
        notes.append('blend / transmission dropped, opaque (%s)' % ', '.join(opaque))
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, mid + '.gltf')
    select_only([o])
    bpy.ops.export_scene.gltf(filepath=dst, export_format='GLTF_SEPARATE', use_selection=True, export_yup=True, export_apply=True,
                              export_keep_originals=True, export_image_format='AUTO', export_jpeg_quality=90,
                              export_animations=False, export_cameras=False, export_lights=False, export_extras=False)
    os.makedirs(PREV, exist_ok=True)
    preview(o, os.path.join(PREV, mid + '.png'))
    mats = len(o.data.materials)
    text = '%s; %s -> %s triangles, %d material%s (tools/blender/process_props.py)' % (
        '; '.join(notes) if notes else 're-exported unchanged (within budget, one material)', format(before, ','), format(after, ','), mats, '' if mats == 1 else 's')
    meta_path = os.path.join(SRC, mid, 'source.json')
    meta = json.load(open(meta_path, encoding='utf-8')) if os.path.exists(meta_path) else {'source': 'Poly Haven', 'title': mid}
    files = {}
    for f in [mid + '.gltf', mid + '.bin']:
        files[f] = hashlib.sha256(open(os.path.join(OUT, f), 'rb').read()).hexdigest()
    meta.pop('resolution', None)
    meta['files'] = files
    meta['modifications'] = text[0].upper() + text[1:] + '.'
    meta['processed_from'] = os.path.relpath(src, ROOT).replace('\\', '/')
    rec = os.path.join(OUT, 'sources')
    os.makedirs(rec, exist_ok=True)
    json.dump(meta, open(os.path.join(rec, mid + '.json'), 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
    print('[props] %-28s %8d -> %6d tris  %d mat  %.2f x %.2f x %.2f m  %s' % (mid, before, after, mats, size[0], size[1], size[2], text))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ids = model_ids()
    if argv == ['--list']:
        print('[props] ' + ' '.join(ids))
        return
    before = '--before' in argv
    argv = [a for a in argv if a != '--before']
    for mid in ids:
        if argv and mid not in argv:
            continue
        try:
            process(mid, MODELS.get(mid, {}), before)
        except Exception as e:
            import traceback
            traceback.print_exc()
            print('[props] FAILED %s: %s' % (mid, e))


main()
