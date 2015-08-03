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

/*
 * TODO
 * Analize irda base on length of pulses
 * Count time as 1/2 of bit len.  (n+1)/2 is the bit len
 * 0 - 899us (2x) is 1
 * 900 - 1199 (3x) is 2
 * high pulse can have any length
 * max low pulse len is 3.
 * mas transations allowed is 20.
 *
 * information can be packed. in 2 or 4 bits each byte contains High len and low length as a pair.
 * timeout is produce if t > 300us*7
 */

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

#define XCORE_CLK_T_ns         4    // produced clock T
#define IRDA_XCORE_CLK_DIV     255
#define IRDA_CLK_T_ns          (XCORE_CLK_T_ns*IRDA_XCORE_CLK_DIV) // T of clock to generated irda carrier
#define IRDA_CARRIER_T_ns      27777
#define IRDA_CARRIER_CLK       (IRDA_CARRIER_T_ns/IRDA_CLK_T_ns)    // How many pulse to produce the carrier
#define IRDA_CARRIER_CLK_TON   (IRDA_CARRIER_CLK/4)
#define IRDA_CARRIER_CLK_TOFF  (IRDA_CARRIER_CLK - IRDA_CARRIER_CLK_TON)

#define IRDA_BIT_LEN_ns     (600*1000)
#define IRDA_CLK_PER_BIT    (IRDA_BIT_LEN_ns/IRDA_CLK_T_ns)     // carrier clocks per bit
#define IRDA_PULSE_PER_BIT  (IRDA_BIT_LEN_ns/IRDA_CARRIER_T_ns)                     // carrier pulse per bit

#define IRDA_32b_CLK_DIV      (IRDA_CARRIER_T_ns/(32*XCORE_CLK_T_ns))
#define IRDA_32b_CARRIER_T_ns (IRDA_32b_CLK_DIV*32*XCORE_CLK_T_ns) 
#define IRDA_32b_WAVE         0x000000FF
#define IRDA_32b_WAVE_INV     0xFFFFFF00
#define IRDA_32b_BIT_LEN      (IRDA_BIT_LEN_ns/IRDA_32b_CARRIER_T_ns + 1)   // one more 

// Producing irda carrier without clocked output
#define IRDA_CARRIER_GEN_T_ticks      (IRDA_CARRIER_T_ns/SYS_TIMER_T_ns)
#define IRDA_CARRIER_GEN_TON_ticks    IRDA_CARRIER_GEN_T_ticks/4
#define IRDA_CARRIER_GEN_TOFF_ticks   (IRDA_CARRIER_GEN_T_ticks-IRDA_CARRIER_GEN_TON_ticks)
#define IRDA_BIT_ticks                (IRDA_BIT_LEN_ns/SYS_TIMER_T_ns)

/*
 * Emulate an irda data on pin
 */
#define SONY_IRDA_EMULATE_TX(t,tp,dt,bits,p,high,low) \
  do { \
    unsigned int bitmask = (1<<(bitcount-1));  \
    unsigned char len; \
    t when timerafter(tp) :> void; \
    p <: high; tp+= (4*IRDA_BIT_ticks); \
    t when timerafter(tp) :> void; \
    p <: low; tp+= (IRDA_BIT_ticks); \
    while (bitmask != 0)  { \
      t when timerafter(tp) :> void; \
      len = (dt & bitmask) ? 2 : 1; /* 1 is 2T 0 is T */ \
      p <: high; tp+= (len*IRDA_BIT_ticks); \
      t when timerafter(tp) :> void; \
      p <: low; tp+= (IRDA_BIT_ticks); \
      bitmask >>= 1; \
      } \
      tp += (2*IRDA_BIT_ticks); /* elarge last bit to be 3 bits long*/ \
  } while(0)


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
 * Send irda data using sony protocol
 * bitcount : how many bits to send
 * t : timer
 * p : out port
 */
#define SONY_IRDA_32b_SEND(dt,bitcount,t,p) \
  do { \
    unsigned int bitmask = (1<<(bitcount-1));  \
    unsigned char len; \
    t when timerafter(tp) :> void; \
    IRDA_32b_PULSE(p,4); /*send start bit */ \
    tp += (5*IRDA_BIT_ticks); \
    while (bitmask != 0)  { \
      t when timerafter(tp) :> void; \
      len = (dt & bitmask) ? 2 : 1; /* 1 is 2T 0 is T */ \
      IRDA_32b_PULSE(p,len); \
      tp += ((len+1)*IRDA_BIT_ticks); \
      bitmask >>= 1; \
      } \
      tp += (2*IRDA_BIT_ticks); /* elarge last bit to be 3 bits long*/ \
  } while (0)

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
 * tests 590us 542 570
 */
