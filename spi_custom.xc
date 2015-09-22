/*
 * spi_custom.xc
 *
 *  Created on: 22 Sep 2015
 *      Author: lester.crespo
 */

#include "spi_custom.h"

/*
 * tree commands available
 */

#define  cmd_one    0x1
#define  cmd_two    0x2
#define  cmd_hello  0x3
#define  cmd_echo   0x4

[[distributable]] void test_spi_slave(server interface spi_slave_if spi_if)
{
  unsigned char cmd_id;
  const unsigned char hello[] ={'H','e','l','l','o'};
  while(1)
  {
    select {
      // for pos zero initialize command
      case spi_if.onData(unsigned char din,unsigned pos)-> unsigned char ret:
        switch (cmd_id)
        {
        case cmd_one:
          ret = pos;
          break;
        case cmd_two:
          ret = pos;
          break;
        case cmd_hello:
          ret = hello[(pos) % sizeof(hello)];
          break;
        case cmd_echo:
          ret = din;
          break;
        default :
          ret = 0xFF;
          break;
        }
        break;
      case spi_if.onCmd(unsigned char dt,unsigned char &cmd_len)->unsigned char ret:
        cmd_id = dt;
        switch (cmd_id)
        {
        case cmd_one:
          cmd_len = 1;
          ret = 0;
          break;
        case cmd_two:
          cmd_len = 3;
          break;
        case cmd_hello:
          cmd_len = 1;
          ret = 'H';
          break;
        case cmd_echo:
          cmd_len = 2;
          break;
        default:
          cmd_len = 1;
          ret = 0xFF;
          break;
        }
        break;
    }
  }
}

void spi_slave(in port ss,in port scl,in port mosi,out port miso,client interface spi_slave_if spi_if)
{
  unsigned pos;
  unsigned char cmd_len;
  unsigned char din,dout,pv,bitmask;
  unsigned char ssv,sclv;
  ssv = 1;
  while(1)
  {
    ss when pinseq(0) :> ssv;
    scl :> sclv;
    pos = 0;    // cmd
    cmd_len = 0xFF;     // rd pos is less than
    bitmask = 0x80;
    din = 0;
    while(ssv == 0)
    {
      select
      {
        case ss when pinsneq(ssv) :> ssv:
          break;
        case scl when pinsneq(sclv) :> sclv:
          if (sclv == 1)  // clock up, read data, if 8 bits then prepare to send data at the next clock down
          {
            mosi :> pv;
            if (pv & 1)
              din |= bitmask;
            bitmask >>=1;
            if (bitmask == 0)
            {
              // eight bit send
              if (pos == 0)
                dout = spi_if.onCmd(din,cmd_len);
              else
                dout = spi_if.onData(din,pos);
              din = 0;
              bitmask = 0x80;
              pos++;
            }
          } else if (pos >= cmd_len)      // clock down write data
          {
            if (dout & bitmask)
              miso <: 1;
            else
              miso <: 0;
          }
          break;
      }

    }

  }
}
