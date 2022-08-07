/**
 * Copyright (c) 2022-present, all rights reserved by the BlazingNimbus Group.
 * 
 * Create on Aug 07, 2022
 * Author:
 *        Yaochi <oodame@outlook.com>
 */

#ifndef COMMON_BITS_CONSTBITSET_H_
#define COMMON_BITS_CONSTBITSET_H_

#include <cstdlib>
#include <cassert>

namespace nimbus {
namespace common {

/**
 * @brief A ConstBitSet is a set whose value is either 0 or 1. 
 *
 * Note that this set is only a view on a block of buffer,
 * hence, no modification is allowed.
 */
class ConstBitSet {
public:
    ConstBitSet(const char* data, size_t size) : data_(data), size_(size) {}
    ~ConstBitSet() = default;

    bool test(size_t n) const {
        assert(n < size());
        return data_[bitOffset(n)] & bitMask(n);
    }

    bool operator[](size_t n) const { return test(n); }

    size_t size() const { return size_ << 3; }

private:
    constexpr size_t bitMask(size_t n) const { return 1 << (n % 8); }
    constexpr size_t bitOffset(size_t n) const { return n / 8; }

    const char* data_;
    size_t      size_;
};  // class ConstBitSet

}  // namespace common
}  // namespace nimbus

#endif  // COMMON_BITS_CONSTBITSET_H_
