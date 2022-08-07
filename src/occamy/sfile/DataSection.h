/**
 * Copyright (c) 2022-present, all rights reserved by the BlazingNimbus Group.
 *
 * Create on 26/06/2022
 * Author:
 *        Yaochi <oodame@outlook.com>
 */

#ifndef OCCAMY_SFILE_DATASECTION_H_
#define OCCAMY_SFILE_DATASECTION_H_

#include <cstdlib>

namespace nimbus {
namespace occamy {

/**
 * A DataDection stands for an in-memory representation of a column data 
 * of an EdgeGroup.
 * 
 * The memory layout of a section should be
 * <Null bitmap><Value array><Footer(8 bytes)>
 */
class DataSection {
public:
    DataSection(const char* data, size_t size) 
        : data_(data), size_(size), footer_(0) { 
        memcpy(&footer_, data + size - sizeof(size_t), sizeof(size_t)); 
    }

    // 00: all 0, which means all values are NOT null;
    // 01: all 1, which means all values are null;
    // 10/11: some are null while some are not;
    // for the first two cases, we do NOT store the null bitmap 
    // for space efficiency.
    bool hasNullMap() const { return footer_ & 0x10 == 0x10; }



private:


    const char* data_;
    size_t      size_;
    size_t      footer_;
};    

}  // namespace occamy
}  // namespace nimbus

#endif  // OCCAMY_SFILE_DATASECTION_H_
