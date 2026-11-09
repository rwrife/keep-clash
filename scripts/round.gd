extends Node3D
## Round scene: PBR arena with impact feedback, four keeps/shields,
## ball, adaptive HUD, pause/restart/rematch loop and per-device seat routing.
## The rules run in RoundController; this node only renders and feeds input.

const MENU_SCENE := "res://scenes/menu.tscn"
const SEAT_COLORS := ArenaLook.SEAT_COLORS
const WALL_HALF_ARC := PI / 3.0
const JOY_DEADZONE := 0.25
const TOUCH_SENSITIVITY := 0.012
const IMPACT_POOL_SIZE := 8
const SHAKE_SECONDS := 0.25
const CAMERA_POSITION := Vector3(0, 25, 18)
const CAMERA_BASE_FOV := 52.0
const KEEP_SCENES: Array[PackedScene] = [
	preload("res://assets/models/keep_lod0.glb"),
	preload("res://assets/models/keep_lod1.glb"),
	preload("res://assets/models/keep_lod2.glb"),
]
const KEEP_LOD_DISTANCES := [0.0, 40.0, 60.0, 0.0]
const SHIELD_SCENES: Array[PackedScene] = [
	preload("res://assets/models/shield_lod0.glb"),
	preload("res://assets/models/shield_lod1.glb"),
	preload("res://assets/models/shield_lod2.glb"),
]
const SHIELD_LOD_DISTANCES := [0.0, 40.0, 60.0, 0.0]

var controller: RoundController

var _ball: MeshInstance3D
var _shield_nodes: Array[Node3D] = []
var _keep_nodes: Array[Node3D] = []
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
var _camera: Camera3D
var _impact_pool: Array[GPUParticles3D] = []
var _next_impact := 0
var _impact_audio: AudioStreamPlayer
var _wall_tone: AudioStreamWAV
var _core_tone: AudioStreamWAV
var _shake_remaining := 0.0
var _shake_strength := 0.0
var _shake_phase := 0.0
var _shield_mats: Array[StandardMaterial3D] = []
var _floor_mat: StandardMaterial3D
var _settings_panel: SettingsPanel
var _top: VBoxContainer
var _strip: GridContainer
var _pause_button: Button
var _interrupted := false
var _camera_rest_position := CAMERA_POSITION
var _ball_nodes: Array[MeshInstance3D] = []
var _item_nodes: Array[Node3D] = []
var _small_shield_meshes: Array[ArrayMesh] = []
var _normal_shield_meshes: Array[Mesh] = []
var _bump_buttons: Dictionary = {}
var _footer: VBoxContainer
var _effect_label: Label
var _notice_remaining := 0.0
var _notice := ""
var _ball_emission := Color.WHITE
var _bump_row: GridContainer


func _ready() -> void:
	InputSetup.ensure()
	var session := get_node_or_null("/root/GameSession")
	var seats: Array[Dictionary] = (
		SeatRouting.make_solo_seats(0, false) if session == null
		else SeatRouting.duplicate_seats(session.seats)
	)
	controller = RoundController.new(seats, 1 if session == null else session.match_seed,
		"courtyard" if session == null else String(session.profile.data["arena"]))
	controller.event_emitted.connect(_on_match_event)
	_build_world()
	_build_hud()
	_top.resized.connect(_frame_arena)
	_footer.resized.connect(_frame_arena)
	_footer.minimum_size_changed.connect(_layout_hud)
	GameSession.settings.changed.connect(_apply_settings)
	get_viewport().size_changed.connect(_layout_hud)
	get_viewport().size_changed.connect(_frame_arena)
	_apply_settings()
	_refresh_overlay()


func _process(delta: float) -> void:
	if not _reduced_motion():
		# Keep the mouse aim ray independent of the previous frame's visual shake.
		_camera.position = _camera_rest_position
	_read_human_input(delta)
	controller.advance(delta)
	_sync_visuals()
	_update_hud()
	if not controller.paused:
		_notice_remaining = maxf(0.0, _notice_remaining - delta)
	if not _reduced_motion():
		_update_impact_juice(0.0 if controller.paused else delta)


