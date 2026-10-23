extends Node

## Run-scoped state plus references to the live gameplay systems, so parts and
## behaviors can find them without hard node paths.

signal run_started
signal run_ended(victory: bool)
signal leveled_up(new_level: int)
signal xp_changed
signal inventory_changed
signal part_upgraded(part: PartData, tier: int)

## Where an acquired part ended up.
enum Acquired { ATTACHED, BENCH, SALVAGED, UPGRADED }

## Bench size for new acquisitions (detached parts always fit).
const MAX_INVENTORY := 60

var run_seed: int = 0
var elapsed_time: float = 0.0
var scrap: int = 0
var kills: int = 0
var running: bool = false
var rng := RandomNumberGenerator.new()

# Progression. Scrap you pick up also fills XP, like Survivors gems.
var level: int = 1
var xp: int = 0
## Level-ups earned but not yet chosen.
var pending_levelups: int = 0

## Parallel to `inventory`: true until the player selects that bench item.
var inventory_new: Array[bool] = []

## Upgrade tier per part id (missing = Mk I). Every copy of a part shares it.
var part_tiers: Dictionary = {}
## Unique parts already acquired this run (id -> true).
var uniques_taken: Dictionary = {}
## Chosen upgrade path per part id (id -> path id).
var part_paths: Dictionary = {}
## The chassis picked at run start (locked for the run).
var chassis_id: StringName = &""

## Detached / unplaced parts ("the bench"). Used by build mode. The cap only
## limits new acquisitions; parts you detach always fit.
var inventory: Array[PartData] = []
## When true, parts taken from level-up cards attach to the best free socket
## automatically. Overworld pickups always go to the bench.
var auto_install: bool = true

# Registered by the systems themselves in _ready / cleared in _exit_tree.
var robot: RobotController
var enemies: EnemyManager
var projectiles: ProjectilePool
var pickups: PickupManager
var hazards: HazardField


func begin_new_run(p_seed: int = 0) -> void:
	run_seed = p_seed if p_seed != 0 else randi()
	rng.seed = run_seed
	LootTable.reseed(run_seed)
	elapsed_time = 0.0
	scrap = 0
	kills = 0
	level = 1
	xp = 0
	pending_levelups = 0
	inventory.clear()
	inventory_new.clear()
	part_tiers.clear()
	uniques_taken.clear()
	part_paths.clear()
	chassis_id = &""
	running = true
	run_started.emit()
	inventory_changed.emit()
	xp_changed.emit()


func end_run(victory: bool) -> void:
	if not running:
		return
	running = false
	run_ended.emit(victory)


func add_scrap(amount: int) -> void:
	scrap += maxi(amount, 0)


## XP needed to go from `lvl` to `lvl + 1`.
static func xp_required(lvl: int) -> int:
	return int(round(6.0 + 4.0 * lvl + 2.0 * pow(float(lvl), 1.5)))


func xp_to_next() -> int:
	return xp_required(level)


func add_xp(amount: int) -> void:
	if amount <= 0 or not running:
		return
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		pending_levelups += 1
		leveled_up.emit(level)
	xp_changed.emit()


## Called by the level-up screen when a choice is made (or skipped).
func consume_levelup() -> void:
	pending_levelups = maxi(pending_levelups - 1, 0)


func get_tier(id: StringName) -> int:
	return int(part_tiers.get(id, 1))


func can_upgrade(part: PartData) -> bool:
	return part != null and part.can_upgrade() and get_tier(part.id) < PartData.MAX_TIER


## Raises every copy of `part` one Mk. Returns false at max tier.
func upgrade_part(part: PartData) -> bool:
	if not can_upgrade(part):
		return false
	var t := get_tier(part.id) + 1
	part_tiers[part.id] = t
	if robot != null:
		robot.assembly.recompute()
	part_upgraded.emit(part, t)
	EventBus.message.emit("%s upgraded to %s" % [part.get_display_name(), PartData.tier_name(t)])
	return true


## True when the next upgrade is the Mk III fork and no path is chosen yet.
func needs_path_choice(part: PartData) -> bool:
	return part != null and not part.paths.is_empty() and get_tier(part.id) == PartData.PATH_TIER - 1 \
		and not part_paths.has(part.id)


