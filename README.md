# Rustbound

Godot 4 prototype of a PS2-style, survivors-like roguelike where you build your robot out of parts, and the build's physics decides how it moves.

## What's playable

- **Socket-graph robots**: Core → Chassis → legs/wheels/treads, mounts, internals, head. Sockets have a type and size; some parts fit more than one type (reactors, batteries, jets).
- **Hardpoint grids**: every chassis face is a small grid of attach cells (the box has 27), so the same parts can go in many places.
- **Frame parts** shape the silhouette: **Struts** reach out 1 m (with a leg socket underneath for wide outrigger stances), **Masts** go up 1.2 m.
- **Rotation**: every part turns in 45° steps (Q/E in build mode). Facing sets weapon and armor arcs and the direction of recoil.
- **Placement matters**:
  - **Links**: parts within 0.75 m of each other (or parent/child) modify each other. Heat Sink halves linked weapons' heat, Reactor overclocks them (+30% fire rate, +30% heat), Gyro tightens their spread, Sensor Head extends their range. Shown as cyan lines.
  - **Real arcs**: Nailgun 120°, Rivet Cannon 70°, Chain Sword 110°, all relative to the way the part faces. The starter has a front and a rear nailgun.
  - **Directional armor**: plates block 60% of hits from the 120° they face; overlapping plates stack.
  - **Turning inertia**: mass far from the center slows turning; compact robots pivot fast.
