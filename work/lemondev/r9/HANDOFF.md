# Handoff Record — r9: Player Model, Rig, Gear, Third-Person IK, Sprint & Curb Step Overhaul

## 1. Summary of Completed Work

### A. Blender 5.2 Player Body & 87-Piece Gear Overhaul (`tools/blender/make_gear.py` -> `game/assets/models/gear/gear.glb`)
1. **Clean Manifold Base Shell (`clean_upper_shell`, `fit_bmesh`, `build_body_head`)**:
   - Eliminated the destructive `0.45` decimation pass and removed the baggy hoodie kangaroo pocket (`500` faces) and outer hood (`3,323` faces) before sculpting `skin_torso`, `skin_upperarm`, `skin_forearm`, `shirt_*`, and `jacket_*`.
   - Scaled arm meshes around the true anatomical arm axis (`ARM_AXIS_Y = 0.002`, `ARM_AXIS_Z = 1.456`) with smooth wrist-cuff matching (`wrist_match=True`) and inward wrist/neck plugs on `body_head` so neck, shoulder, elbow, and wrist joints are 100% watertight at all animations and aim angles.
   - Curled the wide-splayed T-pose fingers of `body_head` (`build_body_head`) and `gloves_*` (`glove`) around the knuckle and thumb opposition axes so hands naturally wrap rifle pistol grips, handguards, and handguns.
   - Applied local Retinex de-shadowing to the head UV region of `gear_generic_body.jpg` so the face skin tone matches the hands, neck, and `skin_*` regions without washing out eyes, brows, nostrils, or lips.
2. **BVHTree-Conformed Tactical & Streetwear Gear**:
   - **Backpacks (`pack_school`, `pack_tactical`, `pack_sako`, `pack_sling`)**: Raycast-conformed 15-point smoothed shoulder straps, sternum straps, and cross-body sling straps in the sagittal YZ plane against `bvh_torso` (with T-pose arms stripped) with `4.0–4.5 mm` clearance so straps hug the shoulders, clavicles, pectorals, and ribcage without floating or clipping.
   - **Elbow & Knee Pads (`elbow_*`, `knee_*`)**: Centered on the exact mesh slice centerlines (`elbow_cy, elbow_cz`, `knee_cx, knee_cy`), raycast-conformed outward from the limb centerline against `bvh_elbow_in`, `bvh_elbow_out`, and `bvh_knee_out`, stitched all 4 perimeter walls (`stitch_open_shell`), and transferred per-vertex bone weights via `KDTree` (`kd_arm`, `kd_leg`) from the underlying sleeve/trousers so pads and straps deform identically when bending.
   - **Closed-Toe Footwear & Bare Feet (`boots_sneakers`, `boots_combat`, `boots_rubber`, `boots_tsinelas`, `skin_feet`)**: Built multi-slice lofted closed-toe shoe uppers and lugged outsoles (`build_closed_shoe_bmesh`) so bare toes never appear inside shoes; reshaped `skin_feet` into a low-dorsum bare foot resting at `z = 0.011`; aligned `boots_tsinelas` to the foot splay angle (`+ang`) and transferred `skin_feet` bone weights via `kd_feet`.
   - **Headwear, Hair & Face Gear (`helmet_*`, `hair_*`, `face_*`)**: Conformed `hair_*` domes to `bvh_head` with cosine-feathered hairlines (`2.4 mm` skull clearance) and a tapered sagittal fan-blade `hair_mohawk`; integrated `helmet_beanie`'s folded rib cuff into the contoured dome; conformed `helmet_combat`'s Y-chinstrap and `face_*` straps (`build_head_strap`) to `bvh_head`; expanded `helmet_moto` (`mc = (0, -0.042, 1.676)`, `mr = (0.108, 0.136, 0.136)`, `phi1 = 0.82 * pi`) and updated `Outfit.pieces_for` in `game/src/player/outfit.gd` to hide `face` gear under the full-face `moto` helmet.
   - **Garment Layering & Shader (`shirt_*`, `jacket_*`, `pants_*`, `game/src/player/outfit.gd`)**: Enforced `>= 4.5 mm` radial clearance of `shirt_*` over `skin_torso` via `kd_skin_torso`, preserved sharp outer normals on `add_boundary_rim` via `bmesh.ops.split_edges`, and set `cull_disabled` in `Outfit.SHADER`.

