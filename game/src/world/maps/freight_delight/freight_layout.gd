extends "res://src/world/maps/authored/authored_layout.gd"
## Freight Delight, a Deathmatch map for two teams of up to 12: a squatter settlement grown inside an old container
## yard by the port, always at night.
##
## Unlike the generated maps, its geometry is authored: res://assets/maps/freight_delight.map (TrenchBroom, Valve
## 220), imported by addons/aetherion_map into a scene and placed in res://assets/maps/freight_delight.tscn, which
## is what loads here (anything added to that scene in Godot comes along). This layout reads what the scene carries:
## the team spawns (info_team_spawn), the landmarks, the stair flights (func_stairs) and every solid brush as planes,
## from which it surveys the two walk grids the bots use (ground, y = 0, and the second floor, y = FH) and links them
## at the three stairs.
## Plan (x east, z south, metres): West Team spawns on the fish pier (x ~ -52), East Team at the truck gate (x ~ 52);
## the Container Canyon to the north, the Bodega / crane plaza / Talyer in the middle, the Eskinita shanties to the
## south; the second floor is the inner container row's deck, the plaza bridges and crane platform, the Bodega
## mezzanine and the Taas.

const SCENE_PATH := "res://assets/maps/freight_delight.tscn"


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	MAP_ID = "freight_delight"
	FH = 3.2
	LEVELS = 2
	HALF = 70.0
	PLAY_HALF = 62.0
	edge = 62.0
	bounds = Rect2(-62.0, -42.0, 124.0, 84.0)
	designated = _freight_spots()
	var ps: PackedScene = load(SCENE_PATH)
	if ps == null:
		push_error("[freight] %s did not load (is the .map imported? run tools/import.sh)" % SCENE_PATH)
		return
	load_scene(ps.instantiate())


func _freight_spots() -> Array:
	## (r21) The places this yard offers bots by design (BotNav looks each one round): the deck ends, the crane platform
	## and the Bodega mezzanine look out over the yard (snipe); the Taas rooms, the container homes and the through-homes
	## are rooms to wait in (hide).
	var mid := Vector3(0.0, 0.0, 0.0)
	return [
		{"p": Vector3(-34.0, 3.2, -12.6), "kind": "snipe", "face": Vector3(-10.0, 1.0, 0.0), "name": "Bodega mezzanine"},
		{"p": Vector3(-34.5, 3.2, -28.4), "kind": "snipe", "face": Vector3(0.0, 1.0, -28.0), "name": "deck, west end"},
		{"p": Vector3(1.5, 3.2, -28.4), "kind": "snipe", "face": mid, "name": "deck, middle"},
		{"p": Vector3(33.5, 3.2, -28.4), "kind": "snipe", "face": Vector3(0.0, 1.0, -28.0), "name": "deck, east end"},
		{"p": Vector3(2.6, 3.2, 0.0), "kind": "snipe", "face": Vector3(30.0, 1.0, 0.0), "name": "crane platform"},
		{"p": Vector3(-4.0, 3.2, 23.7), "kind": "snipe", "face": Vector3(0.0, 1.0, 0.0), "name": "Taas balcony"},
		{"p": Vector3(37.6, 3.2, -15.0), "kind": "snipe", "face": Vector3(10.0, 1.0, -6.0), "name": "container stack by the Talyer"},
		{"p": Vector3(8.0, 3.2, 17.3), "kind": "hide", "name": "Taas corridor"},
		{"p": Vector3(10.5, 3.2, 20.8), "kind": "hide", "name": "Taas east room"},
		{"p": Vector3(-32.5, 0.42, -27.3), "kind": "hide", "name": "container home"},
		{"p": Vector3(21.2, 0.42, -28.6), "kind": "hide", "name": "through-home in the inner row"},
		{"p": Vector3(36.2, 0.09, 19.0), "kind": "hide", "name": "through-shanty, east"},
		{"p": Vector3(-36.2, 0.09, 19.0), "kind": "hide", "name": "through-shanty, west"},
		{"p": Vector3(40.0, 0.03, 8.0), "kind": "hide", "name": "Talyer office"},
		{"p": Vector3(-18.0, 0.0, 5.0), "kind": "hide", "name": "sari-sari store"},
	]
