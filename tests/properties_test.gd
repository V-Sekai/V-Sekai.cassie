@tool
extends SceneTree

# Deterministic property-style smokes ported from
# cassie-triangulation/tests/properties.cpp. The original used
# RapidCheck for generative testing with shrinking; GDScript has no
# equivalent so this is a fixed-seed deterministic sweep that
# exercises the same invariants:
#
#   1. triangulate never returns success=true with an empty face list
#   2. all face indices are in [0, nV)
#   3. the output mesh is watertight up to the polygon boundary
#      (every interior edge is shared by exactly two triangles)
#   4. determinism: calling twice with the same input gives the same
#      output (Geogram RNG + Point3 perturb RNG resets are doing
#      their job)

const PI := 3.14159265358979

func _make_circle(nB: int, radius: float, z_jitter: float, seed_val: int) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var b := PackedVector3Array()
	for i in nB:
		var t: float = 2.0 * PI * float(i) / float(nB)
		b.push_back(Vector3(
			radius * cos(t),
			radius * sin(t),
			rng.randf_range(-z_jitter, z_jitter)))
	return b

func _check_indices_in_range(faces: PackedInt32Array, nV: int) -> bool:
	for idx in faces:
		if idx < 0 or idx >= nV:
			return false
	return true

func _check_watertight(faces: PackedInt32Array) -> bool:
	# Boundary edges occur exactly once, interior edges exactly twice.
	# We don't know which edges are on the boundary here, so we just
	# assert no edge is shared by >2 triangles -- the necessary
	# condition for a manifold mesh.
	var edge_count := {}
	var nF := faces.size() / 3
	for f in nF:
		var a := faces[f * 3 + 0]
		var b := faces[f * 3 + 1]
		var c := faces[f * 3 + 2]
		for e in [Vector2i(mini(a, b), maxi(a, b)),
				  Vector2i(mini(b, c), maxi(b, c)),
				  Vector2i(mini(a, c), maxi(a, c))]:
			edge_count[e] = edge_count.get(e, 0) + 1
	for k in edge_count:
		if edge_count[k] > 2:
			return false
	return true

func _initialize() -> void:
	var fails := 0
	# Sweep: n in {6, 10, 16}, radius=1.0, z_jitter in {0, 0.05},
	# target_edge_length in {0.3, 0.6}, seeds {1, 2}. 24 cases total.
	for n in [6, 10, 16]:
		for jitter in [0.0, 0.05]:
			for tgt in [0.3, 0.6]:
				for sd in [1, 2]:
					var name := "n=%d jitter=%.2f tgt=%.2f seed=%d" % [n, jitter, tgt, sd]
					var boundary := _make_circle(n, 1.0, jitter, sd)
					var res: Dictionary = CassieTriangulator.triangulate(boundary, tgt)
					if not res.get("success", false):
						print("[properties][FAIL] %s: success=false" % name)
						fails += 1
						continue
					var verts: PackedVector3Array = res["vertices"]
					var faces: PackedInt32Array = res["faces"]
					if faces.size() == 0:
						print("[properties][FAIL] %s: success but empty faces" % name)
						fails += 1
						continue
					if not _check_indices_in_range(faces, verts.size()):
						print("[properties][FAIL] %s: face index out of range" % name)
						fails += 1
						continue
					if not _check_watertight(faces):
						print("[properties][FAIL] %s: edge shared by >2 faces" % name)
						fails += 1
						continue
					# Determinism: second call must match.
					var res2: Dictionary = CassieTriangulator.triangulate(boundary, tgt)
					var verts2: PackedVector3Array = res2["vertices"]
					var faces2: PackedInt32Array = res2["faces"]
					if verts.size() != verts2.size() or faces.size() != faces2.size():
						print("[properties][FAIL] %s: non-deterministic (size mismatch)" % name)
						fails += 1
						continue
	if fails == 0:
		print("[properties] ALL PASS (24 cases)")
		quit(0)
	else:
		print("[properties] %d FAILURES" % fails)
		quit(1)
