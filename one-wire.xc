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
 *  TODO:
 *  Read byte by byte and resend
 *
 *  Created on: 10 Jul 2015
 *      Author: lester.crespo
 */

#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>
#include <rxtx.h>

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
 * if status != reading then a end signal receive
 */
char owire_rx_getByte(struct one_wire & rthis)
{
    int pv; // port value
    char bitcount = 0; // how many bits have been received invalid if > 64
    int te; // time end of transation
    char val;

    // wait level low, then high
    rthis.RX :> pv;
    rthis.t :> rthis.tp;
    do {
        // wait for pin transition
        select
        {
            case rthis.t when timerafter(rthis.tp+rthis.T*2.5) :> void: // timeout
            if (pv == rthis.high)
            {
                // start condition
                rthis.rx_status = w_id;
                return 0;
            } else
            {
                // end of data
                rthis.rx_status = w_start;
                break;
            }
            break;
            case rthis.RX when pinsneq(pv) :> pv: // for t < 1.5 is 0 otherwise is 1
            rthis.t :> te;
            if (pv == !rthis.high)
            {
                val <<= 1;
                if (te - rthis.tp > rthis.T*1.5) val |= 1;
                bitcount++;
            }
            rthis.tp = te;
            break;
        }
    } while(bitcount < 8);
    return val;
}
/*
 * Call this function to read all command data after recevied the id
 * recieving a start will return 0
 */
void owire_rx(struct one_wire & rthis, char data[], unsigned & max) {
   // char * pd = data;
    //char * pend = data + max;

    // read bytes until status w_id
}


/*
 * Command module
 */

void CMD(client interface ch0_tx_if tx)
{
  timer t;
  unsigned tp;
  t :> tp;
  for (;;)
  {
    t when timerafter(tp+Hz) :> void;
    t :> tp;
  }
}

/*
 * Transmition channel 0
 */
#define MAX_FRAME 8
#define TX_HIGH  1
#define TX_LOW   0

void CH0_TX(server interface ch0_tx_if tx,out port TX,unsigned T)
{
    struct tx_frame_t frm[MAX_FRAME];
    struct tx_frame_t frm0,frm1,frm2,frm3,frm4,frm5,frm6,frm7;
    timer t;
    int tp;
    // initialize MAX_FRAME movable pointer
    struct tx_frame_t* movable pframes[MAX_FRAME] = { frm,&frm1,&frm2,&frm3,&frm4,&frm5,&frm6,&frm7 };

    signed char rd_idx = -1;      // current read frame
    unsigned char rd_idx_pos = 0;  // currently sending byte
    unsigned char rd_bit;      // currently sending bit   16 high pulse, 15 low pulse and so until 0 (18 is the start bit)
    unsigned char dt;         // data to send
    for (int i =0;i<MAX_FRAME;++i)
    {
      pframes[i]->len = 10;
    }
    t :> tp;
    for (;;)
    {
    select {
        case tx.getSlot() -> struct tx_frame_t  * movable frm:
        // Find a slot with len 0
          char pos = rd_idx;
          do
          {
            if (pframes[pos] != null && pframes[pos]->len == 0)
            {
              frm = move(pframes[pos]);
              break;
            }
            ++pos;
            if (pos == MAX_FRAME)
              pos = 0;
          } while (pos != rd_idx);
          break;
        case  tx.sendSlot(struct tx_frame_t  * movable &frm):
          // Find a slot pointer to null
          char pos = rd_idx;
          do
          {
            if (pframes[pos] == null)
            {
              pframes[pos]  = move(frm);
              break;
            }
            ++pos;
            if (pos == MAX_FRAME)
              pos = 0;
          } while (pos != rd_idx);
          // restart transmition machine
          if (rd_idx == -1)
          {
            t :> tp;
            tp += 4*T;  // wake up at early than 1sec
            rd_idx = pos;
          }
          break;
         // case time to send more data, check for pending buffer.
        case t when  timerafter(tp) :> void:
          if (rd_idx == -1)   // if we are not sending data
          {
            // find another frame to send
            char pos = rd_idx;
            do
            {
              if (pframes[pos] != null && pframes[pos]->len != 0)
              {
                // send start bit next time
                 rd_idx = pos;
                 rd_idx_pos = 0;
                 break;
              }
              ++pos;
              if (pos == MAX_FRAME)
                pos = 0;
            } while (pos != rd_idx);
          }
          if (rd_idx == -1)
          {
            tp += Hz; // wake up 1 sec later.
          }
          else
          {
            if (rd_idx_pos == 0)    // start sending first byte of this frame
            {
              // send start bit
              rd_bit = 18;    // 18 start bit, 17 and odd is zero, 16 bit 8 ... 2 bit 1, 1 .. zero, 0 next
              TX <: TX_HIGH;
              tp += 4*T;
              dt = pframes[rd_idx]->dt[rd_idx_pos];
              rd_idx_pos++;
            }
            else
            {
              if (rd_bit == 0)    // one byte done
              {
                  // start sending next byte
                  if (rd_idx_pos == pframes[rd_idx]->len)
                  {
                      // no more data to send
                      tp += 3*T;
                      pframes[rd_idx]->len = 0;
                      rd_idx = -1;
                  }
                  else
                  {
                      rd_bit = 16;
                      dt = pframes[rd_idx]->dt[rd_idx_pos];
                      rd_idx_pos++;
                  }
              }
              if (rd_bit != 0)  // send bit of data
              {
                // send data
                if ((rd_bit & 1) == 0)  // even number (data 1 or 2 T)
                {
                   TX <: TX_HIGH;
                   if ((dt & 1) == 1)
                       tp += 2*T;
                   else
                       tp += T;
                   dt >>= 1;
                }
                else    // odd number (low for T)
                {
                   TX <: TX_LOW;
                   tp += T;      // keep low only for T
                }
                rd_bit--;
              }
            }
          }
          break;
    }
    }
}

/*
 * Tx channel can recieved data one by one using a channel.
 * then an interface can be use to signal end and start buy meybe there is not sync between chn an if. this is not goofd
 *
 *
 */
