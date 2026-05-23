@tool
extends SceneTree

# TDD-grown coverage of CassieSurface, the orchestrator that chains
# CassiePath3D + PolygonTriangulationGodot + IntrinsicTriangulation.

func _initialize() -> void:
	var fails: int = 0

	# Cycle 24: end-to-end pipeline. Build a single CassiePath3D
	# boundary (square-ish pentagon), add to a CassieSurface, call
	# generate_surface(). Expect non-null ArrayMesh with at least
	# one surface. Disable intrinsic remeshing to keep the test
	# focused on the triangulation + headless-fallback path.
	var path := CassiePath3D.new()
	for v in [Vector3(0,0,0), Vector3(1,0,0), Vector3(1.5,0.5,0),
			  Vector3(1,1,0), Vector3(0,1,0)]:
		path.add_point(v, Vector3(0, 0, 1))

	var surface := CassieSurface.new()
	surface.add_boundary_path(path)
	surface.set_auto_beautify(false)
	surface.set_auto_resample(false)
	surface.set_use_intrinsic_remeshing(false)

	var mesh: ArrayMesh = surface.generate_surface()
	if mesh != null and mesh.get_surface_count() > 0:
		print("[surf][PASS] generate_surface: %d surface(s)" % mesh.get_surface_count())
	else:
		print("[surf][FAIL] generate_surface returned null or empty")
		fails += 1

	# Cycle 25: same pipeline with intrinsic remeshing enabled. The
	# extra IntrinsicTriangulation pass replaces the base mesh with
	# a (possibly identical) re-triangulated copy; must still yield
	# a non-null ArrayMesh with at least one surface.
	var path2 := CassiePath3D.new()
	for v in [Vector3(0,0,0), Vector3(1,0,0), Vector3(1.5,0.5,0),
			  Vector3(1,1,0), Vector3(0,1,0)]:
		path2.add_point(v, Vector3(0, 0, 1))
	var surf2 := CassieSurface.new()
	surf2.add_boundary_path(path2)
	surf2.set_auto_beautify(false)
	surf2.set_auto_resample(false)
	surf2.set_use_intrinsic_remeshing(true)
	var mesh2: ArrayMesh = surf2.generate_surface()
	if mesh2 != null and mesh2.get_surface_count() > 0:
		print("[surf][PASS] generate_surface_with_intrinsic: %d surface(s)" % mesh2.get_surface_count())
	else:
		print("[surf][FAIL] generate_surface_with_intrinsic returned null or empty")
		fails += 1

	# Cycle 37: add_boundary_path(null) is rejected. cassie_surface.cpp:75
	# uses ERR_FAIL_COND_MSG(p_path.is_null(), ...). Count must NOT
	# increment when a null Ref<CassiePath3D> is passed.
	var surf3 := CassieSurface.new()
	surf3.add_boundary_path(null)  # prints error to stderr; must not crash
	if surf3.get_boundary_path_count() == 0:
		print("[surf][PASS] null_path_rejected: count stays 0")
	else:
		print("[surf][FAIL] null_path_rejected: count is %d" % surf3.get_boundary_path_count())
		fails += 1

	# Cycle 38: clear_boundary_paths resets count to 0 (matches
	# CassiePath3D.clear_points pattern from cycle 27).
	var surf4 := CassieSurface.new()
	var p1 := CassiePath3D.new()
	p1.add_point(Vector3(0, 0, 0))
	var p2 := CassiePath3D.new()
	p2.add_point(Vector3(1, 0, 0))
	surf4.add_boundary_path(p1)
	surf4.add_boundary_path(p2)
	if surf4.get_boundary_path_count() != 2:
		print("[surf][FAIL] clear_boundary_paths precondition: count=%d" % surf4.get_boundary_path_count())
		fails += 1
	surf4.clear_boundary_paths()
	if surf4.get_boundary_path_count() == 0:
		print("[surf][PASS] clear_boundary_paths: count=0")
	else:
		print("[surf][FAIL] clear_boundary_paths: count still %d" % surf4.get_boundary_path_count())
		fails += 1

	if fails == 0:
		print("[surf] ALL PASS")
		quit(0)
	else:
		print("[surf] %d FAILURES" % fails)
		quit(1)
