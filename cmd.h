/*
 * cmd.h
 *
 *  Created on: 7 Sep 2015
 *      Author: lester
 */


#ifndef CMD_H_
#define CMD_H_

#include "i2c_custom.h"

enum cmd_e
{
  none_cmd,
  i2cw_cmd,
  i2cr_cmd,
  i2cwr_cmd,
};

extern enum cmd_e getCommand(const unsigned char* c,const unsigned char* &t);
extern unsigned get_i2c_buff(const unsigned char* c,struct i2c_frm &ret);
extern void get_i2c_resp(struct i2c_frm &data,struct tx_frame_t ret);

#endif /* CMD_H_ */