## Picks a branch and upgrades to Mk III in one go.
func choose_path(part: PartData, path_id: StringName) -> bool:
	var p := part.find_path(path_id)
	if p.is_empty():
		return false
	part_paths[part.id] = path_id
	EventBus.message.emit("%s takes the %s path" % [part.get_display_name(), String(p.get("name", path_id))])
	return upgrade_part(part)


func get_path_id(id: StringName) -> StringName:
	return part_paths.get(id, &"")


## True if a copy of `part` is on the robot or the bench.
func owns_part(part: PartData) -> bool:
	if inventory.has(part):
		return true
	if robot != null:
		for p in robot.assembly.get_all_parts():
			if p.data == part:
				return true
	return false


## Single entry point for every new part (pickups, level-ups, later: vending,
## wrecks). With `merge_duplicates`, a part you already own upgrades instead
## of piling on another copy. Returns an Acquired value.
func acquire_part(part: PartData, try_install: bool = true, merge_duplicates: bool = false) -> int:
	if part == null:
		return Acquired.SALVAGED
	if merge_duplicates and owns_part(part) and upgrade_part(part):
		return Acquired.UPGRADED
	if part.unique:
		uniques_taken[part.id] = true
	if try_install and auto_install and robot != null and robot.alive:
		if robot.assembly.auto_attach(part) != null:
			EventBus.message.emit("Attached %s" % part.get_display_name())
			return Acquired.ATTACHED
	if add_to_inventory(part, false, true):
		var note := ""
		if owns_part_elsewhere(part):
			note = ", or melt it into an upgrade"
		EventBus.message.emit("%s added to the bench: %s tab (Tab to build%s)" % [part.get_display_name(), UiStyle.part_group(part), note])
		return Acquired.BENCH
	add_scrap(part.scrap_value)
	EventBus.message.emit("Bench full: %s salvaged +%d scrap" % [part.get_display_name(), part.scrap_value])
	return Acquired.SALVAGED


func add_to_inventory(part: PartData, force: bool = false, is_new: bool = false) -> bool:
	if inventory.size() >= MAX_INVENTORY and not force:
		return false
	inventory_new.resize(inventory.size()) # self-heal if inventory was edited directly
	inventory.append(part)
	inventory_new.append(is_new)
	inventory_changed.emit()
	return true


func take_from_inventory(index: int) -> PartData:
	if index < 0 or index >= inventory.size():
		return null
	var p := inventory[index]
	inventory.remove_at(index)
	if index < inventory_new.size():
		inventory_new.remove_at(index)
	inventory_changed.emit()
	return p


func is_new(index: int) -> bool:
	return index >= 0 and index < inventory_new.size() and inventory_new[index]


func mark_seen(index: int) -> void:
	if is_new(index):
		inventory_new[index] = false
		inventory_changed.emit()


func new_count() -> int:
	return inventory_new.count(true)


## Another copy of this part is on the robot or elsewhere on the bench.
func owns_part_elsewhere(part: PartData, bench_index: int = -1) -> bool:
	if robot != null:
		for p in robot.assembly.get_all_parts():
			if p.data == part:
				return true
	for i in inventory.size():
		if i != bench_index and inventory[i] == part:
			return true
	return false


## Why a bench copy can't be melted into an upgrade right now, or "".
func melt_block_reason(index: int) -> String:
	if index < 0 or index >= inventory.size():
		return "nothing selected"
	var part := inventory[index]
	if not part.can_upgrade():
		return "this part has no upgrades"
	if get_tier(part.id) >= PartData.MAX_TIER:
		return "already %s" % PartData.tier_name(PartData.MAX_TIER)
	if needs_path_choice(part):
		return "Mk III is a path choice: take it from a level-up"
	if not owns_part_elsewhere(part, index):
		return "you need another copy to upgrade"
	return ""


## Spends a spare bench copy to upgrade every copy of that part one Mk.
func melt_into_upgrade(index: int) -> bool:
	if melt_block_reason(index) != "":
		return false
	var part := take_from_inventory(index)
	return upgrade_part(part)


func _process(delta: float) -> void:
	if running:
		elapsed_time += delta
