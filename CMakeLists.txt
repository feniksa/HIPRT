cmake_minimum_required(VERSION 3.21)
project(hiprt)

# Only one of those 3 flags should be ON at a time, or none. Multiple flags ON are untested and may cause issues.
option(BAKE_KERNEL "Enable the use of encrypted and baked kernels source code" OFF)
option(BAKE_COMPILED_KERNEL "If enabled, the kernels will be compiled and embedded as a buffer inside the binary. if you do that, you should also enable the flag 'PRECOMPILE'" OFF)
option(BITCODE "Enable bitcode linking: when running the program, it's expected to find precompiled kernels as external files." OFF)

option(PRECOMPILE "Precompile kernels" OFF)
option(HIPRTEW "Use hiprtew" OFF)
option(NO_ENCRYPT "Don't encrypt kernel source and binaries" OFF)
option(NO_UNITTEST "Don't build unit tests" OFF)
option(HIPRT_PREFER_HIP_5 "Prefer HIP 5" OFF)

option(FORCE_DISABLE_CUDA "By default Cuda support is automatically added if a Cuda install is detected. Turn this flag to ON to force Cuda to be disabled." OFF)

find_package(Python COMPONENTS Interpreter REQUIRED)
message(STATUS "Python path = ${Python_EXECUTABLE}")

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake")
include("${CMAKE_SOURCE_DIR}/cmake/utils.cmake")

# GENERATE_BAKE_KERNEL is enabled by default if we use the flags 'BAKE_KERNEL' or 'BITCODE'.
# It can be forced to OFF, but in this case, some building functions from the HIPRT API, like hiprtBuildTraceKernelsFromBitcode will fail.
if(BAKE_KERNEL OR BITCODE)
	set(GENERATE_BAKE_KERNEL___DEFAULT ON)
else()
	set(GENERATE_BAKE_KERNEL___DEFAULT OFF)
endif()
option(GENERATE_BAKE_KERNEL "generate the baked kernels" ${GENERATE_BAKE_KERNEL___DEFAULT})
message(STATUS "GENERATE_BAKE_KERNEL= ${GENERATE_BAKE_KERNEL}")

# Set C++ Standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Define GTEST_HAS_TR1_TUPLE=0 globally
add_definitions(-DGTEST_HAS_TR1_TUPLE=0)

# fill the HIP_VERSION_STR variable, it will look like: "6.2"
# also get the path to hip that'll be used along all this cmake.
get_hip_sdk_version(HIP_VERSION_STR HIP_FINAL_PATH)
message(STATUS "HIP_VERSION_STR = ${HIP_VERSION_STR}")
message(STATUS "HIP_FINAL_PATH = ${HIP_FINAL_PATH}")

# Set up configurations
set(CMAKE_CONFIGURATION_TYPES "Debug;Release;RelWithDebInfo;DebugGpu" CACHE STRING "Configs" FORCE)

set(CMAKE_SHARED_LINKER_FLAGS_DEBUGGPU "")
set(CMAKE_EXE_LINKER_FLAGS_DEBUGGPU "")

# Define platform-specific flags and settings
if(WIN32)
	add_definitions(-D__WINDOWS__)
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /wd4244 /wd4305 /wd4018 /wd4996 /Zc:__cplusplus")
elseif(UNIX)
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fvisibility=hidden")
endif()

add_definitions(-D__USE_HIP__)


# this define is to identify that we are on the public repository of HIPRT.
# it helps AMD to maintain both a public and a private repo for experimentation.
add_definitions(-DHIPRT_PUBLIC_REPO)


