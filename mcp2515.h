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
#include "spi_if.h"

// All registers

#define TX_RTSCTRL  0x0D    //TxnRts Pin control and status register
#define BFP_CTRL    0x0C

#define RXF_0       0x00    // RX filter registers
#define RXF_NEXT    0x04
#define RXF_COUNT   6

#define RXM_0     0x20      // RX mask
#define RXM_NEXT  0x04
#define RXM_COUNT 2

#define CNF1      0x24  //configuration
#define CNF2      0x29
#define CNF3      0x28
#define TEC       0x1C
#define REC       0x1D
#define EFLG      0x2D
#define CAN_INTE  0x2B  // interrupt enable
#define CAN_INTF  0x2C  // interrupt flag
#define CAN_CTRL  0x0F  // control reg
#define CAN_STAT  0x0E  // status

// rx buffers
#define RXB_0      0x60
#define RXB_COUNT  2
#define RXB_NEXT   0x10

// transmit buffer
#define TXB_0         0x30  // first buffer
#define TXB_COUNT     3     // max 3 tx buffers
#define TXB_NEXT      0x10  // position of next buffer


// all offsets
#define RXF_SIDH_OFFSET    0
#define RXF_SIDL_OFFSET    1
#define RXF_EID8_OFFSET    2
#define RXF_EID0_OFFSET    3

#define RXM_SIDH_OFFSET  0
#define RXM_SIDL_OFFSET  1
#define RXM_EID8_OFFSET  2
#define RXM_EID0_OFFSET  3

#define RXB_CTRL_OFFSET   0
#define RXB_SIDH_OFFSET   1    //SID10 .. SID3  (RO)
#define RXB_SIDL_OFFSET   2    //SID2 .. SID0 SRR IDE X EID17 EID16
#define RXB_EID8_OFFSET   3    //EID15 .. EID8
#define RXB_EID0_OFFSET   4    // EID7 .. EID0
#define RXB_DLC_OFFSET    5
#define RXB_DATA_OFFSET   6
#define RXB_DATA_MAX 8
#define RXB_MAX_OFFSET  (RXB_DATA + RXB_DATA_MAX)

#define TXB_CTRL_OFFSET      0     // offset
#define TXB_SIDH_OFFSET      1     // offset from SID10 .. SID3 R/W
#define TXB_SIDL_OFFSET      2     // SID2 SID1 SID0 X EXIDE x EID17 EID16
#define TXB_EID8_OFFSET      3     // EID15 .. EID8 R/W
#define TXB_EID0_OFFSET      4     // EID7 .. EID0
#define TXB_DLC_OFFSET       5     // X RTR X X DLC3 ..DLC0 DATA LENGTH CODE
#define TXB_DATA_OFFSET      6
#define TXB_DATA_MAX  8     // maximun data size
#define TXB_MAX_OFFSET   (TXB_DATA + TXB_DATA_MAX)

// all bits

//Interrupt enable bits
#define CAN_INT_MERRE   0x80
#define CAN_INT_WAKIE   0x40
#define CAN_INT_ERRIE   0x20
#define CAN_INT_TX2IE   0x10
#define CAN_INT_TX1IE   0x08
#define CAN_INT_TX0IE   0x04
#define CAN_INT_RX1IE   0x02
#define CAN_INT_RX0IE   0x01

//Interrupt flagged bits
#define CAN_INT_MERRF   0x80
#define CAN_INT_WAKIF   0x40
#define CAN_INT_ERRIF   0x20
#define CAN_INT_TX2IF   0x10
#define CAN_INT_TX1IF   0x08
#define CAN_INT_TX0IF   0x04
#define CAN_INT_RX1IF   0x02
#define CAN_INT_RX0IF   0x01

// flags
#define TXB_CTRL_ABTF    (1<<6)
#define TXB_CTRL_MLOA    (1<<5)
#define TXB_CTRL_TXERR   (1<<4)
#define TXB_CTRL_TXREQ   (1<<3)
#define TXB_CTRL_TXP1    (1<<1)
#define TXB_CTRL_TXP0    (1<<0)


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
#define TXB_SIDL_EXIDE_BIT  3
#define TXB_SIDL_EXIDE  (1 << TXB_SIDL_EXIDE_BIT)    // 1 = Message will transmit extended identifier
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

// SPI commands
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



/*
 * CAN STAT. iCOD contains the code of the highest priority interrupt
 * 0 - not interrupt
 * 1 ERR
 * 2 WAK
 *
 */
