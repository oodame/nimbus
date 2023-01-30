set(NimbusThirdParty 
    Openssl               : 3.0.4;                       
    Lzma                  : 5.2.6;
    Lz4                   : 1.9.4;
    Snappy                : 1.1.9;
    Zlib                  : 1.2.12;
    Souble-conversion     : 3.2.1;
    Libevent              : 2.1.12;
    Gflags                : 2.2.2;
    Glog                  : 0.6.0;
    Boost                 : 1.80.0;
    Googletest            : 1.12.1;
    Libsodium             : 1.0.18;
    Folly                 : 2022.09.05.00;
)

foreach(pair IN LISTS NimbusThirdParty)
    string(FIND "${pair}" ":" pos)
    if(pos GREATER 1)
        string(SUBSTRING "${pair}" 0 "$pos" pkgName)
        match(EXPR pos "${pos} + 1")
        string(SUBSTRING "${pair}" "${pos}" -1 pkgVersion)

        message(STATUS "Tring to find package <${pkgName}> with version `${pkgVersion}`")
        find_package(pkgName pkgVersion REQUIRED)
    endif()
endforeach()
