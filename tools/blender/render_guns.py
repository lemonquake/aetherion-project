"""Side-view check renders of every gun model: work/lemondev/r5/guns/<id>.png.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/render_guns.py [-- out_dir id ...]

Models: game/assets/models/items/<id>.glb, else loot/<id>.glb, else the Poly Haven source for pistol_9 / bolt_308.
Front is Blender +Y (Godot -Z); the camera looks from the gun's right side.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GUNS = ['pistol_9', 'pistol_45', 'revolver_357', 'pistol_deagle', 'shotgun_pump', 'shotgun_saiga', 'shotgun_double', 'sumpak',
        'smg_9', 'machine_pistol', 'smg_ump45', 'smg_vector', 'smg_tommy', 'rifle_556', 'rifle_762', 'rifle_scar', 'rifle_m416',
        'rifle_m762', 'lmg_m249', 'dmr_mini14', 'dmr_sks', 'marksman_308', 'bolt_308', 'bolt_kar98']
PH = {'pistol_9': 'polyhaven/service_pistol.gltf', 'bolt_308': 'polyhaven/bolt_action_rifle_7_62.gltf'}


def path_for(gid):
    for sub in ('items', 'loot', 'weapons'):
        p = os.path.join(ROOT, 'game', 'assets', 'models', sub, gid + '.glb')
        if os.path.exists(p):
            return p
    if gid in PH:
        return os.path.join(ROOT, 'game', 'assets', 'models', PH[gid])
    return None


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    out = argv[0] if argv else os.path.join(ROOT, 'work', 'lemondev', 'r5', 'guns')
    ids = argv[1:] or GUNS
    os.makedirs(out, exist_ok=True)
    for gid in ids:
        p = path_for(gid)
        if not p:
            print('[render] missing', gid)
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=p)
        objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
        lo = Vector((1e9, 1e9, 1e9))
        hi = -lo
        for o in objs:
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        size = hi - lo
        ctr = (hi + lo) * 0.5
        sc = bpy.context.scene
        sc.render.engine = 'BLENDER_WORKBENCH'
        sc.display.shading.light = 'STUDIO'
        sc.display.shading.color_type = 'TEXTURE'
        sc.display.shading.show_cavity = True
        sc.render.resolution_x = 900
        sc.render.resolution_y = 420
        sc.world = bpy.data.worlds.new('w')
        sc.world.color = (0.5, 0.52, 0.55)
        cd = bpy.data.cameras.new('cam')
        cd.type = 'ORTHO'
        long = max(size.x, size.y)
        cd.ortho_scale = long * 1.1
        cam = bpy.data.objects.new('cam', cd)
        sc.collection.objects.link(cam)
        sc.camera = cam
        # Long axis along X (Poly Haven) or Y (processed): look across it from the side.
        side = Vector((1, 0, 0)) if size.y >= size.x else Vector((0, -1, 0))
        cam.location = ctr + side * long * 3.0
        d = ctr - cam.location
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(out, gid + '.png')
        bpy.ops.render.render(write_still=True)
        print('[render]', gid, 'size %.3f %.3f %.3f' % tuple(size))


main()
