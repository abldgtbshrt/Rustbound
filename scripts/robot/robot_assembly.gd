class_name RobotAssembly
extends Node3D

## Owns the part tree and derives every physical stat from it. Nothing here is
## read from a stat card: mass, center of mass, footprint and height come from
## where parts actually sit.

signal assembly_changed

@export var root_part_data: PartData
## Attached in order when the robot is built.
@export var starting_parts: Array[PartData] = []
## Optional socket name per starting part (same index). The first part in the
## tree with a free socket of that name is used. Empty = auto_attach().
@export var starting_sockets: Array[StringName] = []
## Optional rotation (45° steps) per starting part (same index).
@export var starting_yaws: Array[int] = []

var robot: RobotController
var root: PartInstance

# Derived stats (assembly-local space; y = 0 is the ground under the robot).
var total_mass: float = 0.0
var center_of_mass: Vector3 = Vector3.ZERO
## Width of the narrowest support axis (for display).
var footprint: float = 0.0
## Ground contact rectangle on the XZ plane, assembly-local.
var support_min: Vector2 = Vector2(-0.15, -0.15)
var support_max: Vector2 = Vector2(0.15, 0.15)
var height: float = 0.0
var half_width: float = 0.4
var power_gen: float = 0.0
var power_draw: float = 0.0
var cpu_capacity: int = 0
var cpu_used: int = 0
var max_hp: float = 0.0
var pickup_radius: float = 0.0
var stability: float = 0.0
var heat_passive: float = 0.0
var heat_capacity: float = 0.0
var heat_dissipation: float = 0.0
var energy_capacity: float = 0.0
## Jets: total upward thrust and energy they burn per second while firing.
var jet_thrust: float = 0.0
var jet_energy_per_sec: float = 0.0
var jet_parts: Array[PartInstance] = []
var shield_parts: Array[PartInstance] = []
var locomotion: LocomotionProfile = LocomotionProfile.new()
var part_count: int = 0
## Horizontal moment of inertia about the center of mass. Mass far from the
## middle makes the robot turn slower.
var inertia: float = 0.0
## Turn speed multiplier from inertia (compact = fast) times gyro bonuses.
var turn_factor: float = 1.0
## Gyro effects: knockdown duration multiplier and recovery shockwave damage.
var recover_time_mult: float = 1.0
var recover_pulse: float = 0.0
var armor_parts: Array[PartInstance] = []

## Moment of inertia of the starter robot; it turns at its parts' rated speed.
const INERTIA_REF := 1.6
## Mass points closer than this are linked (as are parent and child).
const LINK_RANGE := 0.75

## PartInstance -> Array[PartInstance] of linked neighbours.
var links: Dictionary = {}
## PartInstance -> Dictionary of multipliers received from neighbours.
var _mods: Dictionary = {}

var _cpu_granted: Dictionary = {} # PartInstance -> true


## Builds the root part and starting loadout. Called by RobotController so
## behaviors get a valid robot reference.
func build(p_robot: RobotController) -> void:
	robot = p_robot
	if root == null and root_part_data != null:
		root = PartInstance.new(root_part_data)
		root.name = "Core"
		add_child(root)
		_spawn_behaviors(root)
	recompute()
	for k in starting_parts.size():
		var p := starting_parts[k]
		if p == null:
			continue
		var socket_name: StringName = starting_sockets[k] if k < starting_sockets.size() else &""
		var yaw: int = starting_yaws[k] if k < starting_yaws.size() else 0
		var inst: PartInstance = null
		if socket_name != &"":
			inst = attach_by_socket_name(p, socket_name, true, yaw)
		else:
			inst = auto_attach(p)
		if inst == null:
			push_warning("Starting part %s found no free socket" % p.id)


## Attaches to the first part (in tree order) with a free, compatible socket
## named `socket_name`.
func attach_by_socket_name(part: PartData, socket_name: StringName, do_recompute: bool = true, yaw_steps: int = 0) -> PartInstance:
	for inst in get_all_parts():
		var s := inst.data.get_socket(socket_name)
		if s != null and inst.is_socket_free(socket_name) and can_fit(part, s):
			return attach(part, inst, socket_name, do_recompute, yaw_steps)
	return null


static func can_fit(part: PartData, socket: SocketDef) -> bool:
	return part != null and socket != null \
		and part.fits_type(socket.type) \
		and part.attach_size <= socket.size


func attach(part: PartData, parent: PartInstance, socket_name: StringName, do_recompute: bool = true, yaw_steps: int = 0) -> PartInstance:
	if part == null:
		return null
	if parent == null:
		parent = root
	if parent == null or parent.data == null:
		return null
	var socket := parent.data.get_socket(socket_name)
	if socket == null or not parent.is_socket_free(socket_name) or not can_fit(part, socket):
		return null

	var inst := PartInstance.new(part)
	parent.attach_child_part(inst, socket, yaw_steps)
	_spawn_behaviors(inst)
	EventBus.part_attached.emit(part.id)
	if do_recompute:
		recompute()
	return inst


