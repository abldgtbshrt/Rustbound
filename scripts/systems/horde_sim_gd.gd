class_name HordeSimGD
extends RefCounted

## GDScript twin of the native HordeSim (native/src/horde_sim.cpp). Same API,
## same behavior: EnemyManager uses this when the compiled library isn't
## available (unsupported platform, or a checkout without bin/). It's several
## times slower, so keep it correct rather than clever, and keep it in sync
## with the C++; tests/run_tests.gd runs both and compares them.

const FLASH_TIME := 0.12
const SEPARATION_NEIGHBORS := 6
const SEPARATION_FORCE := 8.0
const STEER_RATE := 5.0

var capacity: int = 0
var count: int = 0
var cell_size: float = 2.0
var arena_half: float = 58.0

var pos := PackedVector3Array()
var vel := PackedVector3Array()
var hp := PackedFloat32Array()
var flash := PackedFloat32Array()
var cooldown := PackedFloat32Array()
var slow_t := PackedFloat32Array()
var slow_mult := PackedFloat32Array()
var burn_t := PackedFloat32Array()
var burn_dps := PackedFloat32Array()
var type := PackedInt32Array()

var t_radius := PackedFloat32Array()
var t_speed := PackedFloat32Array()
var t_color := PackedColorArray()
var t_shape: Array[Basis] = []
var max_radius: float = 0.5

var grid_min: int = 0
var grid_n: int = 0
var cell_start := PackedInt32Array()
var cell_items := PackedInt32Array()
var cell_of := PackedInt32Array()
var grid_dirty: bool = true

var contacts := PackedInt32Array()
var contact_dirs := PackedVector3Array()
var contact_push := PackedVector3Array()
var kills := PackedInt32Array()
var mm_buffer := PackedFloat32Array()


func backend_name() -> String:
	return "gdscript"


# --- Setup --------------------------------------------------------------------

func setup(p_capacity: int, p_cell_size: float, p_arena_half_extent: float) -> void:
	capacity = maxi(p_capacity, 0)
	cell_size = maxf(p_cell_size, 0.1)
	arena_half = maxf(p_arena_half_extent, 1.0)
	count = 0
	# (Packed arrays are values: resize each one directly, not through a loop.)
	pos.resize(capacity)
	pos.fill(Vector3.ZERO)
	vel.resize(capacity)
	vel.fill(Vector3.ZERO)
	hp.resize(capacity)
	hp.fill(0.0)
	flash.resize(capacity)
	flash.fill(0.0)
	cooldown.resize(capacity)
	cooldown.fill(0.0)
	slow_t.resize(capacity)
	slow_t.fill(0.0)
	burn_t.resize(capacity)
	burn_t.fill(0.0)
	burn_dps.resize(capacity)
	burn_dps.fill(0.0)
	slow_mult.resize(capacity)
	slow_mult.fill(1.0)
	type.resize(capacity)
	type.fill(0)
	grid_min = floori(-arena_half / cell_size) - 1
	var grid_max := floori(arena_half / cell_size) + 1
	grid_n = grid_max - grid_min + 1
	cell_start.resize(grid_n * grid_n + 1)
	cell_items.resize(capacity)
	cell_of.resize(capacity)
	grid_dirty = true
	mm_buffer.resize(capacity * 16)
	kills.clear()
	contacts.clear()
	contact_dirs.clear()
	contact_push.clear()


func set_types(p_radius: PackedFloat32Array, p_speed: PackedFloat32Array, p_color: PackedColorArray) -> void:
	var n := p_radius.size()
	t_radius = p_radius.duplicate()
	t_speed.resize(n)
	t_color.resize(n)
	t_shape.resize(n)
	max_radius = 0.0
	var tip := Basis(Vector3.RIGHT, -PI * 0.5)
	for t in n:
		var r := p_radius[t]
		t_speed[t] = p_speed[t] if t < p_speed.size() else 0.0
		t_color[t] = p_color[t] if t < p_color.size() else Color.WHITE
		var s := r * 2.0
		# Prism points +Y; tip it forward so the wedge "noses" at the robot.
		t_shape[t] = tip * Basis.from_scale(Vector3(s, s * 1.2, s * 0.8))
		max_radius = maxf(max_radius, r)


# --- Rows ---------------------------------------------------------------------

func get_count() -> int:
	return count


func get_capacity() -> int:
	return capacity


func _valid(i: int) -> bool:
	return i >= 0 and i < count


func _type_radius(t: int) -> float:
	return t_radius[t] if t >= 0 and t < t_radius.size() else 0.5


