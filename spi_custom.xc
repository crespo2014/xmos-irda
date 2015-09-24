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

[[distributable]] void test_spi_slave_v2(server interface spi_slave_if_v2 spi_if)
{
  unsigned char cmd_id;
  unsigned char wr_pos;
  unsigned char rd_pos;
  const unsigned char hello[] ={'H','e','l','l','o','\n'};
  while(1)
  {
    select {
      // for pos zero initialize command
      case spi_if.onSS()-> unsigned char ret:
          ret = 0;
          wr_pos = 0;
          rd_pos = 0;
          break;
      case spi_if.onData(unsigned char din)->unsigned char ret:
        if (wr_pos == 0)
        {
          cmd_id = din;
        }
        switch (cmd_id)
        {
        case cmd_one:
        case cmd_two:
          ret = wr_pos;
          break;
        case cmd_hello:
          if (rd_pos == sizeof(hello)) rd_pos = 0;
          ret = hello[rd_pos++];
          break;
        case cmd_echo:
          ret = (wr_pos == 0) ? 0 : din;
          break;
        default :
          ret = 0xFF;
          break;
        }
        wr_pos++;
        break;
    }
  }
}

/*
 * Simple interface
 * todo use a multibit input port.
 * wait for port change if ss = 1 get out
 * if data change then ignore
 * if clock change then do it. prev ^ next -> return 1 if bit change (prev ^ next) & clk_mask
 * clock edge switch between 0 and 1, to match cpha
 *
 * Clock POLarity, Clock PHAse
 */
void spi_slave_v2(in port ss,in port scl,in port mosi,out port miso,unsigned char cpol,unsigned char cpha, client interface spi_slave_if_v2 spi_if)
{
  unsigned din,dout,bitmask;
  unsigned char ssv,sclv;
  unsigned char edge;
  ssv = 1;
  while(1)
  {
    ss when pinseq(0) :> ssv;
    scl :> sclv;
    dout = spi_if.onSS();
    dout = bitrev(dout) >> 24;

    edge = 0;   // next edge
    bitmask = 0x80;
    while(ssv == 0)
    {
      // write before next transition
      if (edge == cpha)
      {
        miso <: >>dout;
      }
      select
      {
        case ss when pinsneq(ssv) :> ssv:
          break;
        case scl when pinsneq(sclv) :> sclv:
          // read after transition
          if (edge == cpha)
          {
            mosi :> >>din;    //MSB to LSB
            bitmask >>=1;
            if (bitmask == 0)
            {
              dout = spi_if.onData(bitrev(din) & 0xFF);
              dout = bitrev(dout) >> 24;
              bitmask = 0x80;
            }
          }
          edge = edge ^ 1;
          break;
      }


    }
  }
}

[[distributable]] void spi_master(out port oport,unsigned char scl_mask,unsigned char mosi_mask,in port miso,server interface spi_master_if spi_if)
{
  //Set all signals high to deselected any slave, we do not care about clk, mosi or anything else
  oport <: 0xFF;
  while(1)
  {
    select
    {
      case spi_if.execute(struct spi_frm_v2* frm,unsigned char ss_mask,unsigned char cpol, unsigned char cpha,unsigned T):
        SPI_EXECUTE_v3(*frm,oport,scl_mask,mosi_mask,ss_mask,miso,cpol,cpha,T);  // wait before processed
        break;
    }
  }
}
/*
 * This is a spi device.
 * multiple devices con be link to one spi_master
 */
[[distributable]] void spi_dev(unsigned char ss_mask,unsigned char cpol, unsigned char cpha,unsigned T,server interface spi_device_if spi_dev,client interface spi_master_if spi_if)
{
  while(1)
  {
    select
    {
      case spi_dev.execute(struct spi_frm_v2* frm):
        spi_if.execute(frm,ss_mask,cpol,cpha,T);
        break;
    }
  }
}

