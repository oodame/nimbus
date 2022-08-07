/**
 * Copyright (c) 2022-present, all rights reserved by the BlazingNimbus Group.
 *
 * Create on 26/06/2022
 * Author:
 *        Yaochi <oodame@outlook.com>
 */

#ifndef COMMON_ERRORCODE_H_
#define COMMON_ERRORCODE_H_

#include <cstdlib>

#include <folly/Expected.h>

namespace nimbus {

/**
 * A enum to represents error in Nimbus Graph.
 */
enum class ErrorCode : uint32_t {
    kOk = 0,
};    

template <typename T>
using ErrorOr = folly::Expected<T, ErrorCode>;

//------------------------------------------------------------
// Useful macros to handle error code returns
#ifndef NG_OK
#define NG_OK(x) (((x) == ErrorCode::kOk) [[likely]])
#endif

#ifndef NG_FAIL
#define NG_FAIL(x) (((x) != ErrorCode::kOk) [[unlikely]])
#endif

#ifndef NG_RET_OK
#define NG_RET_OK(x) (NG_OK(ret = (x)))
#endif

#ifndef NG_RET_FAIL
#define NG_RET_FAIL(x) (NG_FAIL(ret = (x)))
#endif

}  // namespace nimbus

#endif  // COMMON_ERRORCODE_H_