func spawn(p_type: int, at: Vector3, p_hp: float) -> int:
	if count >= capacity or p_type < 0 or p_type >= t_radius.size():
		return -1
	var i := count
	count += 1
	pos[i] = Vector3(at.x, t_radius[p_type], at.z)
	vel[i] = Vector3.ZERO
	hp[i] = p_hp
	flash[i] = 0.0
	cooldown[i] = 0.0
	slow_t[i] = 0.0
	slow_mult[i] = 1.0
	burn_t[i] = 0.0
	burn_dps[i] = 0.0
	type[i] = p_type
	grid_dirty = true
	return i


func clear() -> void:
	count = 0
	kills.clear()
	contacts.clear()
	contact_dirs.clear()
	contact_push.clear()
	grid_dirty = true


func compact() -> void:
	var i := 0
	var changed := false
	while i < count:
		if hp[i] <= 0.0:
			count -= 1
			pos[i] = pos[count]
			vel[i] = vel[count]
			hp[i] = hp[count]
			flash[i] = flash[count]
			cooldown[i] = cooldown[count]
			slow_t[i] = slow_t[count]
			slow_mult[i] = slow_mult[count]
			burn_t[i] = burn_t[count]
			burn_dps[i] = burn_dps[count]
			type[i] = type[count]
			changed = true
		else:
			i += 1
	if changed:
		grid_dirty = true


func is_alive(i: int) -> bool:
	return _valid(i) and hp[i] > 0.0


func alive_count() -> int:
	var n := 0
	for i in count:
		if hp[i] > 0.0:
			n += 1
	return n


func get_pos(i: int) -> Vector3:
	return pos[i] if _valid(i) else Vector3.ZERO

func set_pos(i: int, p: Vector3) -> void:
	if _valid(i): pos[i] = p

func get_vel(i: int) -> Vector3:
	return vel[i] if _valid(i) else Vector3.ZERO

func set_vel(i: int, v: Vector3) -> void:
	if _valid(i): vel[i] = v

func get_hp(i: int) -> float:
	return hp[i] if _valid(i) else 0.0

func set_hp(i: int, v: float) -> void:
	if _valid(i): hp[i] = v

func get_type(i: int) -> int:
	return type[i] if _valid(i) else -1

func get_flash(i: int) -> float:
	return flash[i] if _valid(i) else 0.0

func get_cooldown(i: int) -> float:
	return cooldown[i] if _valid(i) else 0.0

func set_cooldown(i: int, v: float) -> void:
	if _valid(i): cooldown[i] = v

func get_slow_t(i: int) -> float:
	return slow_t[i] if _valid(i) else 0.0

func get_slow_mult(i: int) -> float:
	return slow_mult[i] if _valid(i) else 1.0

func get_burn_t(i: int) -> float:
	return burn_t[i] if _valid(i) else 0.0

func get_burn_dps(i: int) -> float:
	return burn_dps[i] if _valid(i) else 0.0


# --- Combat -------------------------------------------------------------------

func damage(i: int, amount: float, knockback: Vector3) -> bool:
	if not is_alive(i):
		return false
	hp[i] -= amount
	flash[i] = FLASH_TIME
	vel[i] += knockback
	return hp[i] <= 0.0


func apply_slow(i: int, mult: float, duration: float) -> void:
	if not is_alive(i):
		return
	if slow_t[i] <= 0.0 or mult < slow_mult[i]:
		slow_mult[i] = clampf(mult, 0.05, 1.0)
	slow_t[i] = maxf(slow_t[i], duration)


func apply_burn(i: int, dps: float, duration: float) -> void:
	if not is_alive(i):
		return
	burn_dps[i] = maxf(burn_dps[i] if burn_t[i] > 0.0 else 0.0, dps)
	burn_t[i] = maxf(burn_t[i], duration)


func damage_radius(origin: Vector3, radius: float, amount: float, knockback: float) -> int:
	var hits := 0
	for i in query_radius(origin, radius + 1.0):
		var to := pos[i] - origin
		to.y = 0.0
		var d := to.length()
		var reach := radius + _type_radius(type[i])
		if d > reach:
			continue
		var falloff := lerpf(1.0, 0.5, clampf(d / reach, 0.0, 1.0))
		if damage(i, amount * falloff, (to / maxf(d, 0.01)) * knockback):
			kills.append(i)
		hits += 1
	return hits


func take_kills() -> PackedInt32Array:
	var out := kills
	kills = PackedInt32Array()
	return out


# --- Grid ---------------------------------------------------------------------

func _cell(v: float) -> int:
	return clampi(floori(v / cell_size), grid_min, grid_min + grid_n - 1)


