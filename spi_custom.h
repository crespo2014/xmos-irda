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

/*
 * write data, do not read
 * from msb to lsb
 */
static inline void SPI_SEND_U8(unsigned char u8,out port scl,out port mosi,unsigned T,timer t, unsigned& tp)
{
  unsigned v = bitrev((unsigned)u8) >> 24;
  for (int i=8;i;i--)
  {
    mosi <: >> v;
    t when timerafter(tp) :> void;
    scl <: 1;
    tp += (T/2);
    t when timerafter(tp) :> void;
    scl <: 0;
    tp += (T/2);
  }
}

static inline void SPI_SEND_RECV_U8(unsigned char u8,unsigned char &inu8,out port scl,out port mosi,in port miso,unsigned T,timer t, unsigned& tp)
{
  unsigned v = bitrev((unsigned)u8) >> 24;
  for (int i=8;i;i--)
  {
    mosi <: >> v;
    t when timerafter(tp) :> void;
    scl <: 1;
    miso :> >>inu8;
    tp += (T/2);
//    t when timerafter(tp) :> void;
//
//    tp += (T/4);
    t when timerafter(tp) :> void;
    scl <: 0;
    tp += (T/2);
  }
  //todo rotare inu8
}

/*
 * clock should be 0
 */
static inline void SPI_RECV_U8(unsigned char &inu8,out port scl,out port mosi,in port miso,unsigned T,timer t, unsigned& tp)
{
  mosi <: 1;  // dummy
  for (int i=8;i;i--)
  {
    t when timerafter(tp) :> void;
    scl <: 1;
    miso :> >>inu8;
    tp += (T/2);
    t when timerafter(tp) :> void;
    scl <: 0;
    tp += (T/2);
  }
  //todo rotare inu8
}

/*
 * write until rd_pos, rd and wr until wr_len, read until rd_len
 */
static inline void SPI_EXECUTE(struct spi_frm &frm,out port scl,out port mosi,in port miso,unsigned T,timer t, unsigned& tp)
{
  unsigned rdpos = frm.wr_len;
  unsigned wrpos = 0;
  t :> tp;
  while (wrpos < frm.wr_len && (frm.rd_len == 0 || wrpos < frm.rd_pos))
  {
    SPI_SEND_U8(frm.buff[wrpos],scl,mosi,T,t,tp);
    wrpos++;
  }
  while (wrpos < frm.wr_len)
  {
    SPI_SEND_RECV_U8(frm.buff[wrpos],frm.buff[rdpos],scl,mosi,miso,T,t,tp);
    wrpos++;
    rdpos++;
  }
  while (rdpos - frm.rd_pos < frm.rd_len)
  {
    SPI_RECV_U8(frm.buff[rdpos],scl,mosi,miso,T,t,tp);
    rdpos++;
  }
  t when timerafter(tp) :> void;
}

/*
 * clock shuold be 0 when this fucntion is called
 */
static inline void SPI_SEND_U8_v2(unsigned char u8,out port oport,unsigned char &opv,unsigned char scl_mask,unsigned char mosi_mask,unsigned T,timer t, unsigned& tp)
{
  unsigned mask =0x80;
  while (mask)
  {
    if (mask & u8)
      opv |= mosi_mask;
    else
      opv &= (~mosi_mask);
    oport <: opv;
    opv |= scl_mask;  // next
    t when timerafter(tp) :> void;
    oport <: opv;
    opv &= (~scl_mask);
    tp += (T/2);
    t when timerafter(tp) :> void;
    oport <: opv;
    tp += (T/2);
    mask >>= 1;
  }
}

static inline void SPI_SEND_RECV_U8_v2(unsigned char u8,unsigned char &inu8,out port oport,unsigned char &opv,unsigned char scl_mask,unsigned char mosi_mask,in port iport,unsigned char miso_mask,unsigned T,timer t, unsigned& tp)
{
  unsigned mask = 0x80;
  while(mask)
  {
    if (mask & u8)
      opv |= mosi_mask;
    else
      opv &= (~mosi_mask);
    oport <: opv;
    opv |= scl_mask;  // next
    t when timerafter(tp) :> void;
    oport <: opv;
    unsigned char v;
    iport :> v;
    inu8 <<= 1;           //MSB to LSB input
    if (v & miso_mask)
      inu8 |= 0x1;
    tp += (T/2);
    opv &= (~scl_mask);
    t when timerafter(tp) :> void;
    oport <: opv;
    tp += (T/2);
    mask>>=1;
  }
}

