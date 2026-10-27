"""Adds (or removes) Prof section timers around the per-frame callbacks, for the --autotest=perf run.

    python -I tools/prof_instrument.py apply
    python -I tools/prof_instrument.py revert

Every inserted line ends with ##PROF; wrapped callbacks are renamed _prof_<name> and a timed wrapper is appended.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "game"
WRAP = {
    "src/match/world.gd": ["_physics_process", "_process"],
    "src/player/player_controller.gd": ["_physics_process", "_process"],
    "src/player/character_visual.gd": ["_process"],
    "src/audio/sound_system.gd": ["_process"],
    "src/audio/ambience.gd": ["_process"],
    "src/audio/voice.gd": ["_process"],
    "src/fx/effects.gd": ["_process"],
    "src/ui/hud.gd": ["_process"],
    "src/ui/reticle.gd": ["_process"],
    "src/ui/smartab_ui.gd": ["_process"],
    "src/core/game.gd": ["_process"],
    "src/net/net.gd": ["_physics_process"],
    "src/props/corpse.gd": ["_physics_process", "_process"],
    "src/props/physics_prop.gd": ["_physics_process"],
}
# Inner sections: (file, anchor line (stripped), section name, lines to cover)
INNER = [
    ("src/match/world.gd", "map.physics_tick(dt)", "w.map_tick", 1),
    ("src/match/world.gd", "projectiles.step(dt, tick)", "w.projectiles", 1),
    ("src/match/world.gd", "match_server.tick(dt)", "w.match_server", 1),
    ("src/match/world.gd", "_server_health(dt)", "w.health", 1),
    ("src/match/world.gd", "_send_snapshots(tick)", "w.snapshots", 1),
    ("src/match/world.gd", "server_queue_cmds(eid, [bots[eid].think(dt, tick)])", "w.bots_think", 1),
    ("src/match/world.gd", "_server_apply(ch, c, dt, tick, false)", "w.server_apply", 1),
    ("src/match/world.gd", "_record(ch, tick)", "w.record", 1),
    ("src/world/map_builder.gd", "dyn.tick(dt)", "map.dyn_tick", 1),
    ("src/world/map_builder.gd", "lighting.tick(dt)", "map.lighting_tick", 1),
    ("src/world/map_builder.gd", "view_lod.update(dt)", "map.view_lod", 1),
    ("src/ai/bot_brain.gd", "path = nav.find_path(ch.global_position, goal, MAX_EXPAND)", "bot.find_path", 1),
    ("src/world/lighting.gd", "_shadow_budget()", "light.manager", 1),
]
TAG = "  ##PROF"


def apply() -> None:
    for rel, funcs in WRAP.items():
        p = ROOT / rel
        s = p.read_bytes().decode("utf-8")
        if "##PROF" in s:
            continue
        stem = Path(rel).stem
        tail = []
        for fn in funcs:
            m = re.search(r"^func %s\(([^)]*)\)( -> void)?:" % fn, s, re.M)
            if not m:
                print("skip", rel, fn)
                continue
            params = m.group(1)
            names = [x.split(":")[0].strip() for x in params.split(",") if x.strip()]
            s = s[:m.start()] + "func _prof%s(%s)%s:" % (fn, params, m.group(2) or "") + s[m.end():]
            key = "%s.%s" % (stem, fn.strip("_"))
            tail += [
                "",
                "func %s(%s) -> void:%s" % (fn, params, TAG),
                "\tProf.begin(\"%s\")%s" % (key, TAG),
                "\t_prof%s(%s)%s" % (fn, ", ".join(names), TAG),
                "\tProf.end(\"%s\")%s" % (key, TAG),
            ]
        s = s.rstrip("\n") + "\n" + "\n".join(tail) + "\n"
        p.write_bytes(s.encode("utf-8"))
    for rel, anchor, name, n in INNER:
        p = ROOT / rel
        lines = p.read_bytes().decode("utf-8").split("\n")
        out = []
        i = 0
        while i < len(lines):
            ln = lines[i]
            if ln.strip() == anchor:
                ind = ln[: len(ln) - len(ln.lstrip())]
                out.append("%sProf.begin(\"%s\")%s" % (ind, name, TAG))
                out.extend(lines[i:i + n])
                out.append("%sProf.end(\"%s\")%s" % (ind, name, TAG))
                i += n
                continue
            out.append(ln)
            i += 1
        p.write_bytes("\n".join(out).encode("utf-8"))
    print("applied")


def revert() -> None:
    files = set(WRAP) | {x[0] for x in INNER}
    for rel in files:
        p = ROOT / rel
        s = p.read_bytes().decode("utf-8")
        if "##PROF" not in s:
            continue
        lines = [ln for ln in s.split("\n") if "##PROF" not in ln]
        s = "\n".join(lines)
        for fn in WRAP.get(rel, []):
            s = re.sub(r"^func _prof%s\(" % fn, "func %s(" % fn, s, flags=re.M)
        s = s.rstrip("\n") + "\n"
        p.write_bytes(s.encode("utf-8"))
    print("reverted")


if __name__ == "__main__":
    {"apply": apply, "revert": revert}[sys.argv[1]]()
