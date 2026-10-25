extends GutTest
## Issue #3 gates for seat claim invariants, device conflict prevention,
## BackPolicy matrix, ArcMesh generation, and scene loading.


func test_device_cannot_claim_two_seats() -> void:
	var seats := SeatRouting.make_default_seats()
	assert_eq(SeatRouting.claim(seats, 0, "keyboard"), "")
	assert_eq(seats[0]["kind"], "human")
	var second := SeatRouting.claim(seats, 1, "keyboard")
	assert_ne(second, "", "keyboard cannot claim two seats simultaneously")
	assert_true(second.contains("already holds seat 1"))
	assert_eq(seats[1]["kind"], "bot", "second seat must not be reassigned")


func test_seat_cannot_be_double_claimed() -> void:
	var seats := SeatRouting.make_default_seats()
	SeatRouting.claim(seats, 0, "keyboard")
	var second := SeatRouting.claim(seats, 0, "mouse")
	assert_ne(second, "")
	assert_true(second.contains("already claimed"))
	assert_eq(seats[0]["device"], "keyboard")


func test_same_device_re_claiming_same_seat_is_idempotent() -> void:
	var seats := SeatRouting.make_default_seats()
	SeatRouting.claim(seats, 0, "keyboard")
	assert_eq(SeatRouting.claim(seats, 0, "keyboard"), "")


func test_release_seat_allows_new_claim() -> void:
	var seats := SeatRouting.make_default_seats()
	SeatRouting.claim(seats, 0, "keyboard")
	SeatRouting.release(seats, 0)
	assert_eq(SeatRouting.claim(seats, 1, "keyboard"), "",
		"device must be free after seat release")


func test_fill_open_turns_open_seats_into_bots() -> void:
	var seats := SeatRouting.make_default_seats()
	SeatRouting.release(seats, 0)
	SeatRouting.release(seats, 2)
	SeatRouting.fill_open_with_bots(seats, 1)
	for i in range(4):
		assert_eq(seats[i]["kind"], "bot")
	assert_eq(seats[0]["difficulty"], 1)


func test_device_id_for_event_maps_cleanly() -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_A
	assert_eq(SeatRouting.device_id_for_event(key), "keyboard")
	key.keycode = KEY_ESCAPE
	assert_eq(SeatRouting.device_id_for_event(key), "", "esc must not claim seats")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	assert_eq(SeatRouting.device_id_for_event(touch), "touch")
	var joy := InputEventJoypadButton.new()
	joy.device = 2
	joy.pressed = true
	joy.button_index = JOY_BUTTON_DPAD_UP
	assert_eq(SeatRouting.device_id_for_event(joy), "joy_2")


func test_back_policy_matrix() -> void:
	assert_eq(BackPolicy.back_action("round", "Android", false), "pause")
	assert_eq(BackPolicy.back_action("round", "Android", true), "resume")
	assert_eq(BackPolicy.back_action("seats", "Android", false), "menu")
	assert_eq(BackPolicy.back_action("menu", "Android", false), "quit")
	assert_eq(BackPolicy.back_action("menu", "Windows", false), "confirm_quit")
	assert_false(BackPolicy.confirm_leave_round("Android"))
	assert_true(BackPolicy.confirm_leave_round("Windows"))
	assert_eq(BackPolicy.close_request_action("round"), "pause_and_confirm_quit")


func test_arc_mesh_generation() -> void:
	var mesh := ArcMesh.build(1.0, 2.0, 1.0, PI / 4.0, 6)
	assert_not_null(mesh)
	assert_gt(mesh.get_surface_count(), 0)
	var aabb := mesh.get_aabb()
	assert_gt(aabb.size.x, 0.5)
	assert_gt(aabb.size.z, 0.5)
	assert_almost_eq(aabb.size.y, 1.0, 0.01)


func test_round_scene_instantiates() -> void:
	var scene: PackedScene = load("res://scenes/round.tscn")
	assert_not_null(scene, "round.tscn must load")
	if scene != null:
		var node: Node = scene.instantiate()
		assert_not_null(node)
		node.free()


func test_menu_scene_instantiates() -> void:
	var scene: PackedScene = load("res://scenes/menu.tscn")
	assert_not_null(scene, "menu.tscn must load")
	if scene != null:
		var node: Node = scene.instantiate()
		assert_not_null(node)
		node.free()


func test_round_scene_counts_down_and_plays_in_tree() -> void:
	## Scene-level smoke: _ready builds world+HUD, _process drives the controller.
	var scene: PackedScene = load("res://scenes/round.tscn")
	if scene == null:
		return
	var node: Node3D = scene.instantiate()
	add_child(node)
	assert_eq(node.controller.state, RoundController.State.COUNTDOWN)
	var deadline := Time.get_ticks_msec() + 8000
	while node.controller.state == RoundController.State.COUNTDOWN and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_eq(node.controller.state, RoundController.State.PLAYING,
		"the scene loop must leave countdown on its own")
	node.controller.set_paused(true)
	var frozen: Vector2 = node.controller.rules.ball_position
	for _frame in range(10):
		await get_tree().process_frame
	assert_eq(node.controller.rules.ball_position, frozen, "pause must freeze the scene round")
	node.controller.set_paused(false)
	for _frame in range(20):
		await get_tree().process_frame
	assert_ne(node.controller.rules.ball_position, frozen, "resume must move the ball again")
	node.free()
