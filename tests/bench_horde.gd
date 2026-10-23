extends Node

## Horde benchmark. Run headless:
##   godot --headless res://tests/bench_horde.tscn
## For each backend and horde size it fills the prototype arena (spawning off,
## robot invulnerable, weapons firing as normal) and reports:
##   sim ms   EnemyManager's own work per frame (steer, grid, contacts, MultiMesh)
##   frame ms Godot's whole physics step (all weapons, projectiles, pickups...)
## Numbers vary by machine; compare backends and sizes on the same machine.

## Override with env vars, e.g. BENCH_SIZES=600,1000 BENCH_BACKENDS=native
const SIZES := [300, 600, 1000, 1500, 2000]
const WARMUP := 30
const FRAMES := 120


func _ready() -> void:
	await get_tree().process_frame # root is still adding children
	var backends := ["gdscript"]
	if ClassDB.class_exists("HordeSim"):
		backends.append("native")
	else:
		print("native HordeSim not loaded: benchmarking GDScript only")
	var sizes: Array = SIZES
	if OS.get_environment("BENCH_SIZES") != "":
		sizes = Array(OS.get_environment("BENCH_SIZES").split(",")).map(func(x: String) -> int: return x.to_int())
	if OS.get_environment("BENCH_BACKENDS") != "":
		backends = Array(OS.get_environment("BENCH_BACKENDS").split(","))
	print("%-9s %6s %9s %9s" % ["backend", "N", "sim ms", "frame ms"])
	for backend in backends:
		for n in sizes:
			var r := await _run(backend, n)
			print("%-9s %6d %9.2f %9.2f" % [backend, n, r[0], r[1]])
	get_tree().quit()


func _run(backend: String, n: int) -> Array:
	var scene: Node = load("res://scenes/levels/prototype_arena.tscn").instantiate()
	var em: EnemyManager = scene.get_node("EnemyManager")
	em.max_enemies = n
	em.backend = backend
	em.spawn_enabled = false
	get_tree().root.add_child(scene)
	await get_tree().physics_frame
	var robot: RobotController = RunState.robot
	robot.base_hp = 1.0e9
	robot.max_hp = 1.0e9
	robot.hp = 1.0e9
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var center := robot.global_position
	for i in n:
		var ang := rng.randf() * TAU
		var k := em.spawn(0 if i % 10 else 2, center + Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(4.0, 40.0))
		em.set_hp(k, 1.0e6) # keep the horde full for the whole measurement

	for f in WARMUP:
		await get_tree().physics_frame
	var sim_us := 0
	var frame_s := 0.0
	for f in FRAMES:
		await get_tree().physics_frame
		frame_s += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		sim_us += em.last_step_usec
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return [float(sim_us) / FRAMES / 1000.0, frame_s / FRAMES * 1000.0]
