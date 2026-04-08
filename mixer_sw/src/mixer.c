/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "mixer.h"
#include "intr.h"
#include "log.h"
#include "dbg.h"

#include <math.h>
#include <xaxidma.h>
#include <xstatus.h>

#include "xparameters.h"

#define MIXER_DBG(...)                          LOG("MIXER", LOG_LEVEL_DEBUG , ## __VA_ARGS__)
#define MIXER_INF(...)                          LOG("MIXER", LOG_LEVEL_INFO , ## __VA_ARGS__)
#define MIXER_ERR(...)                          LOG("MIXER", LOG_LEVEL_ERROR , ## __VA_ARGS__)

#define MIXER_REC_CONFIG_REG                    0x00
#define MIXER_REC_STATUS_REG                    0x04
#define MIXER_REC_SIZE_REG                      0x08
#define MIXER_PB_DELAY_MUX_SEL_REG              0x0C
#define MIXER_PB_RAMP_GAIN_SEL_REG              0x10
#define MIXER_PB_PS_GAIN_SEL_REG                0x14
#define MIXER_PB_MIC_GAIN_SEL_REG               0x18
#define MIXER_PB_DELAY_GAIN_SEL_REG             0x1C
#define MIXER_PB_DELAY_REG                      0x20

#define MIXER_REC_CONFIG_ACT                    (1 << 0)
#define MIXER_REC_CONFIG_EN                     (1 << 1)

#define MIXER_REC_STATUS_DONE                   (1 << 0)
#define MIXER_REC_STATUS_ACT_ERR                (1 << 1)
#define MIXER_REC_STATUS_EN                     (1 << 2)

#define MIXER_PB_DELAY_MUX_RAMP                 0x0
#define MIXER_PB_DELAY_MUX_PS                   0x1
#define MIXER_PB_DELAY_MUX_MIC                  0x2
#define MIXER_PB_DELAY_MUX_CORE                 0x3

#define MIXER_BASE_ADDR                         XPAR_MIXER_TOP_0_BASEADDR

#define MIXER_DMA_INTR_MM2S                     XPAR_AXI_DMA_0_INTERRUPTS
#define MIXER_DMA_INTR_S2MM                     XPAR_AXI_DMA_0_INTERRUPTS_1
#define MIXER_DMA_IRQ_PRIO                      0x8

#define MIXER_DMA_TX_ALIGN                      (XPAR_AXI_DMA_0_MM2S_DATA_WIDTH / 8)
#define MIXER_DMA_RX_ALIGN                      (XPAR_AXI_DMA_0_S2MM_DATA_WIDTH / 8)

_Static_assert((MIXER_DMA_ALIGN & (MIXER_DMA_TX_ALIGN - 1)) == 0);
_Static_assert((MIXER_DMA_ALIGN & (MIXER_DMA_RX_ALIGN - 1)) == 0);

static XAxiDma xaxidma;
static volatile mixer_dma_state_e dma_rx_state = MixerDmaStateIdle;
static uint8_t* dma_rx_data;
static size_t dma_rx_len;
static volatile mixer_dma_state_e dma_tx_state = MixerDmaStateIdle;

static uint16_t mixer_read_reg(uint16_t offset)
{
    return (uint16_t)Xil_In32((uintptr_t)((uint8_t*)MIXER_BASE_ADDR + offset));
}

static void mixer_write_reg(uint16_t offset, uint16_t value)
{
    Xil_Out32((uintptr_t)((uint8_t*)MIXER_BASE_ADDR + offset), (uint32_t)value);
}

static void mixer_dma_cb(int direction, volatile mixer_dma_state_e* dma_state)
{
    const uint32_t intr = XAxiDma_IntrGetIrq(&xaxidma, direction);

     if (*dma_state == MixerDmaStateActive) {
        if (intr & XAXIDMA_IRQ_ERROR_MASK) {
            *dma_state = MixerDmaStateError;
        } else if (intr & XAXIDMA_IRQ_IOC_MASK) {
            *dma_state = MixerDmaStateDone;
        }
    }

    // safe to ack as long as we are not reentrant
    // when reentrant this sequence breaks as the caller can
    // see MixerDmaStateError/MixerDmaStateDone and proceed with another
    // call before acknowledging the interrupt
    XAxiDma_IntrAckIrq(&xaxidma, intr, direction);
}

