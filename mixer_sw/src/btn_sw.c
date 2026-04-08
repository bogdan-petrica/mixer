/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "btn_sw.h"
#include "timer.h"
#include "log.h"
#include "dbg.h"

#include <xgpio.h>
#include <xstatus.h>

#include "xparameters.h"

#define BTN_SW_DEBOUNCE_TIMEOUT_SEC              0.1f

static XGpio xgpio;
static int all_inputs_in;
static int all_inputs;
static int debounce_active;
static uint32_t debounce_start_ticks;

int btn_sw_init()
{
    int rc;
    XGpio_Config* xgpio_cfg;

    xgpio_cfg = XGpio_LookupConfig(XPAR_XGPIO_0_BASEADDR);
    rc = XGpio_CfgInitialize(&xgpio,
        xgpio_cfg,
        xgpio_cfg->BaseAddress);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    if (!xgpio.IsDual) {
        rc = XST_NOT_ENABLED;
        goto err;
    }

    // set direction for channel 1(btn) to in
    XGpio_SetDataDirection(&xgpio, 1, 0xf);

    // set direction for channel 2(sw) to in
    XGpio_SetDataDirection(&xgpio, 2, 0xf);

    return XST_SUCCESS;
err:
    return rc;
}

void btn_sw_read(int* btn_out, int* sw_out)
{
    DBG_ASSERT(btn_out != 0);
    DBG_ASSERT(sw_out != 0);

    const int btn_in = XGpio_DiscreteRead(&xgpio, 1) & 0xf;
    const int sw_in = XGpio_DiscreteRead(&xgpio, 2) & 0xf;
    
    const int current_inputs = (btn_in << 4) | sw_in;

    if (all_inputs_in != current_inputs) {
        debounce_active = 1;
        debounce_start_ticks = timer_ticks();
    }

    all_inputs_in = current_inputs;

    if (debounce_active) {
        const uint32_t timeout = timer_sec2ticks(BTN_SW_DEBOUNCE_TIMEOUT_SEC);
        if (timer_ticks() - debounce_start_ticks > timeout) {
            all_inputs = all_inputs_in;
            debounce_active = 0;
        }
    }

    if (btn_out) {
        *btn_out = (all_inputs >> 4) & 0xf;
    }

    if (sw_out) {
        *sw_out = all_inputs & 0xf;
    }
}
