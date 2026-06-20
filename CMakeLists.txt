cmake_minimum_required(VERSION 3.20)
project(rc700-gensmedet C)

# This CMakeLists.txt exists for CLion indexing and navigation only.
# The actual builds use z88dk/sdcc via Makefiles in each subdirectory.

# z88dk headers for navigation (stdint.h, etc.)
set(Z88DK_INCLUDE ${CMAKE_SOURCE_DIR}/z88dk/include)

# CLion's host clang follows the clang Z80 code paths.
# Z80-specific asm is guarded by #ifdef __z80__ (only defined by llvm-z80).

add_subdirectory(autoload-in-c)
add_subdirectory(rcbios-in-c)
add_subdirectory(cpnos-in-c)
