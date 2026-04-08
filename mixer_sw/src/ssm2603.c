/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "ssm2603.h"
#include "i2c.h"
#include "timer.h"
#include "log.h"
#include "dbg.h"

#include <math.h>

#include <xstatus.h>

#define SSM2603_DBG(...)            LOG("SSM", LOG_LEVEL_DEBUG , ## __VA_ARGS__)
#define SSM2603_INF(...)            LOG("SSM", LOG_LEVEL_INFO , ## __VA_ARGS__)
#define SSM2603_ERR(...)            LOG("SSM", LOG_LEVEL_ERROR , ## __VA_ARGS__)

 //0011010b
#define SSM2603_IIC_ADDR            0x1a

#define SSM2603_LIV_REG             0x0
#define SSM2603_RIV_REG             0x1
#define SSM2603_AAP_REG             0x4
#define SSM2603_DAP_REG             0x5
#define SSM2603_PWR_REG             0x6
#define SSM2603_ACT_REG             0x9
#define SSM2603_RST_REG             0xF

#define SSM2603_LIV_LRINBOTH        (1 << 8)
#define SSM2603_LIV_LINMUTE         (1 << 7)
#define SSM2603_LIV_LINVOL_OFF      0
#define SSM2603_LIV_LINVOL_MASK     (((1 << 6) - 1) << SSM2603_LIV_LINVOL_OFF)

#define SSM2603_AAP_SIDETONE        (1 << 5)
#define SSM2603_AAP_DACSEL          (1 << 4)
#define SSM2603_AAP_BYPASS          (1 << 3)
#define SSM2603_AAP_INSEL           (1 << 2)
#define SSM2603_AAP_MUTEMIC         (1 << 1)

#define SSM2603_DAP_DACMUT          (1 << 3)

#define SSM2603_PWR_POWER_OFF       (1 << 7)
#define SSM2603_PWR_OUT             (1 << 4)
#define SSM2603_PWR_DAC             (1 << 3)
#define SSM2603_PWR_ADC             (1 << 2)
#define SSM2603_PWR_MIC             (1 << 1)
#define SSM2603_PWR_LINEIN          (1 << 0)

#define SSM2603_ACT_ACTIVE          (1 << 0)
#define SSM2603_ADC_MIN_DB          -34.5f
#define SSM2603_ADC_MAX_DB          33.0f
#define SSM2603_ADC_STEP_DB         1.5f

#define SSM2603_REG_OP_SET          0x1
#define SSM2603_REG_OP_CLEAR        0x2

static int ssm2603_write_reg(uint8_t addr, uint16_t data)
{
    uint8_t buf[2];

    buf[0] = (addr << 1) | (0x1 & (data >> 8));
    buf[1] = data & 0xFF;

    return i2c_send(buf, 2, 0);
}

static int ssm2603_read_reg(uint8_t addr, uint16_t* data)
{
    int rc;
    uint8_t buf[2];

    
    buf[0] = (addr << 1);
    rc = i2c_send(buf, 1, 1);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = i2c_recv(buf, 2, 0);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    *data = (0x1 & (buf[1] << 8)) | buf[0];
    return XST_SUCCESS;

err:
    return rc;
}

