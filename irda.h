/*
 * irda.h
 *
 *  Created on: 21 Jul 2015
 *      Author: lester.crespo
 */

#ifndef IRDA_H_
#define IRDA_H_

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
