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

enum i2c_st {
  idle,     // SDA = 1 SCL = 1
  start,    // SDA =0, wait T/2 and read back.
  addr,
  wack,
  data,
  rd,
  wait,   // waiting on port event
  wait2,  // still waiting on port after T/2
  timeout,
};

#define I2C_SDA1  1
#define I2C_SCL1  2
#define I2C_SDA2  4
#define I2C_SCL2  8
#define I2C_MASK1 3
#define I2C_MASK2 12


void i2c_dual(port p)
{
  timer t;
  unsigned char st;
  unsigned char pv,nv;
  unsigned int tp;
  const unsigned int T=4*us;
  set_port_drive_low(p);
  set_port_pull_up(p);
  pv = 0xFF;
  p <: pv;
  while(1)
  {
    select
    {
      case p when pinsneq(pv) :> nv:
        // check if slave is waiting on ping
        break;
      case t when timerafter(tp) :> void:
        // if waiting for ping then timeout at 2
        break;
    }
  }
}

const unsigned T = 1000;
void i2c_start()
{

}

void i2c_address_7bit(unsigned addr)
{

}

void i2c_send_bit(char bit)
{

}

void i2c_send_byte(char data)
{

}

void i2c_wait_start()
{

}

unsigned i2c_read_address_7()
{
    return 0;
}

char i2c_read_bit()
{
    return 0;
}

unsigned i2c_read_byte()
{
    return 0;
}
