cmake_minimum_required(VERSION 3.20)
project(cpnos-in-c C)

# This CMakeLists.txt exists for CLion indexing and navigation only.
# The actual build uses Makefiles with clang (--target=z80) or z88dk-zsdcc.
# Z80-specific asm is guarded by #ifdef __z80__ (only defined by llvm-z80).

# z88dk headers (stdint.h, etc.) — from parent or standalone open
if(NOT DEFINED Z88DK_INCLUDE)
    set(Z88DK_INCLUDE ${CMAKE_CURRENT_SOURCE_DIR}/../../z88dk/include)
endif()

set(SHARED_INCLUDE ${CMAKE_CURRENT_SOURCE_DIR}/../cpnos-shared/include)

add_library(cpnos_sources OBJECT EXCLUDE_FROM_ALL
    src/cpnos_main.c
    src/hal.h
    src/init.c
    src/resident.c
    src/snios_c.c
    src/transport.h
    src/transport_pio.c
    src/transport_sio.c
)

target_include_directories(cpnos_sources PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${SHARED_INCLUDE}
    ${Z88DK_INCLUDE}
)

# Defines mirror the Makefile's production clang build (lines 115-122 + 217-219).
# Values match the default targets so the indexer sees the same #ifdef branches
# the production build does.
target_compile_definitions(cpnos_sources PRIVATE
    ENABLE_FDC=0
    MIRROR_SIOB=0
    BOOT_MARK_ENABLED=1
    RC702_SLAVEID=0x01
    PIO_SPEED_TEST=0
    PIO_LOOPBACK_TEST
    TRANSPORT_NAME="pio"
)

# Custom targets that invoke the real Makefile
add_custom_target(cpnos-prom1-clang
    COMMAND make prom1-lineprog COMPILER=clang
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Build cpnos-in-c PROM1-only line program (clang)"
)

add_custom_target(cpnos-prom1-sdcc
    COMMAND make prom1-lineprog COMPILER=sdcc
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Build cpnos-in-c PROM1-only line program (sdcc)"
)

add_custom_target(cpnos-polypascal-test
    COMMAND make polypascal-test
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Run cpnos polypascal-test in MAME"
)
