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
/*
 * Combinable serial rx interface
 * rx interface
 *
 */
/*
[[combinable]] void serial_rx_cmb(in port rx,streaming chanend c,server interface serial_rx_if rx_if,out port deb)
{
  unsigned char baudrate;
  unsigned char pv;
  unsigned char bitmask;
  unsigned char st;   // status 0 - waiting to be pv, waiting start, 1 - 10 data,
  timer t;
  unsigned int tp;
  unsigned char dt;
  // idle waiting for pv
  pv = SERIAL_LOW;
  st = 0;
  baudrate = 1;
  while(1)
  {
    select
    {
      case st == 0 => rx when pinseq(pv) :> void: // wait for start
        if (pv == SERIAL_HIGH)
        {
          t :> tp;
          deb <: 1;
          deb <: 0;
          tp += (baudrate*(UART_BASE_BIT_LEN_ticks/2));
          st = 1;
        }
        else
          pv = SERIAL_HIGH;
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
            pv = SERIAL_HIGH;
          }
        } else if (st < 10) //reading data
        {
          if (pv == 1)
            dt |= bitmask;
          bitmask <<= 1;
          st++;
        } else if (st == 10) // waiting for stop
        {
//          if (dt == SERIAL_LOW)
//            st = 0;
//          dt = 0;

          if (pv == SERIAL_LOW)
          {
            c <: dt;
            pv = SERIAL_HIGH;   // wait for high next time
          }
          else
          {
            rx_if.error();  // error clear everything try sending NOK
            pv = SERIAL_LOW;
          }
          st = 0;
        }
        break;
      case rx_if.ack():
          break;
      case rx_if.setbaud(unsigned baud):
        baudrate = baud;
        break;
    }
  }
}
*/
/*
 * Serial
 * Combinable, Timed TX with internal buffer
 */
