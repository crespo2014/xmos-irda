/*
 * rxtx.h
 *
 *  Created on: 14 Jul 2015
 *      Author: lester.crespo
 */


#ifndef RXTX_H_
#define RXTX_H_

#define sec 1000*1000*100
#define ms  1000*100
#define us  100        // 1 usecond

#define T_36Khz 27*us

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

[[combinable]] extern void Router(
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

#endif /* RXTX_H_ */


