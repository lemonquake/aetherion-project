# Aetherion items, weapons, inventory and loadout: report for the DEATHMATCH mode and the Lawless Sub map

Paths are relative to `A:/Python/aetherion-project/game/` unless they start with `tools/` or `work/`. I read the code only and changed no files.

## (a) Guns, classes, calibres and slots

**Weapon slots** are defined in `src/weapons/weapon_state.gd:9`: `enum { HOLSTER, PRIMARY, SECONDARY, HANDGUN }`, which is 0, 1, 2, 3. `slots := [null, null, null, null]` (line 12) is indexed by that enum.

- **Slots 1 and 2** both hold long guns. The engine's SECONDARY is a second long gun, not a pistol.
- **Slot 3** is the handgun slot.
- Keys `weapon_1/2/3` select a slot and `holster` selects slot 0 (`src/player/player_controller.gd:111-118`). The labels are "Primary weapon", "Secondary weapon" and "Handgun" (`src/ui/settings_ui.gd:245-246`), and "Primary/Secondary/Handgun" in the SmarTab (`src/ui/smartab_ui.gd:159`, `:267`).
- On phones there is a single "Weapon" button that cycles through slots with `next_weapon` (`src/ui/touch_controls.gd:41`).

**Where a gun goes** is decided by `slot_for(id)` (`weapon_state.gd:114-122`), using the weapon's `"slot"` field (`"handgun"` or `"long"`):
- A handgun always goes to slot 3.
- A long gun goes to the first empty slot of 1 and 2.
- If both are full, it replaces slot 2 when the player is holding slot 2, otherwise slot 1.

**Naming clash for DM:** the DM spec's "secondary" should map to the handgun in slot 3, or to a second long gun in slot 2. Two handguns cannot both be carried.

**Weapon classes** in `data/weapons.json` are `handgun`, `smg`, `rifle`, `marksman` (DMR), `precision` (bolt-action sniper), `shotgun` and `lmg`. Every gun has `items/<id>.glb`.

Columns: id, display name, class, calibre id (the inventory ammo item is `"ammo_"+calibre`), feed type, magazine size / extended size with an extended-mag attachment, fire modes.

**Handguns (slot "handgun", slot 3):**

| id | Name | Calibre | Feed | Mag / ext | Modes |
|---|---|---|---|---|---|
| `pistol_9` | P92 | 9x19 | mag | 15 / 21 | semi |
| `pistol_45` | P1911 | 45acp | mag | 7 / 12 | semi |
| `revolver_357` | R1895 Revolver | 357 | cylinder | 6 / none | semi |
| `pistol_deagle` | Deagle | 50ae | mag | 7 / 10 | semi |

**Long guns (slot "long", slots 1 and 2):**

| id | Name | Class | Calibre | Feed | Mag / ext | Modes |
|---|---|---|---|---|---|---|
| `smg_9` | MP5K | smg | 9x19 | mag | 30 / 40 | auto, semi |
| `machine_pistol` | Micro UZI | smg | 9x19 | mag | 32 / 45 | auto, semi |
| `smg_ump45` | UMP45 | smg | 45acp | mag | 25 / 35 | auto, semi |
| `smg_vector` | Vector | smg | 9x19 | mag | 19 / 33 | auto, semi |
| `smg_tommy` | Tommy Gun | smg | 45acp | mag | 30 / 50 | auto, semi |
| `rifle_556` | AR-15 | rifle | 556 | mag | 30 / 40 | semi, auto |
| `rifle_762` | AKM | rifle | 762x39 | mag | 30 / 40 | semi, auto |
| `rifle_scar` | SCAR-L | rifle | 556 | mag | 30 / 40 | semi, auto |
| `rifle_m416` | M416 | rifle | 556 | mag | 30 / 40 | semi, auto |
| `rifle_m762` | Beryl M762 | rifle | 762x39 | mag | 30 / 40 | semi, auto |
| `marksman_308` | SLR | marksman | 308 | mag | 20 / 30 | semi |
| `dmr_mini14` | Mini 14 | marksman | 556 | mag | 20 / 30 | semi |
| `dmr_sks` | SKS | marksman | 762x39 | mag | 10 / 20 | semi |
| `bolt_308` | M24 | precision | 308 | mag | 5 / 8 | bolt |
| `bolt_kar98` | Kar98k | precision | 308 | mag | 5 / none | bolt |
| `lmg_m249` | M249 | lmg | 556 | mag | 100 / none | auto |
| `shotgun_pump` | S1897 Pump | shotgun | 12buck | tube | 6 | pump |
| `shotgun_double` | S686 | shotgun | 12buck | break | 2 | semi |
| `sumpak` | Sumpak | shotgun | 12buck | break | 1 | semi |
| `shotgun_saiga` | S12K | shotgun | 12buck | mag | 5 / 8 | semi |

