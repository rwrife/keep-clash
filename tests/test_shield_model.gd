extends GutTest
## Issue #15: inspect imported geometry and scene wiring, not rendered quality.

const GENERATOR = preload("res://tools/gen_shield.gd")
const ROUND_SCENE: PackedScene = preload("res://scenes/round.tscn")
const LODS: Array[PackedScene] = [
	preload("res://assets/models/shield_lod0.glb"),
	preload("res://assets/models/shield_lod1.glb"),
	preload("res://assets/models/shield_lod2.glb"),
]
const TRIANGLES := [1532, 556, 268]
const BUDGETS := [4000, 1000, 300]

var _previous_profile: ProfileStore
var _previous_settings: Dictionary
var _previous_seats: Array[Dictionary]


func before_each() -> void:
	_previous_profile = GameSession.profile
	_previous_settings = GameSession.settings.values.duplicate(true)
	_previous_seats = SeatRouting.duplicate_seats(GameSession.seats)
	GameSession.profile = ProfileStore.new("user://unused_shield_model_test.json")
	GameSession.seats = SeatRouting.make_solo_seats(0, false)
	GameSession.settings.apply(ProfileStore.default_settings())


func after_each() -> void:
	GameSession.profile = _previous_profile
	GameSession.seats = _previous_seats
	GameSession.settings.apply(_previous_settings)


func test_imported_lods_have_budgeted_layered_pbr_geometry() -> void:
	for lod in range(LODS.size()):
		var root: Node3D = autofree(LODS[lod].instantiate())
		var shield := root.find_child("Shield", true, false) as MeshInstance3D
		assert_not_null(shield)
		if shield == null:
			continue
		assert_true(shield.mesh is ArrayMesh)
		var mesh := shield.mesh as ArrayMesh
		if mesh == null:
			continue
		assert_eq(mesh.get_surface_count(), 3, "armor, stone backing and forged rim")
		var triangles := 0
		for surface in range(mesh.get_surface_count()):
			assert_eq(mesh.surface_get_primitive_type(surface), Mesh.PRIMITIVE_TRIANGLES)
			var arrays := mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = (
				PackedInt32Array() if arrays[Mesh.ARRAY_INDEX] == null else arrays[Mesh.ARRAY_INDEX]
			)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var count := vertices.size() if indices.is_empty() else indices.size()
			assert_gt(count, 0)
			assert_eq(count % 3, 0)
			assert_eq(normals.size(), vertices.size())
			triangles += count / 3
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			assert_not_null(material)
			if material == null:
				continue
			assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL)
			assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED)
			assert_almost_eq(material.metallic, [0.75, 0.0, 0.85][surface], 0.001)
			assert_almost_eq(material.roughness, [0.24, 0.86, 0.3][surface], 0.001)
			assert_eq(material.emission_enabled, surface == 0)
			if surface == 0:
				assert_almost_eq(material.emission_energy_multiplier, 1.6, 0.001)
		assert_eq(triangles, TRIANGLES[lod], "count actual imported primitives, not declared metadata")
		assert_lte(triangles, BUDGETS[lod])
		var authored: ArrayMesh = GENERATOR.build_mesh(lod)
		assert_eq(mesh.get_faces().size(), authored.get_faces().size(),
			"regeneration must preserve the authored topology budget")
		assert_almost_eq(mesh.get_aabb().position, authored.get_aabb().position, Vector3.ONE * 0.0001)
		assert_almost_eq(mesh.get_aabb().size, authored.get_aabb().size, Vector3.ONE * 0.0001)
		_assert_visual_only_identity_tree(root)


func test_imported_dimensions_match_the_horizontal_collision_arc() -> void:
	for lod in range(LODS.size()):
		var root: Node3D = autofree(LODS[lod].instantiate())
		var shield := root.find_child("Shield", true, false) as MeshInstance3D
		var minimum_radius := INF
		var maximum_radius := 0.0
		var minimum_angle := INF
		var maximum_angle := -INF
		var minimum_y := INF
		var maximum_y := -INF
		var all_in_front := true
		for vertex in shield.mesh.get_faces():
			var radius := Vector2(vertex.x, vertex.z).length()
			var angle := atan2(vertex.z, vertex.x)
			minimum_radius = minf(minimum_radius, radius)
			maximum_radius = maxf(maximum_radius, radius)
			minimum_angle = minf(minimum_angle, angle)
			maximum_angle = maxf(maximum_angle, angle)
			minimum_y = minf(minimum_y, vertex.y)
			maximum_y = maxf(maximum_y, vertex.y)
			all_in_front = all_in_front and vertex.x > 0.0
		assert_true(all_in_front, "the zero-rotation shield faces local +X")
		assert_almost_eq(minimum_radius, MatchRules.SHIELD_RADIUS - 0.16, 0.0001)
		assert_almost_eq(maximum_radius, MatchRules.SHIELD_RADIUS + 0.16, 0.0001)
		assert_almost_eq(maximum_radius - minimum_radius, 0.32, 0.0001)
		assert_almost_eq(minimum_angle, -MatchRules.SHIELD_HALF_ARC * 0.95, 0.0001)
		assert_almost_eq(maximum_angle, MatchRules.SHIELD_HALF_ARC * 0.95, 0.0001)
		assert_almost_eq(minimum_y, 0.0, 0.0001)
		assert_almost_eq(maximum_y, 0.7, 0.0001)


