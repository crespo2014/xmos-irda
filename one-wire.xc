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
 *  CH0_RX ---> CMD ---   ---CH1_RX
 *                    ^   ^
 *  CHO_TX <-------- ROUTER <----- CH1_TX
 *
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
#include "irda.h"


 enum dest_e {
    to_none,
    to_cmd,
    to_ch0_tx,
    to_ch1_tx,
  };

/*
 * Frame buffer structure
 * - support for destinity
 * - support for peek and push
 *
 */
struct frm_buff_t
{
#define BUFF_MAX 8
  enum dest_e dest[BUFF_MAX];
  struct tx_frame_t* movable pfrm[BUFF_MAX];// = {&frm[0],&frm[1],&frm[2],&frm[3],&frm[4],&frm[5],&frm[6],&frm[7]};
  unsigned char free_count;  // how many frame with no data
};

/*
 * Initialize frame buffer structure
 */
void buff_init(struct frm_buff_t &buff)
{
  buff.free_count = BUFF_MAX; // all frames empty
  for (int i =0 ;i < BUFF_MAX;i++)
  {
    buff.dest[i] = to_none;
    buff.pfrm[i]->len = 0;
  }
}
/*
 * Get a frame from buffer
 */
inline unsigned char buff_get(struct frm_buff_t &buff,enum dest_e dst,struct tx_frame_t  * movable &old_p)
{
  if (buff.free_count != BUFF_MAX)
  {
    for (int i =0 ;i < BUFF_MAX;i++)
    {
      if ( buff.dest[i] == dst)
      {
        struct tx_frame_t  * movable tmp;
        tmp = move(old_p);
        old_p = move(buff.pfrm[i]);
        buff.pfrm[i] = move(tmp);
        buff.free_count++;
        return 1;
      }
    }
  }
  return 0;
}
/*
 * Add a new frame to the buffer
 */
inline unsigned char buff_push(struct frm_buff_t &buff,enum dest_e dst,struct tx_frame_t  * movable &old_p)
{
  if (buff.free_count != 0)
   {
     for (int i =0 ;i < BUFF_MAX;i++)
     {
       if ( buff.dest[i] == to_none)
       {
         struct tx_frame_t  * movable tmp;
         old_p->len = 0;
         tmp = move(old_p);
         old_p = move(buff.pfrm[i]);
         buff.pfrm[i] = move(tmp);
         buff.dest[i] = dst;
         buff.free_count--;
         return 1;
       }
     }
   }
   return 0;
}

/*
 * Send a irda packet from msb to lsb
 * Send high for 3T then send 1 as high for 2T an 0 as high for 1T
 * end signal is low for 3T
 */
inline void irda_send(unsigned int v,unsigned char bitcount,unsigned char high,unsigned char low,out port p, unsigned int BIT_LEN)
{
  timer t;
  unsigned int tp;
  unsigned int len;
  unsigned int bitmask = 1 << (bitcount -1);
  // send start bit
  len = 4*BIT_LEN;
  IRDA_PULSE(27*us,tp,len,t,p,1,0);
  tp += BIT_LEN;
  t when timerafter(tp) :> void;
  // send data
  while (bitmask != 0)
  {
      len = BIT_LEN;
      if (v & bitmask)   //1 is 2T 0 is T
          len += BIT_LEN;
      IRDA_PULSE(27*us,tp,len,t,p,1,0);
      tp += BIT_LEN;
      t when timerafter(tp) :> void;
      bitmask >>= 1;
  }
  // keep low for stop bit
  t when timerafter(tp + 3*BIT_LEN) :> tp;
}

/*
 * Send bytes from 0 to n from MSB to LSB
 * High for 3T low for 1T
 * Send data high for 2t if 1 or higj for 1T if 0
 * Stop as low for 3T
 */
inline void send(const char* dt,char count,unsigned char high,unsigned char low,out port p, unsigned int T)
{
  unsigned char bitmask;
  timer t;
  int tp;
  // send start bit
  p <: high;
  t :> tp;
  t when timerafter(tp + 3*T) :> tp;
  p <: low;
  t when timerafter(tp + T) :> tp;
  while (count)
  {
    bitmask = (1<<7);
    while (bitmask)
    {
      p <: high;
      tp += T;
      if ((*dt) & bitmask)   //1 is 2T 0 is T
        tp += T;
      t when timerafter(tp) :> tp;
      p <: low;
      t when timerafter(tp + T) :> tp;
      bitmask >>= 1;
    }
    --count;
    ++dt;
  }
  // keep low for stop bit
  t when timerafter(tp + 3*T) :> tp;
}

