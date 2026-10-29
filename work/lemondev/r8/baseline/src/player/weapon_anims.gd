extends RefCounted
## First-person weapon animation clips: reloads, and the actions that run between shots (pump, bolt) or with each
## shot (slide, cylinder). Clips are keyframes over normalised time 0..1; the viewmodel plays them over the time the
## weapon state machine (the same code the server runs) gives each step, so the animation always lasts exactly as long
## as the reload or cycle really takes.
##
## A key may set any channel; channels a key leaves out keep the previous key's value:
##   g    [position offset (view space, m), rotation offset (degrees: pitch, yaw, roll)] of the whole gun
##   L, R hand: {a: anchor, o: offset (gun space, or view space for "pouch"), h: hand pose, c: finger grip}
##   p    {part: [position offset, rotation (degrees) about the part's pivot]}
##   mag  where the magazine is: "gun", "hand" (follows the left hand), "drop" (falls away), "none" (hidden)
##   prop what the left hand carries besides a magazine: "", "shell", "round", "clip", "shells2"
## Gun space: origin at the grip, +X right, +Y up, -Z toward the muzzle.

const FpArms := preload("res://src/player/fp_arms.gd")

## Hand orientations: [finger direction, palm normal], gun space unless named view_*.
const HANDS := {
	"grip": [Vector3(-0.15, -0.55, -1.0), Vector3(-1.0, 0.05, 0.1)],
	"sup": [Vector3(0.25, 0.1, -1.0), Vector3(0.35, 1.0, 0.0)],
	"psup": [Vector3(0.45, -0.55, -1.0), Vector3(1.0, 0.35, 0.15)],
	"magL": [Vector3(0.15, -0.1, -1.0), Vector3(1.0, 0.25, 0.0)],
	"magP": [Vector3(0.5, 0.0, -1.0), Vector3(0.1, 1.0, 0.1)],
	"pinch": [Vector3(0.6, -0.2, -1.0), Vector3(0.0, -1.0, 0.0)],
	"rack": [Vector3(0.1, -0.6, -1.0), Vector3(-1.0, -0.1, 0.0)],
	"over": [Vector3(1.0, -0.15, 0.25), Vector3(0.0, -1.0, 0.0)],
	"pump": [Vector3(0.2, 0.05, -1.0), Vector3(0.3, 1.0, 0.0)],
	"under": [Vector3(0.1, 0.25, -1.0), Vector3(0.0, 1.0, 0.0)],
	"thumb": [Vector3(0.3, 0.6, -1.0), Vector3(0.2, 1.0, 0.3)],
	"bolt": [Vector3(-0.3, -0.5, -1.0), Vector3(-0.6, -0.6, 0.0)],
	"view_pouch": [Vector3(0.3, -0.2, -1.0), Vector3(0.6, 0.6, 0.0)],
}

const POUCH := Vector3(-0.3, -0.62, -0.2)   # view space, below the screen: where spare magazines and shells come from

## Every sound a clip can ask for (sounds.json ids; tools/build_r6_sounds.py makes them).
const CUES := ["mag_out", "mag_in", "mag_out_pistol", "mag_in_pistol", "mag_pouch", "charge_back", "charge_release",
	"slide_back", "slide_release", "bolt_up", "bolt_back", "bolt_fwd", "bolt_down", "clip_in", "pump_back", "pump_fwd",
	"shell_insert", "cylinder_open", "cylinder_close", "round_insert", "cylinder_click", "break_open", "break_close",
	"shell_eject", "pipe_slide", "weapon_draw"]


static func reload_kind(wid: String, has: Dictionary) -> String:
	var d := Defs.weapon(wid)
	var feed := str(d.get("feed", "mag"))
	if feed == "tube":
		return "tube"
	if feed == "cylinder":
		return "gate"
	if feed == "break":
		return "pipe" if wid == "sumpak" else "break"
	if str(d.get("slot", "")) == "handgun":
		return "mag_pistol"
	if "bolt" in d.get("fire_modes", []):
		return "mag_bolt" if has.has("mag") else "clip_bolt"
	if not has.has("mag"):
		return "clip_semi"
	return "mag_rifle"


static func charge_side(wid: String) -> String:
	## Which way the charging handle is worked on an empty reload: AR-style over the top at the rear ("top"),
	## AK-style on the right side ("right"), HK / UMP / MP5 at the front left ("front").
	if wid in ["rifle_762", "rifle_m762", "shotgun_saiga", "marksman_308", "dmr_mini14", "rifle_scar", "lmg_m249"]:
		return "right"
	if wid in ["smg_9", "smg_ump45"]:
		return "front"
	return "top"


