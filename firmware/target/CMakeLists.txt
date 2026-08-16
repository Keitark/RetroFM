cmake_minimum_required(VERSION 3.20)
project(retrofm_target_support C CXX)

enable_testing()

set(RETROFM_PORTABLE_MDX_DIR
    "${CMAKE_CURRENT_LIST_DIR}/../../build/deps/portable_mdx"
    CACHE PATH "Path to pinned portable_mdx checkout")

if(EXISTS "${RETROFM_PORTABLE_MDX_DIR}/src/mxdrv/mxdrv.cpp")
    # MXDRV needs X68Sound's OPM timer/command engine to sequence the song, but
    # JT51 is the product FM source. Generate a build-local copy that compiles
    # out only X68Sound's operator/output block while retaining its timer,
    # command, register, envelope, ADPCM, and PCM8 paths. The pinned dependency
    # remains clean and MXDRV remains the authoritative sequencer.
    set(_portable_opm_source
        "${RETROFM_PORTABLE_MDX_DIR}/src/x68sound/x68sound_opm.cpp")
    file(READ "${_portable_opm_source}" _portable_opm_text)
    set(_portable_opm_start
        "\t\t\t\t\t{\n\t\t\t\t\t\tlfo.Update();")
    set(_portable_opm_end_62
        "\t\t\t}\t// UseOpmFlag\n\n\t\t\tif (UseAdpcmFlag) {")
    set(_portable_opm_end_22
        "\t\t}\n\n\t\tif (UseAdpcmFlag) {")
    string(REPLACE "${_portable_opm_start}"
        "#if !defined(RETROFM_SUPPRESS_SOFTWARE_FM)\n${_portable_opm_start}"
        _portable_opm_patched "${_portable_opm_text}")
    string(REPLACE "${_portable_opm_end_62}"
        "#endif\n${_portable_opm_end_62}"
        _portable_opm_patched "${_portable_opm_patched}")
    string(REPLACE "${_portable_opm_end_22}"
        "#endif\n${_portable_opm_end_22}"
        _portable_opm_patched "${_portable_opm_patched}")
    string(REGEX MATCHALL "RETROFM_SUPPRESS_SOFTWARE_FM"
        _portable_opm_guards "${_portable_opm_patched}")
    list(LENGTH _portable_opm_guards _portable_opm_guard_count)
    if(NOT _portable_opm_guard_count EQUAL 2)
        message(FATAL_ERROR
            "Expected two pinned portable_mdx OPM synthesis blocks")
    endif()
    set(_portable_opm_generated
        "${CMAKE_CURRENT_BINARY_DIR}/generated/x68sound_opm.cpp")
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/generated")
    file(WRITE "${_portable_opm_generated}" "${_portable_opm_patched}")

    set(_portable_mdx_sources
        "${RETROFM_PORTABLE_MDX_DIR}/src/mdx_util.c"
        "${RETROFM_PORTABLE_MDX_DIR}/src/mxdrv/mxdrv_context.cpp"
        "${RETROFM_PORTABLE_MDX_DIR}/src/mxdrv/mxdrv.cpp"
        "${RETROFM_PORTABLE_MDX_DIR}/src/mxdrv/sound_iocs.cpp"
        "${RETROFM_PORTABLE_MDX_DIR}/src/x68sound/x68sound_adpcm.cpp"
        "${RETROFM_PORTABLE_MDX_DIR}/src/x68sound/x68sound_context.cpp"
        "${RETROFM_PORTABLE_MDX_DIR}/src/x68sound/x68sound_lfo.cpp"
        "${RETROFM_PORTABLE_MDX_DIR}/src/x68sound/x68sound_op.cpp"
        "${_portable_opm_generated}"
        "${RETROFM_PORTABLE_MDX_DIR}/src/x68sound/x68sound_pcm8.cpp"
        "${RETROFM_PORTABLE_MDX_DIR}/src/x68sound/x68sound.cpp")
    set_source_files_properties(
        "${RETROFM_PORTABLE_MDX_DIR}/src/mxdrv/sound_iocs.cpp"
        PROPERTIES COMPILE_DEFINITIONS
        "_iocs_opmset=retrofm_portable_iocs_opmset_internal")
    set_source_files_properties(
        "${RETROFM_PORTABLE_MDX_DIR}/src/x68sound/x68sound.cpp"
        PROPERTIES COMPILE_DEFINITIONS
        "X68Sound_StartPcm=retrofm_portable_x68sound_start_pcm_internal")
    set_source_files_properties(
        "${_portable_opm_generated}"
        PROPERTIES COMPILE_DEFINITIONS
        "RETROFM_SUPPRESS_SOFTWARE_FM=1")
    add_library(retrofm_mxdrv STATIC
        retrofm_mxdrv.cpp
        ${_portable_mdx_sources})
    target_include_directories(retrofm_mxdrv PUBLIC
        ${CMAKE_CURRENT_LIST_DIR}
        ${CMAKE_CURRENT_LIST_DIR}/../core/include
        "${RETROFM_PORTABLE_MDX_DIR}/include"
        "${RETROFM_PORTABLE_MDX_DIR}/src/mxdrv"
        "${RETROFM_PORTABLE_MDX_DIR}/src/x68sound")
    target_compile_features(retrofm_mxdrv PUBLIC cxx_std_17)

    add_executable(retrofm_mxdrv_tests
        test_mxdrv.cpp
        ../core/src/retrofm_event.c)
    target_link_libraries(retrofm_mxdrv_tests PRIVATE retrofm_mxdrv)
    target_compile_definitions(retrofm_mxdrv_tests PRIVATE
        RETROFM_TESTDATA_DIR="${CMAKE_CURRENT_LIST_DIR}/../../testdata/generated"
        $<$<CXX_COMPILER_ID:MSVC>:_CRT_SECURE_NO_WARNINGS>)
    add_test(NAME retrofm_mxdrv_tests COMMAND retrofm_mxdrv_tests)
