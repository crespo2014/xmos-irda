/*
 * i2c.xc
 *  Implementation of i2c comunication layer
 *
 *  Packet Description
 *  Address u8 - device address
 *  wr_len  u8 - len of data to write
 *  rd_len  u8 - len of data to read
 *  data       - data to be written
 *
 *  Reply
 *  i2c     u8  i2c id
 *  address u8  device address
 *  data        read data
 *
 *
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

[[distributable]] void i2c_master_v2(struct i2c_master_t &obj,server interface tx_if tx)
{
  i2c_init(obj);
  tx.cts();
  while(1)
  {
    select
    {
    case tx.send(struct rx_u8_buff  * movable &pck):
      i2c_execute(obj,*pck);
      tx.cts();
      break;
    case tx.ack():
      break;
    }
  }
}


[[distributable]] void i2c_custom(server interface i2c_custom_if i2c_if[n],size_t n,port scl, port sda, unsigned kbits_per_second)
{
  unsigned T = ms/kbits_per_second;
  timer t;
  unsigned tp;
  //size_t num_bytes_sent;
  set_port_drive_low(scl);
  set_port_drive_low(sda);
  //  set_port_pull_up(scl);
  //  set_port_pull_up(sda);
  scl <: 1;   // p_scl :> void;
  delay_ticks(1);
  sda <: 1;
  while (1) {
     select {
     case i2c_if[unsigned i].i2c_execute(struct i2c_frm &data):
         t :> tp;
#if 0
         data.ret_code = i2c_ack;
         if (data.wr_len)
         {
           data.ret_code = I2C_WRITE_BUFF(data.addr,data.dt,data.wr_len,scl,sda,T,t,tp);
           t when timerafter(tp) :> void;
         }
#endif
#if 0
         if (data.ret_code == i2c_ack && data.rd_len)
         {
           data.ret_code = I2C_READ_BUFF(data.addr,data.dt + data.wr_len,data.rd_len,scl,sda,T,t,tp);
         }
         I2C_STOP(scl,sda,T,t,tp);
#endif
         break;
     }
  }
}


