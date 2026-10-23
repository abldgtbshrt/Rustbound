class_name RobotController
extends CharacterBody3D

## Moves the robot using stats derived from its assembly: mass, thrust,
## grip, center of mass and support footprint.

@export var gravity: float = 20.0
## Sideways drift per meter of center-of-mass offset, at full speed.
@export var drift_factor: float = 1.2
## Scales how much acceleration contributes to tipping. Lower = sturdier.
@export var tip_sensitivity: float = 0.5
@export var tip_threshold: float = 1.0
## How long the tip ratio must stay above threshold before falling over.
@export var tip_grace: float = 0.12
@export var knockdown_time: float = 1.5
@export var max_visual_lean_deg: float = 18.0
@export var base_pickup_radius: float = 2.5
@export var base_hp: float = 50.0

@export_group("Energy")
## Battery size before Battery parts. Surplus power charges it; deficits and
## jets drain it. Empty = brownout.
@export var base_energy_capacity: float = 40.0
## Max weapon fire-rate bonus when the battery is full and power is spare.
@export var max_overcharge: float = 0.5
## Movement speed while browned out.
@export var brownout_speed_mult: float = 0.7
## Brownout clears once the battery refills to this fraction.
@export var brownout_recover_frac: float = 0.15

@export_group("Jets")
## Upward speed cap while thrusting.
@export var jet_max_rise_speed: float = 7.0

@export_group("Heat")
@export var base_heat_capacity: float = 100.0
## Cooling while standing still. Moving adds airflow cooling on top.
@export var base_heat_dissipation: float = 2.0
## Extra cooling per m/s of horizontal speed: kiting cools, camping bakes.
@export var airflow_cooling_per_mps: float = 1.2
@export var overheat_dps: float = 3.0
## Overheat clears once heat drops below this fraction of capacity.
@export var overheat_recover_frac: float = 0.8

@export_group("Locomotion attacks")
## Leg stomp on landing: damage = fall speed x mass x this (x stomp power).
@export var stomp_damage_factor: float = 0.45
@export var stomp_min_fall_speed: float = 3.0
## Wheel ram: damage = speed x mass x this (x ram power) per hit.
@export var ram_damage_factor: float = 0.3
@export var ram_min_speed: float = 3.5
@export var ram_cooldown: float = 0.5
## Tread crush: damage per second (x crush power) to enemies this small or smaller.
@export var crush_dps: float = 60.0
@export var crush_max_enemy_radius: float = 0.45

@export_group("Vent")
## Shift dumps all heat as a scalding blast around the robot.
@export var vent_cooldown: float = 6.0
## Minimum heat needed to vent (prevents spamming it as a free attack).
@export var vent_min_heat: float = 15.0
@export var vent_base_radius: float = 3.0
## Extra blast radius per point of heat dumped.
@export var vent_radius_per_heat: float = 0.035
@export var vent_max_radius: float = 8.0
## Damage per point of heat dumped (falls off to 50% at the edge).
@export var vent_damage_per_heat: float = 0.6
@export var vent_knockback: float = 9.0

@onready var assembly: RobotAssembly = $RobotAssembly
@onready var collision: CollisionShape3D = $CollisionShape3D

## Set by the camera rig so WASD is camera-relative.
var camera_yaw: float = 0.0

var hp: float = 0.0
var max_hp: float = 0.0
var alive: bool = true

## Current tip ratio (1.0 = at the edge of falling over). Read by the HUD.
var tip_ratio: float = 0.0
var is_knocked_down: bool = false

var energy: float = 0.0
## Power stalled: battery empty while drawing more than you generate.
var browned_out: bool = false
## Net power this frame (generation - draw - jets), per second.
var power_net: float = 0.0
var is_jetting: bool = false

var heat: float = 0.0
var is_overheated: bool = false
## Seconds until the vent is ready again.
var vent_cooldown_left: float = 0.0

var _accel_smoothed := Vector3.ZERO
var _tip_timer := 0.0
var _knockdown_t := 0.0
var _knockdown_axis := Vector3.RIGHT
var _was_on_floor := true
var _fall_speed := 0.0
var _trail_dist := 0.0
var _last_pos := Vector3.ZERO
var _bob_t := 0.0


func _ready() -> void:
	RunState.robot = self
	assembly.assembly_changed.connect(_on_assembly_changed)
	assembly.build(self)
	hp = max_hp
	energy = get_energy_capacity()


