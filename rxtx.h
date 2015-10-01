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

/*
 * Comunications
 * Binary.
 * ID_8 DEST_8 DATA  --> send to command interface ;extract id, dest; send to router; tx_work will reply back to command.
 * command interface will translate all packet with destination tx, parser it, and forward it.
 *
 * ones command is send using tx worker, a reply is send to managament if it is necessary
 *
 * incoming data from interface can be send to command port or managament port.
 * an id is preffix before send to command port.
 *
 * it is better use at managamnet tx, to convert all outgoing data.
 * SRC DATA  - source
 *
 *            (ID_8 DEST_8 DATA)
 * in cmd --> [cmd] --> router
 *               <-- [notify] <-- router <-- [input port] <-- interrupt
 * (ID_8 SRC_8 DATA)          (SRC_8 DATA)
 *
 *            [router] -->[tx worker] --> [out if]
 *            [notify]<--          <-- reply
 *
 *  managament port send raw data, frame is fill up with data, and go into router and so.
 *  managament port recieved raw data comming from decoded.
 *
 *  man TX <--- [ coded base on src_rx ] <-- [any interface]
 *  man RX --> [ decoded ] --> [any interface]
 *
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
    unsigned char len;      // actual len of buffer
    unsigned char overflow; // how many bytes lost
    unsigned char id;       // request id , use it for reply
    // router will set up this value base on incomming interface
    unsigned char src_rx;   // where this data is comming from. ( for managament port, fields need to be update before procceded).
    unsigned char header_len; // header len, real data, start here

};

/*
 * For interuptions
 */
struct interrupt_mask_t
{
  unsigned char mask;
  unsigned char val;
  /*
   * bit 0 polarization or level
   * bit 1 0 - level trigger
   *       1 - edge trigger
   */
  unsigned char trigger;
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
// todo . send function should contains full frame, because we need data usefull for the cmd interface.
interface tx_if
{
  [[clears_notification]] void send(const char* data,unsigned char len);
  // clear to send
  [[notification]] slave void cts();
  [[clears_notification]] void ack();
};

enum tx_task
{
  cmd_tx = 0,
  serial_tx,
  mcp2515_tx,
  max_tx,
};

enum rx_task
{
  serial_rx = 0,
  irda_rx,
  cmd_rx,     // command dispatching
  mcp2515_rx,
  test_rx,      // testing interface
  max_rx,
};

//Tx or output interface
interface packet_tx_if
{
  [[notification]] slave void ondata();       // means data is waiting to be read
  [[clears_notification]] void get(struct rx_u8_buff  * movable &old_p,enum tx_task dest);
  // For on demand tx interface this function clears the event
  [[clears_notification]] void ack();
  void push(struct rx_u8_buff  * movable &old_p);   // return back the frame
};

//Rx or input interface
interface rx_frame_if
{
  void push(struct rx_u8_buff  * movable &old_p,enum tx_task dest);
};

[[distributable]] extern void Router_v2(server interface packet_tx_if tx_if[max_tx],server interface rx_frame_if rx_if[max_rx]);
[[combinable]] extern void TX_Worker(client interface packet_tx_if tx_input[max_tx],client interface tx_if tx_out[max_tx]);

extern void fastRX_v7(streaming chanend ch,in buffered port:8 p,clock clk,out port d1);
[[distributable]] extern void fastTX_v7(server interface tx_if tx,clock clk,out buffered port:8 p);

[[combinable]] extern void interrupt_manager(in port iport,unsigned count,struct interrupt_mask_t masks[count],client interface interrupt_if int_if[count]);


#endif /* RXTX_H_ */


