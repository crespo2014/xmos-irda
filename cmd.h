/*
 * cmd.h
 *
 *  Created on: 7 Sep 2015
 *      Author: lester
 */


#ifndef CMD_H_
#define CMD_H_

/*
 * Commands definition for binary packets send to cmd interface
 * it is not the same than rx tx interfaces
 * intefaces work with raw data
 */
#define cmd_none    0
#define cmd_i2cw    1
#define cmd_i2cr    2
#define cmd_i2cwr   3
#define cmd_irda_rx 4   // data comming from irda to command task
#define cmd_can_rx  5   // data comming from can
#define cmd_can_tx  6   // push data to can bus
#define cmd_spi0_tx     7   // write to spi slave 0
#define cmd_info     8 //request ssytem info, including commands id
#define cmd_i2c_nack      12    // use by i2c reply if the operation was not success

[[distributable]] extern void cmd_v1(client interface rx_frame_if rx,server interface tx_if tx);

#endif /* CMD_H_ */
