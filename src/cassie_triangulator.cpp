#include "cassie_triangulator.h"

#include "refine.h"

#include "../thirdparty/multipolygon_triangulator/DMWT.h"
#include "../thirdparty/multipolygon_triangulator/MingCurve.h"
#include "../thirdparty/multipolygon_triangulator/Point3.h"

#include "polygon_triangulation.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/templates/vector.hpp>

#include <Eigen/Core>

#include <cmath>
#include <mutex>
#include <vector>

void CassieTriangulator::_bind_methods() {
    ClassDB::bind_static_method("CassieTriangulator",
            D_METHOD("triangulate", "boundary", "target_edge_length"),
            &CassieTriangulator::triangulate);
}

namespace {

Dictionary make_failure() {
    Dictionary out;
    out["success"] = false;
    out["vertices"] = PackedVector3Array();
    out["faces"] = PackedInt32Array();
    return out;
}

Dictionary matrices_to_dict(const Eigen::MatrixXd &V_fine, const Eigen::MatrixXi &F_fine) {
    PackedVector3Array verts;
    verts.resize(int(V_fine.rows()));
    for (Eigen::Index i = 0; i < V_fine.rows(); ++i) {
        verts.set(int(i), Vector3(float(V_fine(i, 0)), float(V_fine(i, 1)), float(V_fine(i, 2))));
    }

    PackedInt32Array faces;
    faces.resize(int(F_fine.rows() * 3));
    for (Eigen::Index i = 0; i < F_fine.rows(); ++i) {
        faces.set(int(i * 3 + 0), F_fine(i, 0));
        faces.set(int(i * 3 + 1), F_fine(i, 1));
        faces.set(int(i * 3 + 2), F_fine(i, 2));
    }

    Dictionary out;
    out["success"] = true;
    out["vertices"] = verts;
    out["faces"] = faces;
    return out;
}

}  // namespace

Dictionary CassieTriangulator::triangulate(const PackedVector3Array &p_boundary, float p_target_edge_length) {
    // Match cassie-triangulation/src/Triangulation.cpp's coarse mutex.
    // Geogram's Numeric::random_engine, pmp's per-instance properties,
    // and Eigen's parallel solver all carry process-global state that
    // intermittently triggers STATUS_HEAP_CORRUPTION under concurrent
    // calls. Per-call latency is ~1.6 ms; serialized throughput
    // ceiling (~600 calls/sec) is well above any sane caller.
    static std::mutex triangulate_mu;
    std::lock_guard<std::mutex> lock(triangulate_mu);

    // MingCurve's edge-protection retry loop calls Point3::pertube on
    // degenerate inputs (coplanar polygons). pertube uses a thread-local
    // mt19937; reset here so consecutive calls on the same input take
    // the same perturbation path. Pairs with the Geogram RNG reset
    // inside delaunay_geogram.cpp.
    mwt::reset_perturb_rng(0u);

    const int nB = p_boundary.size();
    if (nB < 3) {
        return make_failure();
    }

    // Reject non-positive target_edge_length. pmp's split_long_edges
    // loop divides by the target; <= 0 causes either divide-by-zero
    // or a non-terminating split loop (every edge stays "too long").
    // NaN passes neither comparison so it also lands here.
    if (!(p_target_edge_length > 0.0f)) {
        return make_failure();
    }

    // Flatten the boundary to a stride-3 double array (the form
    // MingCurve / DMWT / refine_patch consume).
    std::vector<double> flat_boundary;
    flat_boundary.reserve(std::size_t(nB) * 3u);
    for (int i = 0; i < nB; ++i) {
        const Vector3 p = p_boundary[i];
        flat_boundary.push_back(double(p.x));
        flat_boundary.push_back(double(p.y));
        flat_boundary.push_back(double(p.z));
    }

    // nB == 3 fast path: DMWT's edge-protection wants 4+ points; a
    // 3-vertex polygon IS a single triangle, so feed it straight into
    // refine_patch and skip the rest.
    if (nB == 3) {
        // Reject degenerate triangles (collinear / zero-area). pmp's
        // remeshing + heat solver don't cope with these (crash inside
        // Eigen's Cholesky) and downstream callers can't use them
        // either.
        const double ax = flat_boundary[0], ay = flat_boundary[1], az = flat_boundary[2];
        const double bx = flat_boundary[3], by = flat_boundary[4], bz = flat_boundary[5];
        const double cx = flat_boundary[6], cy = flat_boundary[7], cz = flat_boundary[8];
        const double e1x = bx - ax, e1y = by - ay, e1z = bz - az;
        const double e2x = cx - ax, e2y = cy - ay, e2z = cz - az;
        const double nx = e1y * e2z - e1z * e2y;
        const double ny = e1z * e2x - e1x * e2z;
        const double nz = e1x * e2y - e1y * e2x;
        const double area = 0.5 * std::sqrt(nx * nx + ny * ny + nz * nz);
        if (area < 1e-9) {
            return make_failure();
        }
        Eigen::MatrixXd V_in(3, 3);
        Eigen::MatrixXi F_in(1, 3);
        for (int i = 0; i < 3; ++i) {
            V_in(i, 0) = flat_boundary[3 * i + 0];
            V_in(i, 1) = flat_boundary[3 * i + 1];
            V_in(i, 2) = flat_boundary[3 * i + 2];
            F_in(0, i) = i;
        }
        Eigen::MatrixXd V_fine;
        Eigen::MatrixXi F_fine;
        refine_patch(V_in, F_in, p_target_edge_length, V_fine, F_fine);
        return matrices_to_dict(V_fine, F_fine);
    }

    // nB >= 4: full cassie-triangulation pipeline.
    // 1. MingCurve preprocesses the boundary (edge-protection
    //    perturbation for near-coplanar / thin inputs). Validated
    //    to combine cleanly with cassie-triangulation's DMWT --
    //    the V-Sekai DMWT it replaced couldn't tolerate the
    //    perturbation points MingCurve emits.
    const int point_limit = 1000000;
    const bool with_norm = false;
    mwt::MingCurve curve(flat_boundary.data(), nB, point_limit, with_norm);
    if (!curve.edgeProtect(true)) {
        return make_failure();
    }

    const int ptn = curve.getNumOfPoints();
    double *pts = curve.getPoints();
    double *deGenPts = curve.getDeGenPoints();
    const bool is_de_gen = curve.isDeGen;

    // 2. mwt::DMWT (cassie-triangulation algorithm). Weights match
    //    cassie-triangulation/src/Triangulation.cpp defaults:
    //    bitri=1, tribd=1, others=0.
    mwt::DMWT dmwt(ptn, pts, deGenPts, is_de_gen);
    dmwt.setWeights(0.0f, 0.0f, 1.0f, 1.0f, 0.0f);
    dmwt.setDot(false);
    dmwt.preprocess();
    if (!dmwt.start()) {
        return make_failure();
    }

    // 3. Pull DMWT's result into V, F (Eigen). DMWT::getResultAsMatrices
    //    fills V from the (perturbed) input points and F from the
    //    optimal tiling indices.
    Eigen::MatrixXd V;
    Eigen::MatrixXi F;
    dmwt.getResultAsMatrices(V, F);

    // 4. pmp::uniform_remeshing with use_projection=true. No inflation
    //    pass -- output stays on the DMWT surface (which interpolates
    //    the input boundary), matching the patch the user drew.
    Eigen::MatrixXd V_fine;
    Eigen::MatrixXi F_fine;
    refine_patch(V, F, p_target_edge_length, V_fine, F_fine);

    return matrices_to_dict(V_fine, F_fine);
}
