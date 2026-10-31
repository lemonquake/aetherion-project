# Blind review: movement

Two builds of a first-person shooter, A and B, ran the same scripted routes on the same flat test course (grey floor,
plain blocks). Each image is a strip of six frames from one route, left to right, top row then bottom row. The HUD
(minimap, team scores, fire mode text) is the same in both builds and is not part of the comparison.

**Criterion (fixed before the captures were taken):** which build's movement and parkour look more like a real person
moving through this space? Look at how the body gets going and stops, how it handles a sudden turn, how it deals with a
wall it jumps at, and how it lands from a high drop.

- **view1**: Sprint from a standstill on flat ground, then all keys released (side view). Frames at 0.1, 0.4, 0.8, 1.33, 1.6 and 2.17 s after the start; keys released at 1.25 s. Files: `view1_A.png`, `view1_B.png`.
  Measured at each frame (speed along the ground; feet height above the course floor):
  - A: speed 1.50, 6.30, 6.30, 5.70, 2.50, 0.00 m/s; feet 0.02, 0.02, 0.02, 0.02, 0.02, 0.02 m
  - B: speed 1.02, 3.67, 5.59, 5.89, 3.37, 0.00 m/s; feet 0.02, 0.02, 0.02, 0.02, 0.02, 0.02 m
- **view2**: Sprinting, then the view snaps 90 degrees to the right at 1.5 s, forward still held (seen from above and behind). Frames at 1.0, 1.5, 1.7, 1.9, 2.17 and 2.63 s. Files: `view2_A.png`, `view2_B.png`.
  Measured at each frame (speed along the ground; feet height above the course floor):
  - A: speed 6.30, 6.30, 4.60, 5.08, 6.30, 6.30 m/s; feet 0.02, 0.02, 0.02, 0.02, 0.02, 0.02 m
  - B: speed 6.14, 6.30, 4.35, 3.79, 5.02, 6.30 m/s; feet 0.02, 0.02, 0.02, 0.02, 0.02, 0.02 m
- **view3**: Running at a 2.2 m wall, Jump pressed about 1.1 m from it, forward held (side view). Frames at 0.42, 0.75, 0.97, 1.25, 1.58 and 2.08 s. Files: `view3_A.png`, `view3_B.png`.
  Measured at each frame (speed along the ground; feet height above the course floor):
  - A: speed 3.78, 4.40, 0.00, 0.99, 0.68, 1.75 m/s; feet 0.02, 0.52, 0.25, 1.83, 2.26, 2.22 m
  - B: speed 4.40, 0.00, 0.00, 0.00, 0.00, 0.00 m/s; feet 0.02, 0.77, 1.00, 0.59, 0.00, 0.00 m
- **view4**: The same run and jump at the 2.2 m wall, as the player sees it. Same frame times. Files: `view4_A.png`, `view4_B.png`.
  Measured at each frame (speed along the ground; feet height above the course floor):
  - A: speed 4.40, 0.00, 0.00, 0.00, 0.00, 0.00 m/s; feet 0.02, 0.77, 1.00, 0.59, 0.00, 0.00 m
  - B: speed 3.78, 4.40, 0.00, 0.99, 0.68, 1.75 m/s; feet 0.02, 0.52, 0.25, 1.83, 2.26, 2.22 m
- **view5**: Walking off a 4.5 m block, Crouch pressed while in the air (side view). Frames at 0.25, 0.75, 1.17, 1.5, 1.67 and 1.92 s. Files: `view5_A.png`, `view5_B.png`.
  Measured at each frame (speed along the ground; feet height above the course floor):
  - A: speed 2.60, 2.35, 1.60, 1.60, 1.60, 1.60 m/s; feet 4.52, 4.25, 2.68, 0.20, 0.02, 0.02 m
  - B: speed 2.52, 2.52, 2.02, 1.62, 2.78, 2.40 m/s; feet 4.52, 4.33, 2.89, 0.52, 0.02, 0.02 m

Mandatory observable constraints: the body never passes through a block; the body is never shown floating in a
pose that cannot be held (for example hanging in the air with nothing to hold); objects the body carries stay with it.

Read only the files in this folder. Do not open anything else on the machine (no source, logs or other folders).
If the evidence is incomplete or the two builds cannot be compared, answer UNVERIFIED with the reason. Otherwise choose A
or B for the criterion as a whole, without numerical scores, and answer in exactly this form:

```
Evidence status: VALID | UNVERIFIED
Unavailable or incomparable evidence: <only if unverified>
Winner: A | B
Clear advantage: true | false
Observed basis: <specific views and frames>
Mandatory constraints: <what you observed for each constraint, per build>
Single comparison gap: <the one largest remaining defect in the build you chose, or "none">
Recheck condition: <an observable condition that would show that gap fixed>
```
