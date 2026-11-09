extends GutTest

const ROUND_SCENE: PackedScene = preload("res://scenes/round.tscn")

var _previous_profile: ProfileStore
var _previous_settings: Dictionary
var _previous_seats: Array[Dictionary]


func before_each() -> void:
	_previous_profile = GameSession.profile
	_previous_settings = GameSession.settings.values.duplicate(true)
	_previous_seats = SeatRouting.duplicate_seats(GameSession.seats)
	GameSession.profile = ProfileStore.new("user://unused_round_framing_test.json")
	GameSession.seats = SeatRouting.make_solo_seats(0, false)
	GameSession.settings.apply(ProfileStore.default_settings())


func after_each() -> void:
	GameSession.profile = _previous_profile
	GameSession.seats = _previous_seats
	GameSession.settings.apply(_previous_settings)


func _viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	return viewport


func _arena(viewport: SubViewport) -> Node3D:
	var arena := ROUND_SCENE.instantiate()
	viewport.add_child(arena)
	arena.set_process(false)
	arena.controller.set_paused(true)
	return arena


func test_entire_arena_fits_below_hud_and_above_controls_after_resizing() -> void:
	var viewport := _viewport(Vector2i(1280, 720))
	var arena := _arena(viewport)
	for id in ArenaCatalog.IDS:
		arena.controller.bounds = ArenaCatalog.ARENAS[id]["bounds"]
		for scale_value in [0.75, 1.0, 1.5]:
			var settings := ProfileStore.default_settings()
			settings["hud_scale"] = scale_value
			GameSession.settings.apply(settings)
			for size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(360, 800), Vector2i(800, 360)]:
				viewport.size = size
				await get_tree().process_frame
				await get_tree().process_frame
				arena._layout_hud()
				arena._frame_arena()
				var camera: Camera3D = arena._camera
				var top: float = arena._top.position.y + arena._top.size.y
				var bottom: float = arena._footer.position.y
				for x in [-arena.controller.bounds.x, arena.controller.bounds.x]:
					for z in [-arena.controller.bounds.y, arena.controller.bounds.y]:
						for y in [0.0, 3.0]:
							var point := Vector3(x, y, z)
							var projected := camera.unproject_position(point)
							var context := "%s %s HUD %s point %s -> %s" % [id, size, scale_value, point, projected]
							assert_false(camera.is_position_behind(point), context)
							assert_between(projected.x, 8.0, float(size.x) - 8.0, context)
							assert_between(projected.y, top, bottom, context)


func test_shrunken_shield_meshes_preserve_radius_and_restore_all_lods() -> void:
	var arena := _arena(_viewport(Vector2i(1280, 720)))
	arena.controller.rules.shrink_remaining = 4.0
	arena._sync_visuals()
	for seat in range(4):
		for lod in range(3):
			var shield: MeshInstance3D = arena._shield_nodes[seat].get_child(lod)
			var source: Mesh = arena._normal_shield_meshes[lod]
			assert_eq(shield.mesh, arena._small_shield_meshes[lod])
			for surface in range(source.get_surface_count()):
				var original: PackedVector3Array = source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				var small: PackedVector3Array = shield.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				var radii_match := true
				var angles_match := true
				for index in range(original.size()):
					var a := Vector2(original[index].x, original[index].z)
					var b := Vector2(small[index].x, small[index].z)
					radii_match = radii_match and is_equal_approx(a.length(), b.length())
					angles_match = angles_match and absf(b.angle() - a.angle() * MatchRules.SHRINK_SCALE) < 0.0001
				assert_true(radii_match, "shrink must not pull the shield inside its collision circle")
				assert_true(angles_match, "visible shield arc must track the collision arc")
	arena.controller.rules.shrink_remaining = 0.0
	arena._sync_visuals()
	for seat in range(4):
		for lod in range(3):
			assert_eq(arena._shield_nodes[seat].get_child(lod).mesh, arena._normal_shield_meshes[lod])


