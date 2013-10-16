/*
This is a two-channel 8-bit waveform generator for the Arduino-alike Digilent
chipKIT Max32 microcontroller, inspired by the following "Hack A Day" post:
http://hackaday.com/2011/06/08/chipkit-sketch-mini-polyphonic-sampling-synth/

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

Copyright 2013 by Kaben Nanlohy. All rights reserved.
*/

#include <peripheral/timer.h>
#include <peripheral/outcompare.h>

/* Wave generator parameters. */
const unsigned int dac_resolution = 256; // Don't change.
const unsigned int waveform_zero_offset = dac_resolution/2; // Don't change.
const uint64_t fixed_int_multiplier = 4294967296ULL; // Don't change.
const int fixed_volume_multiplier = dac_resolution; // Don't change.
const unsigned int wavegen_interrupt_period = 3*dac_resolution; // Don't change

/* Output pin assignments. */
const unsigned int PWM_1 = 3; // OC1 PWM output - don't change
const unsigned int PWM_2 = 5; // OC2 PWM output - don't change
const unsigned int PWM_3 = 6; // OC3 PWM output - don't change
const unsigned int PWM_4 = 9; // OC3 PWM output - don't change
const unsigned int LED_PIN = 13; // On-board LED - don't change

/* Frequency state. */
float f0 = 1000., f1 = 1000.;

/* Phase state. */
uint32_t w0 = 0, w1 = 0;
// Target phase differentials corresponding to above frequencies.
uint32_t dw0_tgt = dw_for_freq(f0), dw1_tgt = dw_for_freq(f1);
// Actual phase differentials.
uint32_t dw0 = 0, dw1 = 0;
// Phase "second-differentials" for gradual frequency adjustment.
uint32_t ddw = fixed_int_multiplier/(2*dac_resolution);

/* Volume state. */
// Target volumes.
int v0_tgt = fixed_volume_multiplier, v1_tgt = fixed_volume_multiplier; // Full volume.
// Actual volumes.
int v0 = 0, v1 = 0;
// Differential for gradual volume adjustment.
int dv = 1;

/* LED "alive" blinkage state. */
const unsigned long blink_period_ms = 500;
unsigned long next_blink_time = 0;
unsigned int led_state = 0;

/* Serial I/O bitrate. */
const unsigned int serial_baud = 115200;


/*
Function to compute required phase differential to generate given frequency.
*/
unsigned int dw_for_freq(float frequency) {
  return frequency * fixed_int_multiplier * wavegen_interrupt_period / F_CPU;
}

