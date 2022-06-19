#------------------------------------------------------------
# A collection of versions that third-party used in Nimbus
#------------------------------------------------------------
#set(GCC_VERSION           "releases/gcc-10.3.0"        PARENT_SCOPE)
#set(FOLLY_VERSION         "v2022.06.13.00"             PARENT_SCOPE)
#set(CATCH2_VERSION        "v3.0.1"                     PARENT_SCOPE)
#set(GOOGLETEST_VERSION    "release-1.11.0"             PARENT_SCOPE)
#set(ZLIB_VERSION          "v1.2.12"                    PARENT_SCOPE)
#set(XZ_VERSION            "v5.2.3"                     PARENT_SCOPE)
#set(LZMA_VERSION          "4.32.7"                     PARENT_SCOPE)
#set(LZ4_VERSION           "v1.9.3"                     PARENT_SCOPE)
#set(SNAPPY_VERSION        "1.1.9"                      PARENT_SCOPE)
#set(OPENSSL_VERSION       "openssl-3.0.3"              PARENT_SCOPE)
#set(OPENSSL_VERSION       "v2.4.7"                     PARENT_SCOPE)
#set(LIBEVENT_VERSION      "release-2.1.12-stable"      PARENT_SCOPE)
#set(GLOG_VERSION          "v0.6.0"                     PARENT_SCOPE)
#set(BOOST_VERSION         "boost-1.79.0"               PARENT_SCOPE)


#------------------------------------------------------------
# Dependency Tree
#------------------------------------------------------------
#
#  folly -----------> zlib
#    |
#    +--------------> xz
#    |
#    +--------------> snappy
#    |
#    +--------------> openssl
#    |
#    +--------------> lzma
#    |
#    +--------------> lz4
#    |
#    +--------------> libtool
#    |
#    +--------------> double-conversion
#    |
#    +--------------> gflag
#    |
#    +--------------> libevent
#    |
#    +--------------> glog
#    |
#    +--------------> boost
#