# ------------------------------------------------------------------ clips

static func clip(kind: String, empty: bool, wid: String = "") -> Array:
	var rest_l := {"a": "sup", "o": Vector3.ZERO, "h": "sup", "c": "fore"}
	var rest_r := {"a": "grip", "o": Vector3.ZERO, "h": "grip", "c": "pistol"}
	var rest_g := [Vector3.ZERO, Vector3.ZERO]
	match kind:
		"mag_rifle":
			var cant := [Vector3(-0.03, -0.03, 0.03), Vector3(9.0, 8.0, -24.0)]
			var keys := [
				{"t": 0.0, "g": rest_g, "L": rest_l, "R": rest_r, "mag": "gun", "p": {}},
				{"t": 0.12, "g": cant, "L": {"a": "mw", "o": Vector3(-0.02, -0.02, 0.0), "h": "magL", "c": "cup"}},
				{"t": 0.19, "L": {"a": "mw", "o": Vector3.ZERO, "h": "magL", "c": "mag"}},
			]
			if empty:
				keys.append_array([
					{"t": 0.2, "mag": "drop", "L": {"a": "mw", "o": Vector3(-0.03, -0.03, 0.0), "h": "magL", "c": "cup"}},
					{"t": 0.36, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "mag"}, "mag": "hand"},
					{"t": 0.48, "L": {"a": "mw", "o": Vector3(-0.015, -0.13, 0.025), "h": "magL", "c": "mag"}},
					{"t": 0.56, "L": {"a": "mw", "o": Vector3.ZERO, "h": "magL", "c": "mag"}, "g": [Vector3(-0.03, -0.015, 0.03), Vector3(10.0, 8.0, -24.0)]},
					{"t": 0.57, "mag": "gun"},
					{"t": 0.6, "g": cant, "L": {"a": "mw", "o": Vector3(-0.02, -0.03, 0.0), "h": "magL", "c": "cup"}},
				])
				keys.append_array(_charge(charge_side(wid), 0.6))
				keys.append_array([
					{"t": 0.9, "g": [Vector3(-0.01, -0.01, 0.01), Vector3(3.0, 2.0, -6.0)], "L": rest_l},
					{"t": 1.0, "g": rest_g, "L": rest_l},
				])
			else:
				keys.append_array([
					{"t": 0.21, "mag": "hand"},
					{"t": 0.3, "L": {"a": "mw", "o": Vector3(-0.02, -0.17, 0.04), "h": "magL", "c": "mag"}},
					{"t": 0.44, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "mag"}},
					{"t": 0.58, "L": {"a": "mw", "o": Vector3(-0.015, -0.13, 0.025), "h": "magL", "c": "mag"}},
					{"t": 0.67, "L": {"a": "mw", "o": Vector3.ZERO, "h": "magL", "c": "mag"}, "g": [Vector3(-0.03, -0.015, 0.03), Vector3(10.0, 8.0, -24.0)]},
					{"t": 0.68, "mag": "gun"},
					{"t": 0.72, "g": cant, "L": {"a": "mw", "o": Vector3(-0.02, -0.03, 0.0), "h": "magL", "c": "cup"}},
					{"t": 0.86, "g": [Vector3(-0.01, -0.01, 0.01), Vector3(3.0, 2.0, -6.0)], "L": rest_l},
					{"t": 1.0, "g": rest_g, "L": rest_l},
				])
			return keys
		"mag_pistol":
			var lift := [Vector3(-0.05, 0.03, 0.04), Vector3(14.0, 10.0, -16.0)]
			var keys := [
				{"t": 0.0, "g": rest_g, "L": {"a": "grip", "o": Vector3(-0.025, -0.02, 0.0), "h": "psup", "c": "cup"}, "R": rest_r, "mag": "gun", "p": {}},
				{"t": 0.1, "g": lift, "L": {"a": "grip", "o": Vector3(-0.09, -0.08, 0.02), "h": "psup", "c": "relaxed"}},
				{"t": 0.12, "mag": "drop"},
				{"t": 0.36, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "mag"}, "mag": "hand"},
				{"t": 0.52, "L": {"a": "mw", "o": Vector3(0.0, -0.1, 0.01), "h": "magP", "c": "mag"}},
				{"t": 0.6, "L": {"a": "mw", "o": Vector3.ZERO, "h": "magP", "c": "mag"}, "g": [Vector3(-0.05, 0.045, 0.04), Vector3(16.0, 10.0, -16.0)]},
				{"t": 0.61, "mag": "gun", "L": {"a": "mw", "o": Vector3(0.0, -0.01, 0.0), "h": "magP", "c": "open"}},
				{"t": 0.64, "g": lift},
			]
			if empty:
				keys.append_array([
					{"t": 0.7, "L": {"a": "sl", "o": Vector3(0.0, 0.015, 0.0), "h": "over", "c": "cup"}, "p": {"slide": [Vector3(0, 0, 0.03), Vector3.ZERO]}},
					{"t": 0.75, "L": {"a": "sl", "o": Vector3(0.0, 0.012, 0.03), "h": "over", "c": "pinch"}, "p": {"slide": [Vector3(0, 0, 0.034), Vector3.ZERO]}},
					{"t": 0.78, "L": {"a": "sl", "o": Vector3(-0.03, 0.04, 0.06), "h": "over", "c": "open"}, "p": {"slide": [Vector3.ZERO, Vector3.ZERO]}},
				])
			keys.append_array([
				{"t": 0.88, "g": [Vector3(-0.01, 0.0, 0.01), Vector3(3.0, 2.0, -3.0)], "L": {"a": "grip", "o": Vector3(-0.025, -0.02, 0.0), "h": "psup", "c": "cup"}},
				{"t": 1.0, "g": rest_g},
			])
			if empty:
				keys[0]["p"] = {"slide": [Vector3(0, 0, 0.03), Vector3.ZERO]}
			return keys
		"mag_bolt":
			var cant := [Vector3(-0.03, -0.03, 0.03), Vector3(8.0, 6.0, -20.0)]
			var keys := [
				{"t": 0.0, "g": rest_g, "L": rest_l, "R": rest_r, "mag": "gun", "p": {}},
				{"t": 0.1, "g": cant, "L": {"a": "mw", "o": Vector3(-0.02, -0.02, 0.0), "h": "magL", "c": "cup"}},
				{"t": 0.16, "L": {"a": "mw", "o": Vector3.ZERO, "h": "magL", "c": "mag"}},
				{"t": 0.17, "mag": "hand"},
				{"t": 0.26, "L": {"a": "mw", "o": Vector3(-0.02, -0.15, 0.03), "h": "magL", "c": "mag"}},
				{"t": 0.38, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "mag"}},
				{"t": 0.5, "L": {"a": "mw", "o": Vector3(-0.015, -0.12, 0.02), "h": "magL", "c": "mag"}},
				{"t": 0.58, "L": {"a": "mw", "o": Vector3.ZERO, "h": "magL", "c": "mag"}},
				{"t": 0.59, "mag": "gun"},
				{"t": 0.64, "L": rest_l, "g": [Vector3(-0.01, -0.02, 0.02), Vector3(4.0, 3.0, -8.0)]},
			]
			if empty:
				keys.append_array(_bolt_cycle(0.64, 0.96))
			keys.append({"t": 1.0, "g": rest_g, "L": rest_l, "R": rest_r})
			return keys
		"clip_bolt", "clip_semi":
			var bolt_hand := "R" if kind == "clip_bolt" else "L"
			var keys := [
				{"t": 0.0, "g": rest_g, "L": rest_l, "R": rest_r, "mag": "gun", "p": {}, "prop": ""},
				{"t": 0.08, "g": [Vector3(-0.04, -0.02, 0.04), Vector3(8.0, 10.0, -12.0)]},
			]
			if bolt_hand == "R":
				keys.append_array([
					{"t": 0.1, "R": {"a": "bolt", "o": Vector3.ZERO, "h": "bolt", "c": "pinch"}},
					{"t": 0.15, "p": {"bolt": [Vector3.ZERO, Vector3(0, 0, 62)]}, "R": {"a": "bolt", "o": Vector3(-0.02, 0.035, 0.0), "h": "bolt", "c": "pinch"}},
					{"t": 0.22, "p": {"bolt": [Vector3(0, 0, 0.08), Vector3(0, 0, 62)]}, "R": {"a": "bolt", "o": Vector3(-0.02, 0.035, 0.08), "h": "bolt", "c": "pinch"}},
					{"t": 0.26, "R": {"a": "grip", "o": Vector3(0.03, 0.0, 0.0), "h": "grip", "c": "relaxed"}},
				])
			else:
				keys.append_array([
					{"t": 0.12, "L": {"a": "chg_r", "o": Vector3.ZERO, "h": "rack", "c": "pinch"}},
					{"t": 0.2, "L": {"a": "chg_r", "o": Vector3(0, 0, 0.08), "h": "rack", "c": "pinch"}},
				])
			keys.append_array([
				{"t": 0.38, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "pinch"}, "prop": "clip"},
				{"t": 0.52, "L": {"a": "top", "o": Vector3(0.0, 0.08, 0.0), "h": "thumb", "c": "pinch"}},
				{"t": 0.6, "L": {"a": "top", "o": Vector3(0.0, 0.035, 0.0), "h": "thumb", "c": "pinch"}},
				{"t": 0.68, "L": {"a": "top", "o": Vector3(0.0, 0.0, 0.0), "h": "thumb", "c": "fist"}},
				{"t": 0.7, "prop": ""},
			])
			if bolt_hand == "R":
				keys.append_array([
					{"t": 0.72, "L": rest_l, "R": {"a": "bolt", "o": Vector3(-0.02, 0.035, 0.08), "h": "bolt", "c": "pinch"}},
					{"t": 0.8, "p": {"bolt": [Vector3.ZERO, Vector3(0, 0, 62)]}, "R": {"a": "bolt", "o": Vector3(-0.02, 0.035, 0.0), "h": "bolt", "c": "pinch"}},
					{"t": 0.85, "p": {"bolt": [Vector3.ZERO, Vector3.ZERO]}, "R": {"a": "bolt", "o": Vector3.ZERO, "h": "bolt", "c": "pinch"}},
					{"t": 0.93, "R": rest_r},
				])
			else:
				keys.append_array([
					{"t": 0.74, "L": {"a": "chg_r", "o": Vector3(0, 0, 0.08), "h": "rack", "c": "pinch"}},
					{"t": 0.78, "L": {"a": "chg_r", "o": Vector3(0.02, 0.03, 0.1), "h": "rack", "c": "open"}},
					{"t": 0.9, "L": rest_l},
				])
			keys.append({"t": 1.0, "g": rest_g, "L": rest_l, "R": rest_r})
			return keys
		"tube_start":
			return [
				{"t": 0.0, "g": rest_g, "L": {"a": "pmp", "o": Vector3.ZERO, "h": "pump", "c": "fore"}, "R": rest_r, "mag": "gun", "p": {}, "prop": ""},
				{"t": 0.6, "g": [Vector3(-0.03, -0.02, 0.04), Vector3(6.0, 6.0, -32.0)], "L": {"a": "port", "o": Vector3(-0.04, -0.06, 0.04), "h": "under", "c": "relaxed"}},
				{"t": 1.0, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "shell"}, "prop": "shell"},
			]
		"tube_insert":
			return [
				{"t": 0.0, "g": [Vector3(-0.03, -0.02, 0.04), Vector3(6.0, 6.0, -32.0)], "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "shell"}, "R": rest_r, "prop": "shell", "p": {}},
				{"t": 0.5, "L": {"a": "port", "o": Vector3(0.0, -0.03, 0.03), "h": "under", "c": "shell"}},
				{"t": 0.68, "L": {"a": "port", "o": Vector3(0.0, -0.005, -0.02), "h": "under", "c": "shell"}},
				{"t": 0.7, "prop": ""},
				{"t": 0.76, "L": {"a": "port", "o": Vector3(-0.02, -0.04, 0.0), "h": "under", "c": "relaxed"}},
				{"t": 1.0, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "shell"}, "prop": "shell"},
			]
		"tube_end":
			var keys := [
				{"t": 0.0, "g": [Vector3(-0.03, -0.02, 0.04), Vector3(6.0, 6.0, -32.0)], "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "relaxed"}, "R": rest_r, "prop": "", "p": {}},
				{"t": 0.45, "g": [Vector3(-0.01, -0.01, 0.01), Vector3(2.0, 2.0, -8.0)], "L": {"a": "pmp", "o": Vector3.ZERO, "h": "pump", "c": "fore"}},
			]
			if empty:
				keys.append_array([
					{"t": 0.62, "L": {"a": "pmp", "o": Vector3(0, 0, 0.085), "h": "pump", "c": "fore"}, "p": {"pump": [Vector3(0, 0, 0.085), Vector3.ZERO]}},
					{"t": 0.78, "L": {"a": "pmp", "o": Vector3.ZERO, "h": "pump", "c": "fore"}, "p": {"pump": [Vector3.ZERO, Vector3.ZERO]}},
				])
			keys.append({"t": 1.0, "g": rest_g, "L": {"a": "pmp", "o": Vector3.ZERO, "h": "pump", "c": "fore"}})
			return keys
		"gate_start":
			return [
				{"t": 0.0, "g": rest_g, "L": {"a": "grip", "o": Vector3(-0.025, -0.02, 0.0), "h": "psup", "c": "cup"}, "R": rest_r, "p": {}, "prop": ""},
				{"t": 0.55, "g": [Vector3(-0.06, 0.04, 0.05), Vector3(18.0, 24.0, 18.0)]},
				{"t": 1.0, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "pinch"}, "prop": "round"},
			]
		"gate_insert":
			return [
				{"t": 0.0, "g": [Vector3(-0.06, 0.04, 0.05), Vector3(18.0, 24.0, 18.0)], "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "pinch"}, "R": rest_r, "prop": "round", "p": {"cylinder": [Vector3.ZERO, Vector3.ZERO]}},
				{"t": 0.55, "L": {"a": "gate", "o": Vector3(0.025, 0.0, 0.04), "h": "pinch", "c": "pinch"}},
				{"t": 0.72, "L": {"a": "gate", "o": Vector3(0.012, 0.0, 0.0), "h": "pinch", "c": "pinch"}},
				{"t": 0.74, "prop": ""},
				{"t": 0.8, "L": {"a": "gate", "o": Vector3(0.03, -0.02, 0.03), "h": "pinch", "c": "relaxed"}},
				{"t": 0.82, "p": {"cylinder": [Vector3.ZERO, Vector3.ZERO]}},
				{"t": 0.98, "p": {"cylinder": [Vector3.ZERO, Vector3(0, 0, 360.0 / 7.0)]}},
				{"t": 1.0, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "pinch"}, "prop": "round"},
			]
		"gate_end":
			return [
				{"t": 0.0, "g": [Vector3(-0.06, 0.04, 0.05), Vector3(18.0, 24.0, 18.0)], "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "relaxed"}, "R": rest_r, "prop": "", "p": {}},
				{"t": 1.0, "g": rest_g, "L": {"a": "grip", "o": Vector3(-0.025, -0.02, 0.0), "h": "psup", "c": "cup"}},
			]
		"break":
			return [
				{"t": 0.0, "g": rest_g, "L": rest_l, "R": rest_r, "p": {"barrel": [Vector3.ZERO, Vector3.ZERO]}, "prop": ""},
				{"t": 0.1, "g": [Vector3(-0.02, 0.02, 0.05), Vector3(-4.0, 6.0, -10.0)]},
				{"t": 0.22, "g": [Vector3(-0.03, 0.06, 0.08), Vector3(-14.0, 8.0, -14.0)], "p": {"barrel": [Vector3.ZERO, Vector3(-36.0, 0, 0)]}, "L": {"a": "sup", "o": Vector3(0.0, -0.06, 0.02), "h": "sup", "c": "fore"}},
				{"t": 0.28, "prop": "spent2"},
				{"t": 0.32, "L": {"a": "sup", "o": Vector3(-0.02, -0.12, 0.06), "h": "sup", "c": "relaxed"}},
				{"t": 0.46, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "shell"}, "prop": "shells2"},
				{"t": 0.62, "L": {"a": "brch", "o": Vector3(0.0, 0.05, -0.05), "h": "thumb", "c": "shell"}},
				{"t": 0.7, "L": {"a": "brch", "o": Vector3(0.0, 0.01, -0.02), "h": "thumb", "c": "shell"}},
				{"t": 0.71, "prop": "loaded2"},
				{"t": 0.76, "L": {"a": "sup", "o": Vector3(0.0, -0.08, 0.02), "h": "sup", "c": "fore"}},
				{"t": 0.84, "p": {"barrel": [Vector3.ZERO, Vector3.ZERO]}, "L": rest_l, "g": [Vector3(-0.02, 0.0, 0.03), Vector3(2.0, 4.0, -8.0)]},
				{"t": 0.85, "prop": ""},
				{"t": 1.0, "g": rest_g},
			]
		"pipe":
			return [
				{"t": 0.0, "g": rest_g, "L": rest_l, "R": rest_r, "p": {"barrel": [Vector3.ZERO, Vector3.ZERO]}, "prop": ""},
				{"t": 0.1, "g": [Vector3(-0.02, 0.0, 0.04), Vector3(6.0, 8.0, -10.0)], "L": {"a": "bar", "o": Vector3.ZERO, "h": "sup", "c": "fore"}},
				{"t": 0.24, "p": {"barrel": [Vector3(0, 0, -0.17), Vector3.ZERO]}, "L": {"a": "bar", "o": Vector3(0, 0, -0.17), "h": "sup", "c": "fore"}},
				{"t": 0.27, "prop": "spent1"},
				{"t": 0.42, "L": {"a": "pouch", "o": Vector3.ZERO, "h": "view_pouch", "c": "shell"}, "prop": "shell"},
				{"t": 0.58, "L": {"a": "bar_rear", "o": Vector3(0.0, 0.03, -0.17), "h": "thumb", "c": "shell"}},
				{"t": 0.66, "L": {"a": "bar_rear", "o": Vector3(0.0, 0.0, -0.17), "h": "thumb", "c": "shell"}},
				{"t": 0.67, "prop": ""},
				{"t": 0.72, "L": {"a": "bar", "o": Vector3(0, 0, -0.17), "h": "sup", "c": "fore"}},
				{"t": 0.86, "p": {"barrel": [Vector3.ZERO, Vector3.ZERO]}, "L": {"a": "bar", "o": Vector3.ZERO, "h": "sup", "c": "fore"}},
				{"t": 0.92, "L": rest_l},
				{"t": 1.0, "g": rest_g},
			]
		"cycle_pump":
			return [
				{"t": 0.0, "g": rest_g, "L": {"a": "pmp", "o": Vector3.ZERO, "h": "pump", "c": "fore"}, "R": rest_r, "p": {"pump": [Vector3.ZERO, Vector3.ZERO]}},
				{"t": 0.1, "g": [Vector3.ZERO, Vector3(-2.0, 0.0, -2.0)]},
				{"t": 0.42, "L": {"a": "pmp", "o": Vector3(0, 0, 0.085), "h": "pump", "c": "fore"}, "p": {"pump": [Vector3(0, 0, 0.085), Vector3.ZERO]}, "g": [Vector3(0.0, -0.01, 0.01), Vector3(-3.0, 0.0, -4.0)]},
				{"t": 0.82, "L": {"a": "pmp", "o": Vector3.ZERO, "h": "pump", "c": "fore"}, "p": {"pump": [Vector3.ZERO, Vector3.ZERO]}, "g": [Vector3.ZERO, Vector3(-1.0, 0.0, -1.0)]},
				{"t": 1.0, "g": rest_g},
			]
		"cycle_bolt":
			var keys := [{"t": 0.0, "g": rest_g, "L": rest_l, "R": rest_r, "p": {"bolt": [Vector3.ZERO, Vector3.ZERO]}}]
			keys.append_array(_bolt_cycle(0.02, 0.96))
			keys.append({"t": 1.0, "g": rest_g, "R": rest_r})
			return keys
	return [{"t": 0.0, "g": rest_g, "L": rest_l, "R": rest_r, "mag": "gun", "p": {}}]


