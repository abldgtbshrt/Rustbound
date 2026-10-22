extends Node3D

## Prototype arena: starts a run, scatters low-poly landmarks and handles
## restart. Gameplay systems register themselves with RunState.

@export var arena_half_extent: float = 60.0
@export var obstacle_count: int = 26
@export var run_seed: int = 0
## Scatter a few part pickups near the start so the attach flow is testable.
@export var starter_pickups: Array[PartData] = []


var _restart_was_down := false


func _ready() -> void:
	# A reload can happen mid-build-mode or mid-level-up.
	Engine.time_scale = 1.0
	get_tree().paused = false
	RunState.begin_new_run(run_seed)
	_build_walls()
	_scatter_obstacles()
	var pickups := RunState.pickups
	if pickups != null:
		for k in starter_pickups.size():
			var ang := TAU * float(k) / maxf(float(starter_pickups.size()), 1.0)
			pickups.spawn_part(Vector3(cos(ang), 0.0, sin(ang)) * 6.0, starter_pickups[k])


func _process(_delta: float) -> void:
	# Polled so it works inside the PS2 SubViewport too. Only after death, or
	# with the game unpaused, so R doesn't clash with level-up's repair key.
	var down := Input.is_action_pressed("restart")
	if down and not _restart_was_down and not get_tree().paused:
		get_tree().reload_current_scene()
	_restart_was_down = down


func _build_walls() -> void:
	var h := arena_half_extent
	for spec in [[Vector3(0, 2, -h - 0.5), Vector3(2 * h + 2, 4, 1)], [Vector3(0, 2, h + 0.5), Vector3(2 * h + 2, 4, 1)],
			[Vector3(-h - 0.5, 2, 0), Vector3(1, 4, 2 * h + 2)], [Vector3(h + 0.5, 2, 0), Vector3(1, 4, 2 * h + 2)]]:
		_add_block(spec[0], spec[1], Vector3.ZERO, Color(0.35, 0.3, 0.28))


func _scatter_obstacles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = RunState.run_seed
	var palette := [Color(0.45, 0.4, 0.35), Color(0.5, 0.33, 0.22), Color(0.35, 0.38, 0.4)]
	for k in obstacle_count:
		var p := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * (arena_half_extent - 6.0)
		if p.length() < 10.0:
			continue # keep the drop zone clear
		var size := Vector3(rng.randf_range(2, 6), rng.randf_range(1, 5), rng.randf_range(2, 6))
		var rot := Vector3(0, rng.randf_range(0, 180), 0)
		if k % 5 == 0:
			# Ramp: a tilted slab you can drive up.
			size = Vector3(4, 0.5, 9)
			rot.x = 14.0
			p.y = 1.0
		else:
			p.y = size.y * 0.5
		_add_block(p, size, rot, palette[k % palette.size()])


func _add_block(at: Vector3, size: Vector3, rot_deg: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation_degrees = rot_deg
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = PartVisuals.material_for(color)
	body.add_child(mi)
	$Obstacles.add_child(body)