endif()

add_library(retrofm_st7789 STATIC
    retrofm_st7789.c
    retrofm_ui.c
    retrofm_japanese_font.c
    vendor/lgfx_font_japan_gothic_12.c)
target_include_directories(retrofm_st7789 PUBLIC ${CMAKE_CURRENT_LIST_DIR})
target_compile_features(retrofm_st7789 PUBLIC c_std_11)

add_executable(retrofm_st7789_tests test_st7789.c)
target_link_libraries(retrofm_st7789_tests PRIVATE retrofm_st7789)

add_executable(retrofm_ui_preview preview_ui.c)
target_link_libraries(retrofm_ui_preview PRIVATE retrofm_st7789)

add_executable(retrofm_hw_tests
    test_hw.c
    ../core/src/retrofm_event.c)
target_include_directories(retrofm_hw_tests PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}
    ${CMAKE_CURRENT_LIST_DIR}/../core/include)

add_executable(retrofm_diagnostic_tests
    test_diagnostic.c
    retrofm_diagnostic.c)
target_include_directories(retrofm_diagnostic_tests PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}
    ${CMAKE_CURRENT_LIST_DIR}/../core/include)

if(MSVC)
    target_compile_options(retrofm_st7789 PRIVATE /W4 /WX)
    target_compile_options(retrofm_st7789_tests PRIVATE /W4 /WX)
    target_compile_options(retrofm_ui_preview PRIVATE /W4 /WX)
    target_compile_definitions(retrofm_ui_preview PRIVATE
        _CRT_SECURE_NO_WARNINGS)
    target_compile_options(retrofm_hw_tests PRIVATE /W4 /WX)
    target_compile_options(retrofm_diagnostic_tests PRIVATE /W4 /WX)
    if(TARGET retrofm_mxdrv)
        target_compile_options(retrofm_mxdrv PRIVATE /W3)
        target_compile_options(retrofm_mxdrv_tests PRIVATE /W4 /WX)
    endif()
else()
    target_compile_options(retrofm_st7789 PRIVATE -Wall -Wextra -Werror -pedantic)
    target_compile_options(retrofm_st7789_tests PRIVATE -Wall -Wextra -Werror -pedantic)
    target_compile_options(retrofm_ui_preview PRIVATE
        -Wall -Wextra -Werror -pedantic)
    target_compile_options(retrofm_hw_tests PRIVATE -Wall -Wextra -Werror -pedantic)
    target_compile_options(retrofm_diagnostic_tests PRIVATE
        -Wall -Wextra -Werror -pedantic)
    if(TARGET retrofm_mxdrv)
        target_compile_options(retrofm_mxdrv PRIVATE -Wall -Wextra)
        target_compile_options(retrofm_mxdrv_tests PRIVATE
            -Wall -Wextra -Werror -pedantic)
    endif()
endif()

add_test(NAME retrofm_st7789_tests COMMAND retrofm_st7789_tests)
add_test(NAME retrofm_hw_tests COMMAND retrofm_hw_tests)
add_test(NAME retrofm_diagnostic_tests COMMAND retrofm_diagnostic_tests)
