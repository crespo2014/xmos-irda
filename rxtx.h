/*
 * rxtx.h
 *
 *  Created on: 14 Jul 2015
 *      Author: lester.crespo
 */


#ifndef RXTX_H_
#define RXTX_H_

#include <timer.h>
#include <xs1.h>
#include <stdio.h>

enum tx_task
{
  cmd_tx = 0,
  serial_tx,
  tx_i2c,
  mcp2515_tx,
  max_tx,
};

enum rx_task
{
  serial_rx = 0,
  irda_rx,
  mcp2515_rx,
  test_rx,      // testing interface
  reply_rx,     // command comming from tx worker as reply
  cmd_rx,     // command dispatching
  max_rx,
};

/*
 * Comunications
 * Binary.
 * ID_8 DEST_8 DATA  --> send to command interface ;extract id, dest; send to router; tx_work will reply back to command.
 * command interface will translate all packet with destination tx, parser it, and forward it.
 *
 *  Data comming from user interface is decode to send to the specificy interface.
 *  data comming fro minterface is forward to user interface
 */

/*
 * CAN frame has some extra bits
 */
#define CAN_RTR  (1<<30)  // remote transmit request
#define CAN_EXID (1<<31)  // extended id

/*
 * Some Rx task can hold a buffer until it is peek from other task
 * a serial rx can hold this buffer.
 * then a Buffer interface can peek data until \n
 * and parse without blocking rx by channel or something else
 *
 *
 */

struct rx_u8_buff
{
    unsigned char dt[32];
    unsigned len;          // last data byte
    unsigned overflow;     // how many bytes lost
    unsigned id;           // request id , use it for reply
    unsigned header_len;   // header len, real data, start here
    unsigned cmd_id;       //which command generated this packet
};

/*
 * Interrupt notification interface
 * For long interupt attend send a notifycation to other task
 */
interface interrupt_if
{
  void onInterrupt();
 // void ack();   // read port and generated a new notifycation in case
};

/*
 * Fault reporting interface
 */
interface fault_if {
  void fault(unsigned int id);
};

/*
 * send a byte from MSB to LSB
 * 1 will be 110
 * 0 will be 10
 * t - timer
 * tp - start timepoint, it will be update to end tp
 * bitlen - leng of bit
 * uc_dt - unsigned char to send
 * p - out port
 */

#define SERIAL_SEND(uc_dt,bitlen,t,tp,p,high,low) \
    for (unsigned char mask = (1<<7);mask != 0;mask>>=1) { \
      p <: high;  \
      tp += bitlen; \
      if ((uc_dt & mask) != 0) tp += bitlen; \
      t when timerafter(tp) :> void; \
      p <: low;  \
      tp += bitlen; \
      t when timerafter(tp) :> void; \
    }

/*
 * Defined fault types
 */
#define RX_FRAME_TOO_LONG   (1<<7)
#define RX_BUFFER_OVERFLOW  (1<<8)
#define ROUTE_OVERFLOW      (1<<9)        // all buffers are full
#define RX_BIT_OVERFLOW     (1<<10)       // irda bits overflow

// Port sharer interface
interface out_port_if {
  void set();
  void clear();
  void update(unsigned char v);
};

// for irda write from msb to lsb
// len is the number of bits
// todo . rename to packet_out_if
interface tx_if
{
  //todo. send a reply id id !=0 or data need to be send back
  [[clears_notification]] void send(struct rx_u8_buff  * movable &_packet);
  // clear to send
  [[notification]] slave void cts();
  [[clears_notification]] void ack();
};

//Tx or output interface
// todo rename to packet_container_out_if
interface packet_tx_if
{
  // data is waiting to be read
  [[notification]] slave void ondata();
  // get data
  [[clears_notification]] void get(struct rx_u8_buff  * movable &old_p,enum tx_task dest);
  // clear events
  [[clears_notification]] void ack();
  // return buffer tx interfaces does not keep any buffer
  void push(struct rx_u8_buff  * movable &old_p);
};

//Rx or input interface
// todo rename to packet_container_in_if
interface rx_frame_if
{
  void push(struct rx_u8_buff  * movable &old_p,enum tx_task dest);
};

[[distributable]] extern void Router_v2(server interface packet_tx_if tx_if[max_tx],server interface rx_frame_if rx_if[max_rx]);
[[combinable]] extern void TX_Worker(client interface packet_tx_if rx[max_tx],client interface tx_if tx[max_tx],client interface rx_frame_if reply);

extern void fastRX_v7(streaming chanend ch,in buffered port:8 p,clock clk,out port d1);
[[distributable]] extern void fastTX_v7(server interface tx_if tx,clock clk,out buffered port:8 p);

[[combinable]] extern void interrupt_manager(in port iport,unsigned count,client interface interrupt_if int_if[count],unsigned inactive);

static inline void tracePacket(struct rx_u8_buff *b)
{
  printf("Pck: id : %d, cmd : %d, head : %d, len : %d\n",b->id,b->cmd_id,b->header_len,b->len);
}


#endif /* RXTX_H_ */


