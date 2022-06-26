/**
 * Copyright (c) 2022-2022, all rights reserved by the BlazingNimbus Group.
 *
 * Create on 26/06/2022
 * Author:
 *        Yaochi oodame@outlook.com
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
    DataSection(const char* compressed, size_t size) {}

private:
};    

}  // namespace occamy
}  // namespace nimbus

#endif  // OCCAMY_SFILE_DATASECTION_H_
