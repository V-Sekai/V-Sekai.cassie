@tool
extends SceneTree

# TDD-grown coverage of CassieTriangulator failure modes. Each
# case asserts the boundary contract:
#   - success=false on degenerate input
#   - empty vertices/faces arrays on failure (never null)
#   - never crashes / segfaults inside the pipeline

func _expect_failure(name: String, boundary: PackedVector3Array, tgt: float) -> bool:
	var res: Dictionary = CassieTriangulator.triangulate(boundary, tgt)
	var ok: bool = res.get("success", true) == false \
			and res.get("vertices", null) != null \
			and res.get("faces", null) != null \
			and (res["vertices"] as PackedVector3Array).size() == 0 \
			and (res["faces"] as PackedInt32Array).size() == 0
	if ok:
		print("[errors][PASS] %s: graceful failure" % name)
	else:
		print("[errors][FAIL] %s: %s" % [name, str(res)])
	return ok

func _initialize() -> void:
	var fails: int = 0

	# Cycle 1: empty boundary (0 points).
	if not _expect_failure("empty",  PackedVector3Array(),                  0.3):
		fails += 1

	# Cycle 2: single point (nB=1, below the minimum of 3).
	if not _expect_failure("single", PackedVector3Array([Vector3(0,0,0)]), 0.3):
		fails += 1

	# Cycle 3: two points (nB=2, below the minimum of 3).
	if not _expect_failure("pair",   PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0)]), 0.3):
		fails += 1

	# Cycle 4: three collinear points (zero-area triangle). The
	# CassieTriangulator nB=3 fast path computes the cross-product
	# area and rejects below 1e-9.
	if not _expect_failure("collinear", PackedVector3Array([
			Vector3(0, 0, 0),
			Vector3(1, 0, 0),
			Vector3(2, 0, 0),
	]), 0.3):
		fails += 1

	# Cycle 5: three coincident points (zero-area, all identical).
	if not _expect_failure("coincident", PackedVector3Array([
			Vector3(1, 1, 1),
			Vector3(1, 1, 1),
			Vector3(1, 1, 1),
	]), 0.3):
		fails += 1

	# Cycle 6: NaN in a coordinate. Geogram's BDEL solver asserts on
	# non-finite inputs; the pipeline should reject before reaching it.
	if not _expect_failure("nan_coord", PackedVector3Array([
			Vector3(0, 0, 0),
			Vector3(1, 0, 0),
			Vector3(NAN, 0.5, 0),
			Vector3(0, 1, 0),
	]), 0.3):
		fails += 1

	# Cycle 7: +inf in a coordinate.
	if not _expect_failure("inf_coord", PackedVector3Array([
			Vector3(0, 0, 0),
			Vector3(1, 0, 0),
			Vector3(INF, 0.5, 0),
			Vector3(0, 1, 0),
	]), 0.3):
		fails += 1

	# Cycle 8: target_edge_length = 0 on an otherwise-valid pentagon.
	# Before this cycle the input hung pmp's split_long_edges loop
	# (every edge stayed "too long" forever). Fixed by guarding
	# `p_target_edge_length > 0.0f` in CassieTriangulator::triangulate
	# at src/cassie_triangulator.cpp.
	var pent_zero := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1.5, 0.5, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	if not _expect_failure("zero_tgt", pent_zero, 0.0):
		fails += 1

	# Cycle 8b: negative target_edge_length — same guard.
	if not _expect_failure("neg_tgt", pent_zero, -0.3):
		fails += 1

	# Cycle 8c: NaN target_edge_length — same guard.
	if not _expect_failure("nan_tgt", pent_zero, NAN):
		fails += 1

	if fails == 0:
		print("[errors] ALL PASS")
		quit(0)
	else:
		print("[errors] %d FAILURES" % fails)
		quit(1)
