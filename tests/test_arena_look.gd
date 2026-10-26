extends GutTest
## Issue #4 gates: pure PBR/PCM/particle configuration and scene impact wiring.
## No GPU rendering, particle simulation, listening or frame-budget claim.

const ROUND_SCENE: PackedScene = preload("res://scenes/round.tscn")


func test_environment_is_configured_for_forward_plus() -> void:
	var environment := ArenaLook.build_environment()
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "forward_plus")
	assert_eq(environment.background_mode, Environment.BG_COLOR)
	assert_eq(environment.background_color, Color("08131d"))
	assert_eq(environment.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	assert_gt(environment.ambient_light_energy, 0.0)
	assert_true(environment.glow_enabled)
	assert_almost_eq(environment.glow_intensity, 0.85, 0.001)
	assert_almost_eq(environment.glow_bloom, 0.12, 0.001)
	assert_gt(environment.glow_hdr_threshold, 1.0)
	var glow_weight := 0.0
	for level in range(7):
		glow_weight += environment.get_glow_level(level)
	assert_gt(glow_weight, 0.0, "glow must have active bloom levels")
	assert_true(environment.sdfgi_enabled)
	assert_false(environment.sdfgi_read_sky_light, "the color background has no sky to read")
	assert_almost_eq(environment.sdfgi_energy, 1.15, 0.001)
	assert_gt(environment.sdfgi_bounce_feedback, 0.0)
	assert_eq(environment.tonemap_mode, Environment.TONE_MAPPER_ACES)
	assert_true(environment.adjustment_enabled)
	assert_gt(environment.adjustment_contrast, 1.0)


func test_floor_is_matte_and_walls_are_brushed_metal() -> void:
	var floor_material := ArenaLook.floor_material()
	_assert_pbr(floor_material, 0.1, 0.25, 0.75, 0.9)
	assert_false(floor_material.emission_enabled)
	var wall_material := ArenaLook.wall_material()
	_assert_pbr(wall_material, 0.55, 0.75, 0.3, 0.5)
	assert_false(wall_material.emission_enabled)
	assert_ne(floor_material.albedo_color, wall_material.albedo_color)


func test_keeps_and_emissive_shields_preserve_distinct_seat_tints() -> void:
	var expected_colors: Array[Color] = [
		Color("e05c5c"), Color("e0b35c"), Color("5ce0a8"), Color("5c9be0"),
	]
	assert_eq(ArenaLook.SEAT_COLORS.size(), 4)
	for seat in range(4):
		var tint: Color = expected_colors[seat]
		assert_eq(ArenaLook.SEAT_COLORS[seat], tint)
		var keep := ArenaLook.keep_material(seat)
		_assert_pbr(keep, 0.4, 0.6, 0.25, 0.4)
		assert_eq(keep.albedo_color, tint.darkened(0.18))
		var shield := ArenaLook.shield_material(seat)
		_assert_pbr(shield, 0.65, 0.85, 0.15, 0.3)
		assert_eq(shield.albedo_color, tint.lightened(0.12))
		assert_true(shield.emission_enabled)
		assert_eq(shield.emission, tint)
		assert_gt(shield.emission_energy_multiplier, 1.0)
		assert_true(shield.rim_enabled, "rim lighting emphasizes the shield edges")
		for other in range(seat + 1, 4):
			assert_ne(keep.albedo_color, ArenaLook.keep_material(other).albedo_color)
			assert_ne(shield.emission, ArenaLook.shield_material(other).emission)


func test_ball_is_polished_and_emissive() -> void:
	var ball := ArenaLook.ball_material()
	_assert_pbr(ball, 0.35, 0.55, 0.15, 0.3)
	assert_true(ball.emission_enabled)
	assert_gt(ball.emission_energy_multiplier, 2.0)
	assert_ne(ball.emission, Color.BLACK)


func test_builders_return_independent_resources() -> void:
	var first := ArenaLook.keep_material(0)
	var second := ArenaLook.keep_material(0)
	assert_ne(first, second)
	first.albedo_color = Color.BLACK
	assert_ne(second.albedo_color, first.albedo_color)
	var first_environment := ArenaLook.build_environment()
	first_environment.glow_enabled = false
	assert_true(ArenaLook.build_environment().glow_enabled)
	var first_particles: GPUParticles3D = autofree(ArenaLook.impact_particles())
	var second_particles: GPUParticles3D = autofree(ArenaLook.impact_particles())
	assert_ne(first_particles.process_material, second_particles.process_material)
	assert_ne(first_particles.draw_pass_1, second_particles.draw_pass_1)
	assert_ne(first_particles.draw_pass_1.surface_get_material(0),
		second_particles.draw_pass_1.surface_get_material(0))


func test_impact_pcm_is_bounded_mono_pcm_with_no_click_endpoints() -> void:
	var wall := ArenaLook.impact_pcm("wall")
	var core := ArenaLook.impact_pcm("core")
	_assert_pcm(wall)
	_assert_pcm(core)
	assert_ne(wall.data, core.data)
	assert_eq(wall.data, ArenaLook.impact_pcm("wall").data, "tone generation must be deterministic")
	assert_eq(core.data, ArenaLook.impact_pcm("core").data)
	assert_lt(_positive_crossings(core.data), _positive_crossings(wall.data),
		"core destruction must have a lower thud than a wall impact")
	assert_between(ArenaLook.impact_tone_db(), -24.0, -10.0, "impact volume stays modest")


func test_impact_particles_are_an_idle_one_shot_emissive_burst() -> void:
	var particles: GPUParticles3D = autofree(ArenaLook.impact_particles())
	assert_null(particles.get_parent(), "the factory must not add nodes to the scene tree")
	assert_false(particles.emitting)
	assert_true(particles.one_shot)
	assert_gt(particles.amount, 0)
	assert_between(particles.lifetime, 0.2, 0.6)
	assert_eq(particles.explosiveness, 1.0)
	assert_false(particles.local_coords, "pool repositioning must not drag existing sparks")
	assert_true(particles.process_material is ParticleProcessMaterial)
	var process: ParticleProcessMaterial = particles.process_material
	assert_lt(process.gravity.y, 0.0)
	assert_gt(process.spread, 0.0)
	assert_gt(process.initial_velocity_min, 0.0)
	assert_gt(process.initial_velocity_max, process.initial_velocity_min)
	assert_not_null(particles.draw_pass_1)
	var material: StandardMaterial3D = particles.draw_pass_1.surface_get_material(0)
	assert_not_null(material)
	assert_true(material.emission_enabled)
	assert_gt(material.emission_energy_multiplier, 1.0)


func test_round_uses_arena_look_resources() -> void:
	var arena := _arena()
	var environment: WorldEnvironment = arena.get_child(0)
	assert_true(environment.environment.glow_enabled)
	assert_true(environment.environment.sdfgi_enabled)
	var floor_node: MeshInstance3D = arena.get_child(2)
	var floor_material: StandardMaterial3D = floor_node.material_override
	assert_eq(floor_material.roughness, ArenaLook.floor_material().roughness)
	for seat in range(4):
		var keep_material: StandardMaterial3D = arena._core_mats[seat]
		assert_eq(keep_material.albedo_color, ArenaLook.keep_material(seat).albedo_color)
		var walls: Array = arena._wall_nodes[seat]
		var wall: MeshInstance3D = walls[0]
		var wall_material: StandardMaterial3D = wall.material_override
		assert_eq(wall_material.metallic, ArenaLook.wall_material().metallic)
		var shield: MeshInstance3D = arena._shield_nodes[seat].get_child(0)
		var shield_material: StandardMaterial3D = shield.material_override
		assert_true(shield_material.emission_enabled)
		assert_eq(shield_material.emission, ArenaLook.shield_material(seat).emission)
	var ball: MeshInstance3D = arena._ball
	var ball_material: StandardMaterial3D = ball.material_override
	assert_true(ball_material.emission_enabled)


func test_wall_impacts_use_midpoints_and_reuse_a_bounded_pool() -> void:
	var arena := _arena()
	var child_count := arena.get_child_count()
	var ball_before: Vector2 = arena.controller.rules.ball_position
	var ticks_before: int = arena.controller.rules.ticks
	assert_eq(arena._impact_pool.size(), arena.IMPACT_POOL_SIZE)
	for seat in range(4):
		var center: Vector2 = MatchRules.SEAT_POSITIONS[seat]
		for sector in range(3):
			var burst: GPUParticles3D = arena._impact_pool[arena._next_impact]
			arena._on_match_event({"kind": "wall", "seat": seat, "wall": sector})
			var angle := -PI / 2.0 + sector * TAU / 3.0
			var expected := Vector3(center.x, 0.6, center.y)
			expected += Vector3(cos(angle), 0, sin(angle)) * MatchRules.WALL_RADIUS
			assert_true(burst.position.is_equal_approx(expected))
			assert_true(burst.emitting)
			assert_eq(burst.amount_ratio, 0.5)
			assert_eq(arena._impact_audio.stream, arena._wall_tone)
			var entry: Dictionary = arena.controller.seats[seat]
			var difficulty: int = entry["difficulty"]
			var pitch := 0.95 + 0.05 * difficulty if entry["kind"] == "bot" else 1.0
			assert_almost_eq(arena._impact_audio.pitch_scale, pitch, 0.001)
		assert_eq(arena.controller.rules.keeps[seat]["walls"], [true, true, true],
			"feedback must not mutate wall rules")
	assert_eq(arena.get_child_count(), child_count, "impacts must not allocate scene nodes")
	assert_eq(arena.controller.rules.ball_position, ball_before)
	assert_eq(arena.controller.rules.ticks, ticks_before)
	assert_eq(arena._next_impact, 12 % arena.IMPACT_POOL_SIZE)
	assert_eq(arena._impact_audio.volume_db, ArenaLook.impact_tone_db())
	var audio_players := 0
	for child in arena.get_children():
		if child is AudioStreamPlayer:
			audio_players += 1
	assert_eq(audio_players, 1, "all impacts reuse one audio player")


func test_core_destruction_is_bigger_and_keeps_existing_visual_elimination() -> void:
	var arena := _arena()
	var burst: GPUParticles3D = arena._impact_pool[0]
	arena._on_match_event({"kind": "core", "seat": 1, "wall": -1})
	var center: Vector2 = MatchRules.SEAT_POSITIONS[1]
	assert_eq(burst.position, Vector3(center.x, 0.8, center.y))
	assert_eq(burst.amount_ratio, 1.0)
	var process: ParticleProcessMaterial = burst.process_material
	assert_gt(process.initial_velocity_max, 5.0)
	assert_eq(arena._impact_audio.stream, arena._core_tone)
	assert_almost_eq(arena._shake_strength, 0.24, 0.001)
	var core_material: StandardMaterial3D = arena._core_mats[1]
	assert_eq(core_material.albedo_color, Color("3d434b"))
	assert_false(core_material.emission_enabled)
	var shield: Node3D = arena._shield_nodes[1]
	assert_false(shield.visible)
	var walls: Array = arena._wall_nodes[1]
	for wall in walls:
		assert_false(wall.visible)


func test_camera_shake_decays_and_restores_exact_framing() -> void:
	var arena := _arena()
	var camera: Camera3D = arena._camera
	var rest := camera.position
	var rotation := camera.rotation
	arena._on_match_event({"kind": "wall", "seat": 0, "wall": 0})
	assert_almost_eq(arena._shake_remaining, 0.25, 0.001)
	arena._update_impact_juice(0.05)
	assert_ne(camera.position, rest)
	assert_lt(camera.position.distance_to(rest), 0.09)
	arena._update_impact_juice(0.15)
	assert_lt(camera.position.distance_to(rest), 0.01, "shake amplitude must decay")
	arena._update_impact_juice(0.05)
	assert_true(camera.position.is_equal_approx(rest), "shake ends after about 0.25 seconds")
	arena._update_impact_juice(0.01)
	assert_eq(camera.position, rest)
	assert_eq(camera.rotation, rotation, "shake must never change aiming orientation")


func test_visual_shake_does_not_change_mouse_aim() -> void:
	var arena := _arena()
	var camera: Camera3D = arena._camera
	var rest := camera.position
	var center: Vector2 = MatchRules.SEAT_POSITIONS[0]
	arena.controller.seats[0] = {"kind": "human", "device": "mouse", "difficulty": -1}
	# A narrow view puts the headless pointer's ray near the chosen keep.
	camera.fov = 1.0
	camera.look_at(Vector3(center.x, 0, center.y), Vector3.UP)
	var expected: float = arena._mouse_arena_angle()
	assert_true(is_finite(expected), "the pointer must aim inside the keep's input area")
	if not is_finite(expected):
		return
	arena._on_match_event({"kind": "wall", "seat": 0, "wall": 0})
	arena._update_impact_juice(0.05)
	assert_ne(camera.position, rest)
	arena._process(0.0)
	var target: float = arena.controller.targets[0]
	assert_almost_eq(angle_difference(expected, target), 0.0, 0.00001,
		"input uses unshaken framing even while the rendered camera moves")
	assert_ne(camera.position, rest)


func test_unrelated_events_do_not_trigger_feedback_and_round_resets_clear_it() -> void:
	var arena := _arena()
	var kinds: Array[String] = ["serve", "shield", "rail", "win", "round_over"]
	for kind in kinds:
		arena._on_match_event({"kind": kind, "seat": -1})
	assert_eq(arena._next_impact, 0)
	assert_null(arena._impact_audio.stream)
	var resets: Array[StringName] = [&"_restart", &"_rematch"]
	for reset in resets:
		arena._on_match_event({"kind": "wall", "seat": 0, "wall": 0})
		arena._update_impact_juice(0.05)
		arena.call(reset)
		assert_eq(arena._next_impact, 0)
		assert_eq(arena._shake_remaining, 0.0)
		var camera: Camera3D = arena._camera
		assert_eq(camera.position, arena.CAMERA_POSITION)
		assert_false(arena._impact_audio.playing)
		var pool: Array[GPUParticles3D] = arena._impact_pool
		for burst in pool:
			assert_false(burst.emitting)


func _assert_pbr(material: StandardMaterial3D, metal_min: float, metal_max: float, rough_min: float, rough_max: float) -> void:
	assert_between(material.metallic, metal_min, metal_max)
	assert_between(material.roughness, rough_min, rough_max)
	assert_between(material.metallic_specular, 0.3, 0.65)
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL)


