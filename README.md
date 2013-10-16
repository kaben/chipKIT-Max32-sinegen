chipKIT-Max32-sinegen
=====================

A sine-wave generator running on the chipKIT-Max32 microcontroller board.

This is a two-channel 8-bit waveform generator for the Arduino-alike Digilent
chipKIT Max32 microcontroller, inspired by the following "Hack A Day" post:
http://hackaday.com/2011/06/08/chipkit-sketch-mini-polyphonic-sampling-synth/

I wrote it because I needed a frequency generator, but I didn't have one, but
I did have everything needed to make one.

The user can specify two frequencies and amplitudes (i.e. voltage, 5.0v max)
via serial by typing commands like the following:
  "1000.0 0.05 2000.0 0.10"
which specifies a 1kHz 0.05v signal on pin 3, and a 2kHz 0.10v signal on pin 5.
By default a serial baudrate of 115,200 is used.

This program outputs the two user-specified (co)sine waves on pins 3 and 5,
with their sum on pin 6 and their difference on pin 9. The outputs are
pulse-width modulated at a frequency of 312.500 kHz. A low-pass filter must be
applied to the output signals. The modulator that lays a (co)sine signal
over the PWM signal runs about about half as fast as the PWM generator, so
(co)sine waves have a Nyquist frequency of 78.125 kHz.

Frequencies are specified in Hertz with precision of approximately 0.00003 Hz.
Amplitudes are specified in Volts with precision of approximately 0.04 V.

The wave generator will smoothly transition from old to new frequencies and
volumes with no discontinuities, which prevents "click" sounds during transition.

Regarding accuracy:
When I compare a generated 440.0 Hz signal with my 440 Hz tuning fork, agreement
is within about 0.5 Hz. I think this indicates that my tuning fork is slightly
out of tune.

Note: I'm seeing jitter in the timing of interrupt handling. It seems to occur
about every 50,000 heartbeats, where the system heartbeat is 80 MHz. It's evident
when generating higher-frequency signals (>10 kHz). I think this is probably
caused by other interrupt handlers. When many of them are in use, there can some
significant lag between the time an interrupt is generated and the time the
corresponding handler is run. If this guess is correct, disabling unused
functionality, interrupts, timers, etc. on the microcontroller should make the
problem go away or become less significant.

Another note: with 8-bits (256 different voltages) the smoothest
sine wave that can be generated requires a minimum of 510 samples. With the
hardware configuration we're using, this means that our sine waves are only as
smooth as possible when they have a frequency of about 600 Hz or lower. At
higher frequencies, fewer than 510 samples are used, so the quality of the
waveform starts to gradually degrade at about 612 Hz, and continues to degrade
up to the Nyquist frequency of 78.125 kHz.
