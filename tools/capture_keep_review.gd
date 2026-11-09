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
	root.get_node("GameSession").seats = SeatRouting.make_solo_seats(0, false)
	var arena := round_scene.instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.controller.state = RoundController.State.PLAYING
	arena.controller.timer = 0.0
	arena._sync_visuals()
	arena._update_hud()
	for size in SIZES:
		root.size = size
		DisplayServer.window_set_size(size)
		for frame in range(20):
			await process_frame
		var rect := root.get_visible_rect()
		var camera := arena.get_viewport().get_camera_3d() as Camera3D
		if camera == null or rect.size != Vector2(size):
			push_error("Camera/viewport not ready at %s" % size)
			quit(1)
			return
		var inside := Rect2(rect.position, rect.size).grow(-rect.size.x * 0.04)
		for seat in range(4):
			var visual: MeshInstance3D = arena._keep_nodes[seat].get_child(0)
			var box := visual.mesh.get_aabb()
			var projected := Rect2(camera.unproject_position(visual.to_global(box.position)), Vector2.ZERO)
			for corner in range(8):
				projected = projected.expand(camera.unproject_position(visual.to_global(box.get_endpoint(corner))))
			if not inside.encloses(projected) or projected.size.y < 12.0:
				push_error("Keep %d clipped/unreadable at %s: %s; viewport %s" % [seat, size, projected, rect])
				quit(1)
				return
		var top: float = arena._top.position.y + arena._top.size.y
		var bottom: float = arena._footer.position.y
		for x in [-arena.controller.bounds.x, arena.controller.bounds.x]:
			for z in [-arena.controller.bounds.y, arena.controller.bounds.y]:
				for y in [0.0, 3.0]:
					var point := camera.unproject_position(Vector3(x, y, z))
					if point.x < 8.0 or point.x > rect.size.x - 8.0 or point.y < top or point.y > bottom:
						push_error("Arena clipped by screen/HUD at %s: %s" % [size, point])
						quit(1)
						return
		var image := root.get_texture().get_image()
		var path := output.path_join("keep-%dx%d.png" % [size.x, size.y])
		if image.get_size() != size or image.save_png(path) != OK:
			push_error("Screenshot failed: " + path)
			quit(1)
			return
		print("CAPTURE: %s (%s) full arena and keeps inside HUD-safe frame" % [path, size])
	arena._set_paused(false)
	var rules: MatchRules = arena.controller.rules
	rules.ball_position = rules.positions[2] + Vector2(0, -2.4)
	rules.ball_velocity = Vector2(0, 14)
	var bump := InputEventKey.new()
	bump.physical_keycode = KEY_SPACE
	bump.keycode = KEY_SPACE
	bump.pressed = true
	Input.parse_input_event(bump)
	await process_frame
	bump.pressed = false
	Input.parse_input_event(bump)
	arena.controller.tick()
	if rules.balls[0]["boost"] <= 0.0 or rules.ball_velocity.length() <= 28.0:
		push_error("Live Space input did not produce a powered shield return")
		quit(1)
		return
	for item in rules.items:
		rules.ball_position = Vector2(item["position"]) - Vector2(2, 0)
		rules.ball_velocity = Vector2.RIGHT * rules.ball_velocity.length()
		for event in rules.step(0.1):
			arena._on_match_event(event)
	if rules.balls.size() != MatchRules.MAX_BALLS or rules.shrink_remaining <= 0.0 or rules.balls[0]["boost"] <= 0.0:
		push_error("Rendered power-up probe did not activate all three effects")
		quit(1)
		return
	arena._sync_visuals()
	arena._update_hud()
	for frame in range(20):
		await process_frame
	var effect_path := output.path_join("powerups-1280x720.png")
	if root.get_texture().get_image().save_png(effect_path) != OK:
		push_error("Power-up screenshot failed: " + effect_path)
		quit(1)
		return
	print("CAPTURE: %s live Space bump, three balls, speed boost and smaller shields" % effect_path)
	quit(0)
