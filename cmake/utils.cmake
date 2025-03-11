function(copy_dir src_dir dst_dir pattern)
	file(GLOB_RECURSE files "${src_dir}/${pattern}")
	foreach(file ${files})
		file(RELATIVE_PATH rel_file ${src_dir} ${file})
		set(target "${dst_dir}/${rel_file}")
		get_filename_component(target_dir ${target} DIRECTORY)
		file(MAKE_DIRECTORY ${target_dir})
		file(COPY ${file} DESTINATION ${target_dir})
	endforeach()
endfunction()

function(file_exists file)
	if(EXISTS ${file})
		return(0)
	else()
		return(1)
	endif()
endfunction()

function(read_file file)
	file(READ ${file} content)
	return(${content})
endfunction()

function(get_version file)
	file(STRINGS ${file} lines)
	list(GET lines 0 major)
	list(GET lines 1 minor)
	list(GET lines 2 patch)
	set(patch_hex "0x${patch}")
	set(major ${major} PARENT_SCOPE)
	set(minor ${minor} PARENT_SCOPE)
	set(patch ${patch_hex} PARENT_SCOPE)
endfunction()



# Remove the last character from the string if it's a / or \\  
function(remove_trailing_slash strInOut)
	string(LENGTH "${${strInOut}}" strLength)
	math(EXPR lastIndex "${strLength} - 1")
	string(SUBSTRING "${${strInOut}}" ${lastIndex} 1 lastChar)
	if("${lastChar}" STREQUAL "\\" OR "${lastChar}" STREQUAL "/")
		string(SUBSTRING "${${strInOut}}" 0 ${lastIndex} strInOut_modified)
		set(${strInOut} "${strInOut_modified}" PARENT_SCOPE)
	endif()
endfunction()




# 'result'      is the HIP version as string, for example: 6.2
# 'result_path' is the output of the path to HIP, for example:  C:\Program Files\AMD\ROCm\6.2
function(get_hip_sdk_version result result_path)
	if(WIN32)
		set(root ".\\")
	endif()

	set(exec_perl "")
	set(hipCommand "hipcc")
	set(PATH $ENV{PATH})
	set(useHipFromPATH OFF)


	# Check if HIP_PATH is defined as a CMake parameter
	if(DEFINED HIP_PATH)
		message(STATUS "HIP_PATH is defined as a CMake parameter: ${HIP_PATH}")

	# Check if HIP_PATH is defined as an environment variable
	elseif(DEFINED ENV{HIP_PATH})
		
		set(HIP_PATH $ENV{HIP_PATH})
		message(STATUS "HIP_PATH is defined as an environment variable: ${HIP_PATH}")
			
	# if HIP_PATH is not in cmake, and not in environment variable
	else()
		message(WARNING "WARNING: HIP_PATH is not defined as a CMake parameter or an environment variable - NOT RECOMMENDED")

		# TODO: improve that, but it's not recommanded to use the cmake script without defining HIP_PATH anyway...
		set(${result_path} "UNKONWN_PATH" PARENT_SCOPE)

		# Check if HIP is in the PATH environment variable
		string(REPLACE ";" "\n" PATH_LIST ${PATH})
		foreach(token ${PATH_LIST})
			if("${token}" MATCHES "hip")
				if(EXISTS "${token}/hipcc")
					set(useHipFromPATH ON)
				endif()
			endif()
		endforeach()


	endif()


	# clean/format HIP_PATH here.
	if ( HIP_PATH )
		remove_trailing_slash(HIP_PATH)
		# message(STATUS "HIP_PATH formatted: ${HIP_PATH}")
		set(${result_path} ${HIP_PATH} PARENT_SCOPE)
	endif()


	# build hip command for Windows
	if(WIN32)
		set(exec_perl "perl")

		if(NOT HIP_PATH)
			if(useHipFromPATH)
				set(hipCommand "hipcc")
			else()
				# try classic path used by HIPRT developers
				set(hipCommand "hipSdk\\bin\\hipcc")
			endif()
		else()
		
			# HIP_PATH is expected to look like: C:\Program Files\AMD\ROCm\5.7
			
			if(EXISTS "${HIP_PATH}\\bin\\hipcc.exe")
				# in newer version of HIP SDK (>= 6.3), we are using 'hipcc.exe --version' to check the version
				# message(STATUS "using hipcc.exe to get the version")
				set(exec_perl "")
				set(hipCommand "${HIP_PATH}\\bin\\hipcc.exe")
			else()
				# in older version of HIP SDK, we are using 'perl hipcc --version' to check the version
				# message(STATUS "using perl hipcc to get the version")
				set(hipCommand "${HIP_PATH}\\bin\\${hipCommand}")
			endif()


		endif()
	
	# build hip command for Linux
	else()
	
		# If not defined we try to take it from the PATH
		if(NOT HIP_PATH)
			set(hipCommand "hipcc")
			
		# otherwise, build the hipcc command with full path.
		else()
			set(hipCommand "${HIP_PATH}/bin/${hipCommand}")
		endif()
	endif()


	file(WRITE ${CMAKE_BINARY_DIR}/hip_version_tmp.txt "")

	# message(STATUS "hipCommand : ${hipCommand}")
	# message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")

	execute_process(
		COMMAND ${exec_perl} "${hipCommand}" --version
		OUTPUT_FILE ${CMAKE_BINARY_DIR}/hip_version_tmp.txt
		# ERROR_QUIET
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		)

	file(READ ${CMAKE_BINARY_DIR}/hip_version_tmp.txt version_output)
	string(REGEX MATCH "[0-9]+\\.[0-9]+" version "${version_output}")

	file(REMOVE ${CMAKE_BINARY_DIR}/hip_version_tmp.txt)

	if(NOT version)
		set(version "HIP_SDK_NOT_FOUND")
	endif()

	message(STATUS "HIP VERSION from command : ${version}")
	set(${result} ${version} PARENT_SCOPE)
