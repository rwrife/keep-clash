extends SceneTree
## Compatibility-rendered LOD probe. Not Windows Forward+ or mobile-device evidence.
const SCENES: Array[PackedScene] = [
	preload("res://assets/models/keep_lod0.glb"),
	preload("res://assets/models/keep_lod1.glb"),
	preload("res://assets/models/keep_lod2.glb"),
]
const DISTANCES := [20.0, 50.0, 70.0]
const TRIANGLES := [5344, 1376, 384]

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var output := OS.get_environment("KEEP_CLASH_CAPTURE_DIR")
	if output.is_empty() or not output.is_absolute_path():
		push_error("KEEP_CLASH_CAPTURE_DIR must be an absolute output path")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create output directory: " + output)
		quit(1)
		return
	root.size = Vector2i(640, 480)
	DisplayServer.window_set_size(root.size)
	var world := Node3D.new()
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 40, 0)
	world.add_child(light)
	for lod in range(3):
		var imported: Node3D = SCENES[lod].instantiate()
		var source := imported.find_child("Keep", true, false) as MeshInstance3D
		var keep := MeshInstance3D.new()
		keep.mesh = source.mesh
		keep.visibility_range_begin = [0.0, 40.0, 60.0][lod]
		keep.visibility_range_end = [40.0, 60.0, 0.0][lod]
		world.add_child(keep)
		imported.free()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	world.add_child(camera)
	camera.current = true
	for lod in range(3):
		camera.position = Vector3(0, 0.8, DISTANCES[lod])
		camera.look_at(Vector3(0, 0.8, 0))
		for frame in range(30):
			await process_frame
		var count := root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,
			Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		if count != TRIANGLES[lod]:
			push_error("LOD%d at %.0fm rendered %d primitives; expected %d" %
				[lod, DISTANCES[lod], count, TRIANGLES[lod]])
			quit(1)
			return
		var image := root.get_texture().get_image()
		var path := output.path_join("keep-lod%d.png" % lod)
		if image.get_size() != root.size or image.save_png(path) != OK:
			push_error("LOD%d screenshot failed: %s" % [lod, path])
			quit(1)
			return
		print("LOD%d: %.0fm, %d rendered primitives, capture %s" % [lod, DISTANCES[lod], count, path])
	quit(0)
