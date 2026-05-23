cmake_minimum_required(VERSION 3.17...3.30)

# V-Sekai.cassie GDExtension.
# Replaces the previous engine-module (SCons) build; targets stock
# Godot 4.4 via godot-cpp + a Geogram-backed Delaunay backend
# (mirrors the cassie-triangulation TetGen->Geogram swap).
project(cassie LANGUAGES CXX)

# Block find_package(OpenMP) globally. pmp-library does
# `find_package(OpenMP); target_link_libraries(pmp PUBLIC OpenMP::OpenMP_CXX)`
# which on MSVC propagates /openmp into our library and creates a
# VCOMP140.DLL runtime dependency. Godot's exported game/template
# build won't have vcomp140 next to the extension, and the user's
# machine may not have the VC++ redistributable, so the .dll fails
# to load there. Our workloads are mesh sizes in the dozens to
# hundreds of triangles -- OpenMP overhead dwarfs any parallel
# speedup. Plus EIGEN_DONT_PARALLELIZE to make sure no Eigen
# internal path tries to use OpenMP if some other dep still finds
# it. (Mirrors cassie-triangulation/CMakeLists.txt.)
set(CMAKE_DISABLE_FIND_PACKAGE_OpenMP TRUE)
add_compile_definitions(EIGEN_DONT_PARALLELIZE)

# --- Geogram options (must be set before add_subdirectory) ---
# Same exclusions used in cassie-triangulation/libs/CMakeLists.txt:
# strip every option whose license is incompatible with our shipping
# constraints, and disable everything that needs OpenGL / Lua /
# legacy numerics. The "BDEL" creator (native Geogram Delaunay3d)
# is always registered and is what the wrapper uses.
set(GEOGRAM_LIB_ONLY              ON  CACHE BOOL "" FORCE)
set(GEOGRAM_WITH_GRAPHICS         OFF CACHE BOOL "" FORCE)
set(GEOGRAM_WITH_LEGACY_NUMERICS  OFF CACHE BOOL "" FORCE)
set(GEOGRAM_WITH_HLBFGS           OFF CACHE BOOL "" FORCE)
set(GEOGRAM_WITH_TETGEN           OFF CACHE BOOL "" FORCE)
set(GEOGRAM_WITH_TRIANGLE         OFF CACHE BOOL "" FORCE)
set(GEOGRAM_WITH_LUA              OFF CACHE BOOL "" FORCE)

add_subdirectory(godot-cpp)
add_subdirectory(thirdparty/geogram)

# --- pmp-library options (must be set before add_subdirectory) ---
# Mirror cassie-triangulation/libs/CMakeLists.txt exactly. PMP is MIT;
# bundles Eigen 3.4.0 under external/ which is reached via its own
# FindEigen3.cmake. We use double precision throughout to match
# Eigen::MatrixXd usage in refine.cpp.
set(PMP_SCALAR_TYPE        64  CACHE STRING "" FORCE)
set(PMP_BUILD_EXAMPLES     OFF CACHE BOOL   "" FORCE)
set(PMP_BUILD_TESTS        OFF CACHE BOOL   "" FORCE)
set(PMP_BUILD_DOCS         OFF CACHE BOOL   "" FORCE)
set(PMP_BUILD_VIS          OFF CACHE BOOL   "" FORCE)
set(PMP_INSTALL            OFF CACHE BOOL   "" FORCE)
set(PMP_STRICT_COMPILATION OFF CACHE BOOL   "" FORCE)
set(BUILD_SHARED_LIBS      OFF CACHE BOOL   "" FORCE)
add_subdirectory(thirdparty/pmp-library)

# pmp-library only exposes its src include directory PUBLIC when
# PMP_INSTALL is ON; we keep it OFF, so add the include here.
target_include_directories(pmp PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/pmp-library/src>)

# pmp's own CMakeLists uses add_definitions(-DPMP_SCALAR_TYPE_64),
# which only reaches pmp's own compilation. Promote to PUBLIC so
# every consumer sees Scalar=double and pmp::Point layout matches.
target_compile_definitions(pmp PUBLIC PMP_SCALAR_TYPE_64)

set(TARGET_NAME cassie)

