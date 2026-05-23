#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "cassie_path_3d.h"
#include "cassie_surface.h"
#include "cassie_triangulator.h"
#include "intrinsic_triangulation.h"
#include "polygon_triangulation_godot.h"
#include "polygon_triangulation.h"

using namespace godot;

void initialize_cassie_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    GDREGISTER_CLASS(PolygonTriangulation);
    GDREGISTER_CLASS(PolygonTriangulationGodot);
    GDREGISTER_CLASS(CassiePath3D);
    GDREGISTER_CLASS(IntrinsicTriangulation);
    GDREGISTER_CLASS(CassieSurface);
    GDREGISTER_CLASS(CassieTriangulator);
}

void uninitialize_cassie_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT cassie_library_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(
            p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_cassie_module);
    init_obj.register_terminator(uninitialize_cassie_module);
    init_obj.set_minimum_library_initialization_level(
            MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
