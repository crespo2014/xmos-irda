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

void spi_slave_v3(in port iport,unsigned char scl_mask,unsigned char mosi_mask,unsigned char ss_mask,out port miso,unsigned char cpol,unsigned char cpha, client interface spi_slave_if_v2 spi_if)
{
  unsigned din,dout,bitmask;
  unsigned char edge;
  unsigned ipv;         // input port value previous
  unsigned ipv_l=0xFF;        //
  while(1)
  {
    // wait for ss
    do
    {
      ipv = ipv_l;
      iport when pinsneq(ipv):> ipv_l;
    } while ((ipv_l & ss_mask) != 0);
    edge = 0;   // next edge
    bitmask = 0x80;
    din = 0;
    dout = spi_if.onSS();
    dout = bitrev(dout) >> 24;
    for(;;)
    {
      if (edge == cpha)
      {
        miso <: >>dout;
      }
      // wait for clock or ss
      do
      {
        ipv = ipv_l;
        iport when pinsneq(ipv):> ipv_l;
      } while (((ipv_l ^ ipv) & (scl_mask | ss_mask))  == 0);
      // check ss still low
      if ((ipv_l & ss_mask) != 0) break;
      if (edge == cpha)
      {
        if (ipv_l & mosi_mask)
          din = din | bitmask;
        bitmask >>=1;
        if (bitmask == 0)
        {
          dout = spi_if.onData(din);
          dout = bitrev(dout) >> 24;
          bitmask = 0x80;
          din = 0;
        }
      }
      edge = edge ^ 1;
    }
    // on disconnect
  }
}
/*
 * TODO.
 * put ss_mask , cpol and so into an struture and send as const reference
 */
[[distributable]] void spi_master(out port oport,in port miso,server interface spi_master_if spi_if)
{
  //Set all signals high to deselected any slave, we do not set clk
  oport <: (unsigned char)(~(SPI1_SCK_MASK | SPI1_MOSI_MASK));
  while(1)
  {
    select
    {
      case spi_if.execute(struct spi_frm_v2* frm,unsigned char ss_mask,unsigned char cpol, unsigned char cpha,unsigned T):
        unsigned dout,din,edge;
        unsigned pos = 0;
        unsigned tp;
        unsigned opv = (~SPI1_SCK_MASK) | (cpol << SPI1_SCK_BIT); // set to 0xFF except for sclk
        timer t;
        oport <: opv;
        opv &= (~ss_mask);  // enable slave
        oport <: opv;
        t :> tp;
        tp += T/2;
        while(pos < frm->len)
        {
          dout = 0x100;   // repeat 8 times
          if (pos < frm->wr_len)
            dout |= (bitrev(frm->buff[pos]) >> 24);
          edge = 0;
          while(dout ^ 1 || edge)  // leave the clock at edge 0
          {
            if (edge == cpha)   // is it the next edge to read
            {
              opv = (opv & (~SPI1_MOSI_MASK)) | ( (dout & 1) << SPI1_MOSI_BIT);
              oport <: opv;
              dout >>= 1;
              opv ^= SPI1_SCK_MASK;
              t when timerafter(tp) :> void;
              oport <: opv;
              miso :> >>din;   //MSB to LSB input
              tp += T/2;
            } else
            {
              opv ^= SPI1_SCK_MASK;
              t when timerafter(tp) :> void;
              oport <:opv;
              tp += T/2;
            }
            edge = edge ^ 1;
          }
          frm->buff[frm->wr_len + pos] = bitrev(din);
          pos++;

//          SPI1_SEND_RECV(len < frm->wr_len ? frm->buff[len] : 0,*(frm->buff+frm->wr_len+len),oport,opv,miso,cpha,T,t,tp);
//          len++;
        }
        t when timerafter(tp) :> void;
        opv |= ss_mask;
        oport <: opv;   // disable slave at the next clock
        tp += T/2;
        t when timerafter(tp) :> void;
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

