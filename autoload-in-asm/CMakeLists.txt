cmake_minimum_required(VERSION 3.20)
project(autoload-in-asm C)

# This CMakeLists.txt exists for CLion indexing and navigation only.
# The actual build uses the autoload-in-asm Makefile (host-test path
# with -DHOST_TEST, plus a Z80 path that's parked — see PARKED.md).

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_library(autoload_asm_sources OBJECT EXCLUDE_FROM_ALL
    boot.c
    boot.h
    fdc.c
    fmt.c
    hal.h
    hal_host.c
    hal_z80.c
    init.c
    isr.c
    rom_all.c
    test_boot.c
    test_fdc.c
)

target_include_directories(autoload_asm_sources PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# HOST_TEST mirrors the Makefile's only currently-built path.
target_compile_definitions(autoload_asm_sources PRIVATE HOST_TEST)
