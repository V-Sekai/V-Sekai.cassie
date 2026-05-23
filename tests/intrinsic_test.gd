@tool
extends SceneTree

# TDD-grown coverage of IntrinsicTriangulation: edge bookkeeping,
# Delaunay flips, statistics.

func _initialize() -> void:
	var fails: int = 0

	# Cycle 14: a quad split into two triangles by one diagonal has
	# exactly 5 edges (4 boundary + 1 shared interior). Tests that
	# build_initial_intrinsic_mesh dedupes the shared edge.
	var intr := IntrinsicTriangulation.new()
	intr.set_mesh_data(
		PackedVector3Array([
			Vector3(0, 0, 0),
			Vector3(1, 0, 0),
			Vector3(1, 1, 0),
			Vector3(0, 1, 0),
		]),
		PackedInt32Array([0, 1, 2,  0, 2, 3]),
		PackedVector3Array(),
	)
	if intr.get_edge_count() == 5 and intr.get_triangle_count() == 2 and intr.get_vertex_count() == 4:
		print("[intr][PASS] quad_edges: 4v 2t 5e")
	else:
		print("[intr][FAIL] quad_edges: %dv %dt %de" % [intr.get_vertex_count(), intr.get_triangle_count(), intr.get_edge_count()])
		fails += 1

	# Cycle 15: flip_to_delaunay must return true (converged) on a
	# trivially-Delaunay input. The unit square split along the
	# (0,2) diagonal already satisfies the Delaunay criterion --
	# both opposite-angle sums equal pi/2 + pi/2 = pi exactly.
	# Algorithm should do zero flips and report converged.
	if intr.flip_to_delaunay():
		print("[intr][PASS] flip_already_delaunay_converges")
	else:
		print("[intr][FAIL] flip_already_delaunay_converges: returned false")
		fails += 1

	# Cycle 16: get_statistics must include every documented key.
	# Defends against silent key renames in IntrinsicTriangulation::
	# get_statistics (intrinsic_triangulation.cpp).
	var stats: Dictionary = intr.get_statistics()
	var required_keys := ["vertex_count", "edge_count", "triangle_count",
			"average_edge_length", "min_edge_length", "max_edge_length"]
	var missing: PackedStringArray = PackedStringArray()
	for k in required_keys:
		if not stats.has(k):
			missing.push_back(k)
	if missing.is_empty():
		print("[intr][PASS] statistics_keys: 6/6 present")
	else:
		print("[intr][FAIL] statistics_keys missing: %s" % str(missing))
		fails += 1

	# Cycle 26: set_mesh accepts a full ArrayMesh as input (parallel
	# ingestion path to set_mesh_data). Build a 4-vert / 2-tri quad
	# ArrayMesh manually, hand it to a fresh IntrinsicTriangulation,
	# expect identical bookkeeping.
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2,  0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var intr2 := IntrinsicTriangulation.new()
	intr2.set_mesh(mesh, 0)
	if intr2.get_vertex_count() == 4 and intr2.get_triangle_count() == 2 and intr2.get_edge_count() == 5:
		print("[intr][PASS] set_mesh_arraymesh: 4v 2t 5e")
	else:
		print("[intr][FAIL] set_mesh_arraymesh: %dv %dt %de" % [intr2.get_vertex_count(), intr2.get_triangle_count(), intr2.get_edge_count()])
		fails += 1

	# Cycle 35: smooth_intrinsic_positions must actually move at
	# least one vertex (not a no-op). Fan mesh: 4 boundary corners +
	# 1 interior center, 4 fan triangles. The center is deliberately
	# offset; Laplacian smoothing should pull it toward the centroid.
	var fan := IntrinsicTriangulation.new()
	fan.set_mesh_data(
		PackedVector3Array([
			Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
			Vector3(0.8, 0.2, 0),  # interior, deliberately off-centroid
		]),
		PackedInt32Array([
			4, 0, 1,
			4, 1, 2,
			4, 2, 3,
			4, 3, 0,
		]),
		PackedVector3Array(),
	)
	var before := (fan.get_vertices() as PackedVector3Array)[4]
	fan.smooth_intrinsic_positions(10)
	var after := (fan.get_vertices() as PackedVector3Array)[4]
	if before.distance_to(after) > 0.01:
		print("[intr][PASS] smooth_moves_interior: %s -> %s (delta %.3f)" % [before, after, before.distance_to(after)])
	else:
		print("[intr][FAIL] smooth_moves_interior: %s -> %s (delta too small)" % [before, after])
		fails += 1

	if fails == 0:
		print("[intr] ALL PASS")
		quit(0)
	else:
		print("[intr] %d FAILURES" % fails)
		quit(1)
