/*
 * Copyright (c) 2026 Bogdan Petrica
 * SPDX-License-Identifier: Apache-2.0
 */
#include "intr.h"
#include "timer.h"
#include "ssm2603.h"
#include "mixer.h"
#include "dbg.h"
#include "btn_sw.h"
#include "led.h"
#include "log.h"
#include "buffer.h"
#include "note_gen.h"

#include <stdint.h>
#include <memory.h>
#include <math.h>

#include <sys/_intsup.h>
#include <xstatus.h>

#define APP_DBG(...)                                    LOG("APP", LOG_LEVEL_DEBUG , ## __VA_ARGS__)
#define APP_INF(...)                                    LOG("APP", LOG_LEVEL_INFO , ## __VA_ARGS__)
#define APP_ERR(...)                                    LOG("APP", LOG_LEVEL_ERROR , ## __VA_ARGS__)

#define APP_PS_NOTE_RAMP                                0x1
#define APP_PS_NOTE_SINE                                0x2
#define APP_PS_NOTE                                     APP_PS_NOTE_SINE

#define APP_MODE_SEL_SW_MASK                            0x7
#define APP_MODE_SEL_SW_RAMP_GAIN                       0x0
#define APP_MODE_SEL_SW_PS_GAIN                         0x1
#define APP_MODE_SEL_SW_MIC_GAIN                        0x2
#define APP_MODE_SEL_SW_DELAY_GAIN                      0x3
#define APP_MODE_SEL_SW_DELAY                           0x4
#define APP_MODE_SEL_SW_DELAY_MUX                       0x5

#define APP_MICSEL_SW_MASK                              0x8

#define APP_PLAY_BTN                                    (1 << 0)
#define APP_RECORD_BTN                                  (1 << 1)
#define APP_NEXT_BTN                                    (1 << 2)
#define APP_PREV_BTN                                    (1 << 3)

#define APP_LED_COUNT                                   4

#define APP_ALIVE_LED                                   0
#define APP_PLAY_LED                                    1
#define APP_RECORD_LED                                  2

#define APP_NEXT_PREV_EVENT_PERIOD_SEC                  0.1f

#define APP_GAIN_MAX_DB                                 MIXER_GAIN_MAX_DB
#define APP_GAIN_MIN_DB                                 -35.0f
#define APP_GAIN_STEP_DB                                1.0f

_Static_assert(APP_GAIN_MIN_DB >= MIXER_GAIN_MIN_DB);
_Static_assert(APP_GAIN_MAX_DB <= MIXER_GAIN_MAX_DB);
_Static_assert(APP_GAIN_STEP_DB == (int)(APP_GAIN_STEP_DB / MIXER_GAIN_STEP_DB) * MIXER_GAIN_STEP_DB);

#define APP_ADC_MIC_DB                                  -20.0f
#define APP_ADC_LININ_DB                                0.0f

#define APP_DELAY_STEP_SEC                              0.01f

#define APP_FEEDBACK_PERIOD_SEC                         0.8f

#define APP_LED_BAR_SIGMA                               0.7f
#define APP_LED_BAR_BASE_LEVEL                          0.4f

#define APP_CNT_PERIOD_SEC                              0.01f

#define APP_ALIVE_LED_HALF_PERIOD_TICKS                 32
#define APP_PLAY_LED_HALF_PERIOD_TICKS                  16
#define APP_RECORD_LED_HALF_PERIOD_TICKS                8

typedef enum {
    AppFeedbackStateNormal,
    AppFeedbackStateRampGain,
    AppFeedbackStatePsGain,
    AppFeedbackStateMicGain,
    AppFeedbackStateDelayGain,
    AppFeedbackStateDelayMuxSel,
    AppFeedbackStateDelay,
} app_feedback_e;

typedef enum {
    AppPlayStateIdle,
    AppPlayStateRun,
    AppPlayStateStop,
} app_pb_state_e;

typedef enum {
    AppRecordStateIdle,
    AppRecordStateRun,
    AppRecordStateStop,
} app_rec_state_e;