func _exit_tree() -> void:
	if RunState.robot == self:
		RunState.robot = null


func get_mass() -> float:
	return maxf(assembly.total_mass, 0.25)


func get_load_ratio() -> float:
	return assembly.total_mass / maxf(assembly.locomotion.mass_capacity, 0.1)


## 1.0 when within capacity, 0.0 at double capacity (can't move).
func get_speed_multiplier() -> float:
	var load := get_load_ratio()
	var m := 1.0 if load <= 1.0 else clampf(2.0 - load, 0.0, 1.0)
	return m * (brownout_speed_mult if browned_out else 1.0)


func get_energy_capacity() -> float:
	return base_energy_capacity + assembly.energy_capacity


## Fire-rate multiplier for weapons: up to 1 + max_overcharge when the battery
## is full and generation exceeds draw. Spare power is never wasted.
func get_overcharge_mult() -> float:
	if browned_out or energy < get_energy_capacity() - 0.01:
		return 1.0
	var spare := assembly.power_gen - assembly.power_draw
	if spare <= 0.0:
		return 1.0
	return 1.0 + max_overcharge * clampf(spare / maxf(assembly.power_gen, 1.0), 0.0, 1.0)


## 0..1: how much of their demand powered parts get. 1 unless browned out.
func get_power_supply() -> float:
	return assembly.get_power_ratio() if browned_out else 1.0


func get_top_speed() -> float:
	return assembly.locomotion.top_speed * get_speed_multiplier()


func get_pickup_radius() -> float:
	return base_pickup_radius + assembly.pickup_radius


func get_body_radius() -> float:
	return clampf(assembly.half_width, 0.35, 1.5)


func _physics_process(delta: float) -> void:
	var prof := assembly.locomotion
	var mass := get_mass()

	var input := Vector2.ZERO
	if alive and not is_knocked_down:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera_yaw)
	if dir.length() > 1.0:
		dir = dir.normalized()

	if prof.mode != LocomotionProfile.Mode.HOVER:
		assembly.position.y = 0.0
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var start_hvel := hvel
	var accel := prof.thrust / mass
	if is_knocked_down:
		hvel = hvel.move_toward(Vector3.ZERO, 6.0 * delta) # sliding on your side
	else:
		match prof.mode:
			LocomotionProfile.Mode.ROVER:
				hvel = _move_vehicle(hvel, dir, delta, accel, false)
			LocomotionProfile.Mode.TANK:
				hvel = _move_vehicle(hvel, dir, delta, accel, true)
			LocomotionProfile.Mode.HOVER:
				hvel = _move_hover(hvel, dir, delta, accel)
			_:
				hvel = _move_free(hvel, dir, delta, accel)

	# Asymmetry: an off-center center of mass pulls the robot to that side.
	if hvel.length() > 0.2 and alive:
		var side := global_basis.x * assembly.center_of_mass.x
		var speed_frac := clampf(hvel.length() / maxf(prof.top_speed, 0.1), 0.0, 1.0)
		hvel += side * drift_factor * speed_frac * delta * 4.0

	velocity.x = hvel.x
	velocity.z = hvel.z

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		try_jump()
	_update_jets(delta, Input.is_action_pressed("jump"))

	if not is_on_floor():
		_fall_speed = maxf(_fall_speed, -velocity.y)
	move_and_slide()

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		if alive and _fall_speed >= stomp_min_fall_speed and prof.stomp > 0.0:
			stomp(_fall_speed)
		for b in assembly.get_all_behaviors():
			b.on_land()
	if on_floor:
		_fall_speed = 0.0
	_was_on_floor = on_floor

	_update_energy(delta)
	_update_trail(delta)
	_update_heat(delta)
	_update_tipping(delta, (hvel - start_hvel) / maxf(delta, 0.0001))

	if alive:
		for b in assembly.get_all_behaviors():
			b.on_tick(delta)


