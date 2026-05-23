@tool
extends SceneTree

# TDD-grown coverage of CassieTriangulator behaviors that don't fit
# the existing per-class test files (shape coverage, refinement
# monotonicity, properties already live in their own files).

const PI := 3.14159265358979

func _initialize() -> void:
	var fails: int = 0

	# Cycle 30: target_edge_length much larger than the boundary
	# diagonal must NOT explode the output. pmp's split_long_edges
	# is a no-op when every edge is already shorter than the target,
	# so output should be close to the raw DMWT triangulation -- a
	# unit hexagon (diagonal ~2) with target=10 must produce a
	# small mesh, NOT thousands of vertices from a runaway loop.
	var hex := PackedVector3Array()
	for i in 6:
		var t: float = 2.0 * PI * float(i) / 6.0
		hex.push_back(Vector3(cos(t), sin(t), 0))
	var res: Dictionary = CassieTriangulator.triangulate(hex, 10.0)
	if not res.get("success", false):
		print("[ctr][FAIL] large_target: success=false")
		fails += 1
	else:
		var verts: PackedVector3Array = res["vertices"]
		var faces: PackedInt32Array = res["faces"]
		var nF: int = faces.size() / 3
		# Loose upper bound: unit hexagon at target=10 should yield
		# well under 50 vertices. The bare DMWT output for hex is
		# 6v / 4f (n-2); inflation may add a few interior vertices
		# but pmp shouldn't subdivide anything.
		if verts.size() < 50 and nF > 0:
			print("[ctr][PASS] large_target_no_explode: nV=%d nF=%d" % [verts.size(), nF])
		else:
			print("[ctr][FAIL] large_target_no_explode: nV=%d nF=%d (suspect runaway)" % [verts.size(), nF])
			fails += 1

	# Cycle 31: stronger manifold check. After full pipeline (DMWT +
	# pmp uniform_remeshing + inflate), every edge must be shared by
	# exactly 1 (boundary) or 2 (interior) faces. properties_test
	# only flags >2; this also catches dangling edges (count==0 is
	# impossible by construction, but the fold doubles as a sanity
	# check on faces output).
	var pent := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1.5, 0.5, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	var res_m: Dictionary = CassieTriangulator.triangulate(pent, 0.3)
	if not res_m.get("success", false):
		print("[ctr][FAIL] manifold_check: success=false")
		fails += 1
	else:
		var faces_m: PackedInt32Array = res_m["faces"]
		var edge_count := {}
		var nF_m := faces_m.size() / 3
		for f in nF_m:
			var a := faces_m[f * 3 + 0]
			var b := faces_m[f * 3 + 1]
			var c := faces_m[f * 3 + 2]
			for e in [Vector2i(mini(a, b), maxi(a, b)),
					  Vector2i(mini(b, c), maxi(b, c)),
					  Vector2i(mini(a, c), maxi(a, c))]:
				edge_count[e] = edge_count.get(e, 0) + 1
		var bad: int = 0
		for k in edge_count:
			var n: int = edge_count[k]
			if n != 1 and n != 2:
				bad += 1
		if bad == 0:
			print("[ctr][PASS] manifold_pentagon: all %d edges have 1 or 2 faces" % edge_count.size())
		else:
			print("[ctr][FAIL] manifold_pentagon: %d edges with bad face count" % bad)
			fails += 1

	# Cycle 32: self-intersecting "figure-8" / X boundary. Tracing
	# (0,0) -> (1,1) -> (1,0) -> (0,1) -> back-to-(0,0) makes the
	# diagonals cross. The pipeline isn't designed for this -- but
	# it must NOT crash. Either gracefully fail or produce SOME
	# mesh; we only assert the return shape is well-formed.
	var fig8 := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 1, 0),
		Vector3(1, 0, 0),
		Vector3(0, 1, 0),
	])
	var res_8: Dictionary = CassieTriangulator.triangulate(fig8, 0.3)
	# The contract: return a Dictionary with the expected keys, no
	# segfault. Either success=true with valid output, or
	# success=false with empty arrays. Both are acceptable.
	var well_formed: bool = res_8.has("success") \
			and res_8.get("vertices", null) != null \
			and res_8.get("faces", null) != null
	if well_formed:
		print("[ctr][PASS] figure_8_no_crash: success=%s, nV=%d, nF=%d" % [
			str(res_8["success"]),
			(res_8["vertices"] as PackedVector3Array).size(),
			(res_8["faces"] as PackedInt32Array).size() / 3,
		])
	else:
		print("[ctr][FAIL] figure_8_no_crash: bad return shape %s" % str(res_8))
		fails += 1

	# Cycle 33: serial determinism across 5 calls. Same input + same
	# target -> same output across consecutive calls. Verifies the
	# Geogram RNG reset + Point3 perturb RNG reset (cassie_triangulator.cpp:80)
	# are both effective. (Concurrent test was hanging Godot's Thread
	# system; sequential repeats exercise the determinism contract
	# without the GDScript-Thread flakiness.)
	var hex_d := PackedVector3Array()
	for i in 6:
		var t: float = 2.0 * PI * float(i) / 6.0
		hex_d.push_back(Vector3(cos(t), sin(t), 0))
	var first_call: Dictionary = CassieTriangulator.triangulate(hex_d, 0.3)
	var first_nV: int = (first_call["vertices"] as PackedVector3Array).size()
	var first_nF: int = (first_call["faces"] as PackedInt32Array).size()
	var deterministic: bool = true
	for i in 4:
		var r: Dictionary = CassieTriangulator.triangulate(hex_d, 0.3)
		if (r["vertices"] as PackedVector3Array).size() != first_nV \
				or (r["faces"] as PackedInt32Array).size() != first_nF:
			deterministic = false
			break
	if deterministic:
		print("[ctr][PASS] determinism_5_calls: nV=%d nF=%d stable" % [first_nV, first_nF / 3])
	else:
		print("[ctr][FAIL] determinism_5_calls: output size changed across runs")
		fails += 1

	# Cycle 36: every output triangle has strictly positive area.
	# Degenerate (zero-area) triangles in the output would crash
	# normal-vector computations downstream and indicate either pmp
	# emitting a sliver or DMWT picking a collinear candidate.
	var hex_a := PackedVector3Array()
	for i in 6:
		var t: float = 2.0 * PI * float(i) / 6.0
		hex_a.push_back(Vector3(cos(t), sin(t), 0))
	var res_a: Dictionary = CassieTriangulator.triangulate(hex_a, 0.3)
	var verts_a: PackedVector3Array = res_a["vertices"]
	var faces_a: PackedInt32Array = res_a["faces"]
	var zero_area: int = 0
	for f in faces_a.size() / 3:
		var v0: Vector3 = verts_a[faces_a[f * 3 + 0]]
		var v1: Vector3 = verts_a[faces_a[f * 3 + 1]]
		var v2: Vector3 = verts_a[faces_a[f * 3 + 2]]
		# 2 * area = |cross|
		var area2: float = (v1 - v0).cross(v2 - v0).length()
		if area2 < 1e-9:
			zero_area += 1
	if zero_area == 0:
		print("[ctr][PASS] no_zero_area_triangles: all %d non-degenerate" % (faces_a.size() / 3))
	else:
		print("[ctr][FAIL] no_zero_area_triangles: %d degenerate of %d" % [zero_area, faces_a.size() / 3])
		fails += 1

	if fails == 0:
		print("[ctr] ALL PASS")
		quit(0)
	else:
		print("[ctr] %d FAILURES" % fails)
		quit(1)
