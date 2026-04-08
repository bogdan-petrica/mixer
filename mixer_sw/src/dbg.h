/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __DBG_H__
#define __DBG_H__

void dbg_assert(const char* file, int line, const char* cond);

#define DBG_ASSERT_IMPL(cond)                                   \
    do {                                                        \
        if (!(cond)) {                                          \
            dbg_assert(__FILE__, __LINE__, #cond);              \
            while (1);                                          \
        }                                                       \
    } while (0)


#ifdef DBG_ASSERT_CONF
#define DBG_ASSERT(cond)                    DBG_ASSERT_IMPL(cond)
#else
#define DBG_ASSERT(cond)                    (void)(cond)
#endif

#endif // #ifndef __DBG_H__
