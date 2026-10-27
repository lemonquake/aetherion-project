"""Trash never blocks anyone or anything (user, 2026-10-27): garbage heaps lose their collision, trash bags and cans
lie where people (and bullets) pass through them; they can still be picked up with T."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

m = Patch('game/src/world/model_lib.gd')
m.rep('''	"trashbag": {"model": "trashbag", "mass": 4.0, "mat": "fabric", "hp": 30, "kind": "small"},''',
      '''	"trashbag": {"model": "trashbag", "mass": 4.0, "mat": "fabric", "hp": 30, "kind": "small", "no_block": true},''')
m.rep('''	"can": {"model": "can_rusted", "mass": 0.3, "mat": "sheet_metal", "hp": 20, "kind": "small", "throwable": true},''',
      '''	"can": {"model": "can_rusted", "mass": 0.3, "mat": "sheet_metal", "hp": 20, "kind": "small", "throwable": true, "no_block": true},''')
for size in ['large', 'medium', 'small']:
    for v in 'ab':
        key = '"heap_%s_%s": {' % (size, v)
        i0 = m.s.index(key)
        i1 = m.s.index('"static": true}', i0)
        m.s = m.s[:i1] + '"static": true, "no_collide": true}' + m.s[i1 + len('"static": true}'):]
m.save()

d = Patch('game/src/world/dynamics.gd')
d.rep('''	PhysicsServer3D.body_set_collision_layer(body, Defs.PHYS_PROP | Defs.PHYS_INTERACT)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	var ref := Ref.new()
	ref.set_meta("prop_id", p.id)''', '''	# Trash (no_block) can be grabbed but blocks no one and stops no bullet.
	var no_block: bool = models.spec(str(p.name)).get("no_block", false)
	PhysicsServer3D.body_set_collision_layer(body, Defs.PHYS_INTERACT if no_block else Defs.PHYS_PROP | Defs.PHYS_INTERACT)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	var ref := Ref.new()
	ref.set_meta("prop_id", p.id)''')
d.save()

p = Patch('game/src/props/physics_prop.gd')
p.rep('''	collision_layer = Defs.PHYS_PROP | Defs.PHYS_INTERACT
	collision_mask = Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS | Defs.PHYS_CHAR''', '''	collision_layer = Defs.PHYS_PROP | Defs.PHYS_INTERACT
	collision_mask = Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS | Defs.PHYS_CHAR
	if s.get("no_block", false):
		# Trash: tumbles on the ground and can be carried, but people and bullets pass through it.
		collision_layer = Defs.PHYS_DEBRIS | Defs.PHYS_INTERACT
		collision_mask = Defs.PHYS_WORLD | Defs.PHYS_GLASS''')
p.save()
