/*
 * rxtx.xc
 *
 *  Created on: 11 Aug 2015
 *      Author: lester.crespo
 *
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
 *  CH0_RX ---> CMD ---   ---CH1_RX
 *                    ^   ^
 *  CHO_TX <-------- ROUTER <----- CH1_TX
 *

 *
 *
 * TODO Combinable task using clocked port.
 * case p <: data:  // executed when buffered port is ready
 * Sendign state ( 0 - idle , 1 - sending, 2 - waiting for time )
 *
 * Modify buffer behavior
 * max-size, use-count, next-write
 * if uxe-count == max-size then full
 * next-write is increment on each store
 * next to read is (next-write + max-size + use_count) % max-size
 */

#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>
#include "rxtx.h"

/*
 * v7
 * wait for 1 read as 8bit buffered port at 2 times freq.
 *
 * timing for a 2ns reader clock
 * 142 ns from signal high after 8 bits are read.
 *  50 ns to process start bit
 *  90 ns to parser normal bits
 * 120 ns last bit
 *
 */
void fastRX_v7(streaming chanend ch,in buffered port:8 p,clock clk,out port d1)
{
  unsigned char d;
  unsigned dt,i;
  configure_clock_xcore(clk,2);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  i = 0;
  while(1)
  {
//    d1 <: 1;
//    d1 <: 0;
    //p when pinseq(0) :> void;
    p when pinseq(1) :> void;
    p :> d;  // get next 8 bits  //
    if ( d > 64)
    {
      if (i != 0 )
        ch <: (unsigned char)0xFF;
      i = 0;    // if i !=0 then error
      continue;
    }
    dt = dt << 1; // rotate current data always. it makes space for next bit
    if ( d  > 8)
        dt = dt | 1;
    i++;
    if (i == 8)
    {
      ch <: (unsigned char)dt;
      i = 0;
    }
  }
}

/*
 * RX needs between 160 - 230 ns to parse each bit
 * it react in 46ns, 2*f need to be more than 46ns to catch 2T pulse
 * 24ns pulse produce a 192ns length byte
 * A second byte with zero is need to readch 230ns needed by rx task
 *
 * timing
 * 0 -
 * 46ns(up)
 * + 96ns read 8 bits
 * +
 *
 * 1byte = 9 * 192 = 1728ns = 0.5Mbytes sec = 4Mbits/s
 *
 * Upper limit is
 * 192ns per bit, 1728ns per byte, 578703.7bytes/sec 556.1403Kb/sec 5Mbyte/sec
 *
 * 1920ns per byte 520.833bytes/sec
 */
[[distributable]] void fastTX_v7(server interface tx_if tx,clock clk,out buffered port:8 p)
{
  configure_clock_xcore(clk,6);     // 24ns
  configure_in_port(p, clk);
  start_clock(clk);
  while(1)
  {
    select
    {
      case tx.send(const char* data,unsigned char len):
        // Give two bytes packet gap
        p <: (unsigned short)0;
        while(len--)
        {
          p <: (unsigned char)0x7;    //start
          unsigned dt = *data++;
          unsigned i = 8;
          while(i--)
          {
            if (dt & 0x80)
              p <: (unsigned char)0x03;
            else
              p <: (unsigned char)0x01;
            dt <<=1;
          }
          p <: (unsigned char)0x0;  //24 * 8 = 192ns
        }
        break;
    }
  }
}
/*
 * Each interface has until 8 frames to process in the router.
 */
#define frame_buffer_list_max (1 << 2)  // 4

struct frames_buffer
{
  unsigned char rd_idx;    // first element to read
  unsigned char count;     // how many elements
  struct rx_u8_buff* movable list[frame_buffer_list_max];
};

/*
 * All packet will came to this interface for deliverying
 * All TX task will be combine in one.#
 * All RX will be alone in a core
 * Command can be combine with tx also.
 */
