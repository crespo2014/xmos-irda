/*
 * i2c.h
 *
 *  Created on: 26 Aug 2015
 *      Author: lester.crespo
 */


#ifndef I2C_H_
#define I2C_H_

//#include "i2c.h"
/*
enum i2c_st_v2
{
  start,
  wrbit1,
  wrbit2,
  wrbit3,
  wrbit4,
  wrbit5,
  wrbit6,
  wrbit7,
  wrbit8,
  wrack,      // reading ack
  wr_ack_rd,  // safe to read
  start_2,
  wr2bit1,
  wr2bit2,
  wr2bit3,
  wr2bit4,
  wr2bit5,
  wr2bit6,
  wr2bit7,
  wr2bit8,
  wr2ack,     // prepare for read ack
  wr2_ack_rd,  // safe to read
  rdbit1,
  rdbit2,
  rdbit3,
  rdbit4,
  rdbit5,
  rdbit6,
  rdbit7,
  rdbit8,
  rdack,    //what is next
  rdack_done,
  stop,
  i2c_none,
};
*/
/*
 * Status.
 * idle - to start transmition set sda=0, st = addr, sub_st = clk_up, bitmask
 */
/*
enum i2c_st {
  idle,     // SDA = 1 SCL = 1
  wr1,      // written
  start2,
  wr2,    // written after a second start (dummy write)
  rd,     // reading
  stp,        //
};
*/

/*
 * I2c substatus
 * Reading and generating signals have identical states
 */
/*
enum i2c_sub_st
{
  scl_none,
  scl_up,       // clock is 1
  scl_down,     // clock just go down ,SCL is 0, but SDA is unknown
  scl_none2,
  read_send,        // ready to generate the signal
  read_done,    // it is different to clock down
  // ack sending
  ack_send,
  ack_done,

  to_read,    // up the clock
  reading,    // possible clock strech

  to_signal,
  signaling,
};
*/
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
  i2c_0 = 0,
  i2c_1 = 1,
  i2c_data_max,     // if valued more than this then it is an error
  i2c_success,
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
/*
struct i2c_chn_v2
{
    struct i2c_frm* movable pfrm;
    enum i2c_st_v2 st;
    enum i2c_sub_st sub_st;
    unsigned char dt;           // data currently sending
    unsigned char bit_mask;     // for rd/rw byte
    unsigned char byte_count;   // how many bytes left to write or read
    unsigned short baud;        // to support different rates on bus.
    unsigned short baud_count;    //set to baud, when reach zero the channel is update
    unsigned char sda_mask;
    unsigned char scl_mask;
};
struct i2c_chn
{
    struct i2c_frm frm;
    struct i2c_frm* movable pfrm;
    enum i2c_st st;
    enum i2c_sub_st sub_st;
    unsigned char dt;         // data currently sending
    unsigned char bit_mask;   // for rd/rw byte
    unsigned char byte_count;   // how many bytes left to write or read
    unsigned short baud;    // to support different rates on bus.
    unsigned short baud_count;    //set to baud, when reach zero the channel is update
    unsigned char sda_mask;
    unsigned char scl_mask;
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
