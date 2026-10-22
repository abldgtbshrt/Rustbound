extends Node

## Global signal hub for decoupled gameplay events.

signal part_attached(part_id: StringName)
signal part_detached(part_id: StringName)
signal robot_brownout
signal robot_overheat
signal robot_damaged(amount: float)
signal loot_spawned(position: Vector3)
