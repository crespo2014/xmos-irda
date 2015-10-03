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
 * return cmd and len
 */
{unsigned ,unsigned } static inline getCommand(const unsigned char c[])
{
  unsigned len;
  unsigned id;
  {id,len} = CheckPreffix("I2CR",c);
  if (id) return {cmd_i2cr,len};
  {id,len} = CheckPreffix("I2CW",c);
  if (id) return {cmd_i2cw,len};
  {id,len} =CheckPreffix("I2CWR",c);
  if (id) return {cmd_i2cwr,len};
  {id,len} =CheckPreffix("CANTX",c);
  if (id) return {cmd_can_tx,len};
  {id,len} =CheckPreffix("SPI0",c);
  if (id) return {cmd_spi0_tx,len};
  {id,len} =CheckPreffix("INFO",c);
  if (id) return {cmd_info,len};
  return {cmd_none,0};
}

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
       // tracePacket(_packet);
        unsigned len;
        if (_packet->src_rx == serial_rx || _packet->src_rx == test_rx)
        {
          if (_packet->dt[0] < ' ')   //binary commands should go straight to the device
          {
            _packet->id = _packet->dt[0];
            _packet->cmd_id = _packet->dt[1];
            _packet->header_len = 2;    // id dest
            if (_packet->dt[1] < max_rx)
            {
              rx.push(_packet,_packet->dt[1]);
              break;
            }
            m_frame->cmd_id = cmd_invalid_dest;
          }
          else
          {
            // read command
            { m_frame->cmd_id, len } = getCommand(_packet->dt);
            _packet->header_len = len + 1;
            // read packet id
            if (m_frame->cmd_id != cmd_none)
            {
              unsigned v;
              {v,len} = asciiToHex8(_packet->dt + _packet->header_len);
              _packet->header_len += len;
              if (v > 0xFF || _packet->dt[_packet->header_len] != ' ')
                m_frame->cmd_id = cmd_invalid_hex;
              else
              {
                m_frame->id = v;
                _packet->header_len += 1;
              }
            }
          }
          m_frame->header_len  = 0;
          switch (m_frame->cmd_id)
          {
          case cmd_i2cw:
            ascii_i2cw(_packet->dt + _packet->header_len,m_frame,i2c);
            break;
          case cmd_can_tx:
            if (ascii_cantx(_packet->dt + + _packet->header_len,*m_frame))
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
          // do not reply command with missing id
          if (_packet->id != 0)
          {
            m_frame->header_len = 0;
            m_frame->len = 0;
            m_frame->len += strcpy_2(m_frame->dt+m_frame->len,"RPL ");
            m_frame->len += u8ToHex(_packet->id,m_frame->dt+m_frame->len);
            if (_packet->header_len != _packet->len)
            {
              m_frame->len += DataToHex(_packet->dt+_packet->header_len,_packet->len -_packet->header_len,m_frame->dt+m_frame->len);
            }
            m_frame->len += strcpy_2(m_frame->dt+m_frame->len,"\n>");
            rx.push(m_frame,serial_tx);
          }
        } else
        {
          // forward packet to serial, with SRC_ID, DATA,
          m_frame->header_len = 0;
          m_frame->len = 0;
          switch (_packet->src_rx)
          {
          case mcp2515_rx:
            m_frame->len += strcpy_2(m_frame->dt+m_frame->len,"CANRX ");
            break;
          default:
            m_frame->len += strcpy_2(m_frame->dt+m_frame->len,"RX ");
            break;
          }
          if (_packet->header_len != _packet->len)
          {
            m_frame->len += DataToHex(_packet->dt+_packet->header_len,_packet->len -_packet->header_len,m_frame->dt+m_frame->len);
          }
          m_frame->len += strcpy_2(m_frame->dt+m_frame->len,"\n>");
          rx.push(m_frame,serial_tx);
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

