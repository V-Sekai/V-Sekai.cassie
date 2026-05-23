#pragma once

// Geogram-backed Delaunay shims that replace Godot's built-in
// Delaunay2D::triangulate / Delaunay3D::tetrahedralize. Backed by
// GEO::Delaunay::create(3, "BDEL") / create(2, "BDEL2d"). Mirrors the
// proven cassie-triangulation/src/Utility/DelaunayFaces wrapper but
// produces godot-cpp containers instead of std::vector<>.

#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace cassie {

// Triangle output for the 2D path (replaces Delaunay2D::Triangle).
struct DelaunayTriangle2D {
    int points[3];
};

// Tetrahedron output for the 3D path (replaces Delaunay3D::OutputSimplex).
struct DelaunayTet3D {
    int points[4];
};

// 2D Delaunay triangulation. Returns triangles whose three indices
// refer back into p_points. Empty result on degenerate input
// (fewer than 3 points or all colinear).
godot::Vector<DelaunayTriangle2D> delaunay_triangulate_2d(const godot::PackedVector2Array &p_points);

// 3D Delaunay tetrahedralization. Returns tetrahedra whose four
// indices refer back into p_points. Empty result on degenerate
// input (fewer than 4 points or all coplanar).
godot::Vector<DelaunayTet3D> delaunay_tetrahedralize_3d(const godot::PackedVector3Array &p_points);

// Non-godot-cpp overload for callers that have stride-3 doubles
// already (e.g. mwt::DMWT's coplanar branch). `p_xy_coords` has
// length 2*n_points; each consecutive pair is (x, y).
//
// Returns the flat face index list (`*out_face_indices`, length
// 3 * *out_face_count) — caller owns and must `delete[]` it.
// Returns false on degenerate input.
bool delaunay_triangulate_2d_raw(const double *p_xy_coords, int n_points,
        int **out_face_indices, int *out_face_count);

}  // namespace cassie
