# Opus voice codec GDExtension (Phase 5b).
#
#   tools/build_opus.sh             # every platform this machine can build
#   tools/build_opus.sh linux|windows|macos
#
# Downloads pinned sources (godot-cpp 4.4, libopus 1.5.2), links libopus
# statically and writes the library to addons/opus_voice/bin/.
cmake_minimum_required(VERSION 3.17)
project(opus_voice LANGUAGES C CXX)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# Keep libopus' symbols private to the library.
set(CMAKE_C_VISIBILITY_PRESET hidden)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

include(FetchContent)

# --- godot-cpp (4.4 branch, pinned) -----------------------------------------
set(GODOTCPP_TARGET template_release CACHE STRING "" FORCE)
FetchContent_Declare(
    godot_cpp
    GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
    GIT_TAG b0e3b1e4b78a606f48d162898afb5eeda533d2a9 # 4.4 branch, 2025
)

# --- libopus 1.5.2 (release tarball, checksum-verified) ----------------------
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_DRED OFF CACHE BOOL "" FORCE)
set(OPUS_OSCE OFF CACHE BOOL "" FORCE)
set(OPUS_DEEP_PLC OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    opus
    URL https://github.com/xiph/opus/releases/download/v1.5.2/opus-1.5.2.tar.gz
    URL_HASH SHA256=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)

FetchContent_MakeAvailable(godot_cpp opus)

# --- The extension -------------------------------------------------------------
add_library(opus_voice SHARED src/opus_voice.cpp src/opus_voice.h src/register_types.cpp src/register_types.h)
target_link_libraries(opus_voice PRIVATE godot::cpp opus)

if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(OV_PLATFORM windows)
    # No MinGW runtime DLLs next to the game.
    target_link_options(opus_voice PRIVATE -static -static-libgcc -static-libstdc++)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(OV_PLATFORM macos)
else()
    set(OV_PLATFORM linux)
    # Export only the GDExtension entry point (not libopus / libstdc++ symbols).
    target_link_options(opus_voice PRIVATE "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/src/exports.map")
    # Stay mapped until the process exits: the static C++ runtime registers
    # exit handlers that would otherwise point into unloaded code (crash on quit).
    target_link_options(opus_voice PRIVATE -Wl,-z,nodelete)
    if(NOT OV_ZIG) # Zig links its own libc++ statically
        target_link_options(opus_voice PRIVATE -static-libgcc -static-libstdc++)
    endif()
endif()
if(OV_PLATFORM STREQUAL "macos")
    # No build-machine path in the install name.
    if(NOT OV_ZIG) # Apple's linker: export only the entry point (Zig's lacks this flag)
        target_link_options(opus_voice PRIVATE "-Wl,-exported_symbol,_opus_voice_library_init")
    endif()
    set_target_properties(opus_voice PROPERTIES INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR ON)
endif()
if(NOT OV_PLATFORM STREQUAL "macos")
    target_link_options(opus_voice PRIVATE $<$<CONFIG:Release,MinSizeRel>:-s>) # strip
endif()

set(OV_PROCESSOR "${CMAKE_SYSTEM_PROCESSOR}")
if(CMAKE_OSX_ARCHITECTURES)
    set(OV_PROCESSOR "${CMAKE_OSX_ARCHITECTURES}")
endif()
if(OV_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
    set(OV_ARCH arm64)
else()
    set(OV_ARCH x86_64)
endif()

set(OV_OUT "${CMAKE_CURRENT_SOURCE_DIR}/../../addons/opus_voice/bin")
set_target_properties(opus_voice PROPERTIES
    CXX_STANDARD 17
    CXX_EXTENSIONS OFF
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
    PREFIX "lib"
    OUTPUT_NAME "opus_voice.${OV_PLATFORM}.${OV_ARCH}"
    LIBRARY_OUTPUT_DIRECTORY "$<1:${OV_OUT}>"
    RUNTIME_OUTPUT_DIRECTORY "$<1:${OV_OUT}>"
)
