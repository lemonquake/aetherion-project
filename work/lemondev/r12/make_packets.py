"""r12 blind review packets from one autotest run (python -I make_packets.py <run dir> <pass n>).

critic_move<n>/: the movement strips (r11 motor vs r12 motor, same scripted routes), critic_field<n>/: the boundary
captures (old haze vs new field). One random A/B order per packet (the same in every view); the mapping goes to *_mapping_private.json next
to the packet folder, never inside it.
"""
import json
import random
import shutil
import sys
from pathlib import Path

run = Path(sys.argv[1])
n = sys.argv[2]
here = Path(__file__).resolve().parent
rng = random.Random(f"r12-{n}")

MOVE = [
    ("view1", "start_stop", "Sprint from a standstill on flat ground, then all keys released (side view). Frames at 0.1, 0.4, 0.8, 1.33, 1.6 and 2.17 s after the start; keys released at 1.25 s."),
    ("view2", "hard_turn", "Sprinting, then the view snaps 90 degrees to the right at 1.5 s, forward still held (seen from above and behind). Frames at 1.0, 1.5, 1.7, 1.9, 2.17 and 2.63 s."),
    ("view3", "wall_side", "Running at a 2.2 m wall, Jump pressed about 1.1 m from it, forward held (side view). Frames at 0.42, 0.75, 0.97, 1.25, 1.58 and 2.08 s."),
    ("view4", "wall_fp", "The same run and jump at the 2.2 m wall, as the player sees it. Same frame times."),
    ("view5", "drop_roll", "Walking off a 4.5 m block, Crouch pressed while in the air (side view). Frames at 0.25, 0.75, 1.17, 1.5, 1.67 and 1.92 s."),
]
FIELD = [
    ("view1", "boundary_{}_day", "The boundary of the safe area, 14 m ahead of the player, in daylight."),
    ("view2", "boundary_{}_night", "The same boundary at night."),
    ("view3", "boundary_inside_{}", "The player standing in the boundary (outside the safe area), looking back toward the safe area, at night."),
]


def find(name: str) -> Path:
    hits = sorted(run.glob(f"*{name}.png"))
    if not hits:
        raise SystemExit(f"missing capture {name} in {run}")
    return hits[-1]


measured = {}
try:
    measured = json.loads((run / "r12_measure.json").read_text(encoding="utf-8")).get("ab_frames", {})
except (OSError, ValueError):
    pass


def frame_table(name: str, builds) -> str:
    # Speed along the ground and feet height at each frame, measured the same way in both builds.
    rows = []
    for label, build in zip("AB", builds):
        m = measured.get(f"{name}_{build}")
        if not m:
            return ""
        rows.append(f"  - {label}: speed " + ", ".join(f"{f['speed']:.2f}" for f in m) + " m/s; feet "
                    + ", ".join(f"{f['feet_y']:.2f}" for f in m) + " m")
    return "\n  Measured at each frame (speed along the ground; feet height above the course floor):\n" + "\n".join(rows)


def packet(kind: str, views, src) -> None:
    out = here / f"critic_{kind}{n}"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir()
    mapping = {}
    rows = []
    a_is_new = rng.random() < 0.5   # one assignment for the whole packet: A is the same build in every view
    for vid, name, desc in views:
        builds = ("r12", "r11") if a_is_new else ("r11", "r12")
        for label, build in zip("AB", builds):
            shutil.copy(src(name, build), out / f"{vid}_{label}.png")
        mapping[vid] = {"name": name.format("x"), "A": "candidate" if a_is_new else "baseline"}
        rows.append(f"- **{vid}**: {desc} Files: `{vid}_A.png`, `{vid}_B.png`." + (frame_table(name, builds) if kind == "move" else ""))
    (here / f"critic_{kind}{n}_mapping_private.json").write_text(json.dumps(mapping, indent=1), encoding="utf-8")
    brief = BRIEF[kind].format(views="\n".join(rows))
    (out / "BRIEF.md").write_text(brief, encoding="utf-8")
    print(out, mapping)


BRIEF = {
    "move": """# Blind review: movement

Two builds of a first-person shooter, A and B (A is the same build in every view, and so is B), ran the same scripted routes on the same flat test course (grey floor,
plain blocks). Each image is a strip of six frames from one route, left to right, top row then bottom row. The HUD
(minimap, team scores, fire mode text) is the same in both builds and is not part of the comparison.

**Criterion (fixed before the captures were taken):** which build's movement and parkour look more like a real person
moving through this space? Look at how the body gets going and stops, how it handles a sudden turn, how it deals with a
wall it jumps at, and how it lands from a high drop.

{views}

Mandatory observable constraints: the body never passes through a block; the body is never shown floating in a
pose that cannot be held (for example hanging in the air with nothing to hold); objects the body carries stay with it.

Read only the files in this folder. Do not open anything else on the machine (no source, logs or other folders).
If the evidence is incomplete or the two builds cannot be compared, answer UNVERIFIED with the reason. Otherwise choose A
or B for the criterion as a whole, without numerical scores, and answer in exactly this form:

```
Evidence status: VALID | UNVERIFIED
Unavailable or incomparable evidence: <only if unverified>
Winner: A | B
Clear advantage: true | false
Observed basis: <specific views and frames>
Mandatory constraints: <what you observed for each constraint, per build>
Single comparison gap: <the one largest remaining defect in the build you chose, or "none">
Recheck condition: <an observable condition that would show that gap fixed>
```
""",
    "field": """# Blind review: the edge of the safe area

Two builds of a first-person shooter, A and B (A is the same build in every view, and so is B). In both, the play area shrinks over a match and its edge is shown in
the world. The captures were taken at the same spot, same view and same time of day in both builds. The HUD (minimap,
team scores, fire mode text) is the same apart from anything the edge itself adds.

**Criterion (fixed before the captures were taken):** which boundary is easier to see and reads as an electric
forcefield?

{views}

Mandatory observable constraints: the boundary does not hide the players and buildings near it so much that they can
no longer be made out; nothing is broken in the image (missing textures, black or magenta surfaces, flicker frozen
into a solid sheet).

Read only the files in this folder. Do not open anything else on the machine (no source, logs or other folders).
If the evidence is incomplete or the two builds cannot be compared, answer UNVERIFIED with the reason. Otherwise choose A
or B for the criterion as a whole, without numerical scores, and answer in exactly this form:

```
Evidence status: VALID | UNVERIFIED
Unavailable or incomparable evidence: <only if unverified>
Winner: A | B
Clear advantage: true | false
Observed basis: <specific views>
Mandatory constraints: <what you observed for each constraint, per build>
Single comparison gap: <the one largest remaining defect in the build you chose, or "none">
Recheck condition: <an observable condition that would show that gap fixed>
```
""",
}

packet("move", MOVE, lambda name, build: run / "ab" / f"{name}_{build}.png")
packet("field", FIELD, lambda name, build: find(name.format(build)))
