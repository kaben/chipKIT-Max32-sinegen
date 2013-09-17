#include <math.h>
#include <peripheral/timer.h>
#include <peripheral/outcompare.h>

#define PWM_1 3 // OC1 PWM output - don't change
#define PWM_2 5 // OC2 PWM output - don't change
#define PWM_3 6 // OC3 PWM output - don't change
#define PWM_4 9 // OC3 PWM output - don't change

unsigned int lcm(unsigned int a, unsigned int b)
{
  for(unsigned int n=1;;n++) { if((n%a == 0) && (n%b == 0)) { return n; } }
}
  
class DblWaveEntry {
public:
  double t;
  int n;
  DblWaveEntry(double _t = 0., int _n = 0): t(_t), n(_n) {}
};

class IntWaveEntry {
public:
  unsigned int t;
  int n;
  IntWaveEntry(unsigned int _t = 0, int _n = 0): t(_t), n(_n) {}
};

void generateDblWaveTbl(DblWaveEntry *tbl, unsigned int resolution = 256){
  const unsigned int peak = resolution - 1;
  const unsigned int tbl_len = peak*2;
  const int half = resolution/2;
  const double incr = 2./peak;
  const double pi2_inv = 0.5/3.1415926535897932384;
  int n = half;
  double sine = n*incr - 1.;
  unsigned int i = 0;
  for (; i<half; i++, n++, sine+=incr){
    tbl[i].t = asin(sine)*pi2_inv;
    tbl[i].n = n;
  }
  unsigned int i2 = peak-i-1;
  for (; i<peak; i++, i2--){
    tbl[i].t = 0.5 - tbl[i2].t;
    tbl[i].n = tbl[i2].n;
  }
  i2 = i-peak;
  for (; i<tbl_len; i++, i2++){
    tbl[i].t = 0.5 + tbl[i2].t;
    tbl[i].n = peak - tbl[i2].n;
  }
}

void updateIntWaveTbl(IntWaveEntry *int_tbl, DblWaveEntry *dbl_tbl, unsigned int factor, unsigned int tbl_len = 510){
  for (unsigned int i=0; i<tbl_len; i++){
    int_tbl[i].t = factor * dbl_tbl[i].t;
    int_tbl[i].n = dbl_tbl[i].n;
  }
}

void updateDblWaveTbl(DblWaveEntry *tgt_tbl, DblWaveEntry *src_tbl, double factor, unsigned int tbl_len = 510){
  for (unsigned int i=0; i<tbl_len; i++){
    tgt_tbl[i].t = factor * src_tbl[i].t;
    tgt_tbl[i].n = src_tbl[i].n;
  }
}

unsigned int binsearchIntWaveTbl(IntWaveEntry *tbl, unsigned int t, unsigned int tbl_len = 510, unsigned int d = 512){
  unsigned int i = d;
  for (; 0<d; d>>=1){
    if (i<tbl_len){
      if ((t<=tbl[i].t) && ((i==0) || (tbl[i-1].t<t))){ break; }
      if (tbl[i].t<t) { i += d; }
      else { i -= d; }
    } else { i -= d; }
  }
  return i;
}

unsigned int binsearchDblWaveTbl(DblWaveEntry *tbl, double t, unsigned int tbl_len = 510, unsigned int d = 512){
  unsigned int i = d;
  for (; 0<d; d>>=1){
    if (i<tbl_len){
      if ((t<=tbl[i].t) && ((i==0) || (tbl[i-1].t<t))){ break; }
      if (tbl[i].t<t) { i += d; }
      else { i -= d; }
    } else { i -= d; }
  }
  return i;
}

class WaveTable {
public:
  unsigned int period;
  float phase;
  float num_waves;
  float volume;
  byte *bytes;
public:
  WaveTable(): period(0), phase(0), num_waves(5), volume(1.), bytes(0) {}
public:
  void newPeriod(unsigned int _period, float _phase, float _num_waves, float _volume, DblWaveEntry *d_tbl){
    if (bytes) { delete[] bytes; }
    period = _period;
    phase = _phase;
    volume = _volume;
    num_waves = _num_waves;
    bytes = new byte[period];
    DblWaveEntry tbl[510];
    updateDblWaveTbl(tbl, d_tbl, period/num_waves);
    for (unsigned int i=0; i<period; i++) {
      double remainder = fmod(i + phase*period/num_waves, period/num_waves);
      bytes[i] = volume*(tbl[binsearchDblWaveTbl(tbl, remainder)].n - 128) + 128;
    }
  }
  void newFrequency(float freq, float _phase, float _num_waves, float _volume, DblWaveEntry *d_tbl){
    unsigned int _period = (num_waves * F_CPU) / (256 * freq);
    newPeriod(_period, _phase, _num_waves, _volume, d_tbl);
  }
  byte get(unsigned int tick) { return bytes[tick % period]; }
  void print(HardwareSerial s){
    for (unsigned int i=0; i<period; i++) {
      s.print("i: ");
      s.print(i);
      s.print(", n: ");
      s.println((unsigned int)(bytes[i]));
    }
  }
};