func rebuild_grid() -> void:
	var cells := grid_n * grid_n
	cell_start.fill(0)
	var gmax := grid_min + grid_n - 1
	var inv_cell := 1.0 / cell_size
	for i in count:
		var p := pos[i]
		var c := (clampi(floori(p.x * inv_cell), grid_min, gmax) - grid_min) * grid_n \
			+ (clampi(floori(p.z * inv_cell), grid_min, gmax) - grid_min)
		cell_of[i] = c
		cell_start[c + 1] += 1
	for c in cells:
		cell_start[c + 1] += cell_start[c]
	var fill := cell_start.slice(0, cells)
	for i in count:
		var c := cell_of[i]
		cell_items[fill[c]] = i
		fill[c] += 1
	grid_dirty = false


# --- Queries ------------------------------------------------------------------

func query_radius(origin: Vector3, radius: float) -> PackedInt32Array:
	if grid_dirty:
		rebuild_grid()
	var out := PackedInt32Array()
	var r2 := radius * radius
	var x0 := _cell(origin.x - radius)
	var x1 := _cell(origin.x + radius)
	var z0 := _cell(origin.z - radius)
	var z1 := _cell(origin.z + radius)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var c := (cx - grid_min) * grid_n + (cz - grid_min)
			for k in range(cell_start[c], cell_start[c + 1]):
				var i := cell_items[k]
				if hp[i] <= 0.0:
					continue
				var dx := pos[i].x - origin.x
				var dz := pos[i].z - origin.z
				if dx * dx + dz * dz <= r2:
					out.append(i)
	return out


func query_segment(origin: Vector3, dir: Vector3, reach: float, width: float) -> PackedInt32Array:
	if grid_dirty:
		rebuild_grid()
	var out := PackedInt32Array()
	var tip := origin + dir * reach
	var pad := width + max_radius
	var x0 := _cell(minf(origin.x, tip.x) - pad)
	var x1 := _cell(maxf(origin.x, tip.x) + pad)
	var z0 := _cell(minf(origin.z, tip.z) - pad)
	var z1 := _cell(maxf(origin.z, tip.z) + pad)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var c := (cx - grid_min) * grid_n + (cz - grid_min)
			for k in range(cell_start[c], cell_start[c + 1]):
				var i := cell_items[k]
				if hp[i] <= 0.0:
					continue
				var to := pos[i] - origin
				to.y = 0.0
				var along := to.dot(dir)
				if along < 0.0 or along > reach:
					continue
				if (to - dir * along).length() <= width + _type_radius(type[i]):
					out.append(i)
	return out


func find_nearest(origin: Vector3, max_range: float, forward: Vector3, cos_half_arc: float) -> int:
	if grid_dirty:
		rebuild_grid()
	if count == 0:
		return -1
	var best := -1
	var best_d2 := max_range * max_range
	var f := Vector2(forward.x, forward.z).normalized()
	var use_arc := cos_half_arc > -1.0
	var ox := floori(origin.x / cell_size)
	var oz := floori(origin.z / cell_size)
	var max_ring := ceili(max_range / cell_size) + 1
	var gmax := grid_min + grid_n - 1
	for r in max_ring + 1:
		if r >= 2:
			var gap := (r - 1) * cell_size
			if gap * gap > best_d2:
				break
		for cx in range(ox - r, ox + r + 1):
			if cx < grid_min or cx > gmax:
				continue
			var edge_col := cx == ox - r or cx == ox + r
			var step := 1 if (edge_col or r == 0) else 2 * r
			for cz in range(oz - r, oz + r + 1, step):
				if cz < grid_min or cz > gmax:
					continue
				var c := (cx - grid_min) * grid_n + (cz - grid_min)
				for k in range(cell_start[c], cell_start[c + 1]):
					var i := cell_items[k]
					if hp[i] <= 0.0:
						continue
					var dx := pos[i].x - origin.x
					var dz := pos[i].z - origin.z
					var d2 := dx * dx + dz * dz
					if d2 >= best_d2 and not (d2 == best_d2 and best >= 0 and i < best):
						continue
					if use_arc and d2 > 0.0001:
						var inv := 1.0 / sqrt(d2)
						if (dx * f.x + dz * f.y) * inv < cos_half_arc:
							continue
					best = i
					best_d2 = d2
	return best


# --- Per frame ----------------------------------------------------------------

