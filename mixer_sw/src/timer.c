/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "timer.h"
#include "intr.h"
#include "log.h"

#include <math.h>

#include <xscutimer.h>

#include "xparameters.h"

#define TIMER_IRQ_PRIORITY              0x0

// the timer counter is decremented every two CPU cycles
//
// CPU runs at ~667MHZ this gives 333500000 / sec, or 33350 / 100nsec ( microseconds )
#define TIMER_LOAD_VALUE                33350

// for conversion to seconds
#define TIMER_FREQ                      (((float)XPAR_CPU_CORE_CLOCK_FREQ_HZ / 2) / TIMER_LOAD_VALUE)

static XScuTimer timer;
static volatile uint32_t tick_count = 0;

void timer_callback(void* data)
{
    (void)data;
    ++tick_count;
}

int timer_init()
{
    int rc;
    XScuTimer_Config* timer_cfg;

    timer_cfg = XScuTimer_LookupConfig(XPAR_SCUTIMER_BASEADDR);
    rc = XScuTimer_CfgInitialize(&timer,
        timer_cfg,
        timer_cfg->BaseAddr);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = intr_connect(timer_cfg->IntrId, 0, &timer_callback, 0);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    intr_enable(timer_cfg->IntrId);

    // set auto reload, enable the interrupt and start the timer
    XScuTimer_EnableAutoReload(&timer);
    XScuTimer_LoadTimer(&timer, TIMER_LOAD_VALUE);
    XScuTimer_EnableInterrupt(&timer);
    XScuTimer_Start(&timer);

    // LOG module uses timer to extract seconds, the timer is not running at this point
    // so it will use the initial seconds value of the timer
    //
    // this circular definition is acceptable
    LOG("TIMER", LOG_LEVEL_INFO, "timer freq is %8.3f HZ, period: %8.3f ms",
        TIMER_FREQ, 1000.f / TIMER_FREQ);

    return XST_SUCCESS;
err:
    return rc;
}

uint32_t timer_ticks()
{
    return tick_count;
}

float timer_sec()
{
    return timer_ticks2sec(timer_ticks());
}

float timer_ticks2sec(uint32_t ticks)
{
    return ticks * (1.f / TIMER_FREQ);
}

uint32_t timer_sec2ticks(float sec)
{
    return (uint32_t)(roundf(sec * TIMER_FREQ));
}

void timer_sleep(float timeout_sec)
{
    const uint32_t timeout_ticks = timer_sec2ticks(timeout_sec);
    const uint32_t start_ticks = timer_ticks();
    while (timer_ticks() - start_ticks < timeout_ticks) {
        ;
    }
}
