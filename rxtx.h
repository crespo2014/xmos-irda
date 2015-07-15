/*
 * rxtx.h
 *
 *  Created on: 14 Jul 2015
 *      Author: lester.crespo
 */


#ifndef RXTX_H_
#define RXTX_H_

#define Hz   100*1000*1000 // timer frecuency in Hz

enum rx_status_e
{
    w_start,    // waiting start
    w_id,       // waiting id
    d_bridge,   // act as bridge
    d_cmd,      // reading cmd
};
struct one_wire
{
    enum rx_status_e rx_status;         //waiting start,waiting id, bridge, processing
    in port RX;
    out port TX;
    unsigned T;  // frecuency
    unsigned tp; // time point of current low level, set up after start bit.
    timer t;
    char  high;     // polarity
    char  pv;       // last rx port value
};

/*
 * Transmition channel has a list of frames to send
 * it use a pointer that circle looking for full frames forwards and backwards looking for free frames
 */
struct tx_frame_t
{
    unsigned char    dt[20];
    unsigned char    len;        //0 all data has been sent
    //enum { free,writting, reading } st;         //0 - free, 1 - writing , 2 - reading
};

/*
 * Command interface, or inteface that process incomming data
 */
interface cmd_if {
    void nothing();
};

/*
 * Generic Tx interface.
 * Tx module acts as client waiting for ontx notification
 */
interface tx_if {
    [[notification]] slave void ontx();           //data waiting to be send
    [[clears_notification]] unsigned char get(struct tx_frame_t  * movable &old_p);  // get pointer to frame true if pointer is get
};

/*
 * Generic RX interface.
 * RX module acts as server, it send notifications when data can be read
 */
interface rx_if {
    [[notification]] slave void onrx();       // data waiting to be read
    [[clears_notification]] unsigned char get(struct tx_frame_t  * movable &old_p);  // get pointer to frame true if pointer is get
};

extern void CMD(server interface cmd_if cmd,server interface tx_if tx,client interface rx_if rx);
extern void CH0_RX(server interface rx_if ch0rx,client interface cmd_if cmd,in port RX,unsigned T);
extern void CH0_TX(client interface tx_if tx,out port TX,unsigned T);
extern void CH1_RX(server interface rx_if ch0rx,client interface cmd_if cmd,in port RX,unsigned T);
extern void CH1_TX(client interface tx_if tx,out port TX,unsigned T);

#endif /* RXTX_H_ */