## Walker / Skater / Stomper / Ball: move toward the input direction and
## face it. Walkers stop on a dime; skaters and balls keep their momentum and
## carve through turns.
func _move_free(hvel: Vector3, dir: Vector3, delta: float, accel: float) -> Vector3:
	var prof := assembly.locomotion
	var glides := prof.mode == LocomotionProfile.Mode.SKATER or prof.mode == LocomotionProfile.Mode.BALL
	if dir.length() > 0.1:
		var desired := dir * get_top_speed()
		var dv := desired - hvel
		if hvel.length() > 0.5:
			var fwd := hvel.normalized()
			var along := fwd * dv.dot(fwd)
			var perp := dv - along
			dv = along + perp * lerpf(0.25, 1.0, prof.grip)
		hvel += dv.limit_length(accel * delta)
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = rotate_toward(rotation.y, target_yaw, deg_to_rad(get_turn_rate_deg()) * delta)
	elif glides:
		hvel = hvel.move_toward(Vector3.ZERO, maxf(prof.coast_drag * hvel.length(), 0.3) * delta)
	else:
		# Feet plant: walkers brake much harder than they accelerate.
		hvel = hvel.move_toward(Vector3.ZERO, maxf(accel * 3.0, 15.0) * delta)
	return hvel


## Hover: slides toward the input in any direction without turning to face
## it. The robot turns to face the nearest enemy instead (or the way it's
## drifting if nothing's around). Pads need power: brownout = 40% thrust.
func _move_hover(hvel: Vector3, dir: Vector3, delta: float, accel: float) -> Vector3:
	var prof := assembly.locomotion
	if browned_out:
		accel *= 0.4
	if dir.length() > 0.1:
		var dv := dir * get_top_speed() - hvel
		hvel += dv.limit_length(accel * delta)
	else:
		hvel = hvel.move_toward(Vector3.ZERO, maxf(prof.coast_drag * hvel.length(), 0.2) * delta)
	var face := Vector3.ZERO
	if RunState.enemies != null:
		var i := RunState.enemies.find_nearest(global_position, 18.0)
		if i >= 0:
			face = RunState.enemies.pos[i] - global_position
	if face == Vector3.ZERO and hvel.length() > 1.0:
		face = hvel
	face.y = 0.0
	if face.length_squared() > 0.01:
		rotation.y = rotate_toward(rotation.y, atan2(-face.x, -face.z), deg_to_rad(get_turn_rate_deg()) * delta)
	# Gentle bob so it reads as floating.
	_bob_t += delta
	assembly.position.y = sin(_bob_t * 2.5) * 0.06
	return hvel


## Trail paths on the drivetrain (fire / oil / static) leave ground patches
## every so often while moving.
func _update_trail(_delta: float) -> void:
	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	_last_pos = global_position
	if RunState.hazards == null or not alive or moved > 3.0:
		return
	var trail := _trail_params()
	if trail.is_empty():
		return
	_trail_dist += moved
	if _trail_dist < float(trail.get("trail_spacing", 0.8)):
		return
	_trail_dist = 0.0
	var kind := HazardField.Kind.FIRE
	match String(trail["trail"]):
		"oil": kind = HazardField.Kind.OIL
		"static": kind = HazardField.Kind.STATIC
	RunState.hazards.spawn(global_position, kind, float(trail.get("trail_radius", 1.1)), float(trail.get("trail_life", 4.0)), float(trail.get("trail_strength", 8.0)))


func _trail_params() -> Dictionary:
	for inst in assembly.locomotion.active_parts:
		if not is_instance_valid(inst):
			continue
		var path := inst.get_chosen_path()
		var pp: Dictionary = path.get("params", {})
		if pp.has("trail"):
			return pp
	return {}


## Rover / Tank: the robot drives along its heading. Rovers steer like a car
## (steering needs speed), carry momentum and drift with low grip. Tanks pivot
## in place until they face where you want to go, then roll forward.
func _move_vehicle(hvel: Vector3, dir: Vector3, delta: float, accel: float, pivot: bool) -> Vector3:
	var prof := assembly.locomotion
	var turn := deg_to_rad(get_turn_rate_deg())
	var heading := -global_basis.z
	heading.y = 0.0
	heading = heading.normalized()
	var speed := hvel.dot(heading)
	var target_speed := 0.0
	if dir.length() > 0.1:
		var target_yaw := atan2(-dir.x, -dir.z)
		var diff := absf(angle_difference(rotation.y, target_yaw))
		if pivot:
			rotation.y = rotate_toward(rotation.y, target_yaw, turn * delta)
			if diff < deg_to_rad(35.0):
				target_speed = get_top_speed() * dir.length() * cos(diff)
		else:
			var authority := clampf(absf(speed) / 4.0, 0.25, 1.0)
			rotation.y = rotate_toward(rotation.y, target_yaw, turn * authority * delta)
			target_speed = get_top_speed() * dir.length() if diff < deg_to_rad(110.0) else -get_top_speed() * 0.35
		speed = move_toward(speed, target_speed, accel * delta)
	else:
		speed = move_toward(speed, 0.0, maxf(prof.coast_drag * absf(speed), 0.4) * delta)
	# Re-read heading after steering: whatever velocity no longer points
	# along it is sideways slip, which grip scrubs off (low grip = drift).
	var new_heading := -global_basis.z
	new_heading.y = 0.0
	new_heading = new_heading.normalized()
	var raw := (hvel - heading * hvel.dot(heading)) + heading * speed
	var fwd := raw.dot(new_heading)
	var slip := (raw - new_heading * fwd).move_toward(Vector3.ZERO, prof.grip * 25.0 * delta)
	return new_heading * fwd + slip


