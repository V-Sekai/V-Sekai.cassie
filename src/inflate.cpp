#include "inflate.h"

#include "heat_distance.h"

#include <Eigen/Eigenvalues>

#include <algorithm>
#include <cmath>
#include <vector>

namespace cassie {

void inflate(pmp::SurfaceMesh& mesh, double amplitude) {
    if (amplitude <= 0.0) return;
    if (mesh.n_vertices() == 0) return;

    // 1. PCA on boundary vertices to find the best-fit plane.
    std::vector<Eigen::Vector3d> boundary_pos;
    boundary_pos.reserve(mesh.n_vertices());
    for (auto v : mesh.vertices()) {
        if (mesh.is_boundary(v)) {
            const auto& p = mesh.position(v);
            boundary_pos.emplace_back(p[0], p[1], p[2]);
        }
    }
    if (boundary_pos.size() < 3) return;

    Eigen::Vector3d centroid = Eigen::Vector3d::Zero();
    for (const auto& p : boundary_pos) centroid += p;
    centroid /= double(boundary_pos.size());

    Eigen::Matrix3d cov = Eigen::Matrix3d::Zero();
    for (const auto& p : boundary_pos) {
        const Eigen::Vector3d d = p - centroid;
        cov += d * d.transpose();
    }
    Eigen::SelfAdjointEigenSolver<Eigen::Matrix3d> es(cov);
    Eigen::Vector3d normal = es.eigenvectors().col(0);
    // Eigenvectors come back with arbitrary sign; pick the variant
    // pointing roughly +Z so CASSIE inputs (typically drawn in the
    // XY plane facing the camera) inflate AWAY from the user, not
    // toward them. For boundaries with normal nearly perpendicular
    // to +Z the choice is still arbitrary -- a future caller might
    // pass an explicit "up" direction here.
    if (normal.dot(Eigen::Vector3d(0.0, 0.0, 1.0)) < 0.0) {
        normal = -normal;
    }

    // 2. Smooth distance-to-boundary via the heat method.
    const std::vector<double> dist = heat_distance(mesh);
    if (int(dist.size()) != int(mesh.n_vertices())) return;

    double d_max = 0.0;
    for (auto v : mesh.vertices()) {
        if (!mesh.is_boundary(v) && dist[v.idx()] > d_max) {
            d_max = dist[v.idx()];
        }
    }
    if (d_max <= 0.0) return;

    // 3. Displace interior vertices along the plane normal with a
    // hemispherical profile. Boundary vertices stay put.
    for (auto v : mesh.vertices()) {
        if (mesh.is_boundary(v)) continue;
        const double d = std::max(0.0, std::min(d_max, dist[v.idx()]));
        const double s = 1.0 - d / d_max;             // 1 at boundary, 0 at apex
        const double h = amplitude * d_max
                       * std::sqrt(std::max(0.0, 1.0 - s * s));
        auto& p = mesh.position(v);
        p[0] += pmp::Scalar(normal[0] * h);
        p[1] += pmp::Scalar(normal[1] * h);
        p[2] += pmp::Scalar(normal[2] * h);
    }
}

}  // namespace cassie
