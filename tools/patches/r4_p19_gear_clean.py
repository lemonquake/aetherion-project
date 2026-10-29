"""r4 (review 2 gap): clean open-front edges, skin regions without gaps (every face in exactly one region), boot
shafts over the trousers, the lobby's team cards centred."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

f = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'blender', 'make_gear.py')
patch(f, '''def keep_by_vertex(bm, pred, frac=0.5):''', '''def keep_by_region(bm, region_of_vertex, want):
    """Keep the faces whose vertices mostly belong to region `want` (ties go to the first vertex's region), so that
    neighbouring regions split the surface with no gap and no overlap."""
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


def keep_by_vertex(bm, pred, frac=0.5):''')
patch(f, '''    regions = {
        'skin_torso': lambda v, dl: dominant(v, dl, gn) in TORSO_BONES,
        'skin_upperarm': lambda v, dl: dominant(v, dl, gn) in ('upper_arm.L', 'upper_arm.R'),
        'skin_forearm': lambda v, dl: dominant(v, dl, gn) in ('forearm.L', 'forearm.R', 'hand.L', 'hand.R'),
    }
    for rname, pred in regions.items():
        bm = extract(body, {'Hoodie black', 'Hoodie rib'}, hood_free)
        dl = bm.verts.layers.deform.active
        keep_by_vertex(bm, lambda v: pred(v, dl))''', '''    def arm_region(v, dl):
        d = dominant(v, dl, gn)
        if d in ('upper_arm.L', 'upper_arm.R'):
            return 'skin_upperarm'
        if d in ('forearm.L', 'forearm.R', 'hand.L', 'hand.R'):
            return 'skin_forearm'
        return 'skin_torso'
    for rname in ('skin_torso', 'skin_upperarm', 'skin_forearm'):
        bm = extract(body, {'Hoodie black', 'Hoodie rib'}, hood_free)
        dl = bm.verts.layers.deform.active
        keep_by_region(bm, lambda v: arm_region(v, dl), rname)''')
patch(f, '''    for rname, bones in {'skin_thigh': ('thigh.L', 'thigh.R', 'hips'), 'skin_shin': ('shin.L', 'shin.R')}.items():
        bm = extract(body, {'Jeans dark'})
        dl = bm.verts.layers.deform.active
        keep_by_vertex(bm, lambda v: dominant(v, dl, gn) in bones)''', '''    for rname in ('skin_thigh', 'skin_shin'):
        bm = extract(body, {'Jeans dark'})
        dl = bm.verts.layers.deform.active
        keep_by_region(bm, lambda v: 'skin_shin' if dominant(v, dl, gn) in ('shin.L', 'shin.R', 'foot.L', 'foot.R') else 'skin_thigh', rname)''')
patch(f, '''        if open_front:
            for sx in (-1, 1):
                # Two planes leave a strip down the front open (the shirt shows).
                pass
            dl = bm.verts.layers.deform.active
            keep_by_vertex(bm, lambda v: not (abs(v.co.x) < 0.045 and v.co.y < torso_y and cut_hem < v.co.z < 1.48), frac=0.75)''', '''        if open_front:
            # Two straight cuts down the front leave it open (the shirt shows), with clean edges.
            geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
            bmesh.ops.bisect_plane(bm, geom=geom, dist=0.0001, plane_co=Vector((0.045, 0, 0)), plane_no=Vector((1, 0, 0)))
            geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
            bmesh.ops.bisect_plane(bm, geom=geom, dist=0.0001, plane_co=Vector((-0.045, 0, 0)), plane_no=Vector((1, 0, 0)))
            kill = [f for f in bm.faces if abs(f.calc_center_median().x) < 0.045 and f.calc_center_median().y < torso_y and cut_hem < f.calc_center_median().z < 1.5]
            bmesh.ops.delete(bm, geom=kill, context='FACES')''')
patch(f, '''        for name, top_t, r0, r1, layer, rough, col in (('boots_combat_shaft_', 0.62, 0.058, 0.064, LEATHER, 0.5, (0.12, 0.11, 0.1)),
                                                       ('boots_rubber_shaft_', 0.25, 0.066, 0.078, RUBBER, 0.35, (0.2, 0.35, 0.18))):''', '''        # Shafts wide enough to go over the loosest trousers (tucked in), so no trouser leg shows through.
        for name, top_t, r0, r1, layer, rough, col in (('boots_combat_shaft_', 0.62, 0.074, 0.08, LEATHER, 0.5, (0.12, 0.11, 0.1)),
                                                       ('boots_rubber_shaft_', 0.25, 0.08, 0.092, RUBBER, 0.35, (0.2, 0.35, 0.18))):''')
f2 = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'src', 'ui', 'lobby_ui.gd')
patch(f2, '''	_teams.add_theme_constant_override("v_separation", 12)
	_teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL''', '''	_teams.add_theme_constant_override("v_separation", 12)
	_teams.alignment = FlowContainer.ALIGNMENT_CENTER   # a short last row sits in the middle, not alone at the left
	_teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL''')
