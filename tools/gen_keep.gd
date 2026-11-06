extends SceneTree
## Original scripted masonry model; the reference is mood only, not traced geometry.
## godot --headless --path . -s res://tools/gen_keep.gd

const HEIGHT := 1.6
const RADIUS := 0.65
const SIDES := [32, 16, 8]
const COURSES := [5, 4, 0]
const BLOCKS := [16, 8, 0]
const BUDGETS := [6000, 1500, 400]


func _init() -> void:
	for lod in range(3):
		var root := Node3D.new()
		root.name = "CastleKeep"
		var keep := MeshInstance3D.new()
		keep.name = "Keep"
		keep.mesh = build_mesh(lod)
		root.add_child(keep)
		keep.owner = root
		var triangles := keep.mesh.get_faces().size() / 3
		if triangles > BUDGETS[lod]:
			push_error("Keep LOD%d exceeds its triangle budget: %d" % [lod, triangles])
			root.free()
			quit(1)
			return
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var err := document.append_from_scene(root, state)
		if err == OK:
			err = document.write_to_filesystem(state, "res://assets/models/keep_lod%d.glb" % lod)
		root.free()
		if err != OK:
			push_error("Keep LOD%d export failed: %s" % [lod, error_string(err)])
			quit(1)
			return
		print("Keep LOD%d exported: %d triangles (budget %d)" % [lod, triangles, BUDGETS[lod]])
	quit(0)


static func build_mesh(lod: int) -> ArrayMesh:
	assert(lod >= 0 and lod < 3)
	var mesh := ArrayMesh.new()
	var seat := _surface()
	var stone := _surface()
	var mortar := _surface()
	var iron := _surface()
	var sides: int = SIDES[lod]
	_frustum(stone, RADIUS, 0.57, 0.0, 0.17, sides)
	if lod == 2:
		_frustum(stone, 0.55, 0.52, 0.17, 1.36, sides)
	else:
		_frustum(mortar, 0.535, 0.515, 0.17, 1.26, sides)
		for row in range(COURSES[lod]):
			var bottom := lerpf(0.17, 1.16, float(row) / COURSES[lod])
			var top := lerpf(0.17, 1.16, float(row + 1) / COURSES[lod])
			var radius := lerpf(0.56, 0.54, float(row) / COURSES[lod])
			for block in range(BLOCKS[lod]):
				var start: float = TAU * (block + 0.5 * (row % 2)) / BLOCKS[lod]
				var finish: float = start + TAU / BLOCKS[lod]
				_band(stone, _profile(0.50, radius, bottom + 0.004, top - 0.004,
					0.008 if lod == 0 else 0.0), start + 0.007, finish - 0.007,
					2 if lod == 0 else 1)
		_frustum(stone, 0.52, 0.50, 1.23, 1.36, sides)

	_band(stone, _profile(0.40, 0.60, 1.26, 1.36), 0.0, TAU, sides)
	for tooth in range(8):
		var angle := TAU * tooth / 8.0
		var half_width := PI / 8.0 * 0.53
		_band(stone, _profile(0.41, 0.60, 1.36, HEIGHT,
			0.012 if lod == 0 else 0.0), angle - half_width, angle + half_width,
			2 if lod == 0 else 1)
		if lod < 2:
			_band(iron, _profile(0.408, 0.604, 1.585, HEIGHT),
				angle - half_width, angle + half_width, 2 if lod == 0 else 1)

	_band(seat, _profile(0.515, 0.565, 1.16, 1.235), 0.0, TAU, sides)
	for face in range(4):
		var angle := TAU * face / 4.0
		_box(mortar, angle, Vector3(0, 0.90, 0.551), Vector3(0.072, 0.25, 0.018))
		_box(iron, angle, Vector3(0, 1.035, 0.565), Vector3(0.11, 0.025, 0.024))
		if lod < 2:
			for x in [-0.048, 0.048]:
				_box(iron, angle, Vector3(x, 0.90, 0.565), Vector3(0.02, 0.25, 0.024))
			_box(iron, angle, Vector3(0, 0.765, 0.565), Vector3(0.11, 0.025, 0.024))
			_box(seat, angle, Vector3(0, 1.10, 0.558), Vector3(0.105, 0.12, 0.028))
			for y in [1.10, 1.20]:
				_stud(iron, angle, Vector3(0, y, 0.58), 0.014)
				if lod == 0:
					_stud(iron, angle, Vector3(0.035, y, 0.58), 0.012)

	_commit(mesh, seat, _material("SeatMetal", Color.WHITE, 0.5, 0.32))
	_commit(mesh, stone, _material("Limestone", Color("9b9c91"), 0.0, 0.86))
	_commit(mesh, mortar, _material("Mortar", Color("353b40"), 0.0, 0.95))
	_commit(mesh, iron, _material("ForgedIron", Color("737f89"), 0.85, 0.30))
	return mesh


