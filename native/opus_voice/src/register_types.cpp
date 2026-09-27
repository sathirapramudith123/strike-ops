#include "register_types.h"

#include "opus_voice.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_opus_voice(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(OpusVoiceEncoder);
	GDREGISTER_CLASS(OpusVoiceDecoder);
}

void uninitialize_opus_voice(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT opus_voice_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_opus_voice);
	init_obj.register_terminator(uninitialize_opus_voice);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