#define  MCP2515_ICOD_MASK  0x03
#define  MCP2515_ICOD_BIT   0x0

#define  MCP2515_ICOD_ERR   0x1
#define  MCP2515_ICOD_WAK   0x2
#define  MCP2515_ICOD_TX0   0x3
#define  MCP2515_ICOD_TX1   0x4
#define  MCP2515_ICOD_TX2   0x5
#define  MCP2515_ICOD_RX0   0x6
#define  MCP2515_ICOD_RX1   0x7

struct mcp2515_cnf_t
{
  unsigned T;
  unsigned char cpha,cpol;
  unsigned char ss_mask;
  unsigned char can_ctrl,can_status,rxb_status;
  unsigned char intflags;
//  unsigned char rxb_ctrl[RXB_COUNT];
//  unsigned char txb_ctrl[TXB_COUNT];
//
//  unsigned char buff[5+TXB_DATA_MAX];      //sidh sidl eid8 eid0
//  unsigned char cnf1,cnf2,cnf3,tec,rec,eflg;
};

/*
 * Interface between mcp2515 main task and mcp2515 interrupt task.
 */
interface mcp2515_if
{
  unsigned char getIntFlag();
  void setInterruptEnable(unsigned char ie);
  void ackInterrupt(unsigned char bitmask);     // update canintf to acknowledge the interrupt
  /*
   * required buffer len RXB_NEXT
   */
  void pullBuffer(unsigned char rx_idx,char *buff);
};

/*
 * create a tx buffer for the mcp2515 chip
 */
#define TO_MCP2515(__id,__data,__len,__out) \
  do { \
    *(__out + 0) = __id >> 3; \
    *(__out + 1) = (__id << 5) | (__id >> (28-1) && 0x03); \
    if (__id & CAN_EXID) *(__out + 1) |= TXB_SIDL_EXIDE; \
    *(__out + 2) = (__i >> (26-7)); \
    *(__out + 3) = (__i >> (18-7)); \
    *(__out + 4) = len & 0x07;    \
     if (__id & CAN_RTR) *(__out + 4) |= TXB_DLC_RTR; \
     for (int __i=0;__i<__len;__i++) { \
       *(__out + 5 + i) = *(__data +__i); \
     } \
  } while(0)

[[distributable]] extern void mcp2515_master(server interface mcp2515_if mcp2515[n],size_t n,unsigned char ss_mask,server interface tx_if tx,client interface spi_master_if spi);
[[distributable]] extern void mcp2515_interrupt_manager(client interface mcp2515_if mcp2515,server interface interrupt_if int_src,client interface rx_frame_if router);

interface mcp2515_spi_if
{
    void reset();
    unsigned char read(unsigned char address);
    unsigned char read_rx_buffer(unsigned char address);
    void write(unsigned char address, unsigned char value);
    void load_tx_buffer(unsigned char buffer, unsigned char data);
    void rts(unsigned char buffers);
    unsigned char read_status();
    unsigned char rx_status();
    void bit_modify(unsigned char address, unsigned char mask, unsigned char value);
};

/*
 * Return value will be the tx buffer used for this packet
 */
struct mcp215_msg {
    unsigned exid;    // if == 0 then id is used
    unsigned char data[14];
    unsigned char count;
    bool oneshoot;    // if packet fail to send do not resend.
    unsigned char txBuff; // out, tx buffer used for this frame
};

interface mcp2515_rx_if
{
    [[clears_notification]] void recv(struct mcp215_msg& msg);
    [[notification]] slave void onData();
};

interface mcp2515_tx_if
{
    [[clears_notification]]  void send(struct mcp215_msg& msg);
    [[notification]] slave void onCTS(); // clear to send
    void rts();       // request to send
};

interface mcp2515_admin_if
{
    void enableInterrupt(unsigned char bitmask);
    void reset();
    unsigned char readReg(address);
};

// interrupt interface
interface mcp2515_int_if
{
    [[notification]] slave void onInt();
    [[clears_notification]] void clear();
};

[[distributable]] extern void mcp2515_spi(server interface mcp2515_spi_if mcp2515, client interface spi_if spi);

[[distributable]] extern void mcp2515(
        server interface mcp2515_rx_if rx,
        server interface mcp2515_tx_if tx,
        server interface mcp2515_admin_if admin,
        client interface mcp2515_int_if interrupt,
        client interface mcp2515_spi_if spi);

#endif /* MCP2515_H_ */
