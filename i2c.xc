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
    unsigned char  dt[20];  // read or written data
    unsigned char  wr1_len;   // how many bytes of data to write at first
    unsigned char  wr2_len;   // how many bytes of data to write at first
    unsigned char  rd_len;   // how many bytes to read
    unsigned char  ack;    // 1 = command sucessfull
    unsigned char  pos;     // w/r pos
};


/*
 * Status.
 * idle - to start transmition set sda=0, st = addr, sub_st = clk_up, bitmask
 */
enum i2c_st {
  idle,     // SDA = 1 SCL = 1
  wr1,      // written
  start2,
  wr2,    // written after a second start (dummy write)
  rd,     // reading
  stp,        //
};

/*
 * I2c substatus
 * Reading and generating signals have identical states
 */
enum i2c_sub_st
{
  sda_set,      // sda has the desire value
  scl_up,       // clock is 1
  scl_down,     // clock just go down ,SCL is 0, but SDA is unknown
  // read or signal generator
  read_prepared,   // a signal is going to be generated or a data will be read
  read_send,        // ready to generate the signal
  read_done,    // it is different to clock down
};

// All information about i2c device
struct i2c_chn
{
    struct i2c_frm frm;
    struct i2c_frm* movable pfrm;
    enum i2c_st st;
    enum i2c_sub_st sub_st;
    unsigned char dt;         // data currently sending
    unsigned char bit_mask;   // for rd/rw byte
    unsigned char byte_count;   // how many bytes left to write or read
    unsigned short baud;    // to support different rates on bus.
    unsigned short baud_count;    //set to baud, when reach zero the channel is update
};

#define I2C_SDA1  1
#define I2C_SCL1  2
#define I2C_SDA2  4
#define I2C_SCL2  8
#define I2C_MASK1 3
#define I2C_MASK2 12

void i2c_step(struct i2c_chn* pthis,unsigned char v,unsigned char &pv,unsigned char sda_mask,unsigned char scl_mask)
{
#pragma fallthrough
  if (pthis->st != idle)
  {
    if (pthis->baud_count == 0)
    {
      pthis->baud_count = pthis->baud;
      //do commun routines
      if (pthis->sub_st == sda_set)
      {
        pv |= scl_mask;
        pthis->sub_st = scl_up;
      }
      else if (pthis->sub_st == scl_up)
      {
        pv &= (~scl_mask);
        pthis->sub_st = scl_down;  // next data to be calculate
      } else if (pthis->sub_st == read_prepared)
      {
        pv |= scl_mask;  // SCL =1
        pthis->sub_st = read_send;
        pthis->baud_count = 0;
      } else
      switch (pthis->st)
      {
      case  wr1:
      case wr2:
        switch (pthis->sub_st)
        {
        case scl_down:
          if (pthis->bit_mask == 0)
          {
            // ack
            pv |= sda_mask;
            pthis->sub_st = read_prepared;
          }
          else
          {
            //set next bit value.
            if (pthis->dt & pthis->bit_mask)
              pv |= sda_mask;
            else
              pv &= (~sda_mask);
            pthis->sub_st = sda_set;
            pthis->bit_mask <<=1;
            pthis->baud_count = 0;  //set value fast
          }
          break;
        case read_send:    //read ack
          if (v & sda_mask)
          {
            //nack
            pthis->pfrm->ack = 0;
            pthis->st = stp;
          }
          else
          {
            if (pthis->byte_count != 0)
            {
              pthis->dt = pthis->pfrm->dt[pthis->pfrm->pos++];
              --pthis->byte_count;
              pthis->bit_mask = 1;
            }
            else
            {
              if ((pthis->st == wr1) && (pthis->pfrm->wr2_len != 0))
              {
                // second start
                pthis->st = start2;
              }
              else
              {
                // reading data
                if (pthis->pfrm->rd_len !=0)
                {
                  // reading
                  pthis->st = rd;
                }
                else
                {
                  //stop
                  pthis->st = stp;
                }
              }
            }
          pthis->sub_st = scl_down;
          pv &= (~scl_mask);
          break;
        }
        break;
        }
      case start2:
        switch (pthis->sub_st)
        {
        case read_send:  // sda 1, scl 1
          pv &= (~sda_mask);   //sda = 0
          pthis->sub_st = scl_up;   // it will be scl down
          pthis->bit_mask = 1;
          pthis->st = wr2;
          break;
        }
        break;
      case rd:
        break;
      case stp:
        switch (pthis->sub_st)
        {
        case scl_down:
          pv &= (~sda_mask);   //sda = 0
          pthis->sub_st = read_prepared;
          break;
        case read_send:  // sda 1, scl 1
          pv |= sda_mask;
          pthis->sub_st = idle;
          break;
        }
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
      case st => t when timerafter(tp) :> void:
        p <: pv;
        if (i2c[0].st != idle)
        {
          do
          {
            i2c_step(&i2c[0],nv,pv,I2C_SDA1,I2C_SCL1);
            if (i2c[0].baud_count == 0)
              p<:pv;
          } while (i2c[0].baud_count == 0);
        }
        if (i2c[1].st != idle)
        {
          do
          {
            i2c_step(&i2c[1],nv,pv,I2C_SDA2,I2C_SCL2);
            if (i2c[0].baud_count == 0)
              p<:pv;
          } while (i2c[0].baud_count == 0);
        }
        st = (i2c[0].st != idle) | (i2c[1].st != idle);
        tp += T;
        break;
    }
  }
}
