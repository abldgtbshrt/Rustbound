class_name EnemyManager
extends Node3D

## Data-oriented horde: enemies are rows in flat arrays, drawn with one
## MultiMesh, and found through a spatial grid. No node per enemy.
##
## The per-enemy work runs in a backend: the native HordeSim (C++, see
## native/README.md) when the library is loaded, else HordeSimGD (same API in
## GDScript). This node owns the gameplay side: spawning waves, kill rewards,
## and handing robot contacts to RobotController.

@export var enemy_types: Array[EnemyData] = []
@export var max_enemies: int = 600
@export var cell_size: float = 2.0
@export var arena_half_extent: float = 58.0

@export_group("Waves")
@export var spawn_enabled: bool = true
@export var spawn_radius_min: float = 20.0
@export var spawn_radius_max: float = 28.0
## Enemies per second at the start of a run...
@export var base_spawn_rate: float = 1.2
## ...plus this many per second for every minute survived.
@export var spawn_rate_per_minute: float = 4.0

## Which simulation backend to use: "auto" picks the native library when it's
## loaded (bin/rustbound_native.gdextension) and falls back to GDScript.
@export_enum("auto", "native", "gdscript") var backend: String = "auto"

## Enemy rows live in the backend (HordeSim in C++, or HordeSimGD). Read and
## write them through the accessors below; there are no public arrays.
var count: int:
	get:
		return _sim.get_count() if _sim != null else 0

## Microseconds EnemyManager spent in its last physics step (for the perf
## overlay and tests/bench_horde.tscn).
var last_step_usec: int = 0

## HordeSim (native) or HordeSimGD; both expose the same methods.
var _sim: RefCounted
var _spawn_accum := 0.0
## One MultiMesh per enemy type, so each type can have its own model.
var _mms: Array[MultiMesh] = []
var _mm_rids: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	RunState.enemies = self
	_rng.seed = RunState.run_seed if RunState.run_seed != 0 else randi()
	_sim = create_backend(backend)
	_sim.setup(max_enemies, cell_size, arena_half_extent)
	_sync_types()

	_build_multimeshes()


func _build_multimeshes() -> void:
	var wedge := PrismMesh.new() # placeholder: wedge-shaped scrap bugs
	wedge.size = Vector3(1.0, 1.0, 1.0)
	wedge.material = PartVisuals.material_for(Color.WHITE)
	for t in enemy_types.size():
		var data := enemy_types[t]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var model := data.get_mesh()
		mm.mesh = model if model != null else wedge
		mm.instance_count = max_enemies
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.name = "Enemies_%s" % data.id
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mms.append(mm)
		_mm_rids.append(mm.get_rid())


func _exit_tree() -> void:
	if RunState.enemies == self:
		RunState.enemies = null


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_sim.compact()
	_sync_types()
	if RunState.running and spawn_enabled:
		_spawn_tick(delta)
	_simulate(delta)
	_update_multimesh()
	last_step_usec = Time.get_ticks_usec() - t0


## A fresh simulation backend. "auto" prefers the native library. The env var
## RUSTBOUND_HORDE_BACKEND (gdscript | native) overrides it, e.g. for tests.
static func create_backend(kind: String = "auto") -> RefCounted:
	var forced := OS.get_environment("RUSTBOUND_HORDE_BACKEND")
	if forced != "":
		kind = forced
	var native_ok := ClassDB.class_exists("HordeSim")
	if kind == "native" and not native_ok:
		push_warning("EnemyManager: native HordeSim not loaded; using GDScript")
	if kind != "gdscript" and native_ok:
		return ClassDB.instantiate("HordeSim")
	return HordeSimGD.new()


func backend_name() -> String:
	return _sim.backend_name()


# --- Public API ---------------------------------------------------------------

func spawn(type_index: int, at: Vector3) -> int:
	if type_index < 0 or type_index >= enemy_types.size():
		return -1
	return _sim.spawn(type_index, at, enemy_types[type_index].hp)


func is_alive(i: int) -> bool:
	return _sim.is_alive(i)


func get_data(i: int) -> EnemyData:
	return enemy_types[_sim.get_type(i)]


func get_radius(i: int) -> float:
	return enemy_types[_sim.get_type(i)].radius


func alive_count() -> int:
	return _sim.alive_count()


func get_pos(i: int) -> Vector3:
	return _sim.get_pos(i)


func set_pos(i: int, p: Vector3) -> void:
	_sim.set_pos(i, p)


func get_vel(i: int) -> Vector3:
	return _sim.get_vel(i)


func set_vel(i: int, v: Vector3) -> void:
	_sim.set_vel(i, v)


func get_hp(i: int) -> float:
	return _sim.get_hp(i)


func set_hp(i: int, v: float) -> void:
	_sim.set_hp(i, v)


func get_flash(i: int) -> float:
	return _sim.get_flash(i)


## Per-enemy timer the robot uses to rate-limit ram hits.
func get_cooldown(i: int) -> float:
	return _sim.get_cooldown(i)


func set_cooldown(i: int, v: float) -> void:
	_sim.set_cooldown(i, v)


func get_slow_t(i: int) -> float:
	return _sim.get_slow_t(i)


func get_slow_mult(i: int) -> float:
	return _sim.get_slow_mult(i)


func get_burn_t(i: int) -> float:
	return _sim.get_burn_t(i)


## Returns true if this hit killed the enemy.
func damage(i: int, amount: float, knockback: Vector3 = Vector3.ZERO) -> bool:
	if _sim.damage(i, amount, knockback):
		_on_killed(i)
		return true
	return false


