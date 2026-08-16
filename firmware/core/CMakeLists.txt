cmake_minimum_required(VERSION 3.20)
project(retrofm_core C)

enable_testing()

add_library(retrofm_core STATIC
    vendor/mdxtools/fm_driver.c
    vendor/mdxtools/fm_opm_driver.c
    src/retrofm_event.c
    src/retrofm_mdx.c
    src/retrofm_mdx_sequence.c
    src/retrofm_pcm.c
    src/retrofm_pdx.c
    src/retrofm_player.c
    src/retrofm_playlist.c
    src/retrofm_sjis.c
    src/retrofm_sjis_table.c
    src/retrofm_vgm.c
    src/retrofm_vgz.c
)
target_include_directories(retrofm_core PUBLIC
    include
    vendor/mdxtools)
target_compile_features(retrofm_core PUBLIC c_std_11)

option(RETROFM_ENABLE_VGZ "Build VGZ decompression support" ON)
set(RETROFM_MINIZ_DIR
    "${CMAKE_CURRENT_LIST_DIR}/../../build/deps/miniz"
    CACHE PATH "Path to the pinned miniz source checkout")

set(RETROFM_VGZ_ENABLED OFF)
if(RETROFM_ENABLE_VGZ AND
   EXISTS "${RETROFM_MINIZ_DIR}/miniz.h" AND
   EXISTS "${RETROFM_MINIZ_DIR}/miniz_tinfl.c")
    set(RETROFM_VGZ_ENABLED ON)
    set(_retrofm_miniz_generated_dir
        "${CMAKE_CURRENT_BINARY_DIR}/retrofm_miniz_generated")
    file(MAKE_DIRECTORY "${_retrofm_miniz_generated_dir}")
    file(WRITE "${_retrofm_miniz_generated_dir}/miniz_export.h"
        "#ifndef MINIZ_EXPORT_H\n#define MINIZ_EXPORT_H\n#define MINIZ_EXPORT\n#endif\n")

    add_library(retrofm_miniz_tinfl STATIC
        "${RETROFM_MINIZ_DIR}/miniz_tinfl.c")
    target_include_directories(retrofm_miniz_tinfl PRIVATE
        "${RETROFM_MINIZ_DIR}"
        "${_retrofm_miniz_generated_dir}")
    target_compile_definitions(retrofm_miniz_tinfl PRIVATE
        MINIZ_NO_ARCHIVE_APIS
        MINIZ_NO_DEFLATE_APIS
        MINIZ_NO_MALLOC
        MINIZ_NO_STDIO
        MINIZ_NO_TIME
        MINIZ_NO_ZLIB_APIS)

    target_include_directories(retrofm_core SYSTEM PRIVATE
        "${RETROFM_MINIZ_DIR}"
        "${_retrofm_miniz_generated_dir}")
    target_compile_definitions(retrofm_core
        PUBLIC RETROFM_HAS_VGZ=1
        PRIVATE
            MINIZ_NO_ARCHIVE_APIS
            MINIZ_NO_DEFLATE_APIS
            MINIZ_NO_MALLOC
            MINIZ_NO_STDIO
            MINIZ_NO_TIME
            MINIZ_NO_ZLIB_APIS)
    target_link_libraries(retrofm_core PRIVATE retrofm_miniz_tinfl)
else()
    target_compile_definitions(retrofm_core PUBLIC RETROFM_HAS_VGZ=0)
    message(STATUS
        "VGZ support disabled: pinned miniz not found at ${RETROFM_MINIZ_DIR}")
endif()

if(MSVC)
    target_compile_options(retrofm_core PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_core PRIVATE -Wall -Wextra -Werror -pedantic)
endif()

add_executable(retrofm_core_tests tests/test_vgm.c)
target_link_libraries(retrofm_core_tests PRIVATE retrofm_core)
if(MSVC)
    target_compile_options(retrofm_core_tests PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_core_tests PRIVATE -Wall -Wextra -Werror -pedantic)
endif()

add_test(NAME retrofm_core_tests COMMAND retrofm_core_tests)

add_executable(retrofm_pdx_tests tests/test_pdx.c)
target_link_libraries(retrofm_pdx_tests PRIVATE retrofm_core)
if(MSVC)
    target_compile_options(retrofm_pdx_tests PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_pdx_tests PRIVATE -Wall -Wextra -Werror -pedantic)
endif()

