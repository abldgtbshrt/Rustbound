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

const MAX_INVENTORY := 8

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

## Upgrade tier per part id (missing = Mk I). Every copy of a part shares it.
var part_tiers: Dictionary = {}

## Detached / unplaced parts ("the bench"). Used by build mode. The cap only
## limits new acquisitions; parts you detach always fit.
var inventory: Array[PartData] = []
## When true, new parts attach to the best free socket automatically and only
## go to the bench if nothing fits.
var auto_install: bool = true

# Registered by the systems themselves in _ready / cleared in _exit_tree.
var robot: RobotController
var enemies: EnemyManager
var projectiles: ProjectilePool
var pickups: PickupManager


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
	part_tiers.clear()
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
	if try_install and auto_install and robot != null and robot.alive:
		if robot.assembly.auto_attach(part) != null:
			EventBus.message.emit("Attached %s" % part.get_display_name())
			return Acquired.ATTACHED
	if add_to_inventory(part):
		EventBus.message.emit("%s added to bench (Tab to build)" % part.get_display_name())
		return Acquired.BENCH
	add_scrap(part.scrap_value)
	EventBus.message.emit("Bench full: %s salvaged +%d scrap" % [part.get_display_name(), part.scrap_value])
	return Acquired.SALVAGED


func add_to_inventory(part: PartData, force: bool = false) -> bool:
	if inventory.size() >= MAX_INVENTORY and not force:
		return false
	inventory.append(part)
	inventory_changed.emit()
	return true


func take_from_inventory(index: int) -> PartData:
	if index < 0 or index >= inventory.size():
		return null
	var p := inventory[index]
	inventory.remove_at(index)
	inventory_changed.emit()
	return p


func _process(delta: float) -> void:
	if running:
		elapsed_time += delta
