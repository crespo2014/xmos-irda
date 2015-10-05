/*
 * i2c.h
 *
 *  Created on: 26 Aug 2015
 *      Author: lester.crespo
 */


#ifndef I2C_H_
#define I2C_H_

#define TEST1 1

#include <xclib.h>
#include "cmd.h"

/*
 * i2c User protocol
 * address u8  - device address
 * wr_len  u8  - how many bytes to write
 * rd_len  u8  - how many bytes to read
 * data        - data to write
 * rddata      - read data
 * Reply.
 * I2C :
 */


/*
 * Returned error codes for i2c command execution
 */
enum i2c_ecode
{
  i2c_ack = 0,
  i2c_nack = 1,
  i2c_data_max,     // if valued more than this then it is an error
  i2c_overflow,
  i2c_timeout,
  i2c_error,
};

struct i2c_frm
{
    unsigned addr;    //device address
    unsigned wr_len;   // how many bytes of data to write at first
    unsigned rd_len;   // how many bytes to read
    enum i2c_ecode ret_code;
    unsigned char  pos;     // w/r pos
    unsigned char  dt[20];  // read or written data

};

struct i2c_master_t
{
    port sda;
    port scl;
    unsigned T;
    timer t;
    unsigned tp;
};

static inline void i2c_init(struct i2c_master_t &obj)
{
  set_port_drive_low(obj.scl);
  set_port_drive_low(obj.sda);
   //  set_port_pull_up(scl);
   //  set_port_pull_up(sda);
  obj.sda :> int _;
  obj.scl :> int _;
}

static inline void i2c_send_start(struct i2c_master_t &obj)
{
  obj.sda <: 0;
  obj.t :> obj.tp;
  obj.tp += (obj.T/2);
  obj.t when timerafter(obj.tp) :> void;
  obj.scl <: 0;
  obj.tp += (obj.T/2);
}

static inline void i2c_send_stop(struct i2c_master_t &obj)
{
  obj.sda <: 0;
  obj.t when timerafter(obj.tp) :> void;
  obj.scl :> int _;
  obj.tp += (obj.T/2);
  obj.t when timerafter(obj.tp) :> void;
  obj.sda :> int _;
  obj.tp += (obj.T/2);
  obj.t when timerafter(obj.tp) :> void;
}

/*
 * Generate a clock pulse, use to send a bit of data
 */
static inline void i2c_send_bit(struct i2c_master_t &obj)
{
  // clk_up can be use to allow streching at this level.
  obj.t when timerafter(obj.tp) :> void;
  obj.scl :> int _;
  obj.tp += (obj.T/2);
  obj.t when timerafter(obj.tp) :> void;
  obj.scl <: 0;   // sda could be 1 after this.
  obj.tp += (obj.T/2);
}

/*
 * Raise clock signal allowing streching
 */
static inline unsigned i2c_scl_up(struct i2c_master_t &obj)
{
  unsigned ret;
  obj.t when timerafter(obj.tp) :> void;
  obj.scl :> ret;  // port go to float state
  // wait for signal become high
  for (int i = 8;i != 0;i--)
  {
    obj.scl :> ret;
    if (ret == 1)
    {
      obj.tp += (obj.T/4);    // signal is high, a bit can be read at 1/4 of T
      break;
    }
    obj.tp += (obj.T/2);
    obj.t when timerafter(obj.tp) :> obj.tp;
  }
  return ret;
}

/*
 * return 0, 1 or timeout
 * leave scl down at function exit
 */
static inline unsigned char i2c_read_bit(struct i2c_master_t &obj)
{
  unsigned ecode = i2c_scl_up(obj);
  if (ecode == 1)
  {
    obj.t when timerafter(obj.tp) :> void;
    obj.sda :> ecode;
    obj.tp += obj.T/4;
    obj.t when timerafter(obj.tp) :> void;
  }
  else
    ecode = i2c_timeout;
  obj.scl <: 0;             // keep it down if something goes wrong
  obj.tp += obj.T/2;
  return ecode;
}
/*
 * Send from MSB to LSB
 * Return 0,1 or timeout reading slave answer
 */
