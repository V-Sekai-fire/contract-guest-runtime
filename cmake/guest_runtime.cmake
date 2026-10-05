# The shared guest build: sandbox_api, rd_compute, pump, add_stage_elf and,
# with GUEST_RUNTIME_GGML, ggml and ggml_rd. Include it after project(), configured
# with the riscv64 sysroot's toolchain file (repository-riscv64-sysroot).
# Optional inputs: WEFT_ROOT, GGML_RD_ROOT, GGML_ROOT, GUEST_RUNTIME_GGML,
# GUEST_RUNTIME_GGML_COMMIT, GUEST_ELF_DIR (defaults below).
include_guard(GLOBAL)

if(NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "riscv64" OR NOT CMAKE_SYSROOT)
	message(FATAL_ERROR "guest_runtime.cmake: not a riscv64 sysroot build "
		"(CMAKE_SYSTEM_PROCESSOR=${CMAKE_SYSTEM_PROCESSOR}); configure with "
		"-DCMAKE_TOOLCHAIN_FILE=<repository-riscv64-sysroot>/toolchain.cmake")
endif()

if(NOT DEFINED GUEST_RUNTIME_ROOT)
	get_filename_component(GUEST_RUNTIME_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()
if(NOT DEFINED WEFT_ROOT)
	get_filename_component(WEFT_ROOT "${GUEST_RUNTIME_ROOT}/../.." ABSOLUTE)
endif()
if(NOT DEFINED GGML_RD_ROOT)
	set(GGML_RD_ROOT ${WEFT_ROOT}/2-contract/ggml-rd)
endif()
if(NOT DEFINED GGML_ROOT)
	set(GGML_ROOT ${WEFT_ROOT}/2-contract/ggml)
endif()
option(GUEST_RUNTIME_GGML "Define ggml and ggml_rd (needs the ggml and ggml-rd checkouts)" OFF)
if(NOT DEFINED GUEST_ELF_DIR)
	set(GUEST_ELF_DIR ${CMAKE_SOURCE_DIR})
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
	set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()
# The variant the pen loads: rv64gc without V, and a double-precision Variant.
set(SANDBOX_RISCV_EXT_V OFF CACHE BOOL "Enable RISC-V V (vector) extension")
set(DOUBLE_PRECISION ON CACHE BOOL "Enable double precision real_t")

# The fiber's context switch is a .S file, assembled for the C target triple.
if(CMAKE_C_COMPILER_TARGET AND NOT CMAKE_ASM_COMPILER_TARGET)
	set(CMAKE_ASM_COMPILER_TARGET ${CMAKE_C_COMPILER_TARGET})
endif()
enable_language(ASM)

# Sources are named relative to their repository, so an ELF names neither the
# machine nor the checkout it was built in. Maps added before the include reach every target.
add_compile_options("-ffile-prefix-map=${CMAKE_SOURCE_DIR}/=" "-ffile-prefix-map=${GUEST_RUNTIME_ROOT}/=")
if(GUEST_RUNTIME_GGML)
	add_compile_options("-ffile-prefix-map=${GGML_RD_ROOT}/=" "-ffile-prefix-map=${GGML_ROOT}/=vendor/ggml/")
endif()

# The guest includes <api.hpp> only; nothing is downloaded.
set(DOWNLOAD_RUNTIME_API OFF CACHE BOOL "" FORCE)
add_subdirectory(${GUEST_RUNTIME_ROOT}/vendor/sandbox-api/cmake sandbox_api)

add_library(rd_compute STATIC ${GUEST_RUNTIME_ROOT}/guest/rd_compute.cpp)
target_include_directories(rd_compute PUBLIC ${GUEST_RUNTIME_ROOT}/guest)
target_link_libraries(rd_compute PUBLIC sandbox_api)

# One ELF per stage, copied to ${GUEST_ELF_DIR}/<name>.elf.
function(add_stage_elf name)
	add_sandbox_program(${name} ${ARGN})
	target_link_libraries(${name} PRIVATE rd_compute -lm -lstdc++)
	add_custom_command(TARGET ${name} POST_BUILD
		COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:${name}> ${GUEST_ELF_DIR}/${name}.elf
		COMMENT "Installing ${name}.elf"
	)
endfunction()

# The pump protocol: a job on a guest fiber, advanced one host call at a time.
add_library(pump STATIC ${GUEST_RUNTIME_ROOT}/guest/pump/pump.cpp ${GUEST_RUNTIME_ROOT}/guest/fiber/fiber.cpp
	${GUEST_RUNTIME_ROOT}/guest/fiber/fiber_riscv64.S)
target_include_directories(pump PUBLIC ${GUEST_RUNTIME_ROOT}/guest)
target_link_libraries(pump PUBLIC sandbox_api)

if(NOT GUEST_RUNTIME_GGML)
	return()
endif()

set(GUEST_RUNTIME_GGML_KERNELS ${CMAKE_BINARY_DIR}/ggml_kernels.inc)
foreach(need "${GGML_ROOT}/CMakeLists.txt" "${GGML_RD_ROOT}/guest/ggml-rd/ggml-rd.cpp" "${GUEST_RUNTIME_GGML_KERNELS}")
	if(NOT EXISTS "${need}")
		message(FATAL_ERROR "guest_runtime.cmake: GUEST_RUNTIME_GGML needs ${need} (ggml_kernels.inc comes from "
			"BUILD_DIR=${CMAKE_BINARY_DIR} ${GGML_RD_ROOT}/kernels/ggml/gen.sh --no-emit)")
	endif()
endforeach()

# ggml static at rv64gc, one thread, no dynamic backends, OpenMP, llamafile, RVV or Zfh.
foreach(opt GGML_NATIVE GGML_BACKEND_DL BUILD_SHARED_LIBS GGML_OPENMP GGML_LLAMAFILE
		GGML_RVV GGML_RV_ZFH GGML_RV_ZVFH GGML_RV_ZICBOP GGML_RV_ZIHINTPAUSE GGML_RV_ZVFBFWMA
		GGML_BUILD_TESTS GGML_BUILD_EXAMPLES GGML_CCACHE)
	set(${opt} OFF CACHE BOOL "" FORCE)
endforeach()
add_subdirectory(${GGML_ROOT} ggml EXCLUDE_FROM_ALL)
# A fixed ggml_commit(), so a committed ELF does not change with every ggml commit.
if(NOT DEFINED GUEST_RUNTIME_GGML_COMMIT)
	set(GUEST_RUNTIME_GGML_COMMIT 04b55bba)
endif()
get_target_property(_ggml_defs ggml-base COMPILE_DEFINITIONS)
list(FILTER _ggml_defs EXCLUDE REGEX "^GGML_COMMIT=")
list(APPEND _ggml_defs "GGML_COMMIT=\"${GUEST_RUNTIME_GGML_COMMIT}\"")
set_target_properties(ggml-base PROPERTIES COMPILE_DEFINITIONS "${_ggml_defs}")
# clang predefines __riscv_v_intrinsic without V too, and ggml-cpu keys its RVV paths on it.
target_compile_options(ggml-cpu PRIVATE -U__riscv_v_intrinsic -Wno-switch)

# ggml-rd: ggml's backend over rd_compute. OBJECT, so every ops/<op>.cpp registrar is linked.
file(GLOB GGML_RD_OPS CONFIGURE_DEPENDS ${GGML_RD_ROOT}/guest/ggml-rd/ops/*.cpp)
# The CPU fallback runs the kernels' slangc cpp emits; -ffp-contract=off rounds as the host harness does.
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(GGML_RD_CPU_RUNNER ${CMAKE_BINARY_DIR}/ggml_rd_cpu_kernels.cpp)
file(GLOB GGML_RD_EMITS CONFIGURE_DEPENDS ${GGML_RD_ROOT}/kernels/ggml/cpp/*_emit.cpp)
add_custom_command(
	OUTPUT ${GGML_RD_CPU_RUNNER}
	COMMAND ${Python3_EXECUTABLE} ${GGML_RD_ROOT}/tests/ggml_rd_kernels/gen_host_kernels.py
		${GGML_RD_ROOT}/kernels/ggml/kernels.txt ${GGML_RD_CPU_RUNNER} ${GGML_RD_ROOT}/kernels/ggml/cpp_siblings.txt
	DEPENDS ${GGML_RD_ROOT}/tests/ggml_rd_kernels/gen_host_kernels.py ${GGML_RD_ROOT}/kernels/ggml/kernels.txt
		${GGML_RD_ROOT}/kernels/ggml/cpp_siblings.txt ${GGML_RD_EMITS}
	COMMENT "ggml-rd CPU fallback runners from kernels/ggml/kernels.txt"
)
add_library(ggml_rd OBJECT
	${GGML_RD_ROOT}/guest/ggml-rd/ggml-rd.cpp
	${GGML_RD_ROOT}/guest/ggml-rd/rd_graph.cpp
	${GGML_RD_ROOT}/guest/ggml-rd/rd_kernels.cpp
	${GGML_RD_ROOT}/guest/ggml-rd/rd_pack.cpp
	${GGML_RD_ROOT}/guest/ggml-rd/rd_cpu.cpp
	${GGML_RD_CPU_RUNNER}
	${GGML_RD_OPS}
)
set_source_files_properties(${GGML_RD_CPU_RUNNER} PROPERTIES COMPILE_OPTIONS "-ffp-contract=off"
	INCLUDE_DIRECTORIES "${GGML_RD_ROOT}/kernels/ggml/cpp;${GUEST_RUNTIME_ROOT}/guest/avbd/slang-rt")
target_include_directories(ggml_rd PUBLIC ${GGML_RD_ROOT}/guest/ggml-rd ${GGML_RD_ROOT}/kernels/ggml
	${GGML_RD_ROOT}/tests/ggml_rd_kernels ${CMAKE_BINARY_DIR} ${GGML_ROOT}/src)
target_link_libraries(ggml_rd PUBLIC ggml ggml-base rd_compute)
