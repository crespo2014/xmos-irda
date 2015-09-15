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

#if 0

// This is a combinable i2c TX, but there is not need of combinable tx.
// the only reason to use i2c is because an user command, that is synchronious.
//
/*
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
*/

// 4bits port for a dual i2c configuration
/*
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
*/
/*
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
    pthis->st = i2c_none;
    break;
  }
}
*/

// 4bits port for a dual i2c configuration
/*
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

  i2c[1].st = i2c_none;
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
          if (i2c[i].st != i2c_none) i2c_step_v2(&i2c[i],nv,pv,p);
        }
        st = (i2c[0].st != i2c_none) | (i2c[1].st != i2c_none);
        tp += T;
        break;
    }
  }
}
*/

//TODO set time of next step, 0.6us is the min clock high time, but 1.3ms is the minimum low
/*
inline static void i2c_step_v3(struct i2c_chn_v2* pthis,port sda,port scl)
{
  printf("%d %d\n",pthis->st,pthis->sub_st);
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
    pthis->sub_st = scl_none;
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
    unsigned char c;
    sda :> c;     //lsb to msb
    if (c)  pthis->dt |= 1;
    pthis->dt<<=1;
    pthis->sub_st = to_read;
    scl <: 0;
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
    // set clock down and got next level
    scl <: 0;
    pthis->byte_count--;
    pthis->pfrm->pos++;
    pthis->bit_mask = 1;
    pthis->dt = pthis->pfrm->dt[pthis->pfrm->pos];
    if (pthis->byte_count != 0)
    {
      pthis->st -= 9; // go back to bit1
      break;
    }
    else
      ++pthis->st;
    // check for start2 or rd then initialize at this point
    if (pthis->st == start_2 && pthis->pfrm->wr2_len != 0)
    {
      sda <: 1;
      pthis->sub_st = to_signal;
    }
    else  if (pthis->pfrm->rd_len != 0)
    {
      sda <: 1;
      pthis->st = rdbit1;
      pthis->sub_st = to_read;
      pthis->byte_count = pthis->pfrm->rd_len;
      pthis->dt = 0;
    } else
    {
      pthis->sub_st = to_signal;
      pthis->st = stop;
      sda <: 0;
    }
    break;
  case rdack:
    pthis->pfrm->dt[pthis->pfrm->pos] = pthis->dt;
    pthis->pfrm->pos++;
    pthis->byte_count--;
    pthis->dt = 0;
    sda <: (unsigned char)((pthis->byte_count != 0) ? 0 : 1);
    pthis->sub_st = scl_up;
    break;
  case rdack_done:
    scl <: 0;
    if (pthis->byte_count != 0)
      pthis->st -= 9;
    else
    {
      pthis->sub_st = to_signal;
      pthis->st = stop;
      sda <: 0;
    }
    break;
  case start:
    sda <: 0;
    pthis->sub_st = scl_down;
    pthis->dt = pthis->pfrm->dt[0];
    pthis->pfrm->pos = 0;
    pthis->byte_count = pthis->pfrm->wr1_len;
    break;
  case start_2:
    sda <: 0;
    pthis->byte_count = pthis->pfrm->wr2_len;
    pthis->sub_st = scl_down;
    break;
  case stop:
    sda <: 1;
    pthis->st = i2c_none;
    break;
  default:
    pthis->st = i2c_none;
    break;
  }
}
*/
/*
void i2c_2x1bit_v3(port sda,port scl)
{
  timer t;
  struct i2c_frm frm;
  struct i2c_chn_v2 i2c = { &frm};
  unsigned int tp;
  const unsigned int T=1.5*us;
//  set_port_drive_low(sda);
//  set_port_drive_low(scl);
//  set_port_pull_up(sda);
//  set_port_pull_up(scl);
  sda <: 1;
  scl <: 1;
  // testing data
  i2c.st = start;
  i2c.sub_st = scl_none;
  i2c.baud_count = 0;
  i2c.baud = 0;
  i2c.pfrm->wr1_len = 1;
  i2c.pfrm->wr2_len = 1;
  i2c.pfrm->rd_len = 1;
  i2c.pfrm->dt[0] = 0x55;
  i2c.pfrm->dt[1] = 0x00;
  i2c.pfrm->dt[2] = 0xFF;
  t :> tp;
  while(i2c.st != i2c_none)
  {
    select
    {
      case t when timerafter(tp) :> void:
       if (i2c.st != i2c_none)
         i2c_step_v3(&i2c,sda,scl);
       if (i2c.st == scl_down)
         tp += 600*ns;
       else if (i2c.st != i2c_none)
         tp += T;
       else
         tp += 10*sec;
       break;
    }
  }
}
*/
/*
unsigned get_i2c_buff(const unsigned char* c,struct i2c_frm &ret)
{
  unsigned v;
  unsigned count;
  unsigned pos;
  // <space>XX XX XX XXXXXXX
  do
  {
    v = readHexByte(c);
    if ( v > 0xFF ) break;
    ret.wr1_len = v;
    c++;
    v = readHexByte(c);
    if ( v > 0xFF ) break;
    ret.wr2_len = v;
    c ++;
    v = readHexByte(c);
    if ( v > 0xFF ) break;
    ret.rd_len = v;
    c ++;
    // read
    count = ret.wr1_len + ret.wr2_len;
    pos = 0;
    while(count)
    {
      v = readHexByte(c);
      if ( v > 0xFF ) break;
      ret.dt[pos++] = v;
      count--;
    }
    if (count) break;
    return 1;
  } while(0);
  return 0;
}
*/
/*
void i2c_execute(struct i2c_frm &data,client interface i2c_master_if i2c_if)
{
  data.ret_code = i2c_error;
  size_t num_bytes_sent;
  do
  {
    if (data.wr_len)
    {
      if (i2c_if.write(data.addr,data.dt,data.wr_len,num_bytes_sent,data.rd_len == 0) != I2C_ACK) break;
    }
    if (data.rd_len)
    {
      if (i2c_if.read(data.addr,data.dt + data.wr_len,data.rd_len,1) != I2C_ACK) break;
    }
    data.ret_code = i2c_success;
  } while(0);
}
*/
#endif
void i2c_response(const struct i2c_frm &packet,char* &str)
{
  if (packet.ret_code == i2c_success)
  {
    strcpy(str,"I2C OK ");
    if (packet.rd_len != 0)
      getHexBuffer(packet.dt + packet.wr_len,packet.rd_len,str);
    strcpy(str,"\n");
  }
  else
  {
    strcpy(str,"I2C NOK\n");
  }
}

