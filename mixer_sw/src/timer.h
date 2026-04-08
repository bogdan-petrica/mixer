/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __TIMER_H__
#define __TIMER_H__

#include <stdint.h>

int timer_init();
uint32_t timer_ticks();
float timer_sec();
float timer_ticks2sec(uint32_t ticks);
uint32_t timer_sec2ticks(float sec);
void timer_sleep(float timeout_sec);

#endif // #ifndef __TIMER_H__