- The Micro UZI is class smg in a long slot, not a handgun.
- The bolt guns and the pump use `cycle_time` (`bolt_308` 1.05, `bolt_kar98` 1.1, `shotgun_pump` 0.55).

**Ammo items** (`data/items.json:54-157, 229-241`): `ammo_9x19` (stack 120), `ammo_45acp` (60), `ammo_357` (48), `ammo_12buck` (40), `ammo_12slug` (30), `ammo_556` (120), `ammo_762x39` (90), `ammo_308` (40), `ammo_50ae` (35). Each has an RGB `color`.

**Helpers in `src/core/defs.gd`:**
- `weapon(id)` (88)
- `item(id)` (92-99): a weapon becomes `{name, kind:"weapon", mass, model}`; an attachment becomes `{kind:"attachment", slot}`.
- `ammo_item(weapon_id)` (106) returns `"ammo_"+calibre`.
- `ammo_color(id)` (111) and `calibre_name(id)` (118) give the UI calibre chip, as used in `smartab_ui.gd:279-281`.
- `is_weapon` (125) and `is_attachment` (102).

**Other weapon fields:** `value` (bot ranking), `handed` (pistol or rifle), `attachments` (allowed list), `sight_zoom`, `hold`, `sound`, `model`, plus spread, recoil and timing fields.

**Attachments** (`src/weapons/attachments.gd`): one per mount kind (`KINDS` = sight, muzzle, grip, mag, stock, light).
- `compatible(weapon_id, att_id)` (14)
- `mag_cap(w)` (45-50): the gun's `mag_ext` if a fitted attachment has `ext: true`, otherwise `mag_size`.
- `score` / `best_slot_upgrade` (98-124)
- `bitmask` (53) replicates fitted attachments to other players.

**Data gotchas:**
- `alt_ammo: "12slug"` on the four shotguns is never read by any code. A weapon instance never gets an `"ammo"` key (`weapon_state.gd:239`, `:354` read `w.get("ammo", d.ammo)`), so `ammo_12slug` cannot be loaded into anything. It is dead loot.
- `loot.json weapon_ammo.counts` has a `"762x54"` calibre that no gun or item uses.

## (b) Giving a character a gun, ammo, vest and helmet

**Weapon instance format:** `{id, mag:int, chamber:bool, mode:int, att:[att_ids], wl?:float}`. `wl` is the weapon-light battery charge; `fit()` sets 0.6 and `FlashlightState` sets 0.8 if it is missing.

**`WeaponState.new_instance(id, rng=null, loaded_frac=-1.0)`** (`weapon_state.gd:125-137`, a static function):
- With no rng and no fraction, the gun has a full load: `n = mag_size`. One round is moved to the chamber (also for a cylinder), so `mag = cap-1` and `chamber = true`. The total loaded equals `mag_size`.
- For "mag + 1" (31 in an AR), set `w.mag = Attach.mag_cap(w)` afterwards.
- A mag-fed gun counts as full when `mag >= cap` (`start_reload`, :357), so a fresh `new_instance` can still take one round.
- Break-action guns count as full when `mag + chamber >= cap`.
- Loot uses `new_instance(id, rng)`, which loads 30–100%.

**Inventory** (`src/items/inventory.gd`):
- `bag: Array` of entries `{id, n, ...}`.
- `gear := {"helmet","vest","backpack","flashlight"}` (line 12).
- `add(e: Dictionary, force := false) -> int` (113-144) returns the number of units accepted.
  - It stacks up to the item's `stack` size and copies non-stackable items one per entry.
  - Without `force` it is limited by `capacity()`: 7.0 kg base (`items.json carry.base_capacity`) plus the backpack's `capacity` (small 6, large 12).
  - Only bag mass counts toward capacity and the overweight slowdown (`speed_mult` :57). Worn gear and guns do not.