typedef struct {
    // IO
    int                     play_btn;
    int                     play_btn_pressed;
    
    int                     mode_sel;
    int                     mode_sel_changed;

    int                     rec_btn;
    int                     rec_btn_pressed;

    int                     next_btn;
    int                     next_btn_pressed;
    int                     next_btn_event;
    uint32_t                next_btn_ticks;

    int                     prev_btn;
    int                     prev_btn_pressed;
    int                     prev_btn_event;
    uint32_t                prev_btn_ticks;

    int                     mic_sel;
    int                     mic_sel_changed;

    // app feedback
    app_feedback_e          app_feedback;    
    uint32_t                app_feedback_ticks;

    // led output counter
    uint32_t                cnt_start_ticks;
    uint32_t                cnt;

    int                     error;

    // playback
    app_pb_state_e          pb_state;

    buffer_t                pb_buffer;

    uint32_t                pb_dma_buffer_current;
    uint32_t                pb_dma_buffer_head;
    uint32_t                pb_dma_buffer_tail;

    mixer_dma_state_e       pb_dma_state;
    int                     pb_dma_done;

    // record
    app_rec_state_e         rec_state;
    
    buffer_t                rec_buffer;

    uint32_t                rec_dma_buffer_head;
    uint32_t                rec_dma_buffer_tail;

    mixer_dma_state_e       rec_dma_state;
    int                     rec_dma_done;

    // adc
    unsigned int            adc_active_count;

    // sync
    int                     pb_rec_sync_disable;
    int                     pb_sync;
    int                     rec_sync;

    // playback mixer setting
    mixer_channel_e         delay_mux_channel;
    float                   ramp_gain;
    float                   ps_gain;
    float                   mic_gain;
    float                   delay_gain;
    uint16_t                delay;
} app_t;

static app_t app;

// non static function, part of the "app" interface
int app_init()
{
    int rc;

    app.play_btn               = 0;
    app.play_btn_pressed       = 0;

    app.mode_sel               = APP_MODE_SEL_SW_RAMP_GAIN;
    app.mode_sel_changed       = 0;

    app.rec_btn                = 0;
    app.rec_btn_pressed        = 0;

    app.next_btn               = 0;
    app.next_btn_pressed       = 0;
    app.next_btn_event         = 0;
    app.next_btn_ticks         = 0;

    app.prev_btn               = 0;
    app.prev_btn_pressed       = 0;
    app.prev_btn_event         = 0;
    app.prev_btn_ticks         = 0;

    app.mic_sel                = 0;
    app.mic_sel_changed        = 0;

    // app feedback
    app.app_feedback           = AppFeedbackStateNormal;
    app.app_feedback_ticks     = 0;

    // led output counter
    app.cnt_start_ticks        = 0;
    app.cnt                    = 0;
    app.error                   = XST_SUCCESS;

    // playback
    app.pb_state               = AppPlayStateIdle;

    app.pb_dma_buffer_current  = 0;

    const uint32_t period_samples = (1 << 7); // 1 / ( 2^7 / 48000HZ ) = 48000HZ/128 = 375HZ
    const uint32_t samples = BUFFER_SIZE_SAMPLES * 8; // 256 * 8 / 48000HZ = 2048 / 48000HZ = 0.0427s

    if (APP_PS_NOTE & APP_PS_NOTE_RAMP) {
        note_gen_ramp(&app.pb_buffer, &app.pb_dma_buffer_head, &app.pb_dma_buffer_tail, period_samples, samples);
    } else if (APP_PS_NOTE & APP_PS_NOTE_SINE) {
        note_gen_sine(&app.pb_buffer, &app.pb_dma_buffer_head, &app.pb_dma_buffer_tail, period_samples, samples);
    } else {
        DBG_ASSERT(0);
    }

    APP_INF("init PS with note(%s) @ %f HZ for a time of %5.3f sec",
            (APP_PS_NOTE & APP_PS_NOTE_RAMP) ? "ramp" : "sine",
            (float)SAMPLE_FREQ / period_samples ,
            (float)samples / SAMPLE_FREQ);
    
    app.pb_dma_state           = MixerDmaStateIdle;
    app.pb_dma_done            = 0;

    // record
    app.rec_state              = AppRecordStateIdle;

    app.rec_dma_buffer_head    = 0;
    app.rec_dma_buffer_tail    = 0;

    app.rec_dma_state          = MixerDmaStateIdle;
    app.rec_dma_done           = 0;

    // adc
    app.adc_active_count       = 0;

    // sync
#ifdef APP_PB_REC_SYNC_DISABLE
    app.pb_rec_sync_disable    = 1;
#else
    app.pb_rec_sync_disable    = 0;
#endif
    app.rec_sync               = 0;
    app.pb_sync                = 0;

    // playback mixer settings
    app.delay_mux_channel      = MixerChannelMic;
    app.ramp_gain              = APP_GAIN_MIN_DB;
    app.ps_gain                = APP_GAIN_MIN_DB;
    app.mic_gain               = 0.0f;
    app.delay_gain             = APP_GAIN_MIN_DB;
    app.delay                  = 0;

    // set mixer values that are not default
    rc = mixer_pb_set_delay_mux_sel(app.delay_mux_channel);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = mixer_pb_set_gain(MixerChannelRamp, app.ramp_gain);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = mixer_pb_set_gain(MixerChannelPS, app.ps_gain);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = mixer_pb_set_gain(MixerChannelMic, app.mic_gain);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    rc = mixer_pb_set_gain(MixerChannelDelay, app.delay_gain);
    if (rc != XST_SUCCESS) {
        goto err;
    }

    mixer_pb_set_delay(app.delay);

    // disable all leds
    for(unsigned int led_idx = 0; led_idx < APP_LED_COUNT; ++led_idx) {
        led_set(led_idx, 0.0f);
    }

    APP_INF("audio buffer size: %12.2f KB, buffer size duration: %5.2f sec",
        TOTAL_BUFFER_SIZE / 1024.,
        (float)TOTAL_BUFFER_SIZE / SAMPLE_SIZE / SAMPLE_FREQ);

    return XST_SUCCESS;
err:
    return rc;
}

