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

@export_group("Heat")
@export var base_heat_capacity: float = 100.0
## Cooling while standing still. Moving adds airflow cooling on top.
@export var base_heat_dissipation: float = 2.0
## Extra cooling per m/s of horizontal speed: kiting cools, camping bakes.
@export var airflow_cooling_per_mps: float = 1.2
@export var overheat_dps: float = 3.0
## Overheat clears once heat drops below this fraction of capacity.
@export var overheat_recover_frac: float = 0.8

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

var heat: float = 0.0
var is_overheated: bool = false
## Seconds until the vent is ready again.
var vent_cooldown_left: float = 0.0

var _accel_smoothed := Vector3.ZERO
var _tip_timer := 0.0
var _knockdown_t := 0.0
var _knockdown_axis := Vector3.RIGHT
var _was_on_floor := true


func _ready() -> void:
	RunState.robot = self
	assembly.assembly_changed.connect(_on_assembly_changed)
	assembly.build(self)
	hp = max_hp


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
	return 1.0 if load <= 1.0 else clampf(2.0 - load, 0.0, 1.0)


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

	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var start_hvel := hvel
	var desired := dir * get_top_speed()
	var accel := prof.thrust / mass
	if is_knocked_down:
		accel = 6.0 # sliding to a stop on your side

	# Grip: the part of the velocity change that is sideways to the current
	# heading is scaled down, so low-grip builds (wheels) drift through turns.
	var dv := desired - hvel
	if hvel.length() > 0.5 and not is_knocked_down:
		var fwd := hvel.normalized()
		var along := fwd * dv.dot(fwd)
		var perp := dv - along
		dv = along + perp * lerpf(0.25, 1.0, prof.grip)
	hvel += dv.limit_length(accel * delta)

	# Asymmetry: an off-center center of mass pulls the robot to that side.
	if hvel.length() > 0.2 and alive:
		var side := global_basis.x * assembly.center_of_mass.x
		var speed_frac := clampf(hvel.length() / maxf(prof.top_speed, 0.1), 0.0, 1.0)
		hvel += side * drift_factor * speed_frac * delta * 4.0

	# Face the direction of travel at the locomotion's turn rate.
	if dir.length() > 0.1:
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = rotate_toward(rotation.y, target_yaw, deg_to_rad(prof.turn_rate_deg) * delta)

	velocity.x = hvel.x
	velocity.z = hvel.z

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif alive and not is_knocked_down and prof.can_jump and Input.is_action_just_pressed("jump"):
		velocity.y = prof.jump_force / sqrt(maxf(get_load_ratio(), 1.0))

	move_and_slide()

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		for b in assembly.get_all_behaviors():
			b.on_land()
	_was_on_floor = on_floor

	_update_heat(delta)
	_update_tipping(delta, (hvel - start_hvel) / maxf(delta, 0.0001))

	if alive:
		for b in assembly.get_all_behaviors():
			b.on_tick(delta)


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
	var enemies := RunState.enemies
	if enemies != null:
		var origin := global_position
		for i in enemies.query_radius(origin, radius + 1.0):
			var to := enemies.pos[i] - origin
			to.y = 0.0
			var d := to.length()
			var reach := radius + enemies.get_radius(i)
			if d > reach:
				continue
			var falloff := lerpf(1.0, 0.5, clampf(d / reach, 0.0, 1.0))
			var push := (to / maxf(d, 0.01)) * vent_knockback
			enemies.damage(i, amount * vent_damage_per_heat * falloff, push)
			hits += 1
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
	_knockdown_t = knockdown_time
	_knockdown_axis = axis if axis.length() > 0.01 else Vector3.RIGHT
	_tip_timer = 0.0
	tip_ratio = 0.0
	velocity.x *= 0.4
	velocity.z *= 0.4
	EventBus.robot_knocked_down.emit()


## Weapons push back along their firing direction.
func apply_recoil(impulse: Vector3) -> void:
	var scale := 0.2 if _has_tag("anchored") else 1.0
	velocity.x += impulse.x * scale / get_mass()
	velocity.z += impulse.z * scale / get_mass()


func take_damage(amount: float) -> void:
	if not alive or amount <= 0.0:
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


func heal(amount: float) -> void:
	if alive:
		hp = minf(hp + amount, max_hp)


func _has_tag(tag: String) -> bool:
	for p in assembly.get_all_parts():
		if p.data.tags.has(tag):
			return true
	return false


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
