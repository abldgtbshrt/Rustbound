# Rustbound

Godot 4 prototype scaffold for a PS2-style low-poly robot roguelike.

## What is currently scaffolded

- Data-driven part resources (`PartData`, `SocketDef`)
- Runtime robot assembly foundation (`RobotAssembly`, `PartInstance`)
- Basic robot movement controller (`RobotController`)
- Extensible part behavior base class (`PartBehavior`)
- Foundational autoload systems (`EventBus`, `RunState`, `MetaSave`, `LootTable`)
- Retro starter shader (`shaders/ps2_vertex.gdshader`)
- Prototype scene wiring (`scenes/levels/prototype_arena.tscn`)
- Organized folder layout for gameplay/content iteration

## Open and run

1. Install Godot 4.2+.
2. Clone this repository.
3. Open the folder in Godot.
4. Press Play (F5) to run `prototype_arena.tscn`.

## Notes

- This is a foundation PR-level scaffold, not full gameplay.
- The movement/assembly systems are intentionally minimal and compile-safe.
- Content and systems are designed to be expanded incrementally.

## Near-term milestone checklist

- [ ] Prototype loop
  - [ ] Add starter enemy spawner and basic wave pressure
  - [ ] Add one weapon behavior and one locomotion variant profile
  - [ ] Add simple part pickup + attach flow
- [ ] Core loop
  - [ ] Add level-up part/component choice UI
  - [ ] Add build mode with time slowdown
  - [ ] Add power/heat/cpu feedback UI
- [ ] Exploration depth
  - [ ] Add terrain interaction tags (water, magnetized, weak-floor)
  - [ ] Add wreck-site salvage interactions
  - [ ] Add capability-gated caches
- [ ] Progression and polish
  - [ ] Add hangar/meta progression shell
  - [ ] Add boss encounter stub
  - [ ] Add PS2 post effects (dither/fog/pixel upscale)