static func _charge(side: String, t0: float) -> Array:
	## Empty reload: work the charging handle (left hand), between t0 and t0 + 0.28.
	match side:
		"right":
			return [
				{"t": t0 + 0.08, "L": {"a": "chg_r", "o": Vector3.ZERO, "h": "rack", "c": "pinch"}, "g": [Vector3(-0.03, -0.02, 0.03), Vector3(6.0, 4.0, 10.0)]},
				{"t": t0 + 0.15, "L": {"a": "chg_r", "o": Vector3(0, 0, 0.08), "h": "rack", "c": "pinch"}, "p": {"bolt": [Vector3(0, 0, 0.08), Vector3.ZERO]}},
				{"t": t0 + 0.18, "L": {"a": "chg_r", "o": Vector3(0.03, 0.03, 0.1), "h": "rack", "c": "open"}, "p": {"bolt": [Vector3.ZERO, Vector3.ZERO]}},
			]
		"front":
			return [
				{"t": t0 + 0.08, "L": {"a": "chg_f", "o": Vector3.ZERO, "h": "pinch", "c": "pinch"}},
				{"t": t0 + 0.15, "L": {"a": "chg_f", "o": Vector3(0, 0, 0.07), "h": "pinch", "c": "pinch"}},
				{"t": t0 + 0.18, "L": {"a": "chg_f", "o": Vector3(-0.03, 0.02, 0.0), "h": "pinch", "c": "open"}},
			]
	return [
		# The rifle comes off the cheek, forward and down, while the handle is worked: with it on the shoulder the
		# handle was 12 cm from the eye, the left forearm ran past the camera and the near plane cut it open.
		{"t": t0 + 0.08, "L": {"a": "chg_t", "o": Vector3.ZERO, "h": "pinch", "c": "pinch"}, "g": [Vector3(-0.04, -0.09, -0.13), Vector3(8.0, 6.0, -16.0)]},
		{"t": t0 + 0.15, "L": {"a": "chg_t", "o": Vector3(0, 0, 0.07), "h": "pinch", "c": "pinch"}, "p": {"bolt": [Vector3(0, 0, 0.07), Vector3.ZERO]}},
		{"t": t0 + 0.18, "L": {"a": "chg_t", "o": Vector3(-0.03, 0.03, 0.08), "h": "pinch", "c": "open"}, "p": {"bolt": [Vector3.ZERO, Vector3.ZERO]}},
	]


