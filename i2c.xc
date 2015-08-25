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
  second_start,
  wr_dt,        // sending
  rd_dt,
  stp,        //
  done,
};

/*
 * I2c substatus
 */
enum i2c_sub_st
{
  updated,      // SCL = 0 , SDA has desired value
  prepared,     // for start, stop we need a transition on scl 1
  send,         // SCL has been set to 1 ( we can read now if scl keep as 1)
  ack_sda,      // waiting for ack
  ack_scl,
  ack_rd,
  sda_set,      // sda has the desire value
  sda_signal,   // a signal is going to be generated or a data will be read
  sda_signal_ready,   // ready to generated signal
  scl_up,       // clock is 1
  scl_down,     // clock just go down ,SCL is 0, but SDA is unknown
  scl_keep,     // keep clock high
  sda_up_down,  // start stop to be applied
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
      //do commun routines
      if (pthis->sub_st = sda_set)
      {
        pv |= scl_mask;
        pthis->sub_st = scl_up;
      }
      else if (pthis->sub_st = scl_up)
      {
        pv &= (~scl_mask);
        pthis->sub_st = scl_down;  // next data to be calculate
      } else if (pthis->sub_st = sda_signal)
      {
        pv |= sda_mask;
        pthis->sub_st = sda_signal_ready;
      } else if (pthis->sub_st = sda_signal_ready)
      {
        pv |= scl_mask;
        pthis->sub_st = scl_keep;
        pthis->baud_count = 0;
      } else if (pthis->sub_st = sda_up_down)
      {
        pv &= (~scl_mask);
        pthis->sub_st = scl_down;
      } else
      switch (pthis->st)
      {
      case  addr:
        switch (pthis->sub_st)
        {
        case scl_down:
          if (pthis->bit_mask == 0)
          {
            // no more data to send
            pv |= sda_mask;
            pthis->sub_st = sda_signal_ready;
          }


          //set next bit value.
          if (pthis->pfrm->addr & pthis->bit_mask) pv |= sda_mask;
          else
            pv &= (~sda_mask);
          pthis->sub_st = updated;
          break;
        case scl_keep:    //tim eto read ack
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
            pthis->sub_st = ack_sda;
          }
          break;
        case ack_sda:
          pv |= sda_mask;
          pthis->sub_st = ack_scl;
          break;
        case ack_scl:
          pv |= scl_mask;
          pthis->sub_st = ack_rd;
          break;
        case ack_rd:
          // check that clock is high . realy
          if (v & scl_mask)
          {
           if (v & sda_mask)
           {
             //nack
             pthis->pfrm->ack = 0;
             pthis->st = done;
           }
           else
           {
             if (pthis->pfrm->wrlen != 0)
               pthis->st = wr_dt;
             else
               pthis->st = rd_dt;
             pthis->byte_pos = 0;
             pthis->bit_mask = 1;
             pthis->sub_st = transition;
             pv &= (~scl_mask);
           }
          }
          break;
        }
        break;
      case second_start:
        switch (pthis->sub_st)
        {
        case clk_0:
          pv |= sda_mask;   //sda = 1
          pthis->sub_st = sda_signal;
          break;
        case updated:
          pv |= scl_mask;
          pthis->sub_st = prepared;
          break;
        case prepared:
          pv &= (~sda_mask);
          pthis->sub_st = send;
          break;
        case send:
          pv &= (~scl_mask);
          break;
        }
        break;
      case wr_dt:
        break;
      case rd_dt:
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

// 4bits port for a dual i2c configuration
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
