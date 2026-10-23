class_name MagnetArmBehavior
extends PartBehavior

## Pulls small enemies in its facing arc toward it (into your melee / treads)
## and, via the part's pickup_radius, drags scrap in from far away.
## Params: pull_range, arc_deg, pull_speed, max_enemy_radius.

func on_tick(delta: float) -> void:
	var enemies := RunState.enemies
	if enemies == null or robot == null or robot.browned_out:
		return
	var origin := part.global_position
	var fwd := part.get_facing_global()
	if fwd == Vector3.ZERO:
		return
	var reach := float(param("pull_range", 9.0))
	var cos_half := cos(deg_to_rad(arc_param(100.0) * 0.5))
	var speed := float(param("pull_speed", 6.0))
	var max_r := float(param("max_enemy_radius", 0.45))
	for i in enemies.query_radius(origin, reach):
		if enemies.get_radius(i) > max_r:
			continue
		var to := enemies.pos[i] - origin
		to.y = 0.0
		var d := to.length()
		if d < 0.8 or fwd.dot(to / d) < cos_half:
			continue
		enemies.pos[i] -= (to / d) * speed * delta
