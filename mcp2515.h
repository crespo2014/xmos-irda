/*
 * mcp2515.h
 * library to talk to a mcp2515 canbus spi interface
 *
 *  Created on: 21 Sep 2015
 *      Author: lester.crespo
 */


#ifndef MCP2515_H_
#define MCP2515_H_

#include "spi_custom.h"
#include "rxtx.h"

#define BFP_CTRL    0x0C

#define RXF_0       0x00    // first filter
#define RXF_NEXT    0x04
#define RXF_COUNT   6
#define RXF_SIDH    0
#define RXF_SIDL    1
#define RXF_EID8    2
#define RXF_EID0    3

#define RXM_0     0x20
#define RXM_NEXT  0x04
#define RXM_COUNT 2
#define RXM_SIDH  0
#define RXM_SIDL  1
#define RXM_EID8  2
#define RXM_EID0  3

#define CNF1      0x24
#define CNF2      0x29
#define CNF3      0x28
#define TEC       0x1C
#define REC       0x1D
#define EFLG      0x2D
#define CAN_INTE  0x2B
#define CAN_INTF  0x2C
#define CAN_CTRL  0x0F
#define CAN_STAT  0x0E



#define RXB_0      0x30
#define RXB_COUNT  2
#define RXB_NEXT   0x10
#define RXB_CTRL       0
#define RXB_SIDH   1    //SID10 .. SID3  (RO)
#define RXB_SIDL   2    //SID2 .. SID0 SRR IDE X EID17 EID16
#define RXB_EID8   3    //EID15 .. EID8
#define RXB_EID0   4    // EID7 .. EID0
#define RXB_DLC    5
#define RXB_DATA   6
#define RXB_DATA_MAX 8
#define RXB_MAX_OFFSET  (RXB_DATA + RXB_DATA_MAX)

#define TXB_0         0x30  // first buffer
#define TXB_COUNT     3     // max 3 tx buffers
#define TXB_NEXT      0x10  // position of next buffer
#define TXB_CTRL      0     // offset
#define TXB_SIDH      1     // offset from SID10 .. SID3 R/W
#define TXB_SIDL      2     // SID2 SID1 SID0 X EXIDE x EID17 EID16
#define TXB_EID8      3     // EID15 .. EID8 R/W
#define TXB_EID0      4     // EID7 .. EID0
#define TXB_DLC       5     // X RTR X X DLC3 ..DLC0 DATA LENGTH CODE
#define TXB_DATA      6
#define TXB_DATA_MAX  8
#define TXB_MAX_OFFSET   (TXB_DATA + TXB_DATA_MAX)

#define TXB_CTRL_ABTF    (1<<6)
#define TXB_CTRL_MLOA    (1<<5)
#define TXB_CTRL_TXERR   (1<<4)
#define TXB_CTRL_TXREQ   (1<<3)
#define TXB_CTRL_TXP1    (1<<1)
#define TXB_CTRL_TXP0    (1<<0)

#define TX_RTSCTRL        0x0D    //TxnRts Pin control and status register
#define TX_RTSCTRL_B2RTS  (1<<5)  // Reads state of TX2RTS pin when in Digital Input mode
                                  // Reads as 0 when pin is in Request-to-Send mode
#define TX_RTSCTRL_B1RTS  (1<<4)  // Reads state of TX1RTS pin when in Digital Input mode
                                  // Reads as 0 when pin is in Request-to-Send mode
#define TX_RTSCTRL_B0RTS  (1<<3)  // Reads state of TX0RTS pin when in Digital Input mode
                                  // Reads as 0 when pin is in Request-to-Send mode
#define TX_RTSCTRL_B2RTSM (1<<2)  // 1 = Pin is used to request message transmission of TXB2 buffer (on falling edge)
                                  // 0 = Digital input
#define TX_RTSCTRL_B1RTSM (1<<1)  // 1 = Pin is used to request message transmission of TXB1 buffer (on falling edge)
                                  // 0 = Digital input
#define TX_RTSCTRL_B0RTSM (1<<0)  // 1 = Pin is used to request message transmission of TXB0 buffer (on falling edge)
                                  // 0 = Digital input

#define TXB_SIDL_EXIDE  (1<<3)    // 1 = Message will transmit extended identifier
                                  // 0 = Message will transmit standard identifier
