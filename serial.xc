/*
 * serial.xc
 *
 *  Created on: 31 Jul 2015
 *      Author: lester.crespo
 */

/*
 * TODO
 * define an RX serial port using buffered output if it is possible
 *
 * There is not way to send full byte using buffered output,
 * Data will be send bit by bit.
 * A base frecuency will be use then baud rate will be a factor of this frecuency
 *
 * 9600 bit size is 104us
 * 115200 bits (8.6805 us)
 *
 */

#define UART_BASE_BIT_LEN_ns  8680    //for 115200 use a 8bits divisor

