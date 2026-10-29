import bpy, sys, math
p = sys.argv[sys.argv.index('--') + 1]
bpy.ops.import_scene.gltf(filepath=p)
for o in bpy.context.scene.objects:
    if o.type != 'MESH': continue
    e = o.matrix_world.to_euler(); s = o.matrix_world.to_scale(); t = o.matrix_world.to_translation()
    par = o.parent.name if o.parent else '-'
    print('OBJ %-36s par=%-28s t=(%.2f,%.2f,%.2f) rotdeg=(%.0f,%.0f,%.0f) s=(%.3f,%.3f,%.3f) v=%d' % (o.name, par[:28], *t, *[math.degrees(a) for a in e], *s, len(o.data.vertices)))
