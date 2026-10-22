class_name PartData
extends Resource

enum Category {
	CORE,
	CHASSIS,
	LOCOMOTION,
	MOUNT,
	MODULE,
	HEAD,
	ADAPTER,
	FRAME,
}

enum SocketType {
	STRUCTURAL,
	MOUNT,
	INTERNAL,
	LOCOMOTION,
}

enum Rarity {
	COMMON,
	RARE,
	LEGENDARY,
}

## Which drive a locomotion part provides. Drives don't blend: the robot runs
## one drive mode, chosen from what's on the chassis (see LocomotionProfile).
enum Drive {
	NONE,
	LEG,
	WHEEL,
	TREAD,
}

enum VisualShape {
	BOX,
	CYLINDER,
	SPHERE,
}

@export var id: StringName
@export var display_name: String = ""
@export var category: Category = Category.MODULE
## Optional authored scene. If empty, a low-poly placeholder is generated from
## the Visual group below.
@export var scene: PackedScene

@export_group("Budgets")
@export var mass: float = 1.0
@export var power_draw: float = 0.0
## Passive heat generated while attached. Weapons add heat per shot via params.
@export var heat_per_sec: float = 0.0
@export var cpu_cost: int = 0

@export_group("Provides")
@export var hp: float = 0.0
@export var power_output: float = 0.0
@export var cpu_output: int = 0
@export var pickup_radius: float = 0.0
## Added to the robot's tip resistance (gyros). 0.5 = 50% harder to tip.
@export var stability: float = 0.0
## Extra energy the battery pool can hold.
@export var energy_capacity: float = 0.0
## Extra heat the robot can hold before overheating.
@export var heat_capacity: float = 0.0
## Extra heat shed per second.
@export var heat_dissipation: float = 0.0

@export_group("Armor")
## Fraction of incoming damage blocked when the hit comes from inside this
## part's facing arc. Several plates covering the same side stack.
@export_range(0.0, 0.95) var armor_block: float = 0.0
@export var armor_arc_deg: float = 120.0

@export_group("Links")
## Multipliers this part gives to every part linked to it (touching it, or its
## direct parent/child). Keys: fire_rate_mult, heat_mult, range_mult,
## spread_mult, damage_mult.
@export var neighbor_mods: Dictionary = {}

@export_group("Locomotion")
@export var drive: Drive = Drive.NONE
@export var top_speed: float = 0.0
## Horizontal force. Acceleration = total thrust / total mass.
@export var thrust: float = 0.0
## 1 = turns on a dime, 0 = pure ice. Low grip makes the robot drift.
@export_range(0.0, 1.0) var grip: float = 1.0
@export var jump_force: float = 0.0
## Mass this part can carry before the robot slows down.
@export var mass_capacity: float = 0.0
@export var turn_rate_deg: float = 540.0

@export_group("Attachment")
@export var attach_type: SocketType = SocketType.STRUCTURAL
## Other socket types this part also fits (e.g. reactors on Internal or Mount).
@export var alt_attach_types: Array[int] = []
@export_range(1, 3, 1) var attach_size: int = 1
@export var sockets: Array[SocketDef] = []

@export_group("Customization")
@export_range(0, 4, 1) var component_slots: int = 1
@export var behaviors: Array[Script] = []
## Free-form tuning values read by behaviors (fire_rate, damage, range...).
@export var params: Dictionary = {}
@export var tags: PackedStringArray = []

@export_group("Upgrades")
## Per-tier growth: key -> fraction added per Mk above I. Keys are PartData
## properties (hp, power_output, thrust...) or params keys (damage,
## fire_rate...). Negative values shrink (e.g. swing_time). Empty = can't be
## upgraded.
@export var upgrade_per_tier: Dictionary = {}

@export_group("Loot")
@export var rarity: Rarity = Rarity.COMMON
## Unique parts stop dropping / being offered once you own one this run.
@export var unique: bool = false
## 0 = never drops from enemies.
@export var drop_weight: float = 1.0
@export var scrap_value: int = 5

@export_group("Visual")
@export var visual_shape: VisualShape = VisualShape.BOX
@export var visual_size: Vector3 = Vector3(0.5, 0.5, 0.5)
## Mesh center relative to the attach point. Also used as the part's mass point.
@export var visual_offset: Vector3 = Vector3.ZERO
@export var visual_rotation_degrees: Vector3 = Vector3.ZERO
@export var visual_color: Color = Color(0.6, 0.6, 0.6)


var _expanded: Array[SocketDef] = []
var _expanded_built := false


## All socket cells, with hardpoint grids expanded.
func get_sockets() -> Array[SocketDef]:
	if not _expanded_built:
		_expanded.clear()
		for s in sockets:
			if s != null:
				_expanded.append_array(s.expand())
		_expanded_built = true
	return _expanded


func get_socket(socket_name: StringName) -> SocketDef:
	for s in get_sockets():
		if s.marker_name == socket_name:
			return s
	return null


const MAX_TIER := 5


func can_upgrade() -> bool:
	return not upgrade_per_tier.is_empty()


func fits_type(socket_type: int) -> bool:
	return int(attach_type) == socket_type or alt_attach_types.has(socket_type)


## A stat at `tier` (1 = Mk I). `base` is the Mk I value.
func scaled(key: String, base: float, tier: int) -> float:
	var frac := float(upgrade_per_tier.get(key, 0.0))
	if frac == 0.0 or tier <= 1:
		return base
	return base * maxf(1.0 + frac * float(tier - 1), 0.1)


## Mk I value of a property or param, for display.
func base_value(key: String) -> float:
	if params.has(key):
		return float(params[key])
	var v: Variant = get(key)
	return float(v) if (v is float or v is int) else 0.0


static func rarity_name(r: int) -> String:
	return ["Common", "Rare", "Legendary"][clampi(r, 0, 2)]


static func rarity_color(r: int) -> Color:
	return [Color(0.75, 0.72, 0.68), Color(0.35, 0.65, 1.0), Color(1.0, 0.78, 0.25)][clampi(r, 0, 2)]


static func tier_name(tier: int) -> String:
	return "Mk " + ["I", "II", "III", "IV", "V"][clampi(tier, 1, MAX_TIER) - 1]


func is_weapon() -> bool:
	return params.has("damage")


func get_display_name() -> String:
	return display_name if display_name != "" else String(id)
