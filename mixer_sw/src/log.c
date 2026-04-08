/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "log.h"

#include <stdio.h>
#include <stdarg.h>

void log_print(const char* fmt, ...)
{
    va_list va;

    va_start(va, fmt);
    vprintf(fmt, va);
    va_end(va);
}
