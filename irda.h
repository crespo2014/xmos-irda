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
 * Done:
 * 100 Mhz / 32 = 0.32us pulse for clock.
 * (*86 -> 27.52us -> 36.34Khz)
 * (*75 -> 24us    -> 41.6Khz)
 *
 */

#define IRDA_CLK            0.32  // us clock use for irda
#define IRDA_CARRIER_CLK    86    //  27.52 36.34Khz
#define IRDA_CARRIER_TON    22
#define IRDA_CARRIER_TOFF   (IRDA_CARRIER_CLK_COUNT - IRDA_CARRIER_TON)
#define IRDA_CLK_PER_BIT    (600/IRDA_CLK)
#define IRDA_PULSE_PER_BIT  (IRDA_CLK_PER_BIT/IRDA_CARRIER_CLK)    // how many clock in a irda pulse
#define IRDA_BIT_LEN         600*us     // for timer
/*
 * use
 * p <:0 @ count; at start transmition
 * count+= 3* IRDA_PULSE_CLK; // keep space bettween stop and start
 * bitcount how many bits long the pulse is
 */
#define IRDA_CLK_PULSE(p,bitcount) \
  do { \
    unsigned int count; \
    p <: 0 @count; \
    for (int i = 0; i < bitcount*IRDA_PULSE_PER_BIT;++i) { \
      p @ count <: 1; count += IRDA_CARRIER_TON; \
      p @ count <: 0; count += IRDA_CARRIER_TOFF; \
    } \
  } while(0)


/*
TODO : read from irda and store data as time diff bettween transitions.
and normalize to T.
max len of low signal will be 3 or 4T
max len of high is not define
High signal will be round to lower bound of multiple of T (600us)
Sony (41....3)
Philips (1111.....)
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
