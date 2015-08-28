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
#include "rxtx.h"
#include "i2c.h"



// TODO on scl down update pv and port, and prepare for scl up next time

inline static void i2c_step(struct i2c_chn* pthis,unsigned char v,unsigned char &pv,port p)
{
#pragma fallthrough
  if (pthis->baud_count == 0)
  {
    pthis->baud_count = pthis->baud;
    if (pthis->sub_st == scl_up)
    {
      pv &= (~pthis->scl_mask);
      pthis->sub_st = scl_down;  // next data to be calculate
    }
    else
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
          pv |= pthis->sda_mask;
          p <: pv;  // update sda allowed if scl = 0
          pv |= pthis->scl_mask;  // SCL =1
          pthis->sub_st = read_send;
        }
        else
        {
          //set next bit value.
          if (pthis->dt & pthis->bit_mask)
            pv |= pthis->sda_mask;
          else
            pv &= (~pthis->sda_mask);
          pthis->bit_mask <<=1;
          pthis->baud_count = 0;  //set value fast
          p <: pv;  // update sda allowed if scl = 0
          pv |= pthis->scl_mask;
          pthis->sub_st = scl_up;
        }
        break;
      case read_send:    //read ack
        if (v & pthis->sda_mask)
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
        pv &= (~pthis->scl_mask);
        break;
      }
      break;
      }
    case start2:
      switch (pthis->sub_st)
      {
      case scl_down:
        pv |= pthis->sda_mask;  // SDA = 1
        p <: pv;
        pv |= pthis->scl_mask;  // SCL = 1  later
        pthis->sub_st = read_send;
        break;
      case read_send:  // sda 1, scl 1
        pv &= (~pthis->sda_mask);   //sda = 0
        pthis->sub_st = scl_up;   // it will be scl down
        pthis->bit_mask = 1;
        pthis->st = wr2;
        break;
      }
      break;
    case rd:
      if (pthis->sub_st == read_done)
      {
        if (pthis->bit_mask == 0)
        {
          pv &= (~pthis->sda_mask);
          p <: pv;
          pthis->sub_st = ack_send;
        }
        else
        {
          pthis->sub_st == read_send;
        }
        pv |= pthis->scl_mask;
      } else if (pthis->sub_st == read_send)
      {
        //check clock before read
        if (v & pthis->sda_mask)
        {
          pthis->dt |= pthis->bit_mask;
        }
        pthis->bit_mask <<= 1;
        if (pthis->bit_mask == 0)
        {
          pthis->pfrm->dt[pthis->pfrm->pos++] = pthis->dt;
        }
        pthis->sub_st = read_done;
        pv &= (~pthis->scl_mask);
      } else if (pthis->sub_st == ack_send)
      {
        if (pthis->byte_count != 0)
        {
          pthis->sub_st = read_done;
          pthis->bit_mask = 1;
          pthis->dt = 0;
        }
      }
      break;
    case stp:
      switch (pthis->sub_st)
      {
      case scl_down:
        pv &= (~pthis->sda_mask);   //sda = 0
        p <: pv;
        pv |= pthis->scl_mask;  // SCL = 1  later
        pthis->sub_st = read_send;
        break;
      case read_send:  // sda 0, scl 1
        pv |= pthis->sda_mask;
        pthis->sub_st = idle;
        break;
      }
      break;
    }
  }
  else
    pthis->baud_count--;

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
//  set_port_pull_up(p);
  i2c[0].scl_mask = I2C_SCL1;
  i2c[0].sda_mask = I2C_SDA1;
  i2c[1].scl_mask = I2C_SCL2;
  i2c[1].sda_mask = I2C_SDA2;
  pv = 0xFF;
  nv = 0xFF;
  st = 0;   // idle
  // testing data
  i2c[0].st = wr1;
  i2c[0].sub_st = scl_up;
  i2c[0].baud_count = 0;
  i2c[0].baud = 0;
  i2c[0].dt = 0x55;
  i2c[0].bit_mask = 1;
  i2c[0].frm.pos = 0;
  i2c[0].frm.wr1_len = 1;
  i2c[0].frm.wr2_len = 0;
  i2c[0].frm.rd_len = 0;
  i2c[0].frm.dt[0] = 1;

  i2c[1].st = wr1;
  i2c[1].sub_st = scl_up;
  i2c[1].baud_count = 0;
  i2c[1].baud = 0;
  i2c[1].dt = 0x55;
  i2c[1].bit_mask = 1;
  i2c[1].frm.pos = 0;
  i2c[1].frm.wr1_len = 1;
  i2c[1].frm.wr2_len = 0;
  i2c[1].frm.rd_len = 0;
  i2c[1].frm.dt[0] = 1;

  st = 1;
  p <: pv;
  t :> tp;
  while(st != 0)
  {
    select
    {
      case st == 0 => p when pinsneq(nv) :> nv:
        // keep pins value updated to avoid reading from port
        break;
      case st => t when timerafter(tp) :> void:
        p <: pv;
        for (int i=2;i!=0;)
        {
          --i;
          if (i2c[i].st != idle) i2c_step(&i2c[i],nv,pv,p);
        }
        st = (i2c[0].st != idle) | (i2c[1].st != idle);
        tp += T;
        break;
    }
  }
}

