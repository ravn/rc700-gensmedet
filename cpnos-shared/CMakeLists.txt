cmake_minimum_required(VERSION 3.20)
project(cpnos-shared C)

# CLion indexing only.  cpnos-shared is a header library (cfgtbl.h,
# payload_header.h) consumed by cpnos-in-c and rcbios-in-c, plus the
# testutil/ host helpers and the mame/ Lua test harness (not C).

# Header-only INTERFACE target lets CLion follow the includes.
add_library(cpnos_shared_headers INTERFACE)
target_include_directories(cpnos_shared_headers INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Host-side testutil helpers, indexed as plain C.
file(GLOB CPNOS_TESTUTIL_C CONFIGURE_DEPENDS testutil/*.c testutil/*.h)
if(CPNOS_TESTUTIL_C)
    add_library(cpnos_testutil OBJECT EXCLUDE_FROM_ALL ${CPNOS_TESTUTIL_C})
    target_include_directories(cpnos_testutil PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )
endif()
