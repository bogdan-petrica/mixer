/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "note_gen.h"
#include "dbg.h"
#include "sine_table.h"

#include <stdint.h>
#include <math.h>

#include <xstatus.h>

#define SINE_LUT_PERIOD                         (1 << 12)

// max period is given by the size of the sine LUT table
// 1 / (2^12 / 48000HZ) ~= 11.7188 HZ
#define NOTE_GEN_MAX_PERIOD                    SINE_LUT_PERIOD

// min period is given by what is still audible for humans
// 1 / (2^2 / 48000HZ) ~= 120000 HZ
#define NOTE_GEN_MIN_PERIOD                     (1 << 2)

static int note_gen_check(uint32_t period_samples, uint32_t samples)
{
    if (!IS_POWER_OF_TWO(period_samples)) {
        return XST_INVALID_PARAM;
    }

    if ((NOTE_GEN_MIN_PERIOD > period_samples) || (period_samples > NOTE_GEN_MAX_PERIOD)) {
        return XST_INVALID_PARAM;
    }

    _Static_assert(IS_POWER_OF_TWO(BUFFER_SIZE_SAMPLES));
    if (samples & (BUFFER_SIZE_SAMPLES - 1)) {
        return XST_INVALID_PARAM;
    }

    if (samples > TOTAL_BUFFER_SIZE / SAMPLE_SIZE) {
        return XST_BUFFER_TOO_SMALL;
    }

    return XST_SUCCESS;
}

static float sine_lookup(uint32_t t, uint32_t period_samples)
{
    const uint32_t sine_period_samples = 1 << 12;
    // already asserted in note_gen_check(), period_sample is power of two and
    // larger than SINE_LUT_PERIOD
    DBG_ASSERT((period_samples & ~(SINE_LUT_PERIOD - 1)) == 0);
    return sine_table[t * sine_period_samples / period_samples];
}


void note_gen_ramp(buffer_t* buffer, uint32_t* head, uint32_t* tail, uint32_t period_samples, uint32_t samples)
{
    DBG_ASSERT(note_gen_check(period_samples, samples) == XST_SUCCESS);

    const uint32_t count = samples / BUFFER_SIZE_SAMPLES;

    *head = 0;
    *tail = count;

    const uint32_t step = (1 << 16) / period_samples;
    uint16_t right = 0;
    
    for (uint32_t i = 0; i < count; ++i) {
        for (uint32_t j = 0; j < BUFFER_SIZE_SAMPLES; ++j) {
            // right channel on lsb bytes
            const uint32_t sample = right;
            buffer->data[i][j] = sample;
            right += step;
        }
    }
}

void note_gen_sine(buffer_t* buffer, uint32_t* head, uint32_t* tail, uint32_t period_samples, uint32_t samples)
{
    DBG_ASSERT(note_gen_check(period_samples, samples) == XST_SUCCESS);

    const uint32_t count = samples / BUFFER_SIZE_SAMPLES;
    *head = 0;
    *tail = count;

    uint16_t t = 0;

    for (uint32_t i = 0; i < count; ++i) {
        for (uint32_t j = 0; j < BUFFER_SIZE_SAMPLES; ++j) {
            const float sine = sine_lookup(t, period_samples);
            // first, convert to Q15 and round
            // second, convert to signed integer
            // third, convert to unsigned for storing the sample(well defined, mod 2^16 arhitmetic)
            // right channel on lsb bytes
            const uint16_t right = (uint16_t)((int16_t)(roundf(sine * 32767.0f)));
            const uint32_t sample = right;
            buffer->data[i][j] = sample;
            
            t = (t + 1) & (period_samples - 1);
        }
    }
}
