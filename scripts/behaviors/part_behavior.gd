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


func param(key: String, default_value: Variant) -> Variant:
	if part == null or part.data == null:
		return default_value
	return part.data.params.get(key, default_value)


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
