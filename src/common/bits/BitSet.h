/**
 * Copyright (c) 2022-present, all rights reserved by the BlazingNimbus Group.
 * 
 * Create on Aug 07, 2022
 * Author:
 *        Yaochi <oodame@outlook.com>
 */

#ifndef COMMON_BITS_BITSET_H_
#define COMMON_BITS_BITSET_H_

#include <cstdlib>
#include <cassert>

namespace nimbus {
namespace common {

/**
 * @brief A BitSet is a set whose value is either 0 or 1. 
 *
 * The bit count of this BitSet is not compile time determined,
 * so this differs from the std::bitset a lot.
 */
class BitSet {
public:
    BitSet(char* data, size_t size) : data_(data), size_(size) {}
    ~BitSet() = default;

    void set(size_t n) { 
        assert(n < size());
        data_[bitOffset(n)] |= bitMask(n);
    }

    bool test(size_t n) const {
        assert(n < size());
        return data_[bitOffset(n)] & bitMask(n);
    }

    bool operator[](size_t n) const { return test(n); }

    size_t count() const {
        return 0;    
    }

    size_t size() const { return size_ << 3; }

private:
    constexpr size_t bitMask(size_t n) const { return 1 << (n % 8); }
    constexpr size_t bitOffset(size_t n) const { return n / 8; }

    char*       data_;
    size_t      size_;
};  // class BitSet

}  // namespace common
}  // namespace nimbus

#endif  // COMMON_BITS_BITSET_H_
