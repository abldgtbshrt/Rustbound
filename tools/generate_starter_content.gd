extends SceneTree

## Regenerates the starter .tres content in data/. Run from the project root:
##   godot --headless -s tools/generate_starter_content.gd
## Overwrites existing files with the same names. Hand-tune the .tres files in
## the inspector afterwards, or edit the tables here and re-run.

const STRUCT := PartData.SocketType.STRUCTURAL
const MOUNT := PartData.SocketType.MOUNT
const INTERNAL := PartData.SocketType.INTERNAL
const LOCO := PartData.SocketType.LOCOMOTION

const NAILGUN := "res://scripts/behaviors/weapons/nailgun.gd"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/parts")
	DirAccess.make_dir_recursive_absolute("res://data/enemies")
	for p in _parts():
		_save(p, "res://data/parts/%s.tres" % p.id)
	for e in _enemies():
		_save(e, "res://data/enemies/%s.tres" % e.id)
	print("Starter content generated.")
	quit()


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("Failed to save %s (%d)" % [path, err])
	else:
		print("  wrote ", path)


func _part(id: String, display: String, cat: PartData.Category, attach: PartData.SocketType, size: int) -> PartData:
	var p := PartData.new()
	p.id = StringName(id)
	p.display_name = display
	p.category = cat
	p.attach_type = attach
	p.attach_size = size
	return p


