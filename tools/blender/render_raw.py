"""Three orthographic views (along X, Y, Z) of raw downloaded models, for picking sources.

    blender -b --factory-startup -P tools/blender/render_raw.py -- <out_dir> <model.glb> ...

Writes <out_dir>/<name>.png (three views side by side) and prints mesh/armature/bone/animation counts.
"""
import os
import sys

import bpy
from mathutils import Vector


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    out = argv[0]
    os.makedirs(out, exist_ok=True)
    for p in argv[1:]:
        name = os.path.splitext(os.path.basename(p))[0]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=p)
        objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
        arms = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
        bones = sum(len(a.data.bones) for a in arms)
        tris = sum(sum(len(pl.vertices) - 2 for pl in o.data.polygons) for o in objs)
        print('[raw]', name, 'meshes', len(objs), 'armatures', len(arms), 'bones', bones, 'tris', tris, 'actions', len(bpy.data.actions),
              [a.name for a in bpy.data.actions][:12])
        for a in arms:
            print('[raw]   bones:', [b.name for b in a.data.bones][:80])
        lo = Vector((1e9, 1e9, 1e9))
        hi = -lo
        for o in objs:
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        size = hi - lo
        ctr = (hi + lo) * 0.5
        print('[raw]   size %.3f %.3f %.3f' % tuple(size))
        sc = bpy.context.scene
        sc.render.engine = 'BLENDER_WORKBENCH'
        sc.display.shading.light = 'STUDIO'
        sc.display.shading.color_type = 'TEXTURE'
        sc.display.shading.show_cavity = True
        sc.render.resolution_x = 500
        sc.render.resolution_y = 400
        sc.world = bpy.data.worlds.new('w')
        sc.world.color = (0.5, 0.52, 0.55)
        cd = bpy.data.cameras.new('cam')
        cd.type = 'ORTHO'
        cd.ortho_scale = max(size) * 1.15
        cd.clip_end = max(size) * 10.0
        cd.clip_start = max(size) * 0.001
        cam = bpy.data.objects.new('cam', cd)
        sc.collection.objects.link(cam)
        sc.camera = cam
        files = []
        for i, (axis, up) in enumerate([(Vector((1, 0, 0)), 'Y'), (Vector((0, -1, 0)), 'Y'), (Vector((0, 0, 1)), 'Y')]):
            cam.location = ctr + axis * max(size) * 3.0
            cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', up).to_euler()
            f = os.path.join(out, '_%s_%d.png' % (name, i))
            sc.render.filepath = f
            bpy.ops.render.render(write_still=True)
            files.append(f)
        print('[raw-files]', name, '|'.join(files))


main()
