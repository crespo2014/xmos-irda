/*
 * irda.h
 *
 *  Created on: 21 Jul 2015
 *      Author: lester.crespo
 */

#ifndef IRDA_H_
#define IRDA_H_

/*
 * TODO
 * use clocked port for irda output
 * 36Khz - 27.77us 3x9us  - 100 (33% ton)
 * irda Pulse 600us 22*27 = 66*9us = 594
 *
 * 8us - 24us(41.6khz) 25pulse per bit
 * 9us - 27us(37Khz)   22pulse per bit
 *
 * to create one irda pulse
 * p <:0 @ count;
 * repeat 22 times or 44 or 66
 * p <:1 @ count;
 * count += 1;
 * p @ count <: 0;
 * count += 2;
 * ...............
 * count += (3x22)
 * p @ count <: 0
 */

#define IRDA_CLK_LEN        8                   // clock use for irda
#define IRDA_CARRIER_P      3*IRDA_CLK_LEN
#define IRDA_PULSE_PER_BIT  600/IRDA_CARRIER_P
#define IRDA_PULSE_CLK      600/IRDA_CLK_LEN    // how many clock in a irda pulse
/*
 * use
 * p <:0 @ count; at start transmition
 * count++;
 */
#define IRDA_CLK_PULSE(count,bitlen) \
  do { \
    for (int i = 0; i < bitlen*IRDA_PULSE_PER_BIT;++i) { \
      p @ count <: 1; ++count; \
      p @ count <: 0; count += 2; \
    } \
    count+=IRDA_PULSE_CLK;  /* low bit */ \
  } while(0)


#define IRDA_BIT_LEN 600*us

/*
TODO : read from irda and store data as time diff bettween transitions.
and normalize to T.
max len of low signal will be 3 or 4T
max len of high is not define
High signal will be round to lower bound of multiple of T (600us)
Sony (41....3)
Philips (1111.....)
*/

/*
 * macro to produce a irda pulse.
 * time point will be update to the end of the pulse
 * a duty cycle of 33% is used
Produce a 36Khz wave form for irda transmitter. (27.8us)
Dutty cycle is 25-33%
Create many pulse to fill the specific time
9us + 18us

T period of the irda carrier,(36Khz = 27us)
tp time point of start of pulse, it will be update to point the end of the pulse
len - len of pulse.
t timer
p port
high, low port values for high an low level

a 1/3T pulse is produce always.
if there is space for a full pulse then another will produce in the next loop
if there is not space no more pulse will be produce.
*/
#define IRDA_PULSE(T,tp,len,t,p,high,low) \
  do {   \
    p <: high;  \
    t when timerafter(tp+T/3) :> void; \
    p <: low;  \
    if (len < T) {  \
      tp += len;  \
      len = 0;        \
    } else  {   \
      tp += T;   \
      len -= T;     \
    } \
    t when timerafter(tp) :> void;\
  } while(len != 0);

/*
 * Send a frame of bits as irda transmition
 * from msb to lsb
 * ui unsigned integer  data to send
 * bitcount  - how many bits to send
 * bitlen - len of a pulse (0 = 10, 1 = 110)
 * t timer object
 * p out port
 */
#define SONY_IRDA_SEND(ui,bitcount,bitlen,t,p,high,low) \
    do { \
      unsigned int bitmask = (1<<(bitcount-1));  \
      unsigned int len = 4*bitlen;    /*send start bit */\
      unsigned int tp;  \
      t :> tp;  \
      IRDA_PULSE(27*us,tp,len,t,p,1,0); \
      tp += bitlen; \
      t when timerafter(tp) :> void; \
      while (bitmask != 0)  { \
          len = bitlen; \
          if (ui & bitmask) len += bitlen; /* 1 is 2T 0 is T */ \
          IRDA_PULSE(27*us,tp,len,t,p,high,low); \
          tp += bitlen; \
          t when timerafter(tp) :> void; \
          bitmask >>= 1; \
      } \
    t when timerafter(tp + 3*bitlen) :> tp;   /* keep low for stop bit */ \
    } while(0)

#endif /* IRDA_H_ */
