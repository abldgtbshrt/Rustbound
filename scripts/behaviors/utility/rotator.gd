class_name RotatorBehavior
extends PartBehavior

## Spins this part (and everything mounted on it) around its up axis, so
## weapons on it sweep a full circle. Params: spin_deg_per_sec.

func on_tick(delta: float) -> void:
	if part == null:
		return
	var speed := deg_to_rad(float(param("spin_deg_per_sec", 120.0)))
	part.rotate_object_local(Vector3.UP, speed * delta)
