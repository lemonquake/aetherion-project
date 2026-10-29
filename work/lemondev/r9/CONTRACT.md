# Component Contract — r9: Player Model, Rig, Gear & Third-Person IK Overhaul

## Goal
Fix all broken player model geometry, rigging/skinning defects, outfit clipping/culling, and third-person weapon-holding IK / upper-body aim posing using Blender 5.2 and Godot 4.7.2 to achieve a cohesive Counter-Strike-caliber third-person player visual across all outfits, animations, weapons, and death ragdolls. Then build and verify the Windows EXE and Android APKs.

## Root Causes Addressed
1. **Sliced-Off Arm Tops (`tools/blender/make_gear.py`)**: Infinite X-axis `bisect_plane` neckline cuts at `z = 1.49..1.515` sliced off the upper half of both arms in T-pose (`skin_upperarm`, `skin_forearm`, `skin_torso`, `shirt_*`). When arms rotate forward to hold a weapon, back-face culling (`cull_back`) hides the open interior trough, making arms disappear or collapse into thin splinters.
2. **Baggy Hoodie Artifacts & Destructive Decimation (`tools/blender/make_gear.py`)**: Shrinking `stranger.glb`'s baggy hoodie (`limb=0.62`) and running `DECIMATE` (`0.45`) left broomstick-thin arms (`4.6 cm`), embossed kangaroo-pocket lumps on bare skin and shirts, leftover hood collar stubs on non-hoodie jackets, open waist/neck gaps (`z=0.98` vs `z=1.02`), and bare toes inside sneakers.
3. **Floating Elbow/Knee Pad Rings & Crude Box Accessories (`tools/blender/make_gear.py`)**: `pad()` failed to flip inner-shell normals (`pass` instead of `ff.normal_flip()`) and generated oversized `0.062..0.098 m` rings oriented along `+Y`, leaving two floating rings hanging below the chest in armed poses. Helmets, face gear, gloves, boots, and backpacks were crude low-poly boxes/ellipsoids.
4. **Broken Arm IK, Missing Clavicle Reach, Wrist Twist & Static Spine Pitch (`game/src/player/character_visual.gd`, `stranger.glb`)**:
   - `model.rotation.y = PI` flips local X (`upper_arm.L` at `X = -0.19`, `upper_arm.R` at `X = +0.19`).
   - `_hand_l` was `0.672 m` from `upper_arm.L` while total arm reach (`0.28 + 0.26 m`) is `0.54 m`, causing hyper-extended locked left arms falling short of the rifle handguard.
   - `TwoBoneIK3D` without deterministic pole/twist alignment caused ~160° candy-wrapper forearm twist and left wrists/hands unaligned with weapon grips, while `body_head` hands in `stranger.glb` had wide-splayed flat T-pose fingers.
   - Upper spine/chest/head did not pitch with `ch.pitch`, causing the rifle stock and `DmVest` to clip and desynchronize when aiming up/down.

## Sub-Components & Contracts

### 1. Base Rig & Mesh (`game/assets/models/characters/stranger.glb`)
- **Invariants**:
  - Preserve exact 24-bone hierarchy and bone names (`root`, `hips`, `spine`, `chest`, `neck`, `head`, `shoulder.L/R`, `upper_arm.L/R`, `forearm.L/R`, `hand.L/R`, `weapon.L/R`, `thigh.L/R`, `shin.L/R`, `foot.L/R`, `toe.L/R`) and all 39 animations (`corpse.gd` and `character_visual.gd` compatibility).
- **Upgrades**:
  - Pose/sculpt the hands in `body_head` into a natural tactical semi-curled grip/relaxed contour (thumb opposed, fingers naturally curved rather than stiff T-pose splay) with clean wrist seam alignment and smooth skin weights.
  - Ensure `body_head` neck base extends cleanly under shirt/jacket collars with zero gap.

### 2. Anatomical Body & Tactical/Streetwear Gear (`tools/blender/make_gear.py` -> `game/assets/models/gear/gear.glb`)
- **Invariants**:
  - Preserve all mesh node names required by `game/data/cosmetics.json` and `game/src/player/outfit.gd` (`skin_torso`, `skin_upperarm`, `skin_forearm`, `skin_thigh`, `skin_shin`, `skin_feet`, and all `shirt_*`, `jacket_*`, `pants_*`, `boots_*`, `helmet_*`, `hair_*`, `face_*`, `gloves_*`, `elbow_*`, `knee_*`, `pack_*` pieces).
  - Preserve `Outfit` combined mesh surface budget (`<= 2` surfaces on character body: `OutfitHead` + `Outfit` for `autotest_r4.gd`).
