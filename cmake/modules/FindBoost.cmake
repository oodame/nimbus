list(APPEND BOOST_COMPONENT_REQUIRED filesystem system)
set(Boost_MINIMUM_REQUIRED 1.79)

find_package(Boost ${Boost_MINIMUM_REQUIRED} QUIET COMPONENTS ${BOOST_COMPONENT_REQUIRED})

if (Boost_FOUND)
    message(STATUS "Found Boost version ${Boost_MAJOR_VERSION}.${Boost_MINOR_VERSION}.${Boost_SUBMINOR_VERSION}")
    add_library(Boost::boost INTERFACE)
else()
    message(STATUS "Boost ${Boost_MINIMUM_REQUIRED} could not be located, now building Boost ${Boost_MINIMUM_REQUIRED} instead")
    
endif()