add_library(${TARGET_NAME} SHARED
    src/register_types.cpp
    src/register_types.h
    src/delaunay_geogram.cpp
    src/delaunay_geogram.h
    src/cassie_path_3d.cpp
    src/cassie_path_3d.h
    src/cassie_surface.cpp
    src/cassie_surface.h
    src/cassie_triangulator.cpp
    src/cassie_triangulator.h
    src/intrinsic_triangulation.cpp
    src/intrinsic_triangulation.h
    src/polygon_triangulation.cpp
    src/polygon_triangulation.h
    src/polygon_triangulation_godot.cpp
    src/polygon_triangulation_godot.h
    src/refine.cpp
    src/refine.h
    thirdparty/multipolygon_triangulator/DelaunayFaces.cpp
    thirdparty/multipolygon_triangulator/DelaunayFaces.h
    thirdparty/multipolygon_triangulator/DMWT.cpp
    thirdparty/multipolygon_triangulator/DMWT.h
    thirdparty/multipolygon_triangulator/DMWT_dot.cpp
    thirdparty/multipolygon_triangulator/EdgeInfo.cpp
    thirdparty/multipolygon_triangulator/EdgeInfo.h
    thirdparty/multipolygon_triangulator/MingCurve.cpp
    thirdparty/multipolygon_triangulator/MingCurve.h
    thirdparty/multipolygon_triangulator/Point3.cpp
    thirdparty/multipolygon_triangulator/Point3.h
    thirdparty/multipolygon_triangulator/Vector3.cpp
    thirdparty/multipolygon_triangulator/Vector3.h
    thirdparty/multipolygon_triangulator/Configure.h
    thirdparty/multipolygon_triangulator/Errors.h
    thirdparty/multipolygon_triangulator/TriangleInfo.cpp
    thirdparty/multipolygon_triangulator/TriangleInfo.h
)

target_include_directories(${TARGET_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/multipolygon_triangulator
)

target_link_libraries(${TARGET_NAME} PRIVATE godot-cpp geogram pmp)

# --- Class docs (godot-cpp documentation system) ---
# godot-cpp's target_doc_sources generates a single .cpp file from
# the XML class docs and compiles it into the extension. Godot
# reads the embedded docs out of the running .dll/.so via
# editor_help.cpp at startup. Only emitted for editor / debug
# targets (release templates don't ship the docs).
if(GODOTCPP_TARGET MATCHES "editor|template_debug")
    # godot-cpp's find_package(Python3) is scoped to its subdirectory,
    # so Python3_EXECUTABLE isn't visible here. Look it up ourselves.
    find_package(Python3 3.4 REQUIRED COMPONENTS Interpreter)

    file(GLOB DOC_XML LIST_DIRECTORIES NO CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/doc_classes/*.xml")

    # godot-cpp 4.4's target_doc_sources / generate_doc_source helpers
    # build the python -c invocation as a CMake list of two strings
    # ("import ...", "call ..."), which on Windows reaches Python as
    # TWO separate args — Python silently runs only the import and
    # never the call, so doc_source.cpp is never created. We bypass
    # the helper and emit a single-string python -c argument that
    # works under MSBuild's quoting.
    set(DOC_SOURCE_FILE "${CMAKE_CURRENT_BINARY_DIR}/gen/doc_source.cpp")
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/gen")

    add_custom_command(
        OUTPUT "${DOC_SOURCE_FILE}"
        COMMAND "${Python3_EXECUTABLE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/tools/gen_doc_source.py"
            "${godot-cpp_SOURCE_DIR}"
            "${DOC_SOURCE_FILE}"
            ${DOC_XML}
        VERBATIM
        DEPENDS
            "${CMAKE_CURRENT_SOURCE_DIR}/tools/gen_doc_source.py"
            "${godot-cpp_SOURCE_DIR}/doc_source_generator.py"
            ${DOC_XML}
        COMMENT "Generating ${DOC_SOURCE_FILE}"
    )
    target_sources(${TARGET_NAME} PRIVATE "${DOC_SOURCE_FILE}")
endif()

# Match godot-cpp's binary suffix convention so the .gdextension
# manifest can use a single naming scheme per platform.
get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)

set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin")

set_target_properties(${TARGET_NAME} PROPERTIES
    CXX_STANDARD 17
    CXX_EXTENSIONS OFF
    CXX_VISIBILITY_PRESET ${GODOTCPP_SYMBOL_VISIBILITY}
    POSITION_INDEPENDENT_CODE ON
    BUILD_RPATH_USE_ORIGIN ON
    LINK_SEARCH_START_STATIC ON
    LINK_SEARCH_END_STATIC ON
    LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    PDB_OUTPUT_DIRECTORY     "$<1:${OUTPUT_DIR}>"
    PREFIX "lib"
    OUTPUT_NAME "cassie${GODOTCPP_SUFFIX}"
)

if(CMAKE_SYSTEM_NAME STREQUAL Darwin)
    set_target_properties(${TARGET_NAME} PROPERTIES
        SUFFIX ""
        OUTPUT_DIR "${OUTPUT_DIR}/libcassie.macos.${GODOTCPP_TARGET}.framework"
    )
endif()
