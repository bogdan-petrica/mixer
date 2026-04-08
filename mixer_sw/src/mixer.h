/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __MIXER_H__
#define __MIXER_H__

#include <stdint.h>
#include <stddef.h>

#define MIXER_SAMPLE_FREQ                   48000
#define MIXER_SAMPLE_SIZE                   sizeof(uint32_t)

#define MIXER_DMA_ALIGN                     sizeof(uint32_t)
#define MIXER_DMA_BOUNDRY_SIZE              4096

#define MIXER_GAIN_MAX                      127

#define MIXER_GAIN_MAX_DB                   +6.0f
#define MIXER_GAIN_STEP_DB                  0.5f
#define MIXER_GAIN_MIN_DB                   (MIXER_GAIN_MAX_DB - MIXER_GAIN_MAX * MIXER_GAIN_STEP_DB)

#define MIXER_PB_DELAY_SIZE_MAX             16384

typedef enum {
    MixerDmaStateIdle,
    MixerDmaStateActive,
    MixerDmaStateError,
    MixerDmaStateDone
} mixer_dma_state_e;

typedef enum {
    MixerChannelRamp,
    MixerChannelPS,
    MixerChannelMic,
    MixerChannelDelay,
    MixerChannelCore,
} mixer_channel_e;

int mixer_init();
int mixer_dma_tx(uint8_t* data, size_t len);
mixer_dma_state_e mixer_dma_get_tx_state();
int mixer_dma_rx_enable(uint16_t rec_size);
int mixer_dma_rx_disable();
int mixer_dma_rx(uint8_t* data, size_t len);
mixer_dma_state_e mixer_dma_get_rx_state();
int mixer_pb_get_gain(mixer_channel_e channel, float* db);
int mixer_pb_set_gain(mixer_channel_e channel, float db);
int mixer_pb_get_delay_mux_sel(mixer_channel_e* out_channel);
int mixer_pb_set_delay_mux_sel(mixer_channel_e channel);
uint16_t mixer_pb_get_delay();
void mixer_pb_set_delay(uint16_t delay);

#endif // #ifndef __MIXER_H__