static int ssm2603_reg_op(uint8_t addr, int op, uint16_t mask)
{
    int rc;

    uint16_t value;

    rc = ssm2603_read_reg(addr, &value);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    if (op & SSM2603_REG_OP_SET) {
        value |= mask;
    } else if (op & SSM2603_REG_OP_CLEAR) {
        value &= ~mask;
    } else {
        DBG_ASSERT(0);
    }

    rc = ssm2603_write_reg(addr, value);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static void ssm2603_dump_reg(const char* name, int level, uint8_t addr)
{
    int rc;
    uint16_t value;
    
    rc = ssm2603_read_reg(addr, &value);
    if (rc != XST_SUCCESS) {
        value = 0xdead;
    }

    LOG("SSM", level, "reg %s @ 0x%x = 0x%x", name, addr, value);
}

static int ssm2603_init_seq()
{
    int rc;
    uint16_t act;

    // 1. reset
    rc = ssm2603_write_reg(SSM2603_RST_REG, 0x0);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // 2. Program all POWER bits expect PWR_OUT
    rc = ssm2603_reg_op(SSM2603_PWR_REG, SSM2603_REG_OP_CLEAR,
        SSM2603_PWR_POWER_OFF |
            SSM2603_PWR_DAC |
            SSM2603_PWR_ADC |
            SSM2603_PWR_MIC |
            SSM2603_PWR_LINEIN);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // 3. Program ANALOG AUDIO PATH
    
    // clear SIDETONE and BYPASS output mixing
    rc = ssm2603_reg_op(SSM2603_AAP_REG, SSM2603_REG_OP_CLEAR,
        SSM2603_AAP_SIDETONE | SSM2603_AAP_BYPASS);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // set DAC output mixing
    rc = ssm2603_reg_op(SSM2603_AAP_REG, SSM2603_REG_OP_SET, SSM2603_AAP_DACSEL);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // clear MUTEMIC
    rc = ssm2603_reg_op(SSM2603_AAP_REG, SSM2603_REG_OP_CLEAR, SSM2603_AAP_MUTEMIC);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // 4. Program ACTIVE

    // sleep 20ms before 
    SSM2603_DBG("sleep 20ms before activating the digital audio core");
    timer_sleep(0.020f);
    rc = ssm2603_write_reg(SSM2603_ACT_REG, SSM2603_ACT_ACTIVE);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    SSM2603_DBG("sleep before reading ACTIVE reg");
    timer_sleep(0.010f);
    rc = ssm2603_read_reg(SSM2603_ACT_REG, &act);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // 5. Program POWER Out bit
    rc = ssm2603_reg_op(SSM2603_PWR_REG, SSM2603_REG_OP_CLEAR, SSM2603_PWR_OUT);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    SSM2603_INF("ssm2603_init() complete");

    ssm2603_dump_reg("LIV", LOG_LEVEL_INFO, SSM2603_LIV_REG);
    ssm2603_dump_reg("RIV", LOG_LEVEL_INFO, SSM2603_RIV_REG);
    ssm2603_dump_reg("PWR", LOG_LEVEL_INFO, SSM2603_PWR_REG);
    ssm2603_dump_reg("AAP", LOG_LEVEL_INFO, SSM2603_AAP_REG);
    ssm2603_dump_reg("DAP", LOG_LEVEL_INFO, SSM2603_DAP_REG);
    ssm2603_dump_reg("ACT", LOG_LEVEL_INFO, SSM2603_ACT_REG);

    return XST_SUCCESS;
err:
    return rc;
}

int ssm2603_init()
{
    int rc;

    rc = i2c_init(SSM2603_IIC_ADDR);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = ssm2603_init_seq();
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // perform twice the init sequence, sometimes the analog
    // path does not initialize properly without a proper
    // reset after the OUT is circuit is power on
    // and signal quality suffers
    rc = ssm2603_init_seq();
    if (rc != XST_SUCCESS) {
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

int ssm2603_dacmut(int dacmut)
{
    int rc;

    SSM2603_DBG("dacmut: %d", dacmut);

    rc = ssm2603_reg_op(SSM2603_DAP_REG,
        dacmut ? SSM2603_REG_OP_SET : SSM2603_REG_OP_CLEAR,
        SSM2603_DAP_DACMUT);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    ssm2603_dump_reg("DAP", LOG_LEVEL_DEBUG, SSM2603_DAP_REG);

    return XST_SUCCESS;
err:   
    return rc; 
}

int ssm2603_adcmut(int adcmut)
{
    int rc;
    uint16_t liv;

    SSM2603_DBG("adcmut: %d", adcmut);

    rc = ssm2603_read_reg(SSM2603_LIV_REG, &liv);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    liv |= SSM2603_LIV_LRINBOTH;
    if (adcmut) {
        liv |= SSM2603_LIV_LINMUTE;
    } else {
        liv &= ~SSM2603_LIV_LINMUTE;
    }

    rc = ssm2603_write_reg(SSM2603_LIV_REG, liv);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    ssm2603_dump_reg("LIV", LOG_LEVEL_DEBUG, SSM2603_LIV_REG);
    ssm2603_dump_reg("RIV", LOG_LEVEL_DEBUG, SSM2603_RIV_REG);

    return XST_SUCCESS;
err:
    return rc;
}

int ssm2603_adclevel(float level)
{
    int rc;
    uint16_t liv;

    level = roundf(level / SSM2603_ADC_STEP_DB) * SSM2603_ADC_STEP_DB;

    if (level < SSM2603_ADC_MIN_DB) {
        level = SSM2603_ADC_MIN_DB;
    } else if (level > SSM2603_ADC_MAX_DB) {
        level = SSM2603_ADC_MAX_DB;
    }

    SSM2603_DBG("adclevel: %f db", level);

    const uint16_t sel = (uint16_t)((level - SSM2603_ADC_MIN_DB) / SSM2603_ADC_STEP_DB);

    rc = ssm2603_read_reg(SSM2603_LIV_REG, &liv);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    liv |= SSM2603_LIV_LRINBOTH;
    liv &= ~SSM2603_LIV_LINVOL_MASK;
    liv |= ((sel << SSM2603_LIV_LINVOL_OFF) & SSM2603_LIV_LINVOL_MASK);

    rc = ssm2603_write_reg(SSM2603_LIV_REG, liv);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    ssm2603_dump_reg("LIV", LOG_LEVEL_DEBUG, SSM2603_LIV_REG);
    ssm2603_dump_reg("RIV", LOG_LEVEL_DEBUG, SSM2603_RIV_REG);

    return XST_SUCCESS;
err:
    return rc;
}

int ssm2603_insel(int insel)
{
    int rc;

    SSM2603_DBG("insel: %d", insel);

    rc = ssm2603_reg_op(SSM2603_AAP_REG,
        insel ? SSM2603_REG_OP_CLEAR : SSM2603_REG_OP_SET,
        SSM2603_AAP_INSEL);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    ssm2603_dump_reg("AAP", LOG_LEVEL_DEBUG, SSM2603_AAP_REG);

    return XST_SUCCESS;
err:
    return rc;
}