func _vis(p: PartData, shape: PartData.VisualShape, vsize: Vector3, offset: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	p.visual_shape = shape
	p.visual_size = vsize
	p.visual_offset = offset
	p.visual_color = color
	p.visual_rotation_degrees = rot


func _sock(n: String, t: int, pos: Vector3, size: int = 1, rot: Vector3 = Vector3.ZERO) -> SocketDef:
	return SocketDef.make(StringName(n), t, pos, size, rot)


func _parts() -> Array[PartData]:
	var out: Array[PartData] = []

	# --- Cores ---------------------------------------------------------------
	var core := _part("core_scrapper", "Scrapper Core", PartData.Category.CORE, STRUCT, 2)
	core.mass = 2.0
	core.hp = 60.0
	core.power_output = 10.0
	core.cpu_output = 2
	core.drop_weight = 0.0
	core.component_slots = 2
	_vis(core, PartData.VisualShape.SPHERE, Vector3(0.6, 0.6, 0.6), Vector3.ZERO, Color(0.95, 0.55, 0.15))
	core.sockets = [_sock("chassis", STRUCT, Vector3.ZERO, 2)]
	out.append(core)

	# --- Chassis -------------------------------------------------------------
	var box := _part("chassis_box", "Box Chassis", PartData.Category.CHASSIS, STRUCT, 2)
	box.mass = 3.0
	box.hp = 40.0
	box.drop_weight = 0.0
	_vis(box, PartData.VisualShape.BOX, Vector3(1.2, 0.7, 1.0), Vector3.ZERO, Color(0.55, 0.52, 0.45))
	box.sockets = [
		_sock("loco_l", LOCO, Vector3(-0.45, -0.35, 0.0), 2),
		_sock("loco_r", LOCO, Vector3(0.45, -0.35, 0.0), 2),
		_sock("loco_front", LOCO, Vector3(0.0, -0.35, -0.4), 2),
		_sock("loco_back", LOCO, Vector3(0.0, -0.35, 0.4), 2),
		_sock("mount_top", MOUNT, Vector3(0.0, 0.35, 0.15), 2),
		_sock("mount_l", MOUNT, Vector3(-0.6, 0.1, 0.0), 2, Vector3(0, 50, 0)),
		_sock("mount_r", MOUNT, Vector3(0.6, 0.1, 0.0), 2, Vector3(0, -50, 0)),
		_sock("internal_a", INTERNAL, Vector3(0.0, 0.0, 0.25), 1),
		_sock("internal_b", INTERNAL, Vector3(0.0, 0.0, -0.25), 1),
		_sock("head", STRUCT, Vector3(0.0, 0.35, -0.3), 1),
	]
	out.append(box)

	var tower := _part("chassis_tower", "Tower Chassis", PartData.Category.CHASSIS, STRUCT, 2)
	tower.mass = 4.0
	tower.hp = 50.0
	tower.drop_weight = 0.0
	_vis(tower, PartData.VisualShape.BOX, Vector3(0.7, 1.8, 0.7), Vector3(0, 0.5, 0), Color(0.5, 0.48, 0.55))
	tower.sockets = [
		_sock("loco_l", LOCO, Vector3(-0.3, -0.4, 0.0), 2),
		_sock("loco_r", LOCO, Vector3(0.3, -0.4, 0.0), 2),
		_sock("mount_top", MOUNT, Vector3(0.0, 1.4, 0.1), 2),
		_sock("mount_l", MOUNT, Vector3(-0.4, 1.1, 0.0), 2, Vector3(0, 50, 0)),
		_sock("mount_r", MOUNT, Vector3(0.4, 1.1, 0.0), 2, Vector3(0, -50, 0)),
		_sock("internal_a", INTERNAL, Vector3(0.0, 0.3, 0.0), 1),
		_sock("internal_b", INTERNAL, Vector3(0.0, 0.8, 0.0), 1),
		_sock("head", STRUCT, Vector3(0.0, 1.4, -0.2), 1),
	]
	out.append(tower)

	# --- Locomotion (all ~0.8 m tall so mixed builds stand level) ------------
	var leg := _part("loco_biped_leg", "Biped Leg", PartData.Category.LOCOMOTION, LOCO, 1)
	leg.mass = 1.5
	leg.hp = 15.0
	leg.top_speed = 7.0
	leg.thrust = 32.0
	leg.grip = 0.85
	leg.jump_force = 7.5
	leg.mass_capacity = 6.0
	leg.turn_rate_deg = 540.0
	leg.drop_weight = 1.0
	_vis(leg, PartData.VisualShape.BOX, Vector3(0.25, 0.8, 0.45), Vector3(0, -0.4, 0), Color(0.4, 0.45, 0.5))
	leg.sockets = [_sock("mount_shin", MOUNT, Vector3(0.0, -0.35, -0.25), 1)]
	out.append(leg)

	var wheel := _part("loco_wheel", "Scrap Wheel", PartData.Category.LOCOMOTION, LOCO, 1)
	wheel.mass = 1.2
	wheel.hp = 10.0
	wheel.top_speed = 11.0
	wheel.thrust = 22.0
	wheel.grip = 0.35
	wheel.jump_force = 0.0
	wheel.mass_capacity = 5.0
	wheel.turn_rate_deg = 360.0
	wheel.drop_weight = 0.9
	_vis(wheel, PartData.VisualShape.CYLINDER, Vector3(0.8, 0.3, 0.8), Vector3(0, -0.4, 0), Color(0.2, 0.2, 0.22), Vector3(0, 0, 90))
	out.append(wheel)

	var tread := _part("loco_tread", "Tread Unit", PartData.Category.LOCOMOTION, LOCO, 2)
	tread.mass = 3.0
	tread.hp = 30.0
	tread.top_speed = 5.0
	tread.thrust = 45.0
	tread.grip = 1.0
	tread.mass_capacity = 12.0
	tread.turn_rate_deg = 200.0
	tread.drop_weight = 0.6
	tread.tags = PackedStringArray(["anchored"])
	_vis(tread, PartData.VisualShape.BOX, Vector3(0.45, 0.8, 1.3), Vector3(0, -0.4, 0), Color(0.3, 0.3, 0.28))
	out.append(tread)

	# --- Weapons -------------------------------------------------------------
	var nail := _part("gun_nail", "Nailgun", PartData.Category.MOUNT, MOUNT, 1)
	nail.mass = 0.8
	nail.hp = 5.0
	nail.power_draw = 2.0
	nail.cpu_cost = 1
	nail.drop_weight = 1.2
	nail.behaviors = [load(NAILGUN)]
	nail.params = {"fire_rate": 4.0, "damage": 9.0, "range": 16.0, "speed": 32.0, "arc_deg": 200.0,
		"spread_deg": 3.0, "recoil": 0.6, "pierce": 0, "knockback": 1.5, "muzzle": 0.55, "heat_per_shot": 1.5}
	_vis(nail, PartData.VisualShape.BOX, Vector3(0.18, 0.18, 0.6), Vector3(0, 0.12, -0.2), Color(0.45, 0.55, 0.65))
	out.append(nail)

	var rivet := _part("gun_rivet", "Rivet Cannon", PartData.Category.MOUNT, MOUNT, 2)
	rivet.mass = 2.2
	rivet.hp = 10.0
	rivet.power_draw = 4.0
	rivet.cpu_cost = 1
	rivet.drop_weight = 0.5
	rivet.behaviors = [load(NAILGUN)]
	rivet.params = {"fire_rate": 1.2, "damage": 40.0, "range": 20.0, "speed": 26.0, "arc_deg": 120.0,
		"spread_deg": 0.5, "recoil": 9.0, "pierce": 3, "knockback": 6.0, "muzzle": 0.8, "heat_per_shot": 9.0}
	_vis(rivet, PartData.VisualShape.BOX, Vector3(0.3, 0.3, 0.9), Vector3(0, 0.18, -0.3), Color(0.6, 0.35, 0.25))
	out.append(rivet)

	# --- Modules / head / armor / adapter ------------------------------------
	var gyro := _part("mod_gyro", "Gyro", PartData.Category.MODULE, INTERNAL, 1)
	gyro.mass = 0.6
	gyro.power_draw = 1.0
	gyro.stability = 0.6
	gyro.drop_weight = 0.8
	_vis(gyro, PartData.VisualShape.SPHERE, Vector3(0.3, 0.3, 0.3), Vector3.ZERO, Color(0.3, 0.8, 0.9))
	out.append(gyro)

	var reactor := _part("mod_reactor", "Reactor", PartData.Category.MODULE, INTERNAL, 1)
	reactor.mass = 1.8
	reactor.power_output = 8.0
	reactor.heat_per_sec = 2.0
	reactor.drop_weight = 0.8
	_vis(reactor, PartData.VisualShape.CYLINDER, Vector3(0.35, 0.4, 0.35), Vector3.ZERO, Color(0.4, 0.9, 0.4))
	out.append(reactor)

	var sink := _part("mod_heat_sink", "Heat Sink", PartData.Category.MODULE, INTERNAL, 1)
	sink.mass = 1.0
	sink.heat_capacity = 40.0
	sink.heat_dissipation = 6.0
	sink.drop_weight = 0.8
	_vis(sink, PartData.VisualShape.BOX, Vector3(0.4, 0.3, 0.3), Vector3.ZERO, Color(0.75, 0.75, 0.8))
	out.append(sink)

	var armor := _part("armor_plate", "Armor Plate", PartData.Category.MOUNT, MOUNT, 1)
	armor.mass = 2.0
	armor.hp = 40.0
	armor.drop_weight = 0.8
	_vis(armor, PartData.VisualShape.BOX, Vector3(0.6, 0.6, 0.1), Vector3(0, 0.1, 0), Color(0.5, 0.5, 0.42))
	out.append(armor)

	var head := _part("head_sensor", "Sensor Head", PartData.Category.HEAD, STRUCT, 1)
	head.mass = 0.5
	head.hp = 5.0
	head.pickup_radius = 3.0
	head.cpu_output = 1
	head.drop_weight = 0.6
	_vis(head, PartData.VisualShape.BOX, Vector3(0.4, 0.3, 0.35), Vector3(0, 0.15, 0), Color(0.85, 0.8, 0.3))
	out.append(head)

	var adapter := _part("adapter_mount_loco", "Mount-to-Leg Adapter", PartData.Category.ADAPTER, MOUNT, 1)
	adapter.mass = 0.3
	adapter.drop_weight = 0.5
	_vis(adapter, PartData.VisualShape.BOX, Vector3(0.25, 0.25, 0.25), Vector3.ZERO, Color(0.7, 0.4, 0.7))
	adapter.sockets = [_sock("loco", LOCO, Vector3(0.0, -0.15, 0.0), 1)]
	out.append(adapter)

	return out


func _enemies() -> Array[EnemyData]:
	var out: Array[EnemyData] = []

	var skitter := EnemyData.new()
	skitter.id = &"skitter"
	skitter.display_name = "Skitter"
	skitter.hp = 12.0
	skitter.speed = 3.6
	skitter.contact_dps = 10.0
	skitter.radius = 0.35
	skitter.color = Color(0.85, 0.45, 0.2)
	skitter.scrap_value = 1
	skitter.part_drop_chance = 0.015
	skitter.spawn_weight = 1.0
	out.append(skitter)

	var dart := EnemyData.new()
	dart.id = &"dart"
	dart.display_name = "Dart"
	dart.hp = 6.0
	dart.speed = 6.0
	dart.contact_dps = 6.0
	dart.radius = 0.25
	dart.color = Color(0.95, 0.85, 0.25)
	dart.scrap_value = 1
	dart.part_drop_chance = 0.01
	dart.spawn_weight = 0.3
	dart.min_time = 90.0
	dart.weight_per_minute = 0.1
	out.append(dart)

	var brute := EnemyData.new()
	brute.id = &"brute"
	brute.display_name = "Brute"
	brute.hp = 70.0
	brute.speed = 2.2
	brute.contact_dps = 25.0
	brute.radius = 0.8
	brute.color = Color(0.55, 0.12, 0.12)
	brute.scrap_value = 4
	brute.part_drop_chance = 0.12
	brute.spawn_weight = 0.05
	brute.min_time = 45.0
	brute.weight_per_minute = 0.25
	out.append(brute)

	return out