inline static void i2c_step_v2(struct i2c_chn_v2* pthis,unsigned char v,unsigned char &pv,port p)
{
  if (pthis->baud_count != 0)
  {
    --pthis->baud_count;
    return;
  }
  pthis->baud_count = pthis->baud;
  if (pthis->sub_st == scl_up)
  {
    pv &= (~pthis->scl_mask);
    pthis->sub_st = scl_down;
    pthis->st++;
    return;
  } else if (pthis->sub_st == reading)
    {
      unsigned char tmp;
      p :> tmp;
      if ((tmp & pthis->scl_mask) == 0)
        return;   // wait next time
      pthis->st++;
    }
  switch (pthis->st)
  {
  case start:
    pv &= (~pthis->sda_mask);
    pthis->sub_st = scl_up;
    pthis->dt = pthis->pfrm->dt[0];
    pthis->bit_mask = 1;
    pthis->pfrm->pos = 0;
    pthis->byte_count = pthis->pfrm->wr1_len;
    break;
  case wrbit1:
  case wrbit2:
  case wrbit3:
  case wrbit4:
  case wrbit5:
  case wrbit6:
  case wrbit7:
  case wrbit8:
    if (pthis->dt & pthis->bit_mask)
      pv |= pthis->sda_mask;
    else
      pv &= (~pthis->sda_mask);
    pthis->bit_mask <<=1;
    p <: pv;  // update sda allowed if scl = 0
    pv |= pthis->scl_mask;
    pthis->sub_st = scl_up;
    break;
  case wrack:
  case wr2ack:
    pv |= pthis->sda_mask;
    p <: pv;
    pv |= pthis->scl_mask;
    pthis->sub_st = reading;
    break;
  case wr_ack_rd:
  case wr2_ack_rd:
    unsigned char tmp;
    p :> tmp;
    if (tmp & pthis->sda_mask)
    {
      //nok
    }
    // set clock down
    pthis->sub_st = scl_down;
    pv &= (~pthis->scl_mask);
    pthis->byte_count--;
    pthis->pfrm->pos++;
    pthis->bit_mask = 1;
    pthis->dt = pthis->pfrm->dt[pthis->pfrm->pos];
    if (pthis->byte_count != 0)
    {
      if (pthis->st == wr_ack_rd)
        pthis->st = wrbit1;
      else
        pthis->st = wr2bit1;

    } else
    {
      if ((pthis->st == wr_ack_rd) && (pthis->pfrm->wr2_len != 0))
        pthis->st = start2;
      else if ((pthis->st == wr2_ack_rd) && (pthis->pfrm->rd_len != 0))
        pthis->st = rd;
      else
        pthis->st = stop;
    }
    break;
  case stop:
    break;
  default:
    pthis->st = none;
    break;
  }
}

// 4bits port for a dual i2c configuration
void i2c_dual_v2(port p)
{
  timer t;
  struct i2c_frm frm[2];
  struct i2c_chn_v2 i2c[2] = { {&frm[0]},{&frm[1]}};
  unsigned char st;
  unsigned char pv,nv;
  unsigned int tp;
  const unsigned int T=4*us;
  set_port_drive_low(p);
//  set_port_pull_up(p);
  i2c[0].scl_mask = I2C_SCL1;
  i2c[0].sda_mask = I2C_SDA1;
  i2c[1].scl_mask = I2C_SCL2;
  i2c[1].sda_mask = I2C_SDA2;
  pv = 0xFF;
  nv = 0xFF;
  st = 0;   // idle
  // testing data
  i2c[0].st = start;
  i2c[0].sub_st = scl_down;
  i2c[0].baud_count = 0;
  i2c[0].baud = 0;
  i2c[0].pfrm->wr1_len = 1;
  i2c[0].pfrm->wr2_len = 0;
  i2c[0].pfrm->rd_len = 0;
  i2c[0].pfrm->dt[0] = 0x55;

  i2c[1].st = none;
  i2c[1].sub_st = scl_up;
  i2c[1].baud_count = 0;
  i2c[1].baud = 0;
  i2c[1].pfrm->wr1_len = 1;
  i2c[1].pfrm->wr2_len = 0;
  i2c[1].pfrm->rd_len = 0;
  i2c[1].pfrm->dt[0] = 0xAA;

  st = 1;
  p <: pv;
  t :> tp;
  while(st != 0)
  {
    select
    {
      case st == 0 => p when pinsneq(nv) :> nv:
        // keep pins value updated to avoid reading from port
        break;
      case st => t when timerafter(tp) :> void:
        p <: pv;
        for (int i=0;i<2;++i)
        {
          if (i2c[i].st != none) i2c_step_v2(&i2c[i],nv,pv,p);
        }
        st = (i2c[0].st != none) | (i2c[1].st != none);
        tp += T;
        break;
    }
  }
}

