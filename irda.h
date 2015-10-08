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
#include "utils.h"

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
#define IRDA_32b_WAVE_BLANK   0x0           // use to create a delay
#define IRDA_32b_BIT_LEN      (IRDA_BIT_LEN_ns/IRDA_32b_CARRIER_T_ns + 1)   // one more
#define IRDA_32b_WAVE_ticks   (IRDA_32b_CARRIER_T_ns/SYS_TIMER_T_ns)

// Producing irda carrier without clocked output
#define IRDA_CARRIER_T_ticks      (IRDA_CARRIER_T_ns/SYS_TIMER_T_ns)
#define IRDA_CARRIER_TON_ticks    IRDA_CARRIER_T_ticks/4
#define IRDA_CARRIER_TOFF_ticks   (IRDA_CARRIER_T_ticks-IRDA_CARRIER_TON_ticks)
#define IRDA_BIT_ticks            (IRDA_BIT_LEN_ns/SYS_TIMER_T_ns)

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
  Create an irda 36Khz pulse using a clocked buffered 32bit port
*/
#define IRDA_32b_PULSE(p,bits) \
do { \
  for (unsigned i = bits*IRDA_32b_BIT_LEN;i!=0;--i) { \
  p <: IRDA_32b_WAVE; \
  }\
} while(0)

/*
 * Wait some cycles before send more data
 * The receiver must synchronized when the signal change
 * I mean it can not synchronize using internal clock at the first pulse
 * it has to synchronize in each pulse
 */
#define IRDA_32b_WAIT(p,bits) \
do { \
  for (unsigned i = bits*IRDA_32b_BIT_LEN;i!=0;--i) { \
  p <: IRDA_32b_WAVE_BLANK; \
  }\
} while(0)


/*
 * Send irda data using sony protocol
 * bitcount : how many bits to send
 * t : timer
 * p : out port
 */
#define SONY_IRDA_32b_SEND(dt,bitcount,p) \
  do { \
    unsigned int bitmask = (1<<(bitcount-1));  \
    unsigned char len; \
    IRDA_32b_PULSE(p,4); /*send start bit */ \
    IRDA_32b_WAIT(p,1); \
    while (bitmask != 0)  { \
      len = (dt & bitmask) ? 2 : 1; /* 1 is 2T 0 is T */ \
      IRDA_32b_PULSE(p,len); \
      IRDA_32b_WAIT(p,1); \
      bitmask >>= 1; \
      } \
      IRDA_32b_WAIT(p,2);  /* elarge last bit to be 3 bits long*/ \
  } while (0)

/*
 * Produce a irda pulse using system timer
 * port,timer,
 * timepoint to start, updated to next pulse time
 * bits len
 * high, low levels
 */
#define IRDA_TIMED_PULSE(p,t,tp,bits,high,low) \
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
 * Create a delay using a clocked irda out port
 */
#define IRDA_CLOCKED_BLANK_BIT(p,bits,low) \
  do { \
    unsigned int count; \
    p <: low @ count ; \
    p @ count+bits*IRDA_CLK_PER_BIT <: low   ; \
  } while(0)

/*
 * Produce a irda pulse of the length of many bits
 * tests 590us 542 570
 */
#define IRDA_CLOCKED_BIT_v1(p,bitcount,high,low) \
  do { \
    unsigned int count; \
    int i = bitcount*IRDA_PULSE_PER_BIT; \
    p @ count <: high; count += IRDA_CARRIER_CLK_TON; \
    for (;;) { \
      p @ count <: low; count += IRDA_CARRIER_CLK_TOFF; \
      --i; if (i == 0) break; \
      p @ count <: high; count += IRDA_CARRIER_CLK_TON; \
    } \
  } while(0)

/*
 * irda send bit v2
 * Use clk per bits for stop condition
 * 570 - 620us
 */
#define IRDA_CLOCKED_BIT_v2(p,bitcount,high,low) \
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
#define SONY_IRDA_CLOCKED_SEND(dt,bitcount,t,p,high,low) \
    do { \
      unsigned int bitmask = (1<<(bitcount-1));  \
      unsigned char len; \
      IRDA_CLOCKED_BIT_v2(p,4,high,low); /*send start bit */ \
      IRDA_CLOCKED_BLANK_BIT(p,1,low);  \
      while (bitmask != 0)  { \
          len = (dt & bitmask) ? 2 : 1; /* 1 is 2T 0 is T */ \
          IRDA_CLOCKED_BIT_v2(p,len ,high,low); \
          IRDA_CLOCKED_BLANK_BIT(p,1,low);  \
          bitmask >>= 1; \
      } \
      IRDA_CLOCKED_BLANK_BIT(p,2,low);  /* elarge last bit to be 3 bits long*/ \
    } while(0)

/*
 * Send data using processor timer
 * tp will mark started
 */
#define SONY_IRDA_TIMED_SEND(dt,bitcount,t,p,high,low) \
    do { \
      unsigned int bitmask = (1<<(bitcount-1));  \
      unsigned char len; \
      IRDA_TIMED_PULSE(p,t,tp,4,high,low);\
      while (bitmask != 0)  { \
          len = (dt & bitmask) ? 2 : 1; /* 1 is 2T 0 is T */ \
          IRDA_TIMED_PULSE(p,t,tp,len,high,low);\
          bitmask >>= 1; \
      } \
      tp += (2*IRDA_BIT_ticks); /* 2 zeroed pulses */ \
    } while(0)

 //extern void irda_32b_tx_comb(/*client interface tx_rx_if tx_if,*/out buffered port:32 tx);

