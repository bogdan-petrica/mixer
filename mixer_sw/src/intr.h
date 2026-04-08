/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __INTR_H__
#define __INTR_H__

#include <stdint.h>

typedef void (intr_callback_t)(void* data);

int intr_init();
int intr_connect(uint32_t intr_id, uint8_t priority, intr_callback_t callback, void* data);
void intr_disconnect(uint32_t intr_id);
void intr_enable(uint32_t intr_id);
void intr_disable(uint32_t intr_id);

#endif // #ifndef __INTR_H__