- **Movement parts fight too**: legs **stomp** on landing (fall speed × mass), wheels **ram** (speed × mass), treads **crush** small enemies and take no bites from them. Each leg past two adds +25% stability and lowers jumps.
- **Active Gyro**: +30% turn speed, knockdowns 65% shorter, recovery shockwave.
- **Rotator**: spins whatever is mounted on it, so guns on it sweep 360°.
- **Chain Sword Arm**: melee, hits everything in its reach and arc; no CPU needed.
- **Physics from the build**: mass, center of mass, support footprint and height are computed from where parts actually sit. They drive acceleration (thrust / mass), top speed (slows past mass capacity, stops at 2×), sideways drift from asymmetric builds, visual lean, and **tipping over** (1.5 s knockdown) when a top-heavy robot turns or brakes too hard. Gyros counter it.
- **Drive modes** (no blending, each has its own controller):
  - **Walker** (legs): nimble, plants its feet to stop, jumps, stomps.
  - **Rover** (wheels): drives along its heading like a car, needs speed to steer, coasts and drifts, rams, no jump.
  - **Tank** (treads): pivots in place until facing where you want, then rolls; slow, crushes, can't be pushed.
  - **Skater** (wheels on legs' feet): glides on momentum, jumps, stomps *and* rams.
  - **Stomper** (treads on legs' feet): slower, anchored, 1.5x stomps, crushes.
  - **Hover** (hover pads, rare): floats 0.5 m up, slides with almost no friction, strafes in any direction while turning to face the nearest enemy. Pads draw 2 power each; in a brownout they lose most of their thrust.
  - **Drivetrains come in pairs**: one Legs / Wheels / Treads / Hover Pads item places a mirrored pair (left + right); detaching either side benches the pair. Add more pairs for 4 or 6. Wheels or treads on leg feet go on as a pair too.
  - Hybrids only happen through a leg's **foot** socket. Different drive types bolted directly to the frame conflict: the majority drives, the rest sit idle, and the HUD and build panel say so.
- **Energy**: power generation minus draw charges a battery (40 + Battery Packs). With the battery full, spare power **overcharges** weapons (up to +50% fire rate). Draw more than you generate and the battery drains; when it's empty you **brown out**: weapons stall and movement drops to 70%. Reactors and batteries fit Internal *or* Mount sockets.
- **Jump Jets**: hold Space in the air to thrust (lift = total jet thrust / mass, gravity is 20), burning 10 energy/s per jet. Two jets on the starter lift it ~10 m; heavy robots need more. Robots without legs can take off on jets alone. Higher falls also mean bigger leg stomps.
- **Budgets**: CPU (weapons without CPU fire straight ahead), HP summed from parts.
- **Nailgun / Rivet Cannon**: auto-firing, mount arcs limit what they can target, recoil pushes the robot.
- **Horde**: MultiMesh enemies in packed arrays with a spatial hash, ramping waves, 3 enemy types. ~600 enemies in GDScript.
- **Pooled projectiles** hit-tested against the spatial hash (no Area3D per bullet).
- **Pickups**: scrap gems are magnet-pulled; parts must be walked over and auto-attach to the free socket that keeps you balanced, or get salvaged for scrap if nothing fits.
- **Level-ups**: scrap fills the XP bar. Each level pauses and offers 3 cards (keys 1-3), or skip to repair 30% (R). Early cards are mostly **upgrades** to parts you already own (Mk I to Mk V, every copy at once); new parts get more likely each level (12% per card at level 2, up to 55%), so the robot gets stronger before it gets chaotic.
- **Upgrades**: each part's `upgrade_per_tier` says what grows per Mk (damage, fire rate, thrust, armor, battery...). Walking over a part you already own upgrades it instead of adding a copy; new copies come from level-up cards.
- **Fewer, more special parts**: part drops are rare (brutes 5%, small enemies ~0.3%) and new-part cards start at 8% per card. Parts have a **rarity** (Common / Rare / Legendary, colored on cards, beams and the bench).
- **Signature parts** (one per run each): **Magnet Arm** (drags small enemies and scrap in), **Tesla Coil** (chain lightning through 5 enemies), **Mortar** (lobs shells into the densest crowd 6-20 m away), **Shield Projector** (legendary: hits from its arc drain battery instead of HP, shoves enemies back), **Scrap Maw** (bites what's in front, eats scrap to repair).
- **More weapons**:
  - **Flamethrower** (common): 5 m, 50° cone of fire in bursts (1.2 s on, 0.8 s off), 40 dps to everything in it.
  - **Boomerang Launcher** (common): throws a blade on a 9 m loop that hits on the way out and back.
  - **Lance Laser** (rare): charges 2.5 s, then a 22 m beam hits every enemy in the line for 45.
  - **Drone Bay** (rare): a little bot orbits you and shoots the nearest enemy.
- **Upgrade paths**: reaching **Mk III** is a fork. The level-up shows both branches side by side and you keep one for the run:
  - Nailgun: Shrapnel (splash) / Cryo Nails (slow). Rivet Cannon: Explosive / Concussion. Chain Sword: Searing (burn) / Hamstring (slow).
  - Flamethrower: Napalm (burn) / Wide Nozzle. Boomerang: Twin Blades / Razor Wind (slow). Laser: Prism (3 beams) / Burning Beam. Drone Bay: Swarm (2nd drone) / Repair Drones.
  - Drivetrains leave **trails**: fire (burns enemies who walk through) or oil / static (slows them to ~45%). Legs: Scorched Steps / Hydraulic Leak. Wheels: Burnout / Oil Slick. Treads: Exhaust Fire / Sludge Treads. Hover: Thermal Wake / Static Field.
  - Enemies show status: orange = burning, blue = slowed.
- **Pickups go to the bench**: overworld parts are never auto-attached; place them in build mode. Level-up parts still auto-install (toggle in build mode).
- **The bench**: new parts auto-install on the most balanced free socket (toggle in build mode); otherwise they go to an 8-slot bench, and overflow is scrapped.
- **Build mode** (Tab): the world pauses (set `BuildMode.pause_world` off to go back to 10% slow motion) and the camera moves in. **Strip to core** sends every part to the bench to rebuild from scratch; detached parts always fit on the bench. Free sockets show as colored dots (gray structural, orange mount, cyan internal, green locomotion); pick a bench part and only the sockets it fits remain. Hover one to see a ghost, Q/E to rotate, click to attach. **M** toggles mirror placement (a second bench copy goes on the mirrored cell, mirrored; rotating a part also turns its twin). Click a part on the robot to rotate, detach (to bench, with everything on it) or scrap it. Overlays: center of mass (pink), footprint (green), links (cyan), weapon arcs (orange), armor arcs (blue).
- **Heat**: weapons add heat per shot, reactors add it passively, heat sinks raise capacity and cooling. Cooling scales with speed (airflow), so kiting cools you and camping bakes you. **Shift vents** all heat as a scalding blast: radius and damage grow with the heat dumped, 6 s cooldown. Over capacity you overheat and take light damage (3 HP/s) until you cool to 80%.
- **Budget HUD**: energy (shows charge rate, OVERCHARGE or BROWNOUT), heat, vent, CPU, mass and tilt bars turn red when you're over. F3 shows the detailed physics readout.
- **PS2 look**: the 3D view renders at ~360 lines and is upscaled with nearest-neighbor, ordered dithering and 15-bit color, while the UI stays sharp. F4 toggles it.

### Controls

| Input | Action |
|---|---|
| WASD / arrows | Move (camera-relative) |
| Space | Jump (legs only) |
| Space (hold) | Jump, then jets while airborne |
| Shift | Vent heat (blast around you) |
| Tab | Build mode (10% time) |
| Left click | Build mode: attach / select |
| Q / E | Build mode: rotate 45° |
| M | Build mode: mirror placement |
| 1 / 2 / 3, R | Level-up: pick a part / repair |
| Right mouse drag | Orbit camera |
| Mouse wheel | Zoom |
| R | Restart run |
| F3 / F4 | Debug readout / PS2 effect |

Weapons fire on their own.

## Open and run

1. Install Godot 4.3+ (4.2 should work).
2. Open the folder in Godot and press Play (F5).

## Tests

```
godot --headless --fixed-fps 60 res://tests/run_tests.tscn
```

196 checks covering assembly math, socket rules, tipping, mass budget, a 20-second simulated run, pickups and the bench, heat, XP/level-ups, the main scene's level-up and build-mode flow (including clicking a socket through the camera), hardpoint grids, rotation, mirroring, frames, links, inertia, leg count, armor, stomp/ram/crush, gyro, rotator, chain sword, upgrades/offers/duplicate merging, strip-to-core, the energy pool (overcharge, drain, brownout), jets, drive modes and hybrids (including simulated walker/skater/rover/tank handling), signature parts, drivetrain pairs, hover, the four new weapons, upgrade paths, splash/slow/burn and trails, and a 600-enemy benchmark. Exit code is non-zero on failure.

## Content

Starter parts and enemies live in `data/parts/*.tres` and `data/enemies/*.tres`. They were generated by `tools/generate_starter_content.gd` (`godot --headless -s tools/generate_starter_content.gd`). Re-running it overwrites the files, so either tune the `.tres` in the inspector or edit the generator, not both.

Adding a part = a `PartData` resource (+ a `PartBehavior` script if it does something). Drop it in `data/parts/` and `LootTable` picks it up automatically (`drop_weight` 0 keeps it out of drops). Behavior tuning goes in `params`.

To try the tippy Tower chassis, swap `chassis_box` for `chassis_tower` on `Robot/RobotAssembly` → `starting_parts` (and update `starting_sockets`: its cells are `bottom_0_0`, `bottom_1_0`, `top`). Socket cell names are `<grid>_<i>_<j>`.

## Project layout

```
autoload/          EventBus, RunState (run state + system refs), LootTable, MetaSave
data/parts|enemies starter content (.tres)
scenes/main.tscn   root: low-res game viewport + UI layers
scenes/levels/     prototype_arena.tscn (3D only; run main.tscn to play)
scripts/data/      PartData, SocketDef, EnemyData
scripts/robot/     RobotAssembly, PartInstance, RobotController, LocomotionProfile, CameraRig, PartVisuals, BuildMode
scripts/behaviors/ PartBehavior, weapons/ (nailgun, chain_sword, flamethrower, boomerang, laser, drone_bay), utility/ (rotator, jet), signature/ (magnet, tesla, mortar, shield, maw)
scripts/systems/   EnemyManager (incl. slow/burn), ProjectilePool, PickupManager, HazardField (trails), UpgradeOffers
scripts/ui/        Hud, LevelUpScreen, BuildPanel, UiStyle
shaders/           ps2_vertex (wobble), ps2_post (dither + quantize)
tests/             run_tests.tscn
tools/             content generator
```

## Known prototype limits

- Enemies ignore obstacles (they path straight at you).
- Drive modes don't check which parts touch the ground (legs on short struts can float a little).
- Level-up offers parts only; components arrive with the Depth milestone.
- Parts are placeholder primitives; `PartData.scene` accepts authored `.glb` scenes, and a `Marker3D` named after a socket overrides its transform.

## Milestone checklist

- [x] Prototype loop
  - [x] Fix scaffold so the project opens and runs
  - [x] Socket attachment with type/size rules and adapters
  - [x] CoM / mass / footprint movement with tip-over
  - [x] Starter enemy spawner and basic wave pressure
  - [x] One weapon behavior and locomotion variants (biped, wheel, tread)
  - [x] Part pickup + attach flow
- [x] Core loop
  - [x] Level-up part choice UI (components come with Depth)
  - [x] Build mode with time slowdown, manual socket placement, detach/scrap
  - [x] Power/heat/CPU/mass/tilt feedback UI
  - [x] Heat simulation and overheat
  - [x] PS2 low-res presentation (pixel upscale, dither, 15-bit color)
- [ ] Exploration depth
  - [ ] Add terrain interaction tags (water, magnetized, weak-floor)
  - [ ] Add wreck-site salvage interactions
  - [ ] Add capability-gated caches
- [ ] Progression and polish
  - [ ] Add hangar/meta progression shell
  - [ ] Add boss encounter stub