static inline enum i2c_ecode i2c_send_u8(struct i2c_master_t &obj,unsigned u8)
{
  u8 = 0x100 | (bitrev(u8) >> 24);
  while (u8 != 0x1)
  {
    obj.sda <: >>u8;
    i2c_send_bit(obj);
  }
  obj.sda :> int _; // prepared for reading
  return i2c_read_bit(obj);
}
/*
 * I2c write command
 * return 0, 1 or timeout
 */
static inline unsigned i2c_write(struct i2c_master_t &obj,unsigned addr,const unsigned char data[len],unsigned len)
{
  unsigned ret;
  i2c_send_start(obj);
  ret = i2c_send_u8(obj,addr << 1);
  for (unsigned i =0;ret==i2c_ack && i<len;i++)
  {
    ret = i2c_send_u8(obj,data[i]);
  }
  return ret;
}
/*
 * I2C read command.
 * read from msb to lsb
 * return 0,1 or timeout
 */
static inline unsigned i2c_read(struct i2c_master_t &obj,unsigned addr,unsigned char dt[len],unsigned len)
{
  unsigned ret;
  i2c_send_start(obj);
  ret = i2c_send_u8(obj,(addr << 1) | 1);
  for (unsigned i =0;ret==i2c_ack && i<len;i++)
  {
    // read 8 bits and send ack
    unsigned data;
    obj.sda :> int _; // prepared for reading
    for (unsigned j=0;ret == i2c_ack && j<8;j++)
    {
       ret = i2c_scl_up(obj);
       obj.t when timerafter(obj.tp) :> void;
       obj.sda :> >> data;
       obj.tp += (obj.T/4);
       obj.t when timerafter(obj.tp) :> void;
       obj.scl <: 0;
       obj.tp += (obj.T/2);
    }
    if (i == len-1) // last byte to read
      obj.sda <: i2c_nack;
    else
      obj.sda <: i2c_ack;
    i2c_send_bit(obj);
    dt[i] = bitrev(data) & 0xFF;
  }
  return ret;
}
/*
 * Execute the specific i2c command
 * u8 address
 * u8 wr_len
 * u8 rd_len
 *    data to write
 * +wr_len read data
 *
 */
static inline unsigned i2c_execute(struct i2c_master_t &obj,struct rx_u8_buff  &frame)
{
  unsigned ret;
  i2c_send_start(obj);
  unsigned addr = frame.dt[frame.header_len];
  unsigned len = frame.dt[frame.header_len+1];
  ret = i2c_write(obj,addr,frame.dt + frame.header_len + 3,len);
  len = frame.dt[frame.header_len+2];
  if (ret == i2c_ack)
      ret = i2c_read(obj,addr,frame.dt,len);
  if (ret == i2c_ack)
  {
    // signal returned data
    frame.header_len = 0;
    frame.len = len;
  }
  else
  {
    frame.cmd_id = cmd_i2c_nack;
    frame.header_len = frame.len;
  }
  i2c_send_stop(obj);
  return ret;
}


/*
 * No delay after scl go down
 */
static inline void I2C_START(port scl, port sda,unsigned T,timer t,unsigned &tp)
{
  sda <: 0;
  t :> tp;
  tp += T/2;
  t when timerafter(tp) :> void;
  scl <: 0;
  tp += T/2;
}

/*
 * do not call this function with the scl line up
 */
static inline void I2C_STOP(port scl,port sda,unsigned T,timer t,unsigned &tp)
{
  sda <: 0; // at this point scl is 0 it is legal
  t when timerafter(tp) :> void;
  scl :> int _;
  tp += T/2;
  t when timerafter(tp) :> void;
  sda :> int _;
  tp += T/2;
  t when timerafter(tp) :> void;
}

/*
 * Generate a clock pulse
 */
static inline void I2C_SEND_BIT(port scl,unsigned T,timer t,unsigned &tp)
{
  // clk_up can be use to allow streching at this level.
  t when timerafter(tp) :> void;
  scl :> int _;
  tp += (T/2);
  t when timerafter(tp) :> void;
  scl <: 0;   // sda could be 1 after this.
  tp += (T/2);
}

/*
 * Raise the clock signal and confirm or timeout
 * Release the clock and wait until it become high, (Streching)
 * Read bit from clock at 3/4 part of the high pulse
 */
