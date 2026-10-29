extends RefCounted
## Lawless Sub: builds every lot of the layout, in the layout's order (big buildings first, then the house rows in
## plan order), so doors, windows, containers and props get the same indices on every machine. House-like lots go to
## Houses.build(mb, lot), the rest to BigBuildings.build(mb, lot). Both are replaceable modules with that one entry
## point (see work/lemondev/r7/map/INTERFACE.md).

const Houses := preload("res://src/world/maps/lawless_sub/houses.gd")
const BigBuildings := preload("res://src/world/maps/lawless_sub/big_buildings.gd")
const HOUSE_KINDS := ["house", "shophouse"]


static func build_all(mb, layout) -> void:
	for lot in layout.lots:
		if str(lot.kind) in HOUSE_KINDS:
			Houses.build(mb, lot)
		else:
			BigBuildings.build(mb, lot)
