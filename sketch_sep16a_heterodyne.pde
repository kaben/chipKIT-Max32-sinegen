/*
This is a two-channel waveform generator for the Arduino-alike Digilent
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
applied to the output signals. The modulating (co)sine signals have a Nyquist
frequency of about 52 kHz. Minimum frequency is about 0.0002

Frequencies are specified in Hertz with precision of approximately 0.0002 Hz.
Amplitudes are specified in Volts with precision of approximately 0.04 V.

The wave generator will smoothly transition from old to new frequencies and
volumes with no discontinuities, which prevents "click" sounds during transition.

Regarding accuracy:
When I compare a generated 440.0 Hz signal with my 440 Hz tuning fork, agreement
is within about 0.5 Hz. I think this indicates that my tuning fork is slightly
out of tune.

Copyright 2013 by Kaben Nanlohy. All rights reserved.
*/

#include <peripheral/timer.h>
#include <peripheral/outcompare.h>

/* Wave generator parameters. */
const unsigned int dac_resolution = 256; // Don't change.
const unsigned int waveform_zero_offset = 128; // Don't change.
const unsigned int fixed_int_multiplier = 1000000000; // Don't change.
const unsigned int wavegen_interrupt_period = 768; // Multiple of 256. 768 appears to be minimum.

/* Output pin assignments. */
const unsigned int PWM_1 = 3; // OC1 PWM output - don't change
const unsigned int PWM_2 = 5; // OC2 PWM output - don't change
const unsigned int PWM_3 = 6; // OC3 PWM output - don't change
const unsigned int PWM_4 = 9; // OC3 PWM output - don't change
const unsigned int LED_PIN = 13; // On-board LED - don't change

/* Frequency state. */
float f0 = 1000., f1 = 1000.;

/* Phase state. */
unsigned int w0 = 0, w1 = 0;
// Target phase differentials corresponding to above frequencies.
unsigned int dw0_tgt = dw_for_freq(f0), dw1_tgt = dw_for_freq(f1);
// Actual phase differentials.
unsigned int dw0 = 0, dw1 = 0;
// Phase "second-differentials" for gradual frequency adjustment.
unsigned int ddw = fixed_int_multiplier/(2*dac_resolution);

