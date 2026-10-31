# Malasugue Mall horror rebuild — 0.19.0

The mall uses a dedicated material profile, enabled during MapBuilder.setup.
Other maps retain their own materials. Every opaque architecture/furniture
surface routed through Materials uses the new material families. Printed signs,
posters, goods and wayfinding retain their readable content with a new wear shader.
Animated escalator treads have grooved, worn metal shading. Existing imported
prop models retain their UV layout; their Materials-based surfaces use the profile.

Sixteen original material cells share three 4096px atlases (albedo, normal, AO/roughness/metal).
Each cell is 1024px with 8px wrap padding. The porcelain and plaster cells use
dedicated 1254px original artwork; the remaining cells originate in the material
sheet. Normal/roughness maps are shallow technical derivations from the artwork,
not photogrammetric scans. Android caps the atlases at 2048px (512px per cell).

Rebuild with `python -I tools/build_mall_horror.py`. Artwork and exact prompts are
retained in `work/r19/source`; shipped atlases are `game/assets/mall/horror`.
Eight additional finishes (ivory paint, sage paint, buff render, brick, terrazzo, green marble, geometric tile and cement repairs) use a second set of three 4096x2048 atlases. Quiet painted surfaces contrast with isolated damage, with room-specific lower wall finishes and irregular repairs. Floor inlays fill cutouts in the base mesh; they do not overlap a visible floor. World-anchored UVs and quantized height selection keep the finishes stable.

Artwork was generated with the built-in ImageGen tool, then technically packed.
No external texture licence is required for these original generated images.

Lighting uses the existing distance/shadow budget, with cold fluorescent pools,
failing fixtures and red emergency lamps. Both elevator cabins use matching cool
white fluorescent fixtures. Lit areas have broader, brighter light pools, while
unlit corners retain shadow. The new screen shader affects the world
below HUD layer 5, without depth haze or volumetrics. The burnt room is cold and
emits no ambient smoke. Reduced-flash accessibility still affects fixtures and guns.

The new lift lobby occupies the Level 1 north unit at x=6..19, z=-45.5..-35.
Lift centres are x=9 and x=16. Both open south at z=-40.5. Their 28m shafts pass through all upper floors to a machinery headhouse. Torn cabin roofs reveal rails, suspension ropes, car crossheads, drive sheaves and counterweights. Upper floors have real landing doors; Level 3 has a damaged open landing with a rail. Collision and the bot
walk grids are built together; small rubble and papers never obstruct movement.
Gallery cover is on Levels 2–5, with two additional recesses on Levels 2 and 4.

Footstep sources:

- **Footsteps on Metal**, IENBA, Freesound sound 698697, **CC0**.
  https://freesound.org/people/IENBA/sounds/698697/
  Downloaded the public high-quality preview. Six individual strikes were trimmed,
  band-limited, faded and level-matched; the natural metal tails were retained.
- Existing **Kenney CC0 footsteps**, from the owner's Sleep project, are filtered
  and level-matched for tile and rubber. Original provenance remains at
  `game/assets/audio/sleep/footsteps/source.json`.

`python -I tools/build_mall_audio.py` rebuilds the sixteen surface samples from
retained sources. The escalator collision has its own physical material so the
stationary department-store escalators also select the correct sound set.

Verification:

- `--autotest=horror`: real player movement in/out of both cabins, ray-tested
  footstep surfaces, imported audio, no-fog profile, upper gallery floor stances,
  pooled world-light illumination/decay, both moving escalator directions,
  and live shopfront glass destruction. Captures and results: `work/r19/qa_current`.
- `--autotest=horror --horror_only=flash`: isolated GPU lighting check.
- Fixed camera captures: `work/r19/final`; original comparison: `work/r19/before`.

Original material sheet prompt:

> Production photoreal PBR base colour atlas for an abandoned Philippine mall.
> Exactly 4 columns by 4 rows, edge-to-edge square material swatches; no gutters,
> borders, labels, perspective, cast shadows, objects or lighting highlights.
> Row 1: dirty ivory cracked porcelain; charcoal granite; stained pale green-grey
> marble; desaturated sage/ivory chipped mosaic. Row 2: peeling institutional
> plaster with mildew; water-damaged acoustic ceiling; scratched oxidized stainless
> steel with dried blood; rusty diamond tread. Row 3: scratched brown oak;
> charcoal ribbed rubber; threadbare burgundy carpet; cracked brown leather.
> Row 4: crumbling structural concrete; grimy bathroom ceramic; oxidized teal
> painted metal; dried tropical decorative foliage. Intricate photographic detail,
> flat diffuse light, opposite edges tile, restrained realistic decay.

Dedicated porcelain prompt:

> Full-resolution seamless PBR base-colour texture, one material edge-to-edge.
> Straight-down orthographic photograph of abandoned mall ivory porcelain: regular
> 4x4 grid of square tiles, thin dark grout, branching fractures, chipped edges,
> scratches, mineral discoloration, ground-in dirt and restrained dried blood
> along several fractures. No debris, objects, perspective, shadows, highlights
> or labels. Even diffuse light, opposite edges match, photographic microdetail.

Dedicated plaster prompt:

> Seamless PBR base-colour texture, one flat material edge-to-edge. Straight-on
> orthographic photograph of grey-ivory institutional plaster, broad patches of
> peeling paint exposing pale sage undercoat and coarse grey plaster, fine cracks,
> mildew clusters, narrow rusty leak streaks and small pitted cement patches.
> No floor, ceiling, objects, text, perspective, cast shadows or baked highlights.
> Even diffuse light; opposite edges tile; intricate photographic detail.


Additional source sheets: `work/r19/source/wall_finishes.png` and `floor_finishes.png`, generated with built-in ImageGen. Wall prompt: four distinct photoreal PBR swatches—quiet aged ivory paint, faded sage paint, buff mineral render and repaired old brick—with restrained, isolated wear and no baked lighting. Floor prompt: four distinct PBR swatches—warm terrazzo, forest green marble, cream/burgundy/charcoal geometric cement tiles and patched taupe cement—with realistic fine material detail, no objects, no lighting highlights and tileable edges.

Current checks: 29/29 gameplay checks in `work/r19/qa_current/results.json`. Moving-camera depth-overlap captures are in `work/r19/floor_stability`.