if (NOT FORCE_DISABLE_CUDA)
	# Enable CUDA if possible
	include(${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/Orochi/enable_cuew.cmake)
else()
	message(STATUS "CUDA support is forced to disabled.")
endif()


# Base output directory
set(BASE_OUTPUT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/dist/bin)
file(MAKE_DIRECTORY "${BASE_OUTPUT_DIR}/Debug")
file(MAKE_DIRECTORY "${BASE_OUTPUT_DIR}/Release")

# Set output directories for each build configuration
foreach(OUTPUTCONFIG ${CMAKE_CONFIGURATION_TYPES} Debug Release RelWithDebInfo MinSizeRel)
	string(TOUPPER ${OUTPUTCONFIG} OUTPUTCONFIG_UPPER)
	set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_${OUTPUTCONFIG_UPPER} ${BASE_OUTPUT_DIR}/${OUTPUTCONFIG})
	set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_${OUTPUTCONFIG_UPPER} ${BASE_OUTPUT_DIR}/${OUTPUTCONFIG})
	set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_${OUTPUTCONFIG_UPPER} ${BASE_OUTPUT_DIR}/${OUTPUTCONFIG})
endforeach()

# Set output directories for single-configuration generators
if(NOT CMAKE_CONFIGURATION_TYPES)
	set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${BASE_OUTPUT_DIR}/${CMAKE_BUILD_TYPE})
	set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${BASE_OUTPUT_DIR}/${CMAKE_BUILD_TYPE})
	set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${BASE_OUTPUT_DIR}/${CMAKE_BUILD_TYPE})
endif()




# Write version info
set(version_str_ "UNDEF")
write_version_info("${CMAKE_CURRENT_SOURCE_DIR}/hiprt/hiprt.h.in" "${CMAKE_CURRENT_SOURCE_DIR}/hiprt/hiprt.h" "${CMAKE_CURRENT_SOURCE_DIR}/version.txt" version_str_)
write_version_info("${CMAKE_CURRENT_SOURCE_DIR}/hiprt/hiprtew.h.in" "${CMAKE_CURRENT_SOURCE_DIR}/hiprt/hiprtew.h" "${CMAKE_CURRENT_SOURCE_DIR}/version.txt" version_str_)


set(HIPRT_NAME "hiprt${version_str_}")

# Project: HIPRT
add_library(${HIPRT_NAME} SHARED)
target_compile_definitions(${HIPRT_NAME} PRIVATE HIPRT_EXPORTS)


if( ${CMAKE_BUILD_TYPE} STREQUAL "Debug" )
	set_target_properties(${HIPRT_NAME} PROPERTIES OUTPUT_NAME "${HIPRT_NAME}64D")
else()
	set_target_properties(${HIPRT_NAME} PROPERTIES OUTPUT_NAME "${HIPRT_NAME}64")
endif()


if(BITCODE)
	target_compile_definitions(${HIPRT_NAME} PRIVATE HIPRT_BITCODE_LINKING ORO_PRECOMPILED)
endif()

if(NOT NO_ENCRYPT)
	target_compile_definitions(${HIPRT_NAME} PRIVATE HIPRT_ENCRYPT )
	set(ENV{HIPRT_NO_ENCRYPT} "OFF")
else()
	set(ENV{HIPRT_NO_ENCRYPT} "ON")
endif()

if(HIPRT_PREFER_HIP_5)
	add_definitions(-DHIPRT_PREFER_HIP_5)
endif()

# files generated by compile.py and precompile_bitcode.py
if(WIN32)
	set(KERNEL_OS_POSTFIX "win")
else()
	set(KERNEL_OS_POSTFIX "linux")
endif()
set(KERNEL_HIPRT_COMP    "${BASE_OUTPUT_DIR}/${CMAKE_BUILD_TYPE}/hiprt${version_str_}_${HIP_VERSION_STR}_amd.hipfb")                                        # example:  hiprt02005_6.2_amd.hipfb
set(KERNEL_UNITTEST_COMP "${BASE_OUTPUT_DIR}/${CMAKE_BUILD_TYPE}/hiprt${version_str_}_${HIP_VERSION_STR}_precompiled_bitcode_${KERNEL_OS_POSTFIX}.hipfb")   # example:  hiprt02005_6.2_precompiled_bitcode_win.hipfb
set(KERNEL_OROCHI_COMP "${BASE_OUTPUT_DIR}/${CMAKE_BUILD_TYPE}/oro_compiled_kernels.hipfb")

