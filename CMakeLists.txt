cmake_minimum_required(VERSION 3.10)
project(icon_loader)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK3 REQUIRED gtk+-3.0)

# Include GTK headers
include_directories(${GTK3_INCLUDE_DIRS})
link_directories(${GTK3_LIBRARY_DIRS})

# Add GTK compile flags
add_definitions(${GTK3_CFLAGS_OTHER})

# Create shared library
add_library(icon_loader SHARED
  src/icon_loader.c
)

# Link against GTK
target_link_libraries(icon_loader ${GTK3_LIBRARIES})