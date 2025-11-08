cmake_minimum_required(VERSION 3.10)
project(icon_loader)

# Find GTK3
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK3 REQUIRED gtk+-3.0)

# Add include directories
include_directories(${GTK3_INCLUDE_DIRS})

# Create shared library
add_library(icon_loader SHARED
    icon_loader.c
)

# Link against GTK3
target_link_libraries(icon_loader ${GTK3_LIBRARIES})

# Set library output path
set_target_properties(icon_loader PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)