func _assert_pcm(stream: AudioStreamWAV) -> void:
	assert_eq(stream.mix_rate, 22050)
	assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_false(stream.stereo)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	var data := stream.data
	assert_eq(data.size(), 5292, "0.12 seconds of mono signed 16-bit PCM")
	if data.is_empty():
		return
	assert_almost_eq(stream.get_length(), 0.12, 0.001)
	assert_eq(data.decode_s16(0), 0)
	assert_eq(data.decode_s16(data.size() - 2), 0)
	var finite := true
	var peak := 0.0
	var max_step := 0.0
	var previous := 0.0
	for offset in range(0, data.size(), 2):
		var sample := float(data.decode_s16(offset)) / 32768.0
		finite = finite and is_finite(sample)
		peak = maxf(peak, absf(sample))
		max_step = maxf(max_step, absf(sample - previous))
		previous = sample
	assert_true(finite, "all decoded samples must be finite")
	assert_between(peak, 0.05, 0.56, "audible but unclipped PCM")
	assert_lt(max_step, 0.06, "no abrupt waveform discontinuity")


func _positive_crossings(data: PackedByteArray) -> int:
	var crossings := 0
	var previous := 0
	for offset in range(0, data.size(), 2):
		var sample := data.decode_s16(offset)
		if previous <= 0 and sample > 0:
			crossings += 1
		previous = sample
	return crossings


func _arena() -> Node3D:
	var node: Node3D = ROUND_SCENE.instantiate()
	add_child_autofree(node)
	node.set_process(false)
	node.controller.set_paused(true)
	return node
