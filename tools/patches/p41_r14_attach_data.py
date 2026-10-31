"""r14: new attachments (5 sights, muzzle brake, duckbill, 3 grips, heavy stock) in game/data/weapons.json, which guns
take them, and where they drop (game/data/loot.json). Idempotent; keeps each file's json.dumps formatting."""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WP = os.path.join(ROOT, 'game', 'data', 'weapons.json')
LP = os.path.join(ROOT, 'game', 'data', 'loot.json')

NEW = {
    "sight_reflex": {"name": "Reflex Sight", "kind": "sight", "zoom": 1.15, "ads_time_mult": 0.95, "axis": 0.028, "reticle": "reflex", "mass": 0.15},
    "scope_lpvo": {"name": "1-4x Variable Scope", "kind": "sight", "zoom": 4.0, "zoom_min": 1.0, "ads_time_mult": 1.18, "axis": 0.045,
                   "reticle": "horseshoe", "scope": True, "mass": 0.55},
    "scope_night": {"name": "3x Night Vision Scope", "kind": "sight", "zoom": 3.0, "ads_time_mult": 1.2, "axis": 0.05, "reticle": "stadia",
                    "scope": True, "filter": "night", "mass": 0.7},
    "scope_thermal": {"name": "4x Thermal Scope", "kind": "sight", "zoom": 4.0, "ads_time_mult": 1.25, "axis": 0.052, "reticle": "thermal",
                      "scope": True, "filter": "thermal", "mass": 0.8},
    "scope_15x": {"name": "15x Sniper Scope", "kind": "sight", "zoom": 15.0, "ads_time_mult": 1.55, "axis": 0.062, "reticle": "tree",
                  "scope": True, "mass": 0.95},
    "muzzle_brake": {"name": "Muzzle Brake", "kind": "muzzle", "recoil_up_mult": 0.74, "recoil_side_mult": 0.88, "loudness_mult": 1.25,
                     "flash_mult": 1.3, "rank": 2.4, "mass": 0.12},
    "duckbill": {"name": "Duckbill Choke", "kind": "muzzle", "pellet_spread_mult": 0.8, "recoil_up_mult": 0.95, "rank": 1.8, "mass": 0.07},
    "grip_thumb": {"name": "Thumb Grip", "kind": "grip", "ads_time_mult": 0.85, "recoil_up_mult": 0.94, "rank": 2.1, "mass": 0.06},
    "grip_light": {"name": "Lightweight Grip", "kind": "grip", "recovery_mult": 1.28, "sway_mult": 0.92, "recoil_up_mult": 1.03, "rank": 1.9, "mass": 0.05},
    "grip_ergonomic": {"name": "Ergonomic Grip", "kind": "grip", "ads_time_mult": 0.9, "recovery_mult": 1.15, "recoil_side_mult": 0.92, "rank": 2.0, "mass": 0.09},
    "stock_heavy": {"name": "Heavy Stock", "kind": "stock", "sway_mult": 0.7, "recoil_side_mult": 0.84, "ads_time_mult": 1.08, "rank": 2.1, "mass": 0.6},
}

RIFLES = ["rifle_556", "rifle_762", "rifle_scar", "rifle_m416", "rifle_m762"]
DMRS = ["marksman_308", "dmr_mini14", "dmr_sks"]
BOLTS = ["bolt_308", "bolt_kar98", "bolt_awp"]
SMGS = ["smg_9", "smg_ump45", "smg_vector"]


def fits(w, a):
    """Which guns take attachment a, by what they take already."""
    att = w.get("attachments", [])
    if a == "sight_reflex":
        return "sight_reddot" in att
    if a == "scope_lpvo":
        return w["id"] in RIFLES + DMRS + ["lmg_m249"]
    if a == "scope_night":
        return w["id"] in RIFLES + DMRS + SMGS + ["lmg_m249"]
    if a == "scope_thermal":
        return w["id"] in RIFLES + DMRS + BOLTS + ["lmg_m249"]
    if a == "scope_15x":
        return w["id"] in DMRS + BOLTS
    if a == "muzzle_brake":
        return w["id"] in RIFLES + DMRS + BOLTS + ["lmg_m249"]
    if a == "duckbill":
        return w["id"] in ["shotgun_pump", "shotgun_saiga"]
    if a in ("grip_thumb", "grip_light", "grip_ergonomic"):
        return "grip_vertical" in att or "grip_angled" in att
    if a == "stock_heavy":
        return "stock_tactical" in att or w["id"] in ["lmg_m249"]
    return False


wb = open(WP, 'rb').read().decode('utf-8')
wd = json.loads(wb)
for k, v in NEW.items():
    wd["attachments"][k] = v
for wid, w in wd["weapons"].items():
    w["id"] = wid
    lst = w.setdefault("attachments", [])
    for a in NEW:
        if a not in lst and fits(w, a):
            lst.append(a)
    del w["id"]
open(WP, 'wb').write(json.dumps(wd, indent=1, ensure_ascii=False).encode('utf-8'))

# Loot: each new attachment where its nearest existing relative drops, a little rarer.
lb = open(LP, 'rb').read().decode('utf-8')
ld = json.loads(lb)
REL = {"sight_reflex": ("sight_reddot", 0.8), "scope_lpvo": ("scope_4x", 0.6), "scope_night": ("scope_3x", 0.45),
       "scope_thermal": ("scope_6x", 0.4), "scope_15x": ("scope_8x", 0.45), "muzzle_brake": ("compensator", 0.8),
       "duckbill": ("choke", 0.8), "grip_thumb": ("grip_angled", 0.8), "grip_light": ("grip_vertical", 0.7),
       "grip_ergonomic": ("grip_half", 0.8), "stock_heavy": ("stock_tactical", 0.8)}
added = 0
for tname, t in ld["tables"].items():
    for key in ("entries", "guaranteed"):
        ent = t.get(key)
        if not isinstance(ent, list):
            continue
        ids = [e[0] for e in ent]
        for a, (rel, f) in REL.items():
            if a in ids:
                continue
            for e in list(ent):
                if e[0] == rel:
                    ent.append([a, round(float(e[1]) * f, 3)] + e[2:])
                    added += 1
                    break
# Bots and corpses: fitted to guns in the world at the usual chance; nothing else to change.
indent = 1 if lb.startswith('{\n "') else 2
open(LP, 'wb').write(json.dumps(ld, indent=indent, ensure_ascii=False).encode('utf-8'))
print("attachments:", len(wd["attachments"]), "loot entries added:", added)
