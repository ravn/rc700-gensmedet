cmake_minimum_required(VERSION 3.20)
project(rcbios-in-c C)

# This CMakeLists.txt exists for CLion indexing and navigation only.
# The actual build uses Makefiles with Docker (clang or z88dk/sdcc).
# sdcc keywords are stubbed in hal.h (#ifdef HOST_TEST).

# z88dk headers (stdint.h, etc.) — z88dk lives at the workspace root
# (/Users/ravn/z80/z88dk/), two levels above this CMakeLists.txt.  Only
# falls back to this path when CLion opens this subdir standalone (the
# parent CMakeLists already sets Z88DK_INCLUDE correctly).
if(NOT DEFINED Z88DK_INCLUDE)
    get_filename_component(Z88DK_INCLUDE
        "${CMAKE_CURRENT_SOURCE_DIR}/../../z88dk/include" ABSOLUTE)
endif()

# Generate builddate.h stub if it doesn't exist (fresh clone)
if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/builddate.h)
    file(WRITE ${CMAKE_CURRENT_SOURCE_DIR}/builddate.h
         "#define BUILDDATE \"CLion-placeholder\"\n")
endif()

add_library(bios_sources OBJECT EXCLUDE_FROM_ALL
    bios.c
    bios.h
    hal.h
    boot_block.c
    boot_confi.c
    boot_entry.c
    bios_hw_init.c
    bios_jump_vector_table.c
    conout_test.c
    # Locale character tables (included by boot_confi.c)
    locale/danish_tables.h
    locale/swedish_tables.h
    locale/german_tables.h
    locale/uk_ascii_tables.h
    locale/us_ascii_tables.h
    locale/french_tables.h
    locale/library_tables.h
    # Clang-specific headers (for navigation, not compiled under HOST_TEST)
    clang/intrinsic.h
    clang/string.h
)

target_include_directories(bios_sources PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/clang
    ${Z88DK_INCLUDE}
)

target_compile_definitions(bios_sources PRIVATE MSIZE=56)

# Custom targets that invoke the real Makefile
add_custom_target(bios
    COMMAND make bios
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

add_custom_target(bios-size
    COMMAND make size
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

add_custom_target(mame-mini
    COMMAND make mame-mini
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

add_custom_target(mame-maxi
    COMMAND make mame-maxi
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

add_custom_target(mame-gdb
    COMMAND ./run_mame.sh -g
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Build + launch MAME with GDB stub on port 23946"
)

add_custom_target(mame-test
    COMMAND make mame-test
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Build + run integration test in MAME"
)

add_custom_target(cycle-test
    COMMAND make cycle-test
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Build + run cycle benchmark in MAME"
)
