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
    void donothing();
};

/*
 * Tx on channel 0
 * Sever keeps a list of pointers plus current pointer idx
 * Requesting a frame will find the first pointer to a block with len == 0.
 * Pushing a frame will be on the first nullptr.
 * when current block is
 * - len = 0 that means nothing to send. it canbe pick it next time
 * - null (frame is comming soon, )
 * -
 */
interface ch0_tx_if {
    struct tx_frame_t  * movable getSlot();             //get a free slot for data buffering (0xff or -1 not free slot)
    void sendSlot(struct tx_frame_t  * movable &frm);
};

/*
 * Channel 0 rx interface provide buffers to cmd interface
 * TODO : provide also for tx interface, act as hub
 */
interface ch0_rx_if {
    [[notification]] slave void ondata();
    [[clears_notification]] unsigned char getcmd(struct tx_frame_t  * movable &old_p);  // get pointer to frame true if pointer is get

    /*
     * [[clears_notification]] unsigned char getForward(struct tx_frame_t  * movable &old_p);     // use by tx interface
     * [[notification]] slave void onForward(); // frame for forwarding
     */
};

extern void CMD(server interface cmd_if cmd,client interface ch0_tx_if tx,client interface ch0_rx_if rx);
extern void CH0_RX(server interface ch0_rx_if ch0rx,client interface cmd_if cmd,in port RX,unsigned T);

#endif /* RXTX_H_ */