## Jets fire while jump is held: in the air, or from the ground if the robot
## can't jump. Thrust / mass lifts you; each jet burns battery energy.
func _update_jets(delta: float, holding: bool) -> void:
	var asm := assembly
	var want := holding and alive and not is_knocked_down and asm.jet_thrust > 0.0 and energy > 0.0 and not browned_out
	if want and is_on_floor() and asm.locomotion.can_jump and velocity.y <= 0.01:
		want = false # legs jump first; jets take over once airborne
	is_jetting = want
	if not want:
		return
	var lift := asm.jet_thrust / get_mass()
	velocity.y = minf(velocity.y + lift * delta, jet_max_rise_speed)


func _update_energy(delta: float) -> void:
	var asm := assembly
	var jet_draw := asm.jet_energy_per_sec if is_jetting else 0.0
	power_net = asm.power_gen - asm.power_draw - jet_draw
	var cap := get_energy_capacity()
	energy = clampf(energy + power_net * delta, 0.0, cap)
	if not browned_out and energy <= 0.0 and power_net < 0.0:
		browned_out = true
		EventBus.robot_brownout.emit()
		for b in asm.get_all_behaviors():
			b.on_brownout()
	elif browned_out and (energy >= cap * brownout_recover_frac or power_net >= 0.0 and energy > 0.0):
		browned_out = false
		EventBus.robot_power_restored.emit()


## Jumps if on the floor with jump-capable locomotion. Heavier = lower.
func try_jump() -> bool:
	var prof := assembly.locomotion
	if not alive or is_knocked_down or not prof.can_jump or not is_on_floor():
		return false
	velocity.y = prof.jump_force / sqrt(maxf(get_load_ratio(), 1.0))
	return true


func get_turn_rate_deg() -> float:
	return assembly.locomotion.turn_rate_deg * assembly.turn_factor


## Leg slam on landing. Heavier robots and longer falls hit harder.
## Returns enemies hit.
func stomp(fall_speed: float) -> int:
	var prof := assembly.locomotion
	var power := minf(prof.stomp, 2.0)
	var dmg := fall_speed * get_mass() * stomp_damage_factor * power
	var radius := minf(1.6 + 0.12 * get_mass(), 5.0)
	var hits := 0
	if RunState.enemies != null:
		hits = RunState.enemies.damage_radius(global_position, radius, dmg, 6.0)
	VentEffect.spawn(get_parent(), global_position - Vector3(0, 0.5, 0), radius, Color(0.85, 0.75, 0.55, 0.8))
	EventBus.robot_stomped.emit(dmg, hits)
	return hits


## Called by EnemyManager for each enemy touching the robot. Applies ram and
## crush, then the enemy's contact damage (reduced by armor facing it).
## `to_enemy` points from the robot to the enemy.
func handle_enemy_contact(em: EnemyManager, i: int, to_enemy: Vector3, delta: float) -> void:
	if not alive:
		return
	var prof := assembly.locomotion
	var t := em.get_data(i)
	var hspeed := Vector2(velocity.x, velocity.z).length()

	if prof.ram > 0.0 and hspeed >= ram_min_speed and em.cooldown[i] <= 0.0:
		var moving_at := Vector3(velocity.x, 0.0, velocity.z).normalized().dot(to_enemy.normalized()) > 0.3
		if moving_at:
			var dmg := hspeed * get_mass() * ram_damage_factor * minf(prof.ram, 2.0)
			em.damage(i, dmg, Vector3(velocity.x, 0.0, velocity.z) * 1.2 + Vector3.UP)
			em.cooldown[i] = ram_cooldown
			velocity.x *= 0.92
			velocity.z *= 0.92

	if prof.crush > 0.0 and t.radius <= crush_max_enemy_radius:
		em.damage(i, crush_dps * prof.crush * delta)
		return # it's under your treads, not biting you

	if em.is_alive(i):
		take_damage(t.contact_dps * delta, to_enemy)


