@tool
extends SceneTree

# TDD-grown coverage of the PolygonTriangulationGodot wrapper.
# Tests invariants of the (V, F) output that don't depend on the
# specific triangulation chosen.

func _initialize() -> void:
	var fails: int = 0

	var pent := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(1.5, 0.5, 0),
		Vector3(1, 1, 0),
		Vector3(0, 1, 0),
	])
	var tri := PolygonTriangulationGodot.create(pent)
	tri.enable_dot_output(false)
	tri.preprocess()
	tri.triangulate()

	# Cycle 17: get_indices().size() must be divisible by 3.
	var idx: PackedInt32Array = tri.get_indices()
	if idx.size() % 3 == 0 and idx.size() > 0:
		print("[ptg][PASS] indices_multiple_of_3: %d" % idx.size())
	else:
		print("[ptg][FAIL] indices_multiple_of_3: size=%d" % idx.size())
		fails += 1

	# Cycle 18: every face index in [0, vertex_count). Out-of-range
	# indices would crash downstream consumers (ArrayMesh::add_surface).
	var nV: int = tri.get_vertex_count()
	var oob_idx: int = -1
	for i in idx:
		if i < 0 or i >= nV:
			oob_idx = i
			break
	if oob_idx == -1:
		print("[ptg][PASS] face_indices_in_range: all %d < nV=%d" % [idx.size(), nV])
	else:
		print("[ptg][FAIL] face_indices_in_range: %d out of [0, %d)" % [oob_idx, nV])
		fails += 1

	# Cycle 19: get_optimal_cost() must be non-negative. Cost is the
	# sum of weight * acos(...) terms (bi-triangle dihedral angles +
	# boundary triangle alignment). acos returns [0, pi], weights are
	# non-negative -> cost can't go negative without something broken.
	# Tolerate tiny negative float noise (-0.0 or accumulator drift
	# from tile_segment's recursive subCostSum += updates).
	var cost: float = tri.get_optimal_cost()
	if cost >= -1e-6 and is_finite(cost):
		print("[ptg][PASS] optimal_cost_non_negative: %f" % cost)
	else:
		print("[ptg][FAIL] optimal_cost_non_negative: %f" % cost)
		fails += 1

	# Cycle 21: vertex_count == input boundary count. PolygonTriangulationGodot
	# does NOT run MingCurve perturbation, so output points must
	# equal input points 1:1 (no inserted Steiner points).
	if nV == 5:
		print("[ptg][PASS] vertex_count_equals_input: %d" % nV)
	else:
		print("[ptg][FAIL] vertex_count_equals_input: got %d, expected 5" % nV)
		fails += 1

	# Cycle 28: optimal_cost > 0 for a non-planar boundary when the
	# bi-triangle weight is active. The default weights are all zero
	# (so cost is always zero regardless of shape — see cycle 19).
	# With bitri=1, dihedral acos terms accumulate -> non-planar
	# input MUST produce strictly positive cost.
	var nonplanar := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(1, 1, 1),  # lifted: introduces a real dihedral angle
		Vector3(0, 1, 0),
	])
	var tri_nf := PolygonTriangulationGodot.create(nonplanar)
	tri_nf.enable_dot_output(false)
	tri_nf.set_cost_weights(0.0, 0.0, 1.0, 1.0, 0.0)
	tri_nf.preprocess()
	tri_nf.triangulate()
	var cost_nf: float = tri_nf.get_optimal_cost()
	if cost_nf > 0.0 and is_finite(cost_nf):
		print("[ptg][PASS] nonplanar_cost_positive: %f" % cost_nf)
	else:
		print("[ptg][FAIL] nonplanar_cost_positive: %f (should be > 0)" % cost_nf)
		fails += 1

	# Cycle 34: n-gon -> exactly n-2 triangles (Euler invariant for
	# triangulating a simple polygon). Sweep n in {3, 5, 7, 10, 15}
	# regular convex polygons; each must yield n-2 triangles.
	var PI := 3.14159265358979
	for n in [3, 5, 7, 10, 15]:
		var poly := PackedVector3Array()
		for i in n:
			var theta: float = 2.0 * PI * float(i) / float(n)
			poly.push_back(Vector3(cos(theta), sin(theta), 0))
		var t := PolygonTriangulationGodot.create(poly)
		t.enable_dot_output(false)
		t.preprocess()
		t.triangulate()
		var got: int = t.get_triangle_count()
		if got != n - 2:
			print("[ptg][FAIL] n_minus_2_invariant: n=%d, got %d tris, expected %d" % [n, got, n - 2])
			fails += 1
	if fails == 0:
		print("[ptg][PASS] n_minus_2_invariant (n in {3, 5, 7, 10, 15})")

	if fails == 0:
		print("[ptg] ALL PASS")
		quit(0)
	else:
		print("[ptg] %d FAILURES" % fails)
		quit(1)
