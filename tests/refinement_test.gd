@tool
extends SceneTree

# Ported from cassie-triangulation/tests/refinement.cpp.
# Calls CassieTriangulator.triangulate three times on the same
# hex-antiprism input with progressively halved target_edge_length
# and asserts the output face count is non-decreasing each time
# (refinement monotonicity).

const PI := 3.14159265358979

func _initialize() -> void:
	var b := PackedVector3Array()
	for i in 6:
		var t: float = 2.0 * PI * float(i) / 6.0
		var z: float = 0.5 if i % 2 == 0 else -0.5
		b.push_back(Vector3(2.0 * cos(t), 2.0 * sin(t), z))

	var targets: Array[float] = [1.0, 0.5, 0.25]
	var prev_nf: int = 0
	for tgt in targets:
		var res: Dictionary = CassieTriangulator.triangulate(b, tgt)
		if not res.get("success", false):
			print("[refinement][FAIL] triangulate returned success=false for tgt=%.2f" % tgt)
			quit(1)
			return
		var faces: PackedInt32Array = res["faces"]
		var nf: int = faces.size() / 3
		print("[refinement] tgt=%.2f -> nV=%d nF=%d" % [tgt, (res["vertices"] as PackedVector3Array).size(), nf])
		if nf < prev_nf:
			print("[refinement][FAIL] nF decreased (%d -> %d) as target halved" % [prev_nf, nf])
			quit(1)
			return
		prev_nf = nf

	print("[refinement] ALL PASS")
	quit(0)
