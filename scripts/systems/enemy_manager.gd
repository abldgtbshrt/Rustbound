class_name EnemyManager
extends Node3D

## Data-oriented horde: enemies are rows in packed arrays, drawn with one
## MultiMesh, and found through a spatial hash. No node per enemy.

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

var count: int = 0
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var hp := PackedFloat32Array()
var flash := PackedFloat32Array()
var type_idx := PackedInt32Array()
## Per-enemy timer the robot uses to rate-limit ram hits.
var cooldown := PackedFloat32Array()

var _grid: Dictionary = {} # Vector2i -> PackedInt32Array
var _spawn_accum := 0.0
var _mm := MultiMesh.new()
var _mm_instance := MultiMeshInstance3D.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	RunState.enemies = self
	_rng.seed = RunState.run_seed if RunState.run_seed != 0 else randi()
	pos.resize(max_enemies)
	vel.resize(max_enemies)
	hp.resize(max_enemies)
	flash.resize(max_enemies)
	type_idx.resize(max_enemies)
	cooldown.resize(max_enemies)

	var mesh := PrismMesh.new() # wedge-shaped scrap bugs
	mesh.size = Vector3(1.0, 1.0, 1.0)
	mesh.material = PartVisuals.material_for(Color.WHITE)
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = mesh
	_mm.instance_count = max_enemies
	_mm.visible_instance_count = 0
	_mm_instance.multimesh = _mm
	_mm_instance.name = "EnemyMultiMesh"
	_mm_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm_instance)


func _exit_tree() -> void:
	if RunState.enemies == self:
		RunState.enemies = null


func _physics_process(delta: float) -> void:
	_compact()
	if RunState.running and spawn_enabled:
		_spawn_tick(delta)
	_rebuild_grid()
	_simulate(delta)
	_update_multimesh()


# --- Public API ---------------------------------------------------------------

func spawn(type_index: int, at: Vector3) -> int:
	if count >= max_enemies or type_index < 0 or type_index >= enemy_types.size():
		return -1
	var i := count
	count += 1
	var t := enemy_types[type_index]
	pos[i] = Vector3(at.x, t.radius, at.z)
	vel[i] = Vector3.ZERO
	hp[i] = t.hp
	flash[i] = 0.0
	cooldown[i] = 0.0
	type_idx[i] = type_index
	return i


func is_alive(i: int) -> bool:
	return i >= 0 and i < count and hp[i] > 0.0


func get_data(i: int) -> EnemyData:
	return enemy_types[type_idx[i]]


func get_radius(i: int) -> float:
	return enemy_types[type_idx[i]].radius


func alive_count() -> int:
	var n := 0
	for i in count:
		if hp[i] > 0.0:
			n += 1
	return n


## Returns true if this hit killed the enemy.
func damage(i: int, amount: float, knockback: Vector3 = Vector3.ZERO) -> bool:
	if not is_alive(i):
		return false
	hp[i] -= amount
	flash[i] = 0.12
	vel[i] += knockback
	if hp[i] <= 0.0:
		_on_killed(i)
		return true
	return false


## Damages every live enemy within `radius` (XZ, edge-inclusive) of `origin`,
## with 50% falloff at the edge, pushing them outward. Returns hits.
func damage_radius(origin: Vector3, radius: float, amount: float, knockback: float = 0.0) -> int:
	var hits := 0
	for i in query_radius(origin, radius + 1.0):
		var to := pos[i] - origin
		to.y = 0.0
		var d := to.length()
		var reach := radius + get_radius(i)
		if d > reach:
			continue
		var falloff := lerpf(1.0, 0.5, clampf(d / reach, 0.0, 1.0))
		damage(i, amount * falloff, (to / maxf(d, 0.01)) * knockback)
		hits += 1
	return hits


## Indices of live enemies whose centers are within `radius` (XZ) of `origin`.
func query_radius(origin: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2 := radius * radius
	var c0 := _cell(origin - Vector3(radius, 0, radius))
	var c1 := _cell(origin + Vector3(radius, 0, radius))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var bucket: PackedInt32Array = _grid.get(Vector2i(cx, cz), PackedInt32Array())
			for i in bucket:
				if hp[i] <= 0.0:
					continue
				var d := pos[i] - origin
				if d.x * d.x + d.z * d.z <= r2:
					out.append(i)
	return out


## Nearest live enemy within range whose direction lies inside a cone around
## `forward` (cos_half_arc = cos(arc/2); pass -1 for any direction).
func find_nearest(origin: Vector3, max_range: float, forward: Vector3 = Vector3.FORWARD, cos_half_arc: float = -1.0) -> int:
	var best := -1
	var best_d2 := max_range * max_range
	var f := Vector2(forward.x, forward.z).normalized()
	for i in count:
		if hp[i] <= 0.0:
			continue
		var dx := pos[i].x - origin.x
		var dz := pos[i].z - origin.z
		var d2 := dx * dx + dz * dz
		if d2 >= best_d2:
			continue
		if cos_half_arc > -1.0 and d2 > 0.0001:
			var inv := 1.0 / sqrt(d2)
			if (dx * f.x + dz * f.y) * inv < cos_half_arc:
				continue
		best = i
		best_d2 = d2
	return best


func clear_all() -> void:
	count = 0
	_grid.clear()
	_update_multimesh()


# --- Internals ----------------------------------------------------------------

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell_size), floori(p.z / cell_size))


