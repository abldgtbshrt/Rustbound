class_name LocomotionProfile
extends RefCounted

## Movement stats blended from every attached locomotion part. Parts closer to
## the center of mass carry more load, so they count for more in the blend.

var top_speed: float = 4.0
var thrust: float = 10.0
var grip: float = 0.3
var jump_force: float = 0.0
var mass_capacity: float = 3.0
var turn_rate_deg: float = 240.0
var can_jump: bool = false
var is_ball: bool = true
var part_count: int = 0
## Parts tagged "leg". More legs: more capacity and stability, lower jumps.
var leg_count: int = 0
## Locomotion attacks, summed from part params "stomp", "ram", "crush".
var stomp: float = 0.0
var ram: float = 0.0
var crush: float = 0.0

## Jump height lost per leg beyond two.
const JUMP_LOSS_PER_EXTRA_LEG := 0.22
## Tip resistance gained per leg beyond two.
const STABILITY_PER_EXTRA_LEG := 0.25


func extra_leg_stability() -> float:
	return STABILITY_PER_EXTRA_LEG * float(maxi(leg_count - 2, 0))


## entries: Array of [PartInstance, Vector3 (assembly-local mass point)].
## Stats are read at each part's upgrade tier.
static func blend(entries: Array, center_of_mass: Vector3) -> LocomotionProfile:
	var prof := LocomotionProfile.new()
	if entries.is_empty():
		return prof # Core-only "ball" fallback.

	prof.is_ball = false
	prof.part_count = entries.size()
	prof.top_speed = 0.0
	prof.thrust = 0.0
	prof.grip = 0.0
	prof.jump_force = 0.0
	prof.mass_capacity = 0.0
	prof.turn_rate_deg = 0.0

	var total_w := 0.0
	for e in entries:
		var inst: PartInstance = e[0]
		var d := inst.data
		var p: Vector3 = e[1]
		var dist := Vector2(p.x - center_of_mass.x, p.z - center_of_mass.z).length()
		var w := 1.0 / (0.25 + dist)
		total_w += w
		prof.top_speed += inst.stat("top_speed", d.top_speed) * w
		prof.grip += d.grip * w
		prof.jump_force += inst.stat("jump_force", d.jump_force) * w
		prof.turn_rate_deg += d.turn_rate_deg * w
		prof.thrust += inst.stat("thrust", d.thrust)
		prof.mass_capacity += inst.stat("mass_capacity", d.mass_capacity)
		if d.tags.has("leg"):
			prof.leg_count += 1
		prof.stomp += inst.stat("stomp", float(d.params.get("stomp", 0.0)))
		prof.ram += inst.stat("ram", float(d.params.get("ram", 0.0)))
		prof.crush += inst.stat("crush", float(d.params.get("crush", 0.0)))

	prof.top_speed /= total_w
	prof.grip /= total_w
	prof.jump_force /= total_w
	prof.turn_rate_deg /= total_w
	if prof.leg_count > 2:
		prof.jump_force /= 1.0 + JUMP_LOSS_PER_EXTRA_LEG * float(prof.leg_count - 2)
	prof.can_jump = prof.jump_force > 0.5
	return prof
