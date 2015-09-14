/*
 *  Created on: 10 Jul 2015
 *      Author: lester.crespo
 *
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
 * TODO  Switched Power Supply (Buck)
 * power control task. ( Imax, Imin for switch transistor signal)
 * adc input when power is on.
 * Imax and delta as intensity control.
 * At power off signal, adc must be stopped, all led switch turn off, power transistor go off).
 * Status (ON, OFF) - 
 * protection for long Ton times. (overcurrent protection, analize ton,toff time)
 * Interface to set Imax or level intensity, read ton-toff, fault indicator, 
 * Turn on ligth in a secuence base on walker speed. ( one motion sensor at enter point)
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
#include <rxtx.h>
#include "irda.h"

#if 0
/*
 enum dest_e {
    to_none,
    to_cmd,
    to_ch0_tx,
    to_ch1_tx,
  };
*/
/*
 * Frame buffer structure
 * - support for destinity
 * - support for peek and push
 *
 */
/*
struct frm_buff_t
{
#define BUFF_MAX 8
  enum dest_e dest[BUFF_MAX];
  struct tx_frame_t* movable pfrm[BUFF_MAX];// = {&frm[0],&frm[1],&frm[2],&frm[3],&frm[4],&frm[5],&frm[6],&frm[7]};
  unsigned char free_count;  // how many frame with no data
};
*/

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
        buff.dest[i] = to_none;
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
[[distributable]]
void Router(
    server interface tx_rx_if ch0_tx,
    server interface tx_rx_if ch1_tx,
    client interface tx_rx_if ch0_rx,
    client interface tx_rx_if ch1_rx,
    server interface cmd_push_if cmd,
    client interface fault_if fault)
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
        printf("ch0 :> %d\n",old_p->len);
        break;
      case ch1_tx.get(struct tx_frame_t  * movable &old_p) -> unsigned char b:
        b = buff_get(buff,to_ch1_tx,old_p);
        printf("ch1 :> %d\n",old_p->len);
        break;
      case cmd.push(struct tx_frame_t  * movable &old_p) -> unsigned char b:
        b = buff_push(buff,to_ch0_tx,old_p);
        printf("ch0 <: cmd %d\n",old_p->len);
        ch0_tx.ondata();
        break;
      case cmd.get(struct tx_frame_t  * movable &old_p) -> unsigned char b:
        b = buff_get(buff,to_cmd,old_p);
        printf("cmd :> %d\n",old_p->len);
        break;
      case ch0_rx.ondata():
        // read all data from ch0 rx
        while (ch0_rx.get(p) == 1)
        {
         if (p->dt[0] == 0)
         {
           buff_push(buff,to_cmd,p);
           printf("cmd <: %d\n",p->len);
           cmd.ondata();
         }
         else
         {
           --(p->dt[0]);
           buff_push(buff,to_ch1_tx,p);
           printf("ch1 <: %d\n",p->len);
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

[[combinable]] void CMD(
    client interface cmd_push_if router,
    server interface tx_rx_if irda_tx,
    client interface tx_rx_if irda_rx,
    client interface fault_if fault)
{
  struct tx_frame_t   frm,irda_frm;     // frame ready to be send to irda tx
  struct tx_frame_t* movable p = &frm;
  struct tx_frame_t* movable pirda = &irda_frm;   //irda packet waiting to be send
  pirda->len = 0;
  p->len = 0;
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
          router.push(p);
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
          pirda->len = 0;
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
          pirda->len = 7;
          pirda->dt[2] = 32;
          irda_tx.ondata();

          printf("%X\n",v);
        }
        break;
    }
  }
}

/*
 * Read data from irda port, max of 32 bits of data are allowed
 * first bytes is the numbers of bit received
 * T is bit lengh in timer units
 */
[[combinable]] void irda_RX(server interface tx_rx_if rx,in port p,unsigned T,unsigned char high,client interface fault_if fault)
{
#define irda_rx_frm_count 2
  struct tx_frame_t frm[irda_rx_frm_count];
  struct tx_frame_t* movable pfrm[irda_rx_frm_count] = {&frm[0],&frm[1]};

  timer t;                   // timer
  unsigned int tp,nxtp;       // time point // timerafter fail with unsigned
  unsigned int val;          // coping incoming bits to this variable
  unsigned char pv;            // current rx pin value
  unsigned char bitcount;     // how many bits has been received
  unsigned char reading;      // true if start bit was recieved

  for (int i = 0;i < irda_rx_frm_count;++i)
  {
      pfrm[i]->len = 0;
  }
  t :> tp;    // get current time
  p :> pv;    // get current port status
  nxtp = 10*sec;
  bitcount = 0;
  val = 0;
  reading = 0;
  while (1)
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
          // TODO do not wait if timeout is on case nxtp>10*sec => t when 
      case t when timerafter(tp + nxtp) :> tp:
          nxtp = 10*sec;      //timeout
          if (pv == high)
          {
            //start signal
            reading = 1;
          }
          else
          {
            reading = 0;
            if (bitcount > 0)            // If stop bit and data has been collected then store it
            {
              // store data on buffers
              int i = 0;
              for (;i < irda_rx_frm_count;++i)
              {
                if (pfrm[i]->len == 0)
                {
                  pfrm[i]->dt[0] = 0 ; // id is 0 this device
                  pfrm[i]->dt[1] = 0 ; // irda device id to be set by cmd interface
                  pfrm[i]->dt[2] = bitcount;  //bit count
                  pfrm[i]->dt[3] = val >> 24;
                  pfrm[i]->dt[4] = val >> 16;
                  pfrm[i]->dt[5] = val >> 8;
                  pfrm[i]->dt[6] = val;
                  pfrm[i]->len = 7;
                  rx.ondata();
                  break;
                }
              }
              if (i == irda_rx_frm_count)   // there is not empty frame
              {
                 printf(":\n");
              }
            }
          }
          // ready for data
          bitcount = 0;
          val = 0;
          break;
      case p when pinsneq(pv) :> pv: // for t < 1.5 is 0 otherwise is 1
          int te;
          t :> te;
          if (pv != high && reading && nxtp < 1*sec)   // it signal going low and it was not timeout
          {
              // it was a normal transition calculate size of pulse
              val <<= 1;
              if (te - tp > T*1.5) val |= 1;
              bitcount++;
              if (bitcount > 32)
              {
                printf(":\n");
                bitcount = 0;
              }
          }
          tp = te;
          nxtp = 2.5*T;
          break;
     }
  }
}

