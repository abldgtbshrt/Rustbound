class_name RobotController
extends CharacterBody3D

@export var move_speed: float = 8.0
@export var base_accel: float = 24.0
@export var jump_velocity: float = 6.5
@export var gravity: float = 20.0

@export var drift_factor: float = 0.6
@export var tip_threshold: float = 1.0

@onready var assembly: RobotAssembly = $RobotAssembly

var _tilt: float = 0.0

func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var mass := max(assembly.total_mass if assembly != null else 1.0, 0.25)
	var accel := base_accel / mass

	var dir_local := Vector3(input.x, 0.0, input.y)
	var desired := (transform.basis * dir_local)
	desired.y = 0.0
	desired = desired.normalized() * move_speed

	velocity.x = move_toward(velocity.x, desired.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired.z, accel * delta)

	if assembly != null:
		velocity += transform.basis.x * assembly.center_of_mass.x * drift_factor * delta
		_update_tipping(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	move_and_slide()

func _update_tipping(delta: float) -> void:
	var stability := max(assembly.footprint, 0.1)
	var com_height := max(assembly.center_of_mass.y, 0.0)
	var lateral := Vector2(velocity.x, velocity.z).length()
	var tip_force := (com_height * lateral) / stability
	_tilt = lerp(_tilt, tip_force, 6.0 * delta)
	if _tilt > tip_threshold:
		_on_fall_over()

func _on_fall_over() -> void:
	# Placeholder hook for knockdown/recovery logic.
	_tilt = 0.0
