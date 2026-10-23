class_name EnemyData
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var hp: float = 10.0
@export var speed: float = 3.0
@export var contact_dps: float = 8.0
@export var radius: float = 0.4
@export var color: Color = Color(0.8, 0.3, 0.2)

@export_group("Visual")
## Authored model (the .glb in assets/enemies/<id>/). Faces -Z, origin at its
## feet, built at real size; its meshes are merged into one for the horde
## MultiMesh. Empty = the placeholder wedge tinted `color`.
@export var model: PackedScene
## Uniform scale applied to `model`.
@export var model_scale: float = 1.0


## The single Mesh the horde draws for this enemy, or null for the wedge.
func get_mesh() -> Mesh:
	return ModelUtil.mesh_from_scene(model) if model != null else null

@export_group("Drops")
@export var scrap_value: int = 1
@export_range(0.0, 1.0) var part_drop_chance: float = 0.02

@export_group("Spawning")
@export var spawn_weight: float = 1.0
## Seconds into the run before this enemy can appear.
@export var min_time: float = 0.0
## Extra spawn weight gained per minute after min_time.
@export var weight_per_minute: float = 0.0