inline static void i2c_step_v3(struct i2c_chn_v2* pthis,port sda,port scl)
{
  if (pthis->baud_count != 0)
  {
    --pthis->baud_count;
    return;
  }
  pthis->baud_count = pthis->baud;
  switch (pthis->sub_st)
  {
  case scl_up:
  case to_read:
  case to_signal:
    scl <: 1;
    pthis->sub_st++;
    return;
    break;
  case scl_down:
    scl <: 0;
    pthis->sub_st++;
    pthis->st++;
    break;
  case reading:
    unsigned char tmp;
    scl :> tmp;
    //if (tmp == 0) return; // clock streching
    pthis->st++;
    break;
  }
  if ((pthis->st >= wrbit1 && pthis->st <= wrbit8 ) ||
      (pthis->st >= wr2bit1 && pthis->st <= wr2bit8 ) )
  {
    pthis->sub_st = scl_up;
    sda <: >>pthis->dt;     //lsb to msb
    return;
  } else if (pthis->st >= rdbit1 && pthis->st <= rdbit8 )
  {
    pthis->sub_st = scl_down;
    pthis->dt<<=1;
    unsigned char c;
    sda :> c;     //lsb to msb
    if (c)  pthis->dt |= 1;
    return;
  }
  switch (pthis->st)
  {
  case wr2ack:
  case wrack:
    sda <: 1;
    pthis->sub_st = to_read;
    break;
  case wr_ack_rd:
  case wr2_ack_rd:
    unsigned char tmp;
    sda :> tmp;
    if (tmp)
    {
      //nok
    }
    // set clock down  // set clock down and got next level
    scl <: 0;
    pthis->byte_count--;
    pthis->pfrm->pos++;
    pthis->bit_mask = 1;
    pthis->dt = pthis->pfrm->dt[pthis->pfrm->pos];
    if (pthis->byte_count != 0)
    {
     if (pthis->st == wr_ack_rd)
       pthis->st = wrbit1;   // one before
     else
       pthis->st = start_2;
    }
    else
      ++pthis->st;
    break;
  case start:
    pthis->sub_st = scl_down;
    pthis->dt = pthis->pfrm->dt[0];
    pthis->pfrm->pos = 0;
    pthis->byte_count = pthis->pfrm->wr1_len;
    sda <: 0;
    break;
#pragma fallthrough
  case start_2:
    if (pthis->sub_st == signaling)
    {
      pthis->byte_count = pthis->pfrm->wr2_len;
      sda <: 0;
      pthis->sub_st = scl_down;
      break;
    }
    if (pthis->pfrm->wr2_len != 0)
    {
      sda <: 1;
      pthis->sub_st = to_signal;
      break;
    }
    pthis->st = start_rd;   // try reading
#pragma fallthrough
  case start_rd:
    if (pthis->pfrm->rd_len != 0)
    {
      sda <: 1;
      pthis->st = rdbit1;
      pthis->sub_st = to_read;
      break;
    }
    pthis->st = stop;
  case stop:
    if (pthis->sub_st == signaling)
    {
      sda <: 1;
      pthis->st = none;
    }
    else
    {
      sda <: 0;
      pthis->sub_st = to_signal;
    }
    break;
  default:
    pthis->st = none;
    break;
  }
}

void i2c_2x1bit_v3(port sda,port scl)
{
  timer t;
  struct i2c_frm frm;
  struct i2c_chn_v2 i2c = { &frm};
  unsigned int tp;
  const unsigned int T=1.5*us;
  //set_port_drive_low(sda);
 // set_port_drive_low(scl);
//  set_port_pull_up(p);
  sda <: 1;
  scl <: 1;
  // testing data
  i2c.st = start;
  i2c.sub_st = scl_none;
  i2c.baud_count = 0;
  i2c.baud = 0;
  i2c.pfrm->wr1_len = 1;
  i2c.pfrm->wr2_len = 2;
  i2c.pfrm->rd_len = 1;
  i2c.pfrm->dt[0] = 0x55;
  i2c.pfrm->dt[1] = 0x00;
  i2c.pfrm->dt[2] = 0xFF;
  t :> tp;
  while(i2c.st != none)
  {
    select
    {
      case t when timerafter(tp) :> void:
       if (i2c.st != none)
         i2c_step_v3(&i2c,sda,scl);
        tp += ((i2c.st != none) ? T : sec) ;
        break;
    }
  }
}
