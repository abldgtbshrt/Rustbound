class_name LocomotionProfile
extends RefCounted

## The robot's drive mode and its movement stats. Drive types don't blend:
## each mode has its own controller (see RobotController), so a legged robot
## and a wheeled one feel distinct.
##
##   WALKER   legs           nimble, strafes, jumps, stomps
##   ROVER    wheels         momentum, steers like a car, drifts, rams, no jump
##   TANK     treads         pivots in place, slow, crushes, can't be pushed
##   SKATER   legs + wheels on their feet: glides on momentum, jumps, stomps, rams
##   STOMPER  legs + treads on their feet: heavy walker, big stomps, crushes
##   BALL     nothing: the core rolls
##
## Hybrids only happen through a leg's foot socket. Different drive types
## mounted directly on the frame conflict: the majority type drives, the rest
## sit idle (dead weight) and build mode says so.

enum Mode { BALL, WALKER, ROVER, TANK, SKATER, STOMPER }

const MODE_NAMES := ["Ball", "Walker", "Rover", "Tank", "Skater", "Stomper"]

var mode: Mode = Mode.BALL
var top_speed: float = 4.0
var thrust: float = 10.0
## Sideways grip: 1 = no drift, low = slides through turns.
var grip: float = 0.3
## Speed lost per second when not accelerating (fraction). Low = glides.
var coast_drag: float = 2.0
var jump_force: float = 0.0
var mass_capacity: float = 3.0
var turn_rate_deg: float = 240.0
var can_jump: bool = false
var is_ball: bool = true
## Recoil and shoves barely move it.
var anchored: bool = false
var part_count: int = 0
var leg_count: int = 0
var stomp: float = 0.0
var ram: float = 0.0
var crush: float = 0.0
## Locomotion parts not driving (conflicting drive types).
var idle_parts: Array[PartInstance] = []
## Human-readable reason, e.g. "2 Scrap Wheel idle: legs drive".
var conflict: String = ""

const JUMP_LOSS_PER_EXTRA_LEG := 0.22
const STABILITY_PER_EXTRA_LEG := 0.25


func mode_name() -> String:
	return MODE_NAMES[mode]


func extra_leg_stability() -> float:
	return STABILITY_PER_EXTRA_LEG * float(maxi(leg_count - 2, 0))


## entries: Array of [PartInstance, Vector3 (assembly-local mass point)] for
## every locomotion part. Stats are read at each part's upgrade tier.
static func resolve(entries: Array, center_of_mass: Vector3) -> LocomotionProfile:
	var prof := LocomotionProfile.new()
	if entries.is_empty():
		return prof

	# Split frame-mounted drive parts from boots (parts on a leg's foot).
	var frame: Dictionary = {} # Drive -> Array of entries
	var boots: Dictionary = {}
	for e in entries:
		var inst: PartInstance = e[0]
		var kind := int(inst.data.drive)
		if kind == PartData.Drive.NONE:
			continue
		var on_leg := inst.parent_part != null and inst.parent_part.data.drive == PartData.Drive.LEG
		var bucket: Dictionary = boots if on_leg else frame
		if not bucket.has(kind):
			bucket[kind] = []
		(bucket[kind] as Array).append(e)
	if frame.is_empty():
		return prof

	# Majority drive type wins; ties prefer legs, then treads, then wheels.
	var winner := -1
	var best := -1
	for kind in [PartData.Drive.LEG, PartData.Drive.TREAD, PartData.Drive.WHEEL]:
		var n: int = (frame.get(kind, []) as Array).size()
		if n > best:
			best = n
			winner = kind
	var idle_names: Dictionary = {}
	for kind in frame.keys():
		if kind == winner:
			continue
		for e in frame[kind]:
			prof.idle_parts.append(e[0])
			var nm: String = (e[0] as PartInstance).data.get_display_name()
			idle_names[nm] = int(idle_names.get(nm, 0)) + 1
	var active: Array = frame[winner]

	prof.is_ball = false
	prof.part_count = active.size()
	_base_stats(prof, active, center_of_mass)

	match winner:
		PartData.Drive.LEG:
			prof.leg_count = active.size()
			# Boots decide the hybrid: whichever kind is on most legs.
			var wheels: Array = boots.get(PartData.Drive.WHEEL, [])
			var treads: Array = boots.get(PartData.Drive.TREAD, [])
			var half := ceili(active.size() / 2.0)
			if wheels.size() >= half and wheels.size() >= treads.size():
				_skater(prof, wheels)
				for e in treads:
					prof.idle_parts.append(e[0])
			elif treads.size() >= half:
				_stomper(prof, treads)
				for e in wheels:
					prof.idle_parts.append(e[0])
			else:
				_walker(prof)
				for e in wheels + treads:
					prof.idle_parts.append(e[0])
		PartData.Drive.WHEEL:
			_rover(prof, active)
		PartData.Drive.TREAD:
			_tank(prof, active)

	if not idle_names.is_empty():
		var parts: PackedStringArray = []
		for nm in idle_names.keys():
			parts.append("%d %s" % [idle_names[nm], nm])
		prof.conflict = "%s idle: %s drive" % [", ".join(parts), ["", "legs", "wheels", "treads"][winner]]
	return prof


