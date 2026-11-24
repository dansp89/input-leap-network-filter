cmake_minimum_required(VERSION 3.16)
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" ILNF_VERSION LIMIT_COUNT 1)
project(input_leap_network_filter VERSION ${ILNF_VERSION} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# ILNF_QT_MAJOR: 5 or 6 (must match the Qt used by the Input Leap binary).
set(ILNF_QT_MAJOR "6" CACHE STRING "Qt major version to build against (5 or 6)")
option(ILNF_BUILD_FILTER "Build the Qt LD_PRELOAD library" ON)
option(ILNF_BUILD_TESTS "Build tests" ON)
option(ILNF_SANITIZE "Build tests with ASan/UBSan" OFF)

add_compile_options(-Wall -Wextra -Wpedantic)
if(ILNF_SANITIZE)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

# Qt-independent core shared by the library, the probe and the tests.
add_library(ilnf_core STATIC src/config.cpp src/interfaces.cpp)
target_include_directories(ilnf_core PUBLIC include)
set_target_properties(ilnf_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_executable(ilnf-probe tools/probe.cpp)
target_link_libraries(ilnf-probe PRIVATE ilnf_core)

if(ILNF_BUILD_FILTER)
  find_package(Qt${ILNF_QT_MAJOR} COMPONENTS Core Network REQUIRED)
  add_library(network-filter SHARED src/filter.cpp)
  set_target_properties(network-filter PROPERTIES PREFIX "" OUTPUT_NAME "network-filter-qt${ILNF_QT_MAJOR}")
  target_link_libraries(network-filter PRIVATE ilnf_core Qt${ILNF_QT_MAJOR}::Core Qt${ILNF_QT_MAJOR}::Network ${CMAKE_DL_LIBS})
  # Only the interposed Qt symbol needs to be visible.
  target_link_options(network-filter PRIVATE -Wl,--exclude-libs,ALL -Wl,-z,now -Wl,-z,relro)

  # Tiny Qt program printing QNetworkInterface::allAddresses(), its arguments
  # and LD_PRELOAD. Used to validate the library before activation and as a
  # stand-in for the Input Leap GUI in tests.
  add_executable(fake-input-leap tests/fixtures/fake_input_leap.cpp)
  target_link_libraries(fake-input-leap PRIVATE Qt${ILNF_QT_MAJOR}::Core Qt${ILNF_QT_MAJOR}::Network)
endif()

if(ILNF_BUILD_TESTS)
  enable_testing()
  add_executable(test_config tests/unit/test_config.cpp)
  target_link_libraries(test_config PRIVATE ilnf_core)
  add_test(NAME unit.config COMMAND test_config)

  add_executable(ilnf-bench tests/bench/bench.cpp)
  target_link_libraries(ilnf-bench PRIVATE ilnf_core)

  if(ILNF_BUILD_FILTER)
    add_test(NAME integration.preload
             COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/preload.sh
                     $<TARGET_FILE:network-filter> $<TARGET_FILE:fake-input-leap>)
    add_test(NAME integration.cli
             COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/cli.sh $<TARGET_FILE:fake-input-leap>)
  endif()
endif()
