/*
 * i2c.xc
 *  Implementation of i2c comunication layer
 *  Created on: 10 Jul 2015
 *      Author: lester.crespo
 */

/*
//TODO use the i2c lib provided
 * Configure port as pull up and
 * and set set_port_drive_low() it means do not drive on 1
 * use a 4bit port to control two i2c
 * do not use share port to avoid delays
 *
 * made it combinable with buffers usign timers.
 * synchronize both i2c to one timer.
 */

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
#include "rxtx.h"

/*
 * main state (idle, start,addr,data_wr, data_ack, data_rd, stop)
 * substates (transition, update/prepare, send(clk) )
 *
 * how many data to read/write
 * each byte requered a ack.
 * each frame required read or write count bytes
 *
 * push a i2c frame will return data in the same frame
 * cmd interfaz only send i2c one by one, but it need to be asynchronious
 */

struct i2c_frm
{
    unsigned short addr;  //including r/w bit
    unsigned char  dt[20];  // read or written data
    unsigned char  rdlen;   // how many bytes to read
    unsigned char  wrlen;   // how many bytes of data to write
    unsigned char  ack;    // 1 = command sucessfull
    unsigned char  rdwr;   // 1 write 0 read
};

enum i2c_st {
  idle,     // SDA = 1 SCL = 1
  start,    // start sent SDA =0
  addr,
  addr_ack,
  wr_dt,        // sending
  wr_dt_ack,
  rd_dt,
 // rd_dt_ack,
  stp,        //
  done,
};

/*
 * I2c substatus
 */
enum i2c_sub_st
{
  transition,   // SCL is 0, but SDA is unknown
  updated,      // SCL = 0 , SDA has desired value
  send,         // SCL has been set to 1 ( we can read now if scl keep as 1)
  //ack,          // waiting for ack
};

// All information about i2c device
struct i2c_chn
{
    struct i2c_frm frm;
    struct i2c_frm* movable pfrm;
    enum i2c_st st;
    enum i2c_sub_st sub_st;
    unsigned char bit_mask;  // for rd/rw byte
    unsigned char byte_pos;   // for rd/wr buffer
    unsigned short baud;    // to support different rates on bus.
    unsigned short baud_count;    //set to baud, when reach zero the channel is update
};

#define I2C_SDA1  1
#define I2C_SCL1  2
#define I2C_SDA2  4
#define I2C_SCL2  8
#define I2C_MASK1 3
#define I2C_MASK2 12

inline void i2c_step(struct i2c_chn* pthis,unsigned char v,unsigned char &pv,unsigned char sda_mask,unsigned char scl_mask)
{
  if (pthis->st != idle)
  {
    if (pthis->baud_count == 0)
    {
      pthis->baud_count = pthis->baud;
      switch (pthis->st)
      {
      case  addr:
        switch (pthis->sub_st)
        {
        case transition:  //set next bit value.
          if (pfrm->addr & bit_mask) pv |= sda_mask;
          else
            pv &= (~sda_mask);
          pthis->sub_st = updated;
          break;
        case updated:
          pv |= scl_mask;
          pthis->sub_st = send;
          break;
        case send:
          pv &= (~scl_mask);
          if (pthis->bit_mask < 0x80)
          {
            pthis->bit_mask <<=1;
            pthis->sub_st = transition;
          }
          else
          {
            //read ack
            pv |= sda_mask;
            pthis->st = addr_ack;
            pthis->sub_st = updated;
          }
          break;
        case addr_ack:
          switch (pthis->sub_st)
          {
          case updated:
            pv |= scl_mask;
            pthis->sub_st = send;
            break;
          case send:
            // check that clock is high
            if (nv & scl_mask)
            {
              if (nv & sda_mask)
              {
                //nack
                pthis->pfrm->ack = 0;
                pthis->st = done;
              }
              else
              {
                pthis->st = wr_dt;
                pthis->sub_st = transition;
                pv &= (~scl_mask);
              }
            }
            break;

          }
          break;
        }
        break;
        case addr_ack:
      case wr_dt:
        break;
      case rd_dt:
        break;
      case wr_dt_ack:
        break;
      case rd_dt_ack:
        break;
      case addr_ack:
        break;
      case start:
        break;
      case stp:
        break;
      }
    }
    else
      pthis->baud_count--;
  }
}

void i2c_dual(port p)
{
  timer t;
  struct i2c_chn i2c[2];

  unsigned char st;
  unsigned char pv,nv;
  unsigned int tp;
  const unsigned int T=4*us;
  set_port_drive_low(p);
  set_port_pull_up(p);
  pv = 0xFF;
  nv = 0xFF;
  st = 0;   // idle
  p <: pv;
  t :> tp;
  while(1)
  {
    select
    {
      case st == 0 => p when pinsneq(nv) :> nv:
        // keep pins value updated to avoid reading from port
        break;
      case st != 0 => t when timerafter(tp) :> void:
        p <: pv;

        // if waiting for ping then timeout at 2
        break;
    }
  }
}
