cmake_minimum_required(VERSION 3.23 FATAL_ERROR)

project(NimbusGraph 
    VERSION       0.0.1
    DESCRIPTION   "An Exploration on OLAP Graph Database."
    LANGUAGES     C CXX)

set_property(DIRECTORY PROPERTY EP_BASE ${CMAKE_BINARY_DIR}/subprojects)
set()

#-----------------------------------------------------
# enable testing BUILD_TESTING configure
if (CMKAE_PROJECT_NAME STREQUAL PROJECT_NAME)
    include(CTest)
endif() 

#-----------------------------------------------------
# Global CMAKE_* variable settings
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)


# Turn on -fPIC
set(CMAKE_POSITION_INDEPENDENT_CODE ON)


#-----------------------------------------------------
# Setup build directories
execute_process(COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_SOURCE_DIR}/bin" "${CMAKE_SOURCE_DIR}/lib"
    RESULT_VARIABLE result
)
if (result)
    message(FATAL_ERROR "Make directory \"${CMAKE_SOURCE_DIR}/{bin,lib}\" failed: ${result}")
endif()


#-----------------------------------------------------
# Includes custom cmake files
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/nimbus)


include(NimbusThirdParty)