// non static function, part of the "app" interface
void app_read_in()
{
    int btn;
    int sw;

    btn_sw_read(&btn, &sw);

    // handle play btn
    app.play_btn_pressed = (!app.play_btn && (btn & APP_PLAY_BTN));
    app.play_btn = btn & APP_PLAY_BTN;

    // handle mode sel sw
    const int mode_sel = sw & APP_MODE_SEL_SW_MASK;
    app.mode_sel_changed = app.mode_sel != mode_sel;
    app.mode_sel = mode_sel;

    // handle record btn
    app.rec_btn_pressed = (!app.rec_btn && (btn & APP_RECORD_BTN));
    app.rec_btn = btn & APP_RECORD_BTN;

    // handle next btn
    const uint32_t ticks = timer_ticks();
    const uint32_t event_period_ticks = timer_sec2ticks(APP_NEXT_PREV_EVENT_PERIOD_SEC);

    app.next_btn_pressed = (!app.next_btn) && (btn & APP_NEXT_BTN);
    const int next_btn_timeout = app.next_btn && (ticks - app.next_btn_ticks > event_period_ticks);

    if (app.next_btn_pressed || next_btn_timeout) {
        app.next_btn_ticks = ticks;
        app.next_btn_event = 1;
    } else {
        app.next_btn_event = 0;
    }

    app.next_btn = btn & APP_NEXT_BTN;

    // handle prev btn
    app.prev_btn_pressed = (!app.prev_btn) && (btn & APP_PREV_BTN);
    const int prev_btn_timeout = app.prev_btn && (ticks - app.prev_btn_ticks > event_period_ticks);

    if (app.prev_btn_pressed || prev_btn_timeout) {
        app.prev_btn_ticks = ticks;
        app.prev_btn_event = 1;
    } else {
        app.prev_btn_event = 0;
    }

    app.prev_btn = btn & APP_PREV_BTN;

    // handle mic sel sw
    const int mic_sel = (sw & APP_MICSEL_SW_MASK);
    app.mic_sel_changed = app.mic_sel != mic_sel;
    app.mic_sel = mic_sel;
}

