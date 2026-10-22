extends Node

## Minimal run-state holder.

var run_seed: int = 0
var elapsed_time: float = 0.0
var scrap: int = 0

func begin_new_run(seed: int = 0) -> void:
	run_seed = seed if seed != 0 else randi()
	elapsed_time = 0.0
	scrap = 0

func add_scrap(amount: int) -> void:
	scrap += max(amount, 0)

func _process(delta: float) -> void:
	elapsed_time += delta
