class_name ChainSwordBehavior
extends PartBehavior

## Melee arm. Swings at everything inside its reach and arc, in front of the
## way it's mounted. No CPU needed. Params:
##   damage, reach, arc_deg, swing_time (s between swings), knockback,
##   heat_per_swing
## Link mods apply: damage_mult, fire_rate_mult (swing speed), heat_mult,
## range_mult (reach).

var swings: int = 0
var _cooldown := 0.0
var _anim := 1.0 # 0..1 progress of the current swing animation
var _swing_side := 1.0


func on_tick(delta: float) -> void:
	_animate(delta)
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var enemies := RunState.enemies
	if enemies == null or robot == null:
		return
	var asm := robot.assembly
	var reach := float(param("reach", 2.4)) * asm.get_mod(part, "range_mult")
	var arc := float(param("arc_deg", 110.0))
	var dmg := float(param("damage", 20.0)) * asm.get_mod(part, "damage_mult")
	var swing_time := float(param("swing_time", 0.5)) / maxf(asm.get_mod(part, "fire_rate_mult") * robot.get_overcharge_mult(), 0.1)
	if robot.browned_out:
		swing_time /= maxf(robot.get_power_supply(), 0.3)
	var knock := float(param("knockback", 5.0))

	var origin := part.global_position
	var fwd := part.get_facing_global()
	if fwd == Vector3.ZERO:
		fwd = -robot.global_basis.z
	var cos_half := cos(deg_to_rad(arc * 0.5))
	var hit := 0
	for i in enemies.query_radius(origin, reach + 1.0):
		var to := enemies.pos[i] - origin
		to.y = 0.0
		var d := to.length()
		if d > reach + enemies.get_radius(i):
			continue
		if d > 0.05 and fwd.dot(to / d) < cos_half:
			continue
		enemies.damage(i, dmg, (to / maxf(d, 0.05)) * knock)
		hit += 1
	if hit == 0:
		return
	swings += 1
	robot.add_heat(float(param("heat_per_swing", 2.0)) * asm.get_mod(part, "heat_mult"))
	_cooldown = swing_time
	_anim = 0.0
	_swing_side = -_swing_side


func _animate(delta: float) -> void:
	if part == null or part.visual == null:
		return
	_anim = minf(_anim + delta / 0.25, 1.0)
	# Sweep across the arc and settle back to center.
	var a := sin(_anim * PI) * deg_to_rad(55.0) * _swing_side
	part.visual.rotation.y = a
