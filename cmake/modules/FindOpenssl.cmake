include(FindPackageHandleStandardArgs)

set(OPENSSL_ROOT ${NIMBUS_THIRD_PARTY_PATH}/openssl-3.0.4)

find_path(Openssl_INCLUDE_DIR 
    NAMES
        openssl/ssl.h
    PATHS 
        ${OPENSSL_ROOT}
    PATH_SUFFIXES 
        include
    NO_DEFAULT_PATH
)

find_library(Openssl_LIBRARY 
    NAMES
        libssl.a
    PATHS
        ${OPENSSL_ROOT}
    PATH_SUFFIXES
        lib
    NO_DEFAULT_PATH
)

find_package_handle_standard_args(Openssl 
    FOUND_VAR
        Openssl_FOUND
    REQUIRED_VARS
        Openssl_INCLUDE_DIR
        Openssl_LIBRARY    
)

if (Openssl_FOUND)
    add_library(Openssl::ssl
        
    )
else()
    message(ERROR "Cannot find openssl")
endif()