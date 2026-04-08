/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __LOG_H__
#define __LOG_H__

#include "timer.h"

#define LOG_LEVEL_DEBUG             0x1
#define LOG_LEVEL_INFO              0x2
#define LOG_LEVEL_ERROR             0x4

#define LOG_LEVEL_MASK              (LOG_LEVEL_DEBUG | LOG_LEVEL_INFO | LOG_LEVEL_ERROR)

#if defined(DEBUG) && !defined(NDEBUG)
#define LOG_CONFIG                  (LOG_LEVEL_DEBUG | LOG_LEVEL_INFO | LOG_LEVEL_ERROR)
#else
#define LOG_CONFIG                  (LOG_LEVEL_INFO | LOG_LEVEL_ERROR)
#endif

void log_print(const char* fmt, ...);

static
inline const char* log_get_level_str(int level)
{
    switch(level)
    {
    case LOG_LEVEL_DEBUG:
        return "DBG";

    case LOG_LEVEL_INFO:
        return "INF";

    case LOG_LEVEL_ERROR:
        return "ERR";
    }

    return "UNK";
}

#define LOG(name, level, fmt, ...)                                                                                              \
    do {                                                                                                                        \
        if (level & LOG_CONFIG) {                                                                                               \
            log_print("[% 8.3f][% 6s][%3s]" fmt "\r\n", timer_sec(),                                                            \
                name, log_get_level_str(level & LOG_LEVEL_MASK) , ## __VA_ARGS__ );                                             \
        }                                                                                                                       \
    } while(0)

#endif // #ifndef __LOG_H__
