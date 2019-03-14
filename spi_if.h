/*
 * spi_if.h
 *
 *  Created on: Mar 14, 2019
 *      Author: lester
 */

#ifndef SPI_IF_H_
#define SPI_IF_H_


//SPI interfaces

/*
 * 4 bits port for output
 * 1 bit port for input
 * 1 clock for timed operations
 *
 * 2T wait at the end of the transmition
 */

interface spi_4b_1b
{
    void setFreq(unsigned khz);
    void wr(unsigned char value);
    char wr_rd(unsigned char value);
    unsigned char rd();
    // enable the device, use to invoque bulk operations
    void start();
    void end();
};

[[distributable]] extern void spi_4b(server interface spi_4b_1b spi_if, out port p4b, in port mosi);

#endif /* SPI_IF_H_ */
