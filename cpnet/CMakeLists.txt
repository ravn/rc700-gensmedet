cmake_minimum_required(VERSION 3.20)
project(cpnet C)

# CLion indexing only.  Real builds use z88dk +cpm via per-utility
# Makefiles (todsrv, rtctod, todget).

if(NOT DEFINED Z88DK_INCLUDE)
    set(Z88DK_INCLUDE ${CMAKE_CURRENT_SOURCE_DIR}/../../z88dk/include)
endif()

add_library(cpnet_utils OBJECT EXCLUDE_FROM_ALL
    todsrv/todsrv.c
    rtctod/rtctod.c
    todget/todget.c
)

target_include_directories(cpnet_utils PRIVATE
    ${Z88DK_INCLUDE}
)
