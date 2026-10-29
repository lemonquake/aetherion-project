extends RefCounted
## Lawless Sub: builds every lot of the layout, in the layout's order (big buildings first, then the house rows in
## plan order), so doors, windows, containers and props get the same indices on every machine. House-like lots go to
## Houses.build(mb, lot), the rest to BigBuildings.build(mb, lot). Both are replaceable modules with that one entry
## point (see work/lemondev/r7/map/INTERFACE.md).

const Houses := preload("res://src/world/maps/lawless_sub/houses.gd")
const BigBuildings := preload("res://src/world/maps/lawless_sub/big_buildings.gd")
const FacadeDetail := preload("res://src/world/maps/lawless_sub/facade_detail.gd")
const LandmarkDetail := preload("res://src/world/maps/lawless_sub/landmark_detail.gd")
const HOUSE_KINDS := ["house", "shophouse"]


static func build_all(mb, layout) -> void:
	var i := 0
	for lot in layout.lots:
		i += 1
		if Game.loading_screen and i % 6 == 1:
			Game.load_progress(lerpf(0.3, 0.68, float(i) / maxf(layout.lots.size(), 1)), "Building houses (%d of %d)" % [i, layout.lots.size()])
		if str(lot.kind) in HOUSE_KINDS:
			Houses.build(mb, lot)
		else:
			BigBuildings.build(mb, lot)
	if Game.loading_screen:
		Game.load_progress(0.7, "Hanging gutters, meters and aircon units")
	FacadeDetail.build_all(mb, layout)
	LandmarkDetail.build_all(mb, layout)
