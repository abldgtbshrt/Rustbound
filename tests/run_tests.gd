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
	print("horde backend: %s (set RUSTBOUND_HORDE_BACKEND=gdscript|native to force)" % EnemyManager.create_backend().backend_name())
	_test_horde_backends()
	_test_assembly_math()
	_test_socket_rules()
	_test_tip_ratio()
	_test_overload()
	await _test_arena_loop()
	await _test_part_pickup()
	await _test_heat()
	await _test_progression()
	await _test_main_scene_flow()
	_test_grids_rotation_frames()
	await _test_utility_parts()
	await _test_build_mode_rework()
	await _test_upgrades()
	await _test_energy_and_jets()
	_test_drive_modes()
	await _test_drive_feel()
	await _test_signature_parts()
	_test_pairs()
	_test_every_part_describes()
	await _test_hover()
	await _test_new_weapons()
	await _test_paths_and_effects()
	await _test_combo_and_list_fixes()
	_test_drive_balance()
	await _test_bench_pickups()
	await _test_chassis_select()
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


## Builds a robot part by part with raw single attaches (no automatic
## pairing), so physics tests control exactly what's where.
func make_assembly(chassis: String, layout: Array) -> RobotAssembly:
	var a := RobotAssembly.new()
	a.root_part_data = part("core_scrapper")
	var parts: Array[PartData] = [part(chassis)]
	var sockets: Array[StringName] = [&"chassis"]
	a.starting_parts = parts
	a.starting_sockets = sockets
	a.build(null)
	for e in layout:
		var sn := StringName(e[1])
		for inst in a.get_all_parts():
			var s := inst.data.get_socket(sn)
			if s != null and inst.is_socket_free(sn):
				a.attach(part(e[0]), inst, sn)
				break
	return a


## Main scene with the default chassis (Bulwark) picked.
func _open_main(pick: int = 0) -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	(main.get_node("ChassisSelect") as ChassisSelect).choose(pick)
	await get_tree().process_frame
	return main


func _test_assembly_math() -> void:
	print("assembly math")
	var a := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"], ["gun_nail", "top_1_0"]])
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
	var lop := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"], ["gun_rivet", "left_0_0"]])
	check(lop.center_of_mass.x < -0.05, "left-mounted cannon pulls CoM left (x=%.2f)" % lop.center_of_mass.x)

	var tower := make_assembly("chassis_tower", [["loco_biped_leg", "bottom_0_0"], ["loco_biped_leg", "bottom_1_0"], ["gun_nail", "top"]])
	check(tower.center_of_mass.y > a.center_of_mass.y + 0.2, "tower CoM is higher than box (%.2f vs %.2f)" % [tower.center_of_mass.y, a.center_of_mass.y])

	var ball := make_assembly("chassis_box", [])
	check(ball.locomotion.is_ball and not ball.locomotion.can_jump, "no locomotion falls back to ball mode")
	for x in [a, lop, tower, ball]:
		x.free()


func _test_socket_rules() -> void:
	print("socket rules")
	var a := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"]])
	var chassis := a.root.get_child_in(&"chassis")
	check(chassis != null, "chassis sits in core socket")
	check(a.attach(part("loco_wheel"), chassis, &"left_0_0") == null, "wheel rejected on a mount socket")
	check(a.attach(part("gun_rivet"), a.root.walk()[2], &"mount_shin") == null, "size-2 cannon rejected on size-1 shin mount")
	check(a.attach(part("gun_nail"), chassis, &"left_0_0") != null, "gun on a side cell")
	check(a.attach(part("gun_nail"), chassis, &"left_0_0") == null, "occupied socket is rejected")
	var leg := chassis.get_child_in(&"bottom_0_1")
	var skate := a.attach(part("loco_wheel"), leg, &"foot")
	check(skate != null, "a wheel fits a leg's foot")

	# Detach removes the subtree.
	var before := a.part_count
	var removed := a.detach(leg)
	check(removed.size() == 2 and a.part_count == before - 2, "detach removes leg + its wheel")

	# auto_attach fills sockets until none fit.
	var n := 0
	while a.auto_attach(part("mod_gyro")) != null:
		n += 1
	check(n == 2, "box chassis has 2 internal sockets (filled %d)" % n)
	check(a.stability > 1.1, "two gyros add stability (%.2f)" % a.stability)
	a.free()


func _test_tip_ratio() -> void:
	print("tipping")
	var box := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"], ["gun_nail", "top_1_0"]])
	var tower := make_assembly("chassis_tower", [["loco_biped_leg", "bottom_0_0"], ["loco_biped_leg", "bottom_1_0"], ["gun_nail", "top"]])
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
	var a := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"]])
	var cap := a.locomotion.mass_capacity
	check(a.total_mass > cap, "one leg can't carry a box chassis (%.1f > %.1f)" % [a.total_mass, cap])
	a.free()


