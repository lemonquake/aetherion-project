"""r5: process_items.py keeps moving parts (mag, slide, bolt, ...) as separate meshes."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'tools', 'blender', 'process_items.py')
s = open(p, 'rb').read().decode()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')
a = s.index('def process(item_id, cfg):')
b = s.index('def main():')
NEW = r'''def split_boxes(parts, cfg):
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
    cam_data.ortho_scale = length * 1.1
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
    lo, hi = extent([v for o in parts.values() for v in verts(o)])
    return {'length': length, 'lo': list(lo), 'hi': list(hi), 'ortho': length * 1.1, 'res': [1000, 500]}


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


'''
s = s[:a] + NEW + s[b:]
s = s.replace("PREV = os.path.join(ROOT, 'work', 'items')", "PREV = os.path.join(ROOT, 'work', 'lemondev', 'r5', 'items')")
open(p, 'wb').write(s.replace('\n', nl).encode())
print('patched')