static func _bolt_cycle(t0: float, t1: float) -> Array:
	## Right hand leaves the grip, lifts the bolt handle, draws it back, runs it home and returns to the grip.
	var s := func(f: float) -> float: return t0 + (t1 - t0) * f
	return [
		{"t": s.call(0.16), "R": {"a": "bolt", "o": Vector3.ZERO, "h": "bolt", "c": "pinch"}, "g": [Vector3(0.0, -0.01, 0.01), Vector3(-2.0, 2.0, -6.0)]},
		{"t": s.call(0.28), "p": {"bolt": [Vector3.ZERO, Vector3(0, 0, 62)]}, "R": {"a": "bolt", "o": Vector3(-0.02, 0.035, 0.0), "h": "bolt", "c": "pinch"}},
		{"t": s.call(0.44), "p": {"bolt": [Vector3(0, 0, 0.085), Vector3(0, 0, 62)]}, "R": {"a": "bolt", "o": Vector3(-0.02, 0.035, 0.085), "h": "bolt", "c": "pinch"}},
		{"t": s.call(0.6), "p": {"bolt": [Vector3.ZERO, Vector3(0, 0, 62)]}, "R": {"a": "bolt", "o": Vector3(-0.02, 0.035, 0.0), "h": "bolt", "c": "pinch"}},
		{"t": s.call(0.7), "p": {"bolt": [Vector3.ZERO, Vector3.ZERO]}, "R": {"a": "bolt", "o": Vector3.ZERO, "h": "bolt", "c": "pinch"}},
		{"t": s.call(0.92), "R": {"a": "grip", "o": Vector3.ZERO, "h": "grip", "c": "pistol"}, "g": [Vector3.ZERO, Vector3.ZERO]},
	]


