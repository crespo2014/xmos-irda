/*
 * i2c.h
 *
 *  Created on: 26 Aug 2015
 *      Author: lester.crespo
 */


#ifndef I2C_H_
#define I2C_H_

#include <xclib.h>
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

/*
 * No delay after scl go down
 */
static inline void I2C_START(port scl, port sda,unsigned T,timer t,unsigned &tp)
{
  t when timerafter(tp) :> void;
  scl :> void; /* or set to 1 */
  tp += T/4; t when timerafter(tp) :> void;
  sda <: 0;
  tp += T/2; t when timerafter(tp) :> void;
  scl <: 0;
  tp += T/2;
}

inline void I2C_STOP(port scl,port sda,unsigned T,timer t,unsigned &tp)
{
  t when timerafter(tp) :> void;
  sda <: 0;
  tp += T/2; t when timerafter(tp) :> void;
  scl <: 1;
  tp += T; t when timerafter(tp) :> void;
  sda <: 0;
  tp += T/4;
}

/*
 * Generate a clock pulse
 */
inline void I2C_SEND_BIT(port scl,port sda,unsigned T,timer t,unsigned &tp)
{
  t when timerafter(tp) :> void;
  scl <: 1;
  tp += T/2; t when timerafter(tp) :> void;
  scl <: 0;
  tp += T/2;
}

/*
 * Raise the clock signal and confirm or timeout
 * Release the clock and wait until it become high, (Streching)
 * Read bit from clock at 3/4 part of the high pulse
 */
inline static enum i2c_ecode I2C_CLK_UP(port scl,unsigned T,timer t,unsigned &tp)
{
  enum i2c_ecode ret;
  t when timerafter(tp) :> void;
  scl <: 1;
  select {
  case scl when pinseq(1) :> void:
    tp += 3*T/4;
    t when timerafter(tp) :> tp;
    tp += T/4; /* next transition*/
    ret = i2c_ack;
    break;
  case t when timerafter(tp + 1.5*T) :> void:
    ret = i2c_timeout;
    break;
  }
  return ret;
}

/*
 * Put clock signal down
 */
inline void I2C_CLK_DOWN(port scl,unsigned T,timer t,unsigned &tp)
{
   t when timerafter(tp) :> void;
   scl <: 0;
   tp += T/2;
}

/*
 * Send byte
 * Clock signal should be low
 */
inline enum i2c_ecode I2C_SEND_U8(unsigned char u8,port scl,port sda,unsigned T,timer t,unsigned &tp)
{
  unsigned v = u8;
  v = bitrev(v) >> 24;
  for (int i = 8; i != 0; i--)
  {
     sda <: >> v;
     I2C_SEND_BIT(scl,sda,T,t,tp);
  }
  enum i2c_ecode ecode = I2C_CLK_UP(scl,T,t,tp);
  if (ecode == i2c_ack) sda :> ecode;
  I2C_CLK_DOWN(scl,T,t,tp);
  return ecode;
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

#endif /* I2C_H_ */