### B. Third-Person Tactical Pose, Arm IK & Looping Sprint Animation (`game/src/player/character_visual.gd`)
1. **Looping Sprint Animation Fix**:
   - Added `"hero_run"`, `"run_hurt"`, `"crouch_walk"`, `"carry_box"`, `"idle_adjust"`, `"idle_hurt"`, `"idle_look"`, `"hero_walk"`, and `"walk_hurt"` to `LOOP_ANIMS` in `game/src/player/character_visual.gd` so `"hero_run"` (`0.633 s`) loops continuously (`Animation.LOOP_LINEAR`) instead of freezing on its last airborne keyframe after `0.633 s`.
2. **Deterministic `TacticalPoseModifier` & Analytical Two-Bone Arm IK**:
   - Replaced `TwoBoneIK3D` twist artifacts with `TacticalPoseModifier` (`_apply_tactical_pose` + `_solve_arm_ik`):
     - Upper-body pitch and bladed stance distributed across `spine`, `chest`, `neck`, and `head` (keeping `DmVest` and backpack straps locked to the torso).
     - Clavicle protraction (`shoulder.L` / `shoulder.R`) when armed (and reset to rest when unarmed) so the left support hand comfortably reaches rifle handguards (`0.54 m` arm reach).
     - Rifle aim pitch (`+0.45` / `-0.45`) pivoted around the right shoulder pocket (`pocket_self - fire_basis * stock_local`) so the buttstock stays seated in the shoulder pocket at all elevation angles.
     - Across-chest low-ready sprint carry (`_sprint_blend`) with stride-synchronized weapon bob (`_stride_phase`) and stock clearance in front of the right pectoral.
     - Analytical law-of-cosines two-bone IK (`_solve_arm_ik`) with anatomical pole vectors and palm-wrapped wrist offsets (`0.076` / `0.086`).

### C. Sidewalk / Curb Step-Up Fix (`game/src/player/character.gd`)
- Rewrote `_try_step` in `game/src/player/character.gd` to:
  1. Combine actual pre-slide horizontal velocity and wish direction (`wish_h`, fallback `- basis.z`) so stepping works even when already pressed at zero velocity against a curb (`WALK_TOP = 0.18 m`, `step_height = 0.36 m`).
  2. Probe both the wall-into-curb normal (`-hit_n`) and travel direction (`move_dir`) with `6 cm` forward clearance (`probe_d = maxf(move_d, 0.06)`) so shallow diagonal approaches along a sidewalk edge step up smoothly.
  3. Preserve post-step horizontal slide momentum (`post_slide`) across the top of the curb.

## 2. Verification & Evidence
- **Static Script Check**: `Godot --headless --path game res://tools/check_scripts.tscn` -> `checked 121 scripts, 0 failed`.
- **Visual Contact Sheets & In-Engine Renders**:
  - `work/gear/tactical_poses.png` (6-panel in-engine verification: `DmVest + helmet_combat + rifle_556` operator, `rifle_m416` ADS, `+0.45` aim up, `-0.45` aim down, `t = 1.33 s` continuous `hero_run` sprint, and crouched two-handed `pistol_9`).
  - `work/gear/lineup_new.png` (7-character randomized outfit lineup in Godot).
  - `work/gear/sheet_*.png` (`sheet_pack.png`, `sheet_elbow.png`, `sheet_knee.png`, `sheet_helmet.png`, `sheet_face.png`, `sheet_hair.png`, `sheet_shirt.png`, `sheet_jacket.png`, `sheet_pants.png`, `sheet_boots.png`, `sheet_gloves.png`) and regenerated UI icons in `game/assets/ui/gear/*.png`.
- **Autotests & Builds**:
  - `--autotest=r4 --r4_only=outfits`
  - Windows release executable: `builds/windows/Aetherion.exe`
  - Android release APKs: `builds/android/Aetherion.apk` and `builds/android/Aetherion-opengl.apk`
