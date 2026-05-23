@tool
extends SceneTree

# Ported from cassie-triangulation/tests/shapes.cpp.
# Fixed-input smokes for CASSIE-realistic boundary shapes: sleeve,
# helix, phone outline, star, triangle. Each calls
# CassieTriangulator.triangulate and asserts non-trivial output +
# that inflation actually fired (output AABB excess > 2% of input
# diagonal along at least one axis).

const PI := 3.14159265358979323846

func _bounds_excess(input_pts: PackedVector3Array, output_pts: PackedVector3Array) -> Dictionary:
	var in_min := Vector3(INF, INF, INF)
	var in_max := Vector3(-INF, -INF, -INF)
	for p in input_pts:
		in_min = in_min.min(p)
		in_max = in_max.max(p)
	var in_diag: float = (in_max - in_min).length()

	var out_min := Vector3(INF, INF, INF)
	var out_max := Vector3(-INF, -INF, -INF)
	for p in output_pts:
		out_min = out_min.min(p)
		out_max = out_max.max(p)

	var excess: float = 0.0
	for d in 3:
		excess = maxf(excess, in_min[d] - out_min[d])
		excess = maxf(excess, out_max[d] - in_max[d])

	return {"diag": in_diag, "excess": excess}

func _run_shape(name: String, boundary: PackedVector3Array, tgt: float, min_nf: int, check_inflation: bool) -> bool:
	var res: Dictionary = CassieTriangulator.triangulate(boundary, tgt)
	if not res.get("success", false):
		print("[shapes][FAIL] %s: triangulate returned success=false" % name)
		return false
	var verts: PackedVector3Array = res["vertices"]
	var faces: PackedInt32Array = res["faces"]
	var nf: int = faces.size() / 3
	if nf < min_nf:
		print("[shapes][FAIL] %s: nF=%d < min %d" % [name, nf, min_nf])
		return false
	if check_inflation:
		var b := _bounds_excess(boundary, verts)
		var threshold: float = 0.02 * b["diag"]
		if b["excess"] < threshold:
			print("[shapes][FAIL] %s: inflation excess %.4f < threshold %.4f (diag=%.4f)" % [name, b["excess"], threshold, b["diag"]])
			return false
		print("[shapes][PASS] %s: nB=%d tgt=%.2f -> nV=%d nF=%d excess=%.3f" % [name, boundary.size(), tgt, verts.size(), nf, b["excess"]])
	else:
		print("[shapes][PASS] %s: nB=%d tgt=%.2f -> nV=%d nF=%d" % [name, boundary.size(), tgt, verts.size(), nf])
	return true

func _sleeve() -> PackedVector3Array:
	const L: float = 4.0
	const W: float = 0.6
	var a: float = PI / 6.0
	var c: float = cos(a)
	var s: float = sin(a)
	var pts: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(L/3, 0, 0), Vector3(2*L/3, 0, 0), Vector3(L, 0, 0),
		Vector3(L, 0, W), Vector3(2*L/3, 0, W), Vector3(L/3, 0, W), Vector3(0, 0, W),
	]
	var rotated := PackedVector3Array()
	for p in pts:
		rotated.push_back(Vector3(c * p.x - s * p.z, p.y, s * p.x + c * p.z))
	return rotated

func _helix() -> PackedVector3Array:
	var b := PackedVector3Array()
	const N: int = 16
	const R: float = 1.5
	const H: float = 1.0
	for i in N:
		var t: float = float(i) / float(N - 1)
		var theta: float = 1.5 * PI * t
		b.push_back(Vector3(R * cos(theta), R * sin(theta), H * (t - 0.5)))
	return b

func _phone() -> PackedVector3Array:
	# Rounded-rectangle phone outline: four quarter-circles at the
	# corners + straight edges between them, traced CCW. cassie-
	# triangulation's original phone() shape has duplicate boundary
	# points (its right and left semicircles both pass through (0,0)
	# at i=0), which V-Sekai's DMWT can't tolerate. We use a clean
	# rounded rectangle instead -- same intent (curved corners +
	# straight edges, ~2x4 aspect), no degenerate inputs.
	var b := PackedVector3Array()
	const W: float = 2.0
	const H: float = 4.0
	const R: float = 0.6
	const ARC: int = 4
	# Bottom-right corner (center +x +y inward from corner).
	for i in ARC:
		var t: float = -PI/2 + (PI/2) * float(i) / float(ARC - 1)
		b.push_back(Vector3(W/2 - R + R * cos(t), -H/2 + R + R * sin(t), 0.0))
	# Top-right corner.
	for i in ARC:
		var t: float = 0.0 + (PI/2) * float(i) / float(ARC - 1)
		b.push_back(Vector3(W/2 - R + R * cos(t), H/2 - R + R * sin(t), 0.0))
	# Top-left corner.
	for i in ARC:
		var t: float = PI/2 + (PI/2) * float(i) / float(ARC - 1)
		b.push_back(Vector3(-W/2 + R + R * cos(t), H/2 - R + R * sin(t), 0.0))
	# Bottom-left corner.
	for i in ARC:
		var t: float = PI + (PI/2) * float(i) / float(ARC - 1)
		b.push_back(Vector3(-W/2 + R + R * cos(t), -H/2 + R + R * sin(t), 0.0))
	return b

func _star() -> PackedVector3Array:
	var b := PackedVector3Array()
	const N: int = 5
	const R_OUTER: float = 2.0
	const R_INNER: float = 0.8
	for i in N:
		var t_outer: float = -PI/2 + 2*PI * float(i) / float(N)
		b.push_back(Vector3(R_OUTER * cos(t_outer), R_OUTER * sin(t_outer), 0.0))
		var t_inner: float = t_outer + PI/N
		b.push_back(Vector3(R_INNER * cos(t_inner), R_INNER * sin(t_inner), 0.0))
	return b

func _triangle() -> PackedVector3Array:
	var b := PackedVector3Array()
	for i in 3:
		var t: float = 2.0 * PI * float(i) / 3.0
		b.push_back(Vector3(cos(t), sin(t), 0.0))
	return b

func _initialize() -> void:
	var fails: int = 0
	# Sleeve restored: V-Sekai DMWT was swapped for cassie-triangulation's
	# DMWT, which handles MingCurve's perturbation cleanly.
	if not _run_shape("sleeve",   _sleeve(),   0.15, 20, true):  fails += 1
	if not _run_shape("helix",    _helix(),    0.25, 8,  true):  fails += 1
	if not _run_shape("phone",    _phone(),    0.3,  20, true):  fails += 1
	if not _run_shape("star",     _star(),     0.3,  10, true):  fails += 1
	# nB=3: bare triangle; inflation effectively no-ops here (heat
	# d_max is tiny for a single triangle), so skip the AABB-excess
	# check. The point is "doesn't crash and yields >= 1 face".
	if not _run_shape("triangle", _triangle(), 0.3,  1,  false): fails += 1

	if fails == 0:
		print("[shapes] ALL PASS")
		quit(0)
	else:
		print("[shapes] %d FAILURES" % fails)
		quit(1)