- `equip_gear(e) -> Dictionary` (147-158) picks the slot from `item.slot` (or `"flashlight"` for kind flashlight) and returns the replaced entry, or `{}`.
- `take(id, n)` (90), `count(id)` (64), `unequip(slot)` (161), `all_entries()` (170; everything goes to the corpse), `clear()` (185).
- `mark_dirty()` (20) sets `dirty`. That flag drives replication to the owner through `world._send_owner_state()` (`src/match/world.gd:818-833`), which sends health plus `inv.to_dict()`. `to_dict` includes `"w"`, the weapon slots.

**Armour and helmet items** (`data/items.json:158-212`). The armour only has levels in the sense of light versus heavy; there is no numeric level field.

| id | Name | Slot | Mass | Protection | Durability | Coverage | Blunt | Notes |
|---|---|---|---|---|---|---|---|---|
| `vest_light` | Soft Armor Vest | vest | 2.4 | 900 | 100 | 1.0 (default) | 0.25 | covers torso |
| `vest_heavy` | Plate Carrier | vest | 7.5 | 4200 | 140 | 1.0 (default) | 0.18 | covers torso |
| `helmet_light` | Light Helmet | helmet | 1.3 | 600 | 50 | 0.7 | 0.35 | covers head |
| `helmet_heavy` | Heavy-Plate Helmet | helmet | 3.6 | 2200 | 90 | 0.85 | 0.3 | `break_absorbs_lethal: true` |

- **`helmet_heavy` is the highest helmet** and the only "full plate" option. Its ground model is an Altyn helmet (`docs/ASSET_MANIFEST.md:412`). There is no separate full-face item.
- **Worn armour is not drawn on the character.** Visible headwear is cosmetic only: `data/cosmetics.json` slot `helmet` has none, beanie, cap, combat, hardhat and moto, and `src/player/outfit.gd:175` uses it. A visible "full helmet" in DM would mean forcing `look.helmet = "combat"` or `"moto"`.

**Armour durability** (`src/player/health.gd:153-185`, inside `apply_hit(part, energy, ammo, e0, dir, seed, attacker)`):
- Only the `torso` (vest) and `head` (helmet) are protected. Limbs never are.
- **The entry needs a `"d"` field greater than 0** (`:160`). Without `"d"`, the armour protects nothing.
- A coverage roll `randf() <= coverage` must pass; helmets have 0.7 or 0.85.
- Current protection is `protection * (0.4 + 0.6*d/durability)`. Penetrating energy is `energy * ammo.armor_pen`, where energy is ½mv² (`src/weapons/ballistics.gd:21`).
  - If `p_energy < prot`: blunt only. Damage is multiplied by `blunt`, there is no bleeding or overpenetration, and `d -= energy/35`.
  - Heavy helmet with `d >= 50%` and `p_energy < 2*prot`: the helmet cracks. `d` drops to 0 and damage is ×0.55, clamped so it cannot kill (health ≥ 1, head ≥ 1).
  - Otherwise the round penetrates. Damage is ×`clamp(1 - prot/p_energy*0.5, 0.5, 1)` and `d -= energy/22`.
- `d <= 0` breaks the armour and the result has `armor_broken`. There is no repair.
- Loot armour gets `d = durability * U(0.55, 1.0)` (`src/world/dynamics.gd:837-838`).

**DM balance warning** (muzzle penetrating energy against full-durability armour, from my calculation):
- **Nothing gets through the heavy vest except** `bolt_308`, `bolt_kar98`, `marksman_308` (.308), `dmr_mini14` and `dmr_sks`.
- **Every pistol except .357 and Deagle, every SMG, and all buckshot** are blunt-only against even the light vest (900). Buckshot is about 170 J per pellet, so shotguns are blunt-only against every armour.
- **Rifles and the Deagle crack `helmet_heavy`**, so the first headshot never kills. .308 rounds penetrate it.
- **Result:** if everyone spawns with armour, SMGs, pistols and shotguns become weak against torso and head hits. Choosing `vest_light` over `vest_heavy` matters a lot.