# precompile kernels:
if(PRECOMPILE)
	if(FORCE_DISABLE_CUDA)
		set(CUDA_OPTION "")
	else()
		set(CUDA_OPTION "--nvidia")
	endif()

	set(bvh_source
	${CMAKE_SOURCE_DIR}/hiprt/hiprt_vec.h
	${CMAKE_SOURCE_DIR}/hiprt/hiprt_math.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/Aabb.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/AabbList.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/BvhCommon.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/BvhNode.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/Geometry.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/QrDecomposition.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/Quaternion.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/Transform.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/Instance.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/InstanceList.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/MortonCode.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/Scene.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/TriangleMesh.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/Triangle.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/BvhBuilderUtil.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/SbvhCommon.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/ApiNodeList.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/BvhConfig.h
	${CMAKE_SOURCE_DIR}/hiprt/impl/MemoryArena.h
	${CMAKE_SOURCE_DIR}/hiprt/hiprt_types.h
	${CMAKE_SOURCE_DIR}/hiprt/hiprt_common.h
	)

	message(">> add_custom_command: ${PYTHON_EXECUTABLE} compile.py ${CUDA_OPTION} --hipSdkPath \"${HIP_FINAL_PATH}\"")
	add_custom_command(
			OUTPUT ${KERNEL_HIPRT_COMP} ${KERNEL_OROCHI_COMP}
			COMMAND ${PYTHON_EXECUTABLE} compile.py ${CUDA_OPTION} --hipSdkPath ${HIP_FINAL_PATH}
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/scripts/bitcodes
			COMMENT "Precompiling kernels via compile.py"
			VERBATIM
			DEPENDS ${bvh_source}
		)
		
	# create the 'precompile_kernels' project
	add_custom_target(precompile_kernels ALL
		DEPENDS ${KERNEL_HIPRT_COMP} ${KERNEL_OROCHI_COMP}
		)
	
	if(NOT NO_UNITTEST)

		set(unittest_kernel_source
		${CMAKE_SOURCE_DIR}/test/bitcodes/custom_func_table.cpp
		${CMAKE_SOURCE_DIR}/test/bitcodes/unit_test.cpp
		)
		
		message(">> add_custom_command: ${PYTHON_EXECUTABLE} precompile_bitcode.py ${CUDA_OPTION} --hipSdkPath \"${HIP_FINAL_PATH}\"")
		add_custom_command(
			OUTPUT ${KERNEL_UNITTEST_COMP}
			COMMAND ${PYTHON_EXECUTABLE} precompile_bitcode.py ${CUDA_OPTION} --hipSdkPath ${HIP_FINAL_PATH}
			DEPENDS ${KERNEL_HIPRT_COMP}  # Ensure compile.py has already run.
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/scripts/bitcodes
			COMMENT "Precompiling unit tests kernels via precompile_bitcode.py"
			VERBATIM
			DEPENDS ${unittest_kernel_source}
			)
			
		# create the 'precompile_unittest_kernels' project
		add_custom_target(precompile_unittest_kernels ALL
			DEPENDS ${KERNEL_UNITTEST_COMP}
			)
			
		add_dependencies(${HIPRT_NAME} precompile_unittest_kernels)
	endif()
	

endif()



# convert the binary to a buffer that will be embeded inside the binary
# it's expected the step 'PRECOMPILE' has been executed.
if ( BAKE_COMPILED_KERNEL )
	message(">> precompiled will be embedded.")
	
	set(PYTHON_FILE "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/scripts/convert_binary_to_array.py")

	# HIPRT binary
	set(KERNEL_HIPRT_H "${CMAKE_CURRENT_SOURCE_DIR}/hiprt/impl/bvh_build_array.h")
	add_custom_command(
		OUTPUT ${KERNEL_HIPRT_H}
		COMMAND ${PYTHON_EXECUTABLE} ${PYTHON_FILE} ${KERNEL_HIPRT_COMP} ${KERNEL_HIPRT_H}
		DEPENDS ${KERNEL_HIPRT_COMP}  # Ensure compile.py has already run.
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		COMMENT "Converting HIPRT compiled kernel to header"
		VERBATIM
	)

	# Orochi binary
	set(KERNEL_OROCHI_H "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/ParallelPrimitives/cache/oro_compiled_kernels.h")
	add_custom_command(
		OUTPUT ${KERNEL_OROCHI_H}
		COMMAND ${PYTHON_EXECUTABLE} ${PYTHON_FILE} ${KERNEL_OROCHI_COMP} ${KERNEL_OROCHI_H}
		DEPENDS ${KERNEL_OROCHI_COMP}  # Ensure compile.py has already run.
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		COMMENT "Converting Orochi compiled kernel to header"
		VERBATIM
	)

	# Create the 'bake_compiled_kernels' project
	add_custom_target(bake_compiled_kernels ALL
		DEPENDS ${KERNEL_HIPRT_H} ${KERNEL_OROCHI_H}
	)

	add_dependencies(${HIPRT_NAME} precompile_kernels bake_compiled_kernels)

