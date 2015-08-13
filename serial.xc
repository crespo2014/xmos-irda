/*
 * serial.xc
 *
 *  Created on: 31 Jul 2015
 *      Author: lester.crespo
 */

#include "serial.h"
#include "rxtx.h"
#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>

//TODO give a gap between bytes to allow recovery from wrong synchronization
// not good for speed.
// sending cr until get OK will synchronize the communication. do not send cr to fast
// write 0x00 (clear the line) and CR two times

/*
 * Serial tx over irda led
 * Combinable function
 */

void serial_to_irda_timed(client interface tx_rx_if src, out port tx,unsigned char baud_rate,unsigned char low,unsigned char high)
{
    struct tx_frame_t frm;
    struct tx_frame_t* movable pfrm = &frm;
    unsigned char bitmask,pos,dt;
    unsigned pulse;        // how many pulse to send
    unsigned char pv;      // next port value - it reduce transition time
    timer t;
    unsigned int tp,pulse_tp;   // time of start pulse
    //
    pfrm->len = 1;
    pfrm->dt[0] = 0x55;
    bitmask = (1<<7);
    pos = 0;
    dt = pfrm->dt[pos];
    pulse = (UART_BASE_BIT_LEN_ns*baud_rate/IRDA_CARRIER_T_ns) -1;  //start bit

    pv = low;
    t :> tp;
    tx <: high;
    tp += IRDA_CARRIER_TON_ticks;
    pulse_tp = tp;

    while(1)
    {
      select
      {
//        case pos == 0xFF => tx.ondata():
//            if (tx.get(data) == 1)
//            {
//              t :> tp;
//              TX <: high;
//              pulse_tp = tp;
//              pv = low;
//              bitmask = (1<<7);
//              pulse = 4*IRDA_PULSE_PER_BIT-1;
//              pos = 0;
//            }
//            break;
        case pos != 0xFF => t when timerafter(tp) :> void:
            tx <: pv;
            if (pv == high)
            {
              pulse--;
              tp += IRDA_CARRIER_TON_ticks;
              pv = low;
            }
            else // Toff zone
            {
              if (pulse == 0) // no more pulses 1 low bits needed
              {
                if (bitmask == 0)  // all bits + stop have been sent
                {
                  pos++;
                  if (pos == pfrm->len)  // all data have been sent
                  {
                    pos = 0xFF;
                  }
                  else
                  {
                    bitmask = (1<<7);
                    dt = pfrm->dt[pos];
                  }
                  return ;
                }
                else
                {
                  bitmask >>= 1;
                  if (bitmask == 0)  // no more bits to send
                  {
                    tp = pulse_tp + UART_BASE_BIT_LEN_ticks*baud_rate*2;  //stop bit
                    pv = low;
                  }
                  else
                  {
                    pulse_tp = pulse_tp + UART_BASE_BIT_LEN_ticks*baud_rate*2;
                    pulse = (UART_BASE_BIT_LEN_ns*baud_rate/IRDA_CARRIER_T_ns);
                    pv = high;
                    tp = pulse_tp;
                  }
                }
              }
              else
              {
                tp += IRDA_CARRIER_TOFF_ticks;
                pv = high;
              }
            }
            break;
      }
    }

  }
/*
 * Combinable serial rx interface
 * rx interface
 *
 * TODO echo flag , interface with tx for echo
 */
void serial_rx_cmb(in port rx,chanend c,server interface serial_rx_if rx_if)
{
  unsigned char baudrate;
  unsigned char pv;
  unsigned char bitmask;
  unsigned char st;   // status 0 idle waiting start, 1 start , 2 - reading, 3 waiting stop
  timer t;
  unsigned int tp;
  unsigned char dt;
  rx :> pv;
  st = 0;
  baudrate = 1;
  while(1)
  {
    select
    {
      case st == 0 => rx when pinseq(1) :> pv: // wait for start
        t :> tp;
        tp += ((UART_BASE_BIT_LEN_ticks/2)*baudrate);
        st = 1;
        bitmask = 1;    // LSB to MSB
        dt = 0;
        break;
      case st != 0 => t when timerafter(tp) :> void:    // only read if it is not idle
        rx :> pv;
        printf("%d:%d-%d\n",pv,bitmask,dt);
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        if (st == 1)  // reading start
        {
          if (pv == 1)
          {
            st = 2;
          }
          else
          {
            rx_if.error();
            st = 0; // not valid start
          }
        } else if (st == 2) //reading data
        {
          if (pv == 1)
            dt |= bitmask;
          if (bitmask == 0x80) st = 3;
          bitmask <<= 1;
          //if (bitmask == 0) st = 3;   // all data has been read
        } else if (st == 3) // reading stop
        {
          if (pv == 0)
          {
            c <: dt;
          }
          else
          {
            rx_if.error();  // error clear everything try sending NOK
          }
          st = 0;
        }
        break;
      case rx_if.ack():
          break;
      case rx_if.setbaud(unsigned char baud):
        baudrate = baud;
        break;
    }
  }
}

/*
 * Serial tx timed
 */
void serial_tx_timed_cmb(server interface serial_tx_if cmd,out port tx)
{
  unsigned char baudrate;
  unsigned char st;   // status 0 - idle, 1 - sending data, 2 - sending stop,
  unsigned char data,bitmask;
  unsigned int tp;
  unsigned char pv;   // next output value
  timer t;

  //init
  baudrate = 1;
  st = 0;
  tx <: 0;
  cmd.ready();
  while(1)
  {
    select
    {
      case st == 0 => cmd.push(unsigned char dt):    // call to this function is going to be ignore
        data = dt;
        st = 1;
        pv = 1;       // start bit
        bitmask = 1;  // lsb to msb
        t :> tp;
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        break;
      case cmd.setbaud(unsigned char baud):
        baudrate = baud;
        break;
      case st !=0 => t when timerafter(tp) :> void:
        tx <: pv;
        //printf("%d.",pv);
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        if (st == 1)
        {
          if (bitmask == 0) // no more data to send
          {
            pv = 0;
            st = 2;
          }
          else
          {
            if ((data & bitmask) == bitmask)
              pv = 1;
            else
              pv = 0;
            bitmask<<= 1;
          }
        }
        else if (st == 2)
        {
          st = 0;
          cmd.ready();
        }
        break;
    }
  }
}