- **Upgrades**:
  - **Anatomical Base Skin**: Restrict neckline cuts strictly to `abs(x) < 0.145`; never cut arm geometry. Smooth out hoodie kangaroo pocket and neck hood lumps on `skin_torso` and shirts. Restore realistic athletic human arm proportions (deltoid, biceps/triceps, forearm taper to wrist) with overlapping watertight joints at shoulder, elbow, wrist, hip, knee, and ankle.
  - **Shirts & Jackets**: Extend shirt hems down to `z = 0.93` (overlapping cleanly inside pants waist at `z = 1.01`) with closed collar/hem/cuff rims. Remove hood-base lumps from non-hoodie jackets; build crisp collars, lapels, zippers, pockets, and tactical field webbing.
  - **Pants & Footwear**: Closed waistbands with belts, articulated knees, cargo pockets, and closed-toe anatomical boots/sneakers with soles, ankle collars, and tread (no bare toes inside shoes).
  - **Pads, Gloves, Helmets, Face, Packs**:
    - Fix `elbow_*` and `knee_*` inner shell normals, fit snugly to actual limb radius (`~0.044 m` elbow, `~0.068 m` knee), and position/skin elbow pads at the elbow joint (`upper_arm` + `forearm` 50/50 blend, pointing toward `-Y` in Blender / back of elbow) so they sit on the elbow point when the arm bends instead of floating in front of the chest.
    - Build high-detail tactical/street headwear (`helmet_combat` FAST/PASGT shell with rails/shroud/chinstrap, curved-brim `helmet_cap`, `helmet_beanie`, `helmet_hardhat`, `helmet_moto`), contoured `face_*` (goggles, respirator, sunglasses, bandana), snug `gloves_*`, and contoured `pack_*` with chest-hugging straps.

### 3. Material & Texture Pipeline (`tools/make_gear_textures.py`, `game/src/player/outfit.gd`)
- High-definition 512x512 procedural material slices (`gear_array.png`) with rich micro-fabric weave, ripstop, Cordura, leather grain, camo patterns, and seam shading.
- `Outfit.SHADER` uses `cull_disabled` to guarantee zero backface holes on cuffs, collars, or straps from any viewing angle, plus balanced rim/subsurface skin and fabric specularity.

### 4. Third-Person Upper-Body Aim, Clavicle Reach & Analytical Arm/Hand IK (`game/src/player/character_visual.gd`, `game/src/match/world.gd`)
- Replace buggy `TwoBoneIK3D` twist behavior with a deterministic `SkeletonModifier3D` (`WeaponPoseModifier`) that runs after `AnimationPlayer` evaluation:
  - Smoothly pitches `spine`, `chest`, and `neck`/`head` with `ch.pitch` when armed/aiming so torso, head, `DmVest`, and weapon pitch as a cohesive unit.
  - Positions `weapon_node` in chest/shoulder-relative space so rifle buttstocks seat cleanly into the right shoulder pocket (no neck clipping) and pistols hold in a natural two-handed tactical Weaver/isosceles stance.
  - Rotates `shoulder.L` forward/inward for two-handed weapons so the left arm (`0.54 m`) comfortably reaches the foregrip/handguard with a natural elbow bend.
  - Analytically solves `upper_arm.R/L`, `forearm.R/L`, and `hand.R/L` bone poses using the law of cosines and anatomically grounded elbow pole vectors, with zero forearm twist and exact hand alignment to grip and barrel axes.
  - Preserves first-person `dm_no_own_body` and `dm_arms_clear` guarantees.

## Verification & Integration Gates
1. `bash tools/check.sh` -> 0 compile errors.
2. Blind Critic review (`research` subagent) on high-res in-engine renders of:
   - Armed third-person operators (M16 + combat helmet + heavy vest + elbow pads + camo pants from user screenshot, plus rifle/pistol aiming up/level/down, crouching, moving from multiple angles).
   - `res://tools/outfit_lineup.tscn` (all 8 preset outfits + randomized loadouts).
3. Automated test suites:
   - `--autotest=r4 --r4_only=outfits`
   - `--autotest=dm`
   - `--autotest=r5`
4. Production builds:
   - Windows: `builds/windows/Aetherion.exe`
   - Android: `builds/android/Aetherion.apk` and `builds/android/Aetherion-opengl.apk`