#define TXB_DLC_LEN_MASK  0x0F    // how many bystes to send
#define TXB_DLC_RTR       (1<<6)  // 1 = Transmitted Message will be a Remote Transmit Request
                                  // 0 = Transmitted Message will be a Data Frame
/*
 RXM<1:0>: Receive Buffer Operating mode bits
  11 = Turn mask/filters off; receive any message
  10 = Receive only valid messages with extended identifiers that meet filter criteria
  01 = Receive only valid messages with standard identifiers that meet filter criteria. Extended ID filter
       registers RXFnEID8:RXFnEID0 are ignored for the messages with standard IDs.
  00 = Receive all valid messages using either standard or extended identifiers that meet filter criteria.
       Extended ID filter registers RXFnEID8:RXFnEID0 are applied to first two bytes of data in the messages with standard IDs.
 */
#define RXB_CTRL_RXM_SHIFT 5
#define RXB_CTRL_RXM_MASK  0x03
#define RXB_CTRL_RXM1      (1<<6)
#define RXB_CTRL_RXM0      (1<<5)
/*
 * RXRTR: Received Remote Transfer Request bit
 * 1 = Remote Transfer Request Received
 * 0 = No Remote Transfer Request Received
 */
#define RXB_CTRL_RXRTR    (1<<3)
/*
 * BUKT: Rollover Enable bit
 * 1 = RXB0 message will rollover and be written to RXB1 if RXB0 is full
 * 0 = Rollover disabled
 */
#define RXB_CTRL_BUKT    (1<<2)
#define RXB_CTRL_BUKT1   (1<<1)  //BUKT1: Read-only Copy of BUKT bit (used internally by the MCP2515)
/*
 * FILHIT0: Filter Hit bit  indicates which acceptance filter enabled reception of message
 * 1 = Acceptance Filter 1 (RXF1)
 * 0 = Acceptance Filter 0 (RXF0)
 * Note: If a rollover from RXB0 to RXB1 occurs, the FILHIT bit will reflect the filter that accepted the message that rolled over.
 */
#define RXB_CTRL_FILHIT0  (1<<0)

#define RXB1_CTRL_RXM1  (1<<6)
#define RXB1_CTRL_RXM0  (1<<5)
#define RXB1_CTRL_RXRTR (1<<3)
/*
 * FILHIT<2:0>: Filter Hit bits - indicates which acceptance filter enabled reception of message
 * 101 = Acceptance Filter 5 (RXF5)
 * 100 = Acceptance Filter 4 (RXF4)
 * 011 = Acceptance Filter 3 (RXF3)
 * 010 = Acceptance Filter 2 (RXF2)
 * 001 = Acceptance Filter 1 (RXF1) (Only if BUKT bit set in RXB0CTRL)
 * 000 = Acceptance Filter 0 (RXF0) (Only if BUKT bit set in RXB0CTRL)
 */
#define RXB1_CTRL_FILHIT_MASK 0x07
#define RXB1_CTRL_FILHIT2  (1<<2)
#define RXB1_CTRL_FILHIT1  (1<<1)
#define RXB1_CTRL_FILHIT0  (1<<0)

/*
 * B1BFS: RX1BF Pin State bit (Digital Output mode only)
 * Reads as 0 when RX1BF is configured as interrupt pin
 */
#define BFP_CTRL_B1BFS     (1<<5)
/*
 * B0BFS: RX0BF Pin State bit (Digital Output mode only)
 * Reads as 0 when RX0BF is configured as interrupt pin
 */
#define BFP_CTRL_B0BFS     (1<<4)
/*
 * B1BFE: RX1BF Pin Function Enable bit
 * 1 = Pin function enabled, operation mode determined by B1BFM bit
 * 0 = Pin function disabled, pin goes to high-impedance state
 */
#define BFP_CTRL_B1BFE     (1<<3)
/*
 * B0BFE: RX0BF Pin Function Enable bit
 * 1 = Pin function enabled, operation mode determined by B0BFM bit
 * 0 = Pin function disabled, pin goes to high-impedance state
 */
#define BFP_CTRL_B0BFE     (1<<2)
/*
 * B1BFM: RX1BF Pin Operation mode bit
 * 1 = Pin is used as interrupt when valid message loaded into RXB1
 * 0 = Digital Output mode
 */
