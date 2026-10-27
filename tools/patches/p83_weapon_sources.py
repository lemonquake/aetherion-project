"""New gun models (user, 2026-10-27: "download more weapons, make sure we have a variety"): CC-BY Sketchfab models
mirrored in Objaverse, picked with tools/sketchfab_search.py. `_b` entries are fallbacks if the first looks wrong."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

NEW = [
    ('rifle_scar', 'b1e821e1e3464bdca3b34531c06f2952', 'SCAR-L 5.56 assault rifle'),
    ('rifle_scar_b', 'e8b99b8c0b754d8e95ca21c49009e7aa', 'SCAR-L 5.56 assault rifle (alternative)'),
    ('rifle_m416', 'c4af2388345b47b995cd5daa8531bde2', 'M416 5.56 assault rifle'),
    ('rifle_m416_b', '4bdb0ab5effd4474a5984c68b0a0c762', 'M416 5.56 assault rifle (alternative: HK416)'),
    ('dmr_mini14', '2e6bd2adb0234b3fa627f451e17f1d6b', 'Mini 14 5.56 marksman rifle'),
    ('pistol_deagle', 'cabde59f5cf24effaf80536e35d04e95', 'Desert Eagle .50 AE pistol'),
    ('pistol_deagle_b', 'b81da261345f4462b2c4412352162287', 'Desert Eagle .50 AE pistol (alternative)'),
    ('bolt_kar98', 'e88c90c8e203401fa28e8f4ef03e657f', 'Kar98k bolt-action rifle'),
    ('bolt_kar98_b', 'd2e0c38707c742d88ed4bd85df4ec8bf', 'Kar98k bolt-action rifle (alternative)'),
    ('dmr_sks', 'e6427acd6cc54b588d13cfc12fd373d8', 'SKS 7.62x39 marksman rifle'),
    ('dmr_sks_b', 'ea48b79acd354e4d8aa5ac901218ae5e', 'SKS 7.62x39 marksman rifle (alternative)'),
    ('smg_ump45', '152fc06d0f484056a3748f3c10771a1b', 'UMP45 .45 submachine gun'),
    ('smg_ump45_b', '53ec6320f1c84960a5d49fa0b7a11480', 'UMP45 .45 submachine gun (alternative)'),
    ('smg_vector', 'ec2fb60fecaf4aea94b681a52ec7bc26', 'Vector 9mm submachine gun'),
    ('smg_vector_b', '79c37c9eedc444d8a146043045e7cf3e', 'Vector 9mm submachine gun (alternative)'),
    ('smg_tommy', 'fad89d93472b4146ade0701ff4173d0e', 'Tommy gun .45 submachine gun'),
    ('smg_tommy_b', '914b7507bfc0400192f68a0b32183e02', 'Tommy gun .45 submachine gun (alternative)'),
    ('lmg_m249', 'bf0105376a2d4c37926f3ce95316460d', 'M249 5.56 light machine gun'),
    ('lmg_m249_b', 'b1e60faa37de4461822103fe38e5c9ce', 'M249 5.56 light machine gun (alternative)'),
    ('shotgun_saiga', '15b495fd2f9344ff9bd35a77628844d7', 'Saiga 12 gauge semi-automatic shotgun'),
    ('shotgun_saiga_b', '68598a9575f9429e8d37e67af4174d85', 'Saiga 12 gauge shotgun (alternative)'),
    ('rifle_m762', '57c1744d3fbf4c758dbcaabc5c05089b', 'M762 7.62x39 assault rifle'),
]

p = Patch('tools/asset_sources.json')
if '"rifle_scar"' not in p.s:
    lines = ',\n'.join('    "%s": {"uid": "%s", "purpose": "%s"}' % e for e in NEW)
    p.rep('''    "first_aid_kit_b": {"uid": "5a8e5955aa1f4cab89bca44c279349a8", "purpose": "medical kit item (alternative)"}
  },''', '''    "first_aid_kit_b": {"uid": "5a8e5955aa1f4cab89bca44c279349a8", "purpose": "medical kit item (alternative)"},
''' + lines + '''
  },''')
    p.save()
