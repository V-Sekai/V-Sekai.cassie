#include "heat_distance.h"

#include <pmp/algorithms/laplace.h>
#include <pmp/algorithms/numerics.h>

#include <Eigen/SparseCholesky>

#include <cmath>

namespace cassie {

std::vector<double> heat_distance(pmp::SurfaceMesh& mesh) {
    const int V = int(mesh.n_vertices());
    std::vector<double> phi_out(V, 0.0);
    if (V == 0) return phi_out;

    // 0. Locate boundary; bail if none.
    int n_boundary = 0;
    for (auto v : mesh.vertices()) {
        if (mesh.is_boundary(v)) ++n_boundary;
    }
    if (n_boundary == 0) return phi_out;

    // 1. Build discrete operators via pmp. The discretisation here
    // is the same one pmp::implicit_smoothing uses, so cotangent
    // weights are consistent across our entire pipeline.
    //
    // pmp's L is negative semi-definite -- M(i,i) is the negative
    // sum of off-diagonals -- so it's the "graph Laplacian" sign
    // convention, equal to -L_math (Crane uses the positive L_math).
    pmp::SparseMatrix L, G, D;
    pmp::DiagonalMatrix M;
    pmp::laplace_matrix(mesh, L);
    pmp::mass_matrix(mesh, M);
    pmp::gradient_matrix(mesh, G);
    pmp::divergence_matrix(mesh, D);

    // 2. Source vector: 1 on boundary vertices, 0 on interior.
    // We want distance=0 on boundary, so heat starts there.
    Eigen::VectorXd u0 = Eigen::VectorXd::Zero(V);
    for (auto v : mesh.vertices()) {
        if (mesh.is_boundary(v)) u0[v.idx()] = 1.0;
    }

    // 3. Time step: Crane et al. recommend t = m^2 where m is the
    // mean edge length. Larger t blurs more (smoother distances,
    // less accurate); smaller t is sharper but accumulates more
    // numerical error in the gradient normalisation step.
    double mean_edge_len = 0.0;
    int n_edges = 0;
    for (auto e : mesh.edges()) {
        const auto& p0 = mesh.position(mesh.vertex(e, 0));
        const auto& p1 = mesh.position(mesh.vertex(e, 1));
        const double dx = p0[0] - p1[0];
        const double dy = p0[1] - p1[1];
        const double dz = p0[2] - p1[2];
        mean_edge_len += std::sqrt(dx*dx + dy*dy + dz*dz);
        ++n_edges;
    }
    if (n_edges > 0) mean_edge_len /= double(n_edges);
    const double t = mean_edge_len * mean_edge_len;

    // 4. Heat solve: (M - t*L) u = M * u0.
    // pmp_L is negative semi-definite, so (M - t*pmp_L) is positive
    // definite for t > 0 -- standard Cholesky works.
    pmp::SparseMatrix A1 = pmp::SparseMatrix(M) - t * L;
    Eigen::SimplicialLDLT<pmp::SparseMatrix> chol1(A1);
    if (chol1.info() != Eigen::Success) return phi_out;
    const Eigen::VectorXd u = chol1.solve(M * u0);

    // 5. Gradient of u: G * u is a 3*nHe vector (3D vector per
    // non-boundary halfedge, stride 3). Since u is high on boundary
    // and low in interior, ∇u points TOWARD the boundary. Flip
    // sign and normalise to get a unit field X pointing AWAY from
    // the boundary -- the direction the distance function grows.
    const Eigen::VectorXd grad = G * u;
    const Eigen::Index n_vec = grad.size() / 3;
    Eigen::VectorXd X(grad.size());
    for (Eigen::Index i = 0; i < n_vec; ++i) {
        const double gx = grad[3*i + 0];
        const double gy = grad[3*i + 1];
        const double gz = grad[3*i + 2];
        const double mag = std::sqrt(gx*gx + gy*gy + gz*gz);
        if (mag > 1e-12) {
            X[3*i + 0] = -gx / mag;
            X[3*i + 1] = -gy / mag;
            X[3*i + 2] = -gz / mag;
        } else {
            X[3*i + 0] = X[3*i + 1] = X[3*i + 2] = 0.0;
        }
    }

    // 6. Poisson solve: Crane writes L_math * phi = ∇·X (positive
    // Laplacian convention). pmp_L = -L_math, so the system is
    // -pmp_L * phi = D * X.
    //
    // L is rank-deficient by 1 (constants are in the null space),
    // so add a small Tikhonov term proportional to mass to make
    // the system positive definite. Epsilon chosen small enough
    // not to bias the result more than ~1e-6 relative.
    pmp::SparseMatrix A2 = -L + 1e-8 * pmp::SparseMatrix(M);
    Eigen::SimplicialLDLT<pmp::SparseMatrix> chol2(A2);
    if (chol2.info() != Eigen::Success) return phi_out;
    // pmp's gradient_matrix and divergence_matrix have a sign
    // convention such that the composed Laplacian D*G equals pmp's
    // negative semi-definite L (not Crane's positive L_math). The
    // straightforward translation of Crane's L_math * phi = div(X)
    // therefore produces a result with FLIPPED sign relative to
    // distance. Empirically: solving (-L + eps*M) phi = D*X gives
    // phi negative in the interior, zero on boundary. Negate to
    // get the conventional distance (zero on boundary, positive
    // in the interior).
    Eigen::VectorXd phi = -chol2.solve(D * X);

    // 7. Shift so the mean boundary value is exactly zero. The
    // regularisation in step 6 picks a particular solution out of
    // the L-kernel-equivalence class; this shifts to the one with
    // phi=0 on the boundary, which is what callers want.
    double phi_b_sum = 0.0;
    for (auto v : mesh.vertices()) {
        if (mesh.is_boundary(v)) phi_b_sum += phi[v.idx()];
    }
    phi.array() -= phi_b_sum / double(n_boundary);

    for (int i = 0; i < V; ++i) phi_out[i] = phi[i];
    return phi_out;
}

}  // namespace cassie
