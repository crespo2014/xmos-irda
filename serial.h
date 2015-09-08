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

/*
 * For byte to byte send interface.
 * Avoid bloquing on channel.
 * we use a ready to send trigger
 * A buffer will buffered all data comming from cmd channel
 */
interface serial_tx_if
{
  [[notification]] slave void ready();                  // a push cmd will be sucessfull
  [[guarded]] [[clears_notification]] void push(unsigned char dt);  // send this data
  void setbaud(unsigned baud);
};

interface serial_tx_v2_if
{
  [[notification]] slave void overflow();          // a push cmd will be sucessfull
  [[clears_notification]] void ack();  // send this data
  void setbaud(unsigned baud);
};

/*
 * Interface for serial buffers
 */
interface serial_buffer_if
{
  [[notification]] slave void onRX(); // CR received a buffer is ready to be pick
  [[clears_notification]] unsigned char get(struct tx_frame_t  * movable &old_p);
  void TX(unsigned char c);
  void setbaud(unsigned baud);
};


extern void serial_buffer(server interface serial_buffer_if cmd,
    chanend rx,
    client interface serial_rx_if rx_if,
    client interface serial_tx_if tx_if);



interface buffer_v1_if
{
  void push(unsigned char* dt,unsigned char count);
  [[notification]] slave void onRX(); // CR received a buffer is ready to be pick
  [[clears_notification]] unsigned char get(struct tx_frame_t  * movable &old_p);
};

interface uart_v4
{
  void setbaud(unsigned baud);
};

extern void buffer_v1(server interface buffer_v1_if cmd,
    streaming chanend rx,
    streaming chanend tx);


[[combinable]] extern void serial_tx_ctb(streaming chanend ch,
    server interface serial_tx_v2_if cmd,
    out port tx);

//extern void serial_test(client interface serial_tx_if tx,chanend rx_c,client interface serial_rx_if rx);
[[combinable]] extern void serial_tx_timed_cmb(server interface serial_tx_if cmd,out port tx);
[[combinable]] extern void serial_rx_cmb(in port rx,streaming chanend c,server interface serial_rx_if rx_if,out port deb);
extern void serial_to_irda_timed(client interface tx_rx_if src, out port tx,unsigned char baud_rate,unsigned char low,unsigned char high);

[[combinable]] extern void serial_rx_v4(server interface serial_rx_if uart_if, streaming chanend c,in port rx);
[[combinable]] extern void serial_tx_v4(server interface uart_v4 uart_if,server interface tx tx_if,out port p);


#endif /* SERIAL_H_ */