/*
Function to compute cosine wave amplitude at given normalized phase.

Normalized phase takes values from zero to one,
in fixed-point representation with 1,000,000,000 fixed-point multiplier.
This corresponds to unnormalized phase from zero to 2*pi.
The giant switch/case statement was generated with a Python script.
The Python script was pretty simple: it computed w=acos(c)
for c in the interval [-1, 1], with the interval sliced into 256 parts,
which gave the first half of the cosine wave. The second half was a reflection
of the first half, with corresponding w offset by pi. This gave corresponding
pairs of phase and amplitude in the form (w, c). The phase values were normalized
to the interval [0, 1,000,000,000], and the amplitude values were normalized to
the interval [-128, 127]. These normalized numbers were used to construct the
case labels for the switch statement.
*/
char cosine_amplitude(unsigned int phase) {
  switch (phase) {
  case 0 ... 85669090: return 127;
  case 85669091 ... 121233944: return 126;
  case 121233945 ... 148578434: return 125;
  case 148578435 ... 171676910: return 124;
  case 171676911 ... 192067762: return 123;
  case 192067763 ... 210539469: return 122;
  case 210539470 ... 227560140: return 121;
  case 227560141 ... 243434593: return 120;
  case 243434594 ... 258374437: return 119;
  case 258374438 ... 272533656: return 118;
  case 272533657 ... 286028437: return 117;
  case 286028438 ... 298948995: return 116;
  case 298948996 ... 311367041: return 115;
  case 311367042 ... 323340690: return 114;
  case 323340691 ... 334917813: return 113;
  case 334917814 ... 346138403: return 112;
  case 346138404 ... 357036274: return 111;
  case 357036275 ... 367640318: return 110;
  case 367640319 ... 377975459: return 109;
  case 377975460 ... 388063369: return 108;
  case 388063370 ... 397923038: return 107;
  case 397923039 ... 407571212: return 106;
  case 407571213 ... 417022752: return 105;
  case 417022753 ... 426290917: return 104;
  case 426290918 ... 435387593: return 103;
  case 435387594 ... 444323490: return 102;
  case 444323491 ... 453108293: return 101;
  case 453108294 ... 461750800: return 100;
  case 461750801 ... 470259026: return 99;
  case 470259027 ... 478640303: return 98;
  case 478640304 ... 486901357: return 97;
  case 486901358 ... 495048374: return 96;
  case 495048375 ... 503087062: return 95;
  case 503087063 ... 511022700: return 94;
  case 511022701 ... 518860184: return 93;
  case 518860185 ... 526604061: return 92;
  case 526604062 ... 534258567: return 91;
  case 534258568 ... 541827655: return 90;
  case 541827656 ... 549315021: return 89;
  case 549315022 ... 556724126: return 88;
  case 556724127 ... 564058218: return 87;
  case 564058219 ... 571320350: return 86;
  case 571320351 ... 578513397: return 85;
  case 578513398 ... 585640067: return 84;
  case 585640068 ... 592702919: return 83;
  case 592702920 ... 599704373: return 82;
  case 599704374 ... 606646717: return 81;
  case 606646718 ... 613532123: return 80;
  case 613532124 ... 620362651: return 79;
  case 620362652 ... 627140259: return 78;
  case 627140260 ... 633866810: return 77;
  case 633866811 ... 640544077: return 76;
  case 640544078 ... 647173752: return 75;
  case 647173753 ... 653757448: return 74;
  case 653757449 ... 660296709: return 73;
  case 660296710 ... 666793007: return 72;
  case 666793008 ... 673247756: return 71;
  case 673247757 ... 679662305: return 70;
  case 679662306 ... 686037953: return 69;
  case 686037954 ... 692375943: return 68;
  case 692375944 ... 698677470: return 67;
  case 698677471 ... 704943683: return 66;
  case 704943684 ... 711175687: return 65;
  case 711175688 ... 717374545: return 64;
  case 717374546 ... 723541284: return 63;
  case 723541285 ... 729676891: return 62;
  case 729676892 ... 735782321: return 61;
  case 735782322 ... 741858493: return 60;
  case 741858494 ... 747906300: return 59;
  case 747906301 ... 753926600: return 58;
  case 753926601 ... 759920226: return 57;
  case 759920227 ... 765887986: return 56;
  case 765887987 ... 771830659: return 55;
  case 771830660 ... 777749004: return 54;
  case 777749005 ... 783643754: return 53;
  case 783643755 ... 789515624: return 52;
  case 789515625 ... 795365306: return 51;
  case 795365307 ... 801193473: return 50;
  case 801193474 ... 807000780: return 49;
  case 807000781 ... 812787865: return 48;
  case 812787866 ... 818555346: return 47;
  case 818555347 ... 824303830: return 46;
  case 824303831 ... 830033905: return 45;
  case 830033906 ... 835746145: return 44;
  case 835746146 ... 841441112: return 43;
  case 841441113 ... 847119352: return 42;
  case 847119353 ... 852781402: return 41;
  case 852781403 ... 858427783: return 40;
  case 858427784 ... 864059008: return 39;
  case 864059009 ... 869675576: return 38;
  case 869675577 ... 875277979: return 37;
  case 875277980 ... 880866695: return 36;
  case 880866696 ... 886442197: return 35;
  case 886442198 ... 892004945: return 34;
  case 892004946 ... 897555393: return 33;
  case 897555394 ... 903093985: return 32;
  case 903093986 ... 908621159: return 31;
  case 908621160 ... 914137343: return 30;
  case 914137344 ... 919642961: return 29;
  case 919642962 ... 925138428: return 28;
  case 925138429 ... 930624153: return 27;
  case 930624154 ... 936100540: return 26;
  case 936100541 ... 941567985: return 25;
  case 941567986 ... 947026881: return 24;
  case 947026882 ... 952477613: return 23;
  case 952477614 ... 957920564: return 22;
  case 957920565 ... 963356110: return 21;
  case 963356111 ... 968784624: return 20;
  case 968784625 ... 974206475: return 19;
  case 974206476 ... 979622026: return 18;
  case 979622027 ... 985031638: return 17;
  case 985031639 ... 990435668: return 16;
  case 990435669 ... 995834471: return 15;
  case 995834472 ... 1001228398: return 14;
  case 1001228399 ... 1006617796: return 13;
  case 1006617797 ... 1012003011: return 12;
  case 1012003012 ... 1017384386: return 11;
  case 1017384387 ... 1022762263: return 10;
  case 1022762264 ... 1028136980: return 9;
  case 1028136981 ... 1033508875: return 8;
  case 1033508876 ... 1038878284: return 7;
  case 1038878285 ... 1044245540: return 6;
  case 1044245541 ... 1049610978: return 5;
  case 1049610979 ... 1054974928: return 4;
  case 1054974929 ... 1060337723: return 3;
  case 1060337724 ... 1065699693: return 2;
  case 1065699694 ... 1071061167: return 1;
  case 1071061168 ... 1076422478: return 0;
  case 1076422479 ... 1081783952: return -1;
  case 1081783953 ... 1087145922: return -2;
  case 1087145923 ... 1092508717: return -3;
  case 1092508718 ... 1097872667: return -4;
  case 1097872668 ... 1103238105: return -5;
  case 1103238106 ... 1108605361: return -6;
  case 1108605362 ... 1113974770: return -7;
  case 1113974771 ... 1119346665: return -8;
  case 1119346666 ... 1124721382: return -9;
  case 1124721383 ... 1130099259: return -10;
  case 1130099260 ... 1135480634: return -11;
  case 1135480635 ... 1140865849: return -12;
  case 1140865850 ... 1146255247: return -13;
  case 1146255248 ... 1151649174: return -14;
  case 1151649175 ... 1157047977: return -15;
  case 1157047978 ... 1162452007: return -16;
  case 1162452008 ... 1167861619: return -17;
  case 1167861620 ... 1173277170: return -18;
  case 1173277171 ... 1178699021: return -19;
  case 1178699022 ... 1184127535: return -20;
  case 1184127536 ... 1189563081: return -21;
  case 1189563082 ... 1195006032: return -22;
  case 1195006033 ... 1200456764: return -23;
  case 1200456765 ... 1205915660: return -24;
  case 1205915661 ... 1211383105: return -25;
  case 1211383106 ... 1216859492: return -26;
  case 1216859493 ... 1222345217: return -27;
  case 1222345218 ... 1227840684: return -28;
  case 1227840685 ... 1233346302: return -29;
  case 1233346303 ... 1238862486: return -30;
  case 1238862487 ... 1244389660: return -31;
  case 1244389661 ... 1249928252: return -32;
  case 1249928253 ... 1255478700: return -33;
  case 1255478701 ... 1261041448: return -34;
  case 1261041449 ... 1266616950: return -35;
  case 1266616951 ... 1272205666: return -36;
  case 1272205667 ... 1277808069: return -37;
  case 1277808070 ... 1283424637: return -38;
  case 1283424638 ... 1289055862: return -39;
  case 1289055863 ... 1294702243: return -40;
  case 1294702244 ... 1300364293: return -41;
  case 1300364294 ... 1306042533: return -42;
  case 1306042534 ... 1311737500: return -43;
  case 1311737501 ... 1317449740: return -44;
  case 1317449741 ... 1323179815: return -45;
  case 1323179816 ... 1328928299: return -46;
  case 1328928300 ... 1334695780: return -47;
  case 1334695781 ... 1340482865: return -48;
  case 1340482866 ... 1346290172: return -49;
  case 1346290173 ... 1352118339: return -50;
  case 1352118340 ... 1357968021: return -51;
  case 1357968022 ... 1363839891: return -52;
  case 1363839892 ... 1369734641: return -53;
  case 1369734642 ... 1375652986: return -54;
  case 1375652987 ... 1381595659: return -55;
  case 1381595660 ... 1387563419: return -56;
  case 1387563420 ... 1393557045: return -57;
  case 1393557046 ... 1399577345: return -58;
  case 1399577346 ... 1405625152: return -59;
  case 1405625153 ... 1411701324: return -60;
  case 1411701325 ... 1417806754: return -61;
  case 1417806755 ... 1423942361: return -62;
  case 1423942362 ... 1430109100: return -63;
  case 1430109101 ... 1436307958: return -64;
  case 1436307959 ... 1442539962: return -65;
  case 1442539963 ... 1448806175: return -66;
  case 1448806176 ... 1455107702: return -67;
  case 1455107703 ... 1461445692: return -68;
  case 1461445693 ... 1467821340: return -69;
  case 1467821341 ... 1474235889: return -70;
  case 1474235890 ... 1480690638: return -71;
  case 1480690639 ... 1487186936: return -72;
  case 1487186937 ... 1493726197: return -73;
  case 1493726198 ... 1500309893: return -74;
  case 1500309894 ... 1506939568: return -75;
  case 1506939569 ... 1513616835: return -76;
  case 1513616836 ... 1520343386: return -77;
  case 1520343387 ... 1527120994: return -78;
  case 1527120995 ... 1533951522: return -79;
  case 1533951523 ... 1540836928: return -80;
  case 1540836929 ... 1547779272: return -81;
  case 1547779273 ... 1554780726: return -82;
  case 1554780727 ... 1561843578: return -83;
  case 1561843579 ... 1568970248: return -84;
  case 1568970249 ... 1576163295: return -85;
  case 1576163296 ... 1583425427: return -86;
  case 1583425428 ... 1590759519: return -87;
  case 1590759520 ... 1598168624: return -88;
  case 1598168625 ... 1605655990: return -89;
  case 1605655991 ... 1613225078: return -90;
  case 1613225079 ... 1620879584: return -91;
  case 1620879585 ... 1628623461: return -92;
  case 1628623462 ... 1636460945: return -93;
  case 1636460946 ... 1644396583: return -94;
  case 1644396584 ... 1652435271: return -95;
  case 1652435272 ... 1660582288: return -96;
  case 1660582289 ... 1668843342: return -97;
  case 1668843343 ... 1677224619: return -98;
  case 1677224620 ... 1685732845: return -99;
  case 1685732846 ... 1694375352: return -100;
  case 1694375353 ... 1703160155: return -101;
  case 1703160156 ... 1712096052: return -102;
  case 1712096053 ... 1721192728: return -103;
  case 1721192729 ... 1730460893: return -104;
  case 1730460894 ... 1739912433: return -105;
  case 1739912434 ... 1749560607: return -106;
  case 1749560608 ... 1759420276: return -107;
  case 1759420277 ... 1769508186: return -108;
  case 1769508187 ... 1779843327: return -109;
  case 1779843328 ... 1790447371: return -110;
  case 1790447372 ... 1801345242: return -111;
  case 1801345243 ... 1812565832: return -112;
  case 1812565833 ... 1824142955: return -113;
  case 1824142956 ... 1836116604: return -114;
  case 1836116605 ... 1848534650: return -115;
  case 1848534651 ... 1861455208: return -116;
  case 1861455209 ... 1874949989: return -117;
  case 1874949990 ... 1889109208: return -118;
  case 1889109209 ... 1904049052: return -119;
  case 1904049053 ... 1919923505: return -120;
  case 1919923506 ... 1936944176: return -121;
  case 1936944177 ... 1955415883: return -122;
  case 1955415884 ... 1975806735: return -123;
  case 1975806736 ... 1998905211: return -124;
  case 1998905212 ... 2026249701: return -125;
  case 2026249702 ... 2061814555: return -126;
  case 2061814556 ... 2147483576: return -127;
  case 2147483577 ... 2233152738: return -128;
  case 2233152739 ... 2268717592: return -127;
  case 2268717593 ... 2296062082: return -126;
  case 2296062083 ... 2319160558: return -125;
  case 2319160559 ... 2339551410: return -124;
  case 2339551411 ... 2358023117: return -123;
  case 2358023118 ... 2375043788: return -122;
  case 2375043789 ... 2390918241: return -121;
  case 2390918242 ... 2405858085: return -120;
  case 2405858086 ... 2420017304: return -119;
  case 2420017305 ... 2433512085: return -118;
  case 2433512086 ... 2446432643: return -117;
  case 2446432644 ... 2458850689: return -116;
  case 2458850690 ... 2470824338: return -115;
  case 2470824339 ... 2482401461: return -114;
  case 2482401462 ... 2493622051: return -113;
  case 2493622052 ... 2504519922: return -112;
  case 2504519923 ... 2515123966: return -111;
  case 2515123967 ... 2525459107: return -110;
  case 2525459108 ... 2535547017: return -109;
  case 2535547018 ... 2545406686: return -108;
  case 2545406687 ... 2555054860: return -107;
  case 2555054861 ... 2564506400: return -106;
  case 2564506401 ... 2573774565: return -105;
  case 2573774566 ... 2582871241: return -104;
  case 2582871242 ... 2591807138: return -103;
  case 2591807139 ... 2600591941: return -102;
  case 2600591942 ... 2609234448: return -101;
  case 2609234449 ... 2617742674: return -100;
  case 2617742675 ... 2626123951: return -99;
  case 2626123952 ... 2634385005: return -98;
  case 2634385006 ... 2642532022: return -97;
  case 2642532023 ... 2650570710: return -96;
  case 2650570711 ... 2658506348: return -95;
  case 2658506349 ... 2666343832: return -94;
  case 2666343833 ... 2674087709: return -93;
  case 2674087710 ... 2681742215: return -92;
  case 2681742216 ... 2689311303: return -91;
  case 2689311304 ... 2696798669: return -90;
  case 2696798670 ... 2704207774: return -89;
  case 2704207775 ... 2711541866: return -88;
  case 2711541867 ... 2718803998: return -87;
  case 2718803999 ... 2725997045: return -86;
  case 2725997046 ... 2733123715: return -85;
  case 2733123716 ... 2740186567: return -84;
  case 2740186568 ... 2747188021: return -83;
  case 2747188022 ... 2754130365: return -82;
  case 2754130366 ... 2761015771: return -81;
  case 2761015772 ... 2767846299: return -80;
  case 2767846300 ... 2774623907: return -79;
  case 2774623908 ... 2781350458: return -78;
  case 2781350459 ... 2788027725: return -77;
  case 2788027726 ... 2794657400: return -76;
  case 2794657401 ... 2801241096: return -75;
  case 2801241097 ... 2807780357: return -74;
  case 2807780358 ... 2814276655: return -73;
  case 2814276656 ... 2820731404: return -72;
  case 2820731405 ... 2827145953: return -71;
  case 2827145954 ... 2833521601: return -70;
  case 2833521602 ... 2839859591: return -69;
  case 2839859592 ... 2846161118: return -68;
  case 2846161119 ... 2852427331: return -67;
  case 2852427332 ... 2858659335: return -66;
  case 2858659336 ... 2864858193: return -65;
  case 2864858194 ... 2871024932: return -64;
  case 2871024933 ... 2877160539: return -63;
  case 2877160540 ... 2883265969: return -62;
  case 2883265970 ... 2889342141: return -61;
  case 2889342142 ... 2895389948: return -60;
  case 2895389949 ... 2901410248: return -59;
  case 2901410249 ... 2907403874: return -58;
  case 2907403875 ... 2913371634: return -57;
  case 2913371635 ... 2919314307: return -56;
  case 2919314308 ... 2925232652: return -55;
  case 2925232653 ... 2931127402: return -54;
  case 2931127403 ... 2936999272: return -53;
  case 2936999273 ... 2942848954: return -52;
  case 2942848955 ... 2948677121: return -51;
  case 2948677122 ... 2954484428: return -50;
  case 2954484429 ... 2960271513: return -49;
  case 2960271514 ... 2966038994: return -48;
  case 2966038995 ... 2971787478: return -47;
  case 2971787479 ... 2977517553: return -46;
  case 2977517554 ... 2983229793: return -45;
  case 2983229794 ... 2988924760: return -44;
  case 2988924761 ... 2994603000: return -43;
  case 2994603001 ... 3000265050: return -42;
  case 3000265051 ... 3005911431: return -41;
  case 3005911432 ... 3011542656: return -40;
  case 3011542657 ... 3017159224: return -39;
  case 3017159225 ... 3022761627: return -38;
  case 3022761628 ... 3028350343: return -37;
  case 3028350344 ... 3033925845: return -36;
  case 3033925846 ... 3039488593: return -35;
  case 3039488594 ... 3045039041: return -34;
  case 3045039042 ... 3050577633: return -33;
  case 3050577634 ... 3056104807: return -32;
  case 3056104808 ... 3061620991: return -31;
  case 3061620992 ... 3067126609: return -30;
  case 3067126610 ... 3072622076: return -29;
  case 3072622077 ... 3078107801: return -28;
  case 3078107802 ... 3083584188: return -27;
  case 3083584189 ... 3089051633: return -26;
  case 3089051634 ... 3094510529: return -25;
  case 3094510530 ... 3099961261: return -24;
  case 3099961262 ... 3105404212: return -23;
  case 3105404213 ... 3110839758: return -22;
  case 3110839759 ... 3116268272: return -21;
  case 3116268273 ... 3121690123: return -20;
  case 3121690124 ... 3127105674: return -19;
  case 3127105675 ... 3132515286: return -18;
  case 3132515287 ... 3137919316: return -17;
  case 3137919317 ... 3143318119: return -16;
  case 3143318120 ... 3148712046: return -15;
  case 3148712047 ... 3154101444: return -14;
  case 3154101445 ... 3159486659: return -13;
  case 3159486660 ... 3164868034: return -12;
  case 3164868035 ... 3170245911: return -11;
  case 3170245912 ... 3175620628: return -10;
  case 3175620629 ... 3180992523: return -9;
  case 3180992524 ... 3186361932: return -8;
  case 3186361933 ... 3191729188: return -7;
  case 3191729189 ... 3197094626: return -6;
  case 3197094627 ... 3202458576: return -5;
  case 3202458577 ... 3207821371: return -4;
  case 3207821372 ... 3213183341: return -3;
  case 3213183342 ... 3218544815: return -2;
  case 3218544816 ... 3223906126: return -1;
  case 3223906127 ... 3229267600: return 0;
  case 3229267601 ... 3234629570: return 1;
  case 3234629571 ... 3239992365: return 2;
  case 3239992366 ... 3245356315: return 3;
  case 3245356316 ... 3250721753: return 4;
  case 3250721754 ... 3256089009: return 5;
  case 3256089010 ... 3261458418: return 6;
  case 3261458419 ... 3266830313: return 7;
  case 3266830314 ... 3272205030: return 8;
  case 3272205031 ... 3277582907: return 9;
  case 3277582908 ... 3282964282: return 10;
  case 3282964283 ... 3288349497: return 11;
  case 3288349498 ... 3293738895: return 12;
  case 3293738896 ... 3299132822: return 13;
  case 3299132823 ... 3304531625: return 14;
  case 3304531626 ... 3309935655: return 15;
  case 3309935656 ... 3315345267: return 16;
  case 3315345268 ... 3320760818: return 17;
  case 3320760819 ... 3326182669: return 18;
  case 3326182670 ... 3331611183: return 19;
  case 3331611184 ... 3337046729: return 20;
  case 3337046730 ... 3342489680: return 21;
  case 3342489681 ... 3347940412: return 22;
  case 3347940413 ... 3353399308: return 23;
  case 3353399309 ... 3358866753: return 24;
  case 3358866754 ... 3364343140: return 25;
  case 3364343141 ... 3369828865: return 26;
  case 3369828866 ... 3375324332: return 27;
  case 3375324333 ... 3380829950: return 28;
  case 3380829951 ... 3386346134: return 29;
  case 3386346135 ... 3391873308: return 30;
  case 3391873309 ... 3397411900: return 31;
  case 3397411901 ... 3402962348: return 32;
  case 3402962349 ... 3408525096: return 33;
  case 3408525097 ... 3414100598: return 34;
  case 3414100599 ... 3419689314: return 35;
  case 3419689315 ... 3425291717: return 36;
  case 3425291718 ... 3430908285: return 37;
  case 3430908286 ... 3436539510: return 38;
  case 3436539511 ... 3442185891: return 39;
  case 3442185892 ... 3447847941: return 40;
  case 3447847942 ... 3453526181: return 41;
  case 3453526182 ... 3459221148: return 42;
  case 3459221149 ... 3464933388: return 43;
  case 3464933389 ... 3470663463: return 44;
  case 3470663464 ... 3476411947: return 45;
  case 3476411948 ... 3482179428: return 46;
  case 3482179429 ... 3487966513: return 47;
  case 3487966514 ... 3493773820: return 48;
  case 3493773821 ... 3499601987: return 49;
  case 3499601988 ... 3505451669: return 50;
  case 3505451670 ... 3511323539: return 51;
  case 3511323540 ... 3517218289: return 52;
  case 3517218290 ... 3523136634: return 53;
  case 3523136635 ... 3529079307: return 54;
  case 3529079308 ... 3535047067: return 55;
  case 3535047068 ... 3541040693: return 56;
  case 3541040694 ... 3547060993: return 57;
  case 3547060994 ... 3553108800: return 58;
  case 3553108801 ... 3559184972: return 59;
  case 3559184973 ... 3565290402: return 60;
  case 3565290403 ... 3571426009: return 61;
  case 3571426010 ... 3577592748: return 62;
  case 3577592749 ... 3583791606: return 63;
  case 3583791607 ... 3590023610: return 64;
  case 3590023611 ... 3596289823: return 65;
  case 3596289824 ... 3602591350: return 66;
  case 3602591351 ... 3608929340: return 67;
  case 3608929341 ... 3615304988: return 68;
  case 3615304989 ... 3621719537: return 69;
  case 3621719538 ... 3628174286: return 70;
  case 3628174287 ... 3634670584: return 71;
  case 3634670585 ... 3641209845: return 72;
  case 3641209846 ... 3647793541: return 73;
  case 3647793542 ... 3654423216: return 74;
  case 3654423217 ... 3661100483: return 75;
  case 3661100484 ... 3667827034: return 76;
  case 3667827035 ... 3674604642: return 77;
  case 3674604643 ... 3681435170: return 78;
  case 3681435171 ... 3688320576: return 79;
  case 3688320577 ... 3695262920: return 80;
  case 3695262921 ... 3702264374: return 81;
  case 3702264375 ... 3709327226: return 82;
  case 3709327227 ... 3716453896: return 83;
  case 3716453897 ... 3723646943: return 84;
  case 3723646944 ... 3730909075: return 85;
  case 3730909076 ... 3738243167: return 86;
  case 3738243168 ... 3745652272: return 87;
  case 3745652273 ... 3753139638: return 88;
  case 3753139639 ... 3760708726: return 89;
  case 3760708727 ... 3768363232: return 90;
  case 3768363233 ... 3776107109: return 91;
  case 3776107110 ... 3783944593: return 92;
  case 3783944594 ... 3791880231: return 93;
  case 3791880232 ... 3799918919: return 94;
  case 3799918920 ... 3808065936: return 95;
  case 3808065937 ... 3816326990: return 96;
  case 3816326991 ... 3824708267: return 97;
  case 3824708268 ... 3833216493: return 98;
  case 3833216494 ... 3841859000: return 99;
  case 3841859001 ... 3850643803: return 100;
  case 3850643804 ... 3859579700: return 101;
  case 3859579701 ... 3868676376: return 102;
  case 3868676377 ... 3877944541: return 103;
  case 3877944542 ... 3887396081: return 104;
  case 3887396082 ... 3897044255: return 105;
  case 3897044256 ... 3906903924: return 106;
  case 3906903925 ... 3916991834: return 107;
  case 3916991835 ... 3927326975: return 108;
  case 3927326976 ... 3937931019: return 109;
  case 3937931020 ... 3948828890: return 110;
  case 3948828891 ... 3960049480: return 111;
  case 3960049481 ... 3971626603: return 112;
  case 3971626604 ... 3983600252: return 113;
  case 3983600253 ... 3996018298: return 114;
  case 3996018299 ... 4008938856: return 115;
  case 4008938857 ... 4022433637: return 116;
  case 4022433638 ... 4036592856: return 117;
  case 4036592857 ... 4051532700: return 118;
  case 4051532701 ... 4067407153: return 119;
  case 4067407154 ... 4084427824: return 120;
  case 4084427825 ... 4102899531: return 121;
  case 4102899532 ... 4123290383: return 122;
  case 4123290384 ... 4146388859: return 123;
  case 4146388860 ... 4173733349: return 124;
  case 4173733350 ... 4209298203: return 125;
  case 4209298204 ... 4294967295: return 126;
  default: return 127;
  }
}

