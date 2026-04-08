/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "intr.h"
#include "log.h"

#include <xil_exception.h>
#include <xinterrupt_wrap.h>
#include <xscugic.h>
#include <xstatus.h>

#include "xparameters.h"

XScuGic xscugic;

static uint32_t intr_num(uint32_t intr_id)
{
    return XGet_IntrId(intr_id) + XGet_IntrOffset(intr_id);
}

static uint32_t intr_trigger(uint32_t intr_id)
{
     return (XGet_TriggerType(intr_id) == 1) || (XGet_TriggerType(intr_id) == 2) ?
        XINTR_IS_EDGE_TRIGGERED : XINTR_IS_LEVEL_TRIGGERED;
}

int intr_init()
{
    int rc;
    XScuGic_Config* xscugic_cfg;

    Xil_ExceptionInit();

    xscugic_cfg = XScuGic_LookupConfig(XPAR_XSCUGIC_0_BASEADDR);
    if (!xscugic_cfg) {
        rc = XST_DEVICE_NOT_FOUND;
        goto err;
    }

    rc = XScuGic_CfgInitialize(&xscugic,
        xscugic_cfg,
        xscugic_cfg->CpuBaseAddress);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_IRQ_INT,
        (Xil_ExceptionHandler)&XScuGic_InterruptHandler,
        &xscugic);

    Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);

    return XST_SUCCESS;
err:
    return rc;
}

int intr_connect(uint32_t intr_id, uint8_t priority, intr_callback_t callback, void* data)
{
    int rc;

    rc = XScuGic_Connect(&xscugic,
        intr_num(intr_id),
        (Xil_InterruptHandler)callback,
        data);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    LOG("INTR", LOG_LEVEL_DEBUG, "intr_connect(), id: 0x%lx, interrupt num: 0x%lx, trigger: 0x%lx",
        intr_id,
        intr_num(intr_id),
        intr_trigger(intr_id));

    XScuGic_SetPriorityTriggerType(&xscugic,
        intr_num(intr_id),
        priority,
        intr_trigger(intr_id));

    return XST_SUCCESS;
err:
    return rc;
}

void intr_disconnect(uint32_t intr_id)
{
    XScuGic_Disconnect(&xscugic, intr_num(intr_id));
}

void intr_enable(uint32_t intr_id)
{
    XScuGic_Enable(&xscugic, intr_num(intr_id));
}

void intr_disable(uint32_t intr_id)
{
    XScuGic_Disable(&xscugic, intr_num(intr_id));
}
