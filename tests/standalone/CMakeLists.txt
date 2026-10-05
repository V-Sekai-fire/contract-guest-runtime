# A guest built outside the pen: dress_on.elf through cmake/guest_runtime.cmake alone.
cmake_minimum_required(VERSION 3.16)
project(guest_runtime_standalone C CXX)

set(GUEST_ELF_DIR ${CMAKE_BINARY_DIR})
include(${CMAKE_CURRENT_LIST_DIR}/../../cmake/guest_runtime.cmake)

add_stage_elf(dress_on ${GUEST_RUNTIME_ROOT}/guest/main.cpp)