func _input(event: InputEvent) -> void:
	if controller == null or _interrupted or is_instance_valid(_settings_panel) or controller.paused or controller.state != RoundController.State.PLAYING:
		return
	var device := ""
	if event.is_action_pressed(InputSetup.ACTION_BUMP) and not event.is_echo():
		if event is InputEventKey:
			device = "keyboard"
		elif event is InputEventJoypadButton:
			device = "joy_%d" % event.device
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		device = "mouse"
	if device != "":
		for seat in _seats_for_device(device):
			controller.bump(seat)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_settings_panel):
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(InputSetup.ACTION_PAUSE):
		if _quit_dialog.visible:
			_quit_dialog.hide()
		elif controller.state != RoundController.State.ROUND_OVER:
			_set_paused(not controller.paused)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag and not controller.paused:
		for seat in _seats_for_device("touch"):
			controller.nudge_target(seat, event.relative.x * TOUCH_SENSITIVITY * RoundController.INPUT_SIGN[seat])


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_handle_close_request()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_handle_back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if controller != null and controller.state != RoundController.State.ROUND_OVER:
				_interrupted = true
				controller.interrupt()
				if is_instance_valid(_pause_panel):
					_pause_panel.visible = true
				if is_instance_valid(_impact_audio):
					_impact_audio.stop()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			# Resuming the OS is not consent to resume a moving round.
			if _interrupted and controller != null:
				controller.interrupt()


func _handle_back() -> void:
	if is_instance_valid(_settings_panel):
		_settings_panel._close()
		return
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
	_pause_panel.visible = controller.paused
	if not value:
		_interrupted = false


func _restart() -> void:
	controller.restart()
	_reset_impact_juice()
	_set_paused(false)
	_apply_settings()
	_refresh_overlay()
	_notice_remaining = 0.0


func _rematch() -> void:
	controller.rematch()
	_reset_impact_juice()
	_apply_settings()
	_refresh_overlay()
	_notice_remaining = 0.0


