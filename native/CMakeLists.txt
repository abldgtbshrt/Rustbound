# Rustbound native library (GDExtension). See native/README.md.
#
#   cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Release
#   cmake --build native/build --config Release
#
# The library lands in bin/<platform>/ where bin/rustbound_native.gdextension
# expects it.
cmake_minimum_required(VERSION 3.13)
project(rustbound_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
	set(CMAKE_BUILD_TYPE Release)
endif()

if(APPLE)
	set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
endif()

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/godot-cpp/CMakeLists.txt")
	message(FATAL_ERROR "native/godot-cpp is missing. Run: git submodule update --init")
endif()
add_subdirectory(godot-cpp EXCLUDE_FROM_ALL)

add_library(rustbound_native SHARED src/horde_sim.cpp src/register_types.cpp)
target_link_libraries(rustbound_native PRIVATE godot-cpp)

if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
	set(RB_PLATFORM windows)
	if(MINGW)
		# Self-contained DLL: no libstdc++/libgcc DLLs needed next to it.
		target_link_options(rustbound_native PRIVATE -static -static-libgcc -static-libstdc++)
	endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
	set(RB_PLATFORM macos)
	set_target_properties(rustbound_native PROPERTIES SUFFIX ".dylib")
else()
	set(RB_PLATFORM linux)
endif()

if(MSVC)
	target_compile_options(rustbound_native PRIVATE /O2 /MD)
else()
	target_compile_options(rustbound_native PRIVATE -O2 -fno-exceptions -fvisibility=hidden)
endif()

if(RB_PLATFORM STREQUAL "macos")
	set(RB_ARCH "")
else()
	set(RB_ARCH ".x86_64")
endif()
set(RB_OUT "${CMAKE_CURRENT_SOURCE_DIR}/../bin/${RB_PLATFORM}")
set_target_properties(rustbound_native PROPERTIES
	PREFIX ""
	OUTPUT_NAME "rustbound_native.${RB_PLATFORM}${RB_ARCH}"
	LIBRARY_OUTPUT_DIRECTORY "${RB_OUT}"
	RUNTIME_OUTPUT_DIRECTORY "${RB_OUT}"
	LIBRARY_OUTPUT_DIRECTORY_RELEASE "${RB_OUT}"
	RUNTIME_OUTPUT_DIRECTORY_RELEASE "${RB_OUT}"
	LIBRARY_OUTPUT_DIRECTORY_DEBUG "${RB_OUT}"
	RUNTIME_OUTPUT_DIRECTORY_DEBUG "${RB_OUT}")
