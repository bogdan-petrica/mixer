/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "i2c.h"
#include "intr.h"
#include "log.h"
#include "dbg.h"

#include <xiic.h>
#include <xiic_l.h>
#include <xstatus.h>

#define I2C_DBG(...)                LOG("I2C", LOG_LEVEL_DEBUG , ## __VA_ARGS__)
#define I2C_INF(...)                LOG("I2C", LOG_LEVEL_INFO , ## __VA_ARGS__)
#define I2C_ERR(...)                LOG("I2C", LOG_LEVEL_ERROR , ## __VA_ARGS__)

#define I2C_IRQ_PRIO           0xa

static XIic xiic;
static volatile int busy_count;
static volatile int send_complete;
static volatile int recv_complete;
static volatile int status;

static int i2c_repeated_start()
{
    return XIic_GetOptions(&xiic) & XII_REPEATED_START_OPTION;
}

static void i2c_send_callback(void* ref, int count)
{
    (void)ref;
    if (!count) {
        send_complete = 1;
    }
}

static void i2c_recv_callback(void* ref, int count)
{
    (void)ref;
    if (!count) {
        recv_complete = 1;
    }
}

static void i2c_status_callback(void* ref, int stat)
{
    (void)ref;
    status |= stat;
}

int i2c_init(uint8_t addr)
{
    int rc;
    XIic_Config* xiic_cfg;

    rc = XST_SUCCESS;
    
    xiic_cfg = XIic_LookupConfig(XPAR_XIIC_0_BASEADDR);
    if (!xiic_cfg) {
        rc = XST_DEVICE_NOT_FOUND;
        goto err;
    }

    rc = XIic_CfgInitialize(&xiic,
        xiic_cfg, xiic_cfg->BaseAddress);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = XIic_SetAddress(&xiic,
        XII_ADDR_TO_SEND_TYPE,
        addr);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = intr_connect(xiic_cfg->IntrId, 
        I2C_IRQ_PRIO,
        &XIic_InterruptHandler,
        &xiic);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    intr_enable(xiic_cfg->IntrId);

    rc = XIic_Start(&xiic);
    if (rc != XST_SUCCESS) {
        goto err_intr_connect;
    }

    XIic_SetSendHandler(&xiic, 0, &i2c_send_callback);
    XIic_SetRecvHandler(&xiic, 0, &i2c_recv_callback);
    XIic_SetStatusHandler(&xiic, 0, &i2c_status_callback);

    I2C_INF("i2c_init() complete");

    return XST_SUCCESS;
err_intr_connect:
    intr_disable(xiic_cfg->IntrId);
    intr_disconnect(xiic_cfg->IntrId);
err:
    return rc;
}

int i2c_send(uint8_t* src, uint32_t count, int cont_next)
{
    int rc;

    DBG_ASSERT(src != 0);
    DBG_ASSERT(count > 0);

    I2C_DBG("i2c_send(), count: %d, repeated start: %d, repeated start next: %d",
        count,
        i2c_repeated_start(),
        cont_next);

    if (!i2c_repeated_start()) {
        // wait for bus
        while (XIic_IsIicBusy(&xiic)) {
            ++busy_count;
        }
    }

    send_complete = 0;
    status = 0;

    const uint32_t xiic_options = cont_next ? XII_REPEATED_START_OPTION : 0;
    XIic_SetOptions(&xiic, xiic_options);

    rc = XIic_MasterSend(&xiic, src, count);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // wait for send complete or NACK
    while (status != XII_SLAVE_NO_ACK_EVENT && !send_complete) {
        ;
    }

    if (status == XII_SLAVE_NO_ACK_EVENT) {
        rc = XST_DEVICE_NOT_FOUND;
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

int i2c_recv(uint8_t* dst, uint32_t count, int cont_next)
{
    int rc;

    DBG_ASSERT(dst != 0);
    DBG_ASSERT(count > 0);

    I2C_DBG("i2c_recv(), count: %d, repeated start: %d, repeated start next: %d",
        count,
        i2c_repeated_start(),
        cont_next);

    if (!i2c_repeated_start()) {
        // wait for bus
        while (XIic_IsIicBusy(&xiic)) {
            ++busy_count;
        }
    }

    recv_complete = 0;
    status = 0;

    const uint32_t xiic_options = cont_next ? XII_REPEATED_START_OPTION : 0;
    XIic_SetOptions(&xiic, xiic_options);

    rc = XIic_MasterRecv(&xiic, dst, count);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // wait for send complete or NACK
    while (status != XII_SLAVE_NO_ACK_EVENT && !recv_complete) {
        ;
    }

    if (status == XII_SLAVE_NO_ACK_EVENT) {
        rc = XST_DEVICE_NOT_FOUND;
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}