uint32_t ticks = 0;
DblWaveEntry dbl_wave_tbl[510];
WaveTable tbl, tbl2;
unsigned int num_waves = 5, num_waves2 = 5;
float frequency = 5000., frequency2 = 5100.;
float phase = 0., phase2 = 0.;
float volume = 0.05, volume2 = 0.05;

void setup() {
  generateDblWaveTbl(dbl_wave_tbl);
  tbl.newFrequency(frequency, phase, num_waves, volume, dbl_wave_tbl);
  tbl2.newFrequency(frequency2, phase2, num_waves2, volume2, dbl_wave_tbl);
  
  pinMode(PWM_1, OUTPUT); // Enable PWM output pin 3
  pinMode(PWM_2, OUTPUT); // Enable PWM output pin 5
  pinMode(PWM_3, OUTPUT); // Enable PWM output pin 6
  ConfigIntTimer2(T2_INT_ON | T2_INT_PRIOR_3);
  OpenTimer2(T2_ON | T2_PS_1_1, 256);
  OpenOC1(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  OpenOC2(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  OpenOC3(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  OpenOC4(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);

  Serial.begin(9600);

  delay(1);
  Serial.print("frequency: ");
  Serial.println(((double)tbl.num_waves * (double)F_CPU)/(double)(256 * tbl.period));
  Serial.print("phase: ");
  Serial.println(tbl.phase);
  Serial.print("num_waves: ");
  Serial.println(tbl.num_waves);
  Serial.print("volume: ");
  Serial.println(tbl.volume);
  Serial.print("period: ");
  Serial.println(tbl.period);

  Serial.print("frequency2: ");
  Serial.println(((double)tbl2.num_waves * (double)F_CPU)/(double)(256 * tbl2.period));
  Serial.print("phase2: ");
  Serial.println(tbl2.phase);
  Serial.print("num_waves2: ");
  Serial.println(tbl2.num_waves);
  Serial.print("volume2: ");
  Serial.println(tbl2.volume);
  Serial.print("period2: ");
  Serial.println(tbl2.period);
}

void loop() {
  if (Serial.available() > 0) {
//    byte input = Serial.read();
//    switch (input) {
//    case 'a': { frequency+=10; break; }
//    case 'b': { frequency-=10; break; }
//    case 'c': { num_waves+=1; break; }
//    case 'd': { num_waves-=1; break; }
//    case 'e': { frequency2+=10; break; }
//    case 'f': { frequency2-=10; break; }
//    case 'g': { num_waves2+=1; break; }
//    case 'h': { num_waves2-=1; break; }
//    default: { break; }
//    }
    frequency = Serial.parseFloat();
    phase = Serial.parseFloat();
    num_waves = Serial.parseInt();
    volume = Serial.parseFloat();
    frequency2 = Serial.parseFloat();
    phase2 = Serial.parseFloat();
    num_waves2 = Serial.parseInt();
    volume2 = Serial.parseFloat();

    INTDisableInterrupts();
    tbl.newFrequency(frequency, phase, num_waves, volume, dbl_wave_tbl);
    tbl2.newFrequency(frequency2, phase2, num_waves2, volume2, dbl_wave_tbl);
    INTEnableInterrupts();

    //  (num_waves * F_CPU) / (256 * _period) = freq;

    Serial.print("frequency: ");
    Serial.println(((double)tbl.num_waves * (double)F_CPU)/(double)(256 * tbl.period));
    Serial.print("phase: ");
    Serial.println(tbl.phase);
    Serial.print("num_waves: ");
    Serial.println(tbl.num_waves);
    Serial.print("volume: ");
    Serial.println(tbl.volume);
    Serial.print("period: ");
    Serial.println(tbl.period);

    Serial.print("frequency2: ");
    Serial.println(((double)tbl2.num_waves * (double)F_CPU)/(double)(256 * tbl2.period));
    Serial.print("phase2: ");
    Serial.println(tbl2.phase);
    Serial.print("num_waves2: ");
    Serial.println(tbl2.num_waves);
    Serial.print("volume2: ");
    Serial.println(tbl2.volume);
    Serial.print("period2: ");
    Serial.println(tbl2.period);
  }
}

extern "C" {
void __ISR(_TIMER_2_VECTOR,ipl3) waveGen(void) {
  int n1, n2, np, nm;
  mT2ClearIntFlag();
  ticks++;
  n1 = tbl.get(ticks);
  n2 = tbl2.get(ticks);
  np = n1+n2 + 1;
  np >>= 1;
  nm = (n1-128)-(n2-128) + 1;
  nm >>= 1;
  nm += 128;
  SetDCOC1PWM(n1);
  SetDCOC2PWM(n2);
  SetDCOC3PWM(np);
  SetDCOC4PWM(nm);
}
}