[[distributable]] void Router_v2(server interface packet_tx_if tx_if[max_tx],server interface rx_frame_if rx_if[max_rx])
{
#define max_frame 16
  unsigned free_count;  // first free frame on list, every frame below this is null
  struct rx_u8_buff frm[max_frame];
  struct rx_u8_buff * movable free_list[max_frame] = { &frm[0],&frm[1],&frm[2],&frm[3],&frm[4],&frm[5],&frm[6],&frm[7],&frm[8],&frm[9],&frm[10],&frm[11],&frm[12],&frm[13],&frm[14],&frm[15]};
  struct frames_buffer frames[max_tx];    // frames per interface
  for (int i = 0;i<max_tx;++i)
  {
   frames[i].count = 0;
   frames[i].rd_idx = 0;
  }
  free_count = max_frame;
  while(1)
  {
    select
    {
    case tx_if[int j].get(struct rx_u8_buff  * movable &old_p,enum tx_task dest):
      // get first on the list
      if (old_p != 0)
      {
        free_list[free_count++] = move(old_p);
      }
      if (frames[dest].count != 0)
      {
        old_p = move(frames[dest].list[frames[dest].rd_idx]);
        frames[dest].rd_idx = (frames[dest].rd_idx + 1) & (frame_buffer_list_max -1);
        frames[dest].count--;
      }
      if (frames[dest].count != 0)
        tx_if[j].ondata();
      break;
    case tx_if[int _].push(struct rx_u8_buff  * movable &old_p):
      free_list[free_count++] = move(old_p);
      break;
        // an input task push data, it need back a free buffer.
    case rx_if[int _].push(struct rx_u8_buff  * movable &old_p,enum tx_task j):
      if (frames[j].count != frame_buffer_list_max && free_count)
      {
        unsigned char pos = (frames[j].rd_idx + frames[j].count) & (frame_buffer_list_max -1);
        frames[j].list[pos] = move(old_p);
        frames[j].count++;
        if (frames[j].count == 1)
          tx_if[j].ondata();
        // return a free buffer
        free_count--;
        old_p = move(free_list[free_count]);
      }
      break;
    }
  }
}

/*
 * Task for tx interface.
 */
[[combinable]] void TX_Worker(client interface packet_tx_if tx_input[max_tx],client interface tx_if tx_out[max_tx])
{
  while(1)
  {
    select
    {
      case tx_input[int j].ondata():
        struct rx_u8_buff  * movable pfrm;
        tx_input[j].get(pfrm,j);
        if (pfrm != 0)
        {
          tx_out[j].send(pfrm->dt,pfrm->len);
          tx_input[j].push(pfrm);
        }
        break;
    }
  }
}
/*
 * Create a packet from data comming from channel
 */
void RX_Packer(streaming chanend ch,unsigned timeout,client interface rx_frame_if rx_input,enum tx_task dest)
{
  struct rx_u8_buff tfrm;   // temporal frame
  struct rx_u8_buff * movable pframe = &tfrm;
  timer t;
  unsigned tp;

  while(1)
  {
    select
    {
      case ch :> unsigned char dt:
        if (pframe->len == sizeof(pframe->dt))
          pframe->overflow++;
        else
        {
          pframe->dt[pframe->len] = dt;
        }
        break;
      case pframe->len => t when timerafter(tp):> void:
        rx_input.push(pframe,dest);
        pframe->len = 0;
        pframe->overflow = 0;
        break;

    }
  }
}

/*
 * Fast rx tx v8.
 * Starting at t0. as high pulse. using T as period.
 * The distance between Tstart and the pulse is the data.
 *
 * |-----|----|  1 - long distance.
 * 0          T
 *
 * |--|-------|  0 - short distance
 * 0          T
 *
 * Rx will read until a zero is inputed.
 * clz function returns distance of pulse
 *
 * v9
 * using a xorg output
 * a clock two times faster than data is xored with data
 * then 1 become 01 and 0 become 10
 * a high pulse is need to start reading the port.
 * sample point at middle of second bit.
 * wait port high or timeout  (5x) 50ns
 * wait T/2
 * read and shift data.
 * check for 8th bit and push data to channel (inc,cmp,send) 30ns
 * timeout as interbyte delay
 * timeout as interframe delay
 *
 * 4ns pulse is read as 0
 * 12ns pulse is read as 1
 */