func _read_human_input(delta: float) -> void:
	if _interrupted or _pause_panel.visible or is_instance_valid(_settings_panel):
		return
	for seat in range(4):
		if controller.seats[seat]["kind"] != "human":
			continue
		var device: String = controller.seats[seat]["device"]
		var sign_dir: float = RoundController.INPUT_SIGN[seat]
		match device:
			"keyboard":
				var axis := InputSetup.device_strength(InputSetup.ACTION_CW) - InputSetup.device_strength(InputSetup.ACTION_CCW)
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
					var buttons := InputSetup.device_strength(InputSetup.ACTION_CW, pad) - InputSetup.device_strength(InputSetup.ACTION_CCW, pad)
					if not is_zero_approx(buttons):
						axis = buttons
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
			var center: Vector2 = controller.rules.positions[seat]
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
	environment.environment = ArenaLook.build_environment()
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 32, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	_floor_mat = ArenaLook.floor_material()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(38, 38)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = _floor_mat
	add_child(floor_node)

	for seat in range(4):
		var center: Vector2 = controller.rules.positions[seat]
		var origin3 := Vector3(center.x, 0, center.y)
		var keep := Node3D.new()
		keep.position = origin3
		add_child(keep)
		var core_mat := ArenaLook.keep_material(seat)
		var keep_pivot := Node3D.new()
		var gilded: bool = controller.seats[seat]["kind"] == "human" and GameSession.profile.data["keep_skin"] == "gilded"
		for lod in range(KEEP_SCENES.size()):
			var imported: Node3D = KEEP_SCENES[lod].instantiate()
			var source := imported.find_child("Keep", true, false) as MeshInstance3D
			var core := MeshInstance3D.new()
			core.name = "KeepLOD%d" % lod
			core.mesh = source.mesh
			imported.free()
			core.set_surface_override_material(0, core_mat)
			core.scale.y = 2.0 / 1.6 if gilded else 1.0
			core.visibility_range_begin = KEEP_LOD_DISTANCES[lod]
			core.visibility_range_end = KEEP_LOD_DISTANCES[lod + 1]
			keep_pivot.add_child(core)
		keep.add_child(keep_pivot)
		_keep_nodes.append(keep_pivot)
		_core_mats.append(core_mat)

		var walls: Array = []
		for sector in range(3):
			var angle := -PI / 2.0 + sector * TAU / 3.0
			var wall := MeshInstance3D.new()
			wall.mesh = ArcMesh.build(0.9, 1.25, 1.2, WALL_HALF_ARC * 0.92)
			wall.rotation.y = -angle
			wall.material_override = ArenaLook.wall_material()
			keep.add_child(wall)
			walls.append(wall)
		_wall_nodes.append(walls)

		var shield_pivot := Node3D.new()
		var aurora: bool = controller.seats[seat]["kind"] == "human" and GameSession.profile.data["shield_skin"] == "aurora"
		var shield_mat := ArenaLook.shield_material(seat)
		_shield_mats.append(shield_mat)
		for lod in range(SHIELD_SCENES.size()):
			var imported: Node3D = SHIELD_SCENES[lod].instantiate()
			var source := imported.find_child("Shield", true, false) as MeshInstance3D
			var shield := MeshInstance3D.new()
			shield.name = "ShieldLOD%d" % lod
			shield.mesh = source.mesh
			if seat == 0:
				_normal_shield_meshes.append(source.mesh)
				_small_shield_meshes.append(_compressed_shield(source.mesh))
			imported.free()
			shield.set_surface_override_material(0, shield_mat)
			shield.scale.y = 1.0 / 0.7 if aurora else 1.0
			shield.visibility_range_begin = SHIELD_LOD_DISTANCES[lod]
			shield.visibility_range_end = SHIELD_LOD_DISTANCES[lod + 1]
			shield_pivot.add_child(shield)
		keep.add_child(shield_pivot)
		_shield_nodes.append(shield_pivot)

	_ball = MeshInstance3D.new()
	# ponytail: orb uses one reviewed LOD; add farther LODs after rendered frame-budget checks.
	var orb_scene: PackedScene = preload("res://assets/models/orb.glb")
	var imported_orb: Node3D = orb_scene.instantiate()
	var orb_mesh: MeshInstance3D = imported_orb.get_child(0) as MeshInstance3D
	_ball.mesh = orb_mesh.mesh
	imported_orb.free()
	_ball.scale = Vector3.ONE * 0.35
	_ball.material_override = ArenaLook.ball_material()
	_ball_emission = _ball.material_override.emission
	add_child(_ball)
	_ball_nodes.append(_ball)
	for index in range(1, MatchRules.MAX_BALLS):
		var extra := MeshInstance3D.new()
		extra.mesh = _ball.mesh
		extra.scale = _ball.scale
		extra.material_override = ArenaLook.ball_material()
		extra.visible = false
		add_child(extra)
		_ball_nodes.append(extra)
	_build_items()
	_build_rails()

	_camera = Camera3D.new()
	add_child(_camera)
	_camera.position = CAMERA_POSITION
	_camera.fov = CAMERA_BASE_FOV
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.current = true
	_frame_arena()
	_build_impact_juice()


func _compressed_shield(mesh: Mesh) -> ArrayMesh:
	var compressed := ArrayMesh.new()
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL].duplicate()
		for index in range(vertices.size()):
			var angle := atan2(vertices[index].z, vertices[index].x)
			var turn := angle * (MatchRules.SHRINK_SCALE - 1.0)
			vertices[index] = vertices[index].rotated(Vector3.UP, -turn)
			normals[index] = normals[index].rotated(Vector3.UP, -turn)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		compressed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		compressed.surface_set_material(surface, mesh.surface_get_material(surface))
	return compressed


func _build_items() -> void:
	var colors := [Color("c49bff"), Color("ffcb52"), Color("ff729d")]
	var labels := ["SPLIT", "SPEED", "SHRINK"]
	for index in range(controller.rules.items.size()):
		var item: Dictionary = controller.rules.items[index]
		var pivot := Node3D.new()
		var point: Vector2 = item["position"]
		pivot.position = Vector3(point.x, 0.6, point.y)
		var body := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = MatchRules.ITEM_RADIUS
		mesh.height = MatchRules.ITEM_RADIUS * 2.0
		body.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[index]
		material.emission_enabled = true
		material.emission = colors[index]
		material.emission_energy_multiplier = 1.8
		body.material_override = material
		pivot.add_child(body)
		var label := Label3D.new()
		label.text = labels[index]
		label.position.y = 1.6
		label.font_size = 48
		label.pixel_size = 0.018
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		pivot.add_child(label)
		add_child(pivot)
		_item_nodes.append(pivot)