static func _base_stats(prof: LocomotionProfile, active: Array, com: Vector3) -> void:
	prof.top_speed = 0.0
	prof.thrust = 0.0
	prof.grip = 0.0
	prof.jump_force = 0.0
	prof.mass_capacity = 0.0
	prof.turn_rate_deg = 0.0
	var total_w := 0.0
	for e in active:
		var inst: PartInstance = e[0]
		var d := inst.data
		var p: Vector3 = e[1]
		var w := 1.0 / (0.25 + Vector2(p.x - com.x, p.z - com.z).length())
		total_w += w
		prof.top_speed += inst.stat("top_speed", d.top_speed) * w
		prof.grip += d.grip * w
		prof.jump_force += inst.stat("jump_force", d.jump_force) * w
		prof.turn_rate_deg += d.turn_rate_deg * w
		prof.thrust += inst.stat("thrust", d.thrust)
		prof.mass_capacity += inst.stat("mass_capacity", d.mass_capacity)
		prof.stomp += inst.stat("stomp", float(d.params.get("stomp", 0.0)))
		prof.ram += inst.stat("ram", float(d.params.get("ram", 0.0)))
		prof.crush += inst.stat("crush", float(d.params.get("crush", 0.0)))
	prof.top_speed /= total_w
	prof.grip /= total_w
	prof.jump_force /= total_w
	prof.turn_rate_deg /= total_w


static func _boot_sum(boots: Array, key: String, prop: bool = false) -> float:
	var t := 0.0
	for e in boots:
		var inst: PartInstance = e[0]
		var base: float = float(inst.data.get(key)) if prop else float(inst.data.params.get(key, 0.0))
		t += inst.stat(key, base)
	return t


static func _legs_jump(prof: LocomotionProfile) -> void:
	if prof.leg_count > 2:
		prof.jump_force /= 1.0 + JUMP_LOSS_PER_EXTRA_LEG * float(prof.leg_count - 2)
	prof.can_jump = prof.jump_force > 0.5


static func _walker(prof: LocomotionProfile) -> void:
	prof.mode = Mode.WALKER
	prof.grip = 1.0
	prof.coast_drag = 8.0
	_legs_jump(prof)


static func _skater(prof: LocomotionProfile, wheels: Array) -> void:
	prof.mode = Mode.SKATER
	prof.top_speed = prof.top_speed * 1.6 + 2.0
	prof.thrust *= 0.8
	prof.grip = 0.5
	prof.coast_drag = 0.35
	prof.mass_capacity += _boot_sum(wheels, "mass_capacity", true) * 0.5
	prof.ram += _boot_sum(wheels, "ram")
	prof.jump_force *= 0.9
	_legs_jump(prof)


static func _stomper(prof: LocomotionProfile, treads: Array) -> void:
	prof.mode = Mode.STOMPER
	prof.top_speed *= 0.75
	prof.thrust *= 1.2
	prof.grip = 1.0
	prof.coast_drag = 10.0
	prof.anchored = true
	prof.mass_capacity += _boot_sum(treads, "mass_capacity", true)
	prof.stomp *= 1.5
	prof.crush += _boot_sum(treads, "crush")
	prof.jump_force *= 0.6
	prof.turn_rate_deg *= 0.7
	_legs_jump(prof)


static func _rover(prof: LocomotionProfile, _active: Array) -> void:
	prof.mode = Mode.ROVER
	prof.coast_drag = 0.6
	prof.jump_force = 0.0
	prof.can_jump = false


static func _tank(prof: LocomotionProfile, _active: Array) -> void:
	prof.mode = Mode.TANK
	prof.coast_drag = 12.0
	prof.grip = 1.0
	prof.anchored = true
	prof.jump_force = 0.0
	prof.can_jump = false
