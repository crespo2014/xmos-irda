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

enum cmd_e
{
  none,
  echo,
  light,
};

struct cmd_tbl_t {
  const unsigned char* unsafe str;
  enum cmd_e cmd;
};

unsafe enum cmd_e parseCommand(const unsigned char* c,unsigned char len,unsigned char& j)
{
  const static struct cmd_tbl_t cmd_tbl[] = {{"echo",echo},{"light",light}};
  unsigned char i;
  for (i =0;i < 2;++i)
  {
    j =0;
    while (j < len && cmd_tbl[i].str[j] == c[j])
    {
     ++j;
    }
    if (cmd_tbl[i].str[j] == 0 && c[j] == ' ')
      return cmd_tbl[i].cmd;
  }
  return none;
}

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


unsafe int  main5()
{
  enum cmd_e cmd;
  unsigned char j;    //arguments start here
  cmd = parseCommand("echo on",7,j);
  printf("%d\n",cmd);
  cmd = parseCommand("light on",7,j);
  printf("%d\n",cmd);
  return 0;
}