func test_bump_key_mouse_and_gamepad_are_routed_only_to_their_seats() -> void:
	GameSession.seats = SeatRouting.make_default_seats()
	for seat in range(4):
		SeatRouting.claim(GameSession.seats, seat, ["keyboard", "mouse", "joy_2", "touch"][seat])
	var arena := _arena(_viewport(Vector2i(1280, 720)))
	arena.controller.set_paused(false)
	arena.controller.state = RoundController.State.PLAYING
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	arena._input(key)
	assert_gt(arena.controller.rules.bump_windows[0], 0.0)
	assert_eq(arena.controller.rules.bump_windows[1], 0.0)
	key.echo = true
	arena.controller.rules.bump_windows[0] = 0.0
	arena.controller.rules.bump_cooldowns[0] = 0.0
	arena._input(key)
	assert_eq(arena.controller.rules.bump_windows[0], 0.0, "holding Space must not auto-arm")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	arena._input(mouse)
	assert_gt(arena.controller.rules.bump_windows[1], 0.0)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	pad.device = 1
	arena._input(pad)
	assert_eq(arena.controller.rules.bump_windows[2], 0.0, "an unclaimed pad must not control another seat")
	pad.device = 2
	arena._input(pad)
	assert_gt(arena.controller.rules.bump_windows[2], 0.0)
	var touch_button: Button = arena._bump_buttons[3]
	touch_button.pressed.emit()
	assert_gt(arena.controller.rules.bump_windows[3], 0.0)


func test_bump_and_items_render_all_balls_and_reset_effects() -> void:
	var arena := _arena(_viewport(Vector2i(1280, 720)))
	arena.controller.rules.balls.append(MatchRules._new_ball(Vector2(3, 4), Vector2(20, 0)))
	arena.controller.rules.balls[1]["boost"] = 2.0
	arena.controller.rules.items[0]["cooldown"] = 5.0
	arena._sync_visuals()
	assert_true(arena._ball_nodes[1].visible)
	assert_eq(arena._ball_nodes[1].position, Vector3(3, 0.55, 4))
	assert_false(arena._ball_nodes[2].visible)
	assert_false(arena._item_nodes[0].visible)
	assert_true(arena._item_nodes[1].visible)
	var material: StandardMaterial3D = arena._ball_nodes[1].material_override
	assert_eq(material.emission, Color("ffb342"))
	arena._on_match_event({"kind": "item", "seat": -1, "item": "split", "position": Vector2.ZERO})
	arena._update_hud()
	assert_string_contains(arena._effect_label.text, "MULTIBALL")
	assert_string_contains(arena._effect_label.text, "BOOST")
	arena._restart()
	arena._sync_visuals()
	assert_false(arena._ball_nodes[1].visible)
	assert_true(arena._item_nodes[0].visible)
	assert_eq(arena._notice_remaining, 0.0)


func test_couch_buttons_and_wrapped_effects_fit_a_small_window() -> void:
	GameSession.seats = SeatRouting.make_default_seats()
	for seat in range(4):
		SeatRouting.claim(GameSession.seats, seat, ["keyboard", "mouse", "joy_2", "touch"][seat])
	var settings := ProfileStore.default_settings()
	settings["hud_scale"] = 1.5
	GameSession.settings.apply(settings)
	var viewport := _viewport(Vector2i(360, 800))
	var arena := _arena(viewport)
	arena.controller.rules.shrink_remaining = 8.0
	arena.controller.rules.balls[0]["boost"] = 3.0
	arena._notice = "MULTIBALL!"
	arena._notice_remaining = 1.5
	arena._update_hud()
	await get_tree().process_frame
	await get_tree().process_frame
	arena._layout_hud()
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size))
	for seat in arena._bump_buttons:
		var button: Button = arena._bump_buttons[seat]
		assert_true(screen.encloses(button.get_global_rect()), "every seat keeps an accessible bump button")
	for x in [-16.0, 16.0]:
		for z in [-16.0, 16.0]:
			var point: Vector2 = arena._camera.unproject_position(Vector3(x, 0, z))
			assert_lt(point.y, arena._footer.position.y, "wrapped status text must not cover the arena")
