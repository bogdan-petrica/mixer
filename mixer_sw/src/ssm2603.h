/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __SSM2603_H__
#define __SSM2603_H__

int ssm2603_init();
int ssm2603_dacmut(int dacmut);
int ssm2603_adcmut(int adcmut);
int ssm2603_adclevel(float level);
int ssm2603_insel(int insel);

#endif // #ifndef __SSM2603_H__
