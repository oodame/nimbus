#------------------------------------------------------------
# A macro wrapper facilites add libary for Nimbus
#
macro(nimbus_add_library suffix type)
    add_library(${suffix} ${type} ${ARGN})    

    #add_dependencies()
endmacro()

macro(nimbus_add_executable target)


    nimbus_install_target_after_build(${target})
endmacro()

#------------------------------------------------------------
# copy generated executable or libraries to build directory
function(nimbus_install_target_after_build target)
    # nimbus
    # |------bin
    # |------lib
    # |------release
    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo ">>>>>> Installing target ${target} <<<<<<"
        COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:${target}> 
                                         $<IF:$<STREQUAL:$<TARGET_PROPERTY:${target}, TYPE>, 
                                                         EXECUTABLE>, 
                                              ${CMAKE_SOURCE_DIR}/bin, 
                                              ${CMAKE_SOURCE_DIR}/lib>
    )
endfunction()



macro(nimbus_add_test target)
    
endmacro()

#------------------------------------------------------------
# A macro to exclude test directory if testing is not enabled.
#
macro(nimbus_add_subdirectory dir_name)
    if ((NOT ENABLE_TESTING) AND ("${dir_name}" MATCHES "test"))    
        add_subdirectory(${dir_name} EXCLUDE_FROM_ALL)
    else()
        add_subdirectory(${dir_name})
    endif()
endmacro()

#------------------------------------------------------------
# A macro to exclude test directory if testing is not enabled.
#
macro(nimbus_link_libraries target)
    target_link_libraries(${target}
        ${ARGN}
        # the following are third party libraries    
    )    
endmacro()


#------------------------------------------------------------
# A macro to exclude test directory if testing is not enabled.
#
include(FetchContent)

macro(NimbusFetchContent_MakeAvailable target MODULES)
    FetchContent_GetProperties(${target})
    if(NOT $<LOWER_CASE:${target}>_POPULATED)
       FetchContent_Populate(${target})
    endif()
        
endmacro(NimbusFetchContent_MakeAvailable)
