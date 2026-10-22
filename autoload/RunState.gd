extends Node

## Run-scoped state plus references to the live gameplay systems, so parts and
## behaviors can find them without hard node paths.

signal run_started
signal run_ended(victory: bool)

var run_seed: int = 0
var elapsed_time: float = 0.0
var scrap: int = 0
var kills: int = 0
var running: bool = false
var rng := RandomNumberGenerator.new()

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
	running = true
	run_started.emit()


func end_run(victory: bool) -> void:
	if not running:
		return
	running = false
	run_ended.emit(victory)


func add_scrap(amount: int) -> void:
	scrap += maxi(amount, 0)


func _process(delta: float) -> void:
	if running:
		elapsed_time += delta
