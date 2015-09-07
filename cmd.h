/*
 * cmd.h
 *
 *  Created on: 7 Sep 2015
 *      Author: lester
 */


#ifndef CMD_H_
#define CMD_H_

enum cmd_e
{
  none,
  echo,
  i2c_cmd,
  light,
};

extern unsafe enum cmd_e parseCommand(const unsigned char* c,unsigned char len,unsigned char& j);
extern unsigned get_i2c_buff(const unsigned char* c,struct i2c_frm &ret);
extern void get_i2c_resp(struct i2c_frm &data,struct tx_frame_t ret);

#endif /* CMD_H_ */