## Finds a free compatible socket anywhere on the robot. Among candidates it
## picks the one that keeps the center of mass closest to the middle, so
## pickups don't wreck balance by accident (build mode will add manual
## placement). Ties go to the earliest socket in tree order. Returns null if nothing fits.
func auto_attach(part: PartData, do_recompute: bool = true) -> PartInstance:
	var best := find_best_socket(part)
	if best.is_empty():
		return null
	return attach(part, best[0], best[1], do_recompute)


## Returns [PartInstance, StringName] or [] if no socket fits.
func find_best_socket(part: PartData) -> Array:
	if root == null or part == null:
		return []
	var best: Array = []
	var best_score := INF
	var com_mass := Vector2(center_of_mass.x, center_of_mass.z) * total_mass
	for entry in _walk_local():
		var inst: PartInstance = entry[0]
		var xf: Transform3D = entry[1]
		for s in inst.get_free_sockets():
			if not can_fit(part, s):
				continue
			var p := xf * (s.get_transform() * part.visual_offset)
			var new_com := (com_mass + Vector2(p.x, p.z) * part.mass) / maxf(total_mass + part.mass, 0.001)
			var score := new_com.length()
			if score < best_score - 0.0001:
				best_score = score
				best = [inst, s.marker_name]
	return best


## Turns an attached part by `delta_steps` x 45° around its socket's up axis.
func rotate_part(inst: PartInstance, delta_steps: int) -> void:
	if inst == null or inst == root or inst.parent_part == null:
		return
	inst.set_yaw(inst.yaw_steps + delta_steps)
	recompute()


## Assembly-local position of a socket cell on `inst`.
func socket_local_position(inst: PartInstance, socket: SocketDef) -> Vector3:
	for e in _walk_local():
		if e[0] == inst:
			return (e[1] as Transform3D) * inst.get_socket_transform(socket).origin
	return Vector3.ZERO


## The free socket mirrored across the robot's center line (x -> -x) that
## also fits `part`, as [PartInstance, SocketDef], or [] if none.
func find_mirror_socket(part: PartData, inst: PartInstance, socket: SocketDef) -> Array:
	var p := socket_local_position(inst, socket)
	if absf(p.x) < 0.05:
		return []
	var want := Vector3(-p.x, p.y, p.z)
	for e in _walk_local():
		var other: PartInstance = e[0]
		var xf: Transform3D = e[1]
		for s in other.get_free_sockets():
			if s == socket or not can_fit(part, s):
				continue
			if (xf * other.get_socket_transform(s).origin).distance_to(want) < 0.06:
				return [other, s]
	return []


## Multiplier a part receives from linked neighbours (1.0 if none).
func get_mod(inst: PartInstance, key: String, default_value: float = 1.0) -> float:
	var m: Dictionary = _mods.get(inst, {})
	return float(m.get(key, default_value))


func get_links(inst: PartInstance) -> Array:
	return links.get(inst, [])


## Fraction of a hit coming from world direction `from_dir` (robot -> attacker)
## that the armor blocks. Overlapping plates stack multiplicatively.
func armor_block_for(from_dir: Vector3) -> float:
	var d := Vector3(from_dir.x, 0.0, from_dir.z)
	if d.length_squared() < 0.0001:
		return 0.0
	d = d.normalized()
	var pass_through := 1.0
	for a in armor_parts:
		if not is_instance_valid(a):
			continue
		var f := a.get_facing_global()
		if f == Vector3.ZERO:
			continue
		if f.dot(d) >= cos(deg_to_rad(a.data.armor_arc_deg * 0.5)):
			pass_through *= 1.0 - clampf(a.stat("armor_block", a.data.armor_block), 0.0, 0.9)
	return 1.0 - pass_through


## Removes a part and everything attached to it. Returns the removed PartData
## (including children) so callers can drop them as loot.
func detach(inst: PartInstance) -> Array[PartData]:
	var removed: Array[PartData] = []
	if inst == null or inst == root or inst.parent_part == null:
		return removed
	for p in inst.walk():
		removed.append(p.data)
		for b in p.behaviors:
			b.on_detached()
		EventBus.part_detached.emit(p.data.id)
	inst.parent_part.detach_child_part(inst)
	inst.queue_free()
	recompute()
	return removed


func get_all_parts() -> Array[PartInstance]:
	if root == null:
		return []
	return root.walk()