static func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface


static func _material(label: String, color: Color, metallic: float,
		roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = label
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
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


static func _point(radius: float, y: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, y, sin(angle) * radius)


static func _band(surface: SurfaceTool, profile: Array[Vector2], start: float,
		finish: float, segments: int) -> void:
	for index in range(segments):
		var a0 := lerpf(start, finish, float(index) / segments)
		var a1 := lerpf(start, finish, float(index + 1) / segments)
		for edge in range(profile.size()):
			var next := (edge + 1) % profile.size()
			var direction := profile[next] - profile[edge]
			var outward := _point(direction.y, -direction.x, (a0 + a1) * 0.5).normalized()
			_quad(surface, _point(profile[edge].x, profile[edge].y, a0),
				_point(profile[edge].x, profile[edge].y, a1),
				_point(profile[next].x, profile[next].y, a1),
				_point(profile[next].x, profile[next].y, a0), outward)
	if is_equal_approx(finish - start, TAU):
		return
	for end in [start, finish]:
		var outward := Vector3(-sin(end), 0, cos(end)) * (-1.0 if end == start else 1.0)
		for index in range(1, profile.size() - 1):
			_triangle(surface, _point(profile[0].x, profile[0].y, end),
				_point(profile[index].x, profile[index].y, end),
				_point(profile[index + 1].x, profile[index + 1].y, end), outward)


static func _frustum(surface: SurfaceTool, lower: float, upper: float,
		bottom: float, top: float, sides: int) -> void:
	for side in range(sides):
		var a0 := TAU * side / sides
		var a1 := TAU * (side + 1) / sides
		_quad(surface, _point(lower, bottom, a0), _point(lower, bottom, a1),
			_point(upper, top, a1), _point(upper, top, a0),
			_point(top - bottom, lower - upper, (a0 + a1) * 0.5).normalized())
		_triangle(surface, Vector3(0, bottom, 0), _point(lower, bottom, a0),
			_point(lower, bottom, a1), Vector3.DOWN)
		_triangle(surface, Vector3(0, top, 0), _point(upper, top, a0),
			_point(upper, top, a1), Vector3.UP)


static func _box(surface: SurfaceTool, angle: float, center: Vector3, size: Vector3) -> void:
	var basis := Basis(Vector3.UP, -angle)
	var points: Array[Vector3] = []
	for corner in range(8):
		var offset := Vector3(1 if (corner & 1) != 0 else -1,
			1 if (corner & 2) != 0 else -1, 1 if (corner & 4) != 0 else -1) * size * 0.5
		points.append(basis * (center + offset))
	for face in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 4, 6, 2],
			[1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3]]:
		var outward := ((points[face[0]] + points[face[1]] + points[face[2]]
			+ points[face[3]]) * 0.25 - basis * center).normalized()
		_quad(surface, points[face[0]], points[face[1]], points[face[2]], points[face[3]], outward)


static func _stud(surface: SurfaceTool, angle: float, center: Vector3, radius: float) -> void:
	var basis := Basis(Vector3.UP, -angle)
	var ring: Array[Vector3] = []
	for side in range(4):
		ring.append(basis * (center + Vector3(cos(TAU * side / 4.0),
			sin(TAU * side / 4.0), 0) * radius))
	for side in range(4):
		var next := (side + 1) % 4
		for depth in [-radius, radius]:
			var tip := basis * (center + Vector3(0, 0, depth))
			var outward := ((ring[side] + ring[next] + tip) / 3.0 - basis * center).normalized()
			_triangle(surface, ring[side], ring[next], tip, outward)


static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, outward: Vector3) -> void:
	_triangle(surface, a, b, c, outward)
	_triangle(surface, a, c, d, outward)


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		outward: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	# Godot uses clockwise front faces; preserve outward flat-shaded normals.
	var vertices := [a, c, b] if normal.dot(outward) > 0.0 else [a, b, c]
	surface.set_normal(normal if normal.dot(outward) > 0.0 else -normal)
	for vertex in vertices:
		surface.add_vertex(vertex)
