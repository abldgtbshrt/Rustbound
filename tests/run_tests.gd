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
	await _test_heat()
	await _test_progression()
	await _test_main_scene_flow()
	_test_grids_rotation_frames()
	await _test_utility_parts()
	await _test_build_mode_rework()
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
	var adapter := a.attach(part("adapter_mount_loco"), chassis, &"left_0_0")
	check(adapter != null, "adapter fits a mount socket")
	var wheel := a.attach(part("loco_wheel"), adapter, &"loco") if adapter != null else null
	check(wheel != null, "adapter lets a wheel go on a mount")
	check(a.locomotion.part_count == 3, "wheel joins the locomotion blend (%d parts)" % a.locomotion.part_count)
	check(a.attach(part("gun_nail"), chassis, &"left_0_0") == null, "occupied socket is rejected")

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
	var a := make_assembly("chassis_box", [["loco_wheel", "bottom_0_1"]])
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

	# A chassis can't attach anywhere (core socket taken) -> goes to the bench.
	rs.pickups.spawn_part(robot.global_position, part("chassis_tower"))
	for f in 60:
		await get_tree().physics_frame
	check(rs.inventory.size() == 1 and rs.inventory[0].id == &"chassis_tower", "unattachable part goes to the bench")
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
	rs.enemies.hp[0] = 1.0e6
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
		if rs.enemies.hp[i] < 70.0:
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
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
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
	check(robot.assembly.part_count == parts_before + 1 or rs.inventory.size() == 1, "chosen part installed or benched")
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
	check(bm.active and is_equal_approx(Engine.time_scale, 0.1) and panel.visible, "build mode slows time to 10% and shows the panel")
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
	check(rs.inventory.size() >= 1 and robot.assembly.locomotion.part_count == loco_n - 1, "leg moved to bench, one fewer locomotion part")
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
	check(reattached and robot.assembly.locomotion.part_count == loco_n, "clicking the socket re-attaches the leg")

	# Scrap from the bench.
	rs.add_to_inventory(part("armor_plate"))
	bm.select_bench(rs.inventory.size() - 1)
	var scrap0: int = rs.scrap
	check(bm.scrap_selected() and rs.scrap > scrap0, "scrap a bench part for scrap")
	check(not bm.scrap_selected(), "scrapping with nothing selected is a no-op")
	bm.select_part(robot.assembly.root)
	check(not bm.detach_selected(), "core can't be detached")

	bm.exit()
	check(not bm.active and is_equal_approx(Engine.time_scale, 1.0) and not panel.visible, "exit restores time and hides panel")
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
	check(hits == 1 and em.hp[0] < 70.0, "stomp damages nearby enemies (%.0f hp left)" % em.hp[0])
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
	var hp0 := em.hp[i]
	robot.handle_enemy_contact(em, i, Vector3(0.9, 0, 0), 1.0 / 60.0)
	check(hp0 - em.hp[i] > 15.0, "ramming at speed hits hard (%.0f dmg)" % (hp0 - em.hp[i]))
	robot.velocity = Vector3.ZERO

	# Crush with treads: small enemies get ground up and don't bite.
	em.clear_all()
	_swap_locomotion(robot, "loco_tread")
	i = em.spawn(0, robot.global_position + Vector3(0.6, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	robot.hp = 100.0
	hp0 = em.hp[i]
	robot.handle_enemy_contact(em, i, Vector3(0.6, 0, 0), 0.1)
	check(em.hp[i] < hp0 and robot.hp == 100.0, "treads crush small enemies without taking contact damage")
	_swap_locomotion(robot, "loco_biped_leg")

	# Gyro recovery pulse.
	em.clear_all()
	robot.assembly.attach(part("mod_gyro"), c, &"internal_0_0")
	i = em.spawn(2, robot.global_position + Vector3(2.0, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	hp0 = em.hp[i]
	robot._fall_over(Vector3.RIGHT)
	var t0 := 0
	while robot.is_knocked_down and t0 < 200:
		await get_tree().physics_frame
		t0 += 1
	check(t0 < 60, "gyro gets the robot up fast (%d frames)" % t0)
	check(em.count > 0 and em.hp[0] < hp0, "recovery shockwave hits nearby enemies")

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
	check(bh.swings >= 1 and em.hp[front] < 70.0, "chain sword hits the enemy in front (%.0f hp)" % em.hp[front])
	check(is_equal_approx(em.hp[back], 70.0), "and not the one behind it")
	scene.queue_free()
	await get_tree().process_frame


func _test_build_mode_rework() -> void:
	print("build mode: rotate, mirror, ghost")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
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