func _rebuild_grid() -> void:
	_grid.clear()
	for i in count:
		var c := _cell(pos[i])
		if _grid.has(c):
			var b: PackedInt32Array = _grid[c]
			b.append(i)
			_grid[c] = b
		else:
			_grid[c] = PackedInt32Array([i])


func _simulate(delta: float) -> void:
	var robot := RunState.robot
	var target := robot.global_position if robot != null else Vector3.ZERO
	var robot_r := robot.get_body_radius() if robot != null else 0.5
	var chase := robot != null and robot.alive
	var steer := clampf(5.0 * delta, 0.0, 1.0)

	for i in count:
		if hp[i] <= 0.0:
			continue
		var t := enemy_types[type_idx[i]]
		var p := pos[i]
		var to := Vector3(target.x - p.x, 0.0, target.z - p.z)
		var d := to.length()

		var desired := Vector3.ZERO
		if chase and d > 0.001:
			desired = to / d * t.speed

		# Separation from up to 6 neighbors in this and adjacent cells.
		var sep := Vector3.ZERO
		var c := _cell(p)
		var checked := 0
		for ox in range(-1, 2):
			for oz in range(-1, 2):
				var bucket: PackedInt32Array = _grid.get(Vector2i(c.x + ox, c.y + oz), PackedInt32Array())
				for j in bucket:
					if j == i or hp[j] <= 0.0:
						continue
					var diff := p - pos[j]
					diff.y = 0.0
					var min_d := t.radius + enemy_types[type_idx[j]].radius
					var dl := diff.length_squared()
					if dl < min_d * min_d and dl > 0.000001:
						sep += diff / sqrt(dl) * (min_d - sqrt(dl)) * 8.0
						checked += 1
						if checked >= 6:
							break
				if checked >= 6:
					break
			if checked >= 6:
				break

		var v := vel[i].lerp(desired, steer) + sep * delta
		p += v * delta
		p.x = clampf(p.x, -arena_half_extent, arena_half_extent)
		p.z = clampf(p.z, -arena_half_extent, arena_half_extent)
		p.y = t.radius

		# Contact: the robot decides (ram, crush, armor), then no overlap.
		var contact := t.radius + robot_r
		if chase and d < contact:
			pos[i] = p
			vel[i] = v
			robot.handle_enemy_contact(self, i, -to, delta)
			v = vel[i] # keep any ram knockback
			if d > 0.001:
				p -= to / d * (contact - d)
		if cooldown[i] > 0.0:
			cooldown[i] -= delta

		pos[i] = p
		vel[i] = v
		if flash[i] > 0.0:
			flash[i] -= delta


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
	var t := enemy_types[type_idx[i]]
	var at := pos[i]
	RunState.kills += 1
	EventBus.enemy_killed.emit(t, at)
	var pickups := RunState.pickups
	if pickups != null:
		pickups.spawn_scrap(at, t.scrap_value)
		if _rng.randf() < t.part_drop_chance:
			var part := LootTable.roll_part()
			if part != null:
				pickups.spawn_part(at, part)


# Removes dead rows by swapping in the last live row. Runs at the start of the
# frame so indices stay stable for everyone else during the frame.
func _compact() -> void:
	var i := 0
	while i < count:
		if hp[i] <= 0.0:
			count -= 1
			pos[i] = pos[count]
			vel[i] = vel[count]
			hp[i] = hp[count]
			flash[i] = flash[count]
			cooldown[i] = cooldown[count]
			type_idx[i] = type_idx[count]
		else:
			i += 1


func _update_multimesh() -> void:
	_mm.visible_instance_count = count
	var robot := RunState.robot
	var target := robot.global_position if robot != null else Vector3.ZERO
	for i in count:
		var t := enemy_types[type_idx[i]]
		var p := pos[i]
		var look := Vector3(target.x - p.x, 0.0, target.z - p.z)
		var b := Basis.IDENTITY
		if look.length_squared() > 0.0001:
			b = Basis.looking_at(look.normalized(), Vector3.UP)
		# Prism points +Y; tip it forward so the wedge "noses" at the robot.
		b = b * Basis(Vector3.RIGHT, -PI * 0.5)
		var s := t.radius * 2.0
		b = b * Basis.from_scale(Vector3(s, s * 1.2, s * 0.8))
		_mm.set_instance_transform(i, Transform3D(b, p))
		var col := t.color
		if flash[i] > 0.0:
			col = Color.WHITE
		_mm.set_instance_color(i, col)
