# r12 parkour notes (C2)

What the movement borrows from real parkour and from games that already made it playable, and the numbers chosen.
Sources are general knowledge of the discipline and of the named games; nothing here is measured from those games.

## Real moves (the body)

| Move | What a traceur does | Used here as |
|---|---|---|
| Cat leap (arm jump) | Jumps at a wall, feet land on the face, hands catch the top edge; the body hangs from the hands with the feet braced. | Ledge grab: in the air, moving forward, a wall top 0.95-1.65 m above the feet is caught by the hands; the body hangs with the feet 1.95 m below the edge (or on whatever is under them). |
| Climb up (muscle-up / cat climb) | From the hang, pulls, turns the arms over the edge and pushes up, a knee or foot comes up on to the top. | Forward or Jump from the hang: a short timed move (Vault state, PK_CLIMB) on to the top, the hands stay planted on the edge while the view rises past them. |
| Wall pass / climb over | On a thin wall, the climb carries on over the top and down the far side. | A top thinner than 0.7 m with ground no more than 3.6 m below on the far side: the climb ends on the far side. |
| Wall run-up (passe muraille) | A sprint into a wall turns into one or two steps up the face, gaining height the legs alone would not give. | Sprint jump at a wall (or reaching it early in a sprint jump): one kick up at 5.5 m/s (about 1.5 m of rise) that brings a 3 m top within reach. Once per jump. |
| Shimmy | Moves sideways along the edge hand over hand. | Left/right while hanging, 0.9 m/s, as long as the edge carries on at the same height. |
| Drop / let go | Lowers to full stretch and drops, or pushes off. | Back or Crouch while hanging lets go with a small push off the wall; the field also tears the hands off. |
| PK roll | Lands from a drop and rolls diagonally over one shoulder so the impact turns into forward motion instead of going into the knees. | Holding Crouch as you land from a real drop (over 1.6 m): 0.6 s roll that keeps the speed; the server takes fall damage as if the drop were 2.5 m lower, then 60 % of that. |
| Slide | Not a classic parkour move but universal in urban running: drops the hips and slides on the side of the leg under an obstacle or into cover. | Crouch at a sprint (5.2 m/s or more): about a second at crouch height, slowing 3.2 m/s per second (less downhill), a little steering, ends in a crouch. |
| Speed vault / step vault | Over a waist-high obstacle with one hand on top. | The existing vault (Vault.gd) kept; the first-person left hand now pushes off the top. |

## Games that made these playable

- **Mirror's Edge (2008):** first-person parkour; the view stays in the body (hands and legs seen), a roll on landing
  (Crouch timed at touch-down) avoids fall damage, wall runs up and along walls, ledge grabs and climb-ups. Borrowed:
  the timed landing roll on Crouch, the hands drawn on the edge, the run-up into a wall.
- **Apex Legends / Titanfall 2:** sprinting into a wall gives a short climb up it; slides from a sprint keep momentum.
  Borrowed: the slide's entry rule (Crouch at a sprint) and the sprint wall climb being limited to one go.
- **Dying Light:** climbing any ledge within reach, hanging and shimmying. Borrowed: shimmy along edges.
- **PUBG and other battle royales:** vault and climb only by an explicit key over low obstacles, no wall running.
  Kept: the existing Jump-near-a-low-obstacle vault, since players already know it.

## Body numbers (character 1.78 m, capsule radius 0.3 m)

- A standing adult reaches about 2.2-2.3 m with the fingers. A jump in place adds roughly 0.4-0.5 m of
  centre-of-mass rise; the game's jump (4.3 m/s) rises 0.94 m, which with the grab window (edge 0.95-1.65 m above
  the feet at the moment of contact) puts plain-jump grabs at walls up to about 2.5 m.
- With the run-up the feet rise about 1.5 m, so a 3.0 m top is reachable from a sprint and not from a run; a 4.5 m
  wall is out of reach either way.
- Fall damage: real people drop 2-3 m (a garden wall, a storey) routinely. Drops up to 3.5 m are free; damage rises
  steeply to lethal at 14 m (6 m: about 12 damage).

## Rules for bots

Bots grab ledges only while their brain sets `climb_ok` (escaping the field); otherwise they would end up hanging on
walls by accident while strafing in a fight.
