/*
 * cmd.h
 *
 *  Created on: 7 Sep 2015
 *      Author: lester
 */


#ifndef CMD_H_
#define CMD_H_

#include "i2c_custom.h"
/*
 * Commands definition
 */

#define cmd_none    0
#define cmd_i2cw    1
#define cmd_i2cr    2
#define cmd_i2cwr  3
#define cmd_irda_rx 4   // data comming from irda to command task
#define cmd_can_rx  5   // data comming from can
#define cmd_can_tx  6   // push data to can bus
#define cmd_spi0_tx     7   // write to spi slave 0
#define cmd_info     8 //request ssytem info, including commands id

extern unsigned  getCommand(const unsigned char* c,const unsigned char* &t);
extern unsigned get_i2c_buff(const unsigned char* c,struct i2c_frm &ret);
//extern void get_i2c_resp(struct i2c_frm &data,struct tx_frame_t ret);

[[distributable]] extern void cmd_v1(client interface rx_frame_if rx,server interface tx_if tx,client interface i2c_custom_if i2c);

#endif /* CMD_H_ */
