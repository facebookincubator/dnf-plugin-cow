cmake_minimum_required(VERSION 3.16)
project(dnf-plugin-cow LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBDNF5 REQUIRED libdnf5)

add_library(reflink MODULE reflink.cpp)
set_target_properties(reflink PROPERTIES PREFIX "")
target_include_directories(reflink PRIVATE ${LIBDNF5_INCLUDE_DIRS})
target_link_libraries(reflink PRIVATE ${LIBDNF5_LIBRARIES})
target_compile_options(reflink PRIVATE ${LIBDNF5_CFLAGS_OTHER})

pkg_get_variable(LIBDNF5_PLUGINDIR libdnf5 plugindir)
if(NOT LIBDNF5_PLUGINDIR)
    include(GNUInstallDirs)
    set(LIBDNF5_PLUGINDIR "${CMAKE_INSTALL_FULL_LIBDIR}/libdnf5/plugins")
endif()

install(TARGETS reflink DESTINATION ${LIBDNF5_PLUGINDIR})
install(FILES reflink.conf DESTINATION ${CMAKE_INSTALL_FULL_SYSCONFDIR}/dnf/libdnf5-plugins)
