#include "refine.h"

#include <pmp/algorithms/remeshing.h>
#include <pmp/surface_mesh.h>

#include <iostream>
#include <unordered_map>
#include <vector>

void refine_patch(const Eigen::MatrixXd& V, const Eigen::MatrixXi& F, float targetEdgeLength,
    Eigen::MatrixXd& V_fine, Eigen::MatrixXi& F_fine) {

    // Build pmp::SurfaceMesh from V, F.
    pmp::SurfaceMesh mesh;
    std::vector<pmp::Vertex> vmap;
    vmap.reserve(V.rows());
    for (Eigen::Index i = 0; i < V.rows(); ++i) {
        vmap.push_back(mesh.add_vertex(pmp::Point(V(i, 0), V(i, 1), V(i, 2))));
    }
    for (Eigen::Index i = 0; i < F.rows(); ++i) {
        mesh.add_triangle(vmap[F(i, 0)], vmap[F(i, 1)], vmap[F(i, 2)]);
    }

    // Mark the patch boundary as a feature curve so the remesher
    // preserves the input boundary shape (matches CGAL's
    // PMP::isotropic_remeshing(..., protect_constraints(true))).
    // pmp's split_long_edges places midpoints exactly on the feature
    // edge being split, so the polyline geometry survives intact.
    auto efeature = mesh.add_edge_property<bool>("e:feature", false);
    auto vfeature = mesh.add_vertex_property<bool>("v:feature", false);
    for (auto e : mesh.edges()) {
        if (mesh.is_boundary(e)) {
            efeature[e] = true;
            vfeature[mesh.vertex(e, 0)] = true;
            vfeature[mesh.vertex(e, 1)] = true;
        }
    }

    const unsigned int nb_iter = 3;
    pmp::uniform_remeshing(mesh, static_cast<pmp::Scalar>(targetEdgeLength),
                           nb_iter, /*use_projection=*/true);

    // No inflation pass: the remesher's use_projection=true keeps every
    // vertex on the DMWT-output surface (which interpolates the input
    // boundary), so the result is a clean refinement of the patch the
    // user drew. Adding a hemispherical bulge in either direction here
    // was a misfeature -- it produced "balloon" artefacts on planar
    // sketches and oriented the bulge inconsistently relative to the
    // user's view, which is what motivated removing it.

    // Write back to V_fine, F_fine.
    V_fine.setZero(static_cast<Eigen::Index>(mesh.n_vertices()), 3);
    F_fine.setZero(static_cast<Eigen::Index>(mesh.n_faces()), 3);

    std::unordered_map<pmp::IndexType, int> vmap2;
    vmap2.reserve(mesh.n_vertices());
    int vi = 0;
    for (auto v : mesh.vertices()) {
        const pmp::Point& p = mesh.position(v);
        V_fine.row(vi) << p[0], p[1], p[2];
        vmap2[v.idx()] = vi;
        ++vi;
    }

    int fi = 0;
    for (auto f : mesh.faces()) {
        int k = 0;
        for (auto v : mesh.vertices(f)) {
            F_fine(fi, k++) = vmap2[v.idx()];
        }
        ++fi;
    }
}
