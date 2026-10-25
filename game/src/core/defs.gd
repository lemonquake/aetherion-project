extends Node
## Data-driven definitions loaded from res://data/*.json. Read-only after load.

const PHYS_WORLD := 1
const PHYS_CHAR := 2
const PHYS_PROP := 4
const PHYS_GLASS := 8
const PHYS_INTERACT := 16
const PHYS_WATER := 32
const PHYS_DEBRIS := 64
const PHYS_CORPSE := 128
const PHYS_FOLIAGE := 256
const PHYS_PROJ_ONLY := 512
const PHYS_BLOCKER := 1024  ## blocks movement only (window bars, chain-link)

## Everything a bullet can hit in the world (characters are tested analytically).
const SHOT_MASK := PHYS_WORLD | PHYS_PROP | PHYS_GLASS | PHYS_WATER | PHYS_CORPSE | PHYS_PROJ_ONLY
## Everything that blocks movement.
const MOVE_MASK := PHYS_WORLD | PHYS_PROP | PHYS_GLASS | PHYS_BLOCKER
## Everything that blocks sight and interaction rays.
const SIGHT_MASK := PHYS_WORLD | PHYS_PROP | PHYS_GLASS

const RENDER_WORLD := 1
const RENDER_VIEWMODEL := 2
const RENDER_LOCAL_BODY := 4
const RENDER_CHARACTERS := 8

const TICK_RATE := 60
const TICK_DT := 1.0 / 60.0

const PARTS: Array[String] = ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]

var ballistics: Dictionary = {}
var weapons: Dictionary = {}
var attachments: Dictionary = {}
var items: Dictionary = {}
var carry: Dictionary = {}
var flashlight: Dictionary = {}
var health: Dictionary = {}
var loot: Dictionary = {}
var rules: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	ballistics = _load("res://data/ballistics.json")
	var w := _load("res://data/weapons.json")
	weapons = w.get("weapons", {})
	attachments = w.get("attachments", {})
	var it := _load("res://data/items.json")
	items = it.get("items", {})
	carry = it.get("carry", {})
	flashlight = it.get("flashlight", {})
	health = it.get("health", {})
	loot = _load("res://data/loot.json")
	rules = _load("res://data/rules.json")


func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Defs: cannot open %s" % path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Defs: invalid JSON in %s" % path)
		return {}
	return data


func ammo(id: String) -> Dictionary:
	return ballistics.get("ammo", {}).get(id, {})


func material(id: String) -> Dictionary:
	var mats: Dictionary = ballistics.get("materials", {})
	return mats.get(id, mats.get("default", {}))


func weapon(id: String) -> Dictionary:
	return weapons.get(id, {})


func item(id: String) -> Dictionary:
	if weapons.has(id):
		var w: Dictionary = weapons[id]
		return {"name": w.name, "kind": "weapon", "mass": w.get("mass", 3.0), "model": w.get("model", id)}
	return items.get(id, {})


func is_weapon(id: String) -> bool:
	return weapons.has(id)


func item_name(id: String) -> String:
	return str(item(id).get("name", id))


func rule(path: String, default_value = null):
	## Dotted lookup into rules.json, e.g. rule("deploy.chute_descent", 5.0).
	var node = rules
	for key in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(key):
			return default_value
		node = node[key]
	return node


func move(key: String) -> float:
	return float(rules.get("movement", {}).get(key, 0.0))
