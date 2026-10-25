class_name ArcMesh
extends RefCounted
## Extruded annular sector. Local angle a maps to (cos a, 0, sin a); rotate the
## owning node by -angle about Y to place it at arena angle `angle`.


static func build(inner_radius: float, outer_radius: float, height: float, half_arc: float, segments: int = 12) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := -half_arc + 2.0 * half_arc * float(i) / segments
		var a1 := -half_arc + 2.0 * half_arc * float(i + 1) / segments
		var o0 := _pt(outer_radius, a0, 0.0)
		var o1 := _pt(outer_radius, a1, 0.0)
		var i0 := _pt(inner_radius, a0, 0.0)
		var i1 := _pt(inner_radius, a1, 0.0)
		var o0t := _pt(outer_radius, a0, height)
		var o1t := _pt(outer_radius, a1, height)
		var i0t := _pt(inner_radius, a0, height)
		var i1t := _pt(inner_radius, a1, height)
		_quad(st, o0, o1, o1t, o0t)
		_quad(st, i1, i0, i0t, i1t)
		_quad(st, i0t, o0t, o1t, i1t)
	var end_a := _pt(inner_radius, -half_arc, 0.0)
	var end_b := _pt(outer_radius, -half_arc, 0.0)
	_quad(st, end_a, end_b, _pt(outer_radius, -half_arc, height), _pt(inner_radius, -half_arc, height))
	var end_c := _pt(outer_radius, half_arc, 0.0)
	var end_d := _pt(inner_radius, half_arc, 0.0)
	_quad(st, end_c, end_d, _pt(inner_radius, half_arc, height), _pt(outer_radius, half_arc, height))
	st.generate_normals()
	return st.commit()


static func _pt(radius: float, angle: float, y: float) -> Vector3:
	return Vector3(cos(angle) * radius, y, sin(angle) * radius)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)
