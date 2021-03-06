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
#include "utils.h"

//TODO give a gap between bytes to allow recovery from wrong synchronization
// not good for speed.
// sending cr until get OK will synchronize the communication. do not send cr to fast
// write 0x00 (clear the line) and CR two times

#if 0
/*
 * Serial tx over irda led
 * Combinable function
 */
/*
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
  */

#endif

/*
 * Serial Rx with buffer and timeout
 */
void serial_rx_v5(server interface serial_rx_if uart_if, client interface rx_frame_if router,in port rx)
{
  struct rx_u8_buff tfrm;   // temporal frame
  struct rx_u8_buff * movable pframe = &tfrm;
  unsigned baudrate;
  /*
   *  0 - wait for 1
   *  1 - wait for 0
   *  2 - wait for 0 or timeout
   *  3 - 13 reading data
   */
  unsigned char st;   // status 0 - waiting to be pv, waiting start, 1 - 10 data,
  timer t;
  unsigned int tp;
  unsigned dt;
  st = 0;
  baudrate = 1;
  pframe->len = 0;
  pframe->overflow = 0;
  while(1)
  {
    select
    {
      case st < 3 => rx when pinseq(st==0) :> void: // wait for 1 or 0
        t :> tp;
        if (st > 0)  // start signal received, prepare for reading
        {
          tp += (baudrate*(UART_BASE_BIT_LEN_ticks/2));
          st = 3;   // set to 3
        }
        else
          st = 1;
        break;
      case st > 1 => t when timerafter(tp) :> void:    // only read if it is not idle
        rx :> >>dt;
        if (st > 2)  // read until 10 bits
        {
          st++;
          tp += (UART_BASE_BIT_LEN_ticks*baudrate);
          if (st == 13)     // bit 10 was read
          {
            dt >>= 22;
            if ( (dt & 0x201) != 0x200 )   // check start stop bits
            {
              uart_if.error();
              //pframe->len = 0;  // discard data, or push to router and send nok
              pframe->overflow++;  //next status is 12
              st = 0;              // wait for signal high again.
              break;
            }
            // store the data
            if (pframe->len < sizeof(pframe->dt))
            {
              dt = dt >> 1;
              pframe->dt[pframe->len] = dt;
              pframe->len++;
            } else
              pframe->overflow++;
            // wait for next or timeout
            st = 2;
            tp += (UART_BASE_BIT_LEN_ticks*baudrate*5); // wait for 1 1/2 bytes gap before trigger timeout
          }
        } else   //timeout waiting for more data
        {
          // for ascii mode time out is disable
          if (pframe->overflow || (pframe->len != 0 && (pframe->dt[0] != ':' ||  pframe->dt[pframe->len-1] == '\n')))
          {
            pframe->cmd_id = serial_rx;
            router.push(pframe,cmd_tx); // command interface will parse the command
          }
          pframe->len = 0;
          pframe->overflow = 0;
          st = 0;
        }
        break;
      case uart_if.ack():
          break;
      case uart_if.setbaud(unsigned baud):
        baudrate = baud;
        break;
    }
  }
}




[[distributable]] void serial_tx_v5(server interface uart_v4 uart_if,server interface tx_if tx,out port p)
{
  unsigned baudrate;
  timer t;
  baudrate = 1;
  // it does not work with xs1, not pull resistor available
  //set_port_drive_low(tx);
  //set_port_pull_up(tx);
  p <: 1;   // the rx will mistake as 0xFF data
  tx.cts();
  while(1)
  {
    select
    {
      case uart_if.setbaud(unsigned baud):
        baudrate = baud;
        break;
      case tx.send(struct rx_u8_buff  * movable &pck):
        UART_TIMED_SEND(pck->dt + pck->header_len,pck->len - pck->header_len,p,baudrate,t);
#if 0
        unsigned outData;    // out value
        t :> tp;
        while (len--)
        {
          outData = (*data) << 1 | 0x200;   // stop bit 10 as 1, start bit 0 as 0
          for (int i = 0;i<10;i++)
          {
            t when timerafter(tp) :> void;
            p <: >>outData;
            tp += (UART_BASE_BIT_LEN_ticks*baudrate);
          }
          data++;
        }
        tp += (UART_BASE_BIT_LEN_ticks*baudrate*10);  // 1 byte gap
        t when timerafter(tp) :> void;
#endif
        tx.cts();
        break;
      case tx.ack():
        break;
    }
  }
}






