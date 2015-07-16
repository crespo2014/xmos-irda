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
 * Command interface, or inteface that process incomming data
 */
interface cmd_if {
    void nothing();
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
 * Generic Tx interface.
 * Tx module acts as client waiting for ontx notification
 */
interface tx_if {
    [[notification]] slave void ondata();           //data waiting to be send
    [[clears_notification]] unsigned char get(struct tx_frame_t  * movable &old_p);  // get pointer to frame true if pointer is get
};

/*
 * Generic RX interface.
 * RX module acts as server, it send notifications when data can be read
 */
interface rx_if {
    [[notification]] slave void ondata();       // data waiting to be read
    [[clears_notification]] unsigned char get(struct tx_frame_t  * movable &old_p);  // get pointer to frame true if pointer is get
};
/*
 * Router interface is a buffer o frames with a destination
 * It will dispatch frames to many tx interfaces.
 * It will read from many interfaces data ( data need to be buffered)
 * Data will be pick from all interface in a circular way one at the time.
 * a counter of empty frames will optimize
 *
 */
interface route_if {
  void nothing();
};

extern void CMD(client interface cmd_push_if router);
extern void RX(server interface rx_if rx,in port RX,unsigned T);
extern void TX(client interface tx_if tx,out port TX,unsigned T);
extern void Router(server interface tx_if ch0_tx,server interface tx_if ch1_tx,client interface rx_if ch0_rx,client interface rx_if ch1_rx,server interface cmd_push_if cmd);
//for join ch1 rx to ch0 tx

#endif /* RXTX_H_ */
