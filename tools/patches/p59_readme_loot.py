"""README: loot, loot boxes, weapons and attachments, the SmarTab Weapons page, and the loot tools and tests.

    python -I tools/patches/p59_readme_loot.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'README.md')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep('''### Phones, PCs and cross-play
''', '''### Loot, weapons and attachments

Loot lies where people would leave it: loose on floors (guns, ammunition, attachments, medicine, batteries,
armour, packs), in drawers, cabinets and wardrobes, and in **loot boxes** you can see: balikbayan boxes, storage
bins, footlockers and rifle cases in houses, iceboxes in kitchens, at the market and on the fish pier, toolboxes and
ammo cans in workshops, first aid cases in clinics and comfort rooms, ammo cans and rifle cases at police posts and
in the container yard. Use (E) on a box opens its contents on the SmarTab; its lid stays open for everyone, so an
opened box tells you somebody has been there. A gun found loose usually has some of its own ammunition beside it.

Twelve guns: 9 mm and .45 pistols, .357 revolver, pump and double-barrel shotguns, the *sumpak* (an improvised
12-gauge pipe gun), 9 mm SMG and machine pistol, 5.56 and 7.62 rifles, a .308 marksman rifle and a .308 bolt rifle.
Each takes one attachment per mount, as listed in `game/data/weapons.json`:

| Mount | Attachments |
|---|---|
| Sight | red dot, holographic (1x, reticle in the sight window); 2x, 3x, 4x, 6x, 8x scopes (scope view while aiming) |
| Muzzle | pistol/SMG suppressor, rifle suppressor (much quieter, no flash), compensator (less recoil, louder), flash hider, shotgun choke (tighter pattern) |
| Grip | vertical (less climb), angled (faster aiming), half grip (faster recovery), laser sight (tighter hip fire; its red dot is visible to everyone) |
| Magazine | extended, quickdraw, extended quickdraw (pistol/SMG and rifle), extended marksman |
| Stock | tactical stock (machine pistol), cheek pad (marksman and bolt rifle), bullet loops (shotguns, bolt rifle) |
| Light | weapon light |

Picking up an attachment fits it to the gun that gains most from it (what it replaces goes in the bag); picking up a
gun fits the compatible attachments you carry. The SmarTab **Weapons** page lists each gun's mounts with **Fit** and
**Off** buttons. Other players see your attachments, and hear and see a suppressed shot as such.

Bots loot the same way: a gun first, then ammunition for the guns they carry, attachments that improve them, armour,
a bigger bag, medicine and batteries; they walk to loose items they see and search loot boxes, leave ammunition they
cannot fire, and pick the gun that suits the distance.

### Phones, PCs and cross-play
''')
rep('''Frame-rate benchmark through a real deploy and six ground spots''', '''Loot play-through (model census, loot boxes and floor loot across the map, items resting on surfaces, each
attachment's effect, pickups that fit attachments, a loot box opening, sights on the bullet line, scope views, and
photographs of every droppable item laid out):

```bash
godot --path game -- --host --bots=11 --autostart=1 --autotest=loot --shots=<folder>
```

The bot-match log prints a `[lootstats]` line every 15 s: bots armed, armed with ammunition for their gun,
attachments fitted, and rounds of ammunition carried that fit no gun they hold.

On Windows, `powershell -ExecutionPolicy Bypass -File tools/run_timed.ps1 -Seconds 600 -Log <file> -ArgLine "..."`
runs any of these with a time limit that also stops the engine process (bash `timeout` stops only the console
wrapper, and the server keeps its port).

Frame-rate benchmark through a real deploy and six ground spots''')
rep('''## Building the Windows EXE and the Android APK''', '''## Rebuilding the loot models and sounds

The attachments, small items, ammunition boxes, loot boxes and the double-barrel, sumpak and marksman rifle are
modelled in code (no downloads):

```bash
python -I tools/make_loot_textures.py                                            # labels and surfaces
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/make_loot_models.py
bash tools/import.sh
python -I tools/build_audio.py --suppressed                                       # suppressed gunshots only
```

Check renders of every model go to `work/loot_models/`.

## Building the Windows EXE and the Android APK''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())
print('ok')