static int app_adc_unmute()
{
    int rc;
    
    if (!app.adc_active_count) {
        rc = ssm2603_adcmut(0);
        if (rc != XST_SUCCESS) {
            APP_ERR("ssm2603_adcmut(), adcmut = 0, fail");
            goto err;
        }
    }

    ++app.adc_active_count;

    return XST_SUCCESS;
err:
    return rc;
}

static int app_adc_mute()
{
    int rc;

    DBG_ASSERT(app.adc_active_count > 0);

    if (app.adc_active_count == 1) {
        rc = ssm2603_adcmut(1);
        if (rc != XST_SUCCESS) {
            APP_ERR("ssm2603_adcmut(), adcmut = 1, fail");
            goto err;
        }
    }

    --app.adc_active_count;
    return XST_SUCCESS;
err:
    return rc;
}

static void app_set_feedback(app_feedback_e feedback)
{
    app.app_feedback = feedback;
    app.app_feedback_ticks = timer_ticks();
}

static int app_pb_inputs_cycle()
{
    int rc;

    if (app.next_btn_event || app.prev_btn_event) {
        switch(app.mode_sel) {
        case APP_MODE_SEL_SW_RAMP_GAIN:
        case APP_MODE_SEL_SW_PS_GAIN:
        case APP_MODE_SEL_SW_MIC_GAIN:
        case APP_MODE_SEL_SW_DELAY_GAIN:
            {
                mixer_channel_e gain_channel;
                float* gain;

                switch(app.mode_sel) {
                case APP_MODE_SEL_SW_RAMP_GAIN:
                    gain_channel = MixerChannelRamp;
                    gain = &app.ramp_gain;
                    app_set_feedback(AppFeedbackStateRampGain);
                    break;
                case APP_MODE_SEL_SW_PS_GAIN:
                    gain_channel = MixerChannelPS;
                    gain = &app.ps_gain;
                    app_set_feedback(AppFeedbackStatePsGain);
                    break;
                case APP_MODE_SEL_SW_MIC_GAIN:
                    gain_channel = MixerChannelMic;
                    gain = &app.mic_gain;
                    app_set_feedback(AppFeedbackStateMicGain);
                    break;
                case APP_MODE_SEL_SW_DELAY_GAIN:
                    gain_channel = MixerChannelDelay;
                    gain = &app.delay_gain;
                    app_set_feedback(AppFeedbackStateDelayGain);
                    break;                
                }

                if (app.next_btn_event) {
                    *gain += APP_GAIN_STEP_DB;
                    if (*gain > APP_GAIN_MAX_DB) {
                        *gain = APP_GAIN_MAX_DB;
                    }
                } else if (app.prev_btn_event) {
                    *gain -= APP_GAIN_STEP_DB;
                    if (*gain < APP_GAIN_MIN_DB) {
                        *gain = APP_GAIN_MIN_DB;
                    }
                }

                rc = mixer_pb_set_gain(gain_channel, *gain);
                if (rc != XST_SUCCESS) {
                    goto err;
                }
            }
            break;
        case APP_MODE_SEL_SW_DELAY:
            {
                const uint16_t delay_step_samples = (uint16_t)(APP_DELAY_STEP_SEC * SAMPLE_FREQ + .5f);

                if (app.next_btn_event) {
                    if (app.delay + delay_step_samples <= MIXER_PB_DELAY_SIZE_MAX) {
                        app.delay += delay_step_samples;
                    }
                } else if (app.prev_btn_event) {
                    if (app.delay < delay_step_samples) {
                        app.delay = 0;
                    } else {
                        app.delay -= delay_step_samples;
                    }
                }

                APP_DBG("set delay, delay: %6.4fs", (float)app.delay / SAMPLE_FREQ);

                mixer_pb_set_delay(app.delay);

                app_set_feedback(AppFeedbackStateDelay);
            }
            break;
        default:
            break;
        };
    }

    if (app.next_btn_pressed && (app.mode_sel == APP_MODE_SEL_SW_DELAY_MUX)) {
        switch(app.delay_mux_channel)
        {
        case MixerChannelPS:
            app.delay_mux_channel = MixerChannelMic;
            break;
        
        case MixerChannelMic:
            app.delay_mux_channel = MixerChannelCore;
            break;

        case MixerChannelCore:
            app.delay_mux_channel = MixerChannelPS;
            break;

        default:
            DBG_ASSERT(0);
        }

        rc = mixer_pb_set_delay_mux_sel(app.delay_mux_channel);
        if (rc != XST_SUCCESS) {
            goto err;
        }

        app_set_feedback(AppFeedbackStateDelayMuxSel);
    }

    if (app.mic_sel_changed) {
        rc = ssm2603_insel(app.mic_sel ? 0 : 1);
        if (rc != XST_SUCCESS) {
            goto err;
        }

        rc = ssm2603_adclevel(app.mic_sel ? APP_ADC_MIC_DB : APP_ADC_LININ_DB);
        if (rc != XST_SUCCESS) {
            goto err;
        }

        APP_DBG("mic_sel changed, mic_sel: %d", app.mic_sel ? 0 : 1);
    }

    return XST_SUCCESS;
err:
    return rc;
}

