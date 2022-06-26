/**
 * Copyright (c) 2022-2022, all rights reserved by the BlazingNimbus Group.
 *
 * Create on 26/06/2022
 * Author:
 *        Yaochi oodame@outlook.com
 */

#ifndef COMMON_MEMORY_BUFFERPTR_H_
#define COMMON_MEMORY_BUFFERPTR_H_

#include "common/Base.h"

namespace nimbus {
namespace common {

/**
 * A BufferPtr holds and owns a raw bytes buffer.
 */
class BufferPtr {
public:
    T* as()

private:
    char*  buf_;
    size_t size_;
};    

}  // namespace common
}  // namespace nimbus

#endif  // COMMON_MEMORY_BUFFERPTR_H_
