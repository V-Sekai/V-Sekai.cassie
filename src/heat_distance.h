#pragma once

#include <pmp/surface_mesh.h>

#include <vector>

namespace cassie {

// Geodesic distance from the boundary to every vertex of `mesh`,
// computed via the heat method (Crane-Weischedel-Wardetzky 2013).
//
// Returns a vector of length mesh.n_vertices() where the i-th
// entry is the distance from vertex i to the nearest boundary
// point. Distance is 0 (within numerical noise) on boundary
// vertices and positive in the interior.
//
// The output is C^infty smooth in the interior -- no medial-axis
// ridges -- so it's safe to use as a height field for inflation.
//
// Cost per call: two sparse SimplicialLDLT factorizations on the
// cotangent Laplacian (V x V). For ~200-vertex meshes this is
// sub-millisecond on modern hardware.
std::vector<double> heat_distance(pmp::SurfaceMesh& mesh);

}  // namespace cassie