static inline void SPI_RECV_U8_v2(unsigned char &inu8,out port oport,unsigned char &opv,unsigned char scl_mask,unsigned char mosi_mask,in port iport,unsigned char miso_mask,unsigned T,timer t, unsigned& tp)
{
  opv |= mosi_mask;
  oport <: opv;
  unsigned mask = 0x80;
  while(mask)
  {
    opv |= scl_mask;  // next
    t when timerafter(tp) :> void;
    oport <: opv;
    unsigned char v;
    iport :> v;
    inu8 <<= 1;           //MSB to LSB input
    if (v & miso_mask)
      inu8 |= 0x1;
    tp += (T/2);
    opv &= (~scl_mask);
    t when timerafter(tp) :> void;
    oport <: opv;
    tp += (T/2);
    mask>>=1;
  }
}

static inline void SPI_EXECUTE_v2(struct spi_frm &frm,out port oport,unsigned char &opv,unsigned char scl_mask,unsigned char mosi_mask,unsigned char ss_mask,in port iport,unsigned char miso_mask,unsigned T,timer t, unsigned& tp)
{
  unsigned rdpos = frm.wr_len;
  unsigned wrpos = 0;
  opv &= (~ss_mask);
  oport <: opv;
  t :> tp;
  tp += T/2;
  while (wrpos < frm.wr_len && (frm.rd_len == 0 || wrpos < frm.rd_pos))
  {
    SPI_SEND_U8_v2(frm.buff[wrpos],oport,opv,scl_mask,mosi_mask,T,t,tp);
    wrpos++;
  }
  while (wrpos < frm.wr_len)
  {
    SPI_SEND_RECV_U8_v2(frm.buff[wrpos],frm.buff[rdpos],oport,opv,scl_mask,mosi_mask,iport,miso_mask,T,t,tp);
    wrpos++;
    rdpos++;
  }
  while (rdpos - frm.wr_len < frm.rd_len)
  {
    SPI_RECV_U8_v2(frm.buff[rdpos],oport,opv,scl_mask,mosi_mask,iport,miso_mask,T,t,tp);
    rdpos++;
  }
  t when timerafter(tp) :> void;
  opv |= ss_mask;
  oport <: opv;
}

/*
 * Wr and rd are done simultanealy
 */
static inline void SPI_EXECUTE_v3(struct spi_frm_v2 &frm,out port oport,unsigned char &opv,unsigned char scl_mask,unsigned char mosi_mask,unsigned char ss_mask,in port iport,unsigned char miso_mask,unsigned T,timer t)
{
  unsigned char *rdpos = frm.buff + frm.len;
  unsigned char *wrpos = frm.buff;
  unsigned len = frm.len;
  unsigned tp = 0;
  opv &= (~ss_mask);    // enable slave
  oport <: opv;
  t :> tp;
  tp += T/2;
  while(len--)
  {
    SPI_SEND_RECV_U8_v2(*wrpos,*rdpos,oport,opv,scl_mask,mosi_mask,iport,miso_mask,T,t,tp);
    wrpos++;
    rdpos++;
  }
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
  void execute(struct spi_frm_v2 *frm);
  //void setMode(unsigned char cpol,unsigned char cpha);
};

[[distributable]] extern void test_spi_slave_v2(server interface spi_slave_if_v2 spi_if);
[[distributable]] extern void test_spi_slave(server interface spi_slave_if spi_if);
[[distributable]] extern void spi_master(out port oport,unsigned char scl_mask,unsigned char mosi_mask,unsigned char ss_mask,in port iport,unsigned char miso_mask,unsigned T,server interface spi_master_if spi_if);

extern void spi_slave(in port ss,in port scl,in port mosi,out port miso,client interface spi_slave_if spi_if);
extern void spi_slave_v2(in port ss,in port scl,in port mosi,out port miso,client interface spi_slave_if_v2 spi_if);

#endif /* SPI_CUSTOM_H_ */
