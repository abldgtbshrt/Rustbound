class_name ScrapMawBehavior
extends PartBehavior

## A jaw that bites enemies in front of it and eats scrap to repair the
## robot. Params: bite_damage, bite_range, arc_deg, bite_interval,
## heal_per_bite, heal_per_scrap.

var bites: int = 0
var _cooldown := 0.0


func on_attached() -> void:
	if not EventBus.scrap_collected.is_connected(_on_scrap):
		EventBus.scrap_collected.connect(_on_scrap)


func on_detached() -> void:
	if EventBus.scrap_collected.is_connected(_on_scrap):
		EventBus.scrap_collected.disconnect(_on_scrap)


func _exit_tree() -> void:
	on_detached()


func _on_scrap(amount: int) -> void:
	if robot != null:
		robot.heal(float(amount) * float(param("heal_per_scrap", 1.5)))


func on_tick(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var enemies := RunState.enemies
	if enemies == null or robot == null:
		return
	var origin := part.global_position
	var fwd := part.get_facing_global()
	if fwd == Vector3.ZERO:
		fwd = -robot.global_basis.z
	var reach := float(param("bite_range", 1.4))
	var cos_half := cos(deg_to_rad(float(param("arc_deg", 100.0)) * 0.5))
	var dmg := float(param("bite_damage", 10.0)) * robot.assembly.get_mod(part, "damage_mult")
	var bit := false
	for i in enemies.query_radius(origin, reach + 1.0):
		var to := enemies.pos[i] - origin
		to.y = 0.0
		var d := to.length()
		if d > reach + enemies.get_radius(i) or (d > 0.05 and fwd.dot(to / d) < cos_half):
			continue
		enemies.damage(i, dmg)
		robot.heal(float(param("heal_per_bite", 2.0)))
		bit = true
	if bit:
		bites += 1
		_cooldown = float(param("bite_interval", 0.35))