func test_round_uses_all_imported_lods_and_the_existing_keep_pivot() -> void:
	for id in ArenaCatalog.IDS:
		GameSession.profile.data["arena"] = id
		var arena := _arena()
		for seat in range(4):
			var pivot: Node3D = arena._shield_nodes[seat]
			var center: Vector2 = arena.controller.rules.positions[seat]
			assert_eq(pivot.position, Vector3.ZERO, "pivot is the keep origin, not the arc center")
			assert_eq(pivot.get_parent().position, Vector3(center.x, 0, center.y))
			assert_eq(pivot.get_child_count(), 3)
			for lod in range(3):
				var shield: MeshInstance3D = pivot.get_child(lod)
				var imported: Node3D = autofree(LODS[lod].instantiate())
				var source := imported.find_child("Shield", true, false) as MeshInstance3D
				assert_eq(shield.mesh, source.mesh)
				assert_null(shield.material_override, "do not flatten the stone/rim material layers")
				var tint := shield.get_surface_override_material(0) as StandardMaterial3D
				assert_eq(tint, arena._shield_mats[seat])
				assert_true(tint.emission_enabled)
				assert_true(tint.rim_enabled)
				assert_eq(tint.emission, ArenaLook.SEAT_COLORS[seat])
				assert_null(shield.get_surface_override_material(1))
				assert_null(shield.get_surface_override_material(2))
				assert_eq(shield.visibility_range_begin, [0.0, 40.0, 60.0][lod])
				assert_eq(shield.visibility_range_end, [40.0, 60.0, 0.0][lod])
				assert_eq(shield.transform, Transform3D.IDENTITY)
			for angle in [0.0, PI / 2.0, PI, -PI / 2.0, 0.37]:
				arena.controller.rules.set_shield_angle(seat, angle)
				arena._sync_visuals()
				var local_contact := Vector3(MatchRules.SHIELD_RADIUS, 0.35, 0)
				var expected := Vector3(center.x + cos(angle) * MatchRules.SHIELD_RADIUS,
					0.35, center.y + sin(angle) * MatchRules.SHIELD_RADIUS)
				assert_true(pivot.to_global(local_contact).is_equal_approx(expected),
					"negative-Y pivot rotation must match the rules' X/Z arena frame")
		arena.free()


func test_aurora_and_live_contrast_apply_to_every_lod_without_physics_changes() -> void:
	var classic := _arena()
	GameSession.profile.data["shield_skin"] = "aurora"
	var aurora := _arena()
	for seat in range(4):
		for lod in range(3):
			var base: MeshInstance3D = classic._shield_nodes[seat].get_child(lod)
			var skinned: MeshInstance3D = aurora._shield_nodes[seat].get_child(lod)
			assert_eq(base.mesh, skinned.mesh)
			assert_almost_eq(skinned.scale.y, 1.0 / 0.7 if seat == 2 else 1.0, 0.0001)
	assert_ne(classic._shield_mats[2].albedo_color, aurora._shield_mats[2].albedo_color)
	assert_eq(classic.controller.rules.keeps, aurora.controller.rules.keeps)
	assert_eq(classic.controller.rules.ball_position, aurora.controller.rules.ball_position)
	assert_eq(classic.controller.rules.ball_velocity, aurora.controller.rules.ball_velocity)
	var settings := ProfileStore.default_settings()
	settings["high_contrast"] = true
	GameSession.settings.apply(settings)
	for seat in range(4):
		for lod in range(3):
			var shield: MeshInstance3D = aurora._shield_nodes[seat].get_child(lod)
			var tint := shield.get_surface_override_material(0) as StandardMaterial3D
			assert_eq(tint.albedo_color, Color.WHITE)
			_assert_visual_only_identity_tree(shield, false)


func _assert_visual_only_identity_tree(node: Node, check_transform: bool = true) -> void:
	assert_false(node is CollisionObject3D)
	assert_false(node is CollisionShape3D)
	assert_false(node is Skeleton3D)
	assert_false(node is AnimationPlayer)
	if check_transform and node is Node3D:
		assert_eq(node.transform, Transform3D.IDENTITY)
	for child in node.get_children():
		_assert_visual_only_identity_tree(child, check_transform)


func _arena() -> Node3D:
	var arena: Node3D = ROUND_SCENE.instantiate()
	add_child_autofree(arena)
	arena.set_process(false)
	return arena
