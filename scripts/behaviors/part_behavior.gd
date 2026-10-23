class_name PartBehavior
extends Node

## Base class for anything a part *does*: weapons, components, synergies.
## RobotController ticks every behavior from its physics step.

var part: PartInstance
var robot: RobotController


func setup(p_part: PartInstance, p_robot: RobotController) -> void:
	part = p_part
	robot = p_robot
	on_attached()


## A tuning value from PartData.params, scaled by the part's upgrade tier.
func param(key: String, default_value: Variant) -> Variant:
	if part == null or part.data == null:
		return default_value
	var v: Variant = part.data.params.get(key, default_value)
	var path := part.get_chosen_path()
	if not path.is_empty() and (path.get("params", {}) as Dictionary).has(key):
		v = path["params"][key] # the chosen Mk III path overrides / adds params
	if v is float or v is int:
		var scaled := part.stat(key, float(v))
		return int(round(scaled)) if v is int else scaled
	return v


## Firing / effect arc in degrees, widened by the chassis (Carousel).
func arc_param(default_value: float) -> float:
	var arc := float(param("arc_deg", default_value))
	if robot != null:
		arc += robot.assembly.arc_bonus
	return minf(arc, 360.0)


## On-hit extras (splash, slow, burn) gathered from params, for projectiles
## and melee hits.
func hit_fx() -> Dictionary:
	var out := {}
	for k in ["splash_radius", "splash_frac", "slow_mult", "slow_dur", "burn_dps", "burn_dur"]:
		var v: Variant = param(k, 0.0)
		if float(v) != 0.0:
			out[k] = float(v)
	return out


## Weapons call this when they shoot/swing/zap, for sound and feedback.
func fired() -> void:
	if part != null:
		EventBus.weapon_fired.emit(part.data.id, part.global_position)


func on_attached() -> void:
	pass


func on_detached() -> void:
	pass


func on_tick(_delta: float) -> void:
	pass


func on_land() -> void:
	pass


func on_hit(_damage: float) -> void:
	pass


func on_brownout() -> void:
	pass