**Recommended DM loadout code** (`ch.wpn`, `ch.inv` and `world.interaction` all exist):
```gdscript
var w := WeaponState.new_instance(primary_id)          # full load
ch.wpn.slots[1] = w                                       # long gun; handgun -> slots[3]; second long -> slots[2]
ch.inv.add({"id": Defs.ammo_item(primary_id), "n": 120}, true)   # force bypasses capacity; auto-stacks
ch.inv.equip_gear({"id": "vest_light", "n": 1, "d": float(Defs.item("vest_light").durability)})
ch.inv.equip_gear({"id": "helmet_heavy", "n": 1, "d": 90.0})
ch.inv.mark_dirty()                                       # writing wpn.slots directly does NOT dirty; required to replicate
```
- **Alternative:** `world.interaction.give(ch, {"id": id, "n": 1, "w": WeaponState.new_instance(id)})` (`src/match/interaction.gd:160`). It picks the slot with `slot_for`, fits attachments from the bag and marks dirty. But it drops any gun already in that slot, and it adds ammo without `force`.
- **Drawing the gun at spawn:** the server sets `cur` from the client command's `"slot"` (`weapon_state.gd:153-164`).
  - **Humans:** the `PlayerController.slot` variable (`player_controller.gd:22`) starts at 0, so the player spawns holstered. Setting `wpn.cur` on the server alone is overridden.
  - **Bots:** they send `ch.wpn.want` and pick a weapon in `_equip_best` (`src/ai/bot_brain.gd:835-860`).

**Current spawn path:** `match_server.gd:76` calls `_loadout(ch)` (88-96) right after `world.server_spawn_character(pid, team, name, pos, Motor.PLANE)` (`world.gd:177`).

## (c) Picking up, swapping and dropping weapons

**Use (E) on a ground item:** `server_use` → `target()` (`interaction.gd:29`, reach 2.3) → `_take_item` (145) → `give()` (160-196).
- **A gun always replaces whatever is in its `slot_for` slot.** The old gun (with its magazine and attachments) is dropped 0.6 m in front of the player by `_drop_entry` (247), which raycasts to the floor and calls `world.map_item_spawn_server` (`world.gd:1204`).
- Then `fit_from_bag(ch, slot)` (232) fits better attachments from the bag. The new gun is not auto-drawn.
- If the gun in hand is replaced, `cur` is unchanged and no draw time is applied.
- **Taking a gun from a container or corpse** (SmarTab op `"take"`, :346-361) also goes through `give()`. The old gun goes on the floor, not back into the container.

**Armour and backpacks:** `give()` (183-189) always equips the new item, even if it is worse. The old item goes to the bag with no `force`, and is dropped if it does not fit. A `vest_heavy` (7.5 kg) never fits a 7 kg bag without a backpack. Bots alone check "better" through `LootSense.value` (`src/ai/loot_sense.gd:66-72`).

**SmarTab requests** (`server_inventory_request(ch, req)`, :342-415): `drop_weapon {slot:1..3}` (401-410; holsters if the gun was in hand), `unload {slot}`, `attach {slot, att}`, `detach {slot, att}`, `drop {index, count}`, `put`, `take {index}`, `unequip {gear}`, `use {item}` and `close`.

**Bots:** `bot_take_entry` (623-649) puts a handgun in slot 3, or a long gun in `LootSense.long_slot` (the weaker of slots 1 and 2). `bot_take_item` (652-670) leaves the swapped gun where the new one lay.

**Death:** `dynamics.server_spawn_corpse` (1266) sets `corpse.entries = inv.all_entries()`, which includes the guns. Bodies are searchable with Use or the SmarTab. That already gives DM players a way to swap weapons. `Motor.SPECTATE` already exists and is excluded from alive checks (`world.gd:167` and others).

## (d) `starting_loadout` format

`data/loot.json` has `"starting_loadout": [["flashlight", 1, [0.55, 0.75]]]`, read in `match_server._loadout` (88-96). The format is a list of `[item_id, count, [charge_min, charge_max]]`.
- `e[2]` is read unconditionally, so a two-element entry fails on an out-of-range index.
- Every entry gets a `"c"` (charge) field.
- Only kind `flashlight` is equipped. Everything else goes through `inv.add(entry, true)` into the bag.

