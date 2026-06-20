cmake_minimum_required(VERSION 3.20)
project(autoload-in-c C)

# This CMakeLists.txt exists for CLion indexing and navigation only.
# The actual build uses z88dk/sdcc or llvm-z80/clang via the Makefile.

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# z88dk headers (stdint.h, etc.) — z88dk lives at the workspace root
# (/Users/ravn/z80/z88dk/), two levels above this CMakeLists.txt.  Only
# falls back to this path when CLion opens this subdir standalone (the
# parent CMakeLists already sets Z88DK_INCLUDE correctly).
if(NOT DEFINED Z88DK_INCLUDE)
    get_filename_component(Z88DK_INCLUDE
        "${CMAKE_CURRENT_SOURCE_DIR}/../../z88dk/include" ABSOLUTE)
endif()

add_executable(rom_index EXCLUDE_FROM_ALL
    rom.c
    boot_rom.c
    intvec.c
)

target_include_directories(rom_index PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/clang_z80
    ${Z88DK_INCLUDE}
)

# Z80-specific asm is guarded by #ifdef __z80__ (only defined by llvm-z80).
# Host clang gets safe fallbacks — no need to fake __z80__ here.