func _test_arena_loop() -> void:
	print("arena loop (simulated)")
	var scene: Node = load("res://scenes/levels/prototype_arena.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var robot: RobotController = rs.robot
	check(robot != null and rs.enemies != null and rs.projectiles != null and rs.pickups != null, "systems registered with RunState")
	check(robot.assembly.part_count == 6, "robot spawned with starter build (front + rear nailgun)")
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
	check(rs.scrap > 0 or rs.pickups.scrap_count > 0, "kills drop scrap (%d banked, %d on the ground)" % [rs.scrap, rs.pickups.scrap_count])
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
	check(robot.assembly.part_count == before and rs.inventory.has(part("mod_gyro")), "overworld pickups go to the bench, not onto the robot")
	check(is_equal_approx(robot.assembly.stability, gyro_stab), "robot unchanged until you place it")

	# A chassis can't attach anywhere (core socket taken) -> goes to the bench.
	rs.pickups.spawn_part(robot.global_position, part("chassis_tower"))
	for f in 60:
		await get_tree().physics_frame
	check(rs.inventory.size() == 2 and rs.inventory[1].id == &"chassis_tower", "second pickup also benched")
	check(rs.pickups.parts.is_empty(), "pickups consumed")

	# Full bench -> salvaged for scrap.
	while rs.inventory.size() < rs.MAX_INVENTORY:
		rs.add_to_inventory(part("armor_plate"))
	var scrap_before: int = rs.scrap
	check(rs.acquire_part(part("chassis_tower")) == rs.Acquired.SALVAGED and rs.scrap > scrap_before, "full bench salvages for scrap")
	rs.inventory.clear()

	# Auto-install off -> bench even if a socket fits.
	rs.auto_install = false
	check(rs.acquire_part(part("mod_gyro")) == rs.Acquired.BENCH, "auto-install off sends parts to the bench")
	rs.auto_install = true
	scene.queue_free()
	await get_tree().process_frame


func _test_heat() -> void:
	print("heat")
	var scene: Node = load("res://scenes/levels/prototype_arena.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var robot: RobotController = rs.robot
	rs.enemies.spawn_enabled = false
	check(robot.heat == 0.0 and not robot.is_overheated, "starts cool")
	var cap := robot.get_heat_capacity()
	robot.add_heat(cap + 20.0)
	var hp_before := robot.hp
	for f in 30:
		await get_tree().physics_frame
	check(robot.is_overheated, "overheats above capacity")
	check(robot.hp < hp_before, "overheat deals damage (%.1f -> %.1f)" % [hp_before, robot.hp])
	robot.heat = cap * 0.5
	for f in 2:
		await get_tree().physics_frame
	check(not robot.is_overheated, "cools below the recovery threshold")

	var sink := robot.assembly.auto_attach(part("mod_heat_sink"))
	check(sink != null and robot.get_heat_capacity() > cap, "heat sink raises capacity (%.0f -> %.0f)" % [cap, robot.get_heat_capacity()])
	robot.assembly.auto_attach(part("mod_reactor")) # second internal slot? box has 2; sink took one
	check(robot.assembly.heat_passive > 0.0, "reactor adds passive heat")

	# Firing adds heat.
	robot.heat = 0.0
	rs.enemies.spawn(0, robot.global_position + Vector3(0, 0, -6))
	rs.enemies.set_hp(0, 1.0e6)
	var gun: NailgunBehavior = null
	for b in robot.assembly.get_all_behaviors():
		if b is NailgunBehavior and gun == null:
			gun = b # the front-facing one
	var shots0 := gun.shots_fired
	robot.base_heat_dissipation = 0.0
	robot.assembly.heat_passive = 0.0
	robot.assembly.heat_dissipation = 0.0
	for f in 60:
		await get_tree().physics_frame
	check(gun.shots_fired > shots0 and robot.heat > 0.0, "shots generate heat (%.1f after %d shots)" % [robot.heat, gun.shots_fired - shots0])

	# Airflow: moving cools faster than standing still.
	robot.base_heat_dissipation = 2.0
	robot.velocity = Vector3.ZERO
	var still := robot.get_heat_dissipation()
	robot.velocity = Vector3(7, 0, 0)
	var moving := robot.get_heat_dissipation()
	robot.velocity = Vector3.ZERO
	check(moving > still + 5.0, "moving at 7 m/s adds airflow cooling (%.1f -> %.1f /s)" % [still, moving])

	# Vent: dumps heat, damages nearby enemies only, then cools down.
	rs.enemies.clear_all()
	for f in 2:
		await get_tree().physics_frame
	var at := robot.global_position
	for off in [Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0.5), Vector3(0, 0, 2.0), Vector3(15, 0, 0)]:
		rs.enemies.spawn(2, at + off) # brutes: 70 hp, survive the blast
	for f in 1:
		await get_tree().physics_frame
	robot.heat = 5.0
	check(robot.vent() == -1, "can't vent with almost no heat")
	robot.heat = 80.0
	var hits := robot.vent()
	check(hits == 3, "vent hits the 3 close enemies, not the far one (hit %d)" % hits)
	check(robot.heat == 0.0 and not robot.is_overheated, "vent dumps all heat")
	var hurt := 0
	for i in rs.enemies.count:
		if rs.enemies.get_hp(i) < 70.0:
			hurt += 1
	check(hurt == 3, "blast damaged them (%d hurt)" % hurt)
	robot.heat = 80.0
	check(robot.vent() == -1, "vent is on cooldown")
	robot.vent_cooldown_left = 0.0
	check(robot.vent() >= 0, "vent ready again after cooldown")
	scene.queue_free()
	await get_tree().process_frame


func _test_progression() -> void:
	print("xp / level")
	rs.begin_new_run(1234)
	var need: int = rs.xp_to_next()
	check(need > 0 and rs.xp_required(2) > need, "xp curve increases (%d, %d)" % [need, rs.xp_required(2)])
	rs.add_xp(need - 1)
	check(rs.level == 1 and rs.pending_levelups == 0, "no level before threshold")
	rs.add_xp(1)
	check(rs.level == 2 and rs.pending_levelups == 1 and rs.xp == 0, "levels up at threshold")
	rs.add_xp(rs.xp_required(2) + rs.xp_required(3))
	check(rs.level == 4 and rs.pending_levelups == 3, "big xp grants several level-ups")
	var offers: Array = get_node("/root/LootTable").roll_choices(3)
	var distinct: bool = offers.size() == 3 and offers[0] != offers[1] and offers[1] != offers[2] and offers[0] != offers[2]
	check(distinct, "level-up offers 3 distinct parts")
	rs.end_run(false)


func _test_main_scene_flow() -> void:
	print("main scene: level-up, build mode, PS2 view")
	var main: Node = await _open_main()
	var container: SubViewportContainer = main.get_node("Screen")
	check(container.stretch_shrink >= 1 and main.get_node("Screen/GameViewport/PrototypeArena") != null, "arena renders inside the low-res viewport (shrink %d)" % container.stretch_shrink)
	var robot: RobotController = rs.robot
	rs.enemies.spawn_enabled = false
	rs.pickups.clear_all()

	# Level-up pauses and offers parts.
	var lvl: LevelUpScreen = main.get_node("LevelUpScreen")
	var parts_before := robot.assembly.part_count
	rs.add_xp(rs.xp_to_next())
	await get_tree().process_frame
	check(lvl.is_open() and get_tree().paused and lvl.offers.size() == 3, "level-up opens, pauses, offers 3")
	lvl.choose(0)
	check(not lvl.is_open() and not get_tree().paused, "choosing closes and unpauses")
	var upgraded := false
	for id in rs.part_tiers.keys():
		upgraded = upgraded or rs.part_tiers[id] > 1
	check(robot.assembly.part_count > parts_before or rs.inventory.size() == 1 or upgraded, "chosen card installed, benched or upgraded")
	# Repair option.
	robot.hp = 10.0
	rs.add_xp(rs.xp_to_next())
	await get_tree().process_frame
	lvl.choose(-1)
	check(robot.hp > 10.0 and not get_tree().paused, "skip repairs the robot")

	# Build mode.
	var bm: BuildMode = main.get_node("Screen/GameViewport/PrototypeArena/BuildMode")
	var panel: BuildPanel = main.get_node("BuildPanel")
	bm.enter()
	check(bm.active and get_tree().paused and panel.visible, "build mode pauses the world and shows the panel")
	rs.inventory.clear()
	rs.inventory_changed.emit()
	var leg: PartInstance = null
	for p in robot.assembly.get_all_parts():
		if p.data.id == &"loco_biped_leg" and p.parent_socket == &"bottom_0_1":
			leg = p
	var chassis := leg.parent_part
	var count := robot.assembly.part_count
	var loco_n := robot.assembly.locomotion.part_count
	bm.select_part(leg)
	check(bm.detach_selected(), "detach leg")
	check(rs.inventory.count(part("loco_biped_leg")) == 1 and robot.assembly.locomotion.part_count == loco_n - 2, "detaching one leg benches the pair (one bench item)")
	check(robot.assembly.part_count < count, "part count dropped")
	var idx: int = rs.inventory.find(part("loco_biped_leg"))
	bm.select_bench(idx)
	check(bm.get_compatible_sockets(part("loco_biped_leg")).size() >= 1, "free locomotion sockets highlighted")

	# Click the socket marker through the camera, like a player would.
	for f in 3:
		await get_tree().process_frame
	var cam := bm.get_viewport().get_camera_3d()
	var sock := chassis.data.get_socket(&"bottom_0_1")
	var world := chassis.global_transform * chassis.get_socket_transform(sock).origin
	bm.pick_at(cam.unproject_position(world))
	var reattached := chassis.get_child_in(&"bottom_0_1") != null
	check(reattached and robot.assembly.locomotion.part_count == loco_n, "clicking a socket places the whole pair")

	# Scrap from the bench.
	rs.add_to_inventory(part("armor_plate"))
	bm.select_bench(rs.inventory.size() - 1)
	var scrap0: int = rs.scrap
	check(bm.scrap_selected() and rs.scrap > scrap0, "scrap a bench part for scrap")
	check(not bm.scrap_selected(), "scrapping with nothing selected is a no-op")
	bm.select_part(robot.assembly.root)
	check(not bm.detach_selected(), "core can't be detached")

	bm.exit()
	check(not bm.active and not get_tree().paused and is_equal_approx(Engine.time_scale, 1.0) and not panel.visible, "exit unpauses and hides panel")
	main.queue_free()
	await get_tree().process_frame


func _facing_local(inst: PartInstance, a: RobotAssembly) -> Vector3:
	var b := a.global_basis.inverse() * inst.global_basis if a.is_inside_tree() else _local_basis(inst)
	var f := -b.z
	f.y = 0.0
	return f.normalized()


func _local_basis(inst: PartInstance) -> Basis:
	var b := inst.basis
	var p := inst.parent_part
	while p != null:
		b = p.basis * b
		p = p.parent_part
	return b


func _test_grids_rotation_frames() -> void:
	print("build rework: grids, rotation, mirror, frames, links, inertia")
	var a := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"]])
	var chassis := a.root.get_child_in(&"chassis")
	check(part("chassis_box").get_sockets().size() == 27, "box chassis expands to 27 hardpoint cells (%d)" % part("chassis_box").get_sockets().size())
	check(part("chassis_box").get_socket(&"top_2_1") != null, "grid cells are addressable (top_2_1)")

	# Rotation: left-face cells face outward (-X); +2 steps turns to face back (+Z).
	var gun := a.attach(part("gun_nail"), chassis, &"left_0_1", true, 0)
	var f0 := _facing_local(gun, a)
	check(f0.distance_to(Vector3(-1, 0, 0)) < 0.01, "side cells face outward by default %s" % f0)
	a.rotate_part(gun, 2)
	var f1 := _facing_local(gun, a)
	check(f1.distance_to(Vector3(0, 0, 1)) < 0.01 and gun.yaw_steps == 2, "rotate 90° -> faces backward %s" % f1)
	a.rotate_part(gun, -1)
	check(gun.yaw_steps == 1, "45° steps")

	# Mirror finds the opposite cell.
	var mirror := a.find_mirror_socket(part("gun_nail"), chassis, part("chassis_box").get_socket(&"left_0_0"))
	check(not mirror.is_empty() and (mirror[1] as SocketDef).marker_name == &"right_0_0", "mirror of left_0_0 is right_0_0")

	# Links: heat sink inside, next to a gun on top -> gun runs cooler.
	var top_gun := a.attach(part("gun_nail"), chassis, &"top_1_0")
	check(is_equal_approx(a.get_mod(top_gun, "heat_mult"), 1.0), "no link yet")
	a.attach(part("mod_heat_sink"), chassis, &"internal_0_0")
	check(is_equal_approx(a.get_mod(top_gun, "heat_mult"), 0.5), "linked heat sink halves gun heat (%.2f)" % a.get_mod(top_gun, "heat_mult"))
	check(is_equal_approx(a.get_mod(gun, "heat_mult"), 1.0), "gun on the far side isn't linked")

	# Frames: a strut with a leg under its end widens the stance; mass out
	# there raises inertia and slows turning.
	var turn_before := a.turn_factor
	var width_before := a.support_max.x - a.support_min.x
	var strut := a.attach(part("frame_strut"), chassis, &"right_0_1")
	var outrigger := a.attach(part("loco_biped_leg"), strut, &"under")
	check(outrigger != null, "leg attaches under a strut")
	check(a.support_max.x - a.support_min.x > width_before + 0.6, "outrigger widens the footprint (%.2f -> %.2f)" % [width_before, a.support_max.x - a.support_min.x])
	a.attach(part("gun_rivet"), strut, &"end")
	check(a.turn_factor < turn_before * 0.85, "mass on a strut slows turning (%.2f -> %.2f)" % [turn_before, a.turn_factor])
	var mast := a.attach(part("frame_mast"), chassis, &"top_0_1")
	check(mast != null and a.height > 2.3, "mast makes a tall robot (%.2f m)" % a.height)

	# Leg count: 4 legs vs 2.
	var two := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"]])
	var four := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_0"], ["loco_biped_leg", "bottom_1_0"], ["loco_biped_leg", "bottom_0_2"], ["loco_biped_leg", "bottom_1_2"]])
	check(four.locomotion.leg_count == 4, "counts legs")
	check(four.locomotion.jump_force < two.locomotion.jump_force, "more legs jump lower (%.1f vs %.1f)" % [four.locomotion.jump_force, two.locomotion.jump_force])
	check(four.stability > two.stability + 0.4, "more legs are steadier (+%.2f)" % (four.stability - two.stability))
	check(four.locomotion.mass_capacity > two.locomotion.mass_capacity, "more legs carry more")

	# Active gyro.
	var g := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"], ["mod_gyro", "internal_0_0"]])
	check(g.turn_factor > two.turn_factor * 1.15, "gyro speeds up turning (%.2f vs %.2f)" % [g.turn_factor, two.turn_factor])
	check(g.recover_time_mult < 0.5 and g.recover_pulse > 0.0, "gyro shortens knockdowns and adds a recovery pulse")
	for x in [a, two, four, g]:
		x.free()


func _arena() -> Node:
	var scene: Node = load("res://scenes/levels/prototype_arena.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	rs.enemies.spawn_enabled = false
	rs.pickups.clear_all()
	rs.enemies.clear_all()
	# Flat, empty ground so movement tests don't depend on random obstacles.
	for o in scene.get_node("Obstacles").get_children():
		o.queue_free()
	await get_tree().physics_frame
	return scene


func _chassis(robot: RobotController) -> PartInstance:
	return robot.assembly.root.get_child_in(&"chassis")


func _swap_locomotion(robot: RobotController, id: String) -> void:
	var c := _chassis(robot)
	for s in [&"bottom_0_1", &"bottom_1_1"]:
		var leg := c.get_child_in(s)
		if leg != null:
			robot.assembly.detach(leg)
		robot.assembly.attach(part(id), c, s)


func _test_utility_parts() -> void:
	print("utility parts: armor, stomp, ram, crush, gyro pulse, rotator, chain sword")
	var scene: Node = await _arena()
	var robot: RobotController = rs.robot
	var em: EnemyManager = rs.enemies
	var c := _chassis(robot)

	# Directional armor.
	var plate := robot.assembly.attach(part("armor_plate"), c, &"left_0_1")
	await get_tree().process_frame
	var facing := plate.get_facing_global()
	robot.hp = 100.0
	robot.take_damage(10.0, facing)
	var front_loss := 100.0 - robot.hp
	robot.hp = 100.0
	robot.take_damage(10.0, -facing)
	var back_loss := 100.0 - robot.hp
	check(front_loss < 5.0 and is_equal_approx(back_loss, 10.0), "armor blocks hits from the side it faces (%.1f vs %.1f)" % [front_loss, back_loss])
	robot.assembly.detach(plate)

	# Stomp: direct call, then a real jump.
	var at := robot.global_position
	em.spawn(2, at + Vector3(1.2, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hits := robot.stomp(8.0)
	check(hits == 1 and em.get_hp(0) < 70.0, "stomp damages nearby enemies (%.0f hp left)" % em.get_hp(0))
	var stomped := [0]
	var cb := func(_d: float, _h: int) -> void: stomped[0] += 1
	EventBus.robot_stomped.connect(cb)
	for f in 20:
		await get_tree().physics_frame # settle on the ground first
	check(robot.try_jump(), "robot can jump")
	for f in 90:
		await get_tree().physics_frame
	EventBus.robot_stomped.disconnect(cb)
	check(stomped[0] >= 1, "jumping and landing triggers a stomp")

	# Ram with wheels.
	em.clear_all()
	_swap_locomotion(robot, "loco_wheel")
	check(robot.assembly.locomotion.ram > 0.0, "wheels give ram power")
	var i := em.spawn(2, robot.global_position + Vector3(0.9, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	robot.velocity = Vector3(9, 0, 0)
	var hp0 := em.get_hp(i)
	robot.handle_enemy_contact(em, i, Vector3(0.9, 0, 0), 1.0 / 60.0)
	check(hp0 - em.get_hp(i) > 15.0, "ramming at speed hits hard (%.0f dmg)" % (hp0 - em.get_hp(i)))
	robot.velocity = Vector3.ZERO

	# Crush with treads: small enemies get ground up and don't bite.
	em.clear_all()
	_swap_locomotion(robot, "loco_tread")
	i = em.spawn(0, robot.global_position + Vector3(0.6, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	robot.hp = 100.0
	hp0 = em.get_hp(i)
	robot.handle_enemy_contact(em, i, Vector3(0.6, 0, 0), 0.1)
	check(em.get_hp(i) < hp0 and robot.hp == 100.0, "treads crush small enemies without taking contact damage")
	_swap_locomotion(robot, "loco_biped_leg")

	# Gyro recovery pulse.
	em.clear_all()
	robot.assembly.attach(part("mod_gyro"), c, &"internal_0_0")
	i = em.spawn(2, robot.global_position + Vector3(2.0, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	hp0 = em.get_hp(i)
	robot._fall_over(Vector3.RIGHT)
	var t0 := 0
	while robot.is_knocked_down and t0 < 200:
		await get_tree().physics_frame
		t0 += 1
	check(t0 < 60, "gyro gets the robot up fast (%d frames)" % t0)
	check(em.count > 0 and em.get_hp(0) < hp0, "recovery shockwave hits nearby enemies")

	# Rotator spins its guns.
	em.clear_all()
	var rot := robot.assembly.attach(part("util_rotator"), c, &"top_0_0")
	var spun := robot.assembly.attach(part("gun_nail"), rot, &"platter")
	await get_tree().physics_frame
	var fa := spun.get_facing_global()
	for f in 30:
		await get_tree().physics_frame
	check(spun.get_facing_global().angle_to(fa) > deg_to_rad(20.0), "rotator turns the gun on it")

	# Chain sword: hits what's in front of it, not behind.
	robot.assembly.detach(rot)
	for p in robot.assembly.get_all_parts():
		if p.data.id == &"gun_nail" and is_instance_valid(p) and p.parent_part != null:
			robot.assembly.detach(p)
	em.clear_all()
	var sword := robot.assembly.attach(part("melee_chain_sword"), c, &"right_0_1")
	await get_tree().physics_frame
	var sf := sword.get_facing_global()
	var front := em.spawn(2, sword.global_position + sf * 1.6)
	var back := em.spawn(2, sword.global_position - sf * 2.2)
	for f in 3:
		await get_tree().physics_frame
	var bh: ChainSwordBehavior = sword.behaviors[0]
	check(bh.swings >= 1 and em.get_hp(front) < 70.0, "chain sword hits the enemy in front (%.0f hp)" % em.get_hp(front))
	check(is_equal_approx(em.get_hp(back), 70.0), "and not the one behind it")
	scene.queue_free()
	await get_tree().process_frame


func _test_build_mode_rework() -> void:
	print("build mode: rotate, mirror, ghost")
	var main: Node = await _open_main()
	rs.enemies.spawn_enabled = false
	var robot: RobotController = rs.robot
	var bm: BuildMode = main.get_node("Screen/GameViewport/PrototypeArena/BuildMode")
	var c := _chassis(robot)
	rs.inventory.clear()
	rs.add_to_inventory(part("gun_nail"))
	rs.add_to_inventory(part("gun_nail"))
	bm.enter()
	bm.select_bench(0)
	bm.set_mirror(true)
	bm.rotate_selection(2)
	check(bm.placement_yaw == 2, "Q/E rotates the pending placement")
	for f in 3:
		await get_tree().process_frame
	var cam := bm.get_viewport().get_camera_3d()
	var s := c.data.get_socket(&"left_0_1")
	var screen := cam.unproject_position(c.global_transform * c.get_socket_transform(s).origin)
	bm.set_hover_at(screen)
	check(not bm.hovered.is_empty() and bm._ghost != null, "hovering a socket shows a ghost")
	bm.pick_at(screen)
	var l := c.get_child_in(&"left_0_1")
	var r := c.get_child_in(&"right_0_1")
	check(l != null and r != null and rs.inventory.is_empty(), "mirror placement uses both bench copies")
	check(l != null and r != null and l.yaw_steps == 2 and r.yaw_steps == 6, "mirrored copy gets mirrored rotation (%d / %d)" % [l.yaw_steps if l else -1, r.yaw_steps if r else -1])
	bm.select_part(l)
	bm.rotate_selection(1)
	check(l.yaw_steps == 3 and r.yaw_steps == 5, "rotating a part with mirror on turns its twin too")
	bm.exit()
	main.queue_free()
	await get_tree().process_frame


func _test_upgrades() -> void:
	print("upgrades: tiers, offers, duplicate merge, strip to core")
	var main: Node = await _open_main()
	rs.enemies.spawn_enabled = false
	rs.pickups.clear_all()
	var robot: RobotController = rs.robot
	var nail := part("gun_nail")
	var gun: NailgunBehavior = null
	for b in robot.assembly.get_all_behaviors():
		if b is NailgunBehavior and gun == null:
			gun = b
	check(is_equal_approx(float(gun.param("damage", 0.0)), 9.0), "Mk I nailgun: 9 dmg")
	check(rs.upgrade_part(nail) and rs.upgrade_part(nail), "upgrade twice")
	check(rs.get_tier(&"gun_nail") == 3 and is_equal_approx(float(gun.param("damage", 0.0)), 13.5), "Mk III nailgun: 13.5 dmg (%.1f)" % float(gun.param("damage", 0.0)))
	var hp_before := robot.assembly.max_hp
	rs.upgrade_part(part("chassis_box"))
	check(robot.assembly.max_hp > hp_before, "chassis upgrade raises HP (%.0f -> %.0f)" % [hp_before, robot.assembly.max_hp])
	rs.upgrade_part(nail)
	rs.upgrade_part(nail)
	check(rs.get_tier(&"gun_nail") == 5 and not rs.upgrade_part(nail), "Mk V is the cap")

	# Offers: early levels lean on upgrades, later levels on new parts.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var early_new := 0
	var late_new := 0
	var total := 0
	for k in 60:
		for o in UpgradeOffers.roll(3, 2, rng):
			total += 1
			early_new += 1 if o["kind"] == "new" else 0
		for o in UpgradeOffers.roll(3, 10, rng):
			late_new += 1 if o["kind"] == "new" else 0
	check(float(early_new) / float(total) < 0.3, "level 2 offers are mostly upgrades (%d%% new)" % int(100.0 * early_new / total))
	check(late_new > early_new * 2, "level 10 offers more new parts (%d vs %d)" % [late_new, early_new])

	# Walking over a part you already own puts a spare on the bench; melt it
	# there to upgrade.
	var legs_before := robot.assembly.part_count
	rs.inventory.clear()
	rs.pickups.spawn_part(robot.global_position + Vector3(0.4, 0, 0), part("loco_biped_leg"))
	for f in 45:
		await get_tree().physics_frame
	check(rs.inventory.count(part("loco_biped_leg")) == 1 and rs.get_tier(&"loco_biped_leg") == 1 and robot.assembly.part_count == legs_before, "duplicate leg pickup lands on the bench")
	var li: int = rs.inventory.find(part("loco_biped_leg"))
	check(rs.melt_into_upgrade(li) and rs.get_tier(&"loco_biped_leg") == 2 and not rs.inventory.has(part("loco_biped_leg")), "melting the spare upgrades legs to Mk II")

	# Strip to core and rebuild.
	var bm: BuildMode = main.get_node("Screen/GameViewport/PrototypeArena/BuildMode")
	rs.inventory.clear()
	bm.enter()
	var n := bm.strip_all()
	check(robot.assembly.part_count == 2 and rs.inventory.size() == n and n >= 3, "strip leaves core + chassis, benches the rest (%d items, legs as one pair)" % n)
	check(not rs.inventory.has(part("chassis_box")), "the chassis stays on: it's locked for the run")
	bm.select_part(_chassis(robot))
	check(not bm.detach_selected() and _chassis(robot) != null, "the chassis can't be detached")
	bm.select_bench(rs.inventory.find(part("loco_biped_leg")))
	check(bm.attach_selected(_chassis(robot), &"bottom_0_1"), "rebuild: legs back on")
	bm.exit()
	main.queue_free()
	await get_tree().process_frame


func _test_energy_and_jets() -> void:
	print("energy pool and jets")
	var scene: Node = await _arena()
	var robot: RobotController = rs.robot
	var c := _chassis(robot)
	for f in 20:
		await get_tree().physics_frame
	check(is_equal_approx(robot.energy, robot.get_energy_capacity()), "battery starts full")
	check(robot.get_overcharge_mult() > 1.1, "spare power overcharges weapons (x%.2f)" % robot.get_overcharge_mult())
	check(RobotAssembly.can_fit(part("mod_reactor"), c.data.get_socket(&"left_0_0")), "reactors fit mount sockets now")
	check(RobotAssembly.can_fit(part("mod_battery"), c.data.get_socket(&"internal_0_0")), "batteries fit inside")

	# Overdraw: three rivet cannons (4 power each) drain the battery, then brown out.
	var rivets: Array = []
	for cell in [&"left_0_0", &"right_0_0", &"top_0_0"]:
		rivets.append(robot.assembly.attach(part("gun_rivet"), c, cell))
	check(robot.assembly.is_browned_out(), "drawing more than generated")
	var speed_ok := robot.get_top_speed()
	var e0 := robot.energy
	for f in 30:
		await get_tree().physics_frame
	check(robot.energy < e0 and not robot.browned_out, "the battery covers the deficit for a while")
	robot.energy = 0.5
	for f in 15:
		await get_tree().physics_frame
	check(robot.browned_out and robot.get_top_speed() < speed_ok, "empty battery = brownout, robot slows (%.1f -> %.1f)" % [speed_ok, robot.get_top_speed()])
	for r in rivets:
		robot.assembly.detach(r)
	for f in 30:
		await get_tree().physics_frame
	check(not robot.browned_out, "power restored once draw is back under generation")

	# Jets: hold jump to fly higher than a plain jump.
	robot.energy = robot.get_energy_capacity()
	for f in 10:
		await get_tree().physics_frame
	robot.try_jump()
	var plain_peak := 0.0
	for f in 90:
		await get_tree().physics_frame
		plain_peak = maxf(plain_peak, robot.global_position.y)
	robot.assembly.attach(part("util_jet"), c, &"back_0_0")
	robot.assembly.attach(part("util_jet"), c, &"back_1_0")
	check(robot.assembly.jet_thrust > 0.0 and robot.assembly.jet_parts.size() == 2, "two jets attached")
	robot.energy = robot.get_energy_capacity()
	var e_before := robot.energy
	robot.try_jump()
	Input.action_press("jump")
	var jet_peak := 0.0
	var saw_jet := false
	for f in 90:
		await get_tree().physics_frame
		jet_peak = maxf(jet_peak, robot.global_position.y)
		saw_jet = saw_jet or robot.is_jetting
	Input.action_release("jump")
	check(saw_jet and jet_peak > plain_peak + 1.0, "jets boost the jump (%.1f m vs %.1f m)" % [jet_peak, plain_peak])
	check(robot.energy < e_before, "jets burn battery")

	# No legs: jets alone lift off.
	for f in 60:
		await get_tree().physics_frame
	for s in [&"bottom_0_1", &"bottom_1_1"]:
		robot.assembly.detach(c.get_child_in(s))
	robot.energy = robot.get_energy_capacity()
	for f in 10:
		await get_tree().physics_frame
	Input.action_press("jump")
	var lift_peak := 0.0
	for f in 40:
		await get_tree().physics_frame
		lift_peak = maxf(lift_peak, robot.global_position.y)
	Input.action_release("jump")
	check(lift_peak > 0.8, "legless robot takes off on jets (%.1f m)" % lift_peak)
	scene.queue_free()
	await get_tree().process_frame


func _test_drive_modes() -> void:
	print("drive modes and hybrids")
	var walker := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"]])
	check(walker.locomotion.mode == LocomotionProfile.Mode.WALKER and walker.locomotion.can_jump, "legs = Walker (jumps)")
	var rover := make_assembly("chassis_box", [["loco_wheel", "bottom_0_0"], ["loco_wheel", "bottom_1_0"], ["loco_wheel", "bottom_0_2"], ["loco_wheel", "bottom_1_2"]])
	check(rover.locomotion.mode == LocomotionProfile.Mode.ROVER and not rover.locomotion.can_jump and rover.locomotion.ram > 0.0, "wheels = Rover (no jump, rams)")
	var tank := make_assembly("chassis_box", [["loco_tread", "bottom_0_1"], ["loco_tread", "bottom_1_1"]])
	check(tank.locomotion.mode == LocomotionProfile.Mode.TANK and tank.locomotion.anchored and tank.locomotion.crush > 0.0, "treads = Tank (anchored, crushes)")
	check(rover.locomotion.top_speed > walker.locomotion.top_speed and tank.locomotion.top_speed < walker.locomotion.top_speed, "rover fastest, tank slowest")

	# Skates: wheels on both legs' feet.
	var sk := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"]])
	var c := sk.root.get_child_in(&"chassis")
	for cell in [&"bottom_0_1", &"bottom_1_1"]:
		sk.attach(part("loco_wheel"), c.get_child_in(cell), &"foot")
	check(sk.locomotion.mode == LocomotionProfile.Mode.SKATER, "wheels on leg feet = Skater")
	check(sk.locomotion.can_jump and sk.locomotion.ram > 0.0 and sk.locomotion.stomp == 0.0, "skater jumps and rams, but can't stomp")
	check(sk.locomotion.top_speed > walker.locomotion.top_speed * 1.4 and sk.locomotion.coast_drag < 1.0, "skater is fast and glides")

	var st := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"]])
	c = st.root.get_child_in(&"chassis")
	for cell in [&"bottom_0_1", &"bottom_1_1"]:
		st.attach(part("loco_tread"), c.get_child_in(cell), &"foot")
	check(st.locomotion.mode == LocomotionProfile.Mode.STOMPER and st.locomotion.anchored, "treads on leg feet = Stomper")
	check(st.locomotion.stomp > walker.locomotion.stomp and st.locomotion.crush > 0.0, "stomper stomps harder and crushes")

	# Mixing drive types on the frame: majority drives, the rest idle.
	var mix := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"], ["loco_wheel", "bottom_0_0"]])
	check(mix.locomotion.mode == LocomotionProfile.Mode.WALKER and mix.locomotion.idle_parts.size() == 1, "legs + a frame wheel: wheel sits idle")
	check(mix.locomotion.conflict.contains("Scrap Wheel"), "conflict is reported (%s)" % mix.locomotion.conflict)
	check(is_equal_approx(mix.locomotion.top_speed, walker.locomotion.top_speed), "idle wheel doesn't change walking speed")
	for x in [walker, rover, tank, sk, st, mix]:
		x.free()


func _set_drive(robot: RobotController, wheels_on_feet: bool, frame_kind: String) -> void:
	var c := _chassis(robot)
	for cell in [&"bottom_0_1", &"bottom_1_1"]:
		var p := c.get_child_in(cell)
		if p != null:
			robot.assembly.detach(p)
		var inst := robot.assembly.attach(part(frame_kind), c, cell)
		if wheels_on_feet:
			robot.assembly.attach(part("loco_wheel"), inst, &"foot")


## Drives the robot forward then releases; returns [speed at release,
## distance coasted after release, sideways speed measured while turning].
func _drive_sample(robot: RobotController) -> Array:
	robot.global_position = Vector3(0, 0.1, 25.0) # room to run toward -Z
	robot.velocity = Vector3.ZERO
	robot.rotation.y = 0.0
	for f in 10:
		await get_tree().physics_frame
	Input.action_press("move_forward")
	for f in 120:
		await get_tree().physics_frame
	var v0 := Vector2(robot.velocity.x, robot.velocity.z).length()
	Input.action_release("move_forward")
	var p0 := robot.global_position
	for f in 60:
		await get_tree().physics_frame
	var coast := robot.global_position.distance_to(p0)
	return [v0, coast]


func _test_drive_feel() -> void:
	print("drive feel (simulated)")
	var scene: Node = await _arena()
	var robot: RobotController = rs.robot
	robot.base_hp = 1.0e6
	robot.hp = 1.0e6
	for b in robot.assembly.get_all_parts():
		if b.data.id == &"gun_nail":
			robot.assembly.detach(b)
	var walk: Array = await _drive_sample(robot)
	_set_drive(robot, true, "loco_biped_leg")
	check(robot.assembly.locomotion.mode == LocomotionProfile.Mode.SKATER, "robot is skating")
	var skate: Array = await _drive_sample(robot)
	_set_drive(robot, false, "loco_wheel")
	var rove: Array = await _drive_sample(robot)
	print("    walker v=%.1f coast=%.1f | skater v=%.1f coast=%.1f | rover v=%.1f coast=%.1f" % [walk[0], walk[1], skate[0], skate[1], rove[0], rove[1]])
	check(walk[1] < 2.0, "walker stops almost dead when you let go (%.1f m)" % walk[1])
	check(skate[1] > walk[1] * 4.0 and skate[1] > 3.0, "skater glides on (%.1f m)" % skate[1])
	check(rove[1] > 3.0, "rover coasts on momentum (%.1f m)" % rove[1])
	check(skate[0] > walk[0], "skater is faster than walking (%.1f vs %.1f)" % [skate[0], walk[0]])

	# Tank pivots in place before moving.
	_set_drive(robot, false, "loco_tread")
	robot.velocity = Vector3.ZERO
	robot.rotation.y = 0.0
	for f in 10:
		await get_tree().physics_frame
	var p0 := robot.global_position
	Input.action_press("move_back") # 180° behind it
	for f in 8:
		await get_tree().physics_frame
	var moved_early := robot.global_position.distance_to(p0)
	for f in 150:
		await get_tree().physics_frame
	Input.action_release("move_back")
	check(moved_early < 0.1, "tank turns in place first (moved %.2f m)" % moved_early)
	check(robot.global_position.distance_to(p0) > 2.0, "then drives off")
	scene.queue_free()
	await get_tree().process_frame


func _test_signature_parts() -> void:
	print("signature parts")
	var scene: Node = await _arena()
	var robot: RobotController = rs.robot
	var em: EnemyManager = rs.enemies
	var c := _chassis(robot)
	for p in robot.assembly.get_all_parts():
		if p.data.id == &"gun_nail" and p.parent_part != null:
			robot.assembly.detach(p)

	# Uniques leave the pool once owned.
	var lt := get_node("/root/LootTable")
	rs.acquire_part(part("sig_tesla_coil"), false)
	var seen := false
	for k in 300:
		seen = seen or lt.roll_part() == part("sig_tesla_coil")
	check(not seen, "a unique part never drops again once you have it")
	check(PartData.rarity_name(part("sig_shield_projector").rarity) == "Legendary", "shield projector is legendary")

	# Tesla: chains through a line of enemies.
	var at := robot.global_position
	for k in 4:
		em.spawn(2, at + Vector3(3.0 + 2.5 * k, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var tesla := robot.assembly.attach(part("sig_tesla_coil"), c, &"top_1_0")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hurt := 0
	for i in em.count:
		hurt += 1 if em.get_hp(i) < 70.0 else 0
	check(hurt >= 3, "tesla arcs through %d enemies" % hurt)
	robot.assembly.detach(tesla)
	em.clear_all()

	# Shield: hits from its side cost battery, not HP.
	var sh := robot.assembly.attach(part("sig_shield_projector"), c, &"left_0_1")
	await get_tree().physics_frame
	robot.hp = 100.0
	robot.energy = robot.get_energy_capacity()
	var e0 := robot.energy
	robot.take_damage(20.0, sh.get_facing_global())
	check(robot.hp == 100.0 and robot.energy < e0, "shield turns damage into battery drain")
	robot.take_damage(20.0, -sh.get_facing_global())
	check(robot.hp < 100.0, "hits from behind still land")
	robot.energy = 0.0
	robot.hp = 100.0
	robot.take_damage(20.0, sh.get_facing_global())
	check(robot.hp < 100.0, "no battery, no shield")
	robot.assembly.detach(sh)

	# Mortar lobs into a crowd at range.
	robot.energy = robot.get_energy_capacity()
	var mortar := robot.assembly.attach(part("sig_mortar"), c, &"top_1_1")
	var fwd := mortar.get_facing_global()
	for k in 5:
		em.spawn(2, robot.global_position + fwd * 12.0 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
	var mb: MortarBehavior = mortar.behaviors[0]
	for f in 90:
		await get_tree().physics_frame
	hurt = 0
	for i in em.count:
		hurt += 1 if em.get_hp(i) < 70.0 else 0
	check(mb.shots >= 1 and hurt >= 2, "mortar shell hits a cluster (%d hurt)" % hurt)
	robot.assembly.detach(mortar)
	em.clear_all()

	# Magnet pulls a small enemy in.
	var mag := robot.assembly.attach(part("sig_magnet_arm"), c, &"right_0_1")
	var mf := mag.get_facing_global()
	var i := em.spawn(1, mag.global_position + mf * 7.0) # dart, small
	await get_tree().physics_frame
	em.enemy_types[1].speed = 0.0 # isolate the pull
	var d0 := em.get_pos(i).distance_to(mag.global_position)
	for f in 30:
		await get_tree().physics_frame
	check(em.get_pos(i).distance_to(mag.global_position) < d0 - 1.5, "magnet arm drags small enemies in")
	em.enemy_types[1].speed = 6.0
	robot.assembly.detach(mag)
	em.clear_all()

	# Scrap Maw: heals on scrap.
	robot.assembly.attach(part("sig_scrap_maw"), c, &"right_0_1")
	robot.hp = 50.0
	EventBus.scrap_collected.emit(10)
	check(robot.hp > 50.0, "scrap maw repairs from scrap (%.0f)" % robot.hp)
	scene.queue_free()
	await get_tree().process_frame


## Every part's description (level-up cards, build panel) must build without
## errors, so new enum values can't crash the UI.
func _test_every_part_describes() -> void:
	print("part descriptions")
	var lt := get_node("/root/LootTable")
	var bad: PackedStringArray = []
	for p in lt.parts:
		var lines: Variant = UiStyle.describe_part(p)
		if not (lines is PackedStringArray) or (lines as PackedStringArray).size() < 2:
			bad.append(String(p.id))
	check(lt.parts.size() >= 25 and bad.is_empty(), "all %d parts describe cleanly %s" % [lt.parts.size(), bad])
	for d in PartData.Drive.values():
		check(UiStyle.drive_text(d) != "", "drive text for %s" % PartData.Drive.keys()[d])


func _test_pairs() -> void:
	print("drivetrain pairs")
	var a := make_assembly("chassis_box", [])
	var left := a.auto_attach(part("loco_biped_leg"))
	check(left != null and a.locomotion.part_count == 2, "one leg item places a mirrored pair (%d)" % a.locomotion.part_count)
	var twin := a.find_twin(left)
	check(twin != null and twin != left, "the pair are mirror twins")
	a.auto_attach(part("loco_biped_leg"))
	check(a.locomotion.part_count == 4 and a.locomotion.leg_count == 4, "a second pair makes four legs")
	var removed := a.detach_with_twin(left)
	check(removed.size() == 2 and a.locomotion.part_count == 2, "detaching one removes its twin")
	var items := RobotAssembly.to_bench_items(removed)
	check(items.size() == 1, "a detached pair is one bench item")
	var mixed: Array[PartData] = [part("loco_wheel"), part("gun_nail"), part("loco_wheel"), part("loco_wheel")]
	check(RobotAssembly.to_bench_items(mixed).size() == 3, "odd leftovers round up to a pair (3 wheels -> 2 items + nail)")
	a.free()


func _test_hover() -> void:
	print("hover drive")
	var h := make_assembly("chassis_box", [["loco_hover_pad", "bottom_0_1"], ["loco_hover_pad", "bottom_1_1"]])
	check(h.locomotion.mode == LocomotionProfile.Mode.HOVER and not h.locomotion.can_jump, "hover pads = Hover mode")
	var min_y := INF
	for e in h._walk_local():
		min_y = minf(min_y, h._part_bounds(e[0], e[1]).position.y)
	check(absf(min_y - 0.5) < 0.05, "robot floats 0.5 m up (lowest point %.2f)" % min_y)
	check(h.power_draw >= 4.0, "pads draw power (%.0f)" % h.power_draw)
	h.free()

	var scene: Node = await _arena()
	var robot: RobotController = rs.robot
	robot.base_hp = 1.0e6
	robot.hp = 1.0e6
	for p in robot.assembly.get_all_parts():
		if p.data.id == &"gun_nail" and is_instance_valid(p) and p.parent_part != null:
			robot.assembly.detach(p)
	var c := _chassis(robot)
	robot.assembly.detach_with_twin(c.get_child_in(&"bottom_0_1"))
	robot.assembly.attach_pair(part("loco_hover_pad"), c, &"bottom_0_1")
	check(robot.assembly.locomotion.mode == LocomotionProfile.Mode.HOVER, "robot hovering")
	robot.global_position = Vector3(0, 0.1, 20)
	robot.rotation.y = 0.0
	var e: int = rs.enemies.spawn(2, robot.global_position + Vector3(8, 0, 0))
	rs.enemies.enemy_types[2].speed = 0.0
	Input.action_press("move_forward")
	for f in 90:
		await get_tree().physics_frame
		rs.enemies.set_pos(e, robot.global_position + Vector3(8, 0.8, 0)) # keep it beside us
	Input.action_release("move_forward")
	rs.enemies.enemy_types[2].speed = 2.2
	var facing := -robot.global_basis.z
	var vel := Vector3(robot.velocity.x, 0, robot.velocity.z).normalized()
	check(facing.dot(Vector3.RIGHT) > 0.8, "hover faces the enemy beside it (%s)" % facing)
	check(vel.dot(Vector3.FORWARD) > 0.8, "while strafing forward (%s)" % vel)
	scene.queue_free()
	await get_tree().process_frame


func _hurt_count(em: EnemyManager, full: float = 70.0) -> int:
	var n := 0
	for i in em.count:
		n += 1 if em.get_hp(i) < full - 0.01 else 0
	return n


func _test_new_weapons() -> void:
	print("new weapons: flamethrower, laser, boomerang, drone bay")
	var scene: Node = await _arena()
	var robot: RobotController = rs.robot
	var em: EnemyManager = rs.enemies
	var c := _chassis(robot)
	robot.base_hp = 1.0e6
	robot.hp = 1.0e6
	for p in robot.assembly.get_all_parts():
		if p.data.id == &"gun_nail" and is_instance_valid(p) and p.parent_part != null:
			robot.assembly.detach(p)
	em.enemy_types[2].speed = 0.0 # stationary targets

	# Flamethrower: cone in front, nothing behind, bursts on and off.
	var fl := robot.assembly.attach(part("gun_flamethrower"), c, &"front_0_0")
	await get_tree().physics_frame
	var ff := fl.get_facing_global()
	var front := em.spawn(2, fl.global_position + ff * 3.0)
	var back := em.spawn(2, fl.global_position - ff * 3.0)
	var fb: FlamethrowerBehavior = fl.behaviors[0]
	var saw_on := false
	var saw_off_after := false
	for f in 150:
		await get_tree().physics_frame
		saw_on = saw_on or fb.is_firing()
		saw_off_after = saw_off_after or (saw_on and not fb.is_firing())
	check(em.get_hp(front) < 70.0 and is_equal_approx(em.get_hp(back), 70.0), "flame cone burns what's in front only (%.0f / %.0f)" % [em.get_hp(front), em.get_hp(back)])
	check(saw_on and saw_off_after, "flamethrower fires in bursts")
	# Cone mesh: narrow tip (+Y of the cylinder) at the nozzle, wide end out.
	var cx: Transform3D = fb._cone.transform
	var tip := cx * Vector3(0, 0.5, 0)
	var mouth := cx * Vector3(0, -0.5, 0)
	check(absf(tip.z) < 0.05 and mouth.z < -3.0, "flame cone starts narrow at the nozzle and widens outward (tip z %.2f, mouth z %.2f)" % [tip.z, mouth.z])
	robot.assembly.detach(fl)
	em.clear_all()

	# Laser: one beam through a whole line.
	var lz := robot.assembly.attach(part("gun_laser"), c, &"top_1_0")
	await get_tree().physics_frame
	var lf := lz.get_facing_global()
	for d in [5.0, 9.0, 13.0]:
		em.spawn(2, lz.global_position + lf * d)
	var lb: LaserBehavior = lz.behaviors[0]
	for f in 170:
		await get_tree().physics_frame
	check(lb.shots >= 1 and lb.last_hits >= 3, "laser hits every enemy in the line (%d)" % lb.last_hits)
	robot.assembly.detach(lz)
	em.clear_all()

	# Boomerang: out and back, hitting on the way.
	var bm := robot.assembly.attach(part("gun_boomerang"), c, &"front_0_0")
	await get_tree().physics_frame
	var bf := bm.get_facing_global()
	em.spawn(2, bm.global_position + bf * 6.0)
	var bb: BoomerangBehavior = bm.behaviors[0]
	var flew := false
	for f in 60:
		await get_tree().physics_frame
		flew = flew or bb.in_flight() > 0
	for f in 60:
		await get_tree().physics_frame
	check(flew and bb.throws >= 1 and bb.hits >= 1, "boomerang thrown and hits (%d hits)" % bb.hits)
	robot.assembly.detach(bm)
	em.clear_all()

	# Drone bay: an orbiting bot that shoots.
	var bay := robot.assembly.attach(part("gun_drone_bay"), c, &"top_0_0")
	em.spawn(2, robot.global_position + Vector3(6, 0, 0))
	var db: DroneBayBehavior = bay.behaviors[0]
	for f in 90:
		await get_tree().physics_frame
	check(db.drones.size() == 1 and db.shots >= 2 and _hurt_count(em) >= 1, "drone follows and shoots (%d shots)" % db.shots)
	var dpos := db.drones[0].global_position
	check(dpos.distance_to(robot.global_position) < 4.0 and dpos.y > 1.0, "drone orbits above the robot")
	em.enemy_types[2].speed = 2.2
	scene.queue_free()
	await get_tree().process_frame


func _test_paths_and_effects() -> void:
	print("upgrade paths, status effects, trails")
	var scene: Node = await _arena()
	var robot: RobotController = rs.robot
	var em: EnemyManager = rs.enemies
	var c := _chassis(robot)
	robot.base_hp = 1.0e6
	robot.hp = 1.0e6
	var nail := part("gun_nail")
	check(not rs.needs_path_choice(nail), "no fork at Mk I")
	rs.upgrade_part(nail)
	check(rs.needs_path_choice(nail), "Mk II -> III is a fork")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var paired_cards := false
	for k in 40:
		var offers := UpgradeOffers.roll(3, 2, rng)
		var n := 0
		for o in offers:
			if o["kind"] == "path" and o["part"] == nail:
				n += 1
		if n > 0:
			paired_cards = paired_cards or n == 2
			if n != 2:
				check(false, "both nailgun paths offered together (got %d)" % n)
	check(paired_cards, "path cards show up as a pair")
	check(rs.choose_path(nail, &"shrapnel") and rs.get_tier(&"gun_nail") == 3, "choosing a path upgrades to Mk III")
	check(not rs.needs_path_choice(nail), "fork resolved")
	var gun: NailgunBehavior = null
	for b in robot.assembly.get_all_behaviors():
		if b is NailgunBehavior and gun == null:
			gun = b
	check(is_equal_approx(float(gun.param("splash_radius", 0.0)), 1.5) and gun.hit_fx().has("splash_radius"), "path params reach the weapon")

	# Splash: one nail into a tight cluster hurts several.
	em.enemy_types[2].speed = 0.0
	var at := robot.global_position + Vector3(0, 0, -6)
	for off in [Vector3.ZERO, Vector3(0.9, 0, 0), Vector3(-0.9, 0, 0)]:
		em.spawn(2, at + off)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for b in robot.assembly.get_all_behaviors():
		if b is NailgunBehavior:
			robot.assembly.detach(b.part)
	rs.projectiles.fire(at + Vector3(0, 0.5, 2.0), Vector3(0, 0, -20), 10.0, 1.0, 0.25, 0, 0.0, Color.WHITE, {"splash_radius": 1.5, "splash_frac": 0.4})
	for f in 10:
		await get_tree().physics_frame
	check(_hurt_count(em) == 3, "shrapnel splash hits the cluster (%d)" % _hurt_count(em))
	em.clear_all()

	# Slow and burn.
	var i := em.spawn(0, robot.global_position + Vector3(15, 0, 0))
	var j := em.spawn(0, robot.global_position + Vector3(-15, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	em.apply_slow(i, 0.3, 5.0)
	var pi0 := em.get_pos(i)
	var pj0 := em.get_pos(j)
	for f in 30:
		await get_tree().physics_frame
	var di := em.get_pos(i).distance_to(pi0)
	var dj := em.get_pos(j).distance_to(pj0)
	check(di < dj * 0.5, "slowed enemy moves less (%.2f vs %.2f m)" % [di, dj])
	var hp0 := em.get_hp(j)
	em.apply_burn(j, 10.0, 2.0)
	for f in 30:
		await get_tree().physics_frame
	check(em.get_hp(j) < hp0 - 3.0 and em.get_flash(j) <= 0.0, "burning ticks damage without hit flashes")
	em.clear_all()

	# Trails: Scorched Steps (fire) on the legs.
	var legs := part("loco_biped_leg")
	rs.upgrade_part(legs)
	check(rs.choose_path(legs, &"fire"), "legs take the fire-trail path")
	em.enemy_types[2].speed = 2.2
	robot.global_position = Vector3(0, 0.1, 20)
	Input.action_press("move_forward")
	for f in 90:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var hz: HazardField = rs.hazards as HazardField
	check(hz.count >= 3, "walking leaves a fire trail (%d patches)" % hz.count)
	var k := em.spawn(2, hz.pos[0])
	em.enemy_types[2].speed = 0.0
	for f in 20:
		await get_tree().physics_frame
	check(em.get_burn_t(k) > 0.0 or em.get_hp(k) < 70.0, "enemies standing in it catch fire")
	# Oil patch slows.
	hz.spawn(robot.global_position + Vector3(10, 0, 0), HazardField.Kind.OIL, 1.5, 5.0, 0.45)
	var o := em.spawn(0, robot.global_position + Vector3(10, 0, 0))
	for f in 20:
		await get_tree().physics_frame
	check(em.get_slow_t(o) > 0.0 and em.get_slow_mult(o) < 0.5, "oil slicks slow enemies")
	em.enemy_types[2].speed = 2.2
	scene.queue_free()
	await get_tree().process_frame


func _test_combo_and_list_fixes() -> void:
	print("regressions: leg combos, auto-install, parts list")
	var main: Node = await _open_main()
	rs.enemies.spawn_enabled = false
	rs.pickups.clear_all()
	var robot: RobotController = rs.robot
	var bm: BuildMode = main.get_node("Screen/GameViewport/PrototypeArena/BuildMode")
	var panel: BuildPanel = main.get_node("BuildPanel")
	var c := _chassis(robot)
	rs.inventory.clear()

	# Overworld hover pickup shows up in the parts list (used to crash it).
	rs.pickups.spawn_part(robot.global_position + Vector3(0.5, 0, 0), part("loco_hover_pad"))
	for f in 60:
		await get_tree().physics_frame
	bm.enter()
	await get_tree().process_frame
	var texts: Array = []
	for b in panel._list.get_children():
		if b is Button:
			texts.append((b as Button).text)
	check(texts.size() == 1 and String(texts[0]).begins_with("NEW  Hover Pads"), "hover pads listed on the bench, marked NEW %s" % [texts])

	# Wheels on the legs' feet: placing on one foot does both (was blocked).
	rs.add_to_inventory(part("loco_wheel"))
	bm.select_bench(rs.inventory.find(part("loco_wheel")))
	var leg := c.get_child_in(&"bottom_0_1")
	var foot_markers := 0
	for m in bm._markers:
		if m["compatible"] and (m["inst"] as PartInstance).data.drive == PartData.Drive.LEG:
			foot_markers += 1
	check(foot_markers == 2, "both leg feet light up for wheels (%d)" % foot_markers)
	check(bm.attach_selected(leg, &"foot") and robot.assembly.locomotion.mode == LocomotionProfile.Mode.SKATER, "wheels on leg feet make a Skater")
	bm.select_part(leg.get_child_in(&"foot"))
	bm.detach_selected()
	check(robot.assembly.locomotion.mode == LocomotionProfile.Mode.WALKER and rs.inventory.count(part("loco_wheel")) == 1, "detaching the skates gives back one pair")

	# Tabs: categories filter the list, counts in the titles.
	rs.inventory.clear()
	for id in ["gun_nail", "gun_laser", "mod_battery", "armor_plate", "frame_strut"]:
		rs.add_to_inventory(part(id))
	panel._tabs.current_tab = UiStyle.GROUPS.find("Weapons")
	await get_tree().process_frame
	var shown := 0
	for b in panel._list.get_children():
		shown += 1 if b is Button else 0
	check(shown == 2, "Weapons tab shows only the 2 weapons (%d)" % shown)
	check(panel._tabs.get_tab_title(0) == "All 5", "tab titles count parts (%s)" % panel._tabs.get_tab_title(0))
	check(UiStyle.part_group(part("mod_battery")) == "Power" and UiStyle.part_group(part("armor_plate")) == "Defense" and UiStyle.part_group(part("frame_strut")) == "Frame", "parts sort into the right tabs")
	bm.select_bench(rs.inventory.find(part("gun_laser")))
	check(panel._detail_title.text.begins_with("Lance Laser") and panel._detail.text.contains("Fits"), "selecting a bench part fills the detail pane")
	check(UiStyle.predict_drive(part("loco_wheel"), robot.assembly).contains("SKATER"), "detail pane predicts the drive a wheel pair would make")
	check(UiStyle.predict_drive(part("loco_tread"), robot.assembly).contains("STOMPER"), "and treads -> Stomper")
	bm.exit()

	# Auto-install never creates a conflicting drive.
	rs.inventory.clear()
	rs.auto_install = true
	var r: int = rs.acquire_part(part("loco_tread"))
	check(r == rs.Acquired.ATTACHED and robot.assembly.locomotion.mode == LocomotionProfile.Mode.STOMPER, "auto-installed treads go on the legs' feet")
	r = rs.acquire_part(part("loco_hover_pad"))
	check(r == rs.Acquired.BENCH and robot.assembly.locomotion.conflict == "", "hover pads on a walker go to the bench instead of conflicting")
	main.queue_free()
	await get_tree().process_frame


func _test_bench_pickups() -> void:
	print("bench: every pickup lands, duplicates, NEW, melt")
	var main: Node = await _open_main()
	rs.enemies.spawn_enabled = false
	rs.pickups.clear_all()
	var robot: RobotController = rs.robot
	var c := _chassis(robot)
	var lt := get_node("/root/LootTable")
	rs.inventory.clear()
	# Own one strut already, then pick up another: it must show up (the bug).
	robot.assembly.attach(part("frame_strut"), c, &"left_0_1")
	rs.pickups.spawn_part(robot.global_position + Vector3(0.6, 0, 0), part("frame_strut"))
	for f in 50:
		await get_tree().physics_frame
	check(rs.inventory.has(part("frame_strut")) and rs.get_tier(&"frame_strut") == 1, "a second strut lands on the bench")
	# Every droppable part lands on the bench, even past the old 8-slot cap.
	var n := 0
	for p in lt.parts:
		if p.category == PartData.Category.CHASSIS or p.category == PartData.Category.CORE:
			continue
		rs.pickups.spawn_part(robot.global_position + Vector3(0.6, 0, 0), p)
		for f in 30:
			await get_tree().physics_frame
		n += 1
	check(rs.inventory.size() == n + 1, "all %d parts picked up are on the bench (%d)" % [n, rs.inventory.size()])
	check(rs.new_count() == rs.inventory.size(), "fresh pickups are marked NEW")
	var bm: BuildMode = main.get_node("Screen/GameViewport/PrototypeArena/BuildMode")
	var panel: BuildPanel = main.get_node("BuildPanel")
	bm.enter()
	panel._tabs.current_tab = UiStyle.GROUPS.find("Weapons")
	await get_tree().process_frame
	check(panel._tabs.get_tab_title(UiStyle.GROUPS.find("Frame")).ends_with("*"), "tabs hiding new parts get a * (%s)" % panel._tabs.get_tab_title(UiStyle.GROUPS.find("Frame")))
	var si: int = rs.inventory.find(part("frame_strut"))
	bm.select_bench(si)
	check(not rs.is_new(si), "selecting a part clears NEW")
	check(rs.melt_block_reason(si) == "" and not panel._melt_btn.disabled, "spare strut can be melted (it's also on the robot)")
	check(rs.melt_into_upgrade(si) and rs.get_tier(&"frame_strut") == 2, "melt -> Strut Mk II")
	var lz: int = rs.inventory.find(part("gun_laser"))
	check(rs.melt_block_reason(lz) == "you need another copy to upgrade", "can't melt your only copy")
	bm.exit()
	main.queue_free()
	await get_tree().process_frame


func _test_drive_balance() -> void:
	print("drive balance")
	var walk := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"]])
	var rove := make_assembly("chassis_box", [["loco_wheel", "bottom_0_1"], ["loco_wheel", "bottom_1_1"]])
	var tank := make_assembly("chassis_box", [["loco_tread", "bottom_0_1"], ["loco_tread", "bottom_1_1"]])
	check(rove.locomotion.top_speed >= 12.0 and rove.locomotion.top_speed > walk.locomotion.top_speed * 1.6, "wheels are much faster (%.1f vs %.1f)" % [rove.locomotion.top_speed, walk.locomotion.top_speed])
	check(rove.locomotion.mass_capacity > walk.locomotion.mass_capacity * 1.5, "wheels carry more than legs")
	check(tank.locomotion.mass_capacity > rove.locomotion.mass_capacity and tank.locomotion.load_tolerance == 2.0, "treads haul the most, no slowdown until 2x")
	check(tank.locomotion.damage_reduction >= 0.25, "tread hull shrugs off 25% damage")
	var sk := make_assembly("chassis_box", [["loco_biped_leg", "bottom_0_1"], ["loco_biped_leg", "bottom_1_1"]])
	var cc := sk.root.get_child_in(&"chassis")
	for cell in [&"bottom_0_1", &"bottom_1_1"]:
		sk.attach(part("loco_wheel"), cc.get_child_in(cell), &"foot")
	check(sk.locomotion.top_speed > walk.locomotion.top_speed and sk.locomotion.top_speed < rove.locomotion.top_speed, "skater sits between walker and rover (%.1f)" % sk.locomotion.top_speed)
	check(sk.locomotion.grip < walk.locomotion.grip, "skater trades grip for speed")
	for x in [walk, rove, tank, sk]:
		x.free()


func _test_chassis_select() -> void:
	print("chassis select")
	var expect := {&"chassis_box": "Bulwark", &"chassis_tower": "Spire", &"chassis_ring": "Carousel", &"chassis_spine": "Lancer"}
	for k in 4:
		var main: Node = await _open_main(k)
		var robot: RobotController = rs.robot
		var asm := robot.assembly
		var cs: ChassisSelect = main.get_node("ChassisSelect")
		check(cs.choices.size() == 4 and not cs.is_open() and not get_tree().paused, "4 chassis offered; picking closes and unpauses")
		var cid: StringName = rs.chassis_id
		check(asm.chassis != null and asm.chassis.data.id == cid and expect.has(cid), "%s locked in" % expect.get(cid, "?"))
		var guns: Array = []
		for p in asm.get_all_parts():
			if p.data.id == &"gun_nail":
				guns.append(p)
		check(guns.size() == 2 and asm.locomotion.mode == LocomotionProfile.Mode.WALKER and is_equal_approx(robot.hp, robot.max_hp), "%s starts with legs + 2 nailguns at full HP" % expect[cid])
		match cid:
			&"chassis_box":
				check(asm.hp_mult == 1.25 and asm.armor_bonus > 0.1, "Bulwark: +25% HP, better armor")
			&"chassis_tower":
				check(is_equal_approx(asm.get_mod(guns[0], "range_mult"), 1.25) and asm.cpu_capacity >= 3, "Spire: +25% range, extra CPU")
			&"chassis_ring":
				check(asm.arc_bonus == 40.0, "Carousel: wider arcs")
				var gun_b: NailgunBehavior = guns[0].behaviors[0]
				check(gun_b.arc_param(120.0) == 160.0, "arc bonus reaches the weapons")
			&"chassis_spine":
				await get_tree().physics_frame
				var front := 0.0
				var back := 0.0
				for g in guns:
					var m := asm.get_mod(g, "damage_mult")
					if (g as PartInstance).parent_socket == &"front":
						front = m
					else:
						back = m
				check(is_equal_approx(front, 1.2) and is_equal_approx(back, 1.0), "Lancer: front gun +20%%, rear gun normal (%.2f / %.2f)" % [front, back])
				check(asm.chassis.data.get_sockets().filter(func(s): return s.type == PartData.SocketType.LOCOMOTION).size() == 6, "Lancer has room for 3 drive pairs")
		main.queue_free()
		await get_tree().process_frame


## Both horde backends must behave the same. Runs the GDScript twin and the
## native HordeSim side by side on identical input and compares them. The
## same checks also run against whichever backend is active (GDScript only
## when the native library isn't built).
func _test_horde_backends() -> void:
	print("horde backends")
	var sims: Array = [HordeSimGD.new()]
	if ClassDB.class_exists("HordeSim"):
		sims.append(ClassDB.instantiate("HordeSim"))
	else:
		print("    (native HordeSim not loaded: checking GDScript only)")
	var radius := PackedFloat32Array([0.35, 0.3, 0.8])
	var speed := PackedFloat32Array([3.4, 5.0, 2.2])
	var color := PackedColorArray([Color(0.8, 0.3, 0.2), Color(0.9, 0.8, 0.2), Color(0.5, 0.3, 0.6)])
	var hp0 := [16.0, 8.0, 70.0]
	for sim in sims:
		sim.setup(400, 2.0, 58.0)
		sim.set_types(radius, speed, color)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		for i in 300:
			var ty := i % 3
			var ang := rng.randf() * TAU
			sim.spawn(ty, Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(0.5, 25.0), hp0[ty])
		for i in range(0, 300, 7):
			sim.apply_slow(i, 0.5, 1.0)
		for i in range(3, 300, 11):
			sim.apply_burn(i, 30.0, 2.0)

	# Basic behavior, per backend.
	for sim in sims:
		var tag: String = sim.backend_name()
		check(sim.get_count() == 300 and sim.alive_count() == 300, "%s: spawned 300" % tag)
		check(sim.spawn(9, Vector3.ZERO, 1.0) == -1, "%s: unknown type is refused" % tag)
		var near: PackedInt32Array = sim.query_radius(Vector3.ZERO, 6.0)
		var brute := 0
		for i in sim.get_count():
			var p: Vector3 = sim.get_pos(i)
			brute += 1 if p.x * p.x + p.z * p.z <= 36.0 else 0
		check(near.size() == brute, "%s: grid radius query matches brute force (%d)" % [tag, brute])
		var n: int = sim.find_nearest(Vector3(3, 0, 3), 40.0, Vector3.FORWARD, -1.0)
		var best := INF
		for i in sim.get_count():
			best = minf(best, Vector2(sim.get_pos(i).x - 3.0, sim.get_pos(i).z - 3.0).length())
		check(n >= 0 and is_equal_approx(Vector2(sim.get_pos(n).x - 3.0, sim.get_pos(n).z - 3.0).length(), best), "%s: find_nearest finds the closest" % tag)
		var cone: int = sim.find_nearest(Vector3.ZERO, 40.0, Vector3.RIGHT, cos(deg_to_rad(20.0)))
		var cp: Vector3 = sim.get_pos(cone)
		check(cone < 0 or Vector2(cp.x, cp.z).normalized().dot(Vector2.RIGHT) >= cos(deg_to_rad(20.0)) - 0.001, "%s: find_nearest respects the cone" % tag)

	# Simulate both for a second with a moving target and compare.
	var contacts := []
	var kills := []
	for sim in sims:
		var nc := 0
		var nk := 0
		for f in 60:
			var target := Vector3(sin(f * 0.05) * 4.0, 0, cos(f * 0.05) * 4.0)
			sim.step(1.0 / 60.0, target, 0.6, true)
			nc += sim.get_contacts().size()
			sim.resolve_contacts()
			nk += sim.take_kills().size()
			if f == 30:
				var hits: int = sim.damage_radius(target, 3.0, 25.0, 4.0)
				nk += sim.take_kills().size()
				check(hits > 0, "%s: damage_radius hits the crowd (%d)" % [sim.backend_name(), hits])
		contacts.append(nc)
		kills.append(nk)
		check(nk > 0, "%s: burning enemies die and are reported (%d)" % [sim.backend_name(), nk])
	if sims.size() < 2:
		return
	var a: RefCounted = sims[0]
	var b: RefCounted = sims[1]
	check(contacts[0] == contacts[1], "parity: same robot contacts (%d / %d)" % contacts)
	check(kills[0] == kills[1], "parity: same kills (%d / %d)" % kills)
	var max_dp := 0.0
	var max_dhp := 0.0
	for i in a.get_count():
		max_dp = maxf(max_dp, a.get_pos(i).distance_to(b.get_pos(i)))
		max_dhp = maxf(max_dhp, absf(a.get_hp(i) - b.get_hp(i)))
	check(max_dp < 0.01 and max_dhp < 0.01, "parity: positions and hp agree after 60 steps (%.5f m, %.5f hp)" % [max_dp, max_dhp])
	var qa: PackedInt32Array = a.query_radius(Vector3(2, 0, -1), 5.0)
	var qb: PackedInt32Array = b.query_radius(Vector3(2, 0, -1), 5.0)
	qa.sort()
	qb.sort()
	check(qa == qb, "parity: query_radius (%d)" % qa.size())
	var sa: PackedInt32Array = a.query_segment(Vector3.ZERO, Vector3(1, 0, 1).normalized(), 20.0, 0.5)
	var sb: PackedInt32Array = b.query_segment(Vector3.ZERO, Vector3(1, 0, 1).normalized(), 20.0, 0.5)
	sa.sort()
	sb.sort()
	check(sa == sb, "parity: query_segment (%d)" % sa.size())
	check(a.find_nearest(Vector3(1, 0, 1), 30.0, Vector3.LEFT, 0.5) == b.find_nearest(Vector3(1, 0, 1), 30.0, Vector3.LEFT, 0.5), "parity: find_nearest")
	a.compact()
	b.compact()
	check(a.get_count() == b.get_count(), "parity: compact leaves %d" % a.get_count())
	var ba: PackedFloat32Array = a.get_multimesh_buffer(Vector3.ZERO)
	var bb: PackedFloat32Array = b.get_multimesh_buffer(Vector3.ZERO)
	var max_db := 0.0
	for k in a.get_count() * 16:
		max_db = maxf(max_db, absf(ba[k] - bb[k]))
	check(ba.size() == bb.size() and max_db < 0.01, "parity: MultiMesh buffers agree (%.5f)" % max_db)


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
