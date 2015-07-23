/*
 * irda.h
 *
 *  Created on: 21 Jul 2015
 *      Author: lester.crespo
 */

#ifndef IRDA_H_
#define IRDA_H_

/*
 * Produce a irda pulse of the length of many bits
 */
#define IRDA_BIT_v1(p,bitcount,high,low) \
  do { \
    unsigned int count; \
    p <: 0 @count; \
    for (int i = bitcount*IRDA_PULSE_PER_BIT; i > 0 ;--i) { \
      p @ count <: high; count += IRDA_CARRIER_CLK_TON; \
      p @ count <: low; count += IRDA_CARRIER_CLK_TOFF; \
    } \
  } while(0)

/*
 * irda send bit v2
 * Use clk per bits for stop condition
 */
#define IRDA_BIT_v2(p,bitcount,high,low) \
  do { \
    unsigned int count; \
    unsigned int clk_count = bitcount*IRDA_CLK_PER_BIT;  \
    p <: 0 @count; \
    while(clk_count >= IRDA_CARRIER_TON) { \
      p @ count <: high; count += IRDA_CARRIER_CLK_TON; \
      p @ count <: low; count += IRDA_CARRIER_CLK_TOFF; \
      if (clk_count < IRDA_CARRIER_CLK) break; \
      clk_count -= IRDA_CARRIER_CLK \
    }\
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

/*
 * Send a frame of bits as irda transmition
 * from msb to lsb
 * ui unsigned integer  data to send
 * bitcount  - how many bits to send
 * bitlen - len of a pulse (0 = 10, 1 = 110)
 * t timer object
 * p out port
 */
//#define SONY_IRDA_SEND(ui,bitcount,bitlen,t,p,high,low) \
//    do { \
//      unsigned int bitmask = (1<<(bitcount-1));  \
//      unsigned int len = 4*bitlen;    /*send start bit */\
//      unsigned int tp;  \
//      t :> tp;  \
//      IRDA_BIT_v1(p,4,high,low); \
//      tp += bitlen; \
//      t when timerafter(tp) :> void; \
//      while (bitmask != 0)  { \
//          len = bitlen; \
//          if (ui & bitmask) len += bitlen; /* 1 is 2T 0 is T */ \
//          IRDA_BIT_v1(p,((ui & bitmask) ? 2 : 1) ,high,low); \
//          tp += bitlen; \
//          t when timerafter(tp) :> void; \
//          bitmask >>= 1; \
//      } \
//    t when timerafter(tp + 3*bitlen) :> tp;   /* keep low for stop bit */ \
//    } while(0)

#endif /* IRDA_H_ */
