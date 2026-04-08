/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __LED_H__
#define __LED_H__

#define LED_COUNT       6

int led_init();
void led_set(unsigned int idx, float brightness);

#endif // #ifndef __LED_H__
