/*
 * cmd.xc
 *
 *  Created on: 16 Aug 2015
 *      Author: lester
 *
 * Core task.
 * It handle all commands received, and execute the desire command
 
 TODO : Sharing a multibits port.
 a distributable task bringing 8 interfaces with set clear.
 holding current port value.
 */

#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>
#include "serial.h"
#include "i2c.h"
#include "utils.h"
#include "cmd.h"


struct cmd_tbl_t {
  const unsigned char* unsafe str;
  enum cmd_e cmd;
};

/*
 * Use a termination character to make not possible past the end of the string
 */
enum cmd_e getCommand(const unsigned char* c,const unsigned char* &t)
{
  if (isPreffix("I2C",c,t) && *t == ' ') return i2c_cmd;
  if (isPreffix("I2CW",c,t) && *t == ' ') return i2c_wcmd;
  if (isPreffix("I2CR",c,t) && *t == ' ') return i2c_rcmd;
  return none_cmd;
}

/*

void command(client interface buffer_v1_if   serial,
    client interface serial_rx_if rx,
    client interface serial_tx_v2_if tx,
    streaming chanend irda_rx,
    streaming chanend irda_tx)
{
  while(1)
  {
    select
    {

    }
  }
}
*/

