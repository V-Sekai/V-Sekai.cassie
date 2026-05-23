#include "DelaunayFaces.h"

#include <geogram/basic/common.h>
#include <geogram/basic/logger.h>
#include <geogram/basic/numeric.h>
#include <geogram/delaunay/delaunay.h>

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <unordered_set>
#include <vector>

namespace {

void ensure_geogram_initialized() {
    static std::once_flag init_flag;
    std::call_once(init_flag, []() {
        GEO::initialize(GEO::GEOGRAM_INSTALL_NONE);
        // Match TetGen's "Q" (quiet) flag.
        GEO::Logger::instance()->set_quiet(true);
    });
}

// Hash a sorted triple of 32-bit vertex indices into a single 64-bit key.
// Indices fit in 21 bits each (max ~2M points) which is plenty for the
// inputs this codebase produces.
struct TriangleKeyHash {
    std::size_t operator()(uint64_t k) const noexcept {
        // FNV-style mix; std::hash<uint64_t> would be fine too.
        k ^= k >> 33;
        k *= 0xff51afd7ed558ccdULL;
        k ^= k >> 33;
        k *= 0xc4ceb9fe1a85ec53ULL;
        k ^= k >> 33;
        return static_cast<std::size_t>(k);
    }
};

uint64_t make_key(int a, int b, int c) {
    // a < b < c by caller contract.
    return (uint64_t(uint32_t(a)) << 42) | (uint64_t(uint32_t(b)) << 21) |
           uint64_t(uint32_t(c));
}

}  // namespace

namespace cassie {

DelaunayFaces::DelaunayFaces() = default;

DelaunayFaces::~DelaunayFaces() { clear(); }

void DelaunayFaces::clear() {
    delete[] trifacelist;
    trifacelist      = nullptr;
    numberoftrifaces = 0;
}

bool DelaunayFaces::compute(const double* points, int npoints) {
    clear();
    if (points == nullptr || npoints < 4) {
        // Fewer than 4 points cannot form a tet; mirror TetGen's
        // "no trifaces" outcome that the caller already handles.
        return false;
    }

    ensure_geogram_initialized();

    // Geogram's Delaunay implementation uses Numeric::random_int32()
    // for insertion hints and tie-breaking on near-degenerate inputs.
    // The underlying mt19937_64 is process-global and advances across
    // calls, which makes the symbolic-perturbation path different on
    // every call. For a near-coplanar input that visibly changes the
    // resulting tetrahedralization and, downstream, the candidate
    // triangle set DMWT picks from -- the mesh that ships to the
    // caller can vary by orders of magnitude in vertex count. Reset
    // the RNG here so every Triangulate(...) call sees the same
    // pseudo-random sequence.
    GEO::Numeric::random_reset();

    GEO::Delaunay_var delaunay;
    try {
        delaunay = GEO::Delaunay::create(3, "BDEL");
        if (delaunay.get() == nullptr) {
            return false;
        }
        delaunay->set_vertices(GEO::index_t(npoints), points);
    } catch (const std::exception&) {
        return false;
    } catch (...) {
        return false;
    }

    // Walk every tet and emit its 4 triangular facets,
    // deduplicating by sorted vertex-index triple. Geogram's
    // facet-vs-local-vertex convention: facet f is opposite local
    // vertex f, so its 3 vertices are the other three locals.
    //
    // Note: nb_finite_cells() requires keeps_infinite() to be true
    // (asserted in delaunay.h). With the default keeps_infinite=false
    // all cells are already finite (the infinite ghost tets have
    // been pruned during compression), so nb_cells() IS the finite
    // cell count.
    const GEO::index_t nb_cells = delaunay->nb_cells();
    std::unordered_set<uint64_t, TriangleKeyHash> seen;
    seen.reserve(std::size_t(nb_cells) * 4u);

    // Local-facet -> 3 local vertices (the ones NOT equal to the
    // facet index). Standard tetrahedron facet layout.
    static const int kFacetVerts[4][3] = {
        {1, 2, 3},
        {0, 2, 3},
        {0, 1, 3},
        {0, 1, 2},
    };

    std::vector<int> tris;
    tris.reserve(std::size_t(nb_cells) * 12u);

    for (GEO::index_t c = 0; c < nb_cells; ++c) {
        int v[4];
        for (int i = 0; i < 4; ++i) {
            v[i] = int(delaunay->cell_vertex(c, GEO::index_t(i)));
        }
        for (int f = 0; f < 4; ++f) {
            int a = v[kFacetVerts[f][0]];
            int b = v[kFacetVerts[f][1]];
            int d = v[kFacetVerts[f][2]];
            if (a > b) std::swap(a, b);
            if (b > d) std::swap(b, d);
            if (a > b) std::swap(a, b);
            if (seen.insert(make_key(a, b, d)).second) {
                tris.push_back(a);
                tris.push_back(b);
                tris.push_back(d);
            }
        }
    }

    if (tris.empty()) {
        return false;
    }

    numberoftrifaces = int(tris.size() / 3);
    trifacelist      = new int[tris.size()];
    std::copy(tris.begin(), tris.end(), trifacelist);
    return true;
}

}  // namespace cassie