func _build_rails() -> void:
	for side in range(4):
		var rail := MeshInstance3D.new()
		var box := BoxMesh.new()
		var horizontal := side < 2
		box.size = Vector3(controller.bounds.x * 2.0 if horizontal else 0.12, 0.12,
			0.12 if horizontal else controller.bounds.y * 2.0)
		rail.mesh = box
		var direction := -1.0 if side % 2 == 0 else 1.0
		rail.position = Vector3(0, 0.06, direction * controller.bounds.y) if horizontal else Vector3(direction * controller.bounds.x, 0.06, 0)
		rail.material_override = ArenaLook.wall_material()
		add_child(rail)


func _build_impact_juice() -> void:
	for index in range(IMPACT_POOL_SIZE):
		var burst := ArenaLook.impact_particles()
		burst.name = "ImpactBurst%d" % index
		burst.amount = ArenaLook.IMPACT_PARTICLE_AMOUNT * 2
		add_child(burst)
		_impact_pool.append(burst)
	_wall_tone = ArenaLook.impact_pcm("wall")
	_core_tone = ArenaLook.impact_pcm("core")
	_impact_audio = AudioStreamPlayer.new()
	_impact_audio.bus = "SFX"
	_impact_audio.volume_db = ArenaLook.impact_tone_db()
	add_child(_impact_audio)


func _play_impact(event: Dictionary) -> void:
	var kind: String = event["kind"]
	var seat: int = event["seat"]
	var center: Vector2 = controller.rules.positions[seat]
	var impact_position := Vector3(center.x, 0.8, center.y)
	var core_hit := kind == "core"
	if not core_hit:
		var sector: int = event["wall"]
		# Match the visible arc midpoint used by _build_world().
		var angle := -PI / 2.0 + sector * TAU / 3.0
		impact_position += Vector3(cos(angle), 0, sin(angle)) * MatchRules.WALL_RADIUS
		impact_position.y = 0.6
	if not _reduced_motion():
		var burst: GPUParticles3D = _impact_pool[_next_impact]
		_next_impact = (_next_impact + 1) % IMPACT_POOL_SIZE
		burst.position = impact_position
		burst.amount_ratio = 1.0 if core_hit else 0.5
		var process: ParticleProcessMaterial = burst.process_material
		process.initial_velocity_min = 3.5 if core_hit else 2.0
		process.initial_velocity_max = 7.0 if core_hit else 5.0
		burst.restart()
		burst.emitting = true
		_shake_remaining = SHAKE_SECONDS
		_shake_strength = maxf(_shake_strength, 0.24 if core_hit else 0.09)
	_impact_audio.stream = _core_tone if core_hit else _wall_tone
	var difficulty: int = controller.seats[seat]["difficulty"]
	_impact_audio.pitch_scale = 0.95 + 0.05 * difficulty if controller.seats[seat]["kind"] == "bot" else 1.0
	_impact_audio.play()


func _update_impact_juice(delta: float) -> void:
	_shake_remaining = maxf(0.0, _shake_remaining - delta)
	if _shake_remaining <= 0.0:
		_camera.position = _camera_rest_position
		_shake_strength = 0.0
		_shake_phase = 0.0
		return
	_shake_phase += delta
	var envelope := _shake_strength * pow(_shake_remaining / SHAKE_SECONDS, 2.0)
	var offset := _camera.basis.x * sin(_shake_phase * 83.0) + _camera.basis.y * cos(_shake_phase * 107.0) * 0.6
	_camera.position = _camera_rest_position + offset * envelope


