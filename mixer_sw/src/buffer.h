/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __BUFFER_H__
#define __BUFFER_H__

#include "mixer.h"
#include "dbg.h"

#include <stdint.h>

#define IS_POWER_OF_TWO(val)                            (!(val & (val - 1)))

#define MEMALIGN_REM(addr, align)                       (addr & (align - 1))
#define MEMALIGN(addr, align)                           (addr + ((MEMALIGN_REM(addr, align) > 0) ? (align - MEMALIGN_REM(addr, align)) : 0))

#define SAMPLE_FREQ                                     MIXER_SAMPLE_FREQ
#define SAMPLE_SIZE                                     MIXER_SAMPLE_SIZE

#define BUFFER_SIZE_SAMPLES                             256
#define BUFFER_SIZE                                     (BUFFER_SIZE_SAMPLES * SAMPLE_SIZE)

#define MIN_BUFFER_SIZE_SEC                             60
#define MIN_BUFFER_SIZE_SAMPLES                         (MIN_BUFFER_SIZE_SEC * SAMPLE_FREQ)

#define TOTAL_BUFFER_SIZE                               (MEMALIGN(MIN_BUFFER_SIZE_SAMPLES * SAMPLE_SIZE, BUFFER_SIZE))

#define TOTAL_BUFFER_CNT                                (TOTAL_BUFFER_SIZE / BUFFER_SIZE)

typedef __attribute__ ((aligned (4096))) struct {
    // samples are stored as a left right pair of Q15 fixed point values
    // 
    // each channel ( left or right ) is better represented by a signed integer
    // however, because shifts are involved for storing/retriving the 
    // channel value we use an unsigned integer
    //
    // msb bytes - left channel
    // lsb bytes - right channel
    uint32_t data[TOTAL_BUFFER_CNT][BUFFER_SIZE_SAMPLES];
} buffer_t;

_Static_assert(sizeof(buffer_t) == TOTAL_BUFFER_SIZE);

static inline
uint32_t buffer_ring_dist(uint32_t a, uint32_t b, uint32_t total)
{
    return (b + total - a) % total;
}

static inline
uint32_t buffer_ring_next(uint32_t head, uint32_t tail, uint32_t total, uint32_t current)
{
    const uint32_t avail = buffer_ring_dist(head, tail, total);
    current = (current + 1) % total;
    const uint32_t current_dist = buffer_ring_dist(head, current, total);

    if (current_dist == avail) {
        current = head;
    } else {
        DBG_ASSERT(current_dist < avail);
    }
    return current;
}

#endif // #ifndef __BUFFER_H__
