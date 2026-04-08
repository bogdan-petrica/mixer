/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __NOTE_GEN_H__
#define __NOTE_GEN_H__

#include "buffer.h"

void note_gen_ramp(buffer_t* buffer, uint32_t* head, uint32_t* tail, uint32_t period_samples, uint32_t samples);
void note_gen_sine(buffer_t* buffer, uint32_t* head, uint32_t* tail, uint32_t period_samples, uint32_t samples);

#endif // #ifndef __NOTE_GEN_H__
