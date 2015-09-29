/*
 * cmd.xc
 *
 *  Created on: 16 Aug 2015
 *      Author: lester
 *
 * Core task.
 * It handle all commands received, and execute the desire command
 
 TODO : Sharing a multibits port.
 a distributable task bringing 8 interfaces with set clear.
 holding current port value.
 */

#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>
#include "safestring.h"
#include "serial.h"
#include "utils.h"
#include "cmd.h"



/*
 * Use a termination character to make not possible past the end of the string
 */
enum cmd_e getCommand(const unsigned char* c,const unsigned char* &t)
{
  if (isPreffix("I2CW",c,t) && *t == ' ') return i2cw_cmd;
  if (isPreffix("I2CR",c,t) && *t == ' ') return i2cr_cmd;
  if (isPreffix("I2CWR",c,t) && *t == ' ') return i2cwr_cmd;
  return none_cmd;
}

/*
 * Buffers that hold data comming from serial channel.
 * It invoke command interface when a packet is recieved
 *
 * v2. integrate into rx, signal when a packet is ready to process
 * two buffers holder.
 *
 * v3. two implementation can be done
 *  - Rx task store data on buffer.
 *   when timeouts a notyfication is send and the buffer swap with other one
 *   cmd task will request the buffer.
 *   cons - event that return buffer to cmd can block the rx for a not acceptable amount of time
 *
 * v4. Buffer task reading from channel stream with timeout will store incoming bytes.
 *   when it timeouts the buffered is processed.
 *   channel can hold until 8 bytes, that gives enough time to execute the previous command.
 *
 * V4.1 create a router that hold all packets using linked list for each interface.
 *  easy to dispatch packets without blocking task.
 *
 *  v4.2 Rx gap between frames can be enough to allow send command to router.
 *
 */
enum cmd_st
{
  cmd_id,
  cmd_len,
  cmd_data,
  cmd_ascii,
};


void ascii_i2cw(const char* buff,struct rx_u8_buff &ret,client interface i2c_custom_if i2c)
{
  struct i2c_frm frm;
  if (!i2cw_decode(buff,frm,'\n'))
  {
    safestrcpy(ret.dt,"I2CW invalid format");
  }
  else
  {
    i2c.i2c_execute(frm);
    i2c_decode_answer(frm,ret);
  }
  ret.len = safestrlen(ret.dt);
}
#if 0
void ascii_i2cr(const char* buff,struct rx_u8_buff &ret,client interface i2c_custom_if i2c)
{
  const char* resp;
  struct i2c_frm frm;
  do
  {
    if (!i2cr_decode(buff,frm))
    {
      resp ="I2CR invalid format";
      break;
    }
    i2c.i2c_execute(frm);
    if (frm.ret_code != i2c_success)
    {
      char* t = ret.dt;
      strcpy(t,"I2CW NOK E: ");
      u8ToHex(frm.ret_code,t);
      *t = 0;
      ret.len = safestrlen(ret.dt);
      return;
    }
  } while(0);
  safestrcpy(ret.dt,resp);
  ret.len = safestrlen(ret.dt);
}

void ProcessCommand(const char* data,unsigned char len,struct rx_u8_buff &pframe,client interface i2c_custom_if i2c)
{
  const unsigned char* l;
  if (*data > ' ')
  {
    //cmd_id = getCommand(data,l);
    switch (getCommand(data,l))
    {
     case i2cw_cmd:
       ascii_i2cw(++l,pframe,i2c);
       break;
     default:
       char* str = pframe.dt;
       strcpy(str,"Ascii cmd unimplemented");
       pframe.len = str - pframe.dt;
       break;
    }
  }
  else
  {
    char* str = pframe.dt;
    strcpy(str,"Binary cmd unimplemented");
    pframe.len = str - pframe.dt;
  }
}
#endif
/*
 * Task to parse user commands.
 */
[[distributable]] void cmd_v1(client interface rx_frame_if rx,server interface tx_if tx,client interface i2c_custom_if i2c)
{
  // packet use to push
  struct rx_u8_buff tfrm;   // temporal frame
  struct rx_u8_buff * movable pframe = &tfrm;
  while(1)
  {
    select
    {
      case tx.send(const char* data,unsigned char len):
          /*
        printf("in :");
        printbuff(data,len);
        ProcessCommand(data,len,*pframe,i2c);
        printf("\nout :");
        printbuff(pframe->dt,pframe->len);
        rx.push(pframe,serial_tx);
        printf("\n");
        */
        break;
      case tx.ack():
        break;
    }
  }
}

#if 0
/*
 * User interface
 * For error reporting
 * 2 hz flashing led
 */
[[combinable]] void ui(
    out port p,
    server interface fault_if ch0_rx,
    server interface fault_if ch1_rx,
    server interface fault_if router,
    server interface fault_if cmd,
    server interface fault_if irda_rx)
{
  unsigned int faults;
  unsigned char led_on = 0;
  timer t;
  unsigned int tp;
  t :> tp;
  tp += 500*ms;
  while(1)
  {
    select
    {
      case ch0_rx.fault(unsigned int id):
        faults |= id;
        break;
      case ch1_rx.fault(unsigned int id):
        faults |= id;
        break;
      case router.fault(unsigned int id):
        faults |= id;
        break;
      case cmd.fault(unsigned int id):
        faults |= id;
        break;
      case irda_rx.fault(unsigned int id):
        faults |= id;
        break;
      case t when timerafter(tp) :>void:
        tp += 500*ms;
        if (led_on)
          p <:0;
        else
          p <: faults;
        led_on = !led_on;
        break;
    }
  }

}
#endif

