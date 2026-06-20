cmake_minimum_required(VERSION 3.20)
project(rc700-gensmedet C)

# This CMakeLists.txt exists for CLion indexing and navigation only.
# The actual builds use z88dk/sdcc via Makefiles in each subdirectory.

# z88dk headers for navigation (stdint.h, etc.) — the z88dk checkout
# lives at the workspace ROOT (/Users/ravn/z80/z88dk/), one level above
# this CMakeLists.txt, not under rc700-gensmedet.
get_filename_component(Z88DK_INCLUDE
    "${CMAKE_SOURCE_DIR}/../z88dk/include" ABSOLUTE)

# CLion's host clang follows the clang Z80 code paths.
# Z80-specific asm is guarded by #ifdef __z80__ (only defined by llvm-z80).

# cpnos-shared first so the header-INTERFACE library it exports is
# available when cpnos-in-c (and any other consumer) calls
# target_link_libraries against it.
add_subdirectory(cpnos-shared)

add_subdirectory(autoload-in-c)
add_subdirectory(rcbios-in-c)
add_subdirectory(cpnos-in-c)
add_subdirectory(autoload-in-asm)
add_subdirectory(cpnet)
