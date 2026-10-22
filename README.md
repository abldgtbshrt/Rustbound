# Rustbound

Godot 4 prototype of a PS2-style, survivors-like roguelike where you build your robot out of parts, and the build's physics decides how it moves.

## What's playable

- **Socket-graph robots**: Core → Chassis → legs/wheels/treads, mounts, internals, head. Sockets have a type and size; adapters convert socket types (e.g. a wheel on a side mount).
- **Hardpoint grids**: every chassis face is a small grid of attach cells (the box has 27), so the same parts can go in many places.
- **Frame parts** shape the silhouette: **Struts** reach out 1 m (with a leg socket underneath for wide outrigger stances), **Masts** go up 1.2 m, **Junction Hubs** branch in four directions.
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
- **Blended locomotion**: every locomotion part contributes; parts nearer the CoM carry more load. Low-grip wheels drift, treads are slow and recoil-proof, legs jump.
- **Budgets**: power (brownout makes weapons stutter), CPU (weapons without CPU fire straight ahead), HP summed from parts.
- **Nailgun / Rivet Cannon**: auto-firing, mount arcs limit what they can target, recoil pushes the robot.
- **Horde**: MultiMesh enemies in packed arrays with a spatial hash, ramping waves, 3 enemy types. ~600 enemies in GDScript.
- **Pooled projectiles** hit-tested against the spatial hash (no Area3D per bullet).
- **Pickups**: scrap gems are magnet-pulled; parts must be walked over and auto-attach to the free socket that keeps you balanced, or get salvaged for scrap if nothing fits.
- **Level-ups**: scrap fills the XP bar. Each level pauses and offers 3 parts (keys 1-3), or skip to repair 30% (R).
- **The bench**: new parts auto-install on the most balanced free socket (toggle in build mode); otherwise they go to an 8-slot bench, and overflow is scrapped.
- **Build mode** (Tab): the world drops to 10% speed and the camera moves in. Free sockets show as colored dots (gray structural, orange mount, cyan internal, green locomotion); pick a bench part and only the sockets it fits remain. Hover one to see a ghost, Q/E to rotate, click to attach. **M** toggles mirror placement (a second bench copy goes on the mirrored cell, mirrored; rotating a part also turns its twin). Click a part on the robot to rotate, detach (to bench, with everything on it) or scrap it. Overlays: center of mass (pink), footprint (green), links (cyan), weapon arcs (orange), armor arcs (blue).
- **Heat**: weapons add heat per shot, reactors add it passively, heat sinks raise capacity and cooling. Cooling scales with speed (airflow), so kiting cools you and camping bakes you. **Shift vents** all heat as a scalding blast: radius and damage grow with the heat dumped, 6 s cooldown. Over capacity you overheat and take light damage (3 HP/s) until you cool to 80%.
- **Budget HUD**: power, heat, CPU, mass and tilt bars turn red when you're over. F3 shows the detailed physics readout.
- **PS2 look**: the 3D view renders at ~360 lines and is upscaled with nearest-neighbor, ordered dithering and 15-bit color, while the UI stays sharp. F4 toggles it.

### Controls

| Input | Action |
|---|---|
| WASD / arrows | Move (camera-relative) |
| Space | Jump (legs only) |
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

115 checks covering assembly math, socket rules, tipping, mass budget, a 20-second simulated run, pickups and the bench, heat, XP/level-ups, the main scene's level-up and build-mode flow (including clicking a socket through the camera), hardpoint grids, rotation, mirroring, frames, links, inertia, leg count, armor, stomp/ram/crush, gyro, rotator, chain sword, and a 600-enemy benchmark. Exit code is non-zero on failure.

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
scripts/behaviors/ PartBehavior, weapons/ (nailgun, chain_sword), utility/ (rotator)
scripts/systems/   EnemyManager, ProjectilePool, PickupManager
scripts/ui/        Hud, LevelUpScreen, BuildPanel, UiStyle
shaders/           ps2_vertex (wobble), ps2_post (dither + quantize)
tests/             run_tests.tscn
tools/             content generator
```

## Known prototype limits

- Enemies ignore obstacles (they path straight at you).
- Blended locomotion doesn't check which parts touch the ground (legs on short struts can float a little).
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