#define IRDA_BIT_v1(p,bitcount,high,low) \
  do { \
    unsigned int count; \
    p @ count <: high; count += IRDA_CARRIER_CLK_TON; \
    for (int i = bitcount*IRDA_PULSE_PER_BIT;;--i) { \
      p @ count <: high; count += IRDA_CARRIER_CLK_TON; \
      if (i <= 1) break; \
      p @ count <: low; count += IRDA_CARRIER_CLK_TOFF; \
    } \
  } while(0)

/*
 * irda send bit v2
 * Use clk per bits for stop condition
 * 570 - 620us
 */
#define IRDA_BIT_v2(p,bitcount,high,low) \
  do { \
    unsigned int count; \
    unsigned int clk_count = bitcount*IRDA_CLK_PER_BIT;  \
    p <: high @ count ; count += IRDA_CARRIER_CLK_TON; /* First pulse */\
    for(;;) { \
      p @ count <: low; count += IRDA_CARRIER_CLK_TOFF; \
      if (clk_count < IRDA_CARRIER_CLK) break; /* try < T + Ton*/\
      clk_count -= IRDA_CARRIER_CLK; \
      p @ count <: high; count += IRDA_CARRIER_CLK_TON; \
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
#define SONY_IRDA_SEND_BAD(dt,bitcount,t,p,high,low) \
    do { \
      unsigned int bitmask = (1<<(bitcount-1));  \
      unsigned int __tp;  \
       unsigned int __tp2,tp3;  \
      unsigned char len; \
      t :> __tp;  \
      tp3 = __tp; \
      IRDA_BIT_v2(p,4,high,low); /*send start bit */ \
      __tp = __tp + (4+1)*IRDA_BIT_ticks; \
      t when timerafter(__tp) :> void; \
      while (bitmask != 0)  { \
          len = (dt & bitmask) ? 2 : 1; /* 1 is 2T 0 is T */ \
          t :> __tp2;  \
          printf("%u S\n",__tp2-tp3) ; \
          IRDA_BIT_v2(p,len ,high,low); \
          __tp = __tp + (len+1)*IRDA_BIT_ticks; \
          t when timerafter(__tp) :> void; \
          bitmask >>= 1; \
      } \
      __tp = __tp + 3*IRDA_BIT_ticks;  /* keep low for stop bit */ \
      t when timerafter(__tp) :> void; \
    } while(0)

/*
 *  tp next send time point
 */
#define SONY_IRDA_SEND(dt,bitcount,t,p,high,low) \
    do { \
      unsigned int bitmask = (1<<(bitcount-1));  \
      unsigned char len; \
      t when timerafter(tp) :> void; \
      IRDA_BIT_v2(p,4,high,low); /*send start bit */ \
      tp += (5*IRDA_BIT_ticks); \
      while (bitmask != 0)  { \
          t when timerafter(tp) :> void; \
          len = (dt & bitmask) ? 2 : 1; /* 1 is 2T 0 is T */ \
          IRDA_BIT_v2(p,len ,high,low); \
          tp += ((len+1)*IRDA_BIT_ticks); \
          bitmask >>= 1; \
      } \
      tp += (2*IRDA_BIT_ticks); /* elarge last bit to be 3 bits long*/ \
    } while(0)

/*
 * Send data using processor timer
 * tp will mark started
 */
#define SONY_IRDA_TIMED_SEND(dt,bitcount,t,p,high,low) \
    do { \
      unsigned int bitmask = (1<<(bitcount-1));  \
      unsigned char len; \
      IRDA_PULSE(p,t,tp,4,high,low);\
      while (bitmask != 0)  { \
          len = (dt & bitmask) ? 2 : 1; /* 1 is 2T 0 is T */ \
          IRDA_PULSE(p,t,tp,len,high,low);\
          bitmask >>= 1; \
      } \
      tp += (2*IRDA_BIT_ticks); /* 2 zeroed pulses */ \
    } while(0)
#endif /* IRDA_H_ */
