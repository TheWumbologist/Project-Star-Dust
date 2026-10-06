class_name Backdrop
extends MeshInstance3D
## The deep-space backdrop: a big plane far below the flight plane with the
## nebula shader. It slides along under the camera so it never runs out,
## while the shader stays pinned to world space (so it still parallaxes).

## How far below the flight plane the backdrop sits.
@export var depth: float = 45.0


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		global_position = Vector3(cam.global_position.x, -depth, cam.global_position.z)
