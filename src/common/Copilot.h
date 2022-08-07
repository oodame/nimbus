/**
 * Copyright (c) 2022-present, all rights reserved by the BlazingNimbus Group.
 *
 * Create on 26/06/2022
 * Author:
 *        Yaochi <oodame@outlook.com>
 */

#ifndef COMMON_COPILOT_H_
#define COMMON_COPILOT_H_

namespace nimbus {
    // This file contains many useful macros to help you write codes.

#ifndef DISALLOW_COPY_AND_MOVE_CONSTRUCT
#define DISALLOW_COPY_AND_MOVE_CONSTRUCT(T)  \
    T(const T& t) = delete;                  \
    T(T&& t) = delete;
#endif    

#ifndef DISALLOW_COPY_AND_MOVE_ASSIGNMENT
#define DISALLOW_COPY_AND_MOVE_ASSIGNMENT(T) \
    T& operator=(const T& other) = delete;   \
    T& operator=(T&& other) = delete;
#endif

#ifndef DISALLOW_COPY_CONSTRUCT_AND_ASSIGNMENT
#define DISALLOW_COPY_CONSTRUCT_AND_ASSIGNMENT(T) \
    T(const T& t) = delete;                       \
    T& operator=(const T& other) = delete;
#endif

#ifndef DISALLOW_MOVE_CONSTRUCT_AND_ASSIGNMENT
#define DISALLOW_MOVE_CONSTRUCT_AND_ASSIGNMENT(T) \
    T(T&& t) = delete;                            \
    T& operator=(T&& other) = delete; 
#endif

}  // namespace nimbus

#endif  // COMMON_COPILOT_H_
