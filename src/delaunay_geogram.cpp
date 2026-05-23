#include "delaunay_geogram.h"

#include <geogram/basic/common.h>
#include <geogram/basic/logger.h>
#include <geogram/basic/numeric.h>
#include <geogram/delaunay/delaunay.h>

#include <mutex>
#include <vector>

namespace cassie {

namespace {

// Initialize Geogram exactly once across all wrapper calls.
void ensure_geogram_initialized() {
    static std::once_flag init_flag;
    std::call_once(init_flag, []() {
        GEO::initialize(GEO::GEOGRAM_INSTALL_NONE);
        // Match the "Q" (quiet) flag the TetGen-era code used.
        GEO::Logger::instance()->set_quiet(true);
    });
}

// Geogram's RNG is process-global. Without resetting it per call,
// symbolic perturbation on near-degenerate inputs depends on the
// call ordering — a property test in cassie-triangulation caught a
// 68x output-size explosion between identical calls. Reset every
// time so callers see a stable pseudo-random sequence.
void reset_rng() { GEO::Numeric::random_reset(); }

}  // namespace

godot::Vector<DelaunayTriangle2D>
delaunay_triangulate_2d(const godot::PackedVector2Array &p_points) {
    godot::Vector<DelaunayTriangle2D> out;
    const int n = p_points.size();
    if (n < 3) {
        return out;
    }

    ensure_geogram_initialized();
    reset_rng();

    // Geogram wants a flat double* of coordinates.
    std::vector<double> coords;
    coords.resize(std::size_t(n) * 2u);
    for (int i = 0; i < n; ++i) {
        const godot::Vector2 &p = p_points[i];
        coords[std::size_t(i) * 2 + 0] = double(p.x);
        coords[std::size_t(i) * 2 + 1] = double(p.y);
    }

    GEO::Delaunay_var delaunay;
    try {
        delaunay = GEO::Delaunay::create(2, "BDEL2d");
        if (delaunay.get() == nullptr) {
            return out;
        }
        delaunay->set_vertices(GEO::index_t(n), coords.data());
    } catch (...) {
        return out;
    }

    // Note: nb_finite_cells() requires keeps_infinite()==true (asserted
    // in delaunay.h). With the default keeps_infinite=false the ghost
    // cells have already been pruned, so nb_cells() IS the finite
    // count. Saved ~4 hours of debugging in cassie-triangulation.
    const GEO::index_t nb_cells = delaunay->nb_cells();
    out.resize(int(nb_cells));
    for (GEO::index_t c = 0; c < nb_cells; ++c) {
        DelaunayTriangle2D tri;
        tri.points[0] = int(delaunay->cell_vertex(c, 0));
        tri.points[1] = int(delaunay->cell_vertex(c, 1));
        tri.points[2] = int(delaunay->cell_vertex(c, 2));
        out.write[int(c)] = tri;
    }
    return out;
}

godot::Vector<DelaunayTet3D>
delaunay_tetrahedralize_3d(const godot::PackedVector3Array &p_points) {
    godot::Vector<DelaunayTet3D> out;
    const int n = p_points.size();
    if (n < 4) {
        return out;
    }

    ensure_geogram_initialized();
    reset_rng();

    std::vector<double> coords;
    coords.resize(std::size_t(n) * 3u);
    for (int i = 0; i < n; ++i) {
        const godot::Vector3 &p = p_points[i];
        coords[std::size_t(i) * 3 + 0] = double(p.x);
        coords[std::size_t(i) * 3 + 1] = double(p.y);
        coords[std::size_t(i) * 3 + 2] = double(p.z);
    }

    GEO::Delaunay_var delaunay;
    try {
        delaunay = GEO::Delaunay::create(3, "BDEL");
        if (delaunay.get() == nullptr) {
            return out;
        }
        delaunay->set_vertices(GEO::index_t(n), coords.data());
    } catch (...) {
        return out;
    }

    const GEO::index_t nb_cells = delaunay->nb_cells();
    out.resize(int(nb_cells));
    for (GEO::index_t c = 0; c < nb_cells; ++c) {
        DelaunayTet3D tet;
        tet.points[0] = int(delaunay->cell_vertex(c, 0));
        tet.points[1] = int(delaunay->cell_vertex(c, 1));
        tet.points[2] = int(delaunay->cell_vertex(c, 2));
        tet.points[3] = int(delaunay->cell_vertex(c, 3));
        out.write[int(c)] = tet;
    }
    return out;
}

bool delaunay_triangulate_2d_raw(const double *p_xy_coords, int n_points,
        int **out_face_indices, int *out_face_count) {
    *out_face_indices = nullptr;
    *out_face_count = 0;
    if (p_xy_coords == nullptr || n_points < 3) {
        return false;
    }

    ensure_geogram_initialized();
    reset_rng();

    GEO::Delaunay_var delaunay;
    try {
        delaunay = GEO::Delaunay::create(2, "BDEL2d");
        if (delaunay.get() == nullptr) {
            return false;
        }
        delaunay->set_vertices(GEO::index_t(n_points), p_xy_coords);
    } catch (...) {
        return false;
    }

    const GEO::index_t nb_cells = delaunay->nb_cells();
    if (nb_cells == 0) {
        return false;
    }
    int *indices = new int[std::size_t(nb_cells) * 3u];
    for (GEO::index_t c = 0; c < nb_cells; ++c) {
        indices[c * 3 + 0] = int(delaunay->cell_vertex(c, 0));
        indices[c * 3 + 1] = int(delaunay->cell_vertex(c, 1));
        indices[c * 3 + 2] = int(delaunay->cell_vertex(c, 2));
    }
    *out_face_indices = indices;
    *out_face_count = int(nb_cells);
    return true;
}

}  // namespace cassie