/* Volume state. */
// Target volumes.
float v0_tgt = 1., v1_tgt = 1.;
// Actual volumes.
float v0 = 0., v1 = 0.;
// Differential for gradual volume adjustment.
float dv = 0.5/dac_resolution;

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
  case 0 ... 19946388: return 127;
  case 19946389 ... 28226976: return 126;
  case 28226977 ... 34593611: return 125;
  case 34593612 ... 39971644: return 124;
  case 39971645 ... 44719259: return 123;
  case 44719260 ... 49020039: return 122;
  case 49020040 ... 52982973: return 121;
  case 52982974 ... 56679032: return 120;
  case 56679033 ... 60157485: return 119;
  case 60157486 ... 63454185: return 118;
  case 63454186 ... 66596184: return 117;
  case 66596185 ... 69604486: return 116;
  case 69604487 ... 72495787: return 115;
  case 72495788 ... 75283620: return 114;
  case 75283621 ... 77979129: return 113;
  case 77979130 ... 80591626: return 112;
  case 80591627 ... 83128984: return 111;
  case 83128985 ... 85597931: return 110;
  case 85597932 ... 88004268: return 109;
  case 88004269 ... 90353043: return 108;
  case 90353044 ... 92648676: return 107;
  case 92648677 ... 94895066: return 106;
  case 94895067 ... 97095675: return 105;
  case 97095676 ... 99253587: return 104;
  case 99253588 ... 101371572: return 103;
  case 101371573 ... 103452123: return 102;
  case 103452124 ... 105497494: return 101;
  case 105497495 ... 107509735: return 100;
  case 107509736 ... 109490711: return 99;
  case 109490712 ... 111442129: return 98;
  case 111442130 ... 113365555: return 97;
  case 113365556 ... 115262430: return 96;
  case 115262431 ... 117134083: return 95;
  case 117134084 ... 118981743: return 94;
  case 118981744 ... 120806549: return 93;
  case 120806550 ... 122609561: return 92;
  case 122609562 ... 124391765: return 91;
  case 124391766 ... 126154081: return 90;
  case 126154082 ... 127897369: return 89;
  case 127897370 ... 129622435: return 88;
  case 129622436 ... 131330037: return 87;
  case 131330038 ... 133020884: return 86;
  case 133020885 ... 134695645: return 85;
  case 134695646 ... 136354953: return 84;
  case 136354954 ... 137999401: return 83;
  case 137999402 ... 139629554: return 82;
  case 139629555 ... 141245944: return 81;
  case 141245945 ... 142849078: return 80;
  case 142849079 ... 144439434: return 79;
  case 144439435 ... 146017469: return 78;
  case 146017470 ... 147583616: return 77;
  case 147583617 ... 149138289: return 76;
  case 149138290 ... 150681880: return 75;
  case 150681881 ... 152214766: return 74;
  case 152214767 ... 153737307: return 73;
  case 153737308 ... 155249844: return 72;
  case 155249845 ... 156752707: return 71;
  case 156752708 ... 158246211: return 70;
  case 158246212 ... 159730657: return 69;
  case 159730658 ... 161206335: return 68;
  case 161206336 ... 162673524: return 67;
  case 162673525 ... 164132490: return 66;
  case 164132491 ... 165583492: return 65;
  case 165583493 ... 167026776: return 64;
  case 167026777 ... 168462582: return 63;
  case 168462583 ... 169891139: return 62;
  case 169891140 ... 171312670: return 61;
  case 171312671 ... 172727389: return 60;
  case 172727390 ... 174135504: return 59;
  case 174135505 ... 175537214: return 58;
  case 175537215 ... 176932714: return 57;
  case 176932715 ... 178322192: return 56;
  case 178322193 ... 179705828: return 55;
  case 179705829 ... 181083800: return 54;
  case 181083801 ... 182456279: return 53;
  case 182456280 ... 183823430: return 52;
  case 183823431 ... 185185415: return 51;
  case 185185416 ... 186542391: return 50;
  case 186542392 ... 187894510: return 49;
  case 187894511 ... 189241921: return 48;
  case 189241922 ... 190584767: return 47;
  case 190584768 ... 191923190: return 46;
  case 191923191 ... 193257327: return 45;
  case 193257328 ... 194587312: return 44;
  case 194587313 ... 195913275: return 43;
  case 195913276 ... 197235343: return 42;
  case 197235344 ... 198553642: return 41;
  case 198553643 ... 199868292: return 40;
  case 199868293 ... 201179414: return 39;
  case 201179415 ... 202487123: return 38;
  case 202487124 ... 203791534: return 37;
  case 203791535 ... 205092758: return 36;
  case 205092759 ... 206390906: return 35;
  case 206390907 ... 207686084: return 34;
  case 207686085 ... 208978399: return 33;
  case 208978400 ... 210267953: return 32;
  case 210267954 ... 211554848: return 31;
  case 211554849 ... 212839185: return 30;
  case 212839186 ... 214121061: return 29;
  case 214121062 ... 215400575: return 28;
  case 215400576 ... 216677819: return 27;
  case 216677820 ... 217952890: return 26;
  case 217952891 ... 219225879: return 25;
  case 219225880 ... 220496877: return 24;
  case 220496878 ... 221765975: return 23;
  case 221765976 ... 223033260: return 22;
  case 223033261 ... 224298822: return 21;
  case 224298823 ... 225562747: return 20;
  case 225562748 ... 226825119: return 19;
  case 226825120 ... 228086026: return 18;
  case 228086027 ... 229345549: return 17;
  case 229345550 ... 230603773: return 16;
  case 230603774 ... 231860780: return 15;
  case 231860781 ... 233116651: return 14;
  case 233116652 ... 234371468: return 13;
  case 234371469 ... 235625311: return 12;
  case 235625312 ... 236878260: return 11;
  case 236878261 ... 238130395: return 10;
  case 238130396 ... 239381794: return 9;
  case 239381795 ... 240632535: return 8;
  case 240632536 ... 241882698: return 7;
  case 241882699 ... 243132360: return 6;
  case 243132361 ... 244381598: return 5;
  case 244381599 ... 245630490: return 4;
  case 245630491 ... 246879113: return 3;
  case 246879114 ... 248127544: return 2;
  case 248127545 ... 249375860: return 1;
  case 249375861 ... 250624137: return 0;
  case 250624138 ... 251872453: return -1;
  case 251872454 ... 253120884: return -2;
  case 253120885 ... 254369507: return -3;
  case 254369508 ... 255618399: return -4;
  case 255618400 ... 256867637: return -5;
  case 256867638 ... 258117299: return -6;
  case 258117300 ... 259367462: return -7;
  case 259367463 ... 260618203: return -8;
  case 260618204 ... 261869602: return -9;
  case 261869603 ... 263121737: return -10;
  case 263121738 ... 264374686: return -11;
  case 264374687 ... 265628529: return -12;
  case 265628530 ... 266883346: return -13;
  case 266883347 ... 268139217: return -14;
  case 268139218 ... 269396224: return -15;
  case 269396225 ... 270654448: return -16;
  case 270654449 ... 271913971: return -17;
  case 271913972 ... 273174878: return -18;
  case 273174879 ... 274437250: return -19;
  case 274437251 ... 275701175: return -20;
  case 275701176 ... 276966737: return -21;
  case 276966738 ... 278234022: return -22;
  case 278234023 ... 279503120: return -23;
  case 279503121 ... 280774118: return -24;
  case 280774119 ... 282047107: return -25;
  case 282047108 ... 283322178: return -26;
  case 283322179 ... 284599422: return -27;
  case 284599423 ... 285878936: return -28;
  case 285878937 ... 287160812: return -29;
  case 287160813 ... 288445149: return -30;
  case 288445150 ... 289732044: return -31;
  case 289732045 ... 291021598: return -32;
  case 291021599 ... 292313913: return -33;
  case 292313914 ... 293609091: return -34;
  case 293609092 ... 294907239: return -35;
  case 294907240 ... 296208463: return -36;
  case 296208464 ... 297512874: return -37;
  case 297512875 ... 298820583: return -38;
  case 298820584 ... 300131705: return -39;
  case 300131706 ... 301446355: return -40;
  case 301446356 ... 302764654: return -41;
  case 302764655 ... 304086722: return -42;
  case 304086723 ... 305412685: return -43;
  case 305412686 ... 306742670: return -44;
  case 306742671 ... 308076807: return -45;
  case 308076808 ... 309415230: return -46;
  case 309415231 ... 310758076: return -47;
  case 310758077 ... 312105487: return -48;
  case 312105488 ... 313457606: return -49;
  case 313457607 ... 314814582: return -50;
  case 314814583 ... 316176567: return -51;
  case 316176568 ... 317543718: return -52;
  case 317543719 ... 318916197: return -53;
  case 318916198 ... 320294169: return -54;
  case 320294170 ... 321677805: return -55;
  case 321677806 ... 323067283: return -56;
  case 323067284 ... 324462783: return -57;
  case 324462784 ... 325864493: return -58;
  case 325864494 ... 327272608: return -59;
  case 327272609 ... 328687327: return -60;
  case 328687328 ... 330108858: return -61;
  case 330108859 ... 331537415: return -62;
  case 331537416 ... 332973221: return -63;
  case 332973222 ... 334416505: return -64;
  case 334416506 ... 335867507: return -65;
  case 335867508 ... 337326473: return -66;
  case 337326474 ... 338793662: return -67;
  case 338793663 ... 340269340: return -68;
  case 340269341 ... 341753786: return -69;
  case 341753787 ... 343247290: return -70;
  case 343247291 ... 344750153: return -71;
  case 344750154 ... 346262690: return -72;
  case 346262691 ... 347785231: return -73;
  case 347785232 ... 349318117: return -74;
  case 349318118 ... 350861708: return -75;
  case 350861709 ... 352416381: return -76;
  case 352416382 ... 353982528: return -77;
  case 353982529 ... 355560563: return -78;
  case 355560564 ... 357150919: return -79;
  case 357150920 ... 358754053: return -80;
  case 358754054 ... 360370443: return -81;
  case 360370444 ... 362000596: return -82;
  case 362000597 ... 363645044: return -83;
  case 363645045 ... 365304352: return -84;
  case 365304353 ... 366979113: return -85;
  case 366979114 ... 368669960: return -86;
  case 368669961 ... 370377562: return -87;
  case 370377563 ... 372102628: return -88;
  case 372102629 ... 373845916: return -89;
  case 373845917 ... 375608232: return -90;
  case 375608233 ... 377390436: return -91;
  case 377390437 ... 379193448: return -92;
  case 379193449 ... 381018254: return -93;
  case 381018255 ... 382865914: return -94;
  case 382865915 ... 384737567: return -95;
  case 384737568 ... 386634442: return -96;
  case 386634443 ... 388557868: return -97;
  case 388557869 ... 390509286: return -98;
  case 390509287 ... 392490262: return -99;
  case 392490263 ... 394502503: return -100;
  case 394502504 ... 396547874: return -101;
  case 396547875 ... 398628425: return -102;
  case 398628426 ... 400746410: return -103;
  case 400746411 ... 402904322: return -104;
  case 402904323 ... 405104931: return -105;
  case 405104932 ... 407351321: return -106;
  case 407351322 ... 409646954: return -107;
  case 409646955 ... 411995729: return -108;
  case 411995730 ... 414402066: return -109;
  case 414402067 ... 416871013: return -110;
  case 416871014 ... 419408371: return -111;
  case 419408372 ... 422020868: return -112;
  case 422020869 ... 424716377: return -113;
  case 424716378 ... 427504210: return -114;
  case 427504211 ... 430395511: return -115;
  case 430395512 ... 433403813: return -116;
  case 433403814 ... 436545812: return -117;
  case 436545813 ... 439842512: return -118;
  case 439842513 ... 443320965: return -119;
  case 443320966 ... 447017024: return -120;
  case 447017025 ... 450979958: return -121;
  case 450979959 ... 455280738: return -122;
  case 455280739 ... 460028353: return -123;
  case 460028354 ... 465406386: return -124;
  case 465406387 ... 471773021: return -125;
  case 471773022 ... 480053609: return -126;
  case 480053610 ... 499999982: return -127;
  case 499999983 ... 519946389: return -128;
  case 519946390 ... 528226977: return -127;
  case 528226978 ... 534593612: return -126;
  case 534593613 ... 539971645: return -125;
  case 539971646 ... 544719260: return -124;
  case 544719261 ... 549020040: return -123;
  case 549020041 ... 552982974: return -122;
  case 552982975 ... 556679033: return -121;
  case 556679034 ... 560157486: return -120;
  case 560157487 ... 563454186: return -119;
  case 563454187 ... 566596185: return -118;
  case 566596186 ... 569604487: return -117;
  case 569604488 ... 572495788: return -116;
  case 572495789 ... 575283621: return -115;
  case 575283622 ... 577979130: return -114;
  case 577979131 ... 580591627: return -113;
  case 580591628 ... 583128985: return -112;
  case 583128986 ... 585597932: return -111;
  case 585597933 ... 588004269: return -110;
  case 588004270 ... 590353044: return -109;
  case 590353045 ... 592648677: return -108;
  case 592648678 ... 594895067: return -107;
  case 594895068 ... 597095676: return -106;
  case 597095677 ... 599253588: return -105;
  case 599253589 ... 601371573: return -104;
  case 601371574 ... 603452124: return -103;
  case 603452125 ... 605497495: return -102;
  case 605497496 ... 607509736: return -101;
  case 607509737 ... 609490712: return -100;
  case 609490713 ... 611442130: return -99;
  case 611442131 ... 613365556: return -98;
  case 613365557 ... 615262431: return -97;
  case 615262432 ... 617134084: return -96;
  case 617134085 ... 618981744: return -95;
  case 618981745 ... 620806550: return -94;
  case 620806551 ... 622609562: return -93;
  case 622609563 ... 624391766: return -92;
  case 624391767 ... 626154082: return -91;
  case 626154083 ... 627897370: return -90;
  case 627897371 ... 629622436: return -89;
  case 629622437 ... 631330038: return -88;
  case 631330039 ... 633020885: return -87;
  case 633020886 ... 634695646: return -86;
  case 634695647 ... 636354954: return -85;
  case 636354955 ... 637999402: return -84;
  case 637999403 ... 639629555: return -83;
  case 639629556 ... 641245945: return -82;
  case 641245946 ... 642849079: return -81;
  case 642849080 ... 644439435: return -80;
  case 644439436 ... 646017470: return -79;
  case 646017471 ... 647583617: return -78;
  case 647583618 ... 649138290: return -77;
  case 649138291 ... 650681881: return -76;
  case 650681882 ... 652214767: return -75;
  case 652214768 ... 653737308: return -74;
  case 653737309 ... 655249845: return -73;
  case 655249846 ... 656752708: return -72;
  case 656752709 ... 658246212: return -71;
  case 658246213 ... 659730658: return -70;
  case 659730659 ... 661206336: return -69;
  case 661206337 ... 662673525: return -68;
  case 662673526 ... 664132491: return -67;
  case 664132492 ... 665583493: return -66;
  case 665583494 ... 667026777: return -65;
  case 667026778 ... 668462583: return -64;
  case 668462584 ... 669891140: return -63;
  case 669891141 ... 671312671: return -62;
  case 671312672 ... 672727390: return -61;
  case 672727391 ... 674135505: return -60;
  case 674135506 ... 675537215: return -59;
  case 675537216 ... 676932715: return -58;
  case 676932716 ... 678322193: return -57;
  case 678322194 ... 679705829: return -56;
  case 679705830 ... 681083801: return -55;
  case 681083802 ... 682456280: return -54;
  case 682456281 ... 683823431: return -53;
  case 683823432 ... 685185416: return -52;
  case 685185417 ... 686542392: return -51;
  case 686542393 ... 687894511: return -50;
  case 687894512 ... 689241922: return -49;
  case 689241923 ... 690584768: return -48;
  case 690584769 ... 691923191: return -47;
  case 691923192 ... 693257328: return -46;
  case 693257329 ... 694587313: return -45;
  case 694587314 ... 695913276: return -44;
  case 695913277 ... 697235344: return -43;
  case 697235345 ... 698553643: return -42;
  case 698553644 ... 699868293: return -41;
  case 699868294 ... 701179415: return -40;
  case 701179416 ... 702487124: return -39;
  case 702487125 ... 703791535: return -38;
  case 703791536 ... 705092759: return -37;
  case 705092760 ... 706390907: return -36;
  case 706390908 ... 707686085: return -35;
  case 707686086 ... 708978400: return -34;
  case 708978401 ... 710267954: return -33;
  case 710267955 ... 711554849: return -32;
  case 711554850 ... 712839186: return -31;
  case 712839187 ... 714121062: return -30;
  case 714121063 ... 715400576: return -29;
  case 715400577 ... 716677820: return -28;
  case 716677821 ... 717952891: return -27;
  case 717952892 ... 719225880: return -26;
  case 719225881 ... 720496878: return -25;
  case 720496879 ... 721765976: return -24;
  case 721765977 ... 723033261: return -23;
  case 723033262 ... 724298823: return -22;
  case 724298824 ... 725562748: return -21;
  case 725562749 ... 726825120: return -20;
  case 726825121 ... 728086027: return -19;
  case 728086028 ... 729345550: return -18;
  case 729345551 ... 730603774: return -17;
  case 730603775 ... 731860781: return -16;
  case 731860782 ... 733116652: return -15;
  case 733116653 ... 734371469: return -14;
  case 734371470 ... 735625312: return -13;
  case 735625313 ... 736878261: return -12;
  case 736878262 ... 738130396: return -11;
  case 738130397 ... 739381795: return -10;
  case 739381796 ... 740632536: return -9;
  case 740632537 ... 741882699: return -8;
  case 741882700 ... 743132361: return -7;
  case 743132362 ... 744381599: return -6;
  case 744381600 ... 745630491: return -5;
  case 745630492 ... 746879114: return -4;
  case 746879115 ... 748127545: return -3;
  case 748127546 ... 749375861: return -2;
  case 749375862 ... 750624138: return -1;
  case 750624139 ... 751872454: return 0;
  case 751872455 ... 753120885: return 1;
  case 753120886 ... 754369508: return 2;
  case 754369509 ... 755618400: return 3;
  case 755618401 ... 756867638: return 4;
  case 756867639 ... 758117300: return 5;
  case 758117301 ... 759367463: return 6;
  case 759367464 ... 760618204: return 7;
  case 760618205 ... 761869603: return 8;
  case 761869604 ... 763121738: return 9;
  case 763121739 ... 764374687: return 10;
  case 764374688 ... 765628530: return 11;
  case 765628531 ... 766883347: return 12;
  case 766883348 ... 768139218: return 13;
  case 768139219 ... 769396225: return 14;
  case 769396226 ... 770654449: return 15;
  case 770654450 ... 771913972: return 16;
  case 771913973 ... 773174879: return 17;
  case 773174880 ... 774437251: return 18;
  case 774437252 ... 775701176: return 19;
  case 775701177 ... 776966738: return 20;
  case 776966739 ... 778234023: return 21;
  case 778234024 ... 779503121: return 22;
  case 779503122 ... 780774119: return 23;
  case 780774120 ... 782047108: return 24;
  case 782047109 ... 783322179: return 25;
  case 783322180 ... 784599423: return 26;
  case 784599424 ... 785878937: return 27;
  case 785878938 ... 787160813: return 28;
  case 787160814 ... 788445150: return 29;
  case 788445151 ... 789732045: return 30;
  case 789732046 ... 791021599: return 31;
  case 791021600 ... 792313914: return 32;
  case 792313915 ... 793609092: return 33;
  case 793609093 ... 794907240: return 34;
  case 794907241 ... 796208464: return 35;
  case 796208465 ... 797512875: return 36;
  case 797512876 ... 798820584: return 37;
  case 798820585 ... 800131706: return 38;
  case 800131707 ... 801446356: return 39;
  case 801446357 ... 802764655: return 40;
  case 802764656 ... 804086723: return 41;
  case 804086724 ... 805412686: return 42;
  case 805412687 ... 806742671: return 43;
  case 806742672 ... 808076808: return 44;
  case 808076809 ... 809415231: return 45;
  case 809415232 ... 810758077: return 46;
  case 810758078 ... 812105488: return 47;
  case 812105489 ... 813457607: return 48;
  case 813457608 ... 814814583: return 49;
  case 814814584 ... 816176568: return 50;
  case 816176569 ... 817543719: return 51;
  case 817543720 ... 818916198: return 52;
  case 818916199 ... 820294170: return 53;
  case 820294171 ... 821677806: return 54;
  case 821677807 ... 823067284: return 55;
  case 823067285 ... 824462784: return 56;
  case 824462785 ... 825864494: return 57;
  case 825864495 ... 827272609: return 58;
  case 827272610 ... 828687328: return 59;
  case 828687329 ... 830108859: return 60;
  case 830108860 ... 831537416: return 61;
  case 831537417 ... 832973222: return 62;
  case 832973223 ... 834416506: return 63;
  case 834416507 ... 835867508: return 64;
  case 835867509 ... 837326474: return 65;
  case 837326475 ... 838793663: return 66;
  case 838793664 ... 840269341: return 67;
  case 840269342 ... 841753787: return 68;
  case 841753788 ... 843247291: return 69;
  case 843247292 ... 844750154: return 70;
  case 844750155 ... 846262691: return 71;
  case 846262692 ... 847785232: return 72;
  case 847785233 ... 849318118: return 73;
  case 849318119 ... 850861709: return 74;
  case 850861710 ... 852416382: return 75;
  case 852416383 ... 853982529: return 76;
  case 853982530 ... 855560564: return 77;
  case 855560565 ... 857150920: return 78;
  case 857150921 ... 858754054: return 79;
  case 858754055 ... 860370444: return 80;
  case 860370445 ... 862000597: return 81;
  case 862000598 ... 863645045: return 82;
  case 863645046 ... 865304353: return 83;
  case 865304354 ... 866979114: return 84;
  case 866979115 ... 868669961: return 85;
  case 868669962 ... 870377563: return 86;
  case 870377564 ... 872102629: return 87;
  case 872102630 ... 873845917: return 88;
  case 873845918 ... 875608233: return 89;
  case 875608234 ... 877390437: return 90;
  case 877390438 ... 879193449: return 91;
  case 879193450 ... 881018255: return 92;
  case 881018256 ... 882865915: return 93;
  case 882865916 ... 884737568: return 94;
  case 884737569 ... 886634443: return 95;
  case 886634444 ... 888557869: return 96;
  case 888557870 ... 890509287: return 97;
  case 890509288 ... 892490263: return 98;
  case 892490264 ... 894502504: return 99;
  case 894502505 ... 896547875: return 100;
  case 896547876 ... 898628426: return 101;
  case 898628427 ... 900746411: return 102;
  case 900746412 ... 902904323: return 103;
  case 902904324 ... 905104932: return 104;
  case 905104933 ... 907351322: return 105;
  case 907351323 ... 909646955: return 106;
  case 909646956 ... 911995730: return 107;
  case 911995731 ... 914402067: return 108;
  case 914402068 ... 916871014: return 109;
  case 916871015 ... 919408372: return 110;
  case 919408373 ... 922020869: return 111;
  case 922020870 ... 924716378: return 112;
  case 924716379 ... 927504211: return 113;
  case 927504212 ... 930395512: return 114;
  case 930395513 ... 933403814: return 115;
  case 933403815 ... 936545813: return 116;
  case 936545814 ... 939842513: return 117;
  case 939842514 ... 943320966: return 118;
  case 943320967 ... 947017025: return 119;
  case 947017026 ... 950979959: return 120;
  case 950979960 ... 955280739: return 121;
  case 955280740 ... 960028354: return 122;
  case 960028355 ... 965406387: return 123;
  case 965406388 ... 971773022: return 124;
  case 971773023 ... 980053610: return 125;
  case 980053611 ... 999999999: return 126;
  default: return 127;
  }
}