**This format cannot express a DM loadout.** A gun id would sit in the bag as an entry with no `"w"`, not in a weapon slot. Armour would go to the bag unworn and without `"d"`. DM needs a new code path (as in (b)) or an extended format.

## (e) Loot tables and how a new map's rooms get loot

**Table format** (`loot.json.tables.<name>`):
```
{"rolls": [min, max], "guaranteed"?: [entries], "entries": [[id, weight, [cmin, cmax]?, [charge_min, charge_max]?], ...]}
```
- The id `"nothing"` is a valid empty entry.
- `guaranteed` is one extra weighted roll that is never empty.

**Rolling** (`src/world/dynamics.gd`):
- `roll_table(table, rng=null) -> Array` (774). An unknown table silently returns `[]`.
- `_pick_entry` (792): a weapon roll also adds its own ammo stack with probability `weapon_ammo.chance` (1.0), using `weapon_ammo.counts[calibre]`.
- `make_entries` (814-841):
  - Guns get `new_instance(id, rng)` (a partial magazine) and, with chance `weapon_attachment_chance` (0.2), one random compatible attachment.
  - Armour gets `"d"`. Batteries and flashlights get `"c"`.

**Tables:** `drawer`, `kitchen`, `bathroom`, `wardrobe`, `under_bed`, `store_shelf`, `store_counter`, `clinic`, `toolbox`, `weapon_locker`, `military_crate`, `crate`, `trash`, `floor_household`, `floor_contested`, `floor_street`, `floor_weapon` (all 24 guns, rolls [1,1]), plus visible-box tables `box_balikbayan`, `box_bin`, `box_ammocan`, `box_footlocker`, `box_toolbox`, `box_medcase`, `box_riflecase` (its guaranteed roll is one long gun, its entries are scopes and attachments) and `box_cooler`.

**Where armour appears:**
- `vest_light`: `wardrobe`, `weapon_locker`, `floor_household`, `floor_contested`, `box_balikbayan`, `box_footlocker`
- `helmet_light`: `weapon_locker`, `floor_household`, `floor_contested`, `box_balikbayan`, `box_footlocker`
- `vest_heavy` and `helmet_heavy`: only `military_crate` and `floor_contested`

**Three placement APIs** (`dynamics.gd`; `bid` is the building id from `map_builder.new_building_id()` (277), or -1 outdoors):
1. **`add_loot_spot(pos: Vector3, table: String, bid: int)`** (298): floor loot in plain sight.
   - `randomize_for_match` (723-771) rolls it on every machine from `floor_rng` (the match seed), with item ids in order and no RPCs.
   - Each spot is settled by a ray against `PHYS_WORLD|PHYS_PROP`, from +0.35 to -0.45 m. A spot with nothing under it, or one embedded more than 6 cm into something, is dropped.
   - **Map generation must therefore be identical on server and clients**, including spot order.
2. **`add_container(pos: Vector3, table: String, bid: int, size := Vector3(0.5,0.5,0.5)) -> int`** (269): hidden searchable volumes such as drawers and cabinets. They are rolled on the server only (:770), and the search sound is chosen from the table name.
3. **`add_loot_box(name: String, xf: Transform3D, table: String, bid: int) -> int`** (302): a visible box. It needs both `name` and `name+"_open"` in `ModelLib` (`lootbox_balikbayan`, `_bin`, `_ammocan`, `_footlocker`, `_toolbox`, `_medcase`, `_riflecase`, `_cooler`; `src/world/model_lib.gd:132-147`). It adds collision and a container, and returns -1 if the model is missing.

