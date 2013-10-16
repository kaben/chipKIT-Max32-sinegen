import math, sys

class WaveEntry(object):
  def __init__(self, t = None, n = None): self.t, self.n = t, n
  def __repr__(self): return "<WaveEntry(%s, %s)>" % (self.t, self.n)


def binsearch_v2(wave, t):
  """
  Searches a sine wave table of WaveEntries for the first entry we such that
  t <= we.t .
  """
  l = len(wave)
  d = 2**int(math.ceil(math.log(l, 2.)))
  i = d
  while 0<d:
    if i < l:
      if (t <= wave[i].t) and (i==0 or (wave[i-1].t < t)): break
      if wave[i].t < t: i += d
      else: i -= d
    else: i -= d
    d >>= 1
  return i, wave[i]


def acos_v8(resolution = 256):
  """
  Constructs a cosine wave table fwt of WaveEntries.
  """
  peak = resolution - 1
  half = resolution/2
  step = 2./peak
  pi2_inv = 0.5/math.pi
  wave = [WaveEntry() for n in range(2*peak)]

  n = peak - half
  cosine = 1.
  for x in range(resolution):
    theta = math.acos(cosine)
    wave[x].t = theta*pi2_inv
    wave[x].n = n
    n -= 1
    cosine -= step
  for x in range(resolution, 2*peak):
    wave[x].t = 1. - wave[2*peak-x].t
    wave[x].n = wave[2*peak-x].n
  return wave


def asin_v7(resolution = 256):
  """
  Constructs a sine wave table fwt of WaveEntries.
  """
  peak = resolution - 1
  half = resolution/2
  step = 2./peak
  pi2_inv = 0.5/math.pi
  wave = [WaveEntry() for n in range(2*peak)]

  n = half
  sine = n*step-1.
  for x in range(half):
    theta = math.asin(sine)
    wave[x].t = theta*pi2_inv
    wave[x].n = n
    n += 1
    sine += step
  for x in range(half, peak):
    wave[x].t = 0.5 - wave[peak-x-1].t
    wave[x].n = wave[peak-x-1].n
  for x in range(peak, 2*peak):
    wave[x].t = 0.5 + wave[x-peak].t
    wave[x].n = peak - wave[x-peak].n
  return wave

def test_binary_search(wave_generator):
  """
  Test of binary search of wave table
  """
  print "testing", wave_generator
  full_wave_table = wave_generator()
  for period in range(5000):
    int_wave_table = [WaveEntry(int(we.t*period), we.n) for we in full_wave_table]
    time_list = [we.t for we in int_wave_table]
    mean_time_list = [(time_list[n]+time_list[n+1])/2. for n in range(len(time_list)-1)]
    search_result_list = [(t, binsearch_v2(int_wave_table, t)) for t in time_list]
    search_result_list += [(t, binsearch_v2(int_wave_table, t)) for t in mean_time_list]
    bad_search_results = [(t, i, we) for (t, (i, we)) in search_result_list if not t <= we.t]
    if 0 < len(bad_search_results):
      print "Number of bad search results for period", period, ":", len(bad_search_results)
    if not period % 100:
      sys.stdout.write(".")
      sys.stdout.flush()

if __name__ == "__main__":
  #full_wave_table = asin_v7()
  #full_wave_table = asin_v7()
  test_binary_search(asin_v7)
  test_binary_search(acos_v8)
