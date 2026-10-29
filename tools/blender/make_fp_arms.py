"""First-person arms: game/assets/models/fp_arms/fp_arms.glb from the downloaded rigged arms.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/make_fp_arms.py

Source: tools/cache/sketchfab/arms_aerolab ("(Animation) FPS Arms For Games", Matt-AeroLab, CC-BY-4.0): skinned human
arms (MakeHuman-style photographic skin with a normal map) on a HumanIK skeleton with four joints per finger.

What this does:
- converts centimetres to metres, drops the source's camera / locators, and puts its authored camera at the origin
  looking along Godot -Z, so the arms sit where the artist framed them;
- splits the skin into skin_upper (the top of the upper arm), skin_arm (the rest of the arm) and skin_hand, so sleeves
  and gloves can hide what they cover;
- builds clothing shells skinned to the same bones (offset along the normals and given a thickness):
  sleeve_short (T-shirt), sleeve_long (long-sleeve shirt), sleeve_jacket (thicker, to the wrist), glove (full),
  glove_fingerless (palm and the first finger joints);
- tints the skin texture to the game's default skin (Kayumanggi; the game multiplies other tones on top).
Writes work/lemondev/r5/arms/fp_arms_check.png (all pieces) and a source.json with credits.
"""
import json
import math
import os
import shutil

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'tools', 'cache', 'sketchfab', 'arms_aerolab')
OUT = os.path.join(ROOT, 'game', 'assets', 'models', 'fp_arms')
CHECK = os.path.join(ROOT, 'work', 'lemondev', 'r5', 'arms')
CAMERA_CM = Vector((0.0, -3.342, 164.564))   # the source's authored first-person camera
# Average bare-skin colour of the game's body texture (gear_generic_body.jpg, linear-ish sRGB 0..1).
SKIN_TARGET = (0.56, 0.39, 0.29)


def side_of(name):
    return 'L' if 'Left' in name else ('R' if 'Right' in name else '')