static func cues(kind: String, empty: bool, wid: String = "") -> Array:
	## The sounds of a clip as [normalised time, sound id], timed to the keys of clip() above (the hand reaches the
	## part, the part moves): played over the same length of time as the clip, they land on the motion.
	match kind:
		"mag_rifle":
			if empty:
				return [[0.17, "mag_out"], [0.33, "mag_pouch"], [0.555, "mag_in"], [0.72, "charge_back"], [0.775, "charge_release"]]
			return [[0.2, "mag_out"], [0.41, "mag_pouch"], [0.665, "mag_in"]]
		"mag_pistol":
			var out := [[0.11, "mag_out_pistol"], [0.34, "mag_pouch"], [0.6, "mag_in_pistol"]]
			if empty:
				out.append_array([[0.745, "slide_back"], [0.78, "slide_release"]])
			return out
		"mag_bolt":
			var out := [[0.16, "mag_out"], [0.36, "mag_pouch"], [0.585, "mag_in"]]
			if empty:
				out.append_array(_bolt_cues(0.64, 0.96))
			return out
		"clip_bolt":
			return [[0.14, "bolt_up"], [0.21, "bolt_back"], [0.36, "mag_pouch"], [0.6, "clip_in"], [0.67, "round_insert"],
				[0.8, "bolt_fwd"], [0.85, "bolt_down"]]
		"clip_semi":
			return [[0.19, "charge_back"], [0.36, "mag_pouch"], [0.6, "clip_in"], [0.67, "round_insert"], [0.775, "charge_release"]]
		"tube_start":
			return [[0.92, "mag_pouch"]]
		"tube_insert":
			return [[0.67, "shell_insert"]]
		"tube_end":
			return [[0.6, "pump_back"], [0.77, "pump_fwd"]] if empty else []
		"gate_start":
			return [[0.5, "cylinder_open"], [0.92, "mag_pouch"]]
		"gate_insert":
			return [[0.72, "round_insert"], [0.97, "cylinder_click"]]
		"gate_end":
			return [[0.25, "cylinder_close"]]
		"break":
			return [[0.21, "break_open"], [0.28, "shell_eject"], [0.44, "mag_pouch"], [0.7, "shell_insert"], [0.83, "break_close"]]
		"pipe":
			return [[0.22, "pipe_slide"], [0.27, "shell_eject"], [0.42, "mag_pouch"], [0.66, "shell_insert"], [0.85, "pipe_slide"]]
		"cycle_pump":
			return [[0.36, "pump_back"], [0.78, "pump_fwd"]]
		"cycle_bolt":
			return _bolt_cues(0.02, 0.96)
	return []


