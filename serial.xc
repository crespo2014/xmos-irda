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
[[combinable]] void serial_rx_cmb(in port rx,chanend c,server interface serial_rx_if rx_if,out port deb)
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
  deb <: 0;
  while(1)
  {
    select
    {
      case st == 0 => rx when pinseq(SERIAL_HIGH) :> void: // wait for start
        t :> tp;
        deb <: 1;
        deb <: 0;
        tp += (baudrate*(UART_BASE_BIT_LEN_ticks/2));
        st = 1;
        break;
      case st != 0 => t when timerafter(tp) :> void:    // only read if it is not idle
        rx :> pv;
        deb <: 1;
        deb <: 0;
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        if (st == 1)  // reading start
        {
          if (pv == SERIAL_HIGH)
          {
            st = 2;
            bitmask = 1;    // LSB to MSB
            dt = 0;
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
        } else if (st == 3) // reading stop
        {
          if (pv == SERIAL_LOW)
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
 * Serial
 * Combinable, Timed TX with internal buffer
 */
[[combinable]] void serial_tx_ctb(streaming chanend ch,
    server interface serial_tx_v2_if cmd,
    out port tx)
{
  unsigned char buff[16];   //mask is 0x0F
  unsigned char buff_wr;
  unsigned char buff_count; // how many bytes in the buffer
  unsigned char data,rcv_dt;
  unsigned char bitmask;
  unsigned char baudrate;
  unsigned int tp;
  unsigned char pv;   // next output value
  unsigned char st;   // status 0 - idle, 1 - sending data, 2 - sending stop,
  timer t;
  //init
  baudrate = 1;
  st = 0;
  tx <: SERIAL_LOW;
  buff_wr = 0;
  buff_count = 0;
  while(1)
  {
    select
    {
      case cmd.ack():
        break;
      case cmd.setbaud(unsigned char baud):
        baudrate = baud;
        break;
      case ch :> rcv_dt:
        if (buff_count != 16)
        {
          buff[buff_wr] = rcv_dt;
          buff_wr = (buff_wr + 1) & 0x0F;
          buff_count++;
        }
        else
          cmd.overflow();
        if (st == 0)
        {
          st = 3;    // start a new transmition
          t :> tp;
          tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        }
        break;
      case st !=0 => t when timerafter(tp) :> void:
        tx <: pv;
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        if (st < 9)  // 1 .. 8 send bits
        {
          pv = data & 1;
          data >>= 1;
          st++;
//          if ((data & bitmask) == bitmask)
//            pv = SERIAL_HIGH;
//          else
//            pv = SERIAL_LOW;
//          if (bitmask == 0x80) st = 2;
//          bitmask<<= 1;
        }
        else if (st == 9)
        {
          pv = SERIAL_LOW;
          st = 3;
        } else
        {
          if (buff_count != 0)
          {
            data = buff[(buff_wr + 16 - buff_count)& 0xF];
            st = 1;
            pv = SERIAL_HIGH;       // start bit
            bitmask = 1;  // lsb to msb
            tp += (UART_BASE_BIT_LEN_ticks*baudrate);
            buff_count--;
            st = 1;
          }
        }
        break;
    }
  }
}


/*
 * Serial tx timed
 */
[[combinable]] void serial_tx_timed_cmb(server interface serial_tx_if cmd,out port tx)
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
        t :> tp;
        data = dt;
        st = 1;
        pv = 1;       // start bit
        bitmask = 1;  // lsb to msb
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        break;
      case cmd.setbaud(unsigned char baud):
        baudrate = baud;
        break;
      case st !=0 => t when timerafter(tp) :> void:
        tx <: pv;
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        if (st == 1)
        {
          if ((data & bitmask) == bitmask)
            pv = 1;
          else
            pv = 0;
          if (bitmask == 0x80) st = 2;
          bitmask<<= 1;
        }
        else if (st == 2)
        {
          pv = 0;
          st = 3;
        } else
        {
          st = 0;
          cmd.ready();
        }
        break;
    }
  }
}

/*
 * This a buffer for serial port
 * it stores incoming data until CR is received. then a notification to cmd task is done.
 * Data has to be collected before the next byte is received.
 *
 * TODO
 * Using streaming channel will speed up communications. but it avoid combinable task live on the same core
 * TX with channel should contain a buffer and a error trigger when buffer overflows.
 * RX write to the channel, the baud rate can be set if bytes do not arrive to fast ( anyway buffer side is peek all bytes faster).
 */

void serial_buffer(server interface serial_buffer_if cmd,
    chanend rx,
    client interface serial_rx_if rx_if,
    client interface serial_tx_if tx_if)
{
  unsigned char   tx_buff[20];
  unsigned char tx_wr;
  unsigned char tx_count;
  struct tx_frame_t rx_buff;
  struct tx_frame_t  * movable rx_ptr = &rx_buff;
  unsigned char rx_st;  // rx buffer status 0 - written, 1 - overflow , 2 - cr received
  unsigned char rx_dt;
  rx_ptr[0].len = 0;
  rx_ptr[1].len = 0;
  while(1)
  {
    select
    {
      case rx :> rx_dt:
        if (rx_dt == '\r')
        {
          if (rx_st == 0)
          {
            rx_st = 2;
            cmd.onRX();
          }
          else
          {
            //error
            rx_st = 0;
            rx_ptr->len = 0;
          }
        } else
        {
          if (rx_ptr->len < sizeof(rx_ptr->dt))
          {
            rx_ptr->dt[rx_ptr->len] = rx_dt;
            rx_ptr->len++;
          }
          else
            rx_st = 1;
        }
        break;
      case cmd.get(struct tx_frame_t  * movable &old_p) -> unsigned char b:
        if (rx_st == 2)
        {
          struct tx_frame_t  * movable tmp;
          tmp = move(old_p);
          old_p = move(rx_ptr);
          rx_ptr = move(tmp);
          b = 1;
          rx_ptr->len = 0;
          rx_st = 0;
        }
        else
          b = 0;
        break;
      case cmd.TX(unsigned char c):
        if (tx_count < sizeof(tx_buff))
        {
          tx_buff[tx_wr] = c;
          tx_wr++;
          if (tx_wr == sizeof(tx_buff)) tx_wr = 0;
          tx_count++;
        }
        break;
      case cmd.setbaud(unsigned char baud):
        rx_if.setbaud(baud);
        tx_if.setbaud(baud);
        break;
    }
  }
}





