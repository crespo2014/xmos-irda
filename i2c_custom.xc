/*
 * i2c.xc
 *  Implementation of i2c comunication layer
 *  Created on: 10 Jul 2015
 *      Author: lester.crespo
 */

/*
 * I2C packet
 *
 * Write S Address 0 [ACK] Command [ACK] Data [ACK] STOP
 * bits      7     1         8             8
 *
 * Read S Address 0 [ACK] Command [ACK] S Address 1 [ACK] [Data] ACK/NACK STOP
 * bits       7   1          8               8    1                 1
 *
 * S Address 0 [ACK] [DATA] NACK STOP
 */

// TODO full status machine for i2c to reduce code size and response time
// start - wr1bit1 ..wr1bit8 - ack - start2 - wr2bit1..wr2bit8 - ack - rdbit1..rdbit8 - rdack -stop
// substatus clock_up go to clk_down
// status points to next one.

/*
 * 4Bits port
 * 4.7us T is 100Khz
 * 1.3us T is 400Khz   hold clock
 *
 * Idle SDA =1 SCL = 1
 * Start SDA =0 (0.6us - 4us)
 * SCL = 0 SDA = X, SCL = 1 (T) , SCL = 0
 * SDA = 1  release it STOP
 * SCL = 1 ( read ACK from SDA)
 * SCL = 0
 *
 * Clock signal.
 * low for 2T high for T (0.6us - 4us)
 * 1.3us +  0.6us = 2.5us = 400Khz
 *
 * Bus stages.
 * idle
 * initial position (?,0) or star position.
 * send/rec  ?,1
 * start reading   ?,1 valid only if
 * reading   ?,?  valid only if SCL==1
 *
 * Phases.
 * Idle (1,1)
 * Start (0,1)
 * Check Start (?,?) = (0,1)
 * Transition point (0,0)
 * Writing from transition point
 * (X,0)
 * (X,1)
 * (X,0) -- transition point
 * Reading from transition point
 * (1,0)
 * (1,1)
 * --- wait for (?,?) (?,1) then it is valid
 * (1,0) -- transition point
 * Sop condition from transition
 * (0,0) - (0,1) - (1,1)
 *
 */

#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>
#include <xclib.h>
#include "rxtx.h"
#include "i2c_custom.h"
#include "utils.h"
#include "safestring.h"


//void i2c_response(const struct i2c_frm &packet,char* &str)
//{
//  if (packet.ret_code == i2c_success)
//  {
//    safestrcpy(str,"I2C OK ");
//    str = str + safestrlen(str);
//    if (packet.rd_len != 0)
//      getHexBuffer(packet.dt + packet.wr_len,packet.rd_len,str);
//    safestrcpy(str,"\n");
//  }
//  else
//  {
//    safestrcpy(str,"I2C NOK\n");
//  }
//}

/*
 * DeviceID or address is left shifted and ored with (0 write , 1 read)
 */
static enum i2c_ecode i2c_write(port scl, port sda,unsigned T,unsigned char address,
    const char* data,unsigned len)
{
  timer t;
  unsigned tp;
  t :> tp;
  enum i2c_ecode ret;
  I2C_START(scl,sda,T,t,tp);
  I2C_SEND_U8((address << 1),scl,sda,T,t,tp,ret);
  while (len && ret == i2c_ack)
  {
    I2C_SEND_U8(*data,scl,sda,T,t,tp,ret);
    data++;
    len--;
  }
  return ret;
}

static enum i2c_ecode i2c_read(port scl, port sda,unsigned T,unsigned char address,
    const char* data,unsigned len)
{
  return i2c_error;
}

/*
 * TODO for command interface
 *
 * I2CW ADDRESS DATA
 * I2CR ADDRESS READ_LEN
 * I2CWR ADDRESS DATA  READ_LEN
 *
 * ADDRESS will be shifted to the left and use two times in WR command
 *
 * There are two basic operations. read and write
 * read use only the address
 * write use address and data
 * w/r is a combination
 */

unsigned i2cw_decode(const unsigned char* c,struct i2c_frm &ret,char stop_char)
{
  //I2CW ADDRESS DATA
  unsigned v;
  unsigned bret = 1;   //ok
  ret.rd_len = 0;

  v = readHexByte(c);
  ret.addr = v;
  if ((*c != ' ') || (v > 0xFF)) bret = 0;
  if (bret)
  {
    c++;
    ret.wr_len = 0;
    while(bret && *c != stop_char && ret.wr_len < sizeof(ret.dt))
    {
      v = readHexByte(c);
      ret.dt[ret.wr_len++] = v;
      if ( v > 0xFF ) bret = 0;
    }
    if (bret && (*c != stop_char)) bret = 0;
  }
  return bret;
}


unsigned i2cr_decode(const unsigned char* c,struct i2c_frm &ret)
{
  //I2CR ADDRESS READ_LEN
  unsigned bret;
  bret = i2cw_decode(c,ret,'\n');
  if (ret.wr_len != 1 || ret.rd_len > sizeof(ret.dt)) bret = 0;
  ret.rd_len = ret.dt[0];
  ret.wr_len = 0;
  return bret;
}

unsigned i2cwr_decode(const unsigned char* c,struct i2c_frm &ret)
{
  unsigned v;
  //I2CR ADDRESS READ_LEN
  unsigned bret;
  bret = i2cw_decode(c,ret,' ');
  if (bret)
  {
    v = readHexByte(c);
    ret.rd_len = v;
  }
  if ((v > 0xFF) || (*c != '\n') || ret.rd_len + ret.wr_len > sizeof(ret.dt) ) bret = 0;
  return bret;
}

void i2c_decode_answer(struct i2c_frm &data,struct rx_u8_buff &ret)
{
  switch (data.ret_code)
  {
  case i2c_ack:
    char* t = ret.dt;
    safestrcpy(t,"I2C OK ");
    t += safestrlen(t);
    if (data.rd_len != 0)
      getHexBuffer(data.dt + data.wr_len,data.rd_len,t);
    break;
  default:
    char* t = ret.dt;
    safestrcpy(t,"I2CW NOK E: ");
    t += safestrlen(t);
    u8ToHex(data.ret_code,t);
    *t = 0;
    break;
  }
  ret.len = safestrlen(ret.dt);
}

[[distributable]] void i2c_custom(server interface i2c_custom_if i2c_if[n],size_t n,port scl, port sda, unsigned kbits_per_second)
{
  unsigned T = ms/kbits_per_second;
  //size_t num_bytes_sent;
  set_port_drive_low(scl);
  set_port_drive_low(sda);
  //  set_port_pull_up(scl);
  //  set_port_pull_up(sda);
  scl <: 1;   // p_scl :> void;
  delay_ticks(1);
  sda <: 1;
  timer t;
  unsigned tp;
  while (1) {
     select {
     case (size_t i =0; i < n; i++) i2c_if[i].i2c_execute(struct i2c_frm &data):
         t :> tp;
         data.ret_code = i2c_error;
         I2C_START(scl,sda,T,t,tp);
#if 1
         if (data.wr_len)
         {
           data.ret_code = i2c_write(scl,sda,T,data.addr,data.dt,data.wr_len);
         }
         if (data.ret_code == i2c_ack && data.rd_len)
         {
           data.ret_code = i2c_read(scl,sda,T,data.addr,data.dt + data.wr_len,data.rd_len);
         }
#endif
         I2C_STOP(scl,sda,T,t,tp);
         break;
     }
  }
}