static inline enum i2c_ecode I2C_CLK_UP(port scl,unsigned T,timer t,unsigned &tp)
{
  unsigned char ret;
  t when timerafter(tp) :> void;
  scl :> ret;  // port go to float state
  // wait for signal become high
  for (int i = 8;i != 0;i--)
  {
    scl :> ret;
    if (ret == 1)
    {
      tp += (T/4);
      break;
    }
    tp += (T/2);
    t when timerafter(tp) :> tp;
  }
  return (ret == 1) ? i2c_ack : i2c_timeout;
}

/*
 * sda should be 1 and ready for read before call this function
 * clock is put back to 0
 */
static inline unsigned char I2C_READ_BIT(port scl,port sda,unsigned T,timer t,unsigned &tp)
{
  enum i2c_ecode ecode = I2C_CLK_UP(scl,T,t,tp);
  if (ecode == i2c_ack)
  {
    t when timerafter(tp) :> void;
    sda :> ecode;
    tp += T/4;
    t when timerafter(tp) :> void;
    scl <: 0;
    tp += T/2;
  }
  scl <: 0;   // keep it down if something goes wrong
  return ecode;
}

/*
 * Send byte
 * Clock signal should be low
 */
static inline enum i2c_ecode I2C_SEND_U8(unsigned char u8,port scl,port sda,unsigned T,timer t,unsigned &tp)
{
  unsigned char mask=0x80;
  while (mask)
  {
    if (mask & u8)
      sda <: 1;
    else
      sda <: 0;
     I2C_SEND_BIT(scl,T,t,tp);
     mask >>=1;
  }
  sda :> int _; // prepared for reading
  return I2C_READ_BIT(scl,sda,T,t,tp);
}

/*
 * DeviceID or address is left shifted and ored with (0 write , 1 read)
 */
static inline enum i2c_ecode I2C_WRITE_BUFF(unsigned char addr,const unsigned char* pdata,unsigned len,port scl,port sda,unsigned T,timer t, unsigned &tp)
{
  I2C_START(scl,sda,T,t,tp);
  enum i2c_ecode ecode = I2C_SEND_U8(addr << 1,scl,sda,T,t,tp);
  while (len && ecode == i2c_ack)
  {
    ecode = I2C_SEND_U8(*pdata,scl,sda,T,t,tp);
    pdata++;
    len--;
  }
  return ecode;
}

/*
 * Send device address and start reading
 */
static inline enum i2c_ecode I2C_READ_BUFF(unsigned char addr,unsigned char* pdata,unsigned len,port scl,port sda,unsigned T,timer t, unsigned &tp)
{
  I2C_START(scl,sda,T,t,tp);
  enum i2c_ecode ecode = I2C_SEND_U8((addr << 1) | 1 ,scl,sda,T,t,tp);
  if (ecode != i2c_ack) return ecode;
  while (len)
  {
    int i;
    unsigned data;
    data = 0;
    sda :> int _; // prepared for reading
    for (i=8;i;--i)
    {
      ecode = I2C_READ_BIT(scl,sda,T,t,tp);
      if (ecode > 1) return ecode;    // neither ack or nack
      data = (data << 1) | ecode;
    }
    *pdata = data;
    pdata++;
    len--;
    if (len)
    {
      sda <: 0;   //ack need more bytes
    }
    else
      sda <: 1;   // no more bytes
    I2C_SEND_BIT(scl,T,t,tp);
  }
  return i2c_ack;
}

/*
 * Packet to build from commands
 * I2CW and I2CR
 */
/*
struct i2c_packet_v2
{
    unsigned char addr;
    unsigned char wr;      //true for write command
    unsigned char addr16;  // true for 16bits address
    unsigned char ack;    // true if operation was success
    unsigned cmd;
    unsigned value;
};
*/

interface i2c_custom_if
{
    void i2c_execute(struct i2c_frm &data);
};

extern unsigned i2cwr_decode(const unsigned char* c,struct i2c_frm &ret);
extern unsigned i2cr_decode(const unsigned char* c,struct i2c_frm &ret);
extern unsigned i2cw_decode(const unsigned char* c,struct i2c_frm &ret,char stop_char);
extern void i2c_decode_answer(struct i2c_frm &data,struct rx_u8_buff &ret);

 [[distributable]] extern void i2c_custom(server interface i2c_custom_if i2c_if[n],size_t n,port scl, port sda, unsigned kbits_per_second);
 [[distributable]] extern void i2c_master_v2(struct i2c_master_t &obj,server interface tx_if tx);
#endif /* I2C_H_ */
