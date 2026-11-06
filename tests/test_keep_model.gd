extends GutTest
## Issue #14: imported asset and deterministic runtime contracts, not rendered quality.

const GENERATOR = preload("res://tools/gen_keep.gd")
const ROUND_SCENE: PackedScene = preload("res://scenes/round.tscn")
const LODS: Array[PackedScene] = [
	preload("res://assets/models/keep_lod0.glb"),
	preload("res://assets/models/keep_lod1.glb"),
	preload("res://assets/models/keep_lod2.glb"),
]
const TRIANGLES := [5344, 1376, 384]
const BUDGETS := [6000, 1500, 400]

var _previous_profile: ProfileStore
var _previous_settings: Dictionary
var _previous_seats: Array[Dictionary]


func before_each() -> void:
	_previous_profile = GameSession.profile
	_previous_settings = GameSession.settings.values.duplicate(true)
	_previous_seats = SeatRouting.duplicate_seats(GameSession.seats)
	GameSession.profile = ProfileStore.new("user://unused_keep_model_test.json")
	GameSession.seats = SeatRouting.make_solo_seats(0, false)
	GameSession.settings.apply(ProfileStore.default_settings())


func after_each() -> void:
	GameSession.profile = _previous_profile
	GameSession.seats = _previous_seats
	GameSession.settings.apply(_previous_settings)


func test_imported_lods_have_budgeted_stone_and_metal_surfaces() -> void:
	for lod in range(3):
		var root: Node3D = autofree(LODS[lod].instantiate())
		var keep := root.find_child("Keep", true, false) as MeshInstance3D
		assert_not_null(keep)
		if keep == null:
			continue
		var mesh := keep.mesh as ArrayMesh
		assert_not_null(mesh)
		if mesh == null:
			continue
		assert_eq(mesh.get_surface_count(), 4, "seat band, limestone, mortar and forged details")
		var triangles := 0
		for surface in range(mesh.get_surface_count()):
			assert_eq(mesh.surface_get_primitive_type(surface), Mesh.PRIMITIVE_TRIANGLES)
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = (
				PackedInt32Array() if arrays[Mesh.ARRAY_INDEX] == null else arrays[Mesh.ARRAY_INDEX]
			)
			var count := vertices.size() if indices.is_empty() else indices.size()
			assert_gt(count, 0)
			assert_eq(count % 3, 0)
			assert_eq(normals.size(), vertices.size())
			triangles += count / 3
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			assert_not_null(material)
			if material == null:
				continue
			assert_eq(material.resource_name, ["SeatMetal", "Limestone", "Mortar", "ForgedIron"][surface])
			assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL)
			assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED)
			assert_false(material.emission_enabled)
			assert_almost_eq(material.metallic, [0.5, 0.0, 0.0, 0.85][surface], 0.001)
			assert_almost_eq(material.roughness, [0.32, 0.86, 0.95, 0.30][surface], 0.001)
		assert_eq(triangles, TRIANGLES[lod], "inspect actual imported triangles")
		assert_lte(triangles, BUDGETS[lod])
		var authored: ArrayMesh = GENERATOR.build_mesh(lod)
		assert_eq(mesh.get_faces().size(), authored.get_faces().size())
		assert_almost_eq(mesh.get_aabb().position, authored.get_aabb().position, Vector3.ONE * 0.0001)
		assert_almost_eq(mesh.get_aabb().size, authored.get_aabb().size, Vector3.ONE * 0.0001)
		_assert_visual_only(root)


func test_imported_dimensions_and_crenellations_keep_a_ground_center_pivot() -> void:
	for lod in range(3):
		var root: Node3D = autofree(LODS[lod].instantiate())
		var keep := root.find_child("Keep", true, false) as MeshInstance3D
		var bounds := keep.mesh.get_aabb()
		assert_almost_eq(bounds.position, Vector3(-0.65, 0, -0.65), Vector3.ONE * 0.0001)
		assert_almost_eq(bounds.size, Vector3(1.3, 1.6, 1.3), Vector3.ONE * 0.0001)
		var teeth: Dictionary = {}
		var has_crenel_floor := false
		var within_radius := true
		var open_crenels := true
		for vertex in keep.mesh.get_faces():
			within_radius = within_radius and Vector2(vertex.x, vertex.z).length() <= 0.6501
			has_crenel_floor = has_crenel_floor or is_equal_approx(vertex.y, 1.36)
			if vertex.y > 1.59:
				var tooth := posmod(roundi(atan2(vertex.z, vertex.x) * 8.0 / TAU), 8)
				teeth[tooth] = true
				var offset := absf(angle_difference(atan2(vertex.z, vertex.x), tooth * TAU / 8.0))
				open_crenels = open_crenels and offset <= PI / 8.0 * 0.53 + 0.0001
		assert_true(within_radius)
		assert_true(open_crenels, "open gaps separate crown teeth")
		assert_eq(teeth.size(), 8, "all LODs retain eight crenellations")
		assert_true(has_crenel_floor)


