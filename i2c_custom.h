/*
 * i2c.h
 *
 *  Created on: 26 Aug 2015
 *      Author: lester.crespo
 */


#ifndef I2C_H_
#define I2C_H_


/*
#define I2C_SDA1  1
#define I2C_SCL1  2
#define I2C_SDA2  4
#define I2C_SCL2  8
#define I2C_MASK1 3
#define I2C_MASK2 12
*/

/*
 * main state (idle, start,addr,data_wr, data_ack, data_rd, stop)
 * substates (transition, update/prepare, send(clk) )
 *
 * how many data to read/write
 * each byte requered a ack.
 * each frame required read or write count bytes
 *
 * push a i2c frame will return data in the same frame
 * cmd interfaz only send i2c one by one, but it need to be asynchronious
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

/*
 * No delay after scl go down
 */
#define I2C_START(scl,sda,T,t,tp) \
do { \
  t when timerafter(tp) :> void; \
  scl :> void; /* or set to 1 */ \
  tp += T/4; t when timerafter(tp) :> void; \
  sda <: 0; \
  tp += T/2; t when timerafter(tp) :> void; \
  scl <: 0; \
  } while(0)

#define I2C_STOP(scl,sda,T,t,tp) \
do { \
  t when timerafter(tp) :> void; \
  sda <: 0; \
  tp += T/2; t when timerafter(tp) :> void; \
  scl <: 1; \
  tp += T; t when timerafter(tp) :> void; \
  sda <: 0; \
  tp += T/4; t when timerafter(tp) :> void; \
  } while(0)

/*
 * Generate a clock pulse
 */
#define I2C_SEND_BIT(scl,sda,T,t,tp) \
do {  \
  t when timerafter(tp) :> void; \
  scl <: 1; \
  tp += T/2; t when timerafter(tp) :> void; \
  scl <: 0; \
  tp += T/2; \
} while(0)

/*
 * Raise the clock signal and confirm or timeout
 * Release the clock and wait until it become high, (Streching)
 * Read bit from clock at 3/4 part of the high pulse
 */
#define I2C_CLK_UP(scl,T,t,tp,ecode) \
  do { \
    t when timerafter(tp) :> void; \
    scl <: 1; \
    select { \
    case scl when pinseq(1) :> void: \
      ecode = i2c_ack; \
      tp += 3*T/4; t when timerafter(tp) :> tp; \
      break; \
    case t when timerafter(tp + 1.5*T) :> void: \
      ecode = i2c_timeout; \
      break; \
    } \
    tp += T/4; /* next transition*/ \
  } while(0)

/*
 * Put clock signal down
 */
#define I2C_CLK_DOWN(scl,T,t,tp) \
  do { \
     t when timerafter(tp) :> void; \
     scl <: 0; tp += T/2; \
  } while(0)

/*
 * Send byte
 * Clock signal should be low
 */
#define I2C_SEND_U8(u8,scl,sda,T,t,tp,ecode) \
  do { \
    unsigned data = ((unsigned) bitrev(u8)) >> 24; \
    for (int i = 8; i != 0; i--) { \
         sda <: >> data; \
         I2C_SEND_BIT(scl,sda,T,t,tp); } \
    I2C_CLK_UP(scl,T,t,tp,ecode); \
    if (ecode == i2c_ack) sda :> ecode; \
    I2C_CLK_DOWN(scl,T,t,tp); \
  } while(0)

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

 [[distributable]] extern void i2c_custom(server interface i2c_custom_if i2c_if[n],size_t n,port scl, port sda, unsigned kbits_per_second);

#endif /* I2C_H_ */