static int app_pb_dma_tx_cont()
{
    int rc;

    uint32_t* const buffer = app.pb_buffer.data[app.pb_dma_buffer_current];
    app.pb_dma_buffer_current = buffer_ring_next(app.pb_dma_buffer_head,
        app.pb_dma_buffer_tail,
        TOTAL_BUFFER_CNT,
        app.pb_dma_buffer_current);
    
    app.pb_dma_done = 0;
    app.pb_dma_state = MixerDmaStateActive;
    rc = mixer_dma_tx((uint8_t*)buffer, BUFFER_SIZE);
    if (rc != XST_SUCCESS) {
        APP_ERR("mixer_dma_tx() fail");
        app.pb_dma_state = MixerDmaStateError;
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static int app_pb_dma_tx_start()
{
    int rc;

    DBG_ASSERT((app.pb_dma_state != MixerDmaStateActive) && (app.pb_dma_state != MixerDmaStateError));

    app.pb_dma_buffer_current = app.pb_dma_buffer_head;

    rc = app_pb_dma_tx_cont();
    if (rc != XST_SUCCESS) {
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static int app_pb_dma_tx_cycle()
{
    int rc;

    const mixer_dma_state_e pb_dma_state = mixer_dma_get_tx_state();

    app.pb_dma_done = (app.pb_dma_state != MixerDmaStateDone) && (pb_dma_state == MixerDmaStateDone);
    app.pb_dma_state = pb_dma_state;

    if (pb_dma_state == MixerDmaStateError) {
        APP_ERR("pb_dma_state == MixerDmaStateError");
        rc = XST_DMA_TRANSFER_ERROR;
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static int app_pb_cycle()
{
    int rc;

    // handle inputs
    rc = app_pb_inputs_cycle();
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // handle DMA
    rc = app_pb_dma_tx_cycle();
    if (rc != XST_SUCCESS) {
        goto err;
    }

    // synchronize with recording
    if (app.rec_sync) {
        DBG_ASSERT(!app.pb_rec_sync_disable);

        const int can_sync = (app.pb_state == AppPlayStateIdle) || app.pb_dma_done;
        if (can_sync) {
            APP_DBG("pb rec_sync");
            --app.rec_sync;

            memcpy(&app.pb_buffer, &app.rec_buffer, sizeof(app.pb_buffer));

            app.pb_dma_buffer_head = app.rec_dma_buffer_head;
            app.pb_dma_buffer_tail = app.rec_dma_buffer_tail;

            app.pb_dma_buffer_current = app.pb_dma_buffer_head;

            ++app.pb_sync;
        }
    }

    // cycle the playback state machine
    switch(app.pb_state) {
    case AppPlayStateIdle:
        if (app.play_btn_pressed) {
            APP_INF("playback start");

            // DAC unmute
            rc = ssm2603_dacmut(0);
            if (rc != XST_SUCCESS) {
                APP_ERR("ssm2603_dacmut(), dacmut = 0, fail");
                goto err;
            }

            // ADC unmute
            rc = app_adc_unmute();
            if (rc != XST_SUCCESS) {
                goto err;
            }

            // start DMA
            rc = app_pb_dma_tx_start();
            if (rc != XST_SUCCESS) {
                goto err;
            }

            app.pb_state = AppPlayStateRun;
        }
        break;

    case AppPlayStateRun:
        if (app.pb_dma_done) {
            rc = app_pb_dma_tx_cont();
            if (rc != XST_SUCCESS) {
                goto err;
            }
        }

        if (app.play_btn_pressed) {
            APP_INF("playback stop request");
            app.pb_state = AppPlayStateStop;
        }
        break;

    case AppPlayStateStop:
        // wait for DMA to finish
        if (app.pb_dma_done) {
            APP_INF("playback stop done");

            rc = app_adc_mute();
            if (rc != XST_SUCCESS) {
                goto err;
            }

            rc = ssm2603_dacmut(1);
            if (rc != XST_SUCCESS) {
                APP_ERR("ssm2603_dacmut(), dacmut = 1, fail");
                goto err;
            }
            
            app.pb_state = AppPlayStateIdle;
        }
        break;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static int app_rec_dma_rx_cont()
{
    int rc;

    uint32_t* const buffer = app.rec_buffer.data[app.rec_dma_buffer_tail];

    app.rec_dma_buffer_tail = (app.rec_dma_buffer_tail + 1) % TOTAL_BUFFER_CNT;
    if (app.rec_dma_buffer_tail == app.rec_dma_buffer_head) {
        app.rec_dma_buffer_head = (app.rec_dma_buffer_head + 1) % TOTAL_BUFFER_CNT;
    }

    app.rec_dma_done = 0;
    app.rec_dma_state = MixerDmaStateActive;
    rc = mixer_dma_rx((void*)buffer, BUFFER_SIZE);
    if (rc != XST_SUCCESS) {
        APP_ERR("mixer_dma_rx() fail");
        app.rec_dma_state = MixerDmaStateError;
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static int app_rec_dma_rx_start()
{
    int rc;

    DBG_ASSERT((app.rec_dma_state != MixerDmaStateActive) && (app.rec_dma_state != MixerDmaStateError));
    
    rc = mixer_dma_rx_enable(BUFFER_SIZE_SAMPLES);
    if (rc != XST_SUCCESS) {
        APP_ERR("mixer_dma_rx_enable() fail");
        goto err;
    }

    app.rec_dma_buffer_head = 0;
    app.rec_dma_buffer_tail = 0;

    rc = app_rec_dma_rx_cont();
    if (rc != XST_SUCCESS) {
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static int app_rec_dma_rx_stop()
{
    int rc;

    DBG_ASSERT(app.rec_dma_state == MixerDmaStateDone);

    APP_INF("app_rec_dma_rx_stop()");

    const uint32_t samples = buffer_ring_dist(app.rec_dma_buffer_head, app.rec_dma_buffer_tail, TOTAL_BUFFER_CNT) * BUFFER_SIZE / SAMPLE_SIZE;
    const float rec_total_sec = (float)samples / SAMPLE_FREQ;
    APP_INF("total recording time: %5.3f", rec_total_sec);

    const uintptr_t buffer_head = (uintptr_t)&app.rec_buffer.data[app.rec_dma_buffer_head];
    const uintptr_t buffer_tail = (uintptr_t)&app.rec_buffer.data[app.rec_dma_buffer_tail];

    if (buffer_head > buffer_tail) {
        const uintptr_t buffer_beg = (uintptr_t)&app.rec_buffer.data[0];
        const uintptr_t buffer_end = buffer_beg + TOTAL_BUFFER_SIZE;

        APP_INF("rec buffer first, offset: 0x%08lx, size: 0x%08lx", buffer_head, buffer_end - buffer_head);
        APP_INF("rec buffer second, offset: 0x%08lx, size: 0x%08lx", buffer_beg, buffer_tail - buffer_beg);
    } else {
        APP_INF("rec buffer, offset: 0x%08lx, size: 0x%08lx", buffer_head, buffer_tail - buffer_head);
    }

    rc = mixer_dma_rx_disable();
    if (rc != XST_SUCCESS) {
        APP_ERR("mixer_dma_rx_disable() failed");
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static int app_rec_dma_rx_cycle()
{
    int rc;

    const mixer_dma_state_e rec_dma_state = mixer_dma_get_rx_state();

    app.rec_dma_done = (app.rec_dma_state != MixerDmaStateDone) && (rec_dma_state == MixerDmaStateDone);
    app.rec_dma_state = rec_dma_state;

    if (rec_dma_state == MixerDmaStateError) {
        APP_ERR("rec_dma_state == MixerDmaStateError");
        rc = XST_DMA_TRANSFER_ERROR;
        goto err;
    }

    return XST_SUCCESS;
err:
    return rc;
}

static int app_rec_cycle()
{
    int rc;

    // DMA cycle
    rc = app_rec_dma_rx_cycle();
    if (rc != XST_SUCCESS) {
        goto err;
    }

    switch(app.rec_state) {
    case AppRecordStateIdle:
        if (app.rec_btn_pressed) {
            APP_INF("record start");

            // ADC unmute
            rc = app_adc_unmute();
            if (rc != XST_SUCCESS) {
                goto err;
            }

            // DMA start
            rc = app_rec_dma_rx_start();
            if (rc != XST_SUCCESS) {
                goto err;
            }

            app.rec_state = AppRecordStateRun;
        }
        break;

    case AppRecordStateRun:
        if (app.rec_dma_done) {
            rc = app_rec_dma_rx_cont();
            if (rc != XST_SUCCESS) {
                goto err;
            }
        }

        if (app.rec_btn_pressed) {
            APP_INF("record stop requet");
            app.rec_state = AppRecordStateStop;
        }
        break;

    case AppRecordStateStop:
        // wait for DMA to finish
        if (app.rec_dma_done) {
            APP_INF("record stop DMA finished");

            rc = app_rec_dma_rx_stop();
            if (rc != XST_SUCCESS) {
                goto err;
            }

            APP_INF("record stop done");

            // ADC mute
            rc = app_adc_mute();
            if (rc != XST_SUCCESS) {
                goto err;
            }

            if (!app.pb_rec_sync_disable) {
                APP_DBG("record sync");
                ++app.rec_sync;
            } else {
                app.rec_state = AppRecordStateIdle;
            }
        }

        if (!app.pb_rec_sync_disable) {
            // wait for playback to finish
            if (app.pb_sync) {
                APP_DBG("rec pb_sync");

                --app.pb_sync;
                app.rec_state = AppRecordStateIdle;
            }
        }

        break;
    };

    return XST_SUCCESS;
err:
    return rc;
}

void app_process()
{
    if (app.error != XST_SUCCESS) {
        return;
    }
    
    app.error = app_pb_cycle();

    if (app.error != XST_SUCCESS) {
        return;
    }

    app.error = app_rec_cycle();
}

static void app_led_bar(float level)
{
    for (unsigned int led_idx = 0; led_idx < 4; ++led_idx) {
        const float dist = led_idx - 3.0f * level;
        const float peak_level = expf(- dist * dist / APP_LED_BAR_SIGMA / APP_LED_BAR_SIGMA);
        const float led_level = APP_LED_BAR_BASE_LEVEL + (1.0f - APP_LED_BAR_BASE_LEVEL) * peak_level;
        led_set(led_idx, led_level);
    }
}

void app_write_out()
{
    // update cnt
    const uint32_t ticks = timer_ticks();
    if (ticks - app.cnt_start_ticks > timer_sec2ticks(APP_CNT_PERIOD_SEC)) {
        ++app.cnt;
        app.cnt_start_ticks = ticks;
    }

    switch(app.app_feedback) {
    case AppFeedbackStateNormal:
        {
            if (!app.error) {

                const int active_led = (app.cnt & APP_ALIVE_LED_HALF_PERIOD_TICKS);
                const int playback_led = (app.pb_state != AppPlayStateIdle) && (app.cnt & APP_PLAY_LED_HALF_PERIOD_TICKS);
                const int record_led = (app.rec_state != AppRecordStateIdle) && (app.cnt & APP_RECORD_LED_HALF_PERIOD_TICKS);

                // output active led
                led_set(APP_ALIVE_LED, active_led ? 1.0f : 0.0f);

                // output playback led
                led_set(APP_PLAY_LED, playback_led ? 1.0f : 0.0f);

                // output record led
                led_set(APP_RECORD_LED, record_led ? 1.0f : 0.0f);
            } else {
                // signal error, flash all leds
                for(unsigned int led_idx = 0; led_idx < APP_LED_COUNT; ++led_idx) {
                    led_set(led_idx, (app.cnt & APP_ALIVE_LED_HALF_PERIOD_TICKS) ? 1.0f : 0.0f);
                }
            }
        }
        break;

    case AppFeedbackStateRampGain:
    case AppFeedbackStatePsGain:
    case AppFeedbackStateMicGain:
    case AppFeedbackStateDelayGain:
        {
            float gain;

            switch(app.app_feedback)
            {
            case AppFeedbackStateRampGain:
                gain = app.ramp_gain;
                break;
            case AppFeedbackStatePsGain:
                gain = app.ps_gain;
                break;
            case AppFeedbackStateMicGain:
                gain = app.mic_gain;
                break;
            case AppFeedbackStateDelayGain:
                gain = app.delay_gain;
                break;
            default:
                DBG_ASSERT(0);
                break;
            }

            const float level = 1.0f - (APP_GAIN_MAX_DB - gain) / (APP_GAIN_MAX_DB - APP_GAIN_MIN_DB);
            app_led_bar(level);
        }
        break;

    case AppFeedbackStateDelay:
        const float level = (float)app.delay / MIXER_PB_DELAY_SIZE_MAX;
        app_led_bar(level);
        break;

    case AppFeedbackStateDelayMuxSel:
        const int led_pattern[3][APP_LED_COUNT] = {
            { 1, 0, 0, 0 }, // MixerChannelPS   
            { 0, 1, 0, 0 }, // MixerChannelMic
            { 0, 0, 1, 0 }, // MixerChannelCore
        };

        int pattern_id = -1;
        
        switch(app.delay_mux_channel)
        {
        case MixerChannelPS:
            pattern_id = 0;
            break;
        case MixerChannelMic:
            pattern_id = 1;
            break;
        case MixerChannelCore:
            pattern_id = 2;
            break;
        default:
            DBG_ASSERT(0);
        }

        for(unsigned int led_idx = 0; led_idx < APP_LED_COUNT; ++led_idx)  {
            led_set(led_idx, led_pattern[pattern_id][led_idx] ? 1.0f : 0.0f);
        }
        break;
    }

    if (app.app_feedback != AppFeedbackStateNormal) {
        const uint32_t timeout_ticks = timer_sec2ticks(APP_FEEDBACK_PERIOD_SEC);
        if (timer_ticks() - app.app_feedback_ticks > timeout_ticks) {
            // turn of all leds
            for(unsigned int led_idx = 0; led_idx < APP_LED_COUNT; ++led_idx) {
                led_set(led_idx, 0.0f);
            }

            app.app_feedback = AppFeedbackStateNormal;
        }
    }
}

int main()
{
    int rc;

    rc = intr_init();
    if (rc != XST_SUCCESS) {
        APP_ERR("intr_init() fail");
        goto err;
    }

    rc = timer_init();
    if (rc != XST_SUCCESS) {
        APP_ERR("timer_init() fail");
        goto err;
    }

    rc = ssm2603_init();
    if (rc != XST_SUCCESS) {
        APP_ERR("ssm2603_init() fail");
        goto err;
    }

    rc = mixer_init();
    if (rc != XST_SUCCESS) {
        APP_ERR("mixer_init() fail");
        goto err;
    }

    rc = btn_sw_init();
    if (rc != XST_SUCCESS) {
        APP_ERR("btn_sw_init() fail");
        goto err;
    }

    rc = led_init();
    if (rc != XST_SUCCESS) {
        APP_ERR("led_init() fail");
        goto err;
    }

    rc = app_init();
    if (rc != XST_SUCCESS) {
        APP_ERR("app_init() fail");
        goto err;
    }

    APP_INF("init complete, starting");

    while (1) {
        app_read_in();
        app_process();
        app_write_out();

        timer_sleep(0.001f);
    }

err:
    return rc;
}