**Room dressing** (`src/world/dresser.gd`): `dress_room(r: Dictionary, house: Dictionary)` (37) sets `dyn.interior_scope = true`, which picks the interior render layer.
- **Room dict:** `{type, xf: Transform3D (room centre at floor), size: Vector2(w, d), h, bid, zone, door_x?, avoid/avoid2/avoid3: Rect2?, local_z?}`. See `src/world/shanty.gd:213-289`.
- **Room types:** `sala`, `kitchen`, `bed`, `cr`, `store`, `workshop`.
- **`house.kind` values that override room type:** `classroom`, `clinic`, `chapel`/`church` (pews, no boxes), `hall`/`pump` (office plus office boxes), `police`/`outpost` (office plus "armed" boxes).
- **Hidden containers per room** (`_container_on`, :183):
  - `drawer` in sala, bed and others
  - `kitchen`
  - `under_bed` and `wardrobe` in bedrooms
  - `bathroom` in the CR
  - `store_counter` and `store_shelf` in stores
  - `toolbox` in workshops
  - `clinic`
- **Floor loot:** `_floor_loot(ctx, table, chance, most)` (189-205) uses `floor_household` and others.
- **Visible boxes:** `BOXES[type or kind]` (13-27) via `_loot_boxes` (208).
- **Guns on the floor:** `_weapon_spots` (44-57) uses `floor_weapon` in every room, including clinics and classrooms: 72% for the first gun and 36% for a second. Police and outpost buildings get 100/50/25%. The CR gets 20%, at most one.
- **Usual entry point:** `map_builder.shanty(spec)` (281-301) builds the house and calls `dresser.dress_room` for each room (298-299).

**Placing loot on Lawless Sub:**
- **Houses:** produce room dicts and call `dresser.dress_room`, or go through `shanty()`.
- **Convenience store:** a `store` room.
- **Factory:** `workshop` rooms (`box_toolbox`/`box_ammocan` boxes, `toolbox` table).
- **Hand-placed hotspots:** follow `src/world/sites.gd`. Weapon lockers are at :270 and :487-488, and the military camp uses `military_crate` plus `floor_contested` plus boxes at :405-409. Add DM-specific tables to `loot.json` freely.
- **Bot looting:** bots group containers by `bid` and skip `bid < 0` (`bot_brain.gd:101-112`). Interior containers and outer doors need a real `bid`.
- **Performance:** each ground item is one RenderingServer instance with a glow material override and a visibility range of 14 m (gun) or 9 m indoors, and 24 m or 15 m outdoors (`dynamics.gd:881`).

## (f) Gun icons and visuals for a loadout picker

- **No gun icons ship in the game.**
  - `src/ui/icons.gd` only draws vector UI icons; unknown names draw a circle.
  - `assets/ui/` has panels, buttons, backgrounds and `ui/gear/*.png` (49 outfit thumbnails used by `src/ui/locker.gd:264`, which falls back to an `Icons` texture).
- **Existing renders, all untracked in git and outside `game/`:**
  - `work/lemondev/r5/items/<id>.png` exists for all 24 guns: 1000x500, RGBA but with an opaque flat grey background of about (170,171,174), muzzle on the left, whole gun in frame. It was made by `tools/blender/process_items.py`. Each also has `<id>_parts.png` and `<id>.view.json`.
  - `work/lemondev/r5/guns/<id>.png` plus `sheet.png` (900x420, made by `tools/blender/render_guns.py`). The handguns are over-zoomed and cropped, so these are not usable as-is.
  - `tools/gun_grid_sheet.py` only draws u/v grids on the items renders for authoring part boxes. It is not an icon tool.
- **Precedent pipeline:** `tools/make_ui_textures.py:108-124` crops `work/gear/*_front.png` into `game/assets/ui/gear/<stem>.png`. A gun-thumbnail step could do the same from `r5/items/<id>.png`, keying out the grey. Or re-render with `film_transparent = True` using Blender at `C:/Program Files/Blender Foundation/Blender 5.2/blender.exe`, then run `bash tools/import.sh`.
- **Live 3D preview:** `GunModel.parts(id)` (`src/weapons/gun_model.gd:9`, static) loads `res://assets/models/items/<id>.glb` and returns `{role: {mesh, aabb}}` with no map needed.
  - `locker.gd:37-48` shows the SubViewport pattern (`own_world_3d`, `transparent_bg`, lower MSAA on mobile).
  - `map.item_visual(id)` (`dresser.gd:367`) needs a built map, so it cannot be used in a menu.
- **Per-player choice in the lobby:** copy `Net.request_look` / `_req_look` (`src/net/net.gd:304-319`). The player dict comes from `_new_player` (:113); the server validates the value and broadcasts the lobby.