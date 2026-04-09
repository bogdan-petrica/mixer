# Introduction

This is the top level repository of an hardware and software audio mixer project.

Target platform is __Zynq 7000__ device series featuring a dual core ARM Cortex-A9 CPU and FPGA fabric. More about the hardware platform can be found [here](./mixer_hw/README.md).

The target board is [__Zybo Z7-7010__](https://digilent.com/reference/programmable-logic/zybo-z7/start).

To jump to __audio mixer IP Core__ design, follow this [link](./mixer_hw/doc/AudioMixerIP.md#block-diagram).

For a quick demo you can checkout [software README](./mixer_sw/README.md#introduction) or check the video below:

[![](./doc/video_thumb.png)YouTube video](https://youtu.be/bm6tZgcA20A?si=PH2dcnjw07uSbbLT)

# Design goals

## Audio mixer IP Core

The goal is to have audio mixing entirely in an IP core, although the sampling frequencies for audio signals are low and mixing has low CPU cost the realtime constraints are present, without them, gaps in recording and playback appear even on powerful CPUs with general purpose OSes(like Linux or Windows), this happens as CPU is controlled by the OS, which is optimized for responsiveness over realtime guarantees.

If software path were chosen, a realtime OS would be a more suitable choice, the drawbacks of such choice are:
* developing on generic realtime OSes is non trivial
* extending the application might introduce latencies which break the realtime requirements

The approach taken here is to offload all of the mixing to a dedicated IP core, the [__Zynq 7000__](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/Introduction?tocId=Hf6C7Oo5ABvv2hkWRoiihQ) platform is an ideal candidate for this, as it provides both generic CPUs and FPGA fabric for implementing dedicated IP cores.

## Multiple channels

An audio mixer usually has multiple input sources, the design includes at least the following stereo channels:
* an IP Core channel, this is used for bring up and testing
* a PS channel, signal coming and going to CPU
* LineIn/MicIn channel

## PS integration

Another goal of the project is that for the audio mixer to be extensible, the PS must be added to the loop. The CPU must be able to send and receive samples to the audio mixer without having to use a realtime operating system.

This is achieved by the use of playback and recording buffers, that are large enough such that CPU can be unresponsive for a significant amount of time (milliseconds) without affecting UX.

The buffers must not be so large that they introduce significant delay.

## Channel gain control

Control of the various channels gain(amplification/attenuation) setting is desirable, therefore the audio mixer must be able to control the gain of each channel independently by specifying the intensity in decibels.

## Mixing effects

Simple mixing effects are desirable and possible within FPGA as the [Artix 7](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/Programmable-Logic-Description) series FPGA has enough computing capabilities for DSP applications.

For example the __Zynq Z7010__ device has 240KiloByte Block RAM and 80 DSP slices.

Echo and reverb audio effects were chosen as they can be implemented with a simple delay line, more details can be found in the [audio mixer IP Core block diagram](./mixer_hw/doc/AudioMixerIP.md#block-diagram).