void report_params() {
  Serial.print("f0: ");
  Serial.print(f0);
  Serial.print(", v0_tgt: ");
  Serial.print(5.*v0_tgt);  // Amplitudes are normalized to 1.0 max, which corresponds to 5.0v.
  Serial.print(", dw0_tgt: ");
  Serial.println(dw0_tgt);
  Serial.flush();

  Serial.print("f1: ");
  Serial.print(f1);
  Serial.print(", v1_tgt: ");
  Serial.print(5.*v1_tgt);
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
  OpenTimer2(T2_ON | T2_PS_1_1, 256);
  OpenOC1(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  OpenOC2(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  OpenOC3(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  OpenOC4(OC_ON | OC_TIMER2_SRC | OC_PWM_FAULT_PIN_DISABLE, 0, 0);
  // Setup waveform generation.
  ConfigIntTimer1(T1_INT_ON | T1_INT_PRIOR_3);
  OpenTimer1(T1_ON | T2_PS_1_1, wavegen_interrupt_period);
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
    v0_tgt = Serial.parseFloat()/5.; // Signal 'a' volume.
    f1 = Serial.parseFloat(); // Signal 'b' frequency.
    v1_tgt = Serial.parseFloat()/5.; // Signal 'b' volume.
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
  int n0, n1, np, nm;
  mT1ClearIntFlag();
  // Adjust wave phases.
  w0 = (w0 + dw0) % fixed_int_multiplier;
  w1 = (w1 + dw1) % fixed_int_multiplier;
  // Adjust waveform amplitudes at adjusted phases.
  n0 = v0*cosine_amplitude(w0);
  n1 = v1*cosine_amplitude(w1);
  // Compute sum and difference signals.
  np = (n0 + n1 + 1) >> 1;
  nm = (n0 - n1 + 1) >> 1;
  // Update PWM signals.
  SetDCOC1PWM(n0 + waveform_zero_offset);
  SetDCOC2PWM(n1 + waveform_zero_offset);
  SetDCOC3PWM(np + waveform_zero_offset);
  SetDCOC4PWM(nm + waveform_zero_offset);
}
}
