"""Download the r7 assets for the Lawless Sub deathmatch map (textures, furniture, store and factory props, cars).

    python -I tools/fetch_r7.py [textures|models|sketchfab ...]

Poly Haven entries are CC0; Sketchfab entries come from the Objaverse mirror and fetch_assets.sketchfab refuses any
licence other than CC-BY or CC0 (checked against the Sketchfab API). Every download gets a source.json; run
`python -I tools/fetch_assets.py --manifest` afterwards to refresh docs/ASSET_MANIFEST.md.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fetch_assets  # noqa: E402

TEXTURES = {
    # streets, lots, canals
    'asphalt_04': '2k', 'asphalt_06': '2k', 'clean_asphalt': '1k', 'concrete_pavers': '2k',
    'interlocking_concrete_pavers': '1k', 'grooved_concrete_driveway': '1k', 'concrete_wall_007': '2k',
    'concrete_panels': '1k', 'concrete_tile_facade': '1k', 'grass_path_2': '1k', 'grass_ground': '1k', 'aerial_grass_rock': '1k',
    # houses
    'clay_roof_tiles_02': '2k', 'grey_roof_tiles': '1k', 'beige_wall_002': '1k', 'grey_plaster': '1k',
    'painted_brick': '1k', 'brick_wall_006': '1k', 'exterior_wall_cladding_03': '1k',
    'laminate_floor_02': '1k', 'herringbone_parquet': '1k', 'interior_tiles': '1k', 'long_white_tiles': '1k',
    'marble_tiles': '1k', 'patio_tiles': '1k',
    # factory
    'factory_wall': '2k', 'hangar_concrete_floor': '2k', 'factory_brick': '1k', 'metal_plate': '1k',
    'blue_metal_plate': '1k',
}

MODELS = [
    # houses and the clubhouse
    'ArmChair_01', 'Sofa_01', 'sofa_02', 'CoffeeTable_01', 'dining_chair_02', 'dining_table', 'side_table_01',
    'modern_wooden_cabinet', 'ClassicNightstand_01', 'potted_plant_01', 'potted_plant_02', 'modern_arm_chair_01',
    'vintage_cabinet_01', 'WoodenTable_02',
    # convenience store
    'wooden_display_shelves_01', 'steel_frame_shelves_03', 'worn_metal_rack', 'WetFloorSign_01',
    'korean_public_payphone_01', 'security_camera_01', 'long_life_food', 'russian_food_cans_01', 'bleach_bottle',
    'multi_cleaner_bottle',
    # factory
    'industrial_storage_cart', 'modular_airduct_rectangular_01', 'Barrel_02', 'industrial_pastic_container',
    'old_military_compressor', 'industrial_caged_sconce', 'industrial_wall_lamp', 'concrete_road_barrier_02',
    # street
    'modular_street_seating', 'large_iron_gate', 'planter_box_01', 'garden_gnome',
]

SKETCHFAB = {
    'car_generic_pack': ('20f9af9b8a404d5cb022ac6fe87f21f5', 'parked cars (generic passenger car pack)'),
    'car_burned_out': ('701066df6b914fd08318524c7ccd96a7', 'burnt-out car wrecks'),
    'car_corolla': ('aab1b90a73f7416890c31a8927cc5038', 'old saloon car'),
    'car_negotiator': ('892b2684fb37442299bfad9222cf331c', '1980s saloon car'),
    'car_fairheaven': ('e2678da920cc4be68dbc193727919ffb', '1980s saloon car'),
    'car_shvan_van': ('09d718c9cf72401b8534d265a06a803f', 'delivery van'),
    'car_doutrive_pickup': ('30700a84311c4bea9ef722f0773ce92a', 'pickup truck'),
    'car_police_burned': ('ad16f7085cb047b494997cf9efed5059', 'burnt police cars'),
    'jeepney': ('0b8bcde5df19458da9fa5606989b1e7d', 'Philippine jeepney (stalled on the avenue)'),
    'jeepney_b': ('4066504694c346c097a229de0fff1728', 'Philippine jeepney (alternative)'),
    'vending_outdoor': ('d0b81fdb4e514859bfcc95165144e8c7', 'outdoor vending machines'),
    'fridge_display': ('752942069dcf4969a43af1e4fa9c4b4d', 'store chiller with glass doors'),
    'grocery_case': ('2b777f898a3d4ee9bf124390f0440b31', 'grocery display case'),
    'shelf_etagere': ('ef66dd1df6884157ad19f58c73de389a', 'store shelving'),
    'forklift': ('81b895de490646de8c6fb1ba03099e08', 'factory forklift'),
    'forklift_b': ('8ab650b3982243f8b661142de50f79c9', 'factory forklift (alternative)'),
    'chemical_tank': ('63c001e74ff5402fbcf1338479c9c0c5', 'factory storage tank'),
    'conveyor': ('55f0d0f9b3384ea4b49cfc8aef97dcf9', 'factory conveyor belt'),
    'control_panel': ('00f665c4abc04d48bdcb430131bc5b73', 'factory control panel'),
    'basketball_hoop': ('d3fc2490cbe54e37b6d5b159704c787f', 'basketball hoop (clubhouse court)'),
    'slide_abandoned': ('11de2b21ec264c0a814ac024c45ab425', 'playground slide'),
    'playground_abandoned': ('fee40d7bf3e24de5b694d7aa3486066a', 'playground set'),
    'traffic_light': ('ab3efdd259a54d4aba5f878eacbe3f20', 'traffic lights at the intersection'),
    'gas_pump': ('b983f3959db641ef8b2870489de95b04', 'gas station pump'),
    'gas_pump_b': ('4354327e7c52491f9dda58bb2fc0b375', 'gas station pump (alternative)'),
    'aircon_condenser': ('940781484cb64c6db6c615473bee996a', 'house air-conditioner outdoor unit'),
}


def main():
    want = set(sys.argv[1:]) or {'textures', 'models', 'sketchfab'}
    fails = []
    if 'textures' in want:
        for k, res in TEXTURES.items():
            try:
                print('texture', k, fetch_assets.ph_texture(k, res), flush=True)
            except Exception as e:  # keep going
                fails.append(f'texture {k}: {e}')
                print('texture', k, 'FAILED', e, flush=True)
    if 'models' in want:
        for k in MODELS:
            try:
                print('model', k, fetch_assets.ph_model(k, '1k'), flush=True)
            except Exception as e:
                fails.append(f'model {k}: {e}')
                print('model', k, 'FAILED', e, flush=True)
    if 'sketchfab' in want:
        for n, (uid, purpose) in SKETCHFAB.items():
            try:
                print('sketchfab', n, fetch_assets.sketchfab(n, uid, purpose), flush=True)
            except Exception as e:
                fails.append(f'sketchfab {n}: {e}')
                print('sketchfab', n, 'FAILED', e, flush=True)
    if fails:
        print('\nFAILURES:\n  ' + '\n  '.join(fails))


if __name__ == '__main__':
    main()
