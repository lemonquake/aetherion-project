# Lawless Sub — Deathmatch map #1 (design)

Reference: the user's top-down image (2026-10-28): a city block cut by two concrete canals (a long straight one and an
angular basin), a wide avenue with lane markings, streetlights and a median, an east-west road that bridges the
canal, a big intersection with zebra crossings on every arm, parking lots with painted stalls, bus stops, mid-rise
buildings, a factory with round tanks at the bottom edge, hedges and trees along the canal walk.

Lawless Sub is that city edge grown into a Philippine subdivision that nobody polices any more: a walled estate of
two-storey houses with real interiors, a clubhouse with an empty pool, a chapel and a water tower, entered past an
abandoned guardhouse, bounded by the avenue, the canals and a plastics factory. Doors are broken, gates hang open,
cars are dumped in the streets, and the convenience store on the corner has been picked half clean.

## Size and shape

- World 560 m square (HALF 280), play area 440 m square (PLAY_HALF 220). x = east, z = south, y = up.
- Built at full scale (MAP_SCALE 1.0): the numbers below are real metres.
- For 2 teams of up to 10. Spawns are point-symmetric about the central intersection I = (-20, 0):
  West Team at I + (-150, -150) = (-170, -150) (office plaza parking), East Team at I + (150, 150) = (130, 150)
  (factory loading yard). Both ~212 m from I, ~425 m apart: ~35 s sprint to the middle.

## Water

| Feature | Where | Shape | Play |
|---|---|---|---|
| Lawless Canal | centreline x = -78, from the north edge to z = -10 | 14 m water between vertical concrete walls 2.4 m high; water 0.9 m deep (wade) | Slow, sheltered flank route north-south; ladders down at 4 points; tree walk on the west bank |
| The Basin | south of the boulevard, x -116..-48, z +8..+82, chamfered corners | same walls; deeper middle | Splits the south-west; culvert under the boulevard joins it to the canal |
| Estero | z = +118, x -8..+222 | 8 m channel, sloped banks, 1.0 m deep | Splits the southern subdivision; road bridge (Acacia), footbridge (Narra), pipe crossing (Molave) |

## Roads

| Road | Line | Width | Notes |
|---|---|---|---|
| Lawless Avenue | x = -20, full length | 16 m, 2+2 lanes, 1.2 m median with lamps | Lane dashes, edge lines, stalled jeepney + bus; main sightline N-S (long and dangerous) |
| Sub Boulevard | z = 0, full width | 14 m | Bridges the canal at x = -78 (road bridge, parapets); E-W sightline |
| The Intersection | (-20, 0) | | Zebra crossings on all 4 arms, traffic lights, wreck pile-up = central cover |
| Service Road | x = -150, z -210..+210 | 8 m | Links the office plaza, gas station and mart on the west side |
| Subdivision streets | N-S: Acacia x = +30, Narra x = +100, Molave x = +170. E-W: Sampaguita z = -140, Ilang-Ilang z = -70, Gumamela z = +60, Rosal z = +170 | 7 m concrete | Curbs, parked/burnt cars, low front walls and gates on both sides. Houses face the N-S streets (one row between the perimeter wall and Acacia, two rows back to back between the others, one row east of Molave) |

## Areas (clockwise from the West Team spawn)

1. **Office Plaza (NW, West spawn).** "Lawless Tower": a four-storey concrete office (stair core, corridor and
   offices per floor, glass curtain windows on the plaza side, roof with a parapet and water tank). Parking plaza in
   front with painted stalls and cars; a guard booth; exit ramp marked OUT. Strong for the spawn team but its roof
   is exposed to the canal row across the water.
2. **Canal Row (west of the avenue).** Two- and three-storey shophouses facing the avenue, their backs on the canal
   walk; a bus stop and a waiting shed at the intersection. Close-quarters fights above the avenue.
3. **The Gate (Ilang-Ilang St at the avenue).** The subdivision wall (2.4 m concrete, gaps and a collapsed stretch)
   runs along the avenue's east side; the arch gate with a guardhouse and a barrier is the obvious choke, the breaches
   are the flanks.
4. **Phase 1 (NE blocks).** Rows of two-storey houses (sala, kitchen, dining, toilet and stair downstairs; two or
   three bedrooms and a bathroom upstairs), front yards behind low walls and gates, carports, back yards against the
   next row. Water tower landmark in the NE corner.
5. **Clubhouse block (centre-east, north of the boulevard).** Two-storey clubhouse (function hall, office, kitchen,
   roof deck), covered basketball court, empty swimming pool (sunken cover), playground. The centre of the east half.
6. **Phase 2 (SE blocks).** More houses, a chapel, the estero with its three crossings.
7. **Lawless Plastics (SE, East spawn).** Factory hall (40 x 26 m, 9 m high): machine lines, a mezzanine catwalk with
   stairs, offices; round storage tanks outside, a loading dock with roller doors, a warehouse and container stacks,
   forklifts. Strong for the spawn team, but the tanks and stacks give attackers cover up to the walls.
8. **Lawless Mart corner (SW).** 24-hour convenience store (glass front, aisles of shelves, chiller wall, counter
   and till, stock room, back door, ladder to the roof), a strip of four shops (pharmacy, eatery, laundromat,
   hardware), a large parking lot with stalls and wrecks, the gas station on the boulevard.
9. **Old Barangay (far SW).** Denser older houses (the classic map's mixed district) between the mart and the basin.

## Rules every building follows (from the classic map)

- Real interiors: rooms with plausible functions and furniture (dresser), lights in only some rooms, dark inside.
- Ground-floor windows are sized to vault through (sill 0.8-0.9 m, opening >= 1.1 m tall, >= 0.95 m wide): open
  frames vault at once; glass ones break first. No building with a single entrance.
- Doors open away from the player, can be shot through and broken into panels; props have physics and break into
  chunks; loot (weapons, ammo, meds, armour) in rooms and containers; acoustic zones and portals per room.
- Stairs follow the shanty rules (openings 0.6 m past the flight foot, rails that let out sideways).

## Sightline and balance notes

- The avenue and the boulevard are the two long lanes (400 m); both are broken by the wreck pile at the
  intersection, the median lamps and the stalled jeepney/bus so a sniper sees stretches, not the whole lane.
- No building sees both spawns. The tower roof overlooks the canal row and the north half of the avenue only; the
  factory catwalk sees the estero and Rosal St only.
- Each spawn has three ways out (West: service road south, canal walk east, plaza north-east to the bridge; East:
  Molave St north, the estero bridges west, Rosal St west).
- Loot value rises toward the middle: armour and rifles in the clubhouse, the mart stock room and the tower's top
  floor; pistol ammo and meds in houses.

## Zone (Deathmatch)

First circle covers the whole play area; its centre is picked within 60 m of the intersection so neither spawn is
favoured; later circles shrink inside the current one (random, on dry land). Phases (wait / shrink seconds):
60/60 to 0.55, 45/45 to 0.32, 40/40 to 0.18, 30/30 to 0.08, 25/25 to 0: about 6.7 minutes to a closed zone.

## Day and night

Same 5-minute night / 5-minute day cycle as Classic; a round starts at a random point in the cycle so roughly half the
rounds see dusk or dawn mid-fight.
