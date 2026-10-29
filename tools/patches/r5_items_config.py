"""r5: new gun sources and named moving parts in process_items.py ITEMS."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'tools', 'blender', 'process_items.py')
s = open(p, 'rb').read().decode()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')
a = s.index('ITEMS = {')
b = s.index('\n}\n', a) + 3
NEW = '''ITEMS = {
    # objs: {part: [substrings of source object names]}; boxes: {part: [[u0, u1, v0, v1], ...]} (see split_boxes); parts
    # are the pieces the first-person animations move: mag, slide, bolt, pump, cylinder, barrel, cover.
    'pistol_9': dict(src='pistol_92fs', length=0.217, gun=True, tris=9000),
    'pistol_45': dict(src='pistol_1911', length=0.216, gun=True, tris=9000),
    'revolver_357': dict(src='revolver_nagant', length=0.235, gun=True, tris=9000, drop=['Chain'],
                         objs={'cylinder': ['Drum', 'Case', 'Projectile']}),
    'shotgun_pump': dict(src='shotgun_870', length=1.0, gun=True, tris=10000),
    'smg_9': dict(src='smg_mp5', length=0.68, gun=True, tris=10000, keep=['Object_9'], rot=(-10, 0, 0)),
    'machine_pistol': dict(src='smg_microuzi', length=0.27, gun=True, tris=8000, drop=['shell'],
                           objs={'mag': ['magazine'], 'slide': ['slide']}),
    'rifle_556': dict(src='rifle_m16', length=1.0, gun=True, tris=12000,
                      objs={'mag': ['MAGAZINE'], 'bolt': ['CHANRIGN HANDLE', 'BOLT CARRIER']}),
    'rifle_762': dict(src='rifle_ak', length=0.88, gun=True, tris=12000),
    'sight_reddot': dict(src='sight_reddot', length=0.09, gun=False, tris=4000),
    'sight_holo': dict(src='sight_holo', length=0.1, gun=False, tris=4000),
    'scope_4x': dict(src='scope_acog', length=0.16, gun=False, tris=5000),
    'flashlight': dict(src='flashlight_tactical', length=0.15, gun=True, tris=4000, flip=True),
    'helmet_light': dict(src='helmet_light', length=0.29, gun=False, tris=6000),
    'helmet_heavy': dict(src='helmet_heavy', length=0.31, gun=False, tris=7000),
    'vest_light': dict(src='vest_military', length=0.62, gun=False, tris=9000),
    'vest_heavy': dict(src='vest_combat', length=0.66, gun=False, tris=10000),
    'first_aid': dict(src='first_aid_kit', length=0.26, gun=False, tris=4000),
    'radio': dict(src='walkie_talkie', length=0.21, gun=False, tris=3000),
    # 2026-10-27 weapon variety (see tools/patches/p83_weapon_sources.py).
    'rifle_scar': dict(src='rifle_scar', length=0.89, gun=True, tris=12000, drop=['Icosphere']),
    'rifle_m416': dict(src='rifle_m416', length=0.84, gun=True, tris=12000),
    'rifle_m762': dict(src='rifle_beryl_tt', length=0.94, gun=True, tris=12000, drop=['Icosphere']),
    'dmr_mini14': dict(src='dmr_mini14', length=0.95, gun=True, tris=10000),
    'dmr_sks': dict(src='dmr_sks', length=1.02, gun=True, tris=10000),
    'bolt_kar98': dict(src='bolt_kar98', length=1.11, gun=True, tris=10000),
    'smg_ump45': dict(src='smg_ump45', length=0.69, gun=True, tris=10000, flip=True, objs={'mag': ['mazagine']}),
    'smg_vector': dict(src='smg_vector_c', length=0.62, gun=True, tris=10000, objs={'mag': ['Magazine']}),
    'smg_tommy': dict(src='smg_thompson', length=0.81, gun=True, tris=12000),
    'lmg_m249': dict(src='lmg_m249', length=1.04, gun=True, tris=12000),
    'shotgun_saiga': dict(src='shotgun_saiga', length=0.97, gun=True, tris=10000),
    'pistol_deagle': dict(src='pistol_deagle', length=0.27, gun=True, tris=9000, drop=['BulletCase', 'Bullet_low'],
                          objs={'slide': ['Slide_low_Slide', 'FrontSight_low', 'RearSight_low', 'Safety_low', 'BoltMain',
                                          'BoltAdd', 'SlidePart', 'BoltButton', 'BoltBack'],
                                'mag': ['_Magazine_0']}),
    # 2026-10-28 (r5): downloaded models replace the code-built S686, Sumpak and SLR and the decimated Poly Haven
    # P92 / M24 stand-ins, and the blocky UZI, Tommy, Beryl and revolver.
    'shotgun_double': dict(src='shotgun_db_schris', length=1.05, gun=True, tris=9000),
    'sumpak': dict(src='shotgun_pipe_ph', length=0.95, gun=True, tris=4000),
    'marksman_308': dict(src='rifle_fal', length=1.09, gun=True, tris=12000),
    'bolt_308': dict(src='bolt_m24', length=1.09, gun=True, tris=12000,
                     drop=['Scope', 'BIpod Mount', 'Bipod', '7.62x51', 'Sling Mount'],
                     objs={'mag': ['Magazine'], 'bolt': ['Charging Handle', 'Bolt_Bolt Back']}),
}
'''
s = s[:a] + NEW + s[b:]
open(p, 'wb').write(s.replace('\n', nl).encode())
print('patched')
