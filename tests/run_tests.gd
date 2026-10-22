extends Node

## Headless smoke + rules tests. From the project root:
##   godot --headless --fixed-fps 60 res://tests/run_tests.tscn
## Exit code 0 = all passed. (Run as a scene, not with -s, so autoloads exist
## before game scripts compile.)

# Autoload names aren't compile-time globals in a -s script; look it up.
var rs: Node
var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	rs = get_node("/root/RunState")
	_test_assembly_math()
	_test_socket_rules()
	_test_tip_ratio()
	_test_overload()
	await _test_arena_loop()
	await _test_part_pickup()
	await _bench_horde()
	print("")
	print("%d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)


func part(id: String) -> PartData:
	var p: PartData = load("res://data/parts/%s.tres" % id)
	assert(p != null, "missing part " + id)
	return p


func make_assembly(chassis: String, layout: Array) -> RobotAssembly:
	var a := RobotAssembly.new()
	a.root_part_data = part("core_scrapper")
	var parts: Array[PartData] = [part(chassis)]
	var sockets: Array[StringName] = [&"chassis"]
	for e in layout:
		parts.append(part(e[0]))
		sockets.append(StringName(e[1]))
	a.starting_parts = parts
	a.starting_sockets = sockets
	a.build(null)
	return a


func _test_assembly_math() -> void:
	print("assembly math")
	var a := make_assembly("chassis_box", [["loco_biped_leg", "loco_l"], ["loco_biped_leg", "loco_r"], ["gun_nail", "mount_top"]])
	check(a.part_count == 5, "starter robot has 5 parts (got %d)" % a.part_count)
	check(is_equal_approx(a.total_mass, 8.8), "mass = 8.8 (got %.2f)" % a.total_mass)
	check(absf(a.center_of_mass.x) < 0.01, "symmetric build has centered CoM (x=%.3f)" % a.center_of_mass.x)
	check(a.center_of_mass.y > 0.6 and a.center_of_mass.y < 1.6, "CoM height plausible (%.2f)" % a.center_of_mass.y)
	check(a.height > 1.4 and a.height < 2.2, "height plausible (%.2f)" % a.height)
	check(a.footprint > 0.3, "two legs give a real footprint (%.2f)" % a.footprint)
	check(a.locomotion.part_count == 2 and a.locomotion.can_jump, "biped profile can jump")
	check(a.cpu_used == 1 and a.cpu_capacity == 2, "nailgun uses 1 of 2 CPU")
	check(not a.is_browned_out(), "starter build is not browned out")

	# Lowest point must sit on y = 0.
	var min_y := INF
	for e in a._walk_local():
		min_y = minf(min_y, a._part_bounds(e[0], e[1]).position.y)
	check(absf(min_y) < 0.01, "robot is lifted so its feet touch y=0 (min y %.3f)" % min_y)

	# Asymmetric: heavy cannon on one side shifts CoM to that side.
	var lop := make_assembly("chassis_box", [["loco_biped_leg", "loco_l"], ["loco_biped_leg", "loco_r"], ["gun_rivet", "mount_l"]])
	check(lop.center_of_mass.x < -0.05, "left-mounted cannon pulls CoM left (x=%.2f)" % lop.center_of_mass.x)

	var tower := make_assembly("chassis_tower", [["loco_biped_leg", "loco_l"], ["loco_biped_leg", "loco_r"], ["gun_nail", "mount_top"]])
	check(tower.center_of_mass.y > a.center_of_mass.y + 0.2, "tower CoM is higher than box (%.2f vs %.2f)" % [tower.center_of_mass.y, a.center_of_mass.y])

	var ball := make_assembly("chassis_box", [])
	check(ball.locomotion.is_ball and not ball.locomotion.can_jump, "no locomotion falls back to ball mode")
	for x in [a, lop, tower, ball]:
		x.free()


func _test_socket_rules() -> void:
	print("socket rules")
	var a := make_assembly("chassis_box", [["loco_biped_leg", "loco_l"], ["loco_biped_leg", "loco_r"]])
	var chassis := a.root.get_child_in(&"chassis")
	check(chassis != null, "chassis sits in core socket")
	check(a.attach(part("loco_wheel"), chassis, &"mount_l") == null, "wheel rejected on a mount socket")
	check(a.attach(part("gun_rivet"), a.root.walk()[2], &"mount_shin") == null, "size-2 cannon rejected on size-1 shin mount")
	var adapter := a.attach(part("adapter_mount_loco"), chassis, &"mount_l")
	check(adapter != null, "adapter fits a mount socket")
	var wheel := a.attach(part("loco_wheel"), adapter, &"loco") if adapter != null else null
	check(wheel != null, "adapter lets a wheel go on a mount")
	check(a.locomotion.part_count == 3, "wheel joins the locomotion blend (%d parts)" % a.locomotion.part_count)
	check(a.attach(part("gun_nail"), chassis, &"mount_l") == null, "occupied socket is rejected")

	# Detach removes the subtree.
	var before := a.part_count
	var removed := a.detach(adapter)
	check(removed.size() == 2 and a.part_count == before - 2, "detach removes adapter + wheel")

	# auto_attach fills sockets until none fit.
	var n := 0
	while a.auto_attach(part("mod_gyro")) != null:
		n += 1
	check(n == 2, "box chassis has 2 internal sockets (filled %d)" % n)
	check(a.stability > 1.1, "two gyros add stability (%.2f)" % a.stability)
	a.free()


func _test_tip_ratio() -> void:
	print("tipping")
	var box := make_assembly("chassis_box", [["loco_biped_leg", "loco_l"], ["loco_biped_leg", "loco_r"], ["gun_nail", "mount_top"]])
	var tower := make_assembly("chassis_tower", [["loco_biped_leg", "loco_l"], ["loco_biped_leg", "loco_r"], ["gun_nail", "mount_top"]])
	var accel := 7.0
	var dir := Vector2(0, 1) # braking / reversing front-to-back
	var r_box := RobotController.compute_tip_ratio(accel, box.center_of_mass.y, box.tip_lever(dir), box.stability, 20.0, 0.5)
	var r_tower := RobotController.compute_tip_ratio(accel, tower.center_of_mass.y, tower.tip_lever(dir), tower.stability, 20.0, 0.5)
	check(r_box < 1.0, "box biped survives a hard reversal (ratio %.2f)" % r_box)
	check(r_tower > r_box, "tower is tippier than box (%.2f vs %.2f)" % [r_tower, r_box])
	tower.auto_attach(part("mod_gyro"))
	var r_gyro := RobotController.compute_tip_ratio(accel, tower.center_of_mass.y, tower.tip_lever(dir), tower.stability, 20.0, 0.5)
	check(r_gyro < r_tower, "gyro reduces tower tip ratio (%.2f -> %.2f)" % [r_tower, r_gyro])
	box.free()
	tower.free()


func _test_overload() -> void:
	print("mass budget")
	var a := make_assembly("chassis_box", [["loco_wheel", "loco_l"]])
	var cap := a.locomotion.mass_capacity
	check(a.total_mass > cap, "one wheel can't carry a box chassis (%.1f > %.1f)" % [a.total_mass, cap])
	a.free()


func _test_arena_loop() -> void:
	print("arena loop (simulated)")
	var scene: Node = load("res://scenes/levels/prototype_arena.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var robot: RobotController = rs.robot
	check(robot != null and rs.enemies != null and rs.projectiles != null and rs.pickups != null, "systems registered with RunState")
	check(robot.assembly.part_count == 5, "robot spawned with starter build")
	check(robot.max_hp > 100.0, "hp derived from parts (%d)" % int(robot.max_hp))

	# Strafe in a circle for ~20 s of game time.
	var guns := []
	for b in robot.assembly.get_all_behaviors():
		if b is NailgunBehavior:
			guns.append(b)
	var frames := 60 * 20
	for f in frames:
		var ang := float(f) / 60.0 * 0.8
		Input.action_release("move_forward")
		Input.action_release("move_right")
		if f % 240 < 180:
			Input.action_press("move_forward")
		if f % 120 < 60:
			Input.action_press("move_right")
		await get_tree().physics_frame
	Input.action_release("move_forward")
	Input.action_release("move_right")

	var shots := 0
	for g in guns:
		shots += (g as NailgunBehavior).shots_fired
	print("    t=%.1fs kills=%d scrap=%d hp=%d enemies=%d shots=%d hits=%d pos=%s" % [rs.elapsed_time, rs.kills,
		rs.scrap, int(robot.hp), rs.enemies.alive_count(), shots, rs.projectiles.hits, robot.global_position])
	check(rs.elapsed_time > 15.0, "run clock advanced")
	check(rs.enemies.alive_count() > 0 or rs.kills > 0, "enemies spawned")
	check(shots > 10, "nailgun auto-fired (%d shots)" % shots)
	check(rs.projectiles.hits > 0, "projectiles hit enemies (%d)" % rs.projectiles.hits)
	check(rs.kills > 0, "enemies died (%d)" % rs.kills)
	check(rs.scrap > 0, "scrap collected (%d)" % rs.scrap)
	check(robot.global_position.length() > 1.0, "robot moved")
	check(robot.global_position.y > -0.5 and robot.global_position.y < 1.0, "robot stayed on the ground (y=%.2f)" % robot.global_position.y)
	scene.queue_free()
	await get_tree().process_frame


func _test_part_pickup() -> void:
	print("part pickup")
	var scene: Node = load("res://scenes/levels/prototype_arena.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var robot: RobotController = rs.robot
	rs.enemies.spawn_enabled = false
	rs.pickups.clear_all()
	var before := robot.assembly.part_count
	var gyro_stab := robot.assembly.stability
	rs.pickups.spawn_part(robot.global_position + Vector3(0.5, 0, 0), part("mod_gyro"))
	for f in 60:
		await get_tree().physics_frame
	check(robot.assembly.part_count == before + 1, "walking over a part attaches it (%d -> %d)" % [before, robot.assembly.part_count])
	check(robot.assembly.stability > gyro_stab, "attached gyro changed stats")

	# A chassis can't attach anywhere (core socket taken) -> salvaged.
	var scrap_before: int = rs.scrap
	rs.pickups.spawn_part(robot.global_position, part("chassis_tower"))
	for f in 60:
		await get_tree().physics_frame
	check(rs.scrap > scrap_before, "unattachable part is salvaged for scrap")
	check(rs.pickups.parts.is_empty(), "pickups consumed")
	scene.queue_free()
	await get_tree().process_frame


## Informational: average frame cost with a full horde (not a pass/fail check,
## machines vary).
func _bench_horde() -> void:
	print("horde benchmark")
	var scene: Node = load("res://scenes/levels/prototype_arena.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var em: EnemyManager = rs.enemies
	em.spawn_enabled = false
	var robot: RobotController = rs.robot
	robot.base_hp = 1.0e9
	robot.max_hp = 1.0e9
	robot.hp = 1.0e9
	var rng := RandomNumberGenerator.new()
	for i in em.max_enemies:
		var ang := rng.randf() * TAU
		em.spawn(0 if i % 10 else 2, Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(4.0, 30.0))
	var t0 := Time.get_ticks_usec()
	var frames := 120
	for f in frames:
		await get_tree().physics_frame
	var avg_ms := float(Time.get_ticks_usec() - t0) / frames / 1000.0
	print("    %d enemies: %.2f ms/frame average (headless, includes test overhead)" % [em.max_enemies, avg_ms])
	check(em.alive_count() > 0, "horde simulated without errors")
	scene.queue_free()
	await get_tree().process_frame
