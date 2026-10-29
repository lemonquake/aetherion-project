"""Check renders of every outfit piece on the body: work/gear/<piece>.png (front three-quarter and back views).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/render_gear.py
then  python -I tools/gear_contact_sheet.py   (one sheet per slot: work/gear/sheet_<slot>.png)
"""
import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GLB = os.path.join(ROOT, 'game', 'assets', 'models', 'gear', 'gear.glb')
OUT = os.path.join(ROOT, 'work', 'gear')
BASE = ['body_head', 'skin_torso', 'skin_upperarm', 'skin_forearm', 'skin_thigh', 'skin_shin', 'shirt_tee', 'pants_jeans', 'boots_sneakers', 'hair_short']
SLOT_PREFIX = {'hair_': 'hair_', 'shirt_': 'shirt_', 'jacket_': 'jacket_', 'pants_': 'pants_', 'boots_': 'boots_', 'gloves_': 'gloves_',
               'elbow_': 'elbow_', 'knee_': 'knee_', 'helmet_': 'helmet_', 'face_': 'face_', 'pack_': 'pack_'}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    os.makedirs(OUT, exist_ok=True)
    meshes = {o.name: o for o in bpy.data.objects if o.type == 'MESH'}
    if 'body_head' in meshes:
        hm = meshes['body_head'].data
        ca = hm.color_attributes.get('Col') or hm.color_attributes.new(name='Col', type='BYTE_COLOR', domain='CORNER')
        hm.color_attributes.active_color = ca
        for d in ca.data:
            d.color = (0.480, 0.216, 0.133, 1.0)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'VERTEX'
    sc.display.shading.show_shadows = False
    sc.display.shading.show_cavity = True
    sc.render.resolution_x = 300
    sc.render.resolution_y = 420
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new('w')
    sc.world.color = (0.35, 0.36, 0.38)
    cam_d = bpy.data.cameras.new('cam')
    cam_d.lens = 50
    cam = bpy.data.objects.new('cam', cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam

    def show(names):
        for n, o in meshes.items():
            o.hide_render = n not in names

    def items_for(prefix):
        # one entry per item: an item's extra parts (pockets, cuffs, shafts, L/R) share its name stem
        stems = {}
        for n in meshes:
            if not n.startswith(prefix) or n.endswith('_over'):
                continue
            parts = n.split('_')
            stem = '_'.join(parts[:2])
            stems.setdefault(stem, []).append(n)
        return stems

    views = [('front', Vector((1.3, -2.7, 1.25)), Vector((0, 0, 1.0))), ('back', Vector((-1.2, 2.7, 1.3)), Vector((0, 0, 1.0)))]
    head_views = [('front', Vector((0.45, -0.9, 1.72)), Vector((0, -0.04, 1.66))), ('back', Vector((-0.5, 0.85, 1.75)), Vector((0, -0.04, 1.66)))]
    for prefix in SLOT_PREFIX:
        for stem, parts in sorted(items_for(prefix).items()):
            names = set(BASE)
            slot_default = {'shirt_': 'shirt_tee', 'pants_': 'pants_jeans', 'boots_': 'boots_sneakers'}.get(prefix)
            if slot_default:
                names.discard(slot_default)
            if prefix == 'pants_':
                names.discard('skin_thigh')
            if prefix in ('shirt_', 'jacket_', 'pants_', 'boots_', 'gloves_', 'elbow_', 'knee_', 'helmet_', 'face_', 'pack_', 'hair_'):
                names.discard('skin_torso')
            if stem in ('shirt_longsleeve', 'jacket_bomber', 'jacket_denim', 'jacket_field', 'jacket_flannel', 'jacket_hoodie', 'jacket_puffer'):
                names.discard('skin_upperarm')
                names.discard('skin_forearm')
            names.update(parts)
            if stem == 'boots_tsinelas':
                names.add('skin_feet')
            if prefix == 'pants_' and stem == 'pants_shorts':
                names.update(['skin_thigh', 'skin_shin'])
            if prefix in ('hair_', 'helmet_'):
                names.discard('hair_short')
                names.update(parts)
            show(names)
            vv = head_views if prefix in ('helmet_', 'face_', 'hair_') else views
            for vname, pos, look in vv:
                cam.location = pos
                d = look - pos
                cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
                sc.render.filepath = os.path.join(OUT, '%s_%s.png' % (stem, vname))
                bpy.ops.render.render(write_still=True)
    print('[render] done')


main()