void report_params() {
  Serial.print("f0: ");
  Serial.print(f0);
  Serial.print(", v0_tgt: ");
  Serial.print(5.*v0_tgt/fixed_volume_multiplier);  // Amplitudes are normalized to 1.0 max, which corresponds to 5.0v.
  Serial.print(", dw0_tgt: ");
  Serial.println(dw0_tgt);
  Serial.flush();

  Serial.print("f1: ");
  Serial.print(f1);
  Serial.print(", v1_tgt: ");
  Serial.print(5.*v1_tgt/fixed_volume_multiplier);
  Serial.print(", dw1_tgt: ");
  Serial.println(dw1_tgt);
  Serial.flush();
}

void setup() {
  // Setup output pins.
  pinMode(PWM_1, OUTPUT); // Enable PWM output pin 3. Outputs channel a sine wave.
  pinMode(PWM_2, OUTPUT); // Enable PWM output pin 5. Outputs channel b sine wave
  pinMode(PWM_3, OUTPUT); // Enable PWM output pin 6. Outputs a+b.
  pinMode(PWM_4, OUTPUT); // Enable PWM output pin 9. Outputs a-b.
  pinMode(LED_PIN, OUTPUT); // Enable output on LED pin 13. For "alive" blinkage.
  // Setup high-speed PWM on timer 2 and PWM_1-4 pins.
  OpenTimer2(T2_ON | T2_PS_1_1, dac_resolution);
  OpenOC1(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  OpenOC2(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  OpenOC3(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  OpenOC4(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  // Setup waveform generation.
  ConfigIntTimer1(T1_INT_ON | T1_INT_PRIOR_3);
  // Setup high-speed PWM on timer 2 and PWM_1-4 pins.
  OpenTimer1(T1_ON | T1_PS_1_1, wavegen_interrupt_period);
  // Open serial port.
  Serial.begin(serial_baud);

  report_params();
}

/*
Main loop in non-interrupt thread.
Blinks "alive" LED,
checks for new user-requested frequencies and volumes,
and gradually adjusts actual frequencies and volumes to match request.
*/
void loop() {
  // LED "alive" blinkage.
  unsigned long now = millis();
  if (next_blink_time < now) {
    next_blink_time += blink_period_ms;
    // Toggle LED.
    if (led_state) { led_state = 0; }
    else { led_state = 1; }
    digitalWrite(LED_PIN, led_state);
  }
  // Check for new user-requested frequencies and volumes.
  if (Serial.available() > 0) {
    f0 = Serial.parseFloat(); // Signal 'a' frequency.
    // Amplitudes are normalized to 1.0 max, which corresponds to 5.0v.
    v0_tgt = fixed_volume_multiplier*Serial.parseFloat()/5.; // Signal 'a' volume.
    f1 = Serial.parseFloat(); // Signal 'b' frequency.
    v1_tgt = fixed_volume_multiplier*Serial.parseFloat()/5.; // Signal 'b' volume.
    // Determine target phase differential to generate requested frequencies.
    dw0_tgt = dw_for_freq(f0); // Signal 'a' phase differential for requested frequency.
    dw1_tgt = dw_for_freq(f1); // Signal 'b' phase differential for requested frequency.
    
    report_params();
  }
  // Gradually adjust actual volumes to match targets.
  if (1e-9 < v0_tgt - v0) { v0 += fminf(dv, v0_tgt - v0); }
  else if (1e-9 < v0 - v0_tgt) { v0 -= fminf(dv, v0 - v0_tgt); }
  else { v0 = v0_tgt; }
  if (1e-9 < v1_tgt - v1) { v1 += fminf(dv, v1_tgt - v1); }
  else if (1e-9 < v1 - v1_tgt) { v1 -= fminf(dv, v1 - v1_tgt); }
  else { v1 = v1_tgt; }
  // By adjusting phase differentials, gradually adjust actual frequencies to match targets.
  if (dw0 < dw0_tgt) { dw0 += min(ddw, dw0_tgt - dw0); }
  else if (dw0_tgt < dw0) { dw0 -= min(ddw, dw0 - dw0_tgt); }
  if (dw1 < dw1_tgt) { dw1 += min(ddw, dw1_tgt - dw1); }
  else if (dw1_tgt < dw1) { dw1 -= min(ddw, dw1 - dw1_tgt); }
}

/* Interrupt handler to generate waveform. */
extern "C" {
void __ISR(_TIMER_1_VECTOR,ipl3) wavegen(void) {
  int n0=0, n1=0, np=0, nm=0;
  // Adjust wave phases.
  // When we use 2^32 as fixed_int_multiplier, the % operation above is equivalent to integer overflow.
//  w0 = (w0 + dw0) % fixed_int_multiplier;
//  w1 = (w1 + dw1) % fixed_int_multiplier;
  w0 = w0 + dw0;
  w1 = w1 + dw1;
  // Adjust waveform amplitudes at adjusted phases.
  n0 = v0*cosine_amplitude(w0) >> 8; // This bitshift is equivalent to divide by fixed_volume_multiplier.
  n1 = v1*cosine_amplitude(w1) >> 8;
  // Compute sum and difference signals.
  np = (n0 + n1 + 1) >> 1;
  nm = (n0 - n1 + 1) >> 1;
  // Update PWM signals.
  SetDCOC1PWM(n0 + waveform_zero_offset);
  SetDCOC2PWM(n1 + waveform_zero_offset);
  SetDCOC3PWM(np + waveform_zero_offset);
  SetDCOC4PWM(nm + waveform_zero_offset);
  mT1ClearIntFlag();
}
}
