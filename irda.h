/*
 * irda.h
 *
 *  Created on: 21 Jul 2015
 *      Author: lester.crespo
 */
 
  /* TODO
 * buffered and clocked output to reduce processor usage
 * irda carrier T 27777ns, clock div = 217 T= 868ns* 32bits = 27776ns
 * 32bits number 0xF000 creates a 25% duty cycle carrier
 * 22 numbers make a bit.
 */

#ifndef IRDA_H_
#define IRDA_H_

#include "rxtx.h"

#define IRDA_32b_CLK_DIV      (IRDA_CARRIER_T_ns/(32*XCORE_CLK_T_ns))
#define IRDA_32b_CARRIER_T_ns (IRDA_32b_CLK_DIV*32*XCORE_CLK_T_ns) 
#define IRDA_32b_WAVE         0xFF000000
#define IRDA_32b_BIT_LEN      (IRDA_BIT_LEN_ns/IRDA_32b_CARRIER_T_ns + 1)   // one more 

// Producing irda carrier without clocked output
#define IRDA_CARRIER_GEN_T_ticks      (IRDA_CARRIER_T_ns/SYS_TIMER_T_ns)
#define IRDA_CARRIER_GEN_TON_ticks    IRDA_CARRIER_GEN_T_ticks/4
#define IRDA_CARRIER_GEN_TOFF_ticks   (IRDA_CARRIER_GEN_T_ticks-IRDA_CARRIER_GEN_TON_ticks)
//#define IRDA_BIT_CARRIER_PULSES       (IRDA_BIT_LEN_ns/IRDA_CARRIER_T_ns)
#define IRDA_BIT_ticks                (IRDA_BIT_LEN_ns/SYS_TIMER_T_ns)

/*
  Create an irda 36Khz pulse using a clocked buffered 32bist port
*/
#define IRDA_32b_PULSE(p,bits) \
do { \
  for (unsigned i = bits*IRDA_32b_BIT_LEN;i!=0;--i) { \
  p <: IRDA_32b_WAVE; \
  }\
} while(0)

/*
 * Produce a irda pulse using system timer
 * port,timer,
 * timepoint to start, updated to next pulse time
 * bits len
 * high, low levels
 */
#define IRDA_PULSE(p,t,tp,bits,high,low) \
  do { \
    unsigned i = IRDA_BIT_ticks*bits;  \
    unsigned ttp = tp; \
    while (i>IRDA_CARRIER_GEN_TON_ticks) {\
      t when timerafter(ttp) :> void;\
      p <: high; \
      ttp += IRDA_CARRIER_GEN_TON_ticks; \
      t when timerafter(ttp) :> void;\
      p <: low; \
      ttp += IRDA_CARRIER_GEN_TOFF_ticks; \
      if (i < IRDA_CARRIER_GEN_T_ticks) break; \
      i-=IRDA_CARRIER_GEN_T_ticks; \
    }\
    tp += ((bits+1)*IRDA_BIT_ticks); /* plus one stop bit*/ \
  } while(0)

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
 * dt unsigned integer  data to send
 * bitcount  - how many bits to send
 * bitlen - len of a pulse (0 = 10, 1 = 110)
 * t timer object
 * p out port
 *
 * get time.
 * send 4bit pulse
 * wait until 5bits time
 * send nbits data
 * wait (n+1) bits
 */
#define SONY_IRDA_SEND(dt,bitcount,t,p,high,low) \
    do { \
      unsigned int bitmask = (1<<(bitcount-1));  \
      unsigned int tp;  \
      unsigned char len; \
      t :> tp;  \
      IRDA_BIT_v1(p,4,high,low); /*send start bit */ \
      tp = tp + (4+1)*IRDA_BIT_ticks; \
      t when timerafter(tp) :> void; \
      while (bitmask != 0)  { \
          len = (dt & bitmask) ? 2 : 1; /* 1 is 2T 0 is T */ \
          IRDA_BIT_v1(p,len ,high,low); \
          tp = tp + (len+1)*IRDA_BIT_ticks; \
          t when timerafter(tp) :> void; \
          bitmask >>= 1; \
      } \
      tp = tp + 3*IRDA_BIT_ticks;  /* keep low for stop bit */ \
      t when timerafter(tp) :> void; \
    } while(0)

#endif /* IRDA_H_ */
