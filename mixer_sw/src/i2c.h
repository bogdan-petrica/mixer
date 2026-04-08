/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __I2C_H__
#define __I2C_H__

#include <stdint.h>

int i2c_init(uint8_t addr);
int i2c_send(uint8_t* src, uint32_t count, int cont_next);
int i2c_recv(uint8_t* dst, uint32_t count, int cont_next);

#endif // #ifndef __I2C_H__
