@tool
extends SceneTree

func _initialize() -> void:
	print("[smoke] starting")

	var failures: int = 0

	# 1. CassiePath3D
	var path := CassiePath3D.new()
	path.add_point(Vector3(0, 0, 0), Vector3(0, 1, 0))
	path.add_point(Vector3(1, 0, 0), Vector3(0, 1, 0))
	path.add_point(Vector3(2, 0, 0), Vector3(0, 1, 0))
	if path.get_point_count() != 3:
		print("[smoke][FAIL] CassiePath3D point count = %d, expected 3" % path.get_point_count())
		failures += 1
	else:
		print("[smoke][PASS] CassiePath3D point count = 3")

	# 2. Triangle (Delaunay2D path via Geogram BDEL2d)
	var triangle := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0.5, 1, 0),
	])
	var tri := PolygonTriangulationGodot.create(triangle)
	if tri == null:
		print("[smoke][FAIL] PolygonTriangulationGodot.create returned null")
		failures += 1
	else:
		tri.enable_dot_output(false)
		tri.preprocess()
		var ok: bool = tri.triangulate()
		var tcount: int = tri.get_triangle_count()
		var vcount: int = tri.get_vertex_count()
		if ok and tcount == 1 and vcount == 3:
			print("[smoke][PASS] triangle: 1 triangle, 3 vertices")
		else:
			print("[smoke][FAIL] triangle: triangulate=%s, tris=%d, verts=%d" % [str(ok), tcount, vcount])
			failures += 1

	# 3. Pentagon (Delaunay2D path with more points)
	var pent := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(1.5, 0.5, 0),
		Vector3(1, 1, 0),
		Vector3(0, 1, 0),
	])
	var pent_tri := PolygonTriangulationGodot.create(pent)
	pent_tri.enable_dot_output(false)
	pent_tri.preprocess()
	var pent_ok: bool = pent_tri.triangulate()
	var pent_tris: int = pent_tri.get_triangle_count()
	if pent_ok and pent_tris == 3:
		print("[smoke][PASS] pentagon: 3 triangles (n-2)")
	else:
		print("[smoke][FAIL] pentagon: triangulate=%s, tris=%d (expected 3)" % [str(pent_ok), pent_tris])
		failures += 1

	# 4. IntrinsicTriangulation construct
	var intr := IntrinsicTriangulation.new()
	var verts := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0.5, 1, 0), Vector3(1.5, 1, 0)])
	var indices := PackedInt32Array([0, 1, 2, 1, 3, 2])
	intr.set_mesh_data(verts, indices, PackedVector3Array())
	if intr.get_vertex_count() == 4 and intr.get_triangle_count() == 2:
		print("[smoke][PASS] IntrinsicTriangulation: 4 verts, 2 tris")
	else:
		print("[smoke][FAIL] IntrinsicTriangulation: verts=%d, tris=%d" % [intr.get_vertex_count(), intr.get_triangle_count()])
		failures += 1

	# 5. CassieSurface construct + boundary
	var surf := CassieSurface.new()
	surf.add_boundary_path(path)
	if surf.get_boundary_path_count() == 1:
		print("[smoke][PASS] CassieSurface: 1 boundary path")
	else:
		print("[smoke][FAIL] CassieSurface: boundary count = %d" % surf.get_boundary_path_count())
		failures += 1

	# 6. CassieTriangulator.triangulate (new single-call pipeline,
	#    mirrors cassie-triangulation/src/Triangulation.cpp Triangulate()).
	#    Hexagon boundary with target_edge_length ~ 0.3 -> expect more
	#    triangles than the raw DMWT output (refine_patch subdivides).
	var hex := PackedVector3Array()
	for i in 6:
		var angle: float = i * TAU / 6.0
		hex.push_back(Vector3(cos(angle), sin(angle), 0))
	var res: Dictionary = CassieTriangulator.triangulate(hex, 0.3)
	if not res.get("success", false):
		print("[smoke][FAIL] CassieTriangulator.triangulate(hex, 0.3) returned success=false")
		failures += 1
	else:
		var hex_verts: PackedVector3Array = res["vertices"]
		var hex_face_idx: PackedInt32Array = res["faces"]
		var hex_face_count: int = hex_face_idx.size() / 3
		if hex_verts.size() < 6 or hex_face_count < 4:
			print("[smoke][FAIL] CassieTriangulator: too few outputs (verts=%d, faces=%d)" % [hex_verts.size(), hex_face_count])
			failures += 1
		else:
			print("[smoke][PASS] CassieTriangulator hex+refine: %d verts, %d faces" % [hex_verts.size(), hex_face_count])

	# 7. nB == 3 fast path -- bypasses DMWT, runs refine_patch directly.
	var tri_in := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0.5, 1, 0),
	])
	var tri_res: Dictionary = CassieTriangulator.triangulate(tri_in, 0.2)
	if not tri_res.get("success", false):
		print("[smoke][FAIL] CassieTriangulator.triangulate(triangle, 0.2) success=false")
		failures += 1
	else:
		var tri_verts: PackedVector3Array = tri_res["vertices"]
		var tri_faces: PackedInt32Array = tri_res["faces"]
		print("[smoke][PASS] CassieTriangulator triangle fast-path: %d verts, %d faces" % [tri_verts.size(), tri_faces.size() / 3])

	if failures == 0:
		print("[smoke] ALL PASS")
		quit(0)
	else:
		print("[smoke] %d FAILURES" % failures)
		quit(1)