func get_heat_capacity() -> float:
	return base_heat_capacity + assembly.heat_capacity


## Current cooling per second, including airflow from moving.
func get_heat_dissipation() -> float:
	var speed := Vector2(velocity.x, velocity.z).length()
	return base_heat_dissipation + assembly.heat_dissipation + airflow_cooling_per_mps * speed


func add_heat(amount: float) -> void:
	heat = maxf(heat + amount, 0.0)


func can_vent() -> bool:
	return alive and vent_cooldown_left <= 0.0 and heat >= vent_min_heat


func get_vent_radius(amount: float) -> float:
	return minf(vent_base_radius + amount * vent_radius_per_heat, vent_max_radius)


## Dumps all heat as a blast that damages and shoves nearby enemies.
## Returns the number of enemies hit, or -1 if the vent wasn't ready.
func vent() -> int:
	if not can_vent():
		return -1
	var amount := heat
	heat = 0.0
	if is_overheated:
		is_overheated = false
		EventBus.robot_cooled.emit()
	vent_cooldown_left = vent_cooldown

	var radius := get_vent_radius(amount)
	var hits := 0
	if RunState.enemies != null:
		hits = RunState.enemies.damage_radius(global_position, radius, amount * vent_damage_per_heat, vent_knockback)
	VentEffect.spawn(get_parent(), global_position, radius)
	EventBus.robot_vented.emit(amount, hits)
	return hits


func _update_heat(delta: float) -> void:
	vent_cooldown_left = maxf(vent_cooldown_left - delta, 0.0)
	if alive and Input.is_action_just_pressed("vent") and vent() < 0:
		if vent_cooldown_left > 0.0:
			EventBus.message.emit("Vent recharging (%.1fs)" % vent_cooldown_left)
		else:
			EventBus.message.emit("Not hot enough to vent")

	var cap := get_heat_capacity()
	heat += (assembly.heat_passive - get_heat_dissipation()) * delta
	heat = clampf(heat, 0.0, cap * 1.5)
	if not is_overheated and heat > cap:
		is_overheated = true
		EventBus.robot_overheat.emit()
	elif is_overheated and heat < cap * overheat_recover_frac:
		is_overheated = false
		EventBus.robot_cooled.emit()
	if is_overheated and alive:
		take_damage(overheat_dps * delta)


## Ratio of tipping torque to restoring torque. Static so it can be tested.
static func compute_tip_ratio(accel: float, com_height: float, lever: float, stability: float, p_gravity: float, sensitivity: float) -> float:
	var restoring := p_gravity * maxf(lever, 0.02) * (1.0 + maxf(stability, 0.0))
	return (accel * maxf(com_height, 0.0) * sensitivity) / restoring


