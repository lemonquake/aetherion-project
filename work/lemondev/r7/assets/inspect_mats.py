import bpy, sys, numpy as np
p = sys.argv[sys.argv.index('--') + 1]
bpy.ops.import_scene.gltf(filepath=p)
seen = set()
for o in bpy.context.scene.objects:
    if o.type != 'MESH': continue
    me = o.data
    uv = me.uv_layers.active
    rng = ''
    if uv:
        a = np.empty(len(me.loops) * 2, np.float32); uv.data.foreach_get('uv', a); a = a.reshape(-1, 2)
        rng = 'uv[%.2f..%.2f, %.2f..%.2f]' % (a[:,0].min(), a[:,0].max(), a[:,1].min(), a[:,1].max())
    print('OBJ', o.name, rng, 'vcol=%d' % len(me.color_attributes), [m.name for m in me.materials if m])
    for m in me.materials:
        if not m or m.name in seen: continue
        seen.add(m.name)
        links = []
        for l in m.node_tree.links:
            n = l.from_node
            extra = (n.image.name + ' %dx%d data=%s' % (n.image.size[0], n.image.size[1], n.image.has_data)) if n.type == 'TEX_IMAGE' and n.image else ''
            links.append('%s:%s %s -> %s:%s' % (n.type, l.from_socket.name, extra, l.to_node.type, l.to_socket.name))
        b = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        bc = tuple(round(x, 2) for x in b.inputs['Base Color'].default_value) if b else None
        print('  MAT', m.name, 'base', bc, 'blend', m.surface_render_method)
        for s in links: print('     ', s)