func get_all_behaviors() -> Array[PartBehavior]:
	var out: Array[PartBehavior] = []
	for p in get_all_parts():
		out.append_array(p.behaviors)
	return out


func has_cpu_for(inst: PartInstance) -> bool:
	return _cpu_granted.has(inst)


## Static deficit: parts draw more than they generate. The battery covers it
## for a while; RobotController.browned_out is the actual stalled state.
func is_browned_out() -> bool:
	return power_draw > power_gen + 0.001


## 1.0 when power is fine, lower when draw exceeds generation.
func get_power_ratio() -> float:
	if power_draw <= 0.001:
		return 1.0
	return clampf(power_gen / power_draw, 0.0, 1.0)


func recompute() -> void:
	total_mass = 0.0
	center_of_mass = Vector3.ZERO
	footprint = 0.0
	height = 0.0
	half_width = 0.4
	power_gen = 0.0
	power_draw = 0.0
	cpu_capacity = 0
	cpu_used = 0
	max_hp = 0.0
	pickup_radius = 0.0
	stability = 0.0
	heat_passive = 0.0
	heat_capacity = 0.0
	heat_dissipation = 0.0
	energy_capacity = 0.0
	jet_thrust = 0.0
	jet_energy_per_sec = 0.0
	jet_parts.clear()
	shield_parts.clear()
	part_count = 0
	inertia = 0.0
	turn_factor = 1.0
	recover_time_mult = 1.0
	recover_pulse = 0.0
	armor_parts.clear()
	links.clear()
	_mods.clear()
	_cpu_granted.clear()

	if root == null:
		locomotion = LocomotionProfile.new()
		assembly_changed.emit()
		return

	# Pass 1: lift the robot so its lowest point touches y = 0.
	root.position = Vector3.ZERO
	var entries := _walk_local()
	var bounds := AABB()
	var first := true
	for e in entries:
		var b := _part_bounds(e[0], e[1])
		if first:
			bounds = b
			first = false
		else:
			bounds = bounds.merge(b)
	root.position.y = -bounds.position.y
	var lift := Vector3(0.0, -bounds.position.y, 0.0)
	height = bounds.size.y
	half_width = maxf(maxf(absf(bounds.position.x), absf(bounds.end.x)), maxf(absf(bounds.position.z), absf(bounds.end.z)))

	# Pass 2: budgets and mass distribution.
	var weighted := Vector3.ZERO
	var loco_entries: Array = []
	var support := AABB()
	var has_support := false
	var cpu_users: Array[PartInstance] = []
	var mass_points: Dictionary = {} # PartInstance -> Vector3
	var gyro_turn := 1.0
	for e in entries:
		var inst: PartInstance = e[0]
		var d := inst.data
		var xf: Transform3D = e[1]
		var mass_point: Vector3 = xf * d.visual_offset + lift
		mass_points[inst] = mass_point
		part_count += 1
		if d.armor_block > 0.0:
			armor_parts.append(inst)
		gyro_turn *= inst.stat("turn_rate_mult", float(d.params.get("turn_rate_mult", 1.0)))
		recover_time_mult = minf(recover_time_mult, float(d.params.get("recover_time_mult", 1.0)))
		recover_pulse += inst.stat("recover_pulse", float(d.params.get("recover_pulse", 0.0)))
		total_mass += d.mass
		weighted += mass_point * d.mass
		# Upgradable stats are read at the part's tier.
		power_gen += inst.stat("power_output", d.power_output)
		power_draw += d.power_draw
		cpu_capacity += int(round(inst.stat("cpu_output", float(d.cpu_output))))
		max_hp += inst.stat("hp", d.hp)
		pickup_radius += inst.stat("pickup_radius", d.pickup_radius)
		stability += inst.stat("stability", d.stability)
		heat_passive += d.heat_per_sec
		heat_capacity += inst.stat("heat_capacity", d.heat_capacity)
		heat_dissipation += inst.stat("heat_dissipation", d.heat_dissipation)
		energy_capacity += inst.stat("energy_capacity", d.energy_capacity)
		if d.params.has("shield_arc_deg"):
			shield_parts.append(inst)
		if d.params.has("jet_thrust"):
			jet_parts.append(inst)
			jet_thrust += inst.stat("jet_thrust", float(d.params["jet_thrust"]))
			jet_energy_per_sec += float(d.params.get("jet_energy", 10.0))
		if d.cpu_cost > 0:
			cpu_users.append(inst)
		if d.category == PartData.Category.LOCOMOTION:
			loco_entries.append([inst, mass_point])
			var fb := _part_bounds(inst, xf)
			fb.position += lift
			if has_support:
				support = support.merge(fb)
			else:
				support = fb
				has_support = true

	if total_mass > 0.0001:
		center_of_mass = weighted / total_mass

	# Moment of inertia (horizontal) about the center of mass: point masses
	# plus each part's own box.
	for e in entries:
		var inst: PartInstance = e[0]
		var d := inst.data
		var mp: Vector3 = mass_points[inst]
		var r2 := Vector2(mp.x - center_of_mass.x, mp.z - center_of_mass.z).length_squared()
		inertia += d.mass * (r2 + (d.visual_size.x * d.visual_size.x + d.visual_size.z * d.visual_size.z) / 12.0)
	turn_factor = clampf(sqrt(INERTIA_REF / maxf(inertia, 0.01)), 0.3, 1.4) * gyro_turn

	_compute_links(entries, mass_points)

	# CPU is granted in attach order; extra weapons fire straight ahead.
	for inst in cpu_users:
		if cpu_used + inst.data.cpu_cost <= cpu_capacity:
			cpu_used += inst.data.cpu_cost
			_cpu_granted[inst] = true

	if has_support:
		support_min = Vector2(support.position.x, support.position.z)
		support_max = Vector2(support.end.x, support.end.z)
	else:
		# Core-only: a small rolling contact patch.
		support_min = Vector2(center_of_mass.x - 0.15, center_of_mass.z - 0.15)
		support_max = Vector2(center_of_mass.x + 0.15, center_of_mass.z + 0.15)
	footprint = minf(support_max.x - support_min.x, support_max.y - support_min.y)
	locomotion = LocomotionProfile.resolve(loco_entries, center_of_mass)
	stability += locomotion.extra_leg_stability()

	assembly_changed.emit()