[[distributable]] extern void irda_tx_v5(clock clk,out buffered port:32 p32,server interface tx_if tx);
[[combinable]] extern void irda_rx_v5(in port p,unsigned bitlen,client interface rx_frame_if router);
[[distributable]] extern void irda_emulator(unsigned bitlen,out port p,server interface tx_if tx);
extern void irda_send(unsigned data,unsigned char bitcount,client interface tx_if tx);

/*
 * Irda clocked port
 * Use clock count to set 0,1
 */
struct irda_tx_1_t
{
    out port p;
    clock clk;
};
/*
 * Use a buffered port to generate the irda wave
 */
struct irda_tx_2_t
{
    out buffered port:32 p;
    clock clk;
};
/*
 * Timed irda tx
 */
struct irda_tx_0_t
{
    out port p;
//    unsigned tp;
    unsigned ton_ticks;   //
    unsigned toff_ticks;
    unsigned bitlen_ticks;
    timer t;
};

/*
 * pulse position modulation
 * sampling a 2T.
 * Pulse-space-(bit at pos 0,1,2,3)
 * Pulse-6 spaces is end of frame
 * Pulse-5x 0 + pulse start frame or byte
 */
struct ppm_rx_t
{
    in buffered port:32 p;  //only 14 bits are read each time
    clock clk;
    timer t;
};

struct ppm_tx_t
{
    out buffered port:32 p;  //only 14 bits are read each time
    clock clk;
    timer t;
};

/*
 * Initialize the timed irda tx, base on freq
 */
void static inline irda_0_init(struct irda_tx_0_t &irda,unsigned T_ns,unsigned ton_percent,unsigned bitlen_ns)
{
  irda.ton_ticks = (T_ns*ton_percent)/(SYS_TIMER_T_ns*100);
  irda.toff_ticks = (T_ns/SYS_TIMER_T_ns) - irda.ton_ticks;
  irda.bitlen_ticks = bitlen_ns/SYS_TIMER_T_ns;
}

/*
 * Send byte from lsb to msb
 */
void static inline irda_0_send(struct irda_tx_0_t &irda,unsigned v,unsigned bitcount)
{
  unsigned tp;
  irda.t :> tp;
  do
  {
    if (v & 1)
    {
      unsigned i = irda.bitlen_ticks;
      while(1)
      {
        if (i < irda.ton_ticks) break;
        i-= irda.ton_ticks;
        irda.t when timerafter(tp) :> void;
        irda.p <: 1;
        tp += irda.ton_ticks;
        irda.t when timerafter(tp) :> void;
        irda.p <: 0;
        if (i < irda.toff_ticks) break;
        i-= irda.toff_ticks;
        tp += irda.toff_ticks;
      }
      tp += i;  // wait remaining part
    }
    else
      tp += irda.bitlen_ticks;
    v >>= 1;
    irda.t when timerafter(tp) :> void;   // wait for next transition
  } while (--bitcount);
}

/*
 * Send 8bits serial data over irda
 * From LSB to MSB
 */
void static inline irda_0_send_uart(struct irda_tx_0_t &irda,unsigned v)
{
  unsigned d = ~((v << 1) | (0x3<< 9));  //set 2x stop bit
  irda_0_send(irda,d,11);
}

// serial over irda shold invert all bits. because 1 means 0, and 0 means 1.
/*
 * Pulse position modulation
 * time different between pulse is the value transmitted.
 * |---|-|---|
 * 1T is 00
 * 2T is 01
 * 3T is 10
 * 4T is 11
 * wait for 1 and take time
 * wait 0.
 * wait for 1, get time differents /2 and send to channel
 * More than 4T waiting for more data is end of frame
 wait 1.
 read
 count zero
 push to channel 30ns
 sample at 4ns for 8 ns bit size. Start bit + 4bit = 40ns
 +40ns pause to process. 
 010XXX data  40ns
 010000 pausa 40ns
  */
void static inline ppm_rx_init(struct ppm_rx_t &ppm,unsigned bitlen_ns)
{
  configure_clock_xcore(ppm.clk,(bitlen_ns/XCORE_CLK_T_ns)/2);     // dividing clock ticks
  configure_in_port(ppm.p,ppm.clk);
  start_clock(ppm.clk);
}

void static inline ppm_tx_init(struct ppm_tx_t &ppm,unsigned bitlen_ns)
{
  configure_clock_xcore(ppm.clk,(bitlen_ns/XCORE_CLK_T_ns)/2);     // dividing clock ticks
  configure_out_port(ppm.p,ppm.clk,0);
  start_clock(ppm.clk);
}
/*
 * 0 - separator
 * 1 - pulse
 *  6x0 start frame
 *  0 - data start
 *  4x? * data
 *
 */
void static inline ppm_send(struct ppm_tx_t &ppm,const char data[n],unsigned n)
{
  unsigned v;
  partout(ppm.p,8,0x2);   // 0 1 00 00 00   SOF
  for (unsigned i =0 ;i< n;i++)
  {
    v = 0x100 | data[i];
    do
    {
      unsigned tv = v & 0x3;
      partout(ppm.p,8,0x2 | (0x8 << tv));
      v >>= 2;
    } while (v != 1);
  }
  partout(ppm.p,9,0x82); // 010 00 00 1 EOF
}

[[distributable]] extern void irda_tx(struct irda_tx_0_t &irda,server interface tx_if tx);

#endif /* IRDA_H_ */