# Uses the acceleration the locomotion itself produced this frame, so hitting
# a wall doesn't register as a huge acceleration.
func _update_tipping(delta: float, raw_accel: Vector3) -> void:
	if is_knocked_down:
		_knockdown_t -= delta
		var recover := clampf(_knockdown_t / 0.4, 0.0, 1.0)
		assembly.basis = Basis(_knockdown_axis, deg_to_rad(75.0) * recover)
		if _knockdown_t <= 0.0:
			is_knocked_down = false
			assembly.basis = Basis.IDENTITY
			_accel_smoothed = Vector3.ZERO
			if assembly.recover_pulse > 0.0 and RunState.enemies != null:
				# Gyros fling the robot upright with a shockwave.
				RunState.enemies.damage_radius(global_position, 3.5, assembly.recover_pulse, 8.0)
				VentEffect.spawn(get_parent(), global_position, 3.5, Color(0.4, 0.9, 1.0, 0.8))
			EventBus.robot_recovered.emit()
		return

	_accel_smoothed = _accel_smoothed.lerp(raw_accel, clampf(10.0 * delta, 0.0, 1.0))

	# Work in robot-local space so the lever matches the assembly layout.
	var local_a := global_basis.inverse() * _accel_smoothed
	var a2 := Vector2(local_a.x, local_a.z)
	var lever := assembly.tip_lever(a2)
	tip_ratio = compute_tip_ratio(a2.length(), assembly.center_of_mass.y, lever, assembly.stability, gravity, tip_sensitivity)

	# Visual lean: top of the robot leans away from the acceleration.
	if a2.length() > 0.01:
		var lean_axis := Vector3(a2.x, 0.0, a2.y).normalized().cross(Vector3.UP)
		var lean := clampf(tip_ratio, 0.0, 1.2) * deg_to_rad(max_visual_lean_deg)
		assembly.basis = Basis(lean_axis, lean)
	else:
		assembly.basis = Basis.IDENTITY

	if tip_ratio > tip_threshold and is_on_floor():
		_tip_timer += delta
		if _tip_timer >= tip_grace:
			_fall_over(Vector3(a2.x, 0.0, a2.y).normalized().cross(Vector3.UP))
	else:
		_tip_timer = maxf(_tip_timer - delta, 0.0)


func _fall_over(axis: Vector3) -> void:
	is_knocked_down = true
	_knockdown_t = knockdown_time * assembly.recover_time_mult
	_knockdown_axis = axis if axis.length() > 0.01 else Vector3.RIGHT
	_tip_timer = 0.0
	tip_ratio = 0.0
	velocity.x *= 0.4
	velocity.z *= 0.4
	EventBus.robot_knocked_down.emit()


## Weapons push back along their firing direction.
func apply_recoil(impulse: Vector3) -> void:
	var scale := 0.2 if assembly.locomotion.anchored else 1.0
	velocity.x += impulse.x * scale / get_mass()
	velocity.z += impulse.z * scale / get_mass()


## `from_dir` (robot -> attacker, world) lets armor facing that way block.
func take_damage(amount: float, from_dir: Vector3 = Vector3.ZERO) -> void:
	if not alive or amount <= 0.0:
		return
	if from_dir != Vector3.ZERO:
		amount = _shield_absorb(amount, from_dir)
		amount *= 1.0 - assembly.armor_block_for(from_dir)
	if amount <= 0.0:
		return
	hp -= amount
	EventBus.robot_damaged.emit(amount)
	for b in assembly.get_all_behaviors():
		b.on_hit(amount)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		EventBus.robot_destroyed.emit()
		RunState.end_run(false)


## Shield Projectors facing the hit turn damage into battery drain.
func _shield_absorb(amount: float, from_dir: Vector3) -> float:
	var d := Vector3(from_dir.x, 0.0, from_dir.z)
	if d.length_squared() < 0.0001 or browned_out:
		return amount
	d = d.normalized()
	for s in assembly.shield_parts:
		if not is_instance_valid(s) or energy <= 0.5:
			continue
		var f := s.get_facing_global()
		var arc := float(s.data.params.get("shield_arc_deg", 120.0))
		if f == Vector3.ZERO or f.dot(d) < cos(deg_to_rad(arc * 0.5)):
			continue
		var cost_per := float(s.data.params.get("energy_per_damage", 0.6))
		var absorbed := minf(amount, energy / maxf(cost_per, 0.01))
		energy -= absorbed * cost_per
		amount -= absorbed
		for b in s.behaviors:
			if b.has_method("flash"):
				b.call("flash")
		if amount <= 0.0:
			return 0.0
	return amount


func heal(amount: float) -> void:
	if alive:
		hp = minf(hp + amount, max_hp)


func _on_assembly_changed() -> void:
	var new_max := base_hp + assembly.max_hp
	if new_max > max_hp:
		hp += new_max - max_hp # new armor arrives repaired
	max_hp = new_max
	hp = minf(hp, max_hp)

	# Resize the body to fit the build: tall robots are tall, wide are wide.
	if collision == null:
		return
	var cap := collision.shape as CapsuleShape3D
	if cap == null:
		cap = CapsuleShape3D.new()
		collision.shape = cap
	cap.radius = clampf(assembly.half_width * 0.8, 0.3, 1.2)
	cap.height = maxf(assembly.height, cap.radius * 2.0 + 0.01)
	collision.position = Vector3(0.0, cap.height * 0.5, 0.0)