func _compute_links(entries: Array, mass_points: Dictionary) -> void:
	for e in entries:
		links[e[0]] = []
	for a_i in entries.size():
		var a: PartInstance = entries[a_i][0]
		for b_i in range(a_i + 1, entries.size()):
			var b: PartInstance = entries[b_i][0]
			var touching := (mass_points[a] as Vector3).distance_to(mass_points[b]) <= LINK_RANGE
			if touching or a.parent_part == b or b.parent_part == a:
				# The core and chassis touch everything; skip structural hubs so
				# links stay meaningful.
				if a == root or b == root:
					continue
				(links[a] as Array).append(b)
				(links[b] as Array).append(a)
	for inst in links.keys():
		var m: Dictionary = {}
		for n in links[inst]:
			var nm: Dictionary = (n as PartInstance).data.neighbor_mods
			for k in nm.keys():
				m[k] = float(m.get(k, 1.0)) * float(nm[k])
		_mods[inst] = m


# Returns Array of [PartInstance, Transform3D relative to this assembly],
# computed from local transforms so it works outside the scene tree too.
func _walk_local() -> Array:
	var out: Array = []
	if root != null:
		_walk_rec(root, root.transform, out)
	return out


func _walk_rec(inst: PartInstance, xf: Transform3D, out: Array) -> void:
	out.append([inst, xf])
	for c in inst.get_children():
		if c is PartInstance:
			_walk_rec(c, xf * (c as PartInstance).transform, out)


func _part_bounds(inst: PartInstance, xf: Transform3D) -> AABB:
	var d := inst.data
	var mi := inst.visual.get_node_or_null("Mesh") as MeshInstance3D if inst.visual != null else null
	if mi != null and mi.mesh != null:
		return (xf * inst.visual.transform * mi.transform) * mi.mesh.get_aabb()
	var half := d.visual_size * 0.5
	return xf * AABB(d.visual_offset - half, d.visual_size)


func _spawn_behaviors(inst: PartInstance) -> void:
	for s in inst.data.behaviors:
		if s == null:
			continue
		var b: Object = s.new()
		if b is PartBehavior:
			var pb := b as PartBehavior
			pb.name = "%s_%s" % [inst.name, s.resource_path.get_file().get_basename()]
			inst.add_child(pb)
			inst.behaviors.append(pb)
			pb.setup(inst, robot)
		elif b is Node:
			(b as Node).queue_free()


## Horizontal distance from the center of mass to the support edge the robot
## would tip over when accelerating along `accel_dir` (assembly-local, XZ).
## Accelerating tips the top backwards, so the edge is on the opposite side.
func tip_lever(accel_dir: Vector2) -> float:
	var d := accel_dir.normalized()
	if d == Vector2.ZERO:
		return INF
	var lever_x := (center_of_mass.x - support_min.x) if d.x > 0.0 else (support_max.x - center_of_mass.x)
	var lever_z := (center_of_mass.z - support_min.y) if d.y > 0.0 else (support_max.y - center_of_mass.z)
	var lever := absf(d.x) * lever_x + absf(d.y) * lever_z
	return maxf(lever, 0.02)