/*
 * Packet router.
 * All packets are delivery to the router
 * router will read from all places until buffers become all full
 * when buffer are empty router does not select for TX interfaces.
 * when buffer are all full routers oly select on tx channels.
 *
 * - purge all incoming data
 * - wait on TX and RX signals and push from cmd interface if buffer is not full.
 * - wait on TX if buffer is full
 * - repeat
 *
 * cmd interface will be like a RX, it will pick from Rx, process, signal, wait for purge
 */
[[combinable]]
void Router(server interface tx_rx_if ch0_tx,
            server interface tx_rx_if ch1_tx,
            client interface tx_rx_if ch0_rx,
            client interface tx_rx_if ch1_rx,
            server interface cmd_push_if cmd)
{
  struct tx_frame_t frm[BUFF_MAX];
  struct frm_buff_t buff = {{},{&frm[0],&frm[1],&frm[2],&frm[3],&frm[4],&frm[5],&frm[6],&frm[7]} };
  struct tx_frame_t tfrm;     // temporal frame
  struct tx_frame_t  * movable p = &tfrm;

  buff_init(buff);
  while (1)
  {
    select
    {
      case ch0_tx.get(struct tx_frame_t  * movable &old_p) -> unsigned char b:
        b = buff_get(buff,to_ch0_tx,old_p);
        break;
      case ch1_tx.get(struct tx_frame_t  * movable &old_p) -> unsigned char b:
        b = buff_get(buff,to_ch1_tx,old_p);
        break;
      case cmd.push(struct tx_frame_t  * movable &old_p) -> unsigned char b:
        b = buff_push(buff,to_ch0_tx,old_p);
        ch0_tx.ondata();
        break;
      case cmd.get(struct tx_frame_t  * movable &old_p) -> unsigned char b:
        b = buff_get(buff,to_cmd,old_p);
        break;
      case ch0_rx.ondata():
        // read all data from ch0 rx
        while (ch0_rx.get(p) == 1)
        {
         if (p->dt[0] == 0)
         {
           buff_push(buff,to_cmd,p);
           cmd.ondata();
         }
         else
         {
           --(p->dt[0]);
           buff_push(buff,to_ch1_tx,p);
           ch1_tx.ondata();
         }
        }
        break;
      case ch1_rx.ondata():
        // Read all from channel 1 RX
        while (ch1_rx.get(p) == 1)
        {
          ++(p->dt[0]);
          buff_push(buff,to_ch0_tx,p);
          ch0_tx.ondata();
        }
        break;
    }
  }
}

/*
 * Command task
 * it will read a command and it will create the answer in the same frame,
 * next time a frame is swap the previous one is send back to host.
 * when command is ready it will be a notification
 */

[[combinable]] void CMD(client interface cmd_push_if router,
    server interface tx_rx_if irda_tx,
    client interface tx_rx_if irda_rx)
{
  struct tx_frame_t   frm,irda_frm;     // frame ready to be send to irda tx
  struct tx_frame_t* movable p = &frm;
  struct tx_frame_t* movable pirda = &irda_frm;   //irda packet waiting to be send
  pirda->len = 0;
  while(1)
  {
    select
    {
        case router.ondata():
        while (router.get(p) == 1)
        {
          // reply back the command
          p->len = 3;
          p->dt[1] = 'B';
          p->dt[2] = 'C';
          if (router.push(p) == 0)
            printf(".\n");
        }
        break;
        case irda_tx.get(struct tx_frame_t  * movable &old_p) -> unsigned char b :
          if (pirda->len != 0)
          {
            struct tx_frame_t  * movable tmp;
            tmp = move(old_p);
            old_p = move(pirda);
            pirda = move(tmp);
            b =1;
          } else
            b = 0;
        break;
        case irda_rx.ondata():
        while (irda_rx.get(p) == 1)
        {
          unsigned int v = 0;
          for (int i= 3;i< p->len;++i)
          {
            v <<= 8;
            v += p->dt[i];
          }
          printf("%X\n",v);
        }
        break;
    }
  }
}

/*
 * Read data from irda port, max of 32 bits of data are allowed
 * first bytes is the numbers of bit received
 */
