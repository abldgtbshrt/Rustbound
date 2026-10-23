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


func _grid(n: String, t: int, pos: Vector3, g: Vector2i, u: Vector3, v: Vector3, size: int = 1, rot: Vector3 = Vector3.ZERO) -> SocketDef:
	return SocketDef.make_grid(StringName(n), t, pos, g, u, v, size, rot)


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
	core.upgrade_per_tier = {"hp": 0.25, "power_output": 0.2, "cpu_output": 0.25}
	out.append(core)

	# --- Chassis -------------------------------------------------------------
	# Chassis are picked at the start of a run and locked in. Each has a
	# feature (params read by RobotAssembly) and a starter layout:
	# [part id, socket, yaw steps].
	var box := _part("chassis_box", "Bulwark", PartData.Category.CHASSIS, STRUCT, 2)
	box.params = {"feature": "Armored box: +25% max HP, armor plates block 15% more. The most hardpoints.",
		"hp_mult": 1.25, "armor_bonus": 0.15,
		"starter": [["loco_biped_leg", "bottom_0_1", 0], ["gun_nail", "top_1_0", 0], ["gun_nail", "top_1_1", 4]]}
	box.mass = 3.0
	box.hp = 40.0
	box.drop_weight = 0.0
	_vis(box, PartData.VisualShape.BOX, Vector3(1.2, 0.7, 1.0), Vector3.ZERO, Color(0.55, 0.52, 0.45))
	# Hardpoint grids on every face. Side/front/back cells face outward by
	# default; the player can rotate whatever goes on them.
	box.sockets = [
		_grid("top", MOUNT, Vector3(0.0, 0.35, 0.05), Vector2i(3, 2), Vector3(0.38, 0, 0), Vector3(0, 0, 0.4), 2),
		_grid("left", MOUNT, Vector3(-0.6, 0.0, 0.0), Vector2i(2, 2), Vector3(0, 0, 0.45), Vector3(0, 0.3, 0), 2, Vector3(0, 90, 0)),
		_grid("right", MOUNT, Vector3(0.6, 0.0, 0.0), Vector2i(2, 2), Vector3(0, 0, 0.45), Vector3(0, 0.3, 0), 2, Vector3(0, -90, 0)),
		_grid("front", MOUNT, Vector3(0.0, 0.0, -0.5), Vector2i(2, 1), Vector3(0.55, 0, 0), Vector3.ZERO, 1),
		_grid("back", MOUNT, Vector3(0.0, 0.0, 0.5), Vector2i(2, 1), Vector3(0.55, 0, 0), Vector3.ZERO, 1, Vector3(0, 180, 0)),
		_grid("bottom", LOCO, Vector3(0.0, -0.35, 0.0), Vector2i(2, 3), Vector3(0.9, 0, 0), Vector3(0, 0, 0.35), 2),
		_grid("internal", INTERNAL, Vector3.ZERO, Vector2i(2, 1), Vector3(0, 0, 0.5), Vector3.ZERO, 1),
		_sock("head", STRUCT, Vector3(0.0, 0.35, -0.45), 1),
	]
	box.upgrade_per_tier = {"hp": 0.35}
	out.append(box)

	var tower := _part("chassis_tower", "Spire", PartData.Category.CHASSIS, STRUCT, 2)
	tower.cpu_output = 1
	tower.params = {"feature": "Tall sightlines: weapons get +25% range and +1 CPU. Top-heavy, so it tips easily.",
		"range_mult": 1.25,
		"starter": [["loco_biped_leg", "bottom_0_0", 0], ["gun_nail", "top", 0], ["gun_nail", "left_0_1", 2]]}
	tower.mass = 4.0
	tower.hp = 50.0
	tower.drop_weight = 0.0
	_vis(tower, PartData.VisualShape.BOX, Vector3(0.7, 1.8, 0.7), Vector3(0, 0.5, 0), Color(0.5, 0.48, 0.55))
	tower.sockets = [
		_sock("top", MOUNT, Vector3(0.0, 1.4, 0.1), 2),
		_grid("left", MOUNT, Vector3(-0.35, 0.6, 0.0), Vector2i(1, 3), Vector3.ZERO, Vector3(0, 0.45, 0), 2, Vector3(0, 90, 0)),
		_grid("right", MOUNT, Vector3(0.35, 0.6, 0.0), Vector2i(1, 3), Vector3.ZERO, Vector3(0, 0.45, 0), 2, Vector3(0, -90, 0)),
		_grid("front", MOUNT, Vector3(0.0, 0.6, -0.35), Vector2i(1, 2), Vector3.ZERO, Vector3(0, 0.6, 0), 1),
		_grid("bottom", LOCO, Vector3(0.0, -0.4, 0.0), Vector2i(2, 1), Vector3(0.6, 0, 0), Vector3.ZERO, 2),
		_grid("internal", INTERNAL, Vector3(0.0, 0.5, 0.0), Vector2i(1, 2), Vector3.ZERO, Vector3(0, 0.5, 0), 1),
		_sock("head", STRUCT, Vector3(0.0, 1.4, -0.2), 1),
	]
	tower.upgrade_per_tier = {"hp": 0.35}
	out.append(tower)

	var ring := _part("chassis_ring", "Carousel", PartData.Category.CHASSIS, STRUCT, 2)
	ring.mass = 3.2
	ring.hp = 40.0
	ring.drop_weight = 0.0
	ring.params = {"feature": "Round hull with 8 rim mounts facing every way: weapon arcs +40°, turns 25% faster.",
		"arc_bonus": 40.0, "turn_rate_mult": 1.25,
		"starter": [["loco_biped_leg", "bottom_0_0", 0], ["gun_nail", "rim_0", 0], ["gun_nail", "rim_4", 0]]}
	_vis(ring, PartData.VisualShape.CYLINDER, Vector3(1.4, 0.6, 1.4), Vector3.ZERO, Color(0.5, 0.55, 0.5))
	var rim: Array[SocketDef] = []
	for k in 8:
		var a := deg_to_rad(45.0 * k)
		rim.append(_sock("rim_%d" % k, MOUNT, Vector3(-sin(a), 0.0, -cos(a)) * 0.7, 2, Vector3(0, 45.0 * k, 0)))
	rim.append_array([
		_sock("top", MOUNT, Vector3(0.0, 0.3, 0.1), 2),
		_grid("bottom", LOCO, Vector3(0.0, -0.3, 0.0), Vector2i(2, 2), Vector3(0.8, 0, 0), Vector3(0, 0, 0.6), 2),
		_grid("internal", INTERNAL, Vector3.ZERO, Vector2i(2, 1), Vector3(0.5, 0, 0), Vector3.ZERO, 1),
		_sock("head", STRUCT, Vector3(0.0, 0.3, -0.4), 1),
	])
	ring.sockets = rim
	ring.upgrade_per_tier = {"hp": 0.35}
	out.append(ring)

	var spine := _part("chassis_spine", "Lancer", PartData.Category.CHASSIS, STRUCT, 2)
	spine.mass = 3.6
	spine.hp = 40.0
	spine.drop_weight = 0.0
	spine.params = {"feature": "Long spine with room for 3 drivetrain pairs: forward-facing weapons deal +20% damage. Turns 15% slower.",
		"front_damage_mult": 1.2, "turn_rate_mult": 0.85,
		"starter": [["loco_biped_leg", "bottom_0_1", 0], ["gun_nail", "front", 0], ["gun_nail", "back", 0]]}
	_vis(spine, PartData.VisualShape.BOX, Vector3(0.6, 0.5, 2.0), Vector3.ZERO, Color(0.55, 0.45, 0.4))
	spine.sockets = [
		_grid("top", MOUNT, Vector3(0.0, 0.25, 0.0), Vector2i(1, 4), Vector3.ZERO, Vector3(0, 0, 0.45), 2),
		_grid("left", MOUNT, Vector3(-0.3, 0.0, 0.0), Vector2i(1, 4), Vector3.ZERO, Vector3(0, 0, 0.45), 2, Vector3(0, 90, 0)),
		_grid("right", MOUNT, Vector3(0.3, 0.0, 0.0), Vector2i(1, 4), Vector3.ZERO, Vector3(0, 0, 0.45), 2, Vector3(0, -90, 0)),
		_sock("front", MOUNT, Vector3(0.0, 0.0, -1.0), 2),
		_sock("back", MOUNT, Vector3(0.0, 0.0, 1.0), 2, Vector3(0, 180, 0)),
		_grid("bottom", LOCO, Vector3(0.0, -0.25, 0.0), Vector2i(2, 3), Vector3(0.6, 0, 0), Vector3(0, 0, 0.7), 2),
		_grid("internal", INTERNAL, Vector3.ZERO, Vector2i(1, 3), Vector3.ZERO, Vector3(0, 0, 0.6), 1),
		_sock("head", STRUCT, Vector3(0.0, 0.25, -0.85), 1),
	]
	spine.upgrade_per_tier = {"hp": 0.35}
	out.append(spine)

	# --- Locomotion (all ~0.8 m tall so mixed builds stand level) ------------
	var leg := _part("loco_biped_leg", "Biped Leg", PartData.Category.LOCOMOTION, LOCO, 1)
	leg.mass = 1.5
	leg.hp = 15.0
	leg.top_speed = 6.5
	leg.thrust = 30.0
	leg.grip = 0.85
	leg.jump_force = 7.5
	leg.mass_capacity = 5.0
	leg.turn_rate_deg = 540.0
	leg.drop_weight = 1.0
	leg.tags = PackedStringArray(["leg"])
	leg.drive = PartData.Drive.LEG
	leg.paired = true
	leg.display_name = "Biped Legs"
	leg.paths = [{"id": "fire", "name": "Scorched Steps", "desc": "Leaves a trail of burning ground that sets enemies alight.", "params": {"trail": "fire", "trail_strength": 10.0, "trail_radius": 1.1, "trail_life": 4.0}}, {"id": "oil", "name": "Hydraulic Leak", "desc": "Leaves an oil slick that slows enemies to 45% speed.", "params": {"trail": "oil", "trail_strength": 0.45, "trail_radius": 1.3, "trail_life": 6.0}}]
	leg.params = {"stomp": 1.0} # slam on landing
	_vis(leg, PartData.VisualShape.BOX, Vector3(0.25, 0.8, 0.45), Vector3(0, -0.4, 0), Color(0.4, 0.45, 0.5))
	# The foot takes a wheel (Skater) or a tread (Stomper): deliberate hybrids.
	leg.sockets = [
		_sock("mount_shin", MOUNT, Vector3(0.0, -0.35, -0.25), 1),
		_sock("foot", LOCO, Vector3(0.0, -0.45, 0.0), 2),
	]
	leg.upgrade_per_tier = {"thrust": 0.12, "top_speed": 0.06, "mass_capacity": 0.15, "jump_force": 0.06, "stomp": 0.25, "hp": 0.3}
	out.append(leg)

	var wheel := _part("loco_wheel", "Scrap Wheel", PartData.Category.LOCOMOTION, LOCO, 1)
	wheel.mass = 1.2
	wheel.hp = 10.0
	wheel.top_speed = 12.0
	wheel.thrust = 30.0
	wheel.grip = 0.55
	wheel.jump_force = 0.0
	wheel.mass_capacity = 9.0
	wheel.turn_rate_deg = 300.0
	wheel.drop_weight = 0.9
	wheel.params = {"ram": 0.8} # ram damage scales with speed
	wheel.drive = PartData.Drive.WHEEL
	wheel.paired = true
	wheel.display_name = "Scrap Wheels"
	wheel.paths = [{"id": "fire", "name": "Burnout", "desc": "Leaves a trail of burning ground that sets enemies alight.", "params": {"trail": "fire", "trail_strength": 10.0, "trail_radius": 1.1, "trail_life": 4.0}}, {"id": "oil", "name": "Oil Slick", "desc": "Leaves an oil slick that slows enemies to 45% speed.", "params": {"trail": "oil", "trail_strength": 0.45, "trail_radius": 1.3, "trail_life": 6.0}}]
	_vis(wheel, PartData.VisualShape.CYLINDER, Vector3(0.8, 0.3, 0.8), Vector3(0, -0.4, 0), Color(0.2, 0.2, 0.22), Vector3(0, 0, 90))
	wheel.upgrade_per_tier = {"thrust": 0.12, "top_speed": 0.08, "mass_capacity": 0.15, "ram": 0.3, "hp": 0.3}
	out.append(wheel)

	var tread := _part("loco_tread", "Tread Unit", PartData.Category.LOCOMOTION, LOCO, 2)
	tread.mass = 3.0
	tread.hp = 30.0
	tread.top_speed = 6.0
	tread.thrust = 55.0
	tread.grip = 1.0
	tread.mass_capacity = 14.0
	tread.turn_rate_deg = 260.0
	tread.drop_weight = 0.6
	tread.tags = PackedStringArray(["anchored"])
	tread.params = {"crush": 1.0} # grinds small enemies
	tread.drive = PartData.Drive.TREAD
	tread.paired = true
	tread.display_name = "Tread Units"
	tread.paths = [{"id": "fire", "name": "Exhaust Fire", "desc": "Leaves a trail of burning ground that sets enemies alight.", "params": {"trail": "fire", "trail_strength": 10.0, "trail_radius": 1.1, "trail_life": 4.0}}, {"id": "oil", "name": "Sludge Treads", "desc": "Leaves an oil slick that slows enemies to 45% speed.", "params": {"trail": "oil", "trail_strength": 0.45, "trail_radius": 1.3, "trail_life": 6.0}}]
	_vis(tread, PartData.VisualShape.BOX, Vector3(0.45, 0.8, 1.3), Vector3(0, -0.4, 0), Color(0.3, 0.3, 0.28))
	tread.upgrade_per_tier = {"thrust": 0.12, "mass_capacity": 0.2, "crush": 0.3, "hp": 0.3}
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
	nail.params["arc_deg"] = 120.0
	nail.paths = [{"id": "shrapnel", "name": "Shrapnel", "desc": "Nails burst on impact: 40% splash in 1.5 m.", "params": {"splash_radius": 1.5, "splash_frac": 0.4}}, {"id": "cryo", "name": "Cryo Nails", "desc": "Hits slow enemies to 55% speed for 1.5 s.", "params": {"slow_mult": 0.55, "slow_dur": 1.5}}]
	_vis(nail, PartData.VisualShape.BOX, Vector3(0.18, 0.18, 0.6), Vector3(0, 0.12, -0.2), Color(0.45, 0.55, 0.65))
	nail.upgrade_per_tier = {"damage": 0.25, "fire_rate": 0.12, "range": 0.05, "hp": 0.3}
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
	rivet.params["arc_deg"] = 70.0
	rivet.paths = [{"id": "explosive", "name": "Explosive Rivets", "desc": "Each rivet explodes: 60% splash in 2.5 m.", "params": {"splash_radius": 2.5, "splash_frac": 0.6}}, {"id": "concussion", "name": "Concussion", "desc": "Double knockback; hits slow to 35% for 1 s.", "params": {"knockback": 12.0, "slow_mult": 0.35, "slow_dur": 1.0}}]
	_vis(rivet, PartData.VisualShape.BOX, Vector3(0.3, 0.3, 0.9), Vector3(0, 0.18, -0.3), Color(0.6, 0.35, 0.25))
	rivet.upgrade_per_tier = {"damage": 0.3, "fire_rate": 0.1, "hp": 0.3}
	rivet.rarity = PartData.Rarity.RARE
	out.append(rivet)

	# --- Modules / head / armor / adapter ------------------------------------
	var gyro := _part("mod_gyro", "Gyro", PartData.Category.MODULE, INTERNAL, 1)
	gyro.mass = 0.6
	gyro.power_draw = 1.0
	gyro.stability = 0.6
	# Active gyro: faster turning, 65% shorter knockdowns that end in a shockwave,
	# and it steadies the aim of linked weapons.
	gyro.params = {"turn_rate_mult": 1.3, "recover_time_mult": 0.35, "recover_pulse": 30.0}
	gyro.neighbor_mods = {"spread_mult": 0.4}
	gyro.drop_weight = 0.8
	_vis(gyro, PartData.VisualShape.SPHERE, Vector3(0.3, 0.3, 0.3), Vector3.ZERO, Color(0.3, 0.8, 0.9))
	gyro.upgrade_per_tier = {"stability": 0.3, "recover_pulse": 0.4, "turn_rate_mult": 0.05}
	gyro.rarity = PartData.Rarity.RARE
	out.append(gyro)

	var reactor := _part("mod_reactor", "Reactor", PartData.Category.MODULE, INTERNAL, 1)
	reactor.mass = 1.8
	reactor.power_output = 8.0
	reactor.heat_per_sec = 2.0
	reactor.alt_attach_types = [MOUNT] # bolt it on anywhere, not just inside
	reactor.neighbor_mods = {"fire_rate_mult": 1.3, "heat_mult": 1.3} # overclocks neighbours
	reactor.drop_weight = 0.8
	_vis(reactor, PartData.VisualShape.CYLINDER, Vector3(0.35, 0.4, 0.35), Vector3.ZERO, Color(0.4, 0.9, 0.4))
	reactor.upgrade_per_tier = {"power_output": 0.3}
	out.append(reactor)

	var sink := _part("mod_heat_sink", "Heat Sink", PartData.Category.MODULE, INTERNAL, 1)
	sink.mass = 1.0
	sink.heat_capacity = 40.0
	sink.heat_dissipation = 6.0
	sink.neighbor_mods = {"heat_mult": 0.5}
	sink.drop_weight = 0.8
	_vis(sink, PartData.VisualShape.BOX, Vector3(0.4, 0.3, 0.3), Vector3.ZERO, Color(0.75, 0.75, 0.8))
	sink.upgrade_per_tier = {"heat_capacity": 0.3, "heat_dissipation": 0.3}
	out.append(sink)

	var armor := _part("armor_plate", "Armor Plate", PartData.Category.MOUNT, MOUNT, 1)
	armor.mass = 2.0
	armor.hp = 40.0
	armor.armor_block = 0.6
	armor.armor_arc_deg = 120.0
	armor.drop_weight = 0.8
	_vis(armor, PartData.VisualShape.BOX, Vector3(0.6, 0.6, 0.1), Vector3(0, 0.1, 0), Color(0.5, 0.5, 0.42))
	armor.upgrade_per_tier = {"hp": 0.35, "armor_block": 0.06}
	out.append(armor)

	var head := _part("head_sensor", "Sensor Head", PartData.Category.HEAD, STRUCT, 1)
	head.mass = 0.5
	head.hp = 5.0
	head.pickup_radius = 3.0
	head.cpu_output = 1
	head.neighbor_mods = {"range_mult": 1.25}
	head.drop_weight = 0.6
	_vis(head, PartData.VisualShape.BOX, Vector3(0.4, 0.3, 0.35), Vector3(0, 0.15, 0), Color(0.85, 0.8, 0.3))
	head.upgrade_per_tier = {"pickup_radius": 0.3, "cpu_output": 0.5}
	head.rarity = PartData.Rarity.RARE
	out.append(head)

	# --- Power & mobility -------------------------------------------------------
	var battery := _part("mod_battery", "Battery Pack", PartData.Category.MODULE, INTERNAL, 1)
	battery.alt_attach_types = [MOUNT]
	battery.mass = 0.8
	battery.hp = 5.0
	battery.energy_capacity = 40.0
	battery.drop_weight = 0.8
	_vis(battery, PartData.VisualShape.BOX, Vector3(0.3, 0.35, 0.25), Vector3(0, 0.12, 0), Color(0.3, 0.7, 0.95))
	battery.upgrade_per_tier = {"energy_capacity": 0.35}
	out.append(battery)

	var jet := _part("util_jet", "Jump Jet", PartData.Category.MOUNT, MOUNT, 1)
	jet.alt_attach_types = [LOCO]
	jet.mass = 0.8
	jet.hp = 8.0
	jet.drop_weight = 0.9
	jet.behaviors = [load("res://scripts/behaviors/utility/jet.gd")]
	# Hold jump in the air to thrust: lift = total jet_thrust / mass (gravity 20).
	jet.params = {"jet_thrust": 140.0, "jet_energy": 10.0}
	_vis(jet, PartData.VisualShape.CYLINDER, Vector3(0.26, 0.45, 0.26), Vector3(0, -0.05, 0), Color(0.35, 0.33, 0.3))
	jet.upgrade_per_tier = {"jet_thrust": 0.2}
	out.append(jet)

	# --- Frame: shape the robot -----------------------------------------------
	var strut := _part("frame_strut", "Strut", PartData.Category.FRAME, MOUNT, 1)
	strut.mass = 0.6
	strut.hp = 8.0
	strut.drop_weight = 1.0
	strut.scrap_value = 3
	_vis(strut, PartData.VisualShape.BOX, Vector3(0.14, 0.14, 1.0), Vector3(0, 0, -0.5), Color(0.62, 0.55, 0.42))
	strut.sockets = [
		_sock("end", MOUNT, Vector3(0.0, 0.0, -1.0), 2),
		_sock("under", LOCO, Vector3(0.0, -0.07, -0.85), 2),
		_sock("side_l", MOUNT, Vector3(-0.07, 0.0, -0.5), 1, Vector3(0, 90, 0)),
		_sock("side_r", MOUNT, Vector3(0.07, 0.0, -0.5), 1, Vector3(0, -90, 0)),
	]
	strut.upgrade_per_tier = {"hp": 0.4}
	out.append(strut)

	var mast := _part("frame_mast", "Mast", PartData.Category.FRAME, MOUNT, 1)
	mast.mass = 0.8
	mast.hp = 8.0
	mast.drop_weight = 0.8
	mast.scrap_value = 3
	# Built upright regardless of the face it sits on: the visual goes up the
	# socket's +Y, which is always up.
	_vis(mast, PartData.VisualShape.BOX, Vector3(0.14, 1.2, 0.14), Vector3(0, 0.6, 0), Color(0.62, 0.55, 0.42))
	mast.sockets = [
		_sock("top", MOUNT, Vector3(0.0, 1.2, 0.0), 2),
		_sock("crow", STRUCT, Vector3(0.0, 1.1, -0.12), 1),
		_sock("mid_l", MOUNT, Vector3(-0.07, 0.6, 0.0), 1, Vector3(0, 90, 0)),
		_sock("mid_r", MOUNT, Vector3(0.07, 0.6, 0.0), 1, Vector3(0, -90, 0)),
	]
	mast.upgrade_per_tier = {"hp": 0.4}
	out.append(mast)

	var rotator := _part("util_rotator", "Rotator", PartData.Category.MOUNT, MOUNT, 2)
	rotator.mass = 1.2
	rotator.hp = 10.0
	rotator.power_draw = 1.0
	rotator.drop_weight = 0.6
	rotator.behaviors = [load("res://scripts/behaviors/utility/rotator.gd")]
	rotator.params = {"spin_deg_per_sec": 120.0}
	_vis(rotator, PartData.VisualShape.CYLINDER, Vector3(0.6, 0.15, 0.6), Vector3(0, 0.08, 0), Color(0.45, 0.5, 0.6))
	rotator.sockets = [
		_sock("platter", MOUNT, Vector3(0.0, 0.16, 0.0), 2),
		_sock("rim_l", MOUNT, Vector3(-0.3, 0.08, 0.0), 1, Vector3(0, 90, 0)),
		_sock("rim_r", MOUNT, Vector3(0.3, 0.08, 0.0), 1, Vector3(0, -90, 0)),
	]
	rotator.upgrade_per_tier = {"spin_deg_per_sec": 0.2, "hp": 0.3}
	rotator.rarity = PartData.Rarity.RARE
	out.append(rotator)

	var sword := _part("melee_chain_sword", "Chain Sword Arm", PartData.Category.MOUNT, MOUNT, 2)
	sword.mass = 2.0
	sword.hp = 15.0
	sword.power_draw = 2.0
	sword.drop_weight = 0.8
	sword.behaviors = [load("res://scripts/behaviors/weapons/chain_sword.gd")]
	sword.params = {"damage": 22.0, "reach": 2.4, "arc_deg": 110.0, "swing_time": 0.5,
		"knockback": 5.0, "heat_per_swing": 2.0}
	_vis(sword, PartData.VisualShape.BOX, Vector3(0.14, 0.1, 1.4), Vector3(0, 0.1, -0.75), Color(0.75, 0.3, 0.25))
	sword.paths = [{"id": "searing", "name": "Searing Edge", "desc": "Sets enemies on fire: 8 dmg/s for 3 s.", "params": {"burn_dps": 8.0, "burn_dur": 3.0}}, {"id": "hamstring", "name": "Hamstring", "desc": "Cuts slow enemies to 40% speed for 2 s.", "params": {"slow_mult": 0.4, "slow_dur": 2.0}}]
	sword.upgrade_per_tier = {"damage": 0.3, "swing_time": -0.08, "reach": 0.05, "hp": 0.3}
	sword.rarity = PartData.Rarity.RARE
	out.append(sword)

	# --- Weapons II ---------------------------------------------------------------
	var flamer := _part("gun_flamethrower", "Flamethrower", PartData.Category.MOUNT, MOUNT, 1)
	flamer.mass = 1.2
	flamer.hp = 8.0
	flamer.power_draw = 2.0
	flamer.drop_weight = 1.0
	flamer.behaviors = [load("res://scripts/behaviors/weapons/flamethrower.gd")]
	flamer.params = {"dps": 40.0, "range": 5.0, "arc_deg": 50.0, "burst_time": 1.2, "pause_time": 0.8, "heat_per_sec": 3.0}
	flamer.upgrade_per_tier = {"dps": 0.25, "range": 0.06, "burst_time": 0.08}
	flamer.paths = [{"id": "napalm", "name": "Napalm", "desc": "Leaves enemies burning: 10 dmg/s for 3 s.", "params": {"burn_dps": 10.0, "burn_dur": 3.0}}, {"id": "wide", "name": "Wide Nozzle", "desc": "A much wider, longer cone (85°, +1.5 m).", "params": {"arc_deg": 85.0, "range": 6.5}}]
	_vis(flamer, PartData.VisualShape.CYLINDER, Vector3(0.2, 0.55, 0.2), Vector3(0, 0.1, -0.2), Color(0.7, 0.35, 0.15), Vector3(-90, 0, 0))
	out.append(flamer)

	var boom := _part("gun_boomerang", "Boomerang Launcher", PartData.Category.MOUNT, MOUNT, 1)
	boom.mass = 1.0
	boom.hp = 8.0
	boom.power_draw = 1.0
	boom.drop_weight = 1.0
	boom.behaviors = [load("res://scripts/behaviors/weapons/boomerang.gd")]
	boom.params = {"damage": 16.0, "range": 9.0, "curve": 1.2, "flight_time": 1.4, "interval": 2.2, "blades": 1, "heat_per_throw": 2.0}
	boom.upgrade_per_tier = {"damage": 0.25, "range": 0.08, "interval": -0.06}
	boom.paths = [{"id": "twin", "name": "Twin Blades", "desc": "Throws two blades in mirrored arcs.", "params": {"blades": 2}}, {"id": "razor", "name": "Razor Wind", "desc": "Blades slow enemies to 50% for 2 s.", "params": {"slow_mult": 0.5, "slow_dur": 2.0}}]
	_vis(boom, PartData.VisualShape.BOX, Vector3(0.3, 0.2, 0.4), Vector3(0, 0.1, -0.15), Color(0.6, 0.6, 0.7))
	out.append(boom)

	var laser := _part("gun_laser", "Lance Laser", PartData.Category.MOUNT, MOUNT, 2)
	laser.rarity = PartData.Rarity.RARE
	laser.mass = 1.8
	laser.hp = 10.0
	laser.power_draw = 4.0
	laser.cpu_cost = 1
	laser.drop_weight = 0.8
	laser.behaviors = [load("res://scripts/behaviors/weapons/laser.gd")]
	laser.params = {"damage": 45.0, "range": 22.0, "width": 0.5, "arc_deg": 40.0, "charge_time": 2.5, "heat_per_shot": 8.0, "beams": 1, "spread_deg": 12.0}
	laser.upgrade_per_tier = {"damage": 0.3, "charge_time": -0.08, "range": 0.05}
	laser.paths = [{"id": "prism", "name": "Prism", "desc": "Splits into 3 beams fanned 24° apart.", "params": {"beams": 3, "spread_deg": 12.0}}, {"id": "burning", "name": "Burning Beam", "desc": "Twice as wide and sets enemies on fire.", "params": {"width": 1.0, "burn_dps": 12.0, "burn_dur": 3.0}}]
	_vis(laser, PartData.VisualShape.BOX, Vector3(0.18, 0.22, 1.0), Vector3(0, 0.12, -0.35), Color(0.75, 0.2, 0.3))
	out.append(laser)

	var bay := _part("gun_drone_bay", "Drone Bay", PartData.Category.MOUNT, MOUNT, 2)
	bay.rarity = PartData.Rarity.RARE
	bay.mass = 1.6
	bay.hp = 12.0
	bay.power_draw = 3.0
	bay.drop_weight = 0.8
	bay.behaviors = [load("res://scripts/behaviors/weapons/drone_bay.gd")]
	bay.params = {"drones": 1, "damage": 6.0, "range": 10.0, "fire_interval": 0.5, "orbit_radius": 2.2}
	bay.upgrade_per_tier = {"damage": 0.3, "fire_interval": -0.06, "range": 0.06}
	bay.paths = [{"id": "swarm", "name": "Swarm", "desc": "Launch a second drone.", "params": {"drones": 2}}, {"id": "repair", "name": "Repair Drones", "desc": "Your drone also repairs you 2 HP/s.", "params": {"heal_per_sec": 2.0}}]
	_vis(bay, PartData.VisualShape.BOX, Vector3(0.5, 0.3, 0.5), Vector3(0, 0.15, 0), Color(0.55, 0.5, 0.3))
	out.append(bay)

	var hover := _part("loco_hover_pad", "Hover Pads", PartData.Category.LOCOMOTION, LOCO, 1)
	hover.rarity = PartData.Rarity.RARE
	hover.drive = PartData.Drive.HOVER
	hover.paired = true
	hover.mass = 1.0
	hover.hp = 10.0
	hover.power_draw = 2.0 # each pad; pads need power to float
	hover.top_speed = 9.0
	hover.thrust = 28.0
	hover.grip = 0.15
	hover.mass_capacity = 7.0
	hover.turn_rate_deg = 360.0
	hover.drop_weight = 0.7
	hover.params = {"hover_height": 0.5}
	hover.upgrade_per_tier = {"thrust": 0.12, "top_speed": 0.08, "mass_capacity": 0.15, "hp": 0.3}
	hover.paths = [{"id": "fire", "name": "Thermal Wake", "desc": "Leaves a trail of burning ground.", "params": {"trail": "fire", "trail_strength": 10.0, "trail_radius": 1.2, "trail_life": 4.0}}, {"id": "static", "name": "Static Field", "desc": "Leaves a crackling field that slows enemies to 40%.", "params": {"trail": "static", "trail_strength": 0.4, "trail_radius": 1.3, "trail_life": 5.0}}]
	_vis(hover, PartData.VisualShape.CYLINDER, Vector3(0.6, 0.18, 0.6), Vector3(0, -0.12, 0), Color(0.3, 0.75, 0.9))
	out.append(hover)

	# --- Signature parts: one distinct mechanic each, one per run -------------
	var magnet := _part("sig_magnet_arm", "Magnet Arm", PartData.Category.MOUNT, MOUNT, 2)
	magnet.rarity = PartData.Rarity.RARE
	magnet.unique = true
	magnet.mass = 1.6
	magnet.hp = 12.0
	magnet.power_draw = 2.0
	magnet.pickup_radius = 6.0
	magnet.behaviors = [load("res://scripts/behaviors/signature/magnet_arm.gd")]
	magnet.params = {"pull_range": 9.0, "arc_deg": 100.0, "pull_speed": 6.0, "max_enemy_radius": 0.45}
	magnet.upgrade_per_tier = {"pull_range": 0.12, "pull_speed": 0.2, "pickup_radius": 0.25}
	_vis(magnet, PartData.VisualShape.BOX, Vector3(0.5, 0.3, 0.7), Vector3(0, 0.12, -0.35), Color(0.75, 0.2, 0.2))
	out.append(magnet)

	var tesla := _part("sig_tesla_coil", "Tesla Coil", PartData.Category.MOUNT, MOUNT, 1)
	tesla.rarity = PartData.Rarity.RARE
	tesla.unique = true
	tesla.mass = 1.2
	tesla.hp = 8.0
	tesla.power_draw = 3.0
	tesla.behaviors = [load("res://scripts/behaviors/signature/tesla_coil.gd")]
	tesla.params = {"damage": 14.0, "range": 7.0, "chains": 4, "chain_range": 3.5, "interval": 0.9, "heat_per_zap": 1.5}
	tesla.upgrade_per_tier = {"damage": 0.25, "chains": 0.25, "range": 0.08}
	_vis(tesla, PartData.VisualShape.CYLINDER, Vector3(0.22, 0.6, 0.22), Vector3(0, 0.3, 0), Color(0.55, 0.85, 1.0))
	out.append(tesla)

	var mortar := _part("sig_mortar", "Mortar", PartData.Category.MOUNT, MOUNT, 2)
	mortar.rarity = PartData.Rarity.RARE
	mortar.unique = true
	mortar.mass = 2.4
	mortar.hp = 14.0
	mortar.power_draw = 2.0
	mortar.behaviors = [load("res://scripts/behaviors/signature/mortar.gd")]
	mortar.params = {"damage": 35.0, "radius": 2.5, "min_range": 6.0, "range": 20.0, "arc_deg": 160.0,
		"interval": 1.6, "flight_time": 1.0, "heat_per_shot": 4.0}
	mortar.upgrade_per_tier = {"damage": 0.25, "radius": 0.1, "interval": -0.08}
	_vis(mortar, PartData.VisualShape.CYLINDER, Vector3(0.36, 0.5, 0.36), Vector3(0, 0.25, 0), Color(0.4, 0.45, 0.35), Vector3(-30, 0, 0))
	out.append(mortar)

	var shield := _part("sig_shield_projector", "Shield Projector", PartData.Category.MOUNT, MOUNT, 2)
	shield.rarity = PartData.Rarity.LEGENDARY
	shield.unique = true
	shield.mass = 1.8
	shield.hp = 10.0
	shield.power_draw = 3.0
	shield.behaviors = [load("res://scripts/behaviors/signature/shield_projector.gd")]
	# Hits from its 120° arc drain 0.6 battery per point instead of HP.
	shield.params = {"shield_arc_deg": 120.0, "shield_radius": 2.2, "energy_per_damage": 0.6, "push": 5.0}
	shield.upgrade_per_tier = {"energy_per_damage": -0.12, "push": 0.2}
	_vis(shield, PartData.VisualShape.BOX, Vector3(0.4, 0.4, 0.2), Vector3(0, 0.2, -0.1), Color(0.3, 0.8, 0.95))
	out.append(shield)

	var maw := _part("sig_scrap_maw", "Scrap Maw", PartData.Category.MOUNT, MOUNT, 2)
	maw.rarity = PartData.Rarity.RARE
	maw.unique = true
	maw.mass = 1.8
	maw.hp = 20.0
	maw.behaviors = [load("res://scripts/behaviors/signature/scrap_maw.gd")]
	maw.params = {"bite_damage": 10.0, "bite_range": 1.4, "arc_deg": 100.0, "bite_interval": 0.35,
		"heal_per_bite": 2.0, "heal_per_scrap": 1.5}
	maw.upgrade_per_tier = {"bite_damage": 0.3, "heal_per_bite": 0.3, "heal_per_scrap": 0.25}
	_vis(maw, PartData.VisualShape.BOX, Vector3(0.55, 0.35, 0.5), Vector3(0, 0.15, -0.25), Color(0.6, 0.55, 0.3))
	out.append(maw)

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
	skitter.part_drop_chance = 0.003
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
	dart.part_drop_chance = 0.002
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
	brute.part_drop_chance = 0.05
	brute.spawn_weight = 0.05
	brute.min_time = 45.0
	brute.weight_per_minute = 0.25
	out.append(brute)

	return out
