extends Node3D
## Round scene: greybox 3D arena (art pass is issue #4), four keeps/shields,
## ball, adaptive HUD, pause/restart/rematch loop and per-device seat routing.
## The rules run in RoundController; this node only renders and feeds input.

const MENU_SCENE := "res://scenes/menu.tscn"
const SEAT_COLORS := [Color("e05c5c"), Color("e0b35c"), Color("5ce0a8"), Color("5c9be0")]
const WALL_HALF_ARC := PI / 3.0
const JOY_DEADZONE := 0.25
const TOUCH_SENSITIVITY := 0.012

var controller: RoundController

var _ball: MeshInstance3D
var _shield_nodes: Array[Node3D] = []
var _wall_nodes: Array[Array] = []
var _core_mats: Array[StandardMaterial3D] = []
var _hud: CanvasLayer
var _seat_labels: Array[Label] = []
var _center_label: Label
var _overlay: Control
var _overlay_title: Label
var _overlay_lines: VBoxContainer
var _pause_panel: Control
var _quit_dialog: ConfirmationDialog
var _quit_to_app := false


func _ready() -> void:
	InputSetup.ensure()
	var session := get_node_or_null("/root/GameSession")
	var seats: Array[Dictionary] = (
		SeatRouting.make_solo_seats(0, false) if session == null
		else SeatRouting.duplicate_seats(session.seats)
	)
	controller = RoundController.new(seats, 1 if session == null else session.match_seed)
	controller.event_emitted.connect(_on_match_event)
	_build_world()
	_build_hud()
	_refresh_overlay()


func _process(delta: float) -> void:
	_read_human_input(delta)
	controller.advance(delta)
	_sync_visuals()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(InputSetup.ACTION_PAUSE):
		if _quit_dialog.visible:
			_quit_dialog.hide()
		elif controller.state != RoundController.State.ROUND_OVER:
			_set_paused(not controller.paused)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag:
		for seat in _seats_for_device("touch"):
			controller.nudge_target(seat, event.delta.x * TOUCH_SENSITIVITY * RoundController.INPUT_SIGN[seat])


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_handle_close_request()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_handle_back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if controller.state == RoundController.State.PLAYING:
				_set_paused(true)


func _handle_back() -> void:
	var action := BackPolicy.back_action("round", OS.get_name(), controller.paused)
	match action:
		"pause":
			_set_paused(true)
		"resume":
			_set_paused(false)
		_:
			_handle_close_request()


func _handle_close_request() -> void:
	if controller.state != RoundController.State.ROUND_OVER:
		_set_paused(true)
	_quit_to_app = true
	_quit_dialog.dialog_text = "Quit Keep Clash? The current round will be abandoned."
	_quit_dialog.popup_centered()


func _set_paused(value: bool) -> void:
	controller.set_paused(value)
	_pause_panel.visible = value


func _restart() -> void:
	controller.restart()
	_set_paused(false)
	_refresh_overlay()


func _rematch() -> void:
	controller.rematch()
	_refresh_overlay()


func _read_human_input(delta: float) -> void:
	for seat in range(4):
		if controller.seats[seat]["kind"] != "human":
			continue
		var device: String = controller.seats[seat]["device"]
		var sign_dir: float = RoundController.INPUT_SIGN[seat]
		match device:
			"keyboard":
				var axis := Input.get_action_strength(InputSetup.ACTION_CW) - Input.get_action_strength(InputSetup.ACTION_CCW)
				if not is_zero_approx(axis):
					controller.rotate_target(seat, axis * sign_dir, delta)
			"mouse":
				var angle := _mouse_arena_angle()
				if angle != INF:
					controller.set_target(seat, angle)
			_:
				if device.begins_with("joy_"):
					var pad := device.substr(4).to_int()
					var axis := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
					if absf(axis) > JOY_DEADZONE:
						controller.rotate_target(seat, axis * sign_dir, delta)


func _mouse_arena_angle() -> float:
	var mouse := get_viewport().get_mouse_position()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return INF
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return INF
	var distance := -origin.y / dir.y
	if distance <= 0.0:
		return INF
	for seat in range(4):
		if controller.seats[seat]["device"] == "mouse" and controller.seats[seat]["kind"] == "human":
			var center: Vector2 = MatchRules.SEAT_POSITIONS[seat]
			var hit := Vector2(origin.x + dir.x * distance, origin.z + dir.z * distance)
			if (hit - center).length() < 6.0:
				return (hit - center).angle()
	return INF


