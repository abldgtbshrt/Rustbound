class_name DroneBayBehavior
extends PartBehavior

## Launches little bots that orbit the robot and shoot the nearest enemy.
## Params: drones (count), damage, range, fire_interval, orbit_radius,
## heal_per_sec (Repair Drones path: each drone patches you up).

var drones: Array[Node3D] = []
var shots: int = 0
var _cooldowns: Array[float] = []
var _t := 0.0


func on_detached() -> void:
	for d in drones:
		d.queue_free()
	drones.clear()


func _sync_count() -> void:
	var want := int(param("drones", 1))
	while drones.size() < want:
		var d := Node3D.new()
		var body := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.18
		m.height = 0.3
		m.radial_segments = 6
		m.rings = 3
		body.mesh = m
		body.material_override = PartVisuals.material_for(Color(0.9, 0.8, 0.3))
		d.add_child(body)
		d.top_level = true
		part.add_child(d)
		d.global_position = part.global_position
		drones.append(d)
		_cooldowns.append(randf() * 0.5)
	while drones.size() > want:
		drones.pop_back().queue_free()
		_cooldowns.pop_back()


func on_tick(delta: float) -> void:
	if robot == null:
		return
	_sync_count()
	_t += delta
	var enemies := RunState.enemies
	var pool := RunState.projectiles
	var asm := robot.assembly
	var r := float(param("orbit_radius", 2.2))
	var heal := float(param("heal_per_sec", 0.0))
	for k in drones.size():
		var d := drones[k]
		var ang := _t * 1.6 + TAU * float(k) / float(drones.size())
		var goal := robot.global_position + Vector3(cos(ang) * r, 1.6 + 0.15 * sin(_t * 3.0 + k), sin(ang) * r)
		d.global_position = d.global_position.lerp(goal, clampf(6.0 * delta, 0.0, 1.0))
		if heal > 0.0:
			robot.heal(heal * delta)
		_cooldowns[k] -= delta
		if _cooldowns[k] > 0.0 or enemies == null or pool == null:
			continue
		var i := enemies.find_nearest(d.global_position, float(param("range", 10.0)) * asm.get_mod(part, "range_mult"))
		if i < 0:
			continue
		var to := enemies.get_pos(i) + Vector3(0, 0.3, 0) - d.global_position
		var speed := 24.0
		pool.fire(d.global_position, to.normalized() * speed, float(param("damage", 6.0)) * asm.get_mod(part, "damage_mult"),
			to.length() / speed * 1.3 + 0.1, 0.25, 0, 0.8, Color(1.0, 0.9, 0.3), hit_fx())
		shots += 1
		fired()
		_cooldowns[k] = float(param("fire_interval", 0.5)) / maxf(asm.get_mod(part, "fire_rate_mult") * robot.get_overcharge_mult(), 0.1)
