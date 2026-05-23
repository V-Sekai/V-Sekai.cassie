#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

using namespace godot;

// Single-call multipolygon triangulator + refinement, mirroring the
// `Triangulate(double*, int, float, double**, int**, int*, int*)` flat C
// ABI from E:\cassie-triangulation\src\Triangulation.cpp, but exposed
// through godot-cpp instead of `extern "C"`.
//
// Pipeline (per cassie-triangulation/src/Triangulation.cpp):
//   1. Serialize concurrent callers (Geogram / pmp / Eigen have
//      process-global state that's not individually thread-safe).
//   2. Reset the Point3 perturb RNG for call-to-call determinism.
//   3. nB == 3 fast path: skip DMWT, run pmp::uniform_remeshing +
//      heat-method inflation directly on the input triangle.
//   4. Otherwise: MingCurve edge protection -> V-Sekai PolygonTriangulation
//      (DMWT) -> refine_patch (pmp isotropic_remeshing + inflate).
//
// Returns a Dictionary with keys:
//   - "success":  bool
//   - "vertices": PackedVector3Array
//   - "faces":    PackedInt32Array (length 3 * num_triangles)
class CassieTriangulator : public RefCounted {
    GDCLASS(CassieTriangulator, RefCounted);

protected:
    static void _bind_methods();

public:
    static Dictionary triangulate(const PackedVector3Array &p_boundary, float p_target_edge_length);

    CassieTriangulator() = default;
    ~CassieTriangulator() = default;
};