void irda_RX(server interface tx_rx_if rx,in port p,unsigned T,unsigned char high)
{
#define irda_rx_frm_count 2
  struct tx_frame_t cfrm;
  struct tx_frame_t frm[irda_rx_frm_count];
  struct tx_frame_t* movable pfrm[irda_rx_frm_count] = {&frm[0],&frm[1]};
  struct tx_frame_t* movable wr_frame = &cfrm;      // currently writting in this frame
  timer t;      // timer
  unsigned int tp;       // time point // timerafter fail with unsigned
  unsigned char pv;            // current rx pin value
  unsigned int val;          // coping incoming bits to this variable

  for (int i = 0;i < irda_rx_frm_count;++i)
  {
      pfrm[i]->len = 0;
  }
  wr_frame->len = 0xFF;  // bits received , if it is 0xFF then a timeout was received then next transition must be ignored
  t :> tp;    // get current time
  p :> pv;
  for (;;)
  {
     select {
      case rx.get(struct tx_frame_t  * movable &old_p) -> unsigned char b :
          // find a frame with data
          int i = 0;
          for (;i < irda_rx_frm_count;++i)
          {
            if (pfrm[i]->len != 0)
            {
              struct tx_frame_t  * movable tmp;
              tmp = move(old_p);
              old_p = move(pfrm[i]);
              pfrm[i] = move(tmp);
              pfrm[i]->len = 0;
              break;
            }
          }
          if ( i == irda_rx_frm_count)
            b = 0;
          else
            b = 1;
          break;
          // wait for pin transition or timeout
      case t when timerafter(tp+T*2.5) :> tp: // timeout (adjusting tp will be a problem for start condition, when signal go dow, the pulse width seems to be short
          if (pv == high)
          {
              // start condition
              wr_frame->len = 0xFF;   // invalidate next transition (long low level does not produce data when go high, not need to set bit to 0xFF)
          } else
          {
            // end of data it will happens many times when we are waiting for start signal
            if (wr_frame->len > 0 && wr_frame->len != 0xFF)
            {
              // create data.
              wr_frame->dt[0] = 0 ; // id is 0 this device
              wr_frame->dt[1] = 0 ; // irda device id to be set by cmd interface
              wr_frame->dt[2] = wr_frame->len;  //bit count
              wr_frame->dt[3] = val >> 24;
              wr_frame->dt[4] = val >> 16;
              wr_frame->dt[5] = val >> 8;
              wr_frame->dt[6] = val;
              wr_frame->len = 7;
              // add full frame to list and notify
              int i = 0;
              for (;i < irda_rx_frm_count;++i)
              {
                if (pfrm[i]->len == 0)
                {
                  struct tx_frame_t  * movable tmp;
                  tmp = move(wr_frame);
                  wr_frame = move(pfrm[i]);
                  pfrm[i] = move(tmp);
                  rx.ondata();
                  break;
                }
              }
              if (i == irda_rx_frm_count)   // there is not empty frame
              {
                 printf(".\n");
              }
              wr_frame->len = 0xFF;   // reuse the same frame
            }
          }
          break;
          case p when pinsneq(pv) :> pv: // for t < 1.5 is 0 otherwise is 1
            int te;
            t :> te;
            if (pv != high)
            {
              if (wr_frame->len == 0xFF)
              {
                wr_frame->len = 0; // it was a start signal going low, just ignore, but now we are ready to store data next time
                val = 0;
              }
              else
              {
                val <<= 1;
                if (te - tp > T*1.5) val |= 1;
                wr_frame->len++;
                if (wr_frame->len > 32)
                  printf("e\n");
              }
            }
            tp = te;
            break;
     }
  }
}

/*
 * Irda frame transmitter
 * id - device id
 * subid - irda device id
 * bit   - bitcount.
 * data - 4 bytes from lsb to msb (Bit are send from MSb to LSB using a bit mask)
 */
void irda_TX(client interface tx_rx_if tx,out port TX,unsigned T,unsigned char low,unsigned char high)
{
  struct tx_frame_t frm;
  struct tx_frame_t* movable pfrm = &frm;

  TX <: low;
  for(;;)     // do not make it combinable, because send data take a while
  {
    select
    {
      case tx.ondata():
      // peek and send data
      while (tx.get(pfrm) == 1)
      {
        // send data
        if (pfrm->len == 7 &&  pfrm->dt[2] > 0)
        {
          irda_send(pfrm->dt[3] | (pfrm->dt[4] << 8) | (pfrm->dt[5] << 16 ) | (pfrm->dt[6] << 24),
              pfrm->dt[2],high,low,TX,T);
        }
      }
      break;
    } // select
  }  // for
}

/*
 * Transmition channel 0
 */
#define MAX_FRAME 4
#define TX_HIGH  1
#define TX_LOW   0

void TX(client interface tx_rx_if tx,out port TX,unsigned T)
{
  struct tx_frame_t frm;
  struct tx_frame_t* movable pfrm = &frm;

  TX <: TX_LOW;
  for(;;)
  {
    select
    {
     case tx.ondata():
        while (tx.get(pfrm) == 1)
        {
          // send data
          if (pfrm->len != 0)
          {
            send(pfrm->dt,pfrm->len,TX_HIGH,TX_LOW,TX,T);
          }
        }
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
void RX(server interface tx_rx_if rx,in port RX,unsigned T)
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
        pfrm[i]->len = 0;
    }
    wr_frame = move(pfrm[0]);
    t :> tp;    // get current time
    RX :> pv;
    for (;;)
    {
       select {
        case rx.get(struct tx_frame_t  * movable &old_p) -> unsigned char b :
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
                    rx.ondata();
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