func step(delta: float, target: Vector3, robot_radius: float, chase: bool) -> void:
	rebuild_grid()
	contacts.clear()
	contact_dirs.clear()
	contact_push.clear()
	var steer := clampf(STEER_RATE * delta, 0.0, 1.0)
	var gmax := grid_min + grid_n - 1
	var inv_cell := 1.0 / cell_size
	# Hot loop: everything inlined, since GDScript function calls are costly.
	for i in count:
		if hp[i] <= 0.0:
			continue
		var t := type[i]
		var rad := t_radius[t]
		var p := pos[i]
		var to := Vector3(target.x - p.x, 0.0, target.z - p.z)
		var d := to.length()

		var desired := Vector3.ZERO
		if chase and d > 0.001:
			desired = to * (t_speed[t] / d)

		var sep := Vector3.ZERO
		var checked := 0
		var cx := clampi(floori(p.x * inv_cell), grid_min, gmax)
		var cz := clampi(floori(p.z * inv_cell), grid_min, gmax)
		for nx in range(maxi(cx - 1, grid_min), mini(cx + 1, gmax) + 1):
			if checked >= SEPARATION_NEIGHBORS:
				break
			var row := (nx - grid_min) * grid_n - grid_min
			for nz in range(maxi(cz - 1, grid_min), mini(cz + 1, gmax) + 1):
				if checked >= SEPARATION_NEIGHBORS:
					break
				var c := row + nz
				for k in range(cell_start[c], cell_start[c + 1]):
					var j := cell_items[k]
					if j == i or hp[j] <= 0.0:
						continue
					var q := pos[j]
					var dx := p.x - q.x
					var dz := p.z - q.z
					var min_d := rad + t_radius[type[j]]
					var dl := dx * dx + dz * dz
					if dl < min_d * min_d and dl > 0.000001:
						var dist := sqrt(dl)
						var push := (min_d - dist) * SEPARATION_FORCE / dist
						sep.x += dx * push
						sep.z += dz * push
						checked += 1
						if checked >= SEPARATION_NEIGHBORS:
							break

		if slow_t[i] > 0.0:
			slow_t[i] -= delta
			desired *= slow_mult[i]
		if burn_t[i] > 0.0:
			burn_t[i] -= delta
			hp[i] -= burn_dps[i] * delta # no hit flash for damage over time
			if hp[i] <= 0.0:
				kills.append(i)
				continue
		var v := vel[i].lerp(desired, steer) + sep * delta
		p += v * delta
		p.x = clampf(p.x, -arena_half, arena_half)
		p.z = clampf(p.z, -arena_half, arena_half)
		p.y = rad

		var contact := rad + robot_radius
		if chase and d < contact:
			contacts.append(i)
			contact_dirs.append(-to)
			contact_push.append(-(to / d) * (contact - d) if d > 0.001 else Vector3.ZERO)
		if cooldown[i] > 0.0:
			cooldown[i] -= delta
		if flash[i] > 0.0:
			flash[i] -= delta
		pos[i] = p
		vel[i] = v


func get_contacts() -> PackedInt32Array:
	return contacts.duplicate()


func get_contact_dirs() -> PackedVector3Array:
	return contact_dirs.duplicate()


func resolve_contacts() -> void:
	for k in contacts.size():
		var i := contacts[k]
		if _valid(i):
			pos[i] += contact_push[k]
	contacts.clear()
	contact_dirs.clear()
	contact_push.clear()


func get_multimesh_buffer(target: Vector3) -> PackedFloat32Array:
	if mm_buffer.size() != capacity * 16:
		mm_buffer.resize(capacity * 16)
	var burn_col := Color(1.0, 0.5, 0.1)
	var slow_col := Color(0.4, 0.7, 1.0)
	for i in count:
		var t := type[i]
		var p := pos[i]
		var look := Vector3(target.x - p.x, 0.0, target.z - p.z)
		var b := Basis.IDENTITY
		if look.length_squared() > 0.0001:
			b = Basis.looking_at(look.normalized(), Vector3.UP)
		b = b * (t_shape[t] if t >= 0 and t < t_shape.size() else Basis.IDENTITY)
		var o := i * 16
		# Basis columns are x/y/z; the buffer wants rows.
		mm_buffer[o] = b.x.x
		mm_buffer[o + 1] = b.y.x
		mm_buffer[o + 2] = b.z.x
		mm_buffer[o + 3] = p.x
		mm_buffer[o + 4] = b.x.y
		mm_buffer[o + 5] = b.y.y
		mm_buffer[o + 6] = b.z.y
		mm_buffer[o + 7] = p.y
		mm_buffer[o + 8] = b.x.z
		mm_buffer[o + 9] = b.y.z
		mm_buffer[o + 10] = b.z.z
		mm_buffer[o + 11] = p.z
		var col := t_color[t] if t >= 0 and t < t_color.size() else Color.WHITE
		if burn_t[i] > 0.0:
			col = col.lerp(burn_col, 0.5)
		elif slow_t[i] > 0.0:
			col = col.lerp(slow_col, 0.5)
		if flash[i] > 0.0:
			col = Color.WHITE
		mm_buffer[o + 12] = col.r
		mm_buffer[o + 13] = col.g
		mm_buffer[o + 14] = col.b
		mm_buffer[o + 15] = col.a
	return mm_buffer


func upload_multimesh(multimesh: RID, target: Vector3) -> void:
	if not multimesh.is_valid() or capacity == 0:
		return
	RenderingServer.multimesh_set_buffer(multimesh, get_multimesh_buffer(target))
