extends SceneTree
## Original, hand-authored shield geometry; no image-to-mesh or Blender dependency.
## godot --headless --path . -s res://tools/gen_shield.gd

const Rules = preload("res://scripts/match_rules.gd")
const HEIGHT := 0.7
const HALF_ARC := Rules.SHIELD_HALF_ARC * 0.95
const INNER := Rules.SHIELD_RADIUS - 0.16
const OUTER := Rules.SHIELD_RADIUS + 0.16
const SEGMENTS := [24, 12, 6]
const PANELS := [5, 3, 1]
const RIVETS := [9, 5, 3]
const BUDGETS := [4000, 1000, 300]


func _init() -> void:
	for lod in range(3):
		var root := Node3D.new()
		root.name = "BattleShield"
		var shield := MeshInstance3D.new()
		shield.name = "Shield"
		shield.mesh = build_mesh(lod)
		root.add_child(shield)
		shield.owner = root
		var triangles := shield.mesh.get_faces().size() / 3
		if triangles > BUDGETS[lod]:
			push_error("Shield LOD%d exceeds its triangle budget: %d" % [lod, triangles])
			root.free()
			quit(1)
			return
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var err := document.append_from_scene(root, state)
		if err == OK:
			err = document.write_to_filesystem(state, "res://assets/models/shield_lod%d.glb" % lod)
		root.free()
		if err != OK:
			push_error("Shield LOD%d export failed: %s" % [lod, error_string(err)])
			quit(1)
			return
		print("Shield LOD%d exported: %d triangles (budget %d)" % [lod, triangles, BUDGETS[lod]])
	quit(0)


static func build_mesh(lod: int) -> ArrayMesh:
	assert(lod >= 0 and lod < 3)
	var mesh := ArrayMesh.new()
	var metal := _surface()
	var panel_count: int = PANELS[lod]
	for panel in range(panel_count):
		var start := -HALF_ARC + 0.035 + (2.0 * HALF_ARC - 0.07) * panel / panel_count
		var finish := -HALF_ARC + 0.035 + (2.0 * HALF_ARC - 0.07) * (panel + 1) / panel_count
		var bevel := 0.018 if lod < 2 else 0.0
		_band(metal, _profile(Rules.SHIELD_RADIUS + 0.01, OUTER - 0.03,
			0.08, HEIGHT - 0.08, bevel), start + 0.004, finish - 0.004,
			4 if lod == 0 else (2 if lod == 1 else 6))
	_commit(mesh, metal, _material("SeatMetal", Color.WHITE, 0.75, 0.24, true))

	var stone := _surface()
	_band(stone, _profile(INNER, Rules.SHIELD_RADIUS + 0.05, 0.04, HEIGHT - 0.04),
		-HALF_ARC, HALF_ARC, SEGMENTS[lod])
	_commit(mesh, stone, _material("StoneBacking", Color("384651"), 0.0, 0.86))

	var rim := _surface()
	for bottom in [0.0, HEIGHT - 0.08]:
		_band(rim, _profile(INNER, OUTER, bottom, bottom + 0.08),
			-HALF_ARC, HALF_ARC, SEGMENTS[lod])
	for start in [-HALF_ARC, HALF_ARC - 0.03]:
		_band(rim, _profile(INNER, OUTER, 0.08, HEIGHT - 0.08), start, start + 0.03, 1)
	for row in [0.04, HEIGHT - 0.04]:
		for index in range(RIVETS[lod]):
			var angle := lerpf(-HALF_ARC + 0.055, HALF_ARC - 0.055,
				float(index) / (RIVETS[lod] - 1))
			_rivet(rim, angle, row, 8 if lod == 0 else (6 if lod == 1 else 4),
				2 if lod == 0 else 1)
	_commit(mesh, rim, _material("ForgedRim", Color("a0abb5"), 0.85, 0.3))
	return mesh


static func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface


