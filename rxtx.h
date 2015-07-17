/*
 * rxtx.h
 *
 *  Created on: 14 Jul 2015
 *      Author: lester.crespo
 */


#ifndef RXTX_H_
#define RXTX_H_

#define Hz   100*1000*1000 // timer frecuency in Hz

/*
 * Transmition channel has a list of frames to send
 * it use a pointer that circle looking for full frames forwards and backwards looking for free frames
 */
struct tx_frame_t
{
    unsigned char    dt[20];
    unsigned char    len;
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

[[combinable]] extern void CMD(client interface cmd_push_if router);
extern void RX(server interface tx_rx_if rx,in port RX,unsigned T);
extern void TX(client interface tx_rx_if tx,out port TX,unsigned T);
[[combinable]] extern void Router(server interface tx_rx_if ch0_tx,server interface tx_rx_if ch1_tx,client interface tx_rx_if ch0_rx,client interface tx_rx_if ch1_rx,server interface cmd_push_if cmd);

#endif /* RXTX_H_ */