/*
 * Release the clock and wait until it become high, (Streching)
 * keep readin the port until one 1 is read or no more tries.
 *  d start at F it will drop to 0 after 4 tries
 *
 * Up clock and wait. after 2T is timeout.
 *
 * Read bit from clock at 3/4 part of the high pulse
 */
static enum i2c_ecode i2c_read_bit(port scl, port sda, unsigned T)
{
  unsigned d;
  d = 0x7;
  sda :> int _;
  delay_ticks(T / 2 + T / 32);
  scl <: 1;
  while(1)
  {
    scl :> >>d;
    if (d & 0x80) break;      // todo take time here and return as fall time.
    if (!d) return i2c_timeout;
    delay_ticks(T / 2);
  }
  delay_ticks((T * 3) / 4);   // wait before read
  sda :> d;
  delay_ticks(T / 4);         // wait before put low
  scl <: 0;
  return d;   // 0  or 1
}

static void i2c_start_bit(port i2c_scl, port i2c_sda,unsigned T)
{
  i2c_scl :> void;
  delay_ticks(T / 4);
  i2c_sda  <: 0;
  delay_ticks(T / 2);
  i2c_scl  <: 0;
}

static void i2c_stop_bit(port scl, port sda,unsigned T)
{
  delay_ticks(T/4);
  sda <: 0;
  delay_ticks(T/2);
  scl <: 1;
  delay_ticks(T);
  sda <: 1;
  delay_ticks(T/4);
}

/*
 * Generate a clock signal to send bit already set in sda
 * T period in ticks units
 */
static void i2c_push_bit(port scl,unsigned T)
{
  delay_ticks(T / 2);
  scl <: 1;
  delay_ticks(T / 2);
  scl <: 0;
}


static enum i2c_ecode i2c_push_u8(port sda,port scl,unsigned char d,unsigned T)
{
  unsigned data = ((unsigned) bitrev(d)) >> 24;
    for (int i = 8; i != 0; i--) {
      sda <: >> data;
      i2c_push_bit(scl, T);
    }
    return i2c_read_bit(scl, sda, T);
}

/*
 * DeviceID or address is left shifted and ored with (0 write , 1 read)
 */
static enum i2c_ecode i2c_write(port scl, port sda,unsigned T,unsigned char address,
    const char* data,unsigned len)
{
//  timer t;
//  unsigned tp;
  enum i2c_ecode ret;
  i2c_start_bit(scl,sda,T);
  ret = i2c_push_u8(sda,scl, (address << 1),1);
  while (len && ret == i2c_0)
  {
    ret = i2c_push_u8(sda,scl, *data,1);
    data++;
    len--;
  }
  if (ret == i2c_0) ret = i2c_success;
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
  while (1) {
     select {
     case (size_t i =0; i < n; i++) i2c_if[i].i2c_execute(struct i2c_frm &data):
         data.ret_code = i2c_error;
         if (data.wr_len)
         {
           data.ret_code = i2c_write(scl,sda,T,data.addr,data.dt,data.wr_len);
         }
         if (data.ret_code == i2c_success && data.rd_len)
         {
           data.ret_code = i2c_read(scl,sda,T,data.addr,data.dt + data.wr_len,data.rd_len);
         }
         i2c_stop_bit(scl,sda,T);
         break;
     }
  }
}


