class_name CameraRig
extends Node3D

## Follow camera. Hold right mouse to orbit, wheel to zoom. Movement input is
## camera-relative, so the rig tells the robot its yaw.

@export var target_path: NodePath
@export var distance: float = 15.0
@export var min_distance: float = 7.0
@export var max_distance: float = 30.0
@export var pitch_deg: float = 52.0
@export var orbit_sensitivity: float = 0.006
@export var follow_speed: float = 8.0

var yaw: float = 0.0

@onready var camera: Camera3D = $Camera3D
var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target != null:
		global_position = _target.global_position
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		yaw -= event.relative.x * orbit_sensitivity
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance - 1.0, min_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance + 1.0, max_distance)


func _process(delta: float) -> void:
	if _target != null:
		var goal := _target.global_position + Vector3(0.0, 1.0, 0.0)
		global_position = global_position.lerp(goal, clampf(follow_speed * delta, 0.0, 1.0))
		if _target is RobotController:
			(_target as RobotController).camera_yaw = yaw
	_apply()


func _apply() -> void:
	rotation = Vector3(-deg_to_rad(pitch_deg), yaw, 0.0)
	if camera != null:
		camera.position = Vector3(0.0, 0.0, distance)
