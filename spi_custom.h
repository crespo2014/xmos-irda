/*
 * spi_custom.h
 * Custom spi implementation
 *
 * Do not mix input with output.
 * 4B - clock,mosi,ss1,ss2
 * 4B - miso  - share by all
 *
 * or
 *
 * 4B clock,ss1,ss2,ss3
 * 4B mosi1,mosi2,mosi3
 * 4B miso1,miso2,miso3
 *
 * 1B clock
 * 4x SS
 * 4x MOSI
 * 4x MISO  a synchronization is need.
 *
 * to allow multiple slave --> send slave signal clock up or down, slave will enable , write or read data base on status
 *
 * spi interface with mask to control ports. slave select mask, share miso value, share mosi value
 *
 * clock_up(ss_v,mois_v,miso_v)
 *
 * CPOL 0 - clock always 0
 *      1 - always 1
 * CPHA 0 at first edge of clock
 *      1 at second edge of clock
 *
 *  Created on: 18 Sep 2015
 *      Author: lester.crespo
 */


#ifndef SPI_CUSTOM_H_
#define SPI_CUSTOM_H_

#include <timer.h>
#include <xs1.h>
#include <xclib.h>

#define SPI1_SCK_BIT          0
#define SPI1_MCP2515_SS_BIT   1
#define SPI1_MOSI_BIT         2

#define SPI1_SCK_MASK        (1 << SPI1_SCK_BIT)
#define SPI1_MOSI_MASK       (1 << SPI1_MOSI_BIT)
#define SPI1_MCP2515_SS_MASK (1 << SPI1_MCP2515_SS_BIT)


struct spi_frm
{
    unsigned wr_len;  // how many data to write, and start position to store incoming data
    unsigned rd_pos;  // how many bytes before fecth data
    unsigned rd_len;
    unsigned char buff[32];
};

/*
 * Full duplex comunication for spi always.
 * Cons: waste read data when it is not needed
 */
struct spi_frm_v2
{
    unsigned len;             // how many bytes to wr/rd max 16
    unsigned wr_len;          // one reach this only zeroes will be push to mosi
    unsigned char buff[32];
};
/*
 * spi slave can fill up a buffer when a command is received
 * do not how to implement no value for miso
 * SS low required reset
 * any incomng byte required an outgoing byte
 *
 * slave -
 * buffer, rd_pos, wr_pos
 * wr_pos == 0; means command id.
 *    > 1. use command id to store or ignore data.
 *
 */

interface spi_slave_if_v2
{
  unsigned char onSS();                      // return next byte to send
  unsigned char onData(unsigned char din);   // return next byte to send
};


static inline void SPI1_SEND_RECV(unsigned char u8,unsigned char &inu8,out port oport,unsigned char opv,in port miso,unsigned char cpha,unsigned T,timer t, unsigned& tp)
{
  unsigned dout = 0x100 | (bitrev(u8) >> 24); // stop at 1
  unsigned edge = 0;
  while(dout ^ 1 || edge)  // leave the clock at edge 0
  {
    if (edge == cpha)   // is it the next edge to read
    {
      opv = (opv & (~SPI1_MOSI_MASK)) | (SPI1_MOSI_MASK * (dout & 1));
      oport <: opv;
      dout >>= 1;
      opv ^= SPI1_SCK_MASK;
      t when timerafter(tp) :> void;
      oport <: opv;
      miso :> >>inu8;   //MSB to LSB input
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
  inu8 = bitrev(inu8) >> 24;
  return;
}

/*
 * TODO.
 * removed conditional sentences.
 * start with a value that hold a 0 in output pins
 * clock ^ mask - invert clock value.
 * data >>= edge;   data is shifted only on specific edge
 * dout | (mask * (v &1))  the bit is enable if bit0 is 1
 * din <<= edge, din | (edge & v) edge zero disable the or
 *
 * Impossible
 * clk value
 * dt value
 * base | clk | value
 *
 */

/*
 * Wr and rd are done simultanealy
 */
static inline void SPI1_EXECUTE(struct spi_frm_v2 &frm,out port oport,unsigned char ss_mask,in port miso,unsigned char cpol, unsigned char cpha,unsigned T)
{
  unsigned tp = 0;
  unsigned opv =  ~(SPI1_SCK_MASK | SPI1_MOSI_MASK);
  timer t;
  opv = opv | (cpol * SPI1_SCK_MASK);    // set clock initial value
  oport <: opv; //set up clock
  t :> tp;
  tp += T/2;    // give some time before enabling the slave
  opv &= (~ss_mask);
  t when timerafter(tp) :> void;
  oport <: opv;   //slave on
  tp += T;
  unsigned pos = 0;
  while(pos < frm.len)
  {
    unsigned dout,din;
    if ( pos < frm.wr_len)
      dout = 0x100 | (bitrev(frm.buff[pos]) >> 24);
    else
      dout = 0;
    unsigned edge = 0;
    while(dout ^ 1 || edge)  // leave the clock at edge 0
    {
      if (edge == cpha)   // is it the next edge to read
      {
        opv = (opv & (~SPI1_MOSI_MASK)) | (SPI1_MOSI_MASK * (dout & 1));
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
    frm.buff[frm.wr_len + pos] = bitrev(din);
    pos++;
  }
  t when timerafter(tp) :> void;
  tp += T;
  t when timerafter(tp) :> void;
  opv |= ss_mask;
  oport <: opv;
  tp += T;
  t when timerafter(tp) :> void;
}

/*
 * Spi slave interface
 * Position is 0 for command id.
 * Data index is pos - cmd_len
 * cmd_len includes the cmd id it means it is always >= 1
 */
interface spi_slave_if
{
  unsigned char onCmd(unsigned char cmd_id,unsigned char &cmd_len);       // return first data if it is the case, set up command size.
  /*
   * cmd id is not a valid position
   * cmd data start at position 0
   */
  unsigned char onData(unsigned char din,unsigned pos);  // data and position ,return data to send, po
};

interface spi_master_if
{
  void execute(struct spi_frm_v2 *frm,unsigned char ss_mask,unsigned char cpol, unsigned char cpha,unsigned T);
  //void setMode(unsigned char cpol,unsigned char cpha);
};

interface spi_device_if
{
  void execute(struct spi_frm_v2 *frm);
};

[[distributable]] extern void test_spi_slave_v2(server interface spi_slave_if_v2 spi_if);
[[distributable]] extern void test_spi_slave(server interface spi_slave_if spi_if);
[[distributable]] extern void spi_master(out port oport,in port miso,server interface spi_master_if spi_if);
[[distributable]] extern void spi_dev(unsigned char ss_mask,unsigned char cpol, unsigned char cpha,unsigned T,server interface spi_device_if spi_dev,client interface spi_master_if spi_if);

extern void spi_slave(in port ss,in port scl,in port mosi,out port miso,client interface spi_slave_if spi_if);
extern void spi_slave_v2(in port ss,in port scl,in port mosi,out port miso,unsigned char cpol,unsigned char cpha,client interface spi_slave_if_v2 spi_if);
extern void spi_slave_v3(in port iport,unsigned char scl_mask,unsigned char mosi_mask,unsigned char ss_mask,out port miso,unsigned char cpol,unsigned char cpha, client interface spi_slave_if_v2 spi_if);

#endif /* SPI_CUSTOM_H_ */
