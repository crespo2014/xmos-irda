/*
 * serial.h
 *
 *  Created on: 31 Jul 2015
 *      Author: lester.crespo
 */


#ifndef SERIAL_H_
#define SERIAL_H_

#include "irda.h"

/*
 * TODO
 * define an RX serial port using buffered output if it is possible
 *
 * There is not way to send full byte using buffered output,
 * Data will be send bit by bit.
 * A base frecuency will be use then baud rate will be a factor of this frecuency
 *
 * 9600 bit size is 104us
 * 115200 bits (8.6805 us)
 *
 * start bit, data, no parity,1-stop bit 8-N-1
 *
 *
 * Serial Rx buffer it is the task that run usercmd, this is a slow interface.
 * it connects using a channel to RX, on time event (1ms) the start packet flag is reset.
 *
 * Command interface to be splited by two (fast, slow).
 */

#define UART_BASE_BIT_LEN_ns  8680    //for 115200 use a divisor to get the desired baud rate
#define UART_XCORE_CLOCK_DIV  217
#define UART_T_CLK            (UART_BASE_BIT_LEN_ns/(XCORE_CLK_T_ns*UART_XCORE_CLOCK_DIV))    // how many clocks to create freq

#define UART_BASE_BIT_LEN_ticks    (UART_BASE_BIT_LEN_ns/SYS_TIMER_T_ns)
#define UART_IRDA_PULSE_PER_BIT    (UART_BASE_BIT_LEN_ns/IRDA_CARRIER_T_ns)


#define SERIAL_HIGH 0
#define SERIAL_LOW  1

/*
 * Send a byte throught a clocked serial port
 * baud - divisor for base rate of 115200
 */
#define UART_CLOCKED_SEND(p,dt,baud,high,low) \
do { \
  unsigned count; unsigned mask = (1 << 7); \
  p <: low @ count;  /* start bit*/ \
  count += (UART_T_CLK*baud); \
  do { \
    p @ count <: (dt & mask) ? high : low; \
    count += (UART_T_CLK*baud); \
    mask >>=1; \
  } while (mask != 0); \
  p  @ count <: high;  /* stop bit*/ \
  count += (UART_T_CLK*baud); \
  p  @ count <: high;  /* end of stop bit*/ \
}while(0)

#define UART_TIME_SEND(p,dt,baud,t,tp) \
    unsigned outData = dt << 1 | 0x200;   /*stop bit 10 as 1, start bit 0 as 0 */ \
    for (int i = 0;i<10;i++) { \
      t when timerafter(tp) :> void; \
      p <: >>outData; \
      tp += (UART_BASE_BIT_LEN_ticks*baudrate); }

/*
 * TODO Serial over irda
 * A frame is a 10x bitlen width. Tb
 * pulse size Tp
 *
 * Sending a 1
 * t = tb
 * while (t > Tp)
 * pulse or not
 * t -= Tp
 * if next is 1 then t += Tb and repeat
 * if next is 0 then
 *
 * FROM LSB to MSB
 *
 * if bitlen < ton then pick another bit or exit and adjust tp
 * calculate port value bit *1
 * generated pulse
 * bitlen -= ton+toff
 */

#define SERIAL_OVER_IRDA_TIMED(p,data,bitcount,Tbit,Ton,Toff,t,tp) \
    do { \
      unsigned bitmask = 1; \
      unsigned bitlen = 0; \
      unsigned adjust = 0; /* for toff */ \
      unsigned char pv; \
      while (bitcount--) {  \
        bitlen = bitlen + Tbit - adjust; /* load bit data */ \
        if (bitmask & data) pv = 1; else pv = 0;   \
        do { \
          if (bitlen < Ton) break; \
          t when timerafter(tp) :> void; p <: pv; \
          tp += Ton; bitlen -= Ton; \
          t when timerafter(tp) :> void; p <: 0; \
          tp += Toff; \
          if (bitlen < Toff) { adjust = toff ;break;} else adjust = 0; \
        } while(0); \
      bitmask <<= 1; \
      }\
    } while (0)

#define UART_TIMED_SEND(pdata,len,p,baudrate,t)  do { \
  unsigned outData;    unsigned tp__; \
  t :> tp__; \
  for (int i =0 ; i< len;i++) { \
    outData = (pdata[i]) << 1 | 0x200;   /*stop bit 10 as 1, start bit 0 as 0*/ \
    for (int i = 0;i<10;i++) {  \
      t when timerafter(tp__) :> void; \
      p <: >>outData; \
      tp__ += (UART_BASE_BIT_LEN_ticks*baudrate); \
    } \
  } \
  tp__ += (UART_BASE_BIT_LEN_ticks*baudrate*10);  /* 1 byte gap */ \
  t when timerafter(tp__) :> void;  \
 } while(0)

/*
 * Serial rx will write to a chan.
 * A buffer will hold data until cr to send to cmd interface
 */
interface serial_rx_if
{
  [[notification]] slave void error();       // invalid character received
  [[clears_notification]] void ack();
  void setbaud(unsigned baud);
};

interface uart_v4
{
  void setbaud(unsigned baud);
};

[[distributable]] extern void serial_tx_v5(server interface uart_v4 uart_if,server interface tx_if tx,out port p);
extern void serial_rx_v5(server interface serial_rx_if uart_if, client interface rx_frame_if router,in port rx);

#endif /* SERIAL_H_ */
