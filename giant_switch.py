import math, sys


def acos(resolution = 256):
  """
  Constructs a cosine wave table of pairs (w, n)
  with w the normalized phase (i.e., 0<=w<=1) and
  n the normalized amplitude.
  """
  peak = resolution - 1
  half = resolution/2
  step = 2./peak
  pi2_inv = 0.5/math.pi

  wave = list()
  wave_len = 2*peak

  n = peak - half
  cosine = 1.
  for x in range(resolution):
    theta = math.acos(cosine)
    wave.append((theta*pi2_inv, n))
    n -= 1
    cosine -= step
  for x in range(resolution, wave_len + 1):
    phase, amplitude = wave[wave_len-x] 
    wave.append((1. - phase, amplitude))
  return wave

def generate_c_switch(wave, fixed_pt_multiplier):
  print """
  switch (phase) {"""
  for i in range(len(wave) - 1):
    start_phase, amplitude = wave[i]
    end_phase, _ = wave[i+1]
    print "  case {start_phase} ... {end_phase}: return {amplitude};".format(
      start_phase = int(fixed_pt_multiplier * start_phase),
      end_phase = int(fixed_pt_multiplier * end_phase - 1),
      amplitude = amplitude
    )
  print "  default: return {amplitude};".format(amplitude = _)
  print "  }"
