cmake_minimum_required(VERSION 3.27)

project(
    hypr-autoscroll
    VERSION 0.3.2
    DESCRIPTION "Windows-style middle-click autoscrolling for Hyprland"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland)

add_library(hypr-autoscroll SHARED src/main.cpp)
set_target_properties(hypr-autoscroll PROPERTIES PREFIX "")
target_link_libraries(hypr-autoscroll PRIVATE PkgConfig::HYPRLAND)
target_compile_options(
    hypr-autoscroll
    PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        $<$<CXX_COMPILER_ID:GNU>:-fno-gnu-unique>
)

include(CTest)
if(BUILD_TESTING)
    add_executable(test-scroll-math tests/test_scroll_math.cpp)
    target_compile_options(
        test-scroll-math
        PRIVATE -Wall -Wextra -Wpedantic
    )
    add_test(NAME scroll-math COMMAND test-scroll-math)
endif()

install(TARGETS hypr-autoscroll LIBRARY DESTINATION lib)