add_test(NAME retrofm_pdx_tests COMMAND retrofm_pdx_tests)

add_executable(retrofm_mdx_tests tests/test_mdx.c)
target_link_libraries(retrofm_mdx_tests PRIVATE retrofm_core)
if(MSVC)
    target_compile_options(retrofm_mdx_tests PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_mdx_tests PRIVATE
        -Wall -Wextra -Werror -pedantic)
endif()

add_test(NAME retrofm_mdx_tests COMMAND retrofm_mdx_tests)

add_executable(retrofm_mdx_trace_tests tests/test_mdx_trace.c)
target_link_libraries(retrofm_mdx_trace_tests PRIVATE retrofm_core)
if(MSVC)
    target_compile_options(retrofm_mdx_trace_tests PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_mdx_trace_tests PRIVATE
        -Wall -Wextra -Werror -pedantic)
endif()

add_test(NAME retrofm_mdx_trace_tests COMMAND retrofm_mdx_trace_tests)

add_executable(retrofm_mdx_probe tools/retrofm_mdx_probe.c)
target_link_libraries(retrofm_mdx_probe PRIVATE retrofm_core)
if(MSVC)
    target_compile_definitions(retrofm_mdx_probe PRIVATE
        _CRT_SECURE_NO_WARNINGS)
    target_compile_options(retrofm_mdx_probe PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_mdx_probe PRIVATE
        -Wall -Wextra -Werror -pedantic)
endif()

add_executable(retrofm_vgm_probe tools/retrofm_vgm_probe.c)
target_link_libraries(retrofm_vgm_probe PRIVATE retrofm_core)
if(MSVC)
    target_compile_definitions(retrofm_vgm_probe PRIVATE
        _CRT_SECURE_NO_WARNINGS)
    target_compile_options(retrofm_vgm_probe PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_vgm_probe PRIVATE
        -Wall -Wextra -Werror -pedantic)
endif()

add_executable(retrofm_generated_tests tests/test_generated.c)
target_link_libraries(retrofm_generated_tests PRIVATE retrofm_core)
target_compile_definitions(retrofm_generated_tests PRIVATE
    RETROFM_TESTDATA_DIR="${CMAKE_CURRENT_LIST_DIR}/../../testdata/generated"
    $<$<C_COMPILER_ID:MSVC>:_CRT_SECURE_NO_WARNINGS>)
if(MSVC)
    target_compile_options(retrofm_generated_tests PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_generated_tests PRIVATE
        -Wall -Wextra -Werror -pedantic)
endif()

add_test(NAME retrofm_generated_tests COMMAND retrofm_generated_tests)

add_executable(retrofm_pcm_tests tests/test_pcm.c)
target_link_libraries(retrofm_pcm_tests PRIVATE retrofm_core)
if(MSVC)
    target_compile_options(retrofm_pcm_tests PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_pcm_tests PRIVATE
        -Wall -Wextra -Werror -pedantic)
endif()

add_test(NAME retrofm_pcm_tests COMMAND retrofm_pcm_tests)

add_executable(retrofm_player_tests tests/test_player.c)
target_link_libraries(retrofm_player_tests PRIVATE retrofm_core)
if(MSVC)
    target_compile_options(retrofm_player_tests PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_player_tests PRIVATE
        -Wall -Wextra -Werror -pedantic)
endif()

add_test(NAME retrofm_player_tests COMMAND retrofm_player_tests)

add_executable(retrofm_sjis_tests tests/test_sjis.c)
target_link_libraries(retrofm_sjis_tests PRIVATE retrofm_core)
if(MSVC)
    target_compile_options(retrofm_sjis_tests PRIVATE /W4 /WX)
else()
    target_compile_options(retrofm_sjis_tests PRIVATE
        -Wall -Wextra -Werror -pedantic)
endif()

add_test(NAME retrofm_sjis_tests COMMAND retrofm_sjis_tests)

if(RETROFM_VGZ_ENABLED)
    add_executable(retrofm_vgz_tests tests/test_vgz.c)
    target_link_libraries(retrofm_vgz_tests PRIVATE retrofm_core)
    if(MSVC)
        target_compile_options(retrofm_vgz_tests PRIVATE /W4 /WX)
    else()
        target_compile_options(retrofm_vgz_tests PRIVATE
            -Wall -Wextra -Werror -pedantic)
    endif()

    add_test(NAME retrofm_vgz_tests COMMAND retrofm_vgz_tests)
endif()