func test_round_wires_all_lods_seat_tints_ranges_and_layout_origins() -> void:
	for id in ArenaCatalog.IDS:
		GameSession.profile.data["arena"] = id
		var arena := _arena()
		for seat in range(4):
			var pivot: Node3D = arena._keep_nodes[seat]
			var center: Vector2 = arena.controller.rules.positions[seat]
			assert_eq(pivot.transform, Transform3D.IDENTITY)
			assert_eq(pivot.get_parent().position, Vector3(center.x, 0, center.y))
			assert_eq(pivot.get_child_count(), 3)
			assert_eq(arena._core_mats[seat].albedo_color, ArenaLook.SEAT_COLORS[seat].darkened(0.18))
			for lod in range(3):
				var core: MeshInstance3D = pivot.get_child(lod)
				var imported: Node3D = autofree(LODS[lod].instantiate())
				var source := imported.find_child("Keep", true, false) as MeshInstance3D
				assert_eq(core.mesh, source.mesh)
				assert_eq(core.transform, Transform3D.IDENTITY)
				assert_null(core.material_override, "preserve the stone and forged material layers")
				assert_eq(core.get_surface_override_material(0), arena._core_mats[seat])
				for surface in range(1, 4):
					assert_null(core.get_surface_override_material(surface))
				assert_eq(core.visibility_range_begin, [0.0, 40.0, 60.0][lod])
				assert_eq(core.visibility_range_end, [40.0, 60.0, 0.0][lod])
				assert_eq(core.visibility_range_begin_margin, 0.0)
				assert_eq(core.visibility_range_end_margin, 0.0)
				assert_eq(core.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED)
			_assert_visual_only(pivot)
		arena.free()


func test_gilded_contrast_elimination_and_reset_reach_every_lod() -> void:
	for human in range(4):
		GameSession.seats = SeatRouting.make_default_seats()
		assert_eq(SeatRouting.claim(GameSession.seats, human, "keyboard"), "")
		GameSession.profile.data["keep_skin"] = "classic"
		var classic := _arena()
		GameSession.profile.data["keep_skin"] = "gilded"
		var gilded := _arena()
		for seat in range(4):
			var tint: Color = ArenaLook.SEAT_COLORS[seat]
			assert_eq(gilded._core_mats[seat].albedo_color,
				tint.lerp(Color("ffd577"), 0.55) if seat == human else tint.darkened(0.18))
			for lod in range(3):
				var base: MeshInstance3D = classic._keep_nodes[seat].get_child(lod)
				var skinned: MeshInstance3D = gilded._keep_nodes[seat].get_child(lod)
				assert_eq(base.mesh, skinned.mesh)
				assert_eq(skinned.position, Vector3.ZERO)
				assert_eq(skinned.scale, Vector3(1, 1.25 if seat == human else 1.0, 1))
		assert_eq(classic.controller.rules.keeps, gilded.controller.rules.keeps)
		var settings := ProfileStore.default_settings()
		settings["high_contrast"] = true
		GameSession.settings.apply(settings)
		for seat in range(4):
			assert_eq(gilded._core_mats[seat].albedo_color, ArenaLook.SEAT_COLORS[seat].lightened(0.35))
		gilded.controller.rules.keeps[human]["alive"] = false
		gilded._on_match_event({"kind": "core", "seat": human, "wall": -1})
		for lod in range(3):
			var core: MeshInstance3D = gilded._keep_nodes[human].get_child(lod)
			assert_eq(core.get_surface_override_material(0).albedo_color, Color("3d434b"))
		GameSession.settings.apply(ProfileStore.default_settings())
		gilded._restart()
		assert_eq(gilded._core_mats[human].albedo_color,
			ArenaLook.SEAT_COLORS[human].lerp(Color("ffd577"), 0.55))
		classic.free()
		gilded.free()


func test_visual_radius_does_not_change_deterministic_core_hit_distance() -> void:
	assert_eq(MatchRules.CORE_RADIUS, 0.45)
	for skin in ["classic", "gilded"]:
		GameSession.profile.data["keep_skin"] = skin
		var arena := _arena()
		for seat in range(4):
			arena._restart()
			var rules: MatchRules = arena.controller.rules
			rules.keeps[seat]["walls"] = [false, false, false]
			rules.set_shield_angle(seat, PI / 2.0)
			var center: Vector2 = rules.positions[seat]
			rules.ball_position = center + Vector2(-0.70, 0)
			rules.ball_velocity = Vector2(10, 0)
			assert_eq(rules.step(0.015), [], "visual base radius 0.65 must not collide")
			var events := rules.step(0.02)
			assert_false(events.is_empty())
			if events.is_empty():
				continue
			assert_eq(events[0]["kind"], "core")
			assert_eq(events[0]["seat"], seat)
			assert_almost_eq(rules.ball_position, center + Vector2(-0.45, 0), Vector2.ONE * 0.0001)
			assert_eq(rules.ball_velocity, Vector2.ZERO)
		arena.free()


func _assert_visual_only(node: Node) -> void:
	assert_false(node is CollisionObject3D)
	assert_false(node is CollisionShape3D)
	assert_false(node is Skeleton3D)
	assert_false(node is AnimationPlayer)
	if node is Node3D:
		assert_eq(node.transform, Transform3D.IDENTITY)
	for child in node.get_children():
		_assert_visual_only(child)


func _arena() -> Node3D:
	var arena: Node3D = ROUND_SCENE.instantiate()
	add_child_autofree(arena)
	arena.set_process(false)
	return arena