endif()



if(BAKE_KERNEL OR GENERATE_BAKE_KERNEL)
	message(">> BakeKernel Executed")
	if(WIN32)
		execute_process(
			COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tools/bakeKernel.bat
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			)
	else()
		execute_process(
			COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tools/bakeKernel.sh
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			)
	endif()

	target_compile_definitions(${HIPRT_NAME} PRIVATE HIPRT_BAKE_KERNEL_GENERATED)

endif()


if ( BAKE_COMPILED_KERNEL )
	# enable the 'BAKE_COMPILED_KERNEL' on Orochi:  this mode is activated by adding those 2 defines.
	target_compile_definitions(${HIPRT_NAME} PRIVATE ORO_BAKE_COMPILED_KERNEL)
	
	#enable the 'BAKE_COMPILED_KERNEL' on HIPRT: 
	target_compile_definitions(${HIPRT_NAME} PRIVATE HIPRT_BAKE_COMPILED_KERNEL )
endif()

if(BAKE_KERNEL)
	target_compile_definitions(${HIPRT_NAME} PRIVATE HIPRT_LOAD_FROM_STRING ORO_PP_LOAD_FROM_STRING)
endif()

if(WIN32)
	target_link_libraries(${HIPRT_NAME} version)
endif()


target_include_directories(${HIPRT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_include_directories(${HIPRT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi)

file(GLOB_RECURSE hiprt_sources "${CMAKE_CURRENT_SOURCE_DIR}/hiprt/*.h" "${CMAKE_CURRENT_SOURCE_DIR}/hiprt/*.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/hiprt/*.inl")
list(FILTER hiprt_sources EXCLUDE REGEX "hiprt/bitcodes/.*")
file(GLOB_RECURSE orochi_sources "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/Orochi/*.h" "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/Orochi/*.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/contrib/cuew/*.h" "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/contrib/cuew/*.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/contrib/hipew/*.h" "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/contrib/hipew/*.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/ParallelPrimitives/*.h" "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/ParallelPrimitives/*.cpp")
target_sources(${HIPRT_NAME} PRIVATE ${hiprt_sources} ${orochi_sources})




#
# install script
#

install(TARGETS ${HIPRT_NAME} DESTINATION bin)

# add header files
file(GLOB HIPRT_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/hiprt/*.h")
install(FILES ${HIPRT_HEADERS}
		DESTINATION include/hiprt)

# add header files from implementation folder
file(GLOB HIPRT_IMPL_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/hiprt/impl/*.h")
install(FILES ${HIPRT_IMPL_HEADERS}
		DESTINATION include/hiprt/impl)
		
# add some header files from Orochi
file(GLOB HIPRT_ORO_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/ParallelPrimitives/*.h")
install(FILES ${HIPRT_ORO_HEADERS}
		DESTINATION include/contrib/Orochi/ParallelPrimitives)

# add hipfb files
file(GLOB HIPRT_HIPFB_FILES "${BASE_OUTPUT_DIR}/${CMAKE_BUILD_TYPE}/*.hipfb")
install(FILES ${HIPRT_HIPFB_FILES}
		DESTINATION bin)


# Project: Unit Test
if(NOT NO_UNITTEST)

	add_executable(unittest)

	if(BITCODE)
		target_compile_definitions(unittest PRIVATE HIPRT_BITCODE_LINKING)
	endif()
	if(WIN32)
		target_compile_options(unittest PRIVATE /wd4244)
		target_link_libraries(unittest PRIVATE version)
	endif()

	if( ${CMAKE_BUILD_TYPE} STREQUAL "Debug" )
		set_target_properties(unittest PROPERTIES OUTPUT_NAME "unittest64D")
	else()
		set_target_properties(unittest PROPERTIES OUTPUT_NAME "unittest64")
	endif()


	target_include_directories(unittest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi)
	target_link_libraries(unittest PRIVATE ${HIPRT_NAME})

	if(UNIX)
		target_link_libraries(unittest PRIVATE pthread dl)
	endif()

	file(GLOB_RECURSE unittest_sources "${CMAKE_CURRENT_SOURCE_DIR}/test/hiprtT*.h" "${CMAKE_CURRENT_SOURCE_DIR}/test/hiprtT*.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/test/shared.h" "${CMAKE_CURRENT_SOURCE_DIR}/test/main.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/test/CornellBox.h" "${CMAKE_CURRENT_SOURCE_DIR}/test/kernels/*.h" "${CMAKE_CURRENT_SOURCE_DIR}/contrib/gtest-1.6.0/gtest-all.cc")


	target_sources(unittest PRIVATE ${unittest_sources} ${orochi_sources})

	target_include_directories(unittest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/contrib/gtest-1.6.0 ${CMAKE_CURRENT_SOURCE_DIR}/contrib/embree/include)


	if(WIN32)

		# Use target_link_directories to specify additional library directories
		target_link_directories(unittest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/contrib/embree/win)
		target_link_directories(unittest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/contrib/bin/win64)

		copy_dir(${CMAKE_CURRENT_SOURCE_DIR}/contrib/embree/win ${CMAKE_CURRENT_SOURCE_DIR}/dist/bin/Release "*.dll")
		copy_dir(${CMAKE_CURRENT_SOURCE_DIR}/contrib/embree/win ${CMAKE_CURRENT_SOURCE_DIR}/dist/bin/Debug "*.dll")
		copy_dir(${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/contrib/bin/win64 ${CMAKE_CURRENT_SOURCE_DIR}/dist/bin/Release "*.dll")
		copy_dir(${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi/contrib/bin/win64 ${CMAKE_CURRENT_SOURCE_DIR}/dist/bin/Debug "*.dll")

		# Explicitly link libraries from contrib/embree/win and contrib/bin/win64
		target_link_libraries(unittest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/contrib/embree/win/embree4.lib)

	endif()


	if(UNIX)
		target_link_directories(unittest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/contrib/embree/linux)
	endif()

	target_link_libraries(unittest PRIVATE embree4 tbb)

endif()


# Project: HIPRTEW Test
if(HIPRTEW)
	add_executable(hiprtewtest)

	target_compile_definitions(hiprtewtest PRIVATE HIPRT_EXPORTS USE_HIPRTEW)
	if(WIN32)
		target_compile_options(hiprtewtest PRIVATE /wd4244)
		target_link_libraries(hiprtewtest PRIVATE version)
	endif()

	target_include_directories(hiprtewtest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/contrib/Orochi)
	if(UNIX)
		target_link_libraries(hiprtewtest PRIVATE pthread dl)
	endif()

	file(GLOB_RECURSE hiprtewtest_sources "${CMAKE_CURRENT_SOURCE_DIR}/test/hiprtewTest.h" "${CMAKE_CURRENT_SOURCE_DIR}/test/hiprtewTest.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/contrib/gtest-1.6.0/gtest-all.cc")
	target_sources(hiprtewtest PRIVATE ${hiprtewtest_sources} ${orochi_sources})

	target_include_directories(hiprtewtest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/contrib/gtest-1.6.0)

	target_compile_definitions(hiprtewtest PRIVATE GTEST_HAS_TR1_TUPLE=0)
endif()