func _reset_impact_juice() -> void:
	_shake_remaining = 0.0
	_shake_strength = 0.0
	_shake_phase = 0.0
	_camera.position = _camera_rest_position
	_impact_audio.stop()
	for burst in _impact_pool:
		burst.restart()
		burst.emitting = false
	_next_impact = 0


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	var safe := _hud_safe_margins()

	var top := VBoxContainer.new()
	_top = top
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = safe.x
	top.offset_top = safe.y
	top.offset_right = -safe.z
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud.add_child(top)
	# Four seat readouts never fit a 360px phone in one row; two columns keep
	# every label on-screen without shrinking text below readable size.
	var narrow := get_viewport().get_visible_rect().size.x < 640.0
	var strip := GridContainer.new()
	_strip = strip
	strip.columns = 2 if narrow else 4
	top.add_child(strip)
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
	_center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 46)
	_center_label.add_theme_color_override("font_color", Color("f2e6c8"))
	_hud.add_child(_center_label)

	var pause_button := Button.new()
	_pause_button = pause_button
	pause_button.text = "II"
	pause_button.custom_minimum_size = Vector2(56, 56)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -64 - safe.z
	pause_button.offset_top = 8 + safe.y
	pause_button.offset_right = -8 - safe.z
	pause_button.offset_bottom = 64 + safe.y
	pause_button.pressed.connect(func() -> void: _set_paused(not controller.paused))
	_hud.add_child(pause_button)
	_footer = VBoxContainer.new()
	_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_footer.alignment = BoxContainer.ALIGNMENT_END
	_hud.add_child(_footer)
	_effect_label = Label.new()
	_effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.add_child(_effect_label)
	var bump_center := CenterContainer.new()
	_footer.add_child(bump_center)
	_bump_row = GridContainer.new()
	_bump_row.columns = 4
	bump_center.add_child(_bump_row)
	for seat in range(4):
		if controller.seats[seat]["kind"] != "human":
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(140, 48)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: controller.bump(seat))
		button.clip_text = true
		_bump_row.add_child(button)
		_bump_buttons[seat] = button

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
	_button(pause_column, "Settings", func() -> void:
		if not is_instance_valid(_settings_panel):
			_settings_panel = SettingsPanel.new()
			_hud.add_child(_settings_panel)
	)
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
	panel.offset_left = -size.x / 2.0
	panel.offset_right = size.x / 2.0
	panel.offset_top = -size.y / 2.0
	panel.offset_bottom = size.y / 2.0
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
			_overlay_lines.remove_child(child)
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
		_label(_overlay_lines, "%d local stars earned" % GameSession.profile.data["stars"])
		if GameSession.profile.error_message != "":
			_label(_overlay_lines, GameSession.profile.error_message)
		_overlay.visible = true
		_layout_hud()
	else:
		_overlay.visible = false


func _on_match_event(event: Dictionary) -> void:
	if event["kind"] == "bump" or event["kind"] == "item":
		_notice = "POWER BUMP!" if event["kind"] == "bump" else (
			{"split": "MULTIBALL!", "speed": "SPEED BOOST!", "shrink": "SMALL SHIELDS!"}[event["item"]])
		_notice_remaining = 1.5
		var point: Vector2 = event["position"]
		if not _reduced_motion():
			var burst := _impact_pool[_next_impact]
			_next_impact = (_next_impact + 1) % IMPACT_POOL_SIZE
			burst.position = Vector3(point.x, 0.7, point.y)
			burst.restart()
			burst.emitting = true
		_impact_audio.stream = _wall_tone
		_impact_audio.pitch_scale = 1.4
		_impact_audio.play()
	if event["kind"] == "round_over" and controller.state == RoundController.State.ROUND_OVER:
		GameSession.record_round(controller)
		_refresh_overlay()
	if event["kind"] == "core":
		var dead: int = event["seat"]
		_core_mats[dead].albedo_color = Color("3d434b")
		_core_mats[dead].emission_enabled = false
		for wall in _wall_nodes[dead]:
			wall.visible = false
		_shield_nodes[dead].visible = false
	if event["kind"] == "wall" or event["kind"] == "core":
		_play_impact(event)


