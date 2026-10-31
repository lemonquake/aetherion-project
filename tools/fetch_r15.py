"""Download the r15 assets for Malasugue Mall, the second Deathmatch map (floors, walls, wood, fabric; plants, seating,
cafe and shop props). Every entry is Poly Haven (CC0).

    python -I tools/fetch_r15.py [textures|models]

Every download gets a source.json; run `python -I tools/fetch_assets.py --manifest` afterwards to refresh
docs/ASSET_MANIFEST.md, then `bash tools/import.sh`.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fetch_assets  # noqa: E402

TEXTURES = {
    # concourse, atrium and shop floors
    'large_floor_tiles_02': '2k', 'granite_tile': '1k', 'marble_01': '2k', 'marble_mosaic_tiles': '1k',
    'floor_tiles_08': '1k', 'large_grey_tiles': '1k', 'rubber_tiles': '1k', 'anti_slip_concrete': '1k',
    # walls, joinery and upholstery
    'plastered_wall_02': '1k', 'oak_veneer_01': '1k', 'walnut_veneer': '1k', 'white_oak_veneer': '1k',
    'velour_velvet': '1k', 'brown_leather': '1k', 'wool_boucle': '1k', 'book_pattern': '1k',
    # outside: the drop-off plaza
    'hexagonal_concrete_paving': '1k',
}

MODELS = [
    # planting
    'potted_plant_04', 'pachira_aquatica_01', 'calathea_orbifolia_01', 'anthurium_botany_01', 'planter_box_02',
    'planter_box_03',
    # seating and tables (food court, cafes, lounges)
    'bar_chair_round_01', 'coffee_table_round_01', 'round_wooden_table_02', 'gallinera_chair', 'gallinera_table',
    'mid_century_lounge_chair', 'sofa_03', 'Ottoman_01', 'modern_coffee_table_01', 'side_table_tall_01',
    # shops and kiosks
    'CoffeeCart_01', 'BarberShopChair_01', 'ceramic_vase_01', 'ceramic_vase_03', 'brass_vase_01', 'boombox',
    'television_02', 'modern_ceiling_lamp_01', 'Chandelier_01', 'fire_alarm', 'bronze_whale_statue',
]


def main():
    want = set(sys.argv[1:]) or {'textures', 'models'}
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
    if fails:
        print('\nFAILURES:\n  ' + '\n  '.join(fails))


if __name__ == '__main__':
    main()