#define BFP_CTRL_B1BFM     (1<<2)
/*
 * B0BFM: RX0BF Pin Operation mode bit
 * 1 = Pin is used as interrupt when valid message loaded into RXB0
 * 0 = Digital Output mode
 */
#define BFP_CTRL_B0BFM     (1<<2)
/*
 * SRR: Standard Frame Remote Transmit Request bit (valid only if IDE bit = 0)
 * 1 = Standard Frame Remote Transmit Request Received
 * 0 = Standard Data Frame Received
 */
#define RX_BUFF_SIDL_SRR   (1<<4)
/*
 * This bit indicates whether the received message was a Standard or an Extended Frame
 * 1 = Received message was an Extended Frame
 * 0 = Received message was a Standard Frame
 */
#define RX_BUFF_SIDL_IDE   (1<<3)

/*
 * RTR: Extended Frame Remote Transmission Request bit (valid only when RXBnSIDL.IDE = 1)
 * 1 = Extended Frame Remote Transmit Request Received
 * 0 = Extended Data Frame Received
 */
#define RXB_DLC_RTR        (1<<6)
#define RXB_DLC_LEN_MASK   0x0F

#define CAN_ONE_SHOT    (1 << 3)

#define MODE_NORMAL     (0 << 5)
#define MODE_SLEEP      (0x1 << 5)
#define MODE_LOOPBACK   (0x2 << 5)
#define MODE_LISTEN     (0x3 << 5)
#define MODE_CONFIGURE  (0x4 << 5)
#define MODE_MASK       (0x7 << 5)

#define SPI_RESET       0xC0
#define SPI_READ        0x03
#define SPI_RD_RXB      0x90
#define SPI_WRITE         0x02
#define SPI_LOAD_TXB      0x40    // bits 0-3 is the index
#define SPI_RTS           0x80
#define SPI_RD_STATUS     0xA0
#define SPI_RXB_STATUS    0xB0
#define SPI_BIT_UPDATE    0x05

/*
 * RXB index for SPI_RD_RXB command
 */
#define SPI_RD_RXB_SHIFT 0x1    // shift buffer idx
#define SPI_RD_RXB_MASK  0x3
#define SPI_RD_RXB_RXB0SIDH    0x0
#define SPI_RD_RXB_RXB0D0      0x1
#define SPI_RD_RXB_RXB1SIDH    0x2
#define SPI_RD_RXB_RXB1D0      0x3

/*
 * Interrupt flags
 */
#define MCP2515_INT_MERR  (1<<7)
#define MCP2515_INT_WAKI  (1<<6)
#define MCP2515_INT_ERRI  (1<<5)
#define MCP2515_INT_TX2I  (1<<4)
#define MCP2515_INT_TX1I  (1<<3)
#define MCP2515_INT_TX0I  (1<<2)
#define MCP2515_INT_RX1I  (1<<1)
#define MCP2515_INT_RX0I  (1<<0)

struct mcp2515_cnf_t
{
  unsigned char cpha,cpol;
  unsigned char can_ctrl,can_status,rxb_status;
  unsigned char rxb_ctrl[RXB_COUNT];
  unsigned char txb_ctrl[TXB_COUNT];

  unsigned char buff[5+TXB_DATA_MAX];      //sidh sidl eid8 eid0
  unsigned char cnf1,cnf2,cnf3,tec,rec,eflg;
};

/*
 * Interface between mcp2515 main task and mcp2515 interrupt task.
 */
interface mcp2515_int_if
{
    unsigned char ClearInt();
};

interface mcp2515_if
{
  void setMode(unsigned char mode);
  void Reset();
  unsigned char getStatus();
//  unsigned char getRXStatus();
//  unsigned char getControl();
//  unsigned char getInterruptEnable();
//  void setInterruptEnable(unsigned char flag);
//  unsigned char getInterruptFlag();
//  void rts();
};

[[distributable]] extern void mcp2515_master(unsigned char ss_mask,server interface mcp2515_if mcp2515,client interface spi_master_if spi,server interface mcp2515_int_if mcp2515_int);
[[distributable]] extern void mcp2515_interrupt_manager(client interface mcp2515_int_if mcp2515,server interface interrupt_if int_src);
#endif /* MCP2515_H_ */
