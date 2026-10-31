cmake_minimum_required(VERSION 3.22)
project(OdinSokol C)
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
add_subdirectory(deps/SDL3-3.2.28 EXCLUDE_FROM_ALL)

set(ENTRY ${CMAKE_CURRENT_BINARY_DIR}/entry.c)
file(WRITE ${ENTRY} "#include \"${CMAKE_CURRENT_SOURCE_DIR}/app/entry.h\"\n")
file(GLOB_RECURSE ODIN_SOURCES CONFIGURE_DEPENDS app/*.odin)
set(APP_OBJECT ${CMAKE_CURRENT_BINARY_DIR}/odin-app.o)
add_custom_command(OUTPUT ${APP_OBJECT}
  COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/scripts/odin-object.sh desktop native ${APP_OBJECT}
  DEPENDS ${ODIN_SOURCES} app/native/shaders_generated.h shaders/app.slang VERBATIM)
set_source_files_properties(${APP_OBJECT} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)

find_package(Threads REQUIRED)
find_package(OpenGL REQUIRED)
find_package(X11 REQUIRED)

# odin-sokol executable; app/native/sokol_shim.c is the SOKOL_IMPL translation
# unit (GL core backend) plus the flat C API the Odin side binds.
add_executable(odin-sokol ${ENTRY} ${APP_OBJECT} app/native/sokol_shim.c)
target_include_directories(odin-sokol PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/vendors)
target_compile_definitions(odin-sokol PRIVATE SOKOL_IMPL SOKOL_GLCORE SOKOL_NO_ENTRY)
target_link_libraries(odin-sokol PRIVATE SDL3::SDL3 OpenGL::GL X11::X11 Threads::Threads ${CMAKE_DL_LIBS})