def region_of(group):
    if 'Hand' in group:
        if any(f in group for f in ('Thumb', 'Index', 'Middle', 'Ring', 'Pinky')):
            joint = ''.join(ch for ch in group.split('_')[1] if ch.isdigit())
            return 'finger' + joint
        return 'hand'
    if 'ForeArm' in group:
        return 'fore'
    return 'upper'


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, 'arms_aerolab.glb'))
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    mesh = next(o for o in bpy.context.scene.objects if o.type == 'MESH' and o.vertex_groups)
    for o in list(bpy.context.scene.objects):
        if o not in (arm, mesh):
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    arm.animation_data_clear()
    # cm -> m, camera at the origin, facing Blender +Y (Godot -Z): turn 180 degrees about Z.
    X = Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Scale(0.01, 4) @ Matrix.Translation(-CAMERA_CM)
    bpy.ops.object.select_all(action='DESELECT')
    for o in (arm, mesh):
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    for o in (arm, mesh):
        o.matrix_world = X @ o.matrix_world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mesh.parent = arm
    mesh.matrix_parent_inverse = Matrix()
    for m in mesh.modifiers:
        if m.type == 'ARMATURE':
            m.object = arm
    arm.name = 'Arms'
    arm.data.name = 'Arms'
    mesh.name = 'skin'

    # Joint positions (rest) for the sleeve lengths.
    bones = {b.name: b.head_local.copy() for b in arm.data.bones}

    def find(part, side):
        return next(v for n, v in bones.items() if part in n and ('Left' if side == 'L' else 'Right') in n and 'Hand' not in n or
                    (part == 'Hand' and n.endswith(('LeftHand_03' if side == 'L' else 'RightHand_027'))))

    joints = {}
    for s in ('L', 'R'):
        pre = 'Character1_%s' % ('Left' if s == 'L' else 'Right')
        joints[s] = {
            'shoulder': next(v for n, v in bones.items() if n.startswith(pre + 'Arm_')),
            'elbow': next(v for n, v in bones.items() if n.startswith(pre + 'ForeArm_')),
            'wrist': next(v for n, v in bones.items() if n.startswith(pre + 'Hand_')),
        }

    # Per vertex: side, region of its strongest bone, and how far along its segment it lies.
    gnames = {g.index: g.name for g in mesh.vertex_groups}
    info = []
    for v in mesh.data.vertices:
        best, bw = None, -1.0
        for ge in v.groups:
            if ge.weight > bw:
                best, bw = gnames[ge.group], ge.weight
        s = 'L' if v.co.x < 0 else 'R'
        reg = region_of(best or '')
        j = joints[s]
        if reg == 'upper':
            a, b = j['shoulder'], j['elbow']
        else:
            a, b = j['elbow'], j['wrist']
        d = b - a
        t = (v.co - a).dot(d) / d.length_squared
        info.append((s, reg, t))

    def faces_where(pred):
        return [f.index for f in mesh.data.polygons if all(pred(info[i]) for i in f.vertices)]

    def is_upper_top(x):
        return x[1] == 'upper' and x[2] < 0.6

    def is_hand(x):
        return x[1] in ('hand', 'finger1', 'finger2', 'finger3', 'finger4') or (x[1] == 'fore' and x[2] > 0.97)

    def is_short(x):
        return x[1] == 'upper' and x[2] < 0.62

    def is_long(x):
        return x[1] == 'upper' or (x[1] == 'fore' and x[2] < 0.93)

    def is_jacket(x):
        return x[1] == 'upper' or (x[1] == 'fore' and x[2] < 0.97)

    def is_glove(x):
        return is_hand(x) or (x[1] == 'fore' and x[2] > 0.9)

    def is_fingerless(x):
        return x[1] in ('hand', 'finger1') or (x[1] == 'fore' and x[2] > 0.92)

    def piece(name, face_ids, offset, thick):
        o = mesh.copy()
        o.data = mesh.data.copy()
        o.name = name
        o.data.name = name
        bpy.context.scene.collection.objects.link(o)
        keep = set(face_ids)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context='FACES')
        bm.normal_update()
        if offset:
            for v in bm.verts:
                v.co += v.normal * offset
        bm.to_mesh(o.data)
        bm.free()
        if thick:
            sm = o.modifiers.new('thick', 'SOLIDIFY')
            sm.thickness = thick
            sm.offset = -1.0
            sm.use_rim = True
            # The modifier has to come before the armature modifier for applying; move it to the top.
            with bpy.context.temp_override(object=o, active_object=o):
                bpy.ops.object.modifier_move_to_index(modifier='thick', index=0)
                bpy.ops.object.modifier_apply(modifier='thick')
        return o

    # The chest and shoulder caps (skinned to the spine and collarbones) are never in view from the eye, but the
    # stance moves the collarbones and they would bulge into the bottom corners: drop them.
    trunk = set(i for i, v in enumerate(mesh.data.vertices)
                if max(v.groups, key=lambda ge: ge.weight, default=None) is not None and
                any(k in gnames[max(v.groups, key=lambda ge: ge.weight).group] for k in ('Spine', 'Shoulder', 'Hips', 'root')))
    bm0 = bmesh.new()
    bm0.from_mesh(mesh.data)
    bm0.faces.ensure_lookup_table()
    dead = [f for f in bm0.faces if any(v.index in trunk for v in f.verts) or all(info[v.index][1] == 'upper' and info[v.index][2] < 0.1 for v in f.verts)]
    bmesh.ops.delete(bm0, geom=dead, context='FACES')
    bmesh.ops.delete(bm0, geom=[v for v in bm0.verts if not v.link_faces], context='VERTS')
    bm0.to_mesh(mesh.data)
    bm0.free()
    mesh.data.update()
    print('[arms] dropped %d trunk faces' % len(dead))
    # Re-read the per-vertex info for the remaining vertices.
    info = []
    for v in mesh.data.vertices:
        best, bw = None, -1.0
        for ge in v.groups:
            if ge.weight > bw:
                best, bw = gnames[ge.group], ge.weight
        s = 'L' if v.co.x < 0 else 'R'
        reg = region_of(best or '')
        j = joints[s]
        a, b = (j['shoulder'], j['elbow']) if reg == 'upper' else (j['elbow'], j['wrist'])
        d = b - a
        info.append((s, reg, (v.co - a).dot(d) / d.length_squared))

    upper_top = faces_where(is_upper_top)
    hand = faces_where(is_hand)
    rest = sorted(set(range(len(mesh.data.polygons))) - set(upper_top) - set(hand))
    pieces = [
        piece('skin_upper', upper_top, 0.0, 0.0),
        piece('skin_arm', rest, 0.0, 0.0),
        piece('skin_hand', hand, 0.0, 0.0),
        piece('sleeve_short', faces_where(is_short), 0.006, 0.003),
        piece('sleeve_long', faces_where(is_long), 0.004, 0.002),
        piece('sleeve_jacket', faces_where(is_jacket), 0.011, 0.004),
        piece('glove', faces_where(is_glove), 0.0022, 0.0),
        piece('glove_fingerless', faces_where(is_fingerless), 0.0024, 0.0012),
    ]
    bpy.data.objects.remove(mesh, do_unlink=True)
    for p in pieces:
        p.parent = arm
        p.matrix_parent_inverse = Matrix()

    # Skin tone: keep the texture's detail, move its average to the game's default skin.
    os.makedirs(OUT, exist_ok=True)
    for img in bpy.data.images:
        px = list(img.pixels)
        n = len(px) // 4
        if n == 0:
            continue
        mean = [sum(px[c::4]) / n for c in range(3)]
        lum = sum(mean) / 3.0
        if mean[0] < mean[2] or lum < 0.25:   # the normal map (blue-ish) is left alone
            continue
        k = [SKIN_TARGET[c] / max(mean[c], 1e-3) for c in range(3)]
        for i in range(n):
            for c in range(3):
                px[i * 4 + c] = min(px[i * 4 + c] * k[c], 1.0)
        img.pixels = px
        img.update()
        print('[arms] skin texture %s tinted, mean %s -> %s' % (img.name, [round(m, 3) for m in mean], SKIN_TARGET))
        break

    # Check render: all pieces from the camera and from the side.
    os.makedirs(CHECK, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'TEXTURE'
    sc.render.resolution_x = 900
    sc.render.resolution_y = 600
    sc.world = bpy.data.worlds.new('w')
    sc.world.color = (0.45, 0.47, 0.5)
    cd = bpy.data.cameras.new('cam')
    cd.lens = 24
    cam = bpy.data.objects.new('cam', cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for vis, tag in ((('skin_upper', 'skin_arm', 'skin_hand'), 'skin'), (('sleeve_jacket', 'glove'), 'jacket_glove'),
                     (('skin_arm', 'skin_hand', 'sleeve_short'), 'tee'), (('sleeve_long', 'skin_hand', 'glove_fingerless'), 'long_fingerless')):
        for p in pieces:
            p.hide_render = p.name not in vis
        for vname, loc, look in (('fp', (0, 0, 0), (0, 1, -0.35)), ('side', (0.9, 0.25, -0.15), (0, 0.25, -0.2))):
            cam.location = loc
            cam.rotation_euler = (Vector(look) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(CHECK, 'fp_arms_%s_%s.png' % (tag, vname))
            bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)

    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    for p in pieces:
        p.hide_render = False
        p.select_set(True)
    dst = os.path.join(OUT, 'fp_arms.glb')
    bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=True, export_yup=True, export_apply=False,
                              export_animations=False, export_image_format='JPEG', export_jpeg_quality=90)
    meta = json.load(open(os.path.join(SRC, 'source.json'), encoding='utf-8'))
    meta['files'] = {'fp_arms.glb': ''}
    meta['modifications'] = ('Scaled cm -> m, re-centred on the authored camera, animation and helper objects removed; skin '
                             'split into upper / arm / hand pieces; sleeves (short, long, jacket) and gloves (full, '
                             'fingerless) built from the arm surface and skinned to the same bones; skin texture tinted to '
                             'a medium brown (tools/blender/make_fp_arms.py).')
    meta['processed_from'] = 'tools/cache/sketchfab/arms_aerolab/arms_aerolab.glb'
    json.dump(meta, open(os.path.join(OUT, 'source.json'), 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
    for p in pieces:
        print('[arms] %-18s %5d tris' % (p.name, sum(len(f.vertices) - 2 for f in p.data.polygons)))
    print('[arms] wrote', dst)


main()