endfunction()

function(write_version_info in_file header_file version_file version_str_out)

	if(NOT EXISTS ${version_file})
		message(FATAL_ERROR "Version.txt file missing!")
	endif()
	if(NOT EXISTS ${in_file})
		message(FATAL_ERROR "${in_file} file is missing!")
	endif()

	# Read version file and extract version information
	get_version(${version_file})

	# set(version "${major}${minor}")
	# set(version_str "${version}_${patch}")

	# Read the content of the header template file
	file(READ ${in_file} header_content)

	# Calculate HIPRT_API_VERSION
	math(EXPR HIPRT_VERSION "${major} * 1000 + ${minor}")


	# Format version_str as a zero-padded 5-digit string
	string(LENGTH "${HIPRT_VERSION}" HIPRT_VERSION_LEN)
	if(${HIPRT_VERSION_LEN} LESS 5)
		math(EXPR HIPRT_VERSION_PAD "5 - ${HIPRT_VERSION_LEN}")
		string(REPEAT "0" ${HIPRT_VERSION_PAD} HIPRT_VERSION_PADDED)
		set(version_str "${HIPRT_VERSION_PADDED}${HIPRT_VERSION}" )
	else()
		set(version_str "${HIPRT_VERSION}" )
	endif()

	# message(STATUS "HIPRT_API_VERSION: ${version_str}_${patch}")

	set(HIPRT_API_VERSION ${HIPRT_VERSION})

	# Replace placeholders with actual version values
	string(REPLACE "@HIPRT_MAJOR_VERSION@" "${major}" header_content "${header_content}")
	string(REPLACE "@HIPRT_MINOR_VERSION@" "${minor}" header_content "${header_content}")
	string(REPLACE "@HIPRT_PATCH_VERSION@" "${patch}" header_content "${header_content}")
	string(REPLACE "@HIPRT_VERSION_STR@" "\"${version_str}\"" header_content "${header_content}")
	string(REPLACE "@HIPRT_API_VERSION@" "${HIPRT_API_VERSION}" header_content "${header_content}")

	# Get HIP SDK version and replace placeholder
	string(REPLACE "@HIP_VERSION_STR@" "\"${HIP_VERSION_STR}\"" header_content "${header_content}")

	# Write the modified content to the header file
	file(WRITE ${header_file} "${header_content}")

	set(${version_str_out} ${version_str} PARENT_SCOPE)
endfunction()



