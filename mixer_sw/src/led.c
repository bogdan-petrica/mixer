/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "led.h"
#include "dbg.h"
#include "log.h"

#include <math.h>

#include <xttcps_hw.h>

#include "xparameters.h"

#define LED_DBG(...)                LOG("LED", LOG_LEVEL_DEBUG , ## __VA_ARGS__)
#define LED_INF(...)                LOG("LED", LOG_LEVEL_INFO , ## __VA_ARGS__)
#define LED_ERR(...)                LOG("LED", LOG_LEVEL_ERROR , ## __VA_ARGS__)

#define TTC_COUNTER_NUM             3
#define TTC_MIN_FREQ                10000
#define TTC_COUNTER_MAX             (1 << 16)

#define TTC0_FREQ                   XPAR_TTC0_CLOCK_FREQ
#define TTC1_FREQ                   XPAR_TTC1_CLOCK_FREQ

#define TTC0_DIVIDER                (TTC0_FREQ / TTC_MIN_FREQ)
#define TTC1_DIVIDER                (TTC1_FREQ / TTC_MIN_FREQ)

_Static_assert(TTC0_DIVIDER <= TTC_COUNTER_MAX);
_Static_assert(TTC1_DIVIDER <= TTC_COUNTER_MAX);

#define LED_GAMMA_FACTOR            3.3f

typedef struct {
    uintptr_t   base_addr;
    uint32_t    interval;
} xttc_t;

static void xttc_set_duty_cycle_int(xttc_t* xttc, unsigned int idx, uint32_t duty_cycle)
{
    DBG_ASSERT(xttc != 0);
    DBG_ASSERT(idx < TTC_COUNTER_NUM);
    DBG_ASSERT(duty_cycle <= xttc->interval);

    // set match value
    XTtcPs_WriteReg(xttc->base_addr, XTTCPS_MATCH_0_OFFSET + sizeof(uint32_t) * idx, duty_cycle);
}

static void xttc_set_duty_cycle(xttc_t* xttc, unsigned int idx, float duty_cycle)
{
    DBG_ASSERT(xttc != 0);
    DBG_ASSERT(duty_cycle >= 0.0f && duty_cycle <= 1.0f);

    xttc_set_duty_cycle_int(xttc, idx, (uint32_t)(duty_cycle * xttc->interval));
}

static void xttc_init(xttc_t* xttc, uintptr_t base_addr, uint32_t divider)
{
    DBG_ASSERT(xttc != 0);
    DBG_ASSERT(base_addr != 0);
    DBG_ASSERT(divider <= TTC_COUNTER_MAX);

    xttc->base_addr = base_addr;
    xttc->interval = divider;

    // determine clk control register
    uint32_t clk_ctrl = 0;

    // determine counter ctrl register
    uint32_t cnt_ctrl = 0;

    cnt_ctrl |= XTTCPS_CNT_CNTRL_DIS_MASK;
    cnt_ctrl |= XTTCPS_CNT_CNTRL_INT_MASK;
    cnt_ctrl |= XTTCPS_CNT_CNTRL_MATCH_MASK;
    cnt_ctrl &= ~XTTCPS_CNT_CNTRL_EN_WAVE_MASK;
    cnt_ctrl |= XTTCPS_CNT_CNTRL_POL_WAVE_MASK;

    const uint32_t cnt_ctrl_start = cnt_ctrl & ~XTTCPS_CNT_CNTRL_DIS_MASK;

    for(int i = 0; i < TTC_COUNTER_NUM; ++i) {
        // set clk control register
        XTtcPs_WriteReg(base_addr, XTTCPS_CLK_CNTRL_OFFSET + sizeof(uint32_t) * i, clk_ctrl);

        // set cnt control register
        XTtcPs_WriteReg(base_addr, XTTCPS_CNT_CNTRL_OFFSET + sizeof(uint32_t) * i, cnt_ctrl);

        // set interval count value
        XTtcPs_WriteReg(base_addr, XTTCPS_INTERVAL_VAL_OFFSET + sizeof(uint32_t) * i, xttc->interval);

        // set duty cycles to 0
        xttc_set_duty_cycle_int(xttc, i, 0);

        // finally start the timer
        XTtcPs_WriteReg(base_addr, XTTCPS_CNT_CNTRL_OFFSET + sizeof(uint32_t) * i, cnt_ctrl_start);
    }
}

static xttc_t xttc0;
static xttc_t xttc1;

int led_init()
{
    const float ttc0_actual_freq = (float)TTC0_FREQ / TTC0_DIVIDER;
    const float ttc1_actual_freq = (float)TTC1_FREQ / TTC1_DIVIDER;

    LED_INF("TTC0 min frequency: %12.4f HZ, actual frequency: %12.4f HZ", (float)TTC_MIN_FREQ, ttc0_actual_freq);
    LED_INF("TTC1 min frequency: %12.4f HZ, actual frequency: %12.4f HZ", (float)TTC_MIN_FREQ, ttc1_actual_freq);

    xttc_init(&xttc0, XPAR_TTC0_BASEADDR, ttc0_actual_freq);
    xttc_init(&xttc1, XPAR_TTC1_BASEADDR, ttc1_actual_freq);
    return XST_SUCCESS;
}

void led_set(unsigned int idx, float brightness)
{
    DBG_ASSERT(idx < LED_COUNT);
    DBG_ASSERT(brightness >= 0.0f && brightness <= 1.0f);

    xttc_t* const dev = idx < TTC_COUNTER_NUM ? &xttc0 : &xttc1;
    const unsigned int dev_idx = idx % TTC_COUNTER_NUM;

    const float duty_cycle = expf(LED_GAMMA_FACTOR * logf(brightness));

    xttc_set_duty_cycle(dev, dev_idx, duty_cycle);
}