static func _bolt_cues(t0: float, t1: float) -> Array:
	## The bolt worked by hand (see _bolt_cycle): lifted, drawn back (the case flies), run home, turned down.
	var s := func(f: float) -> float: return t0 + (t1 - t0) * f
	return [[s.call(0.27), "bolt_up"], [s.call(0.42), "bolt_back"], [s.call(0.58), "bolt_fwd"], [s.call(0.69), "bolt_down"]]


static func clip_name(wid: String, phase: int, has: Dictionary) -> String:
	## The clip for reload phase `phase` (tube and gate loads step through start, one insert per round, end), or for the
	## action worked between shots when phase < 0.
	if phase < 0:
		return "cycle_pump" if "pump" in Defs.weapon(wid).get("fire_modes", []) else "cycle_bolt"
	var kind := reload_kind(wid, has)
	if kind in ["tube", "gate"]:
		return kind + ["_start", "_insert", "_end"][clampi(phase, 0, 2)]
	return kind


# ------------------------------------------------------------------ evaluation

static func filled(keys: Array) -> Array:
	## Every key with every channel (inherited from the key before), parts merged.
	var out := []
	var cur := {"g": [Vector3.ZERO, Vector3.ZERO], "L": {}, "R": {}, "p": {}, "mag": "gun", "prop": ""}
	for k in keys:
		var nk := {"t": float(k.t)}
		for ch in ["g", "L", "R", "mag", "prop"]:
			if k.has(ch):
				cur[ch] = k[ch]
			nk[ch] = cur[ch]
		var parts: Dictionary = (cur.p as Dictionary).duplicate()
		if k.has("p"):
			for r in k.p:
				parts[r] = k.p[r]
			if (k.p as Dictionary).is_empty():
				parts = {}
		cur.p = parts
		nk.p = parts
		out.append(nk)
	# Parts named later but not earlier rest at zero before they are first named.
	var roles := {}
	for k in out:
		for r in k.p:
			roles[r] = true
	for k in out:
		for r in roles:
			if not (k.p as Dictionary).has(r):
				k.p[r] = [Vector3.ZERO, Vector3.ZERO]
	return out


static func sample(keys: Array, t: float) -> Dictionary:
	## {a, b, f}: the two keys around t and the eased blend between them; discrete channels take key a's value.
	t = clampf(t, 0.0, 1.0)
	var i := 0
	while i < keys.size() - 1 and float(keys[i + 1].t) <= t:
		i += 1
	var a: Dictionary = keys[i]
	var b: Dictionary = keys[mini(i + 1, keys.size() - 1)]
	var span := float(b.t) - float(a.t)
	var f := 0.0 if span <= 1e-5 else clampf((t - float(a.t)) / span, 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	return {"a": a, "b": b, "f": f}


static func lerp_g(a: Array, b: Array, f: float) -> Array:
	return [(a[0] as Vector3).lerp(b[0], f), (a[1] as Vector3).lerp(b[1], f)]


static func hand_basis(h: String) -> Basis:
	var v: Array = HANDS.get(h, HANDS.sup)
	return FpArms.hand_basis(v[0], v[1])