[[combinable]] void serial_tx_ctb(streaming chanend ch,
    server interface serial_tx_v2_if cmd,
    out port tx)
{
  unsigned char buff[32];   //mask is 0x1F
  unsigned char buff_wr;
  unsigned char buff_count; // how many bytes in the buffer
  unsigned short data;     // next output value is the LSB
  unsigned char baudrate;
  unsigned int tp;
  unsigned char st;   // status 0 - idle, 1 - sending data, 2 - sending stop,
  timer t;
  //init
  baudrate = 1;
  st = 11;
  data = SERIAL_LOW;
  buff_wr = 0;
  buff_count = 0;
  while(1)
  {
    select
    {
      case cmd.ack():
        break;
      case cmd.setbaud(unsigned baud):
        baudrate = baud;
        break;
      case ch :> unsigned char rcv_dt:
        if (buff_count < sizeof(buff))
        {
          buff[buff_wr] = rcv_dt;
          buff_wr = (buff_wr + 1) & (sizeof(buff)-1);
          buff_count++;
        }
        else
          cmd.overflow();
        if (st == 0)
        {
          st = 11;    // start a new transmition
          data = SERIAL_LOW;  // first bit to be send
          t :> tp;
          //tp += (UART_BASE_BIT_LEN_ticks*baudrate/2);
        }
        break;
      case st !=0 => t when timerafter(tp) :> void:
        tx <: >>data;
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        if (st < 11)  // 1 .. 8 send bits
        {
          st++;
        }
        else
        {
          if (buff_count != 0)
          {
            data = buff[(buff_wr + sizeof(buff) - buff_count)& (sizeof(buff)-1)];
            data<<=1;   // make space for start bit
            if (SERIAL_LOW == 0)
              data |= 1;    // add starbit as 1
            else
              data |= 0xE00;   // add stop bit as 1
            st = 1;
            tp += (UART_BASE_BIT_LEN_ticks*baudrate);
            buff_count--;
          } else
            st = 0;
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
      case cmd.setbaud(unsigned baud):
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
void buffer_v1(
    server interface buffer_v1_if cmd,
    streaming chanend rx,
    streaming chanend tx)
{
  struct tx_frame_t rx_buff;
  struct tx_frame_t  * movable rx_ptr = &rx_buff;
  unsigned char rx_st;  // rx buffer status 0 - written, 1 - overflow , 2 - cr received
  rx_ptr->len = 0;
  while(1)
  {
    select
    {
      case rx :> unsigned char dt:
        if (dt == '\r')
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
          tx <: dt;
          if (rx_ptr->len < sizeof(rx_ptr->dt))
          {
            rx_ptr->dt[rx_ptr->len] = dt;
            rx_ptr->len++;
          }
          else
            rx_st = 1;
        }
        printf(">0x%X %c\n",dt,dt);
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
      case cmd.push(unsigned char* dt,unsigned char count):
          while (count--)
          {
            printf("<0x%X %c\n",*dt,*dt);
            tx <: *dt;
            dt++;
          }
          break;
    }
  }
}
*/

/*
 * This a buffer for serial port
 * it stores incoming data until CR is received. then a notification to cmd task is done.
 * Data has to be collected before the next byte is received.
 *
 */
/*
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
  rx_ptr->len = 0;
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
      case cmd.setbaud(unsigned baud):
        rx_if.setbaud(baud);
        tx_if.setbaud(baud);
        break;
    }
  }
}
*/

[[combinable]] void serial_tx_v3(server interface tx_if_v3 cmd,out port tx)
{
  unsigned char buff[32];   //mask is 0x1F
  unsigned char buff_wr;
  unsigned char buff_count; // how many bytes in the buffer
  unsigned short data;     // next output value is the LSB
  unsigned char baudrate;
  unsigned int tp;
  unsigned char st;   // status 0 - idle, 1 - sending data, 2 - sending stop,
  timer t;
  //init
  baudrate = 1;
  st = 11;
  data = SERIAL_LOW;
  buff_wr = 0;
  buff_count = 0;
  /*
   * it does not work with xs1, not pull resistor available
  set_port_drive_low(tx);
  set_port_pull_up(tx);
  */
  while(1)
  {
    select
    {
      case cmd.setSpeed(unsigned baud):
        baudrate = baud;
        break;
      case cmd.push(unsigned int dt) -> unsigned char b:
        if (buff_count < sizeof(buff))
        {
          buff[buff_wr] = dt;
          buff_wr = (buff_wr + 1) & (sizeof(buff)-1);
          buff_count++;
          b = 0;
        }
        else
          b = 1;
        if (st == 0)
        {
          st = 11;             // start a new transmition
          data = SERIAL_LOW;  // first bit to be send
          t :> tp;
          //tp += (UART_BASE_BIT_LEN_ticks*baudrate/2);
        }
        break;
      case st !=0 => t when timerafter(tp) :> void:
        tx <: >>data;
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        if (st < 11)  // 1 .. 8 send bits
        {
          st++;
        }
        else
        {
          if (buff_count != 0)
          {
            data = buff[(buff_wr + sizeof(buff) - buff_count)& (sizeof(buff)-1)];
            data<<=1;   // make space for start bit
            if (SERIAL_LOW == 0)
              data |= 1;    // add starbit as 1
            else
              data |= 0xE00;   // add stop bit as 1
            st = 1;
            tp += (UART_BASE_BIT_LEN_ticks*baudrate);
            buff_count--;
          } else
            st = 0;
        }
        break;
    }
  }
}

/*
 *
 */

[[combinable]] void serial_tx_v4(server interface uart_v4 uart_if,server interface tx tx_if,out port p)
{
  unsigned data;     // next output value is the LSB
  unsigned baudrate;
  unsigned int tp;
  unsigned char st;   // status 0 - idle, 1 - sending data, 2 - sending stop,
  timer t;
  const unsigned char low = 1;
  //init
  baudrate = 1;
  st = 0;     // idle
  data = low;

   // it does not work with xs1, not pull resistor available
  //set_port_drive_low(tx);
  //set_port_pull_up(tx);

  tx_if.ready();
  while(1)
  {
    select
    {
      case uart_if.setbaud(unsigned baud):
        baudrate = baud;
        break;
      case st !=0 => t when timerafter(tp) :> void:
        p <: >>data;
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        if (st < 11)  // send 11 bits
        {
          st++;
        }
        else
        {
          st = 0;
          tx_if.ready();
        }
        break;
      case st == 0 => tx_if.push(unsigned char dt):
        data = dt;
        if (low)
        {
          data |= 0xE00;   // add stop bit as 1
        }
        else
          data |= 1;    // add starbit as 1
        st = 1;
        break;
    }
  }
}

/*
[[combinable]] void serial_rx_v4(server interface serial_rx_if uart_if, streaming chanend c,in port rx)
{
  unsigned baudrate;
  unsigned char pv;
  unsigned char st;   // status 0 - waiting to be pv, waiting start, 1 - 10 data,
  timer t;
  unsigned int tp;
  unsigned dt;
  const unsigned char low = 1;
  // idle waiting for pv
  pv = SERIAL_LOW;
  st = 0;
  baudrate = 1;
  while(1)
  {
    select
    {
      case st == 0 => rx when pinsneq(low) :> void: // wait for start
        t :> tp;
        tp += (baudrate*(UART_BASE_BIT_LEN_ticks/2));
        st = 1;
        dt = 0;
        break;
      case st != 0 => t when timerafter(tp) :> void:    // only read if it is not idle
        rx :> >>dt;
        st++;
        tp += (UART_BASE_BIT_LEN_ticks*baudrate);
        if (st == 10)  // done reading
        {
          if ((low && (dt & 0x20) != 0x20) ||
              (!low && (dt & 0x1) != 0x1))
          {
            uart_if.error();
          }
          else
          {
            dt >>=1;
            c <: (unsigned char)(dt);
          }
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
  unsigned binary_mode;
  unsigned char st;   // status 0 - waiting to be pv, waiting start, 1 - 10 data,
  timer t;
  unsigned int tp;
  unsigned dt;
  st = 0;
  baudrate = 1;
  binary_mode = 0;   // if no data on buffer then no need for timeout
  pframe->len = 0;
  pframe->overflow = 0;
  while(1)
  {
    select
    {
      case st == 0 => rx when pinsneq(0) :> void: // wait for start
        t :> tp;
        tp += (baudrate*(UART_BASE_BIT_LEN_ticks/2));
        st = 1;
        dt = 0;
        break;
      case st != 0 || binary_mode => t when timerafter(tp) :> void:    // only read if it is not idle
        rx :> >>dt;
        if (st == 0)
        {
          if (pframe->len != 0)
          {
            router.push(pframe,cmd_tx);
            pframe->len = 0;
            pframe->overflow = 0;
          }
          binary_mode = 0;
          break;
        }
        st++;
        if (st != 10)
        {
          tp += (UART_BASE_BIT_LEN_ticks*baudrate);
          break;
        }
        tp += (UART_BASE_BIT_LEN_ticks*10*2); // 2 bytes gap

        dt = dt >> 24;
        if ((dt & 0x100) == 0)   // test stop bit
        {
          uart_if.error();
          pframe->len = 0;  // discard data, or push to router and send nok
          break;
        }
        dt &= 0xFF;
        if (pframe->len == sizeof(pframe->dt))
          pframe->overflow++;
        else
        {
          pframe->dt[pframe->len] = dt;
          if (pframe->len == 0)
          {
            binary_mode = (dt > ' ');
          }
          if (!binary_mode && dt == '\n')
          {
            router.push(pframe,cmd_tx);
            binary_mode = 0;
            pframe->len = 0;
            pframe->overflow = 0;
          }
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
  unsigned int tp;
  timer t;
  baudrate = 1;
  // it does not work with xs1, not pull resistor available
  //set_port_drive_low(tx);
  //set_port_pull_up(tx);

  while(1)
  {
    select
    {
      case uart_if.setbaud(unsigned baud):
        baudrate = baud;
        break;
      case tx.send(const char* data,unsigned char len):
        unsigned outData;    // out value
        while (len--)
        {
          outData = (*data) << 1 | 0xE00;
          t :> tp;
          for (int i = 0;i<10;i++)
          {
            p <: >>outData;
            tp += (UART_BASE_BIT_LEN_ticks*baudrate);
            t when timerafter(tp) :> void;
          }
          data++;
        }
        break;
    }
  }
}