/*
 * Transmition channel 0
 */
#define MAX_FRAME 4
#define TX_HIGH  1
#define TX_LOW   0

void TX(client interface tx_rx_if tx,out port p,unsigned T)
{
  struct tx_frame_t frm;
  struct tx_frame_t* movable pfrm = &frm;
  timer t;
  unsigned int tp;

  p <: TX_LOW;
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
             // send start bit
             p <: TX_HIGH;
             t :> tp;
             tp += 3*T;
             t when timerafter(tp) :> void;
             p <: TX_LOW;
             tp += T;
             t when timerafter(tp) :> void;
             printf("TX %d \n",pfrm->len);
             for (unsigned char i =0;i<pfrm->len;++i)
             {
               SERIAL_SEND(pfrm->dt[i],T,t,tp,p,TX_HIGH,TX_LOW);
             }
             //stop bit
             tp += 3*T;
             t when timerafter(tp) :> void;
             pfrm->len = 0;
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
 */
void RX(server interface tx_rx_if rx,in port RX,unsigned T,client interface fault_if fault)
{
    struct tx_frame_t cfrm;
    struct tx_frame_t frm[MAX_FRAME];
    struct tx_frame_t* movable pfrm[MAX_FRAME] = {&frm[0],&frm[1],&frm[2],&frm[3]};
    struct tx_frame_t* movable wr_frame = &cfrm;      // currently writting in this frame
    timer t;      // timer
    unsigned int tp;       // time point
    unsigned int nxtp;    // next time point to wait for
    unsigned char pv;            // current rx pin value
    unsigned char bitcount; // how many bits have been received invalid if > 64
    unsigned char val;          // coping incoming bytes to this variable
    unsigned char reading;      // true if start bit was recieved
    const unsigned char high = 1;

    for (int i = 0;i < MAX_FRAME;++i)
    {
        pfrm[i]->len = 0;
    }
    reading = 0;
    wr_frame->len = 0;
    RX :> pv;
    t :> tp;    // get current time
    nxtp = tp + 2.5*T;    // pick first timeout
    for (;;)
    {
       select {
        case rx.get(struct tx_frame_t  * movable &old_p) -> unsigned char b :
            // find a frame with data
            int i = 0;
            for (;i < MAX_FRAME;++i)
            {
              if (pfrm[i]->len != 0)
              {
                struct tx_frame_t  * movable tmp;
                old_p->len  = 0;
                tmp = move(old_p);
                old_p = move(pfrm[i]);
                pfrm[i] = move(tmp);
                break;
              }
            }
            if (i == MAX_FRAME)
              b= 0;
            else
              b = 1;
            break;
            // wait for pin transition or timeout
        case t when timerafter(tp+nxtp) :> tp: // timeout (adjusting tp will be a problem for start condition, when signal go dow, the pulse width seems to be short
            nxtp = 10*sec;
            if (pv == high)
            {
             //start signal
             reading = 1;
            }
            else
            {
              // stop signal
              reading = 0;
              if (wr_frame->len !=0)
              {
                // if bitcount !=0 then it was not received full byte, comunication broken

                // If data was received then store in buffers
                int i = 0;
                for (;i < MAX_FRAME;++i)
                {
                  if (pfrm[i]->len == 0)
                  {
                    printf("push %d\n",wr_frame->len);
                    struct tx_frame_t  * movable tmp;
                    tmp = move(wr_frame);
                    wr_frame = move(pfrm[i]);
                    pfrm[i] = move(tmp);
                    rx.ondata();
                    break;
                  }
                }
                if (i == MAX_FRAME)   // there is not empty frame
                {
                   printf(":\n");
                }
              }
            }
            // timeout will reset all
            wr_frame->len = 0;
            bitcount = 0;
            val = 0;
            break;
            case RX when pinsneq(pv) :> pv: // for t < 1.5 is 0 otherwise is 1
              int te;
              t :> te;
              if (pv != high && reading && nxtp < 1*sec)  // is signal going low and it is not timeout
              {
                // store received bit
                val <<= 1;
                if (te - tp > T*1.5) val |= 1;
                bitcount++;
                if (bitcount == 8)    // every 8 bits store value on buffer
                {
                  wr_frame->dt[wr_frame->len] = val;
                  wr_frame->len++;
                  if (wr_frame->len == sizeof(wr_frame->dt))
                  {
                    printf(":\n");  // overflow more than 20 bytes received
                    wr_frame->len = 0;
                  }
                  bitcount = 0;
                  val = 0;
                }
              }
              tp = te;
              nxtp = 2.5*T;   // timeout cleared.
              break;
       }
    }
}
#endif


