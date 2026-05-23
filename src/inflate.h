#pragma once

#include <pmp/surface_mesh.h>

namespace cassie {

// Teddy-style inflation (Igarashi 1999) backed by heat-method
// geodesic distance (Crane-Weischedel-Wardetzky 2013) instead of
// the C0 distance-to-polygon used in the earlier version of this
// file. The smooth geodesic distance eliminates the medial-axis
// ridges that came with min-over-edges Euclidean distance.
//
// Algorithm:
//   1. heat_distance(mesh) -> smooth scalar field d, zero on
//      boundary and positive in the interior.
//   2. PCA on boundary vertices -> plane normal n.
//   3. d_max = max(d). Displace each interior vertex along n by
//        h(d) = amplitude * d_max * sqrt(1 - (1 - d/d_max)^2)
//      which is the hemispherical profile -- continuously, this
//      gives an exact hemisphere on a circular boundary.
//
// The profile has unbounded gradient at the apex (d=d_max), but
// d itself is C-infty smooth (heat-method output), so the
// composed height field is smooth except at the apex. Apex
// non-smoothness is local to one vertex and doesn't propagate
// into the visible mesh the way medial-axis ridges did.
void inflate(pmp::SurfaceMesh& mesh, double amplitude);

}  // namespace cassie
