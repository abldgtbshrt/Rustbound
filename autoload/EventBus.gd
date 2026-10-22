extends Node

## Global signal hub for decoupled gameplay events.
## Signals are emitted from other scripts, so silence the unused warnings.

@warning_ignore("unused_signal")
signal part_attached(part_id: StringName)
@warning_ignore("unused_signal")
signal part_detached(part_id: StringName)
## attached == false means no socket fit and the part was salvaged for scrap.
@warning_ignore("unused_signal")
signal part_picked_up(part: PartData, attached: bool)
@warning_ignore("unused_signal")
signal robot_brownout
@warning_ignore("unused_signal")
signal robot_overheat
@warning_ignore("unused_signal")
signal robot_cooled
@warning_ignore("unused_signal")
signal robot_damaged(amount: float)
@warning_ignore("unused_signal")
signal robot_knocked_down
@warning_ignore("unused_signal")
signal robot_recovered
@warning_ignore("unused_signal")
signal robot_destroyed
@warning_ignore("unused_signal")
signal enemy_killed(enemy: EnemyData, position: Vector3)
@warning_ignore("unused_signal")
signal scrap_collected(amount: int)
@warning_ignore("unused_signal")
signal loot_spawned(position: Vector3)
## For on-screen feedback ("Attached Nailgun", "Brownout!").
@warning_ignore("unused_signal")
signal message(text: String)
