/*
 * cmd.xc
 *
 *  Created on: 16 Aug 2015
 *      Author: lester
 *
 * Core task.
 * It handle all commands received, and execute the desire command
 *
 * Binary command comming from user port
 * id_8 - command id for reply 0 - no reply needed  (0 -31) ok
 * dest_8 - destination interface
 * data   - specific interface data
 
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
#include "mcp2515.h"
#include "rxtx.h"

/*
 * Use a termination character to make not possible past the end of the string
 * update prefix len.
 */
static inline unsigned getCommand(const unsigned char* c,unsigned &len)
{
  unsigned id = cmd_none;
  if (CheckPreffix("I2CR",c,len)) id = cmd_i2cr;
  else if (CheckPreffix("I2CW",c,len)) id = cmd_i2cw;
  else if (CheckPreffix("I2CR",c,len)) id = cmd_i2cr;
  else if (CheckPreffix("I2CWR",c,len)) id = cmd_i2cwr;
  else if (CheckPreffix("CANTX",c,len)) id = cmd_can_tx;
  else if (CheckPreffix("SPI0",c,len)) id = cmd_spi0_tx;
  else if (CheckPreffix("INFO",c,len)) id = cmd_info;
  return id;
}

enum cmd_st
{
  cmd_id,
  cmd_len,
  cmd_data,
  cmd_ascii,
};

/*
 * ASCII can tx command.
 * Build a can packet
 * IN:
 * ID until 32bits
 * data max 8 bytes
 * OUT:
 *  32bits id
 *  data
 *
 * 0 - invalid format
 * 1 - sucess
 */
unsigned ascii_cantx(const char* buff,struct rx_u8_buff &ret)
{
#if 1
  unsigned id;
  id = read32BitsHex(buff);
  if (*buff != ' ') return 0;
  ret.dt[0] = id >> 24;
  ret.dt[1] = id >> 16;
  ret.dt[2] = id >> 8;
  ret.dt[3] = id & 0xFF;
  buff++; // jump space
  id  = readHexBuffer(buff,ret.dt+4,sizeof(ret.dt)-4);
  ret.len = 4 + id;
  if (*buff == ' ' && *buff != '\n') return 0;
#endif
  return 1;
}

void ascii_i2cw(const char* buff,struct rx_u8_buff *ret,client interface i2c_custom_if i2c)
{
#if 1
  struct i2c_frm frm;
  if (!i2cw_decode(buff,frm,'\n'))
  {
    ret->len = strcpy(ret->dt,"I2CW invalid format");
  }
  else
  {
    i2c.i2c_execute(frm);
    i2c_decode_answer(frm,*ret);
  }
  ret->len = safestrlen(ret->dt);
#endif
}
#if 1
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
    if (frm.ret_code != i2c_ack)
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

#endif

/*
 * Task to parse user commands.
 */
[[distributable]] void cmd_v1(client interface rx_frame_if rx,server interface tx_if tx,client interface i2c_custom_if i2c)
{
  // packet use to push
  struct rx_u8_buff tfrm;   // temporal frame
  struct rx_u8_buff * movable m_frame = &tfrm;
  //unsigned ascii_mode = 1;    //all data from rx is send to commnad to return as ascii or not
  tx.cts();
  while(1)
  {
    select
    {
      case tx.send(struct rx_u8_buff  * movable &_packet):
        unsigned len;
        if (_packet->src_rx == serial_rx || _packet->src_rx == test_rx)
        {
          if (_packet->dt[0] < ' ')   //binary commands should go straight to the device
          {
            _packet->id = _packet->dt[0];
            _packet->header_len = 2;    // id dest
            if (_packet->dt[1] < max_rx)
            {
              rx.push(_packet,_packet->dt[1]);
              break;
            }
            cmd_id = cmd_invalid_dest;
          }
          else
          {
              m_frame->id = 0;
              unsigned cmd_id = getCommand(_packet->dt,len);
              len++;
              if (cmd_id != cmd_none)
              {
                // read command id.
                unsigned id = readHex_u8(_packet->dt + len);
                if (id > 0xFF || _packet->dt[len + 2] != ' ')
                  cmd_id = cmd_invalid_hex;
                else
                {
                  m_frame->id = id;
                  len += 3;
                }
              }
           }
           m_frame->header_len  = 0;
          switch (cmd_id)
          {
          case cmd_i2cw:
            ascii_i2cw(_packet->dt + len,m_frame,i2c);
            break;
          case cmd_can_tx:
            if (ascii_cantx(_packet->dt + len,*m_frame))
            {
              rx.push(m_frame,mcp2515_tx);
            }
            break;
          case cmd_invalid_hex:
            m_frame->len = strcpy(m_frame->dt,"NOK: Invalid hex value\n>");
            rx.push(m_frame,serial_tx);
            break;
          case cmd_none:
            //invalid command
            m_frame->len = strcpy(m_frame->dt,"NOK: Ascii cmd unimplemented\n>");
            rx.push(m_frame,serial_tx);
            break;
          case cmd_invalid_dest:
            m_frame->len = strcpy(m_frame->dt,"NOK: Invalid destination\n>");
            rx.push(m_frame,serial_tx);
            break;
          }
        } else if (_packet->src_rx == reply_rx)
        {
          // sen command id as ok,
          unsigned len;
          _packet->header_len = 0;
          len = strcpy(_packet->dt,"RPL ");
          getHex_u8(_packet->id,_packet->dt + len);
          len += 2;
          _packet->len = len;
          _packet->id = 0;    //no reply for command going to user interface
          rx.push(_packet,serial_tx);
        } else
        {
          // forward packet to serial, with SRC_ID, DATA,
        }
        tx.cts();
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

