cmake_minimum_required(VERSION 3.27)
project(native LANGUAGES OBJC CXX OBJCXX)
set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "" FORCE)

set(CMAKE_CXX_STANDARD 17)
set(FLUTTER_ENGINE_VARIANT "host_debug_unopt" CACHE STRING "")

add_library(native SHARED library.mm)
## METAL
find_library(METAL_FRAMEWORK Metal)
find_library(METALKIT_FRAMEWORK MetalKit)
find_library(OPENGL_FRAMEWORK OpenGL)

target_link_libraries(native
        ${METAL_FRAMEWORK}
        ${METALKIT_FRAMEWORK}
        ${OPENGL_FRAMEWORK}
)

# downloaded yours is from the internet you'll have to change this.
#include_directories(${CMAKE_SOURCE_DIR}/out/include)
#target_link_libraries(native ${CMAKE_SOURCE_DIR}/out/bin/flutter_engine.dylib)

find_library(FLUTTER_FRAMEWORK FlutterEmbedder PATHS "${CMAKE_SOURCE_DIR}/out" NO_DEFAULT_PATH)
target_link_libraries(native ${FLUTTER_FRAMEWORK})
message(${FLUTTER_FRAMEWORK})

set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -rpath @executable_path")



find_package(JNI REQUIRED)
include_directories(${JNI_INCLUDE_DIRS})
message(JNI_INCLUDE_DIRs="${JNI_INCLUDE_DIRS}")

target_link_libraries(native
        "-framework IOSurface"
        "-framework Foundation"
        "-framework CoreFoundation"
)

include(FetchContent)

FetchContent_Declare(
        rapidjson
        GIT_REPOSITORY https://github.com/Tencent/rapidjson.git
        GIT_TAG        master  # Or use a specific tag like v1.1.0
)

FetchContent_MakeAvailable(rapidjson)

# Now you can use RapidJSON headers
target_include_directories(native PRIVATE ${rapidjson_SOURCE_DIR}/include)


############################################################
# Flutter Engine
#############################################################
## This is assuming you've built a local version of the Flutter Engine.  If you
## downloaded yours is from the internet you'll have to change this.
#include_directories(${CMAKE_SOURCE_DIR}/out/include)
#target_link_libraries(native -Wl,-force_load,${CMAKE_SOURCE_DIR}/out/bin/flutter_engine.dylib)

# Copy the flutter library here since the shared library
# name is `./libflutter_engine.dylib`.
#add_custom_command(
#        TARGET native POST_BUILD
#        COMMAND ${CMAKE_COMMAND} -E copy
#        ${CMAKE_SOURCE_DIR}/out/bin/flutter_engine.dylib
#        ${CMAKE_CURRENT_BINARY_DIR})