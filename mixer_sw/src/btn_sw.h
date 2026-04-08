/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __BTN_SW_H__
#define __BTN_SW_H__

int btn_sw_init();
void btn_sw_read(int* btn_out, int* sw_out);

#endif // #ifndef __BTN_SW_H__
