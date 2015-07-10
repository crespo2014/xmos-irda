/*
 * one-wire.xc
 *  unidirectional 1 wire protocol.
 *  We use two wires 1 for RX and other for TX.
 *  it is like a serial port
 *  Each device act as a hub , rerouting incoming data from one interface to another that introduce a delay in client response.
 *  We want to support continuos data comming from clients.
 *
 *  I need to create a protocol over this interface.
 *  (id)(cmd)(data)
 *
 *  Protocol
 *  ID - device id, it is decremented every time it pass a bridge. when it reach zero the device become active and send remaining data to process unit.
 *  DATA : max size of data will be 10 bytes to allow buffering
 *  (cmd + data)
 *  WR (bit7) + addres( 7bits 0-128) + data    <=== id + cmd + address or (NOK)
 *
 *  each command will recevied an ack - sent commands will be in a queue waiting for ack until certian time elapse (timeout)
 *
 *                -------------------
 *  ---- RX -----|                   |------- TX -----
 *  CH0          |  **CMD UNIT   **  |  CH2
 *  ---- TX -----|  ** RPL QUEUE **  |-------- RX ----
 *                -------------------
 *  Data comming from Ch0 will got to cmd unit if id was 0 or to CH2
 *  Data coming from CH2 go to a queue to be send to CH0
 *  cmd unit also push data to queue
 *
 *  Created on: 10 Jul 2015
 *      Author: lester.crespo
 */

#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>

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
};

void owire_tx_start(struct one_wire & rthis) {
    rthis.TX <: 1;
    rthis.t :> rthis.tp;
    rthis.tp += 4*rthis.T;
    rthis.t when timerafter(rthis.tp) :> void;
    rthis.TX <: 0;
}

/*
 * Keep pin low for 4T to signal end
 */
void owire_tx_end(struct one_wire & rthis) {
    rthis.tp += 4*rthis.T;
    rthis.t when timerafter(rthis.tp) :> void;
}

void owire_tx(struct one_wire & rthis,char data[],unsigned count)
{
    char*  pd;
    owire_tx_start(rthis);
    for (pd=data;count!=0;count--,pd++)
    {
        for (int i=8;i!=0;--i)
        {
            // keep signal low for T
            rthis.tp += rthis.T;
            rthis.t when timerafter(rthis.tp) :> void;
            rthis.TX <: 1;
            // size of pulse
            if ( *pd & 0x80 )
               rthis.tp += 2*rthis.T;
            else
                rthis.tp += 2*rthis.T;
            (*pd) <<=1;
            rthis.t when timerafter(rthis.tp) :> void;
            rthis.TX <: 0;
        }
    }
    // Keep pin low for 4T to signal end
    rthis.tp += 4*rthis.T;
    rthis.t when timerafter(rthis.tp) :> void;
}

/*
 * read a byte
 */
char owire_rx_getByte(struct one_wire & rthis)
{

}
/*
 * Call this function to read all command data after recevied the id
 * recieving a start will return 0
 */
void owire_rx(struct one_wire & rthis, char data[], unsigned & max) {
    char * pd = data;
    char * pend = data + max;

    int pv; // port value
    char bitcount = 0; // how many bits have been received invalid if > 64
    int ts; // start time of data
    int te; // time end of transation

    rthis.RX :> pv;
    rthis.t :> ts;
    for (;;) {
        // wait for pin transition
        select
        {
            case rthis.t when timerafter(ts+rthis.T*2.5) :> void: // timeout
            if (pv == rthis.high)
            {
                // start condition
                rthis.rx_status = w_id;
                max = 0;
                return;
            } else
            {
                // end of data
                rthis.rx_status = w_start;
                max = pd - data;
                break;
            }
            break;
            case rthis.RX when pinsneq(pv) :> pv: // for t < 1.5 is 0 otherwise is 1
            rthis.t :> te;
            if (pv == !rthis.high)
            {
                (*pd) <<= 1;
                if (te - ts > rthis.T*1.5) (*pd) |= 1;
                bitcount++;
                if (bitcount == 8)
                {
                    bitcount = 0;
                    pd++;
                    if (pd == pend)
                    {
                        max = pd - data;
                        return;
                    }
                }
            }
            ts = te;
            break;
        }
    }
}
