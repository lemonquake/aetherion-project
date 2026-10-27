"""Bot looting tuning after the first 40-bot match (loot run 2026-10-26): fetch only valuable loot close by (bots
were walking 45 m for a bandage), drop ammunition for no carried gun straight away, and trace detours and fetches.

    python -I tools/patches/p52_bot_fetch_tuning.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'src', 'ai', 'bot_brain.gd')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep('''	var need := not LootSense.armed_ok(ch)
	var reach := 45.0 if need else 25.0''', '''	var need := not LootSense.armed_ok(ch)
	var reach := 30.0 if need else 18.0
	var min_v := 2.0 if need else 2.5''')
rep('''		var v := LootSense.value(ch, it.entry)
		if v < (0.6 if need else 1.2):
			continue''', '''		var v := LootSense.value(ch, it.entry)
		if v < min_v:
			continue''')
rep('''	_junk_t -= dt
	if _junk_t <= 0.0:
		_junk_t = 4.0
		if ch.inv.bag_mass() > ch.inv.capacity():
			world.interaction.bot_drop_junk(ch)''', '''	_junk_t -= dt
	if _junk_t <= 0.0:
		_junk_t = 4.0
		world.interaction.bot_drop_junk(ch, ch.inv.bag_mass() > ch.inv.capacity())''')
rep('''	print("[bot %s] %s step %d/%d %s at %s -> %s (%.1f m) path %d/%d stuck %.1f btn %d%s" % [ch.pname, state, plan_i, plan.size(),''',
    '''	if _detour >= 0:
		extra += " detour item %d" % _detour
	if not _fetch.is_empty():
		extra += " fetch %s %d %.0f m" % [str(_fetch.kind), int(_fetch.id), (_fetch.p as Vector3).distance_to(ch.global_position)]
	var guns := []
	for sl in [1, 2, 3]:
		if ch.wpn.slots[sl] != null:
			guns.append("%s(%d+%d)" % [ch.wpn.slots[sl].id, int(ch.wpn.slots[sl].mag), ch.inv.count(Defs.ammo_item(str(ch.wpn.slots[sl].id)))])
	extra += " guns " + ",".join(guns)
	print("[bot %s] %s step %d/%d %s at %s -> %s (%.1f m) path %d/%d stuck %.1f btn %d%s" % [ch.pname, state, plan_i, plan.size(),''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())

p2 = os.path.join(ROOT, 'game', 'src', 'match', 'interaction.gd')
raw = open(p2, 'rb').read().decode()
crlf2 = '\r\n' in raw
s = raw.replace('\r\n', '\n')
rep('''func bot_drop_junk(ch) -> void:
	## Overloaded: drop ammunition for no carried gun, then spare attachments.
	for e in LootSense.junk(ch):
		if ch.inv.bag_mass() <= ch.inv.capacity():
			return''', '''func bot_drop_junk(ch, overloaded: bool) -> void:
	## Ammunition for no carried gun is left behind; spare attachments too when overloaded.
	for e in LootSense.junk(ch):
		if Defs.is_attachment(str(e.id)) and (not overloaded or ch.inv.bag_mass() <= ch.inv.capacity()):
			continue''')
open(p2, 'wb').write((s.replace('\n', '\r\n') if crlf2 else s).encode())
print('ok')
