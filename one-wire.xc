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
 *  ---- TX -----|                   |-------- RX ----
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

/*
 * Command task
 */

void CMD(server interface cmd_if cmd,server interface tx_if tx,client interface rx_if rx)
{
  timer t;
  unsigned tp;
  struct tx_frame_t   frm;
  struct tx_frame_t* movable p = &frm;

  t :> tp;
  for (;;)
  {
      while (rx.get(p) == 1)
      {
          //printf("%c\n",p->dt[0]);
          p->len = 0;
      };
      select
      {
          case rx.onrx():
          break;
      }
      //printf("on data\n");
  }
}

/*
 * Transmition channel 0
 */
#define MAX_FRAME 4
#define TX_HIGH  1
#define TX_LOW   0

void TX(client interface tx_if tx,out port TX,unsigned T)
{
  struct tx_frame_t frm;
  timer t;
  int tp;
  struct tx_frame_t* movable pfrm = &frm;

  TX <: TX_LOW;
  t :> tp;
  t when timerafter(tp + 4*T) :> tp;    // wait 4 cycles
  for(;;)
  {
    t :> tp;
    // peek and send data
    while (tx.get(pfrm) == 1)
    {
      // send data
      if (pfrm->len != 0)
      {
        // send start bit
        TX <: TX_HIGH;
        t when timerafter(tp + 3*T) :> tp;
        TX <: TX_LOW;
        t when timerafter(tp + T) :> tp;
        for (unsigned char pos = 0;pos < pfrm -> len;++pos)
        {
          unsigned char dt = pfrm->dt[pos];
          for (unsigned char bit = 8;bit !=0;--bit)
          {
            TX <: TX_HIGH;
            tp += T;
            if (dt & 0x80)   //1 is 2T 0 is T
              tp += T;
            t when timerafter(tp) :> tp;
            TX <: TX_LOW;
            t when timerafter(tp + T) :> tp;
            dt <<= 1;
          }
        }
        // send stop bit
        t when timerafter(tp + 3*T) :> tp;
      }
    }
    // wait for more data
    select
    {
      case tx.ontx():
        break;
    }
  }
}

/*
 * RX channel 0
 * Data will be buffered from start signal to end one
 * Ones de buffer is full the cmd inteface will be notified
 * cmd interface will pick the buffer and can send also to tx interface, but tx has to send back
 *
 * if data comming faster then cmd processing will no eat all of then, at position of last read frame will be hold to pick all cmd from
 * that place
 *
 * 1. reduce instructions by using not null pointers.
 *
 */
void RX(server interface rx_if ch0rx,client interface cmd_if cmd,in port RX,unsigned T)
{
    struct tx_frame_t cfrm;
    struct tx_frame_t frm[MAX_FRAME];
    struct tx_frame_t* movable pfrm[MAX_FRAME] = {&frm[0],&frm[1],&frm[2],&frm[3]};
    struct tx_frame_t* movable wr_frame = &cfrm;      // currently writting in this frame
    timer t;      // timer
    int tp;       // time point
    unsigned char pv;            // current rx pin value
    unsigned char bitcount = 0; // how many bits have been received invalid if > 64
    unsigned char val;          // coping incoming bytes to this variable
    // bitcount can be use as timeout status. it vaue is 0xFF then a timeout was received then next transition must be ignored
    const unsigned char high = 1;

    for (int i = 0;i < MAX_FRAME;++i)
    {
        pfrm[i]->dt[0] = 'A' + i;
        pfrm[i]->len = 0;
    }
    wr_frame = move(pfrm[0]);
    t :> tp;    // get current time
    RX :> pv;
    for (;;)
    {
       select {
        case ch0rx.get(struct tx_frame_t  * movable &old_p) -> unsigned char b :
            // find a frame with data
            b = 0;
            for (int i = 0;i < MAX_FRAME;++i)
            {
              if (pfrm[i]->len != 0)
              {
                struct tx_frame_t  * movable tmp;
                tmp = move(old_p);
                old_p = move(pfrm[i]);
                pfrm[i] = move(tmp);
                b = 1;
                break;
              }
            }
            break;
            // wait for pin transition or timeout
        case t when timerafter(tp+T*2.5) :> tp: // timeout (adjusting tp will be a problem for start condition, when signal go dow, the pulse width seems to be short
            if (pv == high)
            {
                // start condition
                wr_frame->len = 0;
                bitcount = 0xFF;    // invalidate next transition (long low level does not produce data when go high, not need to set bit to 0xFF)
            } else
            {
              // end of data it will happens many times when we are waiting for start signal
              if (wr_frame->len !=0)
              {
                // add full frame to list and notify
                for (int i = 0;i < MAX_FRAME;++i)
                {
                  if (pfrm[i]->len == 0)
                  {
                    struct tx_frame_t  * movable tmp;
                    tmp = move(wr_frame);
                    wr_frame = move(pfrm[i]);
                    pfrm[i] = move(tmp);
                    ch0rx.onrx();
                    break;
                  }
                }
                if (wr_frame->len != 0)   // there is not empty frame
                {
                   printf(".\n");
                   wr_frame->len = 0;   // reuse the same frame
                }
              }
            }
            break;
            case RX when pinsneq(pv) :> pv: // for t < 1.5 is 0 otherwise is 1
              int te;
              t :> te;
              if (pv == !high)
              {
                if (bitcount < 8) // is this a transition of start signal?
                {
                  val <<= 1;
                  if (te - tp > T*1.5) val |= 1;
                  bitcount++;
                  if (bitcount == 8)
                  {
                    wr_frame->dt[wr_frame->len] = val;
                    wr_frame->len++;
                    bitcount = 0;
                    val = 0;
                  }
                } else
                {
                  bitcount = 0; // it was a start signal going low, just ignore, but now we are ready to store data next time
                }
              }
              tp = te;
              break;
       }
    }

}
