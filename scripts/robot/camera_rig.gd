class_name CameraRig
extends Node3D

## Follow camera. Hold right mouse to orbit, wheel to zoom. Movement input is
## camera-relative, so the rig tells the robot its yaw. Uses real (unscaled)
## time so it stays responsive in build mode's slow motion.

@export var target_path: NodePath
@export var distance: float = 15.0
@export var min_distance: float = 4.0
@export var max_distance: float = 30.0
@export var pitch_deg: float = 52.0
@export var orbit_sensitivity: float = 0.006
@export var follow_speed: float = 8.0

@export_group("Build view")
@export var build_distance: float = 6.5
@export var build_pitch_deg: float = 30.0

var yaw: float = 0.0
var build_view: bool = false

@onready var camera: Camera3D = $Camera3D
var _target: Node3D
var _cur_distance: float
var _cur_pitch: float
var _last_mouse := Vector2.ZERO
var _last_ticks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_target = get_node_or_null(target_path) as Node3D
	if _target != null:
		global_position = _target.global_position
	_cur_distance = distance
	_cur_pitch = pitch_deg
	_last_ticks = Time.get_ticks_usec()
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var step := 0.5 if build_view else 1.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(step)


func _zoom(amount: float) -> void:
	if build_view:
		build_distance = clampf(build_distance + amount, min_distance * 0.5, max_distance)
	else:
		distance = clampf(distance + amount, min_distance, max_distance)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := clampf(float(now - _last_ticks) / 1_000_000.0, 0.0, 0.1)
	_last_ticks = now

	# Orbit by polling so it works whichever viewport receives the events.
	var mouse := get_viewport().get_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= (mouse.x - _last_mouse.x) * orbit_sensitivity
	_last_mouse = mouse

	var want_d := build_distance if build_view else distance
	var want_p := build_pitch_deg if build_view else pitch_deg
	var k := clampf(6.0 * real_dt, 0.0, 1.0)
	_cur_distance = lerpf(_cur_distance, want_d, k)
	_cur_pitch = lerpf(_cur_pitch, want_p, k)

	if _target != null:
		var goal := _target.global_position + Vector3(0.0, 1.0, 0.0)
		global_position = global_position.lerp(goal, clampf(follow_speed * real_dt, 0.0, 1.0))
		if _target is RobotController:
			(_target as RobotController).camera_yaw = yaw
	_apply()


func _apply() -> void:
	rotation = Vector3(-deg_to_rad(_cur_pitch), yaw, 0.0)
	if camera != null:
		camera.position = Vector3(0.0, 0.0, _cur_distance)
