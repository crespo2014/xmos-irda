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
  if (isPreffix("I2CW",c,t) && *t == ' ') return i2cw_cmd;
  if (isPreffix("I2CR",c,t) && *t == ' ') return i2cr_cmd;
  if (isPreffix("I2CWR",c,t) && *t == ' ') return i2cwr_cmd;
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

/*
 * Buffers that hold data comming from serial channel.
 * It invoke command interface when a packet is recieved
 *
 * v2. integrate into rx, signal when a packet is ready to process
 * two buffers holder.
 *
 * v3. two implementation can be done
 *  - Rx task store data on buffer.
 *   when timeouts a notyfication is send and the buffer swap with other one
 *   cmd task will request the buffer.
 *   cons - event that return buffer to cmd can block the rx for a not acceptable amount of time
 *
 * v4. Buffer task reading from channel stream with timeout will store incoming bytes.
 *   when it timeouts the buffered is processed.
 *   channel can hold until 8 bytes, that gives enough time to execute the previous command.
 *
 * V4.1 create a router that hold all packets using linked list for each interface.
 *  easy to dispatch packets without blocking task.
 *
 *  v4.2 Rx gap between frames can be enough to allow send command to router.
 *
 */
enum cmd_st
{
  cmd_id,
  cmd_len,
  cmd_data,
  cmd_ascii,
};

[[combinable]] void SerialRX_Cmd(streaming chanend ch)
{
  struct rx_u8_buff  s_packet;    // static packet
  struct rx_u8_buff* movable packet = &s_packet;
  unsigned discarded;     // how many bytes throw away before a valid packet.
  unsigned char data;
  packet->len = 0;
  packet->overflow = 0;
  discarded = 0;
  while(1)
  {
    select {
      case ch :> data:
        if (packet->len < sizeof(packet->dt))
          packet->dt[packet->len++] = data;
        else
          packet->overflow++;
        break;
    }
  }
}

