include(ExternalProject)
include(FetchContent)
include(NimbusThirdPartyVersions)

set(NimbusSubProjects 
    openssl
    xz
    lz4
    lzma
    snappy
    zlib
    libtool
    double-conversion
    libevent
    gflags
    glog
    boost
    folly
)

macro(find_package)
    if (NOT "${ARG0}" IN_LIST NimbusSubProjects)
        _find_package(${ARGV})
    endif()
endmacro()

# folly
FetchContent_Declare(
    folly 
    GIT_REPOSITORY    https://github.com/facebook/folly.git
    GIT_TAG           e7aad188c79cd31e940393d2d855bf20b9cb193f # v2022.06.13.00
    DEPENDS           boost glog libevent libtool lzma lz4 snappy xz zlib openssl
    # FIND_PACKAGE_ARGS NAMES folly
)

# catch2
FetchContent_Declare(
    catch2
    GIT_REPOSITORY    https://github.com/catchorg/Catch2.git
    GIT_TAG           605a34765aa5d5ecbf476b4598a862ada971b0cc # v3.0.1
    # FIND_PACKAGE_ARGS 
)
FetchContent_GetProperties(catch2)
if (NOT catch2_POPULATED)
    FetchContent_Populate(catch2)
    list(APPEND CMAKE_MODULE_PATH ${catch2_SOURCE_DIR}/extras)
    add_subdirectory(${catch2_SOURCE_DIR} ${catch2_BINARY_DIR})
endif()


# googletest
FetchContent_Declare(
    googletest
    GIT_REPOSITORY    https://github.com/google/googletest.git
    GIT_TAG           e2239ee6043f73722e7aa812a459f54a28552929 # v1.11.0
    # FIND_PACKAGE_ARGS NAMES gtest
)

# zlib
FetchContent_Declare(
    zlib
    GIT_REPOSITORY    https://github.com/madler/zlib.git
    GIT_TAG           21767c654d31d2dccdde4330529775c6c5fd5389 # v1.2.12 
#    FIND_PACKAGE_ARGS NAMES z
)


# xz utils
FetchContent_Declare(
    xz
    GIT_REPOSITORY    https://github.com/roboticslibrary/xz.git 
    GIT_TAG           3d566cd519017eee1a400e7961ff14058dfaf33c # v5.2.3 
    # FIND_PACKAGE_ARGS NAMES xz
)

# snappy 
FetchContent_Declare(
    snappy
    GIT_REPOSITORY    https://github.com/google/snappy.git
    GIT_TAG           2b63814b15a2aaae54b7943f0cd935892fae628f # v1.1.9 
    # FIND_PACKAGE_ARGS NAMES snappy 
)

# openssl 
FetchContent_Declare(
    openssl
    GIT_REPOSITORY    https://github.com/openssl/openssl.git
    GIT_TAG           4d346a188c27bdf78aa76590c641e1217732ca4b # v3.0.3 
    # FIND_PACKAGE_ARGS NAMES openssl 
)

# lzma 
FetchContent_Declare(
    lzma
    URL               https://tukaani.org/lzma/lzma-4.32.7.tar.gz
    URL_HASH          MD5=2a748b77a2f8c3cbc322dbd0b4c9d06a # v4.32.7
    # FIND_PACKAGE_ARGS NAMES lzma 
)

# lz4 
FetchContent_Declare(
    lz4
    GIT_REPOSITORY    https://github.com/lz4/lz4.git
    GIT_TAG           d44371841a2f1728a3f36839fd4b7e872d0927d3 # v1.9.3
    # FIND_PACKAGE_ARGS NAMES lz4 
)

# libtool 
FetchContent_Declare(
    libtool
    GIT_REPOSITORY    https://github.com/autotools-mirror/libtool.git
    GIT_TAG           6d7ce133ce54898cf28abd89d167cccfbc3c9b2b # v2.4.7
    # FIND_PACKAGE_ARGS NAMES libtool 
)

# libevent 
FetchContent_Declare(
    libevent
    GIT_REPOSITORY    https://github.com/libevent/libevent.git 
    GIT_TAG           5df3037d10556bfcb675bc73e516978b75fc7bc7 # v2.1.12 
    COMMENT           v2.1.12
    DEPENDS           openssl
    # FIND_PACKAGE_ARGS NAMES libevent 
)

# glog 
FetchContent_Declare(
    glog
    GIT_REPOSITORY    https://github.com/google/glog.git
    GIT_TAG           b33e3bad4c46c8a6345525fd822af355e5ef9446 # v0.6.0
    # FIND_PACKAGE_ARGS NAMES libevent 
)

# boost 
FetchContent_Declare(
    boost
    GIT_REPOSITORY    https://github.com/boostorg/boost.git 
    GIT_TAG           5df8086b733798c8e08e316626a16babe11bd0d2 # v1.79.0 
    # FIND_PACKAGE_ARGS NAMES boost 
)

# double-conversion 
FetchContent_Declare(
    double-conversion
    GIT_REPOSITORY    https://github.com/google/double-conversion.git 
    GIT_TAG           9e0c13564e17362aad8a32c1344a2214f71952c6 # v3.2.0
    # FIND_PACKAGE_ARGS NAMES double_conversion 
)

message(STATUS "${CMAKE_CURRENT_SOURCE_DIR}")

FetchContent_MakeAvailable(
    openssl
)

# We declare the details of each package first, and the order is not matter.
#
# Dependency order is from high to low.
FetchContent_MakeAvailable(
    openssl
    xz
    lz4
    lzma
    snappy
    zlib
    libtool
    double-conversion
    libevent
    gflags
    glog
    boost
    folly
)