## Slows an enemy to `mult` of its speed for `duration` s (strongest wins).
func apply_slow(i: int, mult: float, duration: float) -> void:
	_sim.apply_slow(i, mult, duration)


## Sets an enemy on fire: `dps` for `duration` s (strongest wins).
func apply_burn(i: int, dps: float, duration: float) -> void:
	_sim.apply_burn(i, dps, duration)


## On-hit extras from a weapon or path: slow_mult/slow_dur, burn_dps/burn_dur.
func apply_hit_fx(i: int, fx: Dictionary) -> void:
	if fx.is_empty():
		return
	if float(fx.get("slow_dur", 0.0)) > 0.0:
		apply_slow(i, float(fx.get("slow_mult", 0.6)), float(fx["slow_dur"]))
	if float(fx.get("burn_dur", 0.0)) > 0.0:
		apply_burn(i, float(fx.get("burn_dps", 5.0)), float(fx["burn_dur"]))


## Damages every live enemy within `radius` (XZ, edge-inclusive) of `origin`,
## with 50% falloff at the edge, pushing them outward. Returns hits.
func damage_radius(origin: Vector3, radius: float, amount: float, knockback: float = 0.0) -> int:
	var hits: int = _sim.damage_radius(origin, radius, amount, knockback)
	_drain_kills()
	return hits


## Indices of live enemies whose centers are within `radius` (XZ) of `origin`.
func query_radius(origin: Vector3, radius: float) -> PackedInt32Array:
	return _sim.query_radius(origin, radius)


## Live enemies touched by a beam from `origin` along `dir` (XZ, normalized)
## for `reach` m, `width` wide plus each enemy's radius.
func query_segment(origin: Vector3, dir: Vector3, reach: float, width: float) -> PackedInt32Array:
	return _sim.query_segment(origin, dir, reach, width)


## Nearest live enemy within range whose direction lies inside a cone around
## `forward` (cos_half_arc = cos(arc/2); pass -1 for any direction).
func find_nearest(origin: Vector3, max_range: float, forward: Vector3 = Vector3.FORWARD, cos_half_arc: float = -1.0) -> int:
	return _sim.find_nearest(origin, max_range, forward, cos_half_arc)


func clear_all() -> void:
	_sim.clear()
	_update_multimesh()


# --- Internals ----------------------------------------------------------------

func _sync_types() -> void:
	var radius := PackedFloat32Array()
	var speed := PackedFloat32Array()
	var color := PackedColorArray()
	var model_scale := PackedFloat32Array()
	for t in enemy_types:
		radius.append(t.radius)
		speed.append(t.speed)
		# Authored models carry their own colors; the tint only flashes them.
		color.append(t.color if t.model == null else Color.WHITE)
		model_scale.append(t.model_scale if t.model != null else 0.0)
	_sim.set_types(radius, speed, color, model_scale)


func _simulate(delta: float) -> void:
	var robot := RunState.robot
	var target := robot.global_position if robot != null else Vector3.ZERO
	var robot_r := robot.get_body_radius() if robot != null else 0.5
	var chase := robot != null and robot.alive
	_sim.step(delta, target, robot_r, chase)
	_drain_kills() # burned to death this step
	# Contact: the robot decides (ram, crush, armor), then no overlap.
	var touching: PackedInt32Array = _sim.get_contacts()
	if not touching.is_empty():
		var dirs: PackedVector3Array = _sim.get_contact_dirs()
		for k in touching.size():
			robot.handle_enemy_contact(self, touching[k], dirs[k], delta)
	_sim.resolve_contacts()


func _drain_kills() -> void:
	for i in _sim.take_kills():
		_on_killed(i)


func _spawn_tick(delta: float) -> void:
	var robot := RunState.robot
	if robot == null or enemy_types.is_empty():
		return
	var minutes := RunState.elapsed_time / 60.0
	_spawn_accum += (base_spawn_rate + spawn_rate_per_minute * minutes) * delta
	while _spawn_accum >= 1.0 and count < max_enemies:
		_spawn_accum -= 1.0
		var ti := _pick_type(RunState.elapsed_time)
		if ti < 0:
			break
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(spawn_radius_min, spawn_radius_max)
		var at := robot.global_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		at.x = clampf(at.x, -arena_half_extent, arena_half_extent)
		at.z = clampf(at.z, -arena_half_extent, arena_half_extent)
		spawn(ti, at)
	_spawn_accum = minf(_spawn_accum, 5.0)


func _pick_type(t: float) -> int:
	var total := 0.0
	var weights := PackedFloat32Array()
	for e in enemy_types:
		var w := 0.0
		if t >= e.min_time:
			w = e.spawn_weight + e.weight_per_minute * (t - e.min_time) / 60.0
		weights.append(w)
		total += w
	if total <= 0.0:
		return -1
	var r := _rng.randf() * total
	for k in weights.size():
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.size() - 1


func _on_killed(i: int) -> void:
	var t := get_data(i)
	var at := get_pos(i)
	RunState.kills += 1
	EventBus.enemy_killed.emit(t, at)
	var pickups := RunState.pickups
	if pickups != null:
		pickups.spawn_scrap(at, t.scrap_value)
		if _rng.randf() < t.part_drop_chance:
			var part := LootTable.roll_part()
			if part != null:
				pickups.spawn_part(at, part)


func _update_multimesh() -> void:
	var robot := RunState.robot
	var target := robot.global_position if robot != null else Vector3.ZERO
	var counts: PackedInt32Array = _sim.upload_multimeshes(_mm_rids, target)
	for t in _mms.size():
		_mms[t].visible_instance_count = counts[t] if t < counts.size() else 0