func _sync_visuals() -> void:
	for seat in range(4):
		_shield_nodes[seat].visible = controller.rules.keeps[seat]["alive"]
		var angle: float = controller.rules.keeps[seat]["shield_angle"]
		_shield_nodes[seat].rotation.y = -angle
		for lod in range(SHIELD_SCENES.size()):
			var shield: MeshInstance3D = _shield_nodes[seat].get_child(lod)
			shield.mesh = _small_shield_meshes[lod] if controller.rules.shrink_remaining > 0.0 else _normal_shield_meshes[lod]
		_shield_mats[seat].emission_energy_multiplier = 4.0 if controller.rules.bump_windows[seat] > 0.0 else 1.6
		var walls: Array = controller.rules.keeps[seat]["walls"]
		for sector in range(3):
			_wall_nodes[seat][sector].visible = walls[sector] and controller.rules.keeps[seat]["alive"]
	for index in range(_ball_nodes.size()):
		var node := _ball_nodes[index]
		node.visible = index < controller.rules.balls.size()
		if not node.visible:
			continue
		var ball: Dictionary = controller.rules.balls[index]
		var point: Vector2 = ball["position"]
		node.position = Vector3(point.x, 0.55, point.y)
		var material: StandardMaterial3D = node.material_override
		material.emission = Color("ffb342") if ball["boost"] > 0.0 else _ball_emission
	for index in range(_item_nodes.size()):
		_item_nodes[index].visible = controller.rules.items[index]["cooldown"] <= 0.0


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
	for seat in _bump_buttons:
		var button: Button = _bump_buttons[seat]
		var cooldown: float = controller.rules.bump_cooldowns[seat]
		var device: String = controller.seats[seat]["device"]
		var hint := "SPACE" if device == "keyboard" else ("RMB" if device == "mouse" else ("A" if device.begins_with("joy_") else "TAP"))
		button.text = "S%d BUMP\n%s" % [seat + 1, hint] if cooldown <= 0.0 else "S%d BUMP\n%.1fs" % [seat + 1, cooldown]
		button.disabled = cooldown > 0.0 or controller.paused or controller.state != RoundController.State.PLAYING or not controller.rules.keeps[seat]["alive"]
	var boosted := 0.0
	for ball in controller.rules.balls:
		boosted = maxf(boosted, ball["boost"])
	var effects := PackedStringArray()
	if _notice_remaining > 0.0:
		effects.append(_notice)
	if controller.rules.balls.size() > 1:
		effects.append("%d BALLS" % controller.rules.balls.size())
	if boosted > 0.0:
		effects.append("BOOST %.1fs" % boosted)
	if controller.rules.shrink_remaining > 0.0:
		effects.append("SMALL SHIELDS %.1fs" % controller.rules.shrink_remaining)
	_effect_label.text = " | ".join(effects) if not effects.is_empty() else "Time your BUMP just before the ball hits your shield"


func _reduced_motion() -> bool:
	return GameSession.settings.values["reduced_motion"]


func _apply_settings() -> void:
	var contrast: bool = GameSession.settings.values["high_contrast"]
	var ui_theme := GameSession.settings.ui_theme()
	for child in _hud.get_children():
		if child is Control:
			child.theme = ui_theme
	for panel in [_pause_panel, _overlay]:
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
		style.bg_color = Color.BLACK if contrast else Color(0.04, 0.09, 0.14, 0.92)
		style.border_color = Color.WHITE
		style.set_border_width_all(2 if contrast else 0)
		panel.add_theme_stylebox_override("panel", style)
	if _reduced_motion():
		_reset_impact_juice()
	_floor_mat.albedo_color = Color("080c14") if contrast else ArenaCatalog.ARENAS[controller.arena_id]["floor"]
	for seat in range(4):
		var tint: Color = SEAT_COLORS[seat]
		var human: bool = controller.seats[seat]["kind"] == "human"
		var gilded: bool = human and GameSession.profile.data["keep_skin"] == "gilded"
		var aurora: bool = human and GameSession.profile.data["shield_skin"] == "aurora"
		_core_mats[seat].albedo_color = tint.lightened(0.35) if contrast else (tint.lerp(Color("ffd577"), 0.55) if gilded else tint.darkened(0.18))
		if not controller.rules.keeps[seat]["alive"]:
			_core_mats[seat].albedo_color = Color("3d434b")
		_shield_mats[seat].albedo_color = Color.WHITE if contrast else tint.lightened(0.45 if aurora else 0.12)
		_shield_mats[seat].emission = tint.lightened(0.5) if aurora else tint
		for wall in _wall_nodes[seat]:
			wall.material_override.albedo_color = Color.WHITE if contrast else Color("91a5b8")
	_layout_hud()


