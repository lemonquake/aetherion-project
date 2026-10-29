import bpy, sys, os, json
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]
out = []
for path in argv:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.endswith('.glb') or path.endswith('.gltf'):
        bpy.ops.import_scene.gltf(filepath=path)
    dg = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9,)*3); hi = Vector((-1e9,)*3)
    objs = []
    tot = 0
    mats = set()
    for o in bpy.context.scene.objects:
        if o.type != 'MESH':
            continue
        me = o.data
        t = sum(len(p.vertices) - 2 for p in me.polygons)
        tot += t
        olo = Vector((1e9,)*3); ohi = Vector((-1e9,)*3)
        for v in me.vertices:
            w = o.matrix_world @ v.co
            olo = Vector(map(min, olo, w)); ohi = Vector(map(max, ohi, w))
        lo = Vector(map(min, lo, olo)); hi = Vector(map(max, hi, ohi))
        for m in me.materials:
            if m: mats.add(m.name)
        objs.append('%s t=%d c=(%.2f,%.2f,%.2f) s=(%.2f,%.2f,%.2f) mats=%s' % (o.name, t, *((olo+ohi)/2), *(ohi-olo), [m.name for m in me.materials if m]))
    imgs = ['%s %dx%d' % (i.name, i.size[0], i.size[1]) for i in bpy.data.images]
    print('=== %s tris=%d objs=%d mats=%d size(blender xyz)=(%.2f,%.2f,%.2f) lo=(%.2f,%.2f,%.2f)' % (os.path.basename(path), tot, len(objs), len(mats), *(hi-lo), *lo))
    print('  imgs: ' + '; '.join(imgs))
    for s in objs[:40]:
        print('  ' + s)
    if len(objs) > 40: print('  ... %d more' % (len(objs)-40))
