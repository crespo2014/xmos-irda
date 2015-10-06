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
  {id,len} = CheckPreffix("INFO",c);
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

/*
 * Decode a i2cw ascii command
 * u8 id
 * u8 addr
 * u8 write len
 *    data
 */
unsigned ascii_i2cw(const char cmd[],struct rx_u8_buff &ret)
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
    return 1;
  } while (0);
  return 0;
}

/*
 * Decode a i2cw ascii command
 * u8 id
 * u8 addr
 * u8 read len
 */
unsigned ascii_i2cr(const char cmd[],struct rx_u8_buff &ret)
{
  unsigned len,v,pos;
  pos = 0;
  do
  {
    {v,len} = hex_space_to_u8(cmd);   // i2c address
    if (v > 0xFF) break;
    pos += (len+1);
    ret.dt[0] = v;
    {v,len} = hex_space_to_u8(cmd + pos);   // read len
    if (v > 0xFF) break;
    pos += len;
    ret.dt[1] = 0;    // no write command needed
    ret.dt[2] = v;
    ret.len = 3;
    return 1;
  } while (0);
  return 0;
}
/*
 * i2c write + read command
 */
unsigned ascii_i2cwr(const char cmd[],struct rx_u8_buff &ret)
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
    ret.dt[1] = v;
    pos += (len+1);
    {v,len} = hex_space_to_u8(cmd + pos);   // read len
    if (v > 0xFF) break;
    ret.dt[2] = v;
    pos += (len+1);
    if (!hex_to_binary(cmd + pos,ret.dt + 3,v)) break; // data to write
    return 1;
  } while (0);
  return 0;
}

unsigned build_ascii_Reply(const struct rx_u8_buff  &rpl,struct rx_u8_buff  &ret)
{
  // Notify to user that packet was delivered
  if (rpl.id == 0 && rpl.header_len == rpl.len ) return 0;
  ret.header_len = 0;
  ret.len = 1;
  ret.dt[0] = ':';
  ret.len += u8ToHex(rpl.id,ret.dt+ret.len);
  ret.dt[ret.len++] = ' ';
  // analize command to create header.
  switch (rpl.cmd_id)
  {
  case cmd_i2c_nack:
    ret.len += strcpy_2(ret.dt + ret.len,"I2C-NACK ");
    break;
  case cmd_can_rx:
    ret.len += strcpy_2(ret.dt + ret.len,"CANRX ");
    break;
  default:
    ret.len += strcpy_2(ret.dt + ret.len,"OK ");
    break;
  }
  if (rpl.header_len != rpl.len)
  {
    ret.len += DataToHex(rpl.dt+rpl.header_len,rpl.len -rpl.header_len,ret.dt+ret.len);
  }
  ret.len += strcpy_2(ret.dt+ret.len,"\n>");
  return 1;
}
/*
 * Extract all info from ascii command and build a response or a packet to destination interface
 */
unsigned decode_ascii_frame(const struct rx_u8_buff  &cmd,struct rx_u8_buff  &ret)
{
  unsigned len,pos,v;
  { ret.cmd_id, len } = getCommand(cmd.dt + 0);
  if (!len) return 0;
  pos = len + 1;
  {v,len} = hex_space_to_u8(cmd.dt + pos);   // command id
  if (v > 0xFF) return 0;
  ret.id = v;
  pos += (len+1);
  ret.header_len  = 0;
  switch (ret.cmd_id)
  {
  case cmd_i2cw:
    return ascii_i2cw(cmd.dt + pos,ret);
  case cmd_i2cr:
    return ascii_i2cr(cmd.dt + pos,ret);
  case cmd_can_tx:
    return ascii_cantx(cmd.dt + pos,ret);
  default:
    return 0;
  }
}
/*
 * Dispatch the packet
 * or send back to user if something went wrong
 */
void dispatch_packet(struct rx_u8_buff  * movable &packet,client interface rx_frame_if rx)
{
  switch (packet->cmd_id)
  {
  case cmd_i2cw:
  case cmd_i2cr:
  case cmd_i2cwr:
    rx.push(packet,tx_i2c);
    return;
  case cmd_can_tx:
    rx.push(packet,mcp2515_tx);
    return;
  case cmd_none:
    packet->len = strcpy(packet->dt,":NOK cmd unimplemented\n>");
    break;
  case cmd_invalid_dest:
    packet->len = strcpy(packet->dt,"NOK: Invalid destination\n>");
    break;
  default:
    packet->len = strcpy(packet->dt,":NOK\n>");
    break;
  }
  packet->header_len = 0;
  rx.push(packet,serial_tx);
}

/*
 * Task to parse user commands.
 */
[[distributable]] void cmd_v1(client interface rx_frame_if rx,server interface tx_if tx)
{
  // packet use to push
  struct rx_u8_buff tfrm;   // temporal frame
  struct rx_u8_buff * movable m_frame = &tfrm;
  unsigned ascii_mode = 1;    //all data from rx is send to commnad to return as ascii or not
  tx.cts();
  while(1)
  {
    select
    {
      case tx.send(struct rx_u8_buff  * movable &_packet):
       // tracePacket(_packet);
        unsigned len,pos,v;
        m_frame->header_len = 0;
        if (_packet->src_rx == serial_rx || _packet->src_rx == test_rx)
        {
          if (_packet->dt[0] != ':')   //binary commands should go straight to the device
          {
            _packet->id = _packet->dt[0];
            _packet->cmd_id = _packet->dt[1];
            _packet->header_len = 2;    // id dest
            dispatch_packet(_packet,rx);
          } else
          {
            if (!decode_ascii_frame(*_packet,*m_frame))
              m_frame->cmd_id = cmd_none;
            dispatch_packet(m_frame,rx);
          }
        } else
        {
          // Data from interfaces are send to user.
          if (ascii_mode && build_ascii_Reply(*_packet,*m_frame))
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