func _seats_for_device(device: String) -> Array[int]:
	var result: Array[int] = []
	for seat in range(4):
		if controller.seats[seat]["kind"] == "human" and controller.seats[seat]["device"] == device:
			result.append(seat)
	return result


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("08131d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("30465c")
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	env.glow_intensity = 0.6
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 32, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mat := _mat(Color("27313d"), 0.05, 0.85)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(38, 38)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = floor_mat
	add_child(floor_node)

	for seat in range(4):
		var center: Vector2 = MatchRules.SEAT_POSITIONS[seat]
		var origin3 := Vector3(center.x, 0, center.y)
		var keep := Node3D.new()
		keep.position = origin3
		add_child(keep)
		var core_mat := _mat(SEAT_COLORS[seat], 0.15, 0.55)
		var core := MeshInstance3D.new()
		var core_mesh := CylinderMesh.new()
		core_mesh.top_radius = MatchRules.CORE_RADIUS
		core_mesh.bottom_radius = MatchRules.CORE_RADIUS + 0.15
		core_mesh.height = 1.6
		core.mesh = core_mesh
		core.position.y = 0.8
		core.material_override = core_mat
		keep.add_child(core)
		_core_mats.append(core_mat)

		var walls: Array = []
		for sector in range(3):
			var angle := -PI / 2.0 + sector * TAU / 3.0
			var wall := MeshInstance3D.new()
			wall.mesh = ArcMesh.build(0.9, 1.25, 1.2, WALL_HALF_ARC * 0.92)
			wall.rotation.y = -angle
			wall.material_override = _mat(Color("8c98a6"), 0.1, 0.7)
			keep.add_child(wall)
			walls.append(wall)
		_wall_nodes.append(walls)

		var shield_pivot := Node3D.new()
		var shield := MeshInstance3D.new()
		shield.mesh = ArcMesh.build(MatchRules.SHIELD_RADIUS - 0.16, MatchRules.SHIELD_RADIUS + 0.16, 0.7, MatchRules.SHIELD_HALF_ARC * 0.95)
		shield.material_override = _mat(SEAT_COLORS[seat].lightened(0.25), 0.35, 0.35)
		shield_pivot.add_child(shield)
		keep.add_child(shield_pivot)
		_shield_nodes.append(shield_pivot)

	_ball = MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.35
	ball_mesh.height = 0.7
	_ball.mesh = ball_mesh
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color("ffd27c")
	ball_mat.emission_enabled = true
	ball_mat.emission = Color("ffb347")
	ball_mat.emission_energy_multiplier = 2.5
	ball_mat.roughness = 0.3
	_ball.material_override = ball_mat
	add_child(_ball)

	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 25, 18)
	camera.fov = 52
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	var safe := _hud_safe_margins()

	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = safe.x
	top.offset_top = safe.y
	top.offset_right = -safe.z
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud.add_child(top)
	# Four seat readouts never fit a 360px phone in one row; two columns keep
	# every label on-screen without shrinking text below readable size.
	var narrow := get_viewport().get_visible_rect().size.x < 640.0
	var strip: Container
	if narrow:
		var grid := GridContainer.new()
		grid.columns = 2
		top.add_child(grid)
		strip = grid
	else:
		var row := HBoxContainer.new()
		top.add_child(row)
		strip = row
	strip.add_theme_constant_override("separation", 10)
	for seat in range(4):
		var label := Label.new()
		label.add_theme_color_override("font_color", SEAT_COLORS[seat])
		label.add_theme_font_size_override("font_size", 13 if narrow else 16)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.add_child(label)
		_seat_labels.append(label)

	_center_label = Label.new()
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 46)
	_center_label.add_theme_color_override("font_color", Color("f2e6c8"))
	_hud.add_child(_center_label)

	var pause_button := Button.new()
	pause_button.text = "II"
	pause_button.custom_minimum_size = Vector2(56, 56)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -64 - safe.z
	pause_button.offset_top = 8 + safe.y
	pause_button.offset_right = -8 - safe.z
	pause_button.offset_bottom = 64 + safe.y
	pause_button.pressed.connect(func() -> void: _set_paused(not controller.paused))
	_hud.add_child(pause_button)

	_overlay = _panel(Vector2(320, 300))
	var overlay_box := VBoxContainer.new()
	overlay_box.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_box.add_theme_constant_override("separation", 10)
	_overlay.add_child(overlay_box)
	_overlay_title = Label.new()
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 30)
	overlay_box.add_child(_overlay_title)
	_overlay_lines = VBoxContainer.new()
	_overlay_lines.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_box.add_child(_overlay_lines)

	_pause_panel = _panel(Vector2(260, 200))
	var pause_column := VBoxContainer.new()
	pause_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_panel.add_child(pause_column)
	_button(pause_column, "Resume", func() -> void: _set_paused(false))
	_button(pause_column, "Restart round", _restart)
	_button(pause_column, "Quit to menu", func() -> void:
		_quit_to_app = false
		if BackPolicy.confirm_leave_round(OS.get_name()):
			_quit_dialog.dialog_text = "Return to menu? The current round will be abandoned."
			_quit_dialog.popup_centered()
		else:
			get_tree().change_scene_to_file(MENU_SCENE)
	)
	_pause_panel.visible = false

	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.title = "Abandon Round?"
	_quit_dialog.dialog_text = "Return to menu? The current round will be abandoned."
	_quit_dialog.confirmed.connect(func() -> void:
		if _quit_to_app:
			get_tree().quit()
		else:
			get_tree().change_scene_to_file(MENU_SCENE))
	_hud.add_child(_quit_dialog)


