extends SceneTree
## Render actual round-scene keeps under Linux Compatibility; not device/performance evidence.
const DISTANCES := [20.0, 50.0, 70.0]
const TRIANGLES := [5344, 1376, 384]

func _initialize() -> void:
	call_deferred("_capture")

func _primitives() -> int:
	for frame in range(30):
		await process_frame
	return root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,
		Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)

func _capture() -> void:
	var output := OS.get_environment("KEEP_CLASH_CAPTURE_DIR")
	if output.is_empty() or not output.is_absolute_path() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("KEEP_CLASH_CAPTURE_DIR must be an absolute writable directory")
		quit(1)
		return
	root.size = Vector2i(640, 480)
	DisplayServer.window_set_size(root.size)
	root.get_node("GameSession").seats = SeatRouting.make_solo_seats(0, false)
	var arena := (load("res://scenes/round.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.controller.state = RoundController.State.PLAYING
	arena.controller.timer = 0.0
	arena._sync_visuals()
	for frame in range(30):
		await process_frame
	var camera: Camera3D = arena.get_viewport().get_camera_3d()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	camera.far = 150.0
	# ponytail: isolated visual in actual round scene under software Compatibility;
	# add full-arena render and Forward+/Mobile device budget checks separately.
	for keep in arena._keep_nodes:
		keep.visible = false
	for lod in range(3):
		for seat in range(4):
			var keep: Node3D = arena._keep_nodes[seat]
			var center: Vector3 = keep.global_position + Vector3(0, 0.8, 0)
			camera.position = center + Vector3(0, DISTANCES[lod] * 0.8, DISTANCES[lod] * 0.6)
			camera.look_at(center, Vector3.UP)
			var baseline := await _primitives()
			keep.visible = true
			var with_keep := await _primitives()
			var added := with_keep - baseline
			if added != TRIANGLES[lod]:
				push_error("Round keep seat %d LOD%d: %d added primitives, expected %d (baseline %d, full %d)" %
					[seat, lod, added, TRIANGLES[lod], baseline, with_keep])
				quit(1)
				return
			var path := output.path_join("round-keep-seat%d-lod%d.png" % [seat, lod])
			var image := root.get_texture().get_image()
			if image.get_size() != root.size or image.save_png(path) != OK:
				push_error("Round keep screenshot failed: " + path)
				quit(1)
				return
			print("ROUND KEEP seat %d LOD%d: %.0fm, baseline %d, full %d, added %d, capture %s" %
				[seat, lod, DISTANCES[lod], baseline, with_keep, added, path])
			keep.visible = false
	quit(0)
