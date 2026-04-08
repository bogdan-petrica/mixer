/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "dbg.h"
#include <stdio.h>

void dbg_assert(const char* file, int line, const char* cond)
{
    printf("assert failed, condition: %s, %s:%d\r\n", cond, file, line);
}
