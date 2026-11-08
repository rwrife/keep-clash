extends SceneTree
## Rendered layout probe for #14. Run under Xvfb; screenshots are evidence, not device tests.

const SIZES := [Vector2i(360, 800), Vector2i(800, 1280), Vector2i(1280, 720)]


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
	var round_scene := load("res://scenes/round.tscn") as PackedScene
	var arena := round_scene.instantiate()
	root.add_child(arena)
	for size in SIZES:
		root.size = size
		DisplayServer.window_set_size(size)
		for frame in range(20):
			await process_frame
		var rect := root.get_visible_rect()
		var camera := arena.get_viewport().get_camera_3d() as Camera3D
		if camera == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
			push_error("Camera/viewport not ready at %s" % size)
			quit(1)
			return
		# Canvas-item stretching keeps logical coordinates independent of screenshot pixels.
		var inside := Rect2(rect.position, rect.size).grow(-rect.size.x * 0.04)
		for seat in range(4):
			var pos: Vector2 = arena.controller.rules.positions[seat]
			var lower := camera.unproject_position(Vector3(pos.x, 0.0, pos.y))
			var upper := camera.unproject_position(Vector3(pos.x, 1.6, pos.y))
			if not inside.has_point(lower) or not inside.has_point(upper) or absf(upper.y - lower.y) < 12.0:
				push_error("Keep %d clipped/unreadable at %s: %s / %s; viewport %s" % [seat, size, lower, upper, rect])
				quit(1)
				return
		var image := root.get_texture().get_image()
		var path := output.path_join("keep-%dx%d.png" % [size.x, size.y])
		if image.get_size() != size or image.save_png(path) != OK:
			push_error("Screenshot failed: " + path)
			quit(1)
			return
		print("CAPTURE: %s (%s) four keep centers and tips in frame" % [path, size])
	quit(0)
