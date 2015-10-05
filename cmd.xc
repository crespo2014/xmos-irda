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
  do
  {
    if (id) { id = cmd_spi0_tx; break; }
    {id,len} = CheckPreffix("INFO",c);
    if (id) { id = cmd_info; break; }
    id = cmd_none;
  } while(0);
  return {id,len};
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

/*
 * read command id and device address
 * return  cursor pos, 0 means error
 */
unsigned ascii_i2c_header(const char cmd[],struct rx_u8_buff &ret)
{
  unsigned len,v,pos;
  pos = 0;
  do
  {
    {v,len} = hex_space_to_u8(cmd);   // command id
    if (v > 0xFF) break;
    pos = len;
    ret.cmd_id = v;
    {v,len} = hex_space_to_u8(cmd);   // i2c address
    if (v > 0xFF) break;
    pos += len;
    ret.dt[0] = v;
    return pos;
  } while (0);
  ret.cmd_id = cmd_invalid_hex;
  return 0;
}

/*
 * Decode a i2cw ascii command
 * u8 id
 * u8 addr
 * u8 write len
 *    data
 */
void ascii_i2cw(const char cmd[],struct rx_u8_buff &ret)
{
  unsigned len,v,pos;
  pos = 0;
  do
  {
    {v,len} = hex_space_to_u8(cmd);   // i2c address
    if (v > 0xFF) break;
    pos += (len+1);
    ret.dt[0] = v;
    {v,len} = hex_space_to_u8(cmd + pos);   // write len
    if (v > 0xFF) break;
    pos += (len+1);
    ret.dt[1] = v;
    ret.dt[2] = 0;    // no read command needed
    ret.len = 3 + v;
    if (!hex_to_binary(cmd + pos,ret.dt + 3,v)) break;
    return;
  } while (0);
  ret.cmd_id = cmd_invalid_hex;
}

/*
 * Decode a i2cw ascii command
 * u8 id
 * u8 addr
 * u8 read len
 */
void ascii_i2cr(const char cmd[],struct rx_u8_buff &ret)
{
  unsigned len,v,pos;
  pos = ascii_i2c_header(cmd,ret);
  if (!pos) return;
  do
  {
    {v,len} = hex_space_to_u8(cmd + pos);   // read len
    if (v > 0xFF) break;
    pos += len;
    ret.dt[1] = 0;    // no write command needed
    ret.dt[2] = v;
    ret.len = 3;
    return;
  } while (0);
  ret.cmd_id = cmd_invalid_hex;
}

/*
 * Task to parse user commands.
 */
[[distributable]] void cmd_v1(client interface rx_frame_if rx,server interface tx_if tx)
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
        unsigned len,pos,v;
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
            pos = len + 1;
            // read packet id
            if (m_frame->cmd_id != cmd_none)
            {
              // read command id
              {v,len} = hex_space_to_u8(_packet->dt + pos);   // command id
              m_frame->id = v;
              pos += (len+1);
              if (v > 0xFF)
              {
                m_frame->cmd_id = cmd_invalid_hex;
              }
            }
          }
          m_frame->header_len  = 0;
          switch (m_frame->cmd_id)
          {
          case cmd_i2cw:
            ascii_i2cw(_packet->dt + pos,*m_frame);
            break;
          case cmd_can_tx:
            if (ascii_cantx(_packet->dt + pos,*m_frame))
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
            // analize command to create header.
            switch (_packet->cmd_id)
            {
            case cmd_i2c_nack:
              m_frame->len += strcpy_2(m_frame->dt+m_frame->len,"I2C-NACK ");
              break;
            default:
              m_frame->len += strcpy_2(m_frame->dt+m_frame->len,"RPL ");
              break;
            }
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
          // packet comming from input interface - forward it to serial, with SRC_ID, DATA,
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

