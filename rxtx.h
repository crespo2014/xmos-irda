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

#define SYS_TIMER_T_ns  10   //set to 100 for testing

#define sec 100000000
#define ms  100000
#define us  100        // 1 usecond
#define ns  (1/SYS_TIMER_T_ns)





/*
 *  0..|..|..|..|..|..|..|
 */

/*
 * Transmition channel has a list of frames to send
 * it use a pointer that circle looking for full frames forwards and backwards looking for free frames
 * TODO add start index to allow layers of protocols
 */
struct tx_frame_t
{
  unsigned int    len;
  unsigned char    dt[20];
};

/*
 * Push interface.
 * Interface to push data on router.
 * - push function will never fail unless all buffer are full.
 * - a trigger is received when data is ready
 * - get data can fail
 */
interface cmd_push_if {
  [[notification]] slave void ondata();       // means data is waiting to be read
  [[clears_notification]] unsigned char get(struct tx_frame_t  * movable &old_p); //push data on the router it never fails
  unsigned char push(struct tx_frame_t  * movable &old_p); //push data on the router it must not fail
};

/*
 * Generic TX RX interface.
 * It notifies when data can be read
 * It acts as server on RX and as client in TX
 */
interface tx_rx_if {
    [[notification]] slave void ondata();       // data waiting to be read
    [[clears_notification]] unsigned char get(struct tx_frame_t  * movable &old_p);  // get pointer to frame true if pointer is get
};

struct irda_tx_frame
{
    unsigned int dt;    // unsigned long long is a 64Bits type
    unsigned char bits;
};
/*
 * Irda tx is able to send until 32bits of data
 */
interface irda_tx_if {
    [[notification]] slave void ondata();       // data waiting to be read
    [[clears_notification]] unsigned char get(struct irda_tx_frame  * movable &old_p);  // get pointer to frame true if pointer is get
};

/*
 * Fault reporting interface
 */
interface fault_if {
  void fault(unsigned int id);
};

[[combinable]] extern void CMD(
    client interface cmd_push_if router,
    server interface tx_rx_if irda_tx,
    client interface tx_rx_if irda_rx,
    client interface fault_if fault);

[[distributable]] extern void Router(
    server interface tx_rx_if ch0_tx,
    server interface tx_rx_if ch1_tx,
    client interface tx_rx_if ch0_rx,
    client interface tx_rx_if ch1_rx,
    server interface cmd_push_if cmd,
    client interface fault_if fault);

extern void RX(
    server interface tx_rx_if rx,
    in port RX,unsigned T,
    client interface fault_if fault);

extern void TX(
    client interface tx_rx_if tx,
    out port TX,unsigned T);

extern void irda_TX(
    client interface tx_rx_if tx,
    out port TX,
    unsigned T,
    unsigned char low,
    unsigned char high);

[[combinable]] extern void irda_RX(
    server interface tx_rx_if rx,
    in port RX,
    unsigned T,
    unsigned char high,
    client interface fault_if fault);

[[combinable]] extern void ui(
    out port p,
    server interface fault_if ch0_rx,
    server interface fault_if ch1_rx,
    server interface fault_if router,
    server interface fault_if cmd,
    server interface fault_if irda_rx);

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

/*
 * Interface suporting buffered
 * Channel less
 */
interface rx_if_v3
{
  void push(unsigned int dt);
  [[notification]] slave void error();
  [[clears_notification]] void ack();
  void setSpeed(unsigned int baud);       // baud rate or line speed
};

/*
 * Keep buffer on tx task
 */
interface tx_if_v3
{
  unsigned char push(unsigned int dt);    // 0 - ok 1 -overflow
  void setSpeed(unsigned int baud);       // baud rate or line speed
};

interface buffer_v3_if
{
  [[notification]] slave void onRX();
  [[clears_notification]] unsigned char get(struct tx_frame_t  * movable &old_p);
  [[clears_notification]] unsigned int pull();  // for irda
  unsigned char push(unsigned int dt);
  unsigned char write(const unsigned char* dt,unsigned char len);
  unsigned char printf(const char* str);

};

interface fast_tx
{
  void push(unsigned char dt);
};

[[distributable]] extern void fastTX(server interface fast_tx tx_if,clock clk,out buffered port:32 p);
extern void fastRX(streaming chanend ch,in port p);
extern void fastRXParser(streaming chanend ch);

#endif /* RXTX_H_ */


