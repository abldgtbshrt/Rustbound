class_name NailgunBehavior
extends PartBehavior

## Auto-firing projectile weapon. Reads tuning from PartData.params:
##   fire_rate (shots/s), damage, range, speed, arc_deg, spread_deg,
##   recoil (impulse per shot), pierce, knockback, muzzle (m ahead of mount),
##   heat_per_shot, hot_fire_rate_mult (fire-rate multiplier while overheated)
## With CPU it aims at the nearest enemy inside its mount arc; without CPU it
## fires straight along the mount's facing whenever something is in range.

var _cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var shots_fired: int = 0


func on_attached() -> void:
	_rng.randomize()
	_cooldown = _rng.randf() * 0.2 # desync multiple guns


func on_tick(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var enemies := RunState.enemies
	var pool := RunState.projectiles
	if enemies == null or pool == null or robot == null:
		return
	var asm := robot.assembly

	var fire_rate := float(param("fire_rate", 4.0))
	var damage := float(param("damage", 8.0))
	var max_range := float(param("range", 16.0))
	var speed := float(param("speed", 30.0))
	var arc_deg := float(param("arc_deg", 200.0))
	var spread_deg := float(param("spread_deg", 3.0))
	var recoil := float(param("recoil", 0.5))
	var pierce := int(param("pierce", 0))
	var knockback := float(param("knockback", 1.5))
	var muzzle := float(param("muzzle", 0.45))
	var heat_per_shot := float(param("heat_per_shot", 0.0))
	# Linked neighbours (heat sinks, reactors, gyros, sensor heads) modify us.
	fire_rate *= asm.get_mod(part, "fire_rate_mult") * robot.get_overcharge_mult()
	damage *= asm.get_mod(part, "damage_mult")
	max_range *= asm.get_mod(part, "range_mult")
	spread_deg *= asm.get_mod(part, "spread_mult")
	heat_per_shot *= asm.get_mod(part, "heat_mult")
	if robot.is_overheated:
		fire_rate *= float(param("hot_fire_rate_mult", 1.0))

	# Brownout: shots stutter in proportion to the power deficit.
	if robot.browned_out and _rng.randf() > robot.get_power_supply():
		_cooldown = 0.35
		return

	var xf := part.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = -robot.global_basis.z
	fwd = fwd.normalized()
	var origin := xf.origin + fwd * muzzle

	var dir: Vector3
	if asm.has_cpu_for(part):
		var idx := enemies.find_nearest(origin, max_range, fwd, cos(deg_to_rad(arc_deg * 0.5)))
		if idx < 0:
			return
		var target := enemies.pos[idx]
		dir = (target - origin).normalized()
	else:
		if enemies.find_nearest(origin, max_range, fwd, cos(deg_to_rad(60.0))) < 0:
			return
		dir = fwd

	var spread := deg_to_rad(_rng.randf_range(-spread_deg, spread_deg))
	dir = dir.rotated(Vector3.UP, spread)
	pool.fire(origin, dir * speed, damage, max_range / speed * 1.15, 0.25, pierce, knockback)
	robot.apply_recoil(-Vector3(dir.x, 0.0, dir.z) * recoil)
	robot.add_heat(heat_per_shot)
	shots_fired += 1
	_cooldown = 1.0 / maxf(fire_rate, 0.01)