func _frame_arena() -> void:
	if not is_instance_valid(_camera):
		return
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_camera.fov = CAMERA_BASE_FOV
	var safe := _hud_safe_margins()
	var top := safe.y + 100.0
	var bottom := safe.w + 100.0
	if is_instance_valid(_top):
		top = _top.position.y + _top.size.y + 16.0
	if is_instance_valid(_footer):
		bottom = size.y - _footer.position.y + 16.0
	var tangent := tan(deg_to_rad(CAMERA_BASE_FOV) * 0.5)
	var vertical_room := maxf(0.1, 1.0 - (top + bottom) / size.y)
	var center_offset := (bottom - top) / size.y
	var horizontal_room := maxf(0.1, 1.0 - 2.0 * (maxf(safe.x, safe.z) + 16.0) / size.x)
	var direction := CAMERA_POSITION.normalized()
	var basis_inverse := _camera.global_basis.inverse()
	var distance := 0.0
	# Fit the actual rail envelope and keep heights, including perspective depth.
	for x in [-controller.bounds.x - 0.7, controller.bounds.x + 0.7]:
		for z in [-controller.bounds.y - 0.7, controller.bounds.y + 0.7]:
			for y in [0.0, 3.0]:
				var local: Vector3 = basis_inverse * Vector3(x, y, z)
				var depth := Vector3(x, y, z).dot(direction)
				distance = maxf(distance, depth + absf(local.x) / (tangent * size.x / size.y * horizontal_room))
				distance = maxf(distance, (local.y / tangent + (1.0 - 2.0 * top / size.y) * depth) / vertical_room)
				distance = maxf(distance, (-local.y / tangent + (1.0 - 2.0 * bottom / size.y) * depth) / vertical_room)
	_camera_rest_position = direction * distance - _camera.global_basis.y * center_offset * distance * tangent
	_camera.position = _camera_rest_position
	_camera.far = maxf(100.0, distance + 60.0)


func _layout_hud() -> void:
	if not is_instance_valid(_top):
		return
	var scale_value := float(GameSession.settings.values["hud_scale"])
	var narrow := get_viewport().get_visible_rect().size.x < 640.0 * scale_value
	var safe := _hud_safe_margins()
	_strip.columns = 2 if narrow else 4
	_top.offset_left = safe.x
	_top.offset_top = safe.y
	_top.offset_right = -safe.z - 64.0 * scale_value
	_pause_button.offset_left = -safe.z - 56.0 * scale_value
	_pause_button.offset_top = safe.y
	_pause_button.offset_right = -safe.z
	_pause_button.offset_bottom = safe.y + 56.0 * scale_value
	_pause_button.custom_minimum_size = Vector2.ONE * 56.0 * scale_value
	_footer.offset_left = safe.x
	_footer.offset_right = -safe.z
	_bump_row.columns = 2 if narrow else 4
	_footer.offset_bottom = -safe.w
	_footer.offset_top = -safe.w - _footer.get_combined_minimum_size().y
	var contrast: bool = GameSession.settings.values["high_contrast"]
	for seat in range(4):
		_seat_labels[seat].add_theme_font_size_override("font_size", roundi((13.0 if narrow else 16.0) * scale_value))
		_seat_labels[seat].add_theme_color_override("font_color", Color.WHITE if contrast else SEAT_COLORS[seat])
	_center_label.add_theme_font_size_override("font_size", roundi((26.0 if narrow else 46.0) * scale_value))
	_center_label.add_theme_color_override("font_color", Color.WHITE if contrast else Color("f2e6c8"))
	_overlay_title.add_theme_font_size_override("font_size", roundi(30.0 * scale_value))
	for panel in [_pause_panel, _overlay]:
		var minimum: Vector2 = panel.get_combined_minimum_size()
		var width := minf(maxf(minimum.x, 280.0), get_viewport().get_visible_rect().size.x - safe.x - safe.z)
		panel.offset_left = -width / 2.0
		panel.offset_right = width / 2.0
		panel.offset_top = -minimum.y / 2.0
		panel.offset_bottom = minimum.y / 2.0
	_frame_arena()


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


func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(action)
	parent.add_child(button)


func _label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