func _panel(size: Vector2) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.09, 0.14, 0.92)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false
	_hud.add_child(panel)
	return panel


func _refresh_overlay() -> void:
	_pause_panel.visible = controller.paused
	if controller.state == RoundController.State.ROUND_OVER:
		var result: Dictionary = controller.result
		var winner: int = result["winner"]
		if winner < 0:
			_overlay_title.text = "DRAW"
		else:
			_overlay_title.text = "SEAT %d WINS" % (winner + 1)
		for child in _overlay_lines.get_children():
			child.queue_free()
		var stars: Array = result["stars"]
		for seat in range(4):
			var entry := controller.seats[seat]
			var suffix := ""
			if result["timed_out"]:
				suffix = " · time up"
			_label(_overlay_lines, "%d %s · %d★%s" % [seat + 1, SeatRouting.describe(entry), stars[seat], suffix])
		_button(_overlay_lines, "REMATCH", _rematch)
		_button(_overlay_lines, "MENU", func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
		_overlay.visible = true
	else:
		_overlay.visible = false


func _on_match_event(event: Dictionary) -> void:
	if event["kind"] == "core":
		var dead: int = event["seat"]
		_core_mats[dead].albedo_color = Color("3d434b")
		_core_mats[dead].emission_enabled = false
		for wall in _wall_nodes[dead]:
			wall.visible = false
		_shield_nodes[dead].visible = false


func _sync_visuals() -> void:
	for seat in range(4):
		var angle: float = controller.rules.keeps[seat]["shield_angle"]
		_shield_nodes[seat].rotation.y = -angle
		var walls: Array = controller.rules.keeps[seat]["walls"]
		for sector in range(3):
			_wall_nodes[seat][sector].visible = walls[sector] and controller.rules.keeps[seat]["alive"]
	var ball_pos: Vector2 = controller.rules.ball_position
	_ball.position = Vector3(ball_pos.x, 0.55, ball_pos.y)


func _update_hud() -> void:
	match controller.state:
		RoundController.State.COUNTDOWN:
			_center_label.text = "GET READY %d" % ceili(controller.timer)
		RoundController.State.PLAYING:
			_center_label.text = "" if controller.timer <= 0.0 else "RESERVE"
		_:
			_center_label.text = ""
	for seat in range(4):
		var walls_left: int = controller.rules.keeps[seat]["walls"].count(true)
		var status := "down" if not controller.rules.keeps[seat]["alive"] else "%d walls" % walls_left
		_seat_labels[seat].text = "S%d %s · %s" % [seat + 1, SeatRouting.describe(controller.seats[seat]), status]


func _hud_safe_margins() -> Vector4:
	var safe := DisplayServer.get_display_safe_area()
	var window := DisplayServer.window_get_size()
	if safe.size == Vector2i(0, 0) or window.x <= 0:
		return Vector4(12, 8, 12, 8)
	return Vector4(
		maxf(12.0, float(safe.position.x)),
		maxf(8.0, float(safe.position.y)),
		maxf(12.0, float(window.x - (safe.position.x + safe.size.x))),
		maxf(8.0, float(window.y - (safe.position.y + safe.size.y))))


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(action)
	parent.add_child(button)


func _label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
