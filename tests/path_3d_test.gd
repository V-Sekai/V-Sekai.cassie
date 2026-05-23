@tool
extends SceneTree

# TDD-grown coverage of CassiePath3D arithmetic + smoothing.
# Each cycle adds one assertion; existing assertions stay green.

const EPS := 1e-4

func _approx(a: float, b: float, label: String) -> bool:
	if absf(a - b) < EPS:
		print("[path][PASS] %s: %f ≈ %f" % [label, a, b])
		return true
	print("[path][FAIL] %s: %f vs %f (delta %f)" % [label, a, b, a - b])
	return false

func _initialize() -> void:
	var fails: int = 0

	# Cycle 9: open 3-4-5 triangle path has length 3 + 4 = 7 (open, no
	# closing edge). Tests the two-edge open-path sum.
	var p := CassiePath3D.new()
	p.add_point(Vector3(0, 0, 0))
	p.add_point(Vector3(3, 0, 0))
	p.add_point(Vector3(3, 4, 0))
	if not _approx(p.get_total_length(), 7.0, "open_3_4_5_length"):
		fails += 1

	# Cycle 10: same triangle as a closed path. Perimeter must
	# include the 5-unit hypotenuse closing edge -> 3+4+5 = 12.
	var pc := CassiePath3D.new()
	pc.add_point(Vector3(0, 0, 0))
	pc.add_point(Vector3(3, 0, 0))
	pc.add_point(Vector3(3, 4, 0))
	pc.set_closed(true)
	if not _approx(pc.get_total_length(), 12.0, "closed_3_4_5_perimeter"):
		fails += 1

	# Cycle 11: resample_uniform must yield exactly the requested
	# point count. Input has 4 unevenly-spaced samples; resample to
	# 10 -> get_point_count() must == 10.
	var pr := CassiePath3D.new()
	pr.add_point(Vector3(0, 0, 0))
	pr.add_point(Vector3(0.1, 0, 0))
	pr.add_point(Vector3(2, 0, 0))
	pr.add_point(Vector3(3, 0, 0))
	pr.resample_uniform(10)
	if pr.get_point_count() == 10:
		print("[path][PASS] resample_count: 10")
	else:
		print("[path][FAIL] resample_count: got %d, expected 10" % pr.get_point_count())
		fails += 1

	# Cycle 12: smooth_normals must leave every output normal unit
	# length. Average of three near-Y-axis normals stays near Y but
	# the averaging step shrinks magnitude unless re-normalised.
	var pn := CassiePath3D.new()
	pn.add_point(Vector3(0, 0, 0), Vector3(0.1, 1, 0))
	pn.add_point(Vector3(1, 0, 0), Vector3(0,   1, 0.1))
	pn.add_point(Vector3(2, 0, 0), Vector3(-0.1, 1, 0))
	pn.smooth_normals()
	var norms: PackedVector3Array = pn.get_normals()
	var all_unit: bool = true
	for n in norms:
		if absf((n as Vector3).length() - 1.0) > EPS:
			all_unit = false
			break
	if all_unit:
		print("[path][PASS] smooth_normals_unit_length")
	else:
		print("[path][FAIL] smooth_normals_unit_length: %s" % str(norms))
		fails += 1

	# Cycle 13: beautify_laplacian must leave open-path endpoints in
	# place. Source explicitly continues at i==0 and i==size-1 when
	# !is_closed (cassie_path_3d.cpp:132-134).
	var pl := CassiePath3D.new()
	pl.add_point(Vector3(0, 0, 0))
	pl.add_point(Vector3(1, 1, 0))  # spiky middle, will move
	pl.add_point(Vector3(2, 0, 0))
	pl.add_point(Vector3(3, 1, 0))
	pl.add_point(Vector3(4, 0, 0))
	pl.beautify_laplacian(0.5, 5)
	var first := pl.get_point_position(0)
	var last := pl.get_point_position(pl.get_point_count() - 1)
	if first == Vector3(0, 0, 0) and last == Vector3(4, 0, 0):
		print("[path][PASS] laplacian_endpoints_preserved")
	else:
		print("[path][FAIL] laplacian_endpoints_preserved: first=%s last=%s" % [first, last])
		fails += 1

	# Cycle 20: average_segment_length must equal total_length /
	# segment_count. 3-4-5 right triangle open path: total = 7,
	# segments = 2, average = 3.5.
	var pa := CassiePath3D.new()
	pa.add_point(Vector3(0, 0, 0))
	pa.add_point(Vector3(3, 0, 0))
	pa.add_point(Vector3(3, 4, 0))
	if not _approx(pa.get_average_segment_length(), 3.5, "open_avg_segment_length"):
		fails += 1

	# Cycle 22: get_sample_points(N) returns exactly N entries. Unlike
	# resample_uniform (which mutates the path), get_sample_points
	# returns a derived array without changing the source. Same source
	# path can yield 20, 50, 100, etc. samples without altering state.
	var ps := CassiePath3D.new()
	ps.add_point(Vector3(0, 0, 0))
	ps.add_point(Vector3(1, 0, 0))
	ps.add_point(Vector3(1, 1, 0))
	for n in [20, 50, 100]:
		var samples: PackedVector3Array = ps.get_sample_points(n)
		if samples.size() != n:
			print("[path][FAIL] sample_count_%d: got %d" % [n, samples.size()])
			fails += 1
			break
	if ps.get_point_count() != 3:
		print("[path][FAIL] sample_does_not_mutate: count now %d" % ps.get_point_count())
		fails += 1
	else:
		print("[path][PASS] get_sample_points (20/50/100, source unchanged)")

	# Cycle 23: beautify_taubin endpoint preservation (parallel to
	# cycle 13's laplacian test). Taubin has two smoothing passes
	# (lambda + mu) but both guard against modifying open-path
	# endpoints at cassie_path_3d.cpp:152-157 and :169-174.
	var pt := CassiePath3D.new()
	pt.add_point(Vector3(0, 0, 0))
	pt.add_point(Vector3(1, 1, 0))
	pt.add_point(Vector3(2, 0, 0))
	pt.add_point(Vector3(3, 1, 0))
	pt.add_point(Vector3(4, 0, 0))
	pt.beautify_taubin(0.5, -0.53, 5)
	var tfirst := pt.get_point_position(0)
	var tlast := pt.get_point_position(pt.get_point_count() - 1)
	if tfirst == Vector3(0, 0, 0) and tlast == Vector3(4, 0, 0):
		print("[path][PASS] taubin_endpoints_preserved")
	else:
		print("[path][FAIL] taubin_endpoints_preserved: first=%s last=%s" % [tfirst, tlast])
		fails += 1

	# Cycle 27: clear_points resets count to 0 (also clears normals
	# in lockstep). Locks in the contract that nothing leaks between
	# a CassiePath3D being repopulated for a second use.
	var pcl := CassiePath3D.new()
	pcl.add_point(Vector3(1, 1, 1))
	pcl.add_point(Vector3(2, 2, 2))
	pcl.add_point(Vector3(3, 3, 3))
	if pcl.get_point_count() != 3:
		print("[path][FAIL] clear_points precondition: count %d != 3" % pcl.get_point_count())
		fails += 1
	pcl.clear_points()
	if pcl.get_point_count() == 0 and (pcl.get_normals() as PackedVector3Array).size() == 0:
		print("[path][PASS] clear_points: count=0, normals=0")
	else:
		print("[path][FAIL] clear_points: count=%d, normals=%d" % [pcl.get_point_count(), (pcl.get_normals() as PackedVector3Array).size()])
		fails += 1

	# Cycle 29: out-of-bounds set_point_position / remove_point /
	# get_point_position must not crash. The C++ uses ERR_FAIL_INDEX
	# (godot-cpp) which prints an error and returns early. Path
	# state must remain consistent afterward.
	var poob := CassiePath3D.new()
	poob.add_point(Vector3(1, 0, 0))
	poob.add_point(Vector3(2, 0, 0))
	# These calls will print "Index ... is out of bounds" to stderr
	# but must not segfault. After them, the path should still have
	# exactly 2 unmodified points.
	poob.set_point_position(99, Vector3(99, 99, 99))
	poob.remove_point(-1)
	var _bad := poob.get_point_position(42)  # returns Vector3()
	if poob.get_point_count() == 2 \
			and poob.get_point_position(0) == Vector3(1, 0, 0) \
			and poob.get_point_position(1) == Vector3(2, 0, 0):
		print("[path][PASS] oob_calls_safe: state unchanged")
	else:
		print("[path][FAIL] oob_calls_safe: count=%d, p0=%s, p1=%s" % [
				poob.get_point_count(),
				poob.get_point_position(0),
				poob.get_point_position(1)])
		fails += 1

	if fails == 0:
		print("[path] ALL PASS")
		quit(0)
	else:
		print("[path] %d FAILURES" % fails)
		quit(1)