static func _material(label: String, color: Color, metallic: float, roughness: float,
		emissive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = label
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.emission_enabled = emissive
	material.emission = Color.WHITE if emissive else Color.BLACK
	material.emission_energy_multiplier = 1.6 if emissive else 1.0
	return material


static func _commit(mesh: ArrayMesh, surface: SurfaceTool, material: StandardMaterial3D) -> void:
	surface.index()
	surface.set_material(material)
	surface.commit(mesh)
	mesh.surface_set_name(mesh.get_surface_count() - 1, material.resource_name)


static func _profile(inner: float, outer: float, bottom: float, top: float,
		bevel: float = 0.0) -> Array[Vector2]:
	if bevel == 0.0:
		return [Vector2(inner, bottom), Vector2(outer, bottom),
			Vector2(outer, top), Vector2(inner, top)]
	return [Vector2(inner + bevel, bottom), Vector2(outer - bevel, bottom),
		Vector2(outer, bottom + bevel), Vector2(outer, top - bevel),
		Vector2(outer - bevel, top), Vector2(inner + bevel, top),
		Vector2(inner, top - bevel), Vector2(inner, bottom + bevel)]


static func _point(profile_point: Vector2, angle: float) -> Vector3:
	return Vector3(cos(angle) * profile_point.x, profile_point.y, sin(angle) * profile_point.x)


static func _band(surface: SurfaceTool, profile: Array[Vector2], start: float,
		finish: float, segments: int) -> void:
	for index in range(segments):
		var a0 := lerpf(start, finish, float(index) / segments)
		var a1 := lerpf(start, finish, float(index + 1) / segments)
		var radial := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		for edge in range(profile.size()):
			var next := (edge + 1) % profile.size()
			var direction := profile[next] - profile[edge]
			var normal := (radial * direction.y - Vector3.UP * direction.x).normalized()
			_quad(surface, _point(profile[edge], a0), _point(profile[edge], a1),
				_point(profile[next], a1), _point(profile[next], a0), normal)
	for end in [start, finish]:
		var normal := Vector3(-sin(end), 0, cos(end)) * (-1.0 if end == start else 1.0)
		for index in range(1, profile.size() - 1):
			_triangle(surface, _point(profile[0], end), _point(profile[index], end),
				_point(profile[index + 1], end), normal)


static func _rivet(surface: SurfaceTool, angle: float, y: float, sides: int, rings: int) -> void:
	var radial := Vector3(cos(angle), 0, sin(angle))
	var tangent := Vector3(-sin(angle), 0, cos(angle))
	var center := radial * (OUTER - 0.026) + Vector3.UP * y
	var rows: Array[PackedVector3Array] = []
	for ring in range(rings):
		var latitude := PI * 0.5 * ring / rings
		var row := PackedVector3Array()
		for side in range(sides):
			var phase := TAU * side / sides
			row.append(center + radial * (0.026 * sin(latitude))
				+ (tangent * cos(phase) + Vector3.UP * sin(phase)) * (0.026 * cos(latitude)))
		rows.append(row)
	for ring in range(rings - 1):
		for side in range(sides):
			var next := (side + 1) % sides
			var a := rows[ring][side]
			var b := rows[ring][next]
			var c := rows[ring + 1][next]
			var d := rows[ring + 1][side]
			_quad(surface, a, b, c, d, ((a + b + c + d) * 0.25 - center).normalized())
	var tip := center + radial * 0.026
	for side in range(sides):
		var a := rows[rings - 1][side]
		var b := rows[rings - 1][(side + 1) % sides]
		_triangle(surface, a, b, tip, ((a + b + tip) / 3.0 - center).normalized())
	for side in range(1, sides - 1):
		_triangle(surface, rows[0][0], rows[0][side], rows[0][side + 1], -radial)


static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, outward: Vector3) -> void:
	_triangle(surface, a, b, c, outward)
	_triangle(surface, a, c, d, outward)


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		outward: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	# Godot front faces are clockwise; keep explicit outward flat-shaded normals.
	var vertices := [a, c, b] if normal.dot(outward) > 0.0 else [a, b, c]
	surface.set_normal(normal if normal.dot(outward) > 0.0 else -normal)
	for vertex in vertices:
		surface.add_vertex(vertex)