static void mixer_dma_tx_cb(void* data)
{
    (void)data;
    mixer_dma_cb(XAXIDMA_DMA_TO_DEVICE, &dma_tx_state);
}

static void mixer_dma_rx_cb(void* data)
{
    (void)data;
    mixer_dma_cb(XAXIDMA_DEVICE_TO_DMA, &dma_rx_state);
}

static int mixer_dma_init()
{
    int rc;
    XAxiDma_Config* xaxidma_cfg;
    
    xaxidma_cfg = XAxiDma_LookupConfig(XPAR_AXI_DMA_0_BASEADDR);
    rc = XAxiDma_CfgInitialize(&xaxidma, xaxidma_cfg);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // disable DMA interrupts
    XAxiDma_IntrDisable(&xaxidma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&xaxidma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    // connect memory to stream interrupt
    rc = intr_connect(MIXER_DMA_INTR_MM2S,
        MIXER_DMA_IRQ_PRIO,
        &mixer_dma_tx_cb,
        0);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    intr_enable(MIXER_DMA_INTR_MM2S);

    // connect stream to memory interrupt
    rc = intr_connect(MIXER_DMA_INTR_S2MM,
        MIXER_DMA_IRQ_PRIO,
        &mixer_dma_rx_cb,
        0);
    if (rc != XST_SUCCESS)  {
        goto err;
    }

    intr_enable(MIXER_DMA_INTR_S2MM);

    // enable DMA interrupts
    XAxiDma_IntrEnable(&xaxidma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrEnable(&xaxidma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    MIXER_DBG("mixer_dma_init() complete");

    return XST_SUCCESS;
err:
    return rc;    
}

static int mixer_dma_check(uint8_t* data, size_t len)
{
    DBG_ASSERT(data != 0);
    DBG_ASSERT(len > 0);

    if ((uintptr_t)data & (MIXER_DMA_ALIGN - 1)) {
        return XST_INVALID_PARAM;
    }

    if (len & (MIXER_DMA_ALIGN - 1)) {
        return XST_INVALID_PARAM;
    }

    const uintptr_t first_page = (uintptr_t)data & ~(MIXER_DMA_BOUNDRY_SIZE - 1);
    const uintptr_t last_page = (uintptr_t)(data + len) & ~(MIXER_DMA_BOUNDRY_SIZE - 1);

    if (first_page != last_page) {
        if (last_page - first_page > MIXER_DMA_BOUNDRY_SIZE) {
            return XST_INVALID_PARAM;
        }

        const uintptr_t last_page_off = (uintptr_t)(data + len) & (MIXER_DMA_BOUNDRY_SIZE - 1);
        if (last_page_off) {
            return XST_INVALID_PARAM;
        }
    }

    return XST_SUCCESS;
}

static int mixer_dma_tx_init(uint8_t* data, size_t len)
{
    int rc;

    DBG_ASSERT(data != 0);
    DBG_ASSERT(len > 0);
    DBG_ASSERT(mixer_dma_check(data, len) == XST_SUCCESS);

    if (dma_tx_state == MixerDmaStateActive || dma_tx_state == MixerDmaStateError) {
        rc = XST_FAILURE;
        goto err;
    }

    Xil_DCacheFlushRange((uintptr_t)data, len);

    dma_tx_state = MixerDmaStateActive;
    rc = XAxiDma_SimpleTransfer(&xaxidma,
        (uintptr_t)data,
        len,
        XAXIDMA_DMA_TO_DEVICE);
    if (rc != XST_SUCCESS) {
        dma_tx_state = MixerDmaStateError;
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static int mixer_dma_rx_init(uint8_t* data, size_t len)
{
    int rc;

    DBG_ASSERT(data != 0);
    DBG_ASSERT(len > 0);
    DBG_ASSERT(mixer_dma_check(data, len) == XST_SUCCESS);

    if (dma_rx_state == MixerDmaStateActive || dma_rx_state == MixerDmaStateError) {
        rc = XST_FAILURE;
        goto err;
    } else if ((dma_rx_state == MixerDmaStateDone) && (dma_rx_data != 0) && (dma_rx_len > 0)) {
        // this condition means the DMA finished but caller hasn't seen the result
        // doing another rx transaction is unexpected
        rc = XST_FAILURE;
        goto err;
    }

    dma_rx_state = MixerDmaStateActive;
    dma_rx_data = data;
    dma_rx_len = len;
    
    rc = XAxiDma_SimpleTransfer(&xaxidma,
        (uintptr_t)data,
        len,
        XAXIDMA_DEVICE_TO_DMA);
    if (rc != XST_SUCCESS) {
        dma_rx_state = MixerDmaStateError;
        return rc;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static void mixer_dump_reg(const char* name, uint16_t offset, int level)
{
    const uint16_t value = mixer_read_reg(offset);
    LOG("MIXER", level, "register %s @ 0x%04x = 0x%04x", name, offset, value);
}

static int mixer_dump_gain(const char* name, mixer_channel_e channel, int level)
{
    int rc;
    float db;

    rc = mixer_pb_get_gain(channel, &db);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    LOG("MIXER", level, "channel %s(%d) db = %5.2f", name, channel, db);

    return XST_SUCCESS;
err:
    return rc;
}

static uint16_t mixer_gain_reg_for_channel(mixer_channel_e channel)
{
    switch(channel)
    {
    case MixerChannelRamp:
        return MIXER_PB_RAMP_GAIN_SEL_REG;
    case MixerChannelPS:
        return MIXER_PB_PS_GAIN_SEL_REG;
    case MixerChannelMic:
        return MIXER_PB_MIC_GAIN_SEL_REG;
    case MixerChannelDelay:
        return MIXER_PB_DELAY_GAIN_SEL_REG;
    default:
        DBG_ASSERT(0);
    }

    DBG_ASSERT(0);
    return MIXER_PB_RAMP_GAIN_SEL_REG;
}

int mixer_init()
{
    int rc;
    
    rc = mixer_dma_init();
    if (rc != XST_SUCCESS) {
        goto err;
    }

    mixer_dump_reg("REC_CONFIG", MIXER_REC_CONFIG_REG, LOG_LEVEL_DEBUG);
    mixer_dump_reg("REC_STATUS", MIXER_REC_STATUS_REG, LOG_LEVEL_DEBUG);
    mixer_dump_reg("REC_SIZE", MIXER_REC_SIZE_REG, LOG_LEVEL_DEBUG);

    rc = mixer_dump_gain("RAMP", MixerChannelRamp, LOG_LEVEL_DEBUG);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = mixer_dump_gain("PS", MixerChannelPS, LOG_LEVEL_DEBUG);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = mixer_dump_gain("MIC", MixerChannelMic, LOG_LEVEL_DEBUG);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = mixer_dump_gain("DELAY", MixerChannelDelay, LOG_LEVEL_DEBUG);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    MIXER_DBG("PB_DELAY = %d", mixer_pb_get_delay());

    MIXER_INF("mixer_init() complete");
    
    return XST_SUCCESS;
err:
    return rc;
}

int mixer_dma_tx(uint8_t* data, size_t len)
{
    return mixer_dma_tx_init(data, len);
}

mixer_dma_state_e mixer_dma_get_tx_state()
{
    return dma_tx_state;
}

int mixer_dma_rx_enable(uint16_t rec_size)
{
    int rc;
    uint16_t rec_config;

    DBG_ASSERT(rec_size * sizeof(uint32_t) <= MIXER_DMA_BOUNDRY_SIZE);

    rec_config = mixer_read_reg(MIXER_REC_CONFIG_REG);
    if (rec_config & MIXER_REC_CONFIG_EN) {
        MIXER_ERR("mixer_dma_rx_enable(), rec_en=1 already");
        rc = XST_FAILURE;
        goto err;
    }

    mixer_write_reg(MIXER_REC_SIZE_REG, rec_size);

    mixer_write_reg(MIXER_REC_CONFIG_REG, MIXER_REC_CONFIG_EN);

    MIXER_DBG("dma rx enable, rec_size: %d", rec_size);

    return XST_SUCCESS;
err:
    return rc;
}

int mixer_dma_rx_disable()
{
    int rc;
    uint16_t rec_config;

    rec_config = mixer_read_reg(MIXER_REC_CONFIG_REG);
    if (!(rec_config & MIXER_REC_CONFIG_EN)) {
        MIXER_ERR("mixer_dma_rx_disable(), rec_en=0 already");
        rc = XST_FAILURE;
        goto err;
    }

    mixer_write_reg(MIXER_REC_CONFIG_REG, MIXER_REC_CONFIG_EN);

    MIXER_DBG("dma rx disable");

    return XST_SUCCESS;
err:
    return rc;    
}

int mixer_dma_rx(uint8_t* data, size_t len)
{
    int rc;
    uint16_t rec_config;
    uint16_t rec_size;

    // check rec_en toggled
    rec_config = mixer_read_reg(MIXER_REC_CONFIG_REG);
    if (!(rec_config & MIXER_REC_CONFIG_EN)) {
        MIXER_ERR("mixer_dma_rx, rec_en = 0");
        rc = XST_FAILURE;
        goto err;
    }

    // check that rec_act is not toggled
    if (rec_config & MIXER_REC_CONFIG_ACT) {
        MIXER_ERR("mixer_dma_rx, rec_act = 1");
        rc = XST_FAILURE;
        goto err;
    }

    // check the len vs rec_size
    rec_size = mixer_read_reg(MIXER_REC_SIZE_REG);
    if (rec_size * MIXER_SAMPLE_SIZE != len) {
        MIXER_ERR("mixer_dma_rx, rec_size = %d, len = %d", rec_size, len);
        rc = XST_INVALID_PARAM;
        goto err;
    }

    // start the DMA engine
    rc = mixer_dma_rx_init(data, len);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // activate transmission, toggle rec_act
    //
    // note on error recovery past XAXI DMA transfer init success:
    //  - option 1 - cancel the current transfer by setting DEVICE TO DMA CR register RUN STOP bit to 0
    //               and wait for DEVICE TO DMA SR register HALTED to become 1
    //
    //               this option needs direct register access as the XAXI DMA driver does not expose this
    //               functionallity
    //
    //  - option 2 - bubble up the error to the higher level, wait for the DMA TO DEVICE transfer to
    //               finish and reset the XAXI DMA engine
    //
    //               this is less than desirable as it has architectural impact for error detection
    //
    // currently the sequence does not have a failure point past mixer_dma_rx_init
    mixer_write_reg(MIXER_REC_CONFIG_REG, MIXER_REC_CONFIG_ACT);

    return XST_SUCCESS;
err:
    return rc;
}

mixer_dma_state_e mixer_dma_get_rx_state()
{
    uint16_t rec_status;

    // cache the dma_rx_state to avoid potential race condition
    // where this sees MixerDmaStateActive and the caller sees MixerDmaStateDone
    // without having the cache invalidated
    const mixer_dma_state_e rx_state = dma_rx_state;

    if (rx_state == MixerDmaStateDone) {
        if (dma_rx_data && dma_rx_len) {
            rec_status = mixer_read_reg(MIXER_REC_STATUS_REG);
            // check that rec_done is properly set every time on interrupt raise
        if (!(rec_status & MIXER_REC_STATUS_DONE)) {
                MIXER_ERR("mixer_dma_get_rx_state(), rec_done!=1 on interrupt completion");
                dma_rx_state = MixerDmaStateError;
                goto err;
            } else {
                Xil_DCacheInvalidateRange((uintptr_t)dma_rx_data, dma_rx_len);
                dma_rx_data = 0;
                dma_rx_len = 0;
            }
        }
    }

    return rx_state;
err:
    return MixerDmaStateError;
}

int mixer_pb_get_gain(mixer_channel_e channel, float* db)
{
    int rc;

    DBG_ASSERT(db != NULL);
    const uint16_t gain_reg = mixer_gain_reg_for_channel(channel);
    
    const uint16_t gain_sel = mixer_read_reg(gain_reg);

    if (gain_sel > MIXER_GAIN_MAX) {
        rc = XST_FAILURE;
        goto err;
    }

    *db = MIXER_GAIN_MAX_DB - (MIXER_GAIN_MAX - gain_sel) * MIXER_GAIN_STEP_DB;

    MIXER_DBG("mixer_pb_gain_read(), reg: %04x, sel: %04x, channel: %d, db: % 6.2f",
        gain_reg, gain_sel, channel, *db);

    return XST_SUCCESS;
err:
    return rc;
}

int mixer_pb_set_gain(mixer_channel_e channel, float db)
{
    int rc;

    DBG_ASSERT(db <= MIXER_GAIN_MAX_DB);
    DBG_ASSERT(fmod(db, MIXER_GAIN_STEP_DB) == 0.f);

    const uint16_t gain_reg = mixer_gain_reg_for_channel(channel);

    float gain_sel_delta = (MIXER_GAIN_MAX_DB - db) / MIXER_GAIN_STEP_DB;
    if (gain_sel_delta > MIXER_GAIN_MAX) {
        gain_sel_delta = MIXER_GAIN_MAX;
    }

    const uint16_t gain_sel = MIXER_GAIN_MAX - (uint16_t)gain_sel_delta;

    MIXER_DBG("mixer_pb_set_gain(), channel: %d, db: % 6.2f, reg: %04x, gain sel: %04x",
        channel, db, gain_reg, gain_sel);
    mixer_write_reg(gain_reg, gain_sel);

    const uint16_t gain_sel2 = mixer_read_reg(gain_reg);
    if (gain_sel != gain_sel2) {
        MIXER_ERR("mixer_pb_set_gain(), failure, requested gain sel: %d, gain sel: %d",
            gain_sel, gain_sel2);
        rc = XST_FAILURE;
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

int mixer_pb_get_delay_mux_sel(mixer_channel_e* out_channel)
{
    DBG_ASSERT(out_channel != 0);

    const uint16_t sel = mixer_read_reg(MIXER_PB_DELAY_MUX_SEL_REG);
    switch (sel) {
    case MIXER_PB_DELAY_MUX_RAMP:
        *out_channel = MixerChannelRamp;
        break;
    case MIXER_PB_DELAY_MUX_PS:
        *out_channel = MixerChannelPS;
        break;
    case MIXER_PB_DELAY_MUX_MIC:
        *out_channel = MixerChannelMic;
        break;
    case MIXER_PB_DELAY_MUX_CORE:
        *out_channel = MixerChannelCore;
        break;
    default:
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

int mixer_pb_set_delay_mux_sel(mixer_channel_e channel)
{
    int rc;
    uint16_t delay_mux_sel;

    switch (channel) {
    case MixerChannelRamp:
        delay_mux_sel = MIXER_PB_DELAY_MUX_RAMP;
        break;
    case MixerChannelPS:
        delay_mux_sel = MIXER_PB_DELAY_MUX_PS;
        break;
    case MixerChannelMic:
        delay_mux_sel = MIXER_PB_DELAY_MUX_MIC;
        break;
    case MixerChannelCore:
        delay_mux_sel = MIXER_PB_DELAY_MUX_CORE;
        break;
    default:
        delay_mux_sel = MIXER_PB_DELAY_MUX_RAMP;
        DBG_ASSERT(0);
    }
    
    mixer_write_reg(MIXER_PB_DELAY_MUX_SEL_REG, delay_mux_sel);

    MIXER_DBG("mixer_pb_set_delay_mux_sel(), channel: %d", channel);

    mixer_channel_e channel2;
    rc = mixer_pb_get_delay_mux_sel(&channel2);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    if (channel != channel2) {
        MIXER_ERR("mixer_pb_set_delay_mux_sel(), requested channel: %d, channel: %d",
            channel, channel2);
        rc = XST_FAILURE;
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

uint16_t mixer_pb_get_delay()
{
    return mixer_read_reg(MIXER_PB_DELAY_REG);
}

void mixer_pb_set_delay(uint16_t delay)
{
    MIXER_DBG("set playback delay, delay: %d", delay);

    mixer_write_reg(MIXER_PB_DELAY_REG, delay & (MIXER_PB_DELAY_SIZE_MAX - 1));
}
