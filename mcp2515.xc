/*
 * mcp2515.xc
 * Interface for mcp2515 canbus controller
 *
 *  Created on: 27 Sep 2015
 *      Author: lester
 */

#include "stdio.h"
#include "mcp2515.h"
#include "spi_custom.h"
#include "utils.h"
#include "rxtx.h"

#define WRITE_BUFF(__addres,__buff,__len,__spi,__obj) \
  do { \
    struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_WRITE; __frm.buff[1] = __addres; \
    for (int i =0;i< __len;i++) { \
      __frm.buff[i+2] = __buff[i]; } \
      __frm.len = __len+2; __frm.wr_len = __len+2;  \
    __spi.execute(&__frm,__obj.ss_mask,__obj.cpol,__obj.cpha,__obj.T); \
  } while(0) ;

#define WRITE(__addres,__value,__spi,__obj) \
  do { \
    struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_WRITE; __frm.buff[1] = __addres; __frm.buff[2] = __value; __frm.len = 3; __frm.wr_len = 3;  \
    __spi.execute(&__frm,__obj.ss_mask,__obj.cpol,__obj.cpha,__obj.T); \
  } while(0) ;

/*
 * Read a register and save to __out
 */
#define READ(__addres,__spi,__obj,__out) \
  do { \
    struct spi_frm_v2 __frm; \
   __frm.buff[0] = SPI_READ; __frm.buff[1] = __addres; __frm.len = 3; __frm.wr_len = 2; \
   __spi.execute(&__frm,__obj.ss_mask,__obj.cpol,__obj.cpha,__obj.T); \
   __out = __frm.buff[__frm.wr_len*2]; \
  } while(0) ;

#define READ_CAN_STATUS(__frm,__spi,__obj,__out) \
  do { \
     struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_RD_STATUS; __frm.len = 2; __frm.wr_len = 1; \
    __spi.execute(&__frm,__obj.ss_mask,__obj.cpol,__obj.cpha,__obj.T); \
    __out = __frm.buff[__frm.wr_len*2]; \
  } while(0) ;

#define RESET(__spi,__obj) \
  do { \
    struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_RESET; __frm.len = 1; __frm.wr_len = 1; \
    __spi.execute(&__frm,__obj.ss_mask,__obj.cpol,__obj.cpha,__obj.T); \
  } while(0) ;

#define RTS(__mask,__spi,__obj) \
  do { \
    struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_RTS | (__mask & 0x03); __frm.len = 1; __frm.wr_len = 1; \
   __spi.execute(&__frm,__obj.ss_mask,__obj.cpol,__obj.cpha,__obj.T); \
  } while(0) ;

#define BIT_MODIFY(__addres,__mask,__value,__spi,__obj) \
  do { \
    struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_BIT_UPDATE; __frm.buff[1] = __addres;__frm.buff[2] = __mask;__frm.buff[3] = __value;__frm.len = 4; __frm.wr_len = 4; \
    __spi.execute(&__frm,__obj.ss_mask,__obj.cpol,__obj.cpha,__obj.T); \
  } while(0) ;

/*
 * aceepted id 0 for rx0 and 2 for rx1
 */
#define RD_RXB(__idx,__buff,__spi,__obj)  \
do { \
  struct spi_frm_v2 __frm; \
  __frm.buff[0] = SPI_RD_RXB | ((__idx & SPI_RD_RXB_MASK) << SPI_RD_RXB_SHIFT); __frm.len = RXB_NEXT; __frm.wr_len = 1; \
  __spi.execute(&__frm,__obj.ss_mask,__obj.cpol,__obj.cpha,__obj.T); \
} while(0) ;

static inline void MCP2515_READ_RXB_STATUS(struct spi_frm_v2 &frm)
{
  frm.buff[0] = SPI_RXB_STATUS;
  frm.len = 2;
  frm.wr_len = 1;
}

/*
* Read the rx buffer
*/
static inline void MCP2515_READ_RXB(unsigned char index,struct spi_frm &frm)
{
  frm.buff[0] = SPI_RD_RXB | ((index & 0x03) << SPI_RD_RXB_SHIFT);
  frm.wr_len = 2;
  frm.wr_len = 1;
}

/*
 * Add ss mask as input parameter
 * Talk to spi master,
 */
[[distributable]] void mcp2515_master(unsigned char ss_mask,server interface mcp2515_if mcp2515,client interface spi_master_if spi,server interface mcp2515_int_if mcp2515_int)
{
  struct mcp2515_cnf_t obj;
  //RESET(frm,spi);
  obj.cpha = 0;
  obj.cpol = 0;
  obj.T = 1*us;
  obj.ss_mask = ss_mask;
  READ(CAN_CTRL,spi,obj,obj.can_ctrl);
  //check for operation mode
  if ((obj.can_ctrl & MODE_MASK) != MODE_CONFIGURE)
    printf("x%02X mcp2515 missing\n",obj.can_ctrl);

  READ(CAN_CTRL,spi,obj,obj.can_ctrl);
  READ_CAN_STATUS(frm,spi,obj,obj.can_status);

  //set loopback and check
  obj.can_ctrl = (obj.can_ctrl & (~MODE_MASK)) | MODE_LOOPBACK;
  WRITE(CAN_CTRL,obj.can_ctrl,spi,obj);
  READ(CAN_CTRL,spi,obj,obj.can_ctrl);
  if ((obj.can_ctrl & MODE_MASK) != MODE_LOOPBACK)
     printf("mcp2515 set mode failed\n");
  //
  while(1)
  {
    select
    {
      case mcp2515.setMode(unsigned char mode):
        obj.can_ctrl = (obj.can_ctrl &(~MODE_MASK)) | (mode & MODE_MASK);
        WRITE(CAN_CTRL,obj.can_ctrl,spi,obj);
        break;
      case mcp2515.Reset():
        RESET(spi,obj);
        break;
      case mcp2515.getStatus() -> unsigned char ret:
          READ_CAN_STATUS(frm,spi,obj,obj.can_status);
        ret = obj.can_status;
        break;
      case mcp2515_int.getIntFlag() -> unsigned char flag:
        READ(CAN_INTF,spi,obj,flag);
        break;
      case mcp2515_int.setInterruptEnable(unsigned char ie):
        WRITE(CAN_INTE,ie,spi,obj);
        break;
        /*
         * Clean specific interrupt source
         */
      case mcp2515_int.ackInterrupt(unsigned char bitmask):
        BIT_MODIFY(CAN_INTF,bitmask,0,spi,obj);
        break;
      case mcp2515_int.pushBuffer(unsigned char tx_idx,const char* buff,const char len):
        WRITE_BUFF(TXB_0 + TXB_SIDH + TXB_NEXT*tx_idx,buff,len,spi,obj);
        // request to send
        WRITE(TXB_0 + TXB_CTRL + TXB_NEXT*tx_idx,TXB_CTRL_TXREQ,spi,obj);
        RTS(tx_idx,spi,obj);
        break;
        // accepted idx values 1 an 0
      case mcp2515_int.pullBuffer(unsigned char rx_idx,char *buff):
        RD_RXB((rx_idx & 1) << 1,buff,spi,obj);
        break;
    }
  }
}

/*
 * This task link the interrupt service with the mcp2515
 * todo oneshot and so modes
 */
[[distributable]] void mcp2515_interrupt_manager(client interface mcp2515_int_if mcp2515,server interface interrupt_if int_src,server interface tx_if tx,client interface rx_frame_if router)
{
  unsigned char rxtx_st;    // rx tx buffer status
  rxtx_st = (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I); // by default tx buffers are empty
  mcp2515.setInterruptEnable(MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I | MCP2515_INT_RX0I | MCP2515_INT_RX1I);   // enable all
  tx.cts();
  while(1)
  {
    select
    {
      case int_src.onInterrupt():
        unsigned char intFlags = mcp2515.getIntFlag();
        // is the tx buffer empty, do we need it
        if (intFlags & (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I) )
        {
          if ((rxtx_st & (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I)) == 0)  //
          {
            tx.cts();
          }
          rxtx_st |= (intFlags & (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I));  // update to known which buffer is empty
        }
        // did a new packet came
        if (intFlags & MCP2515_INT_RX0I)
        {
          // read the packet and send to router
          unsigned char buff[RXB_NEXT];
          mcp2515.pullBuffer(0,buff);
          // parset it
        }
        if (intFlags & MCP2515_INT_RX1I)
        {
          // read the packet and send to router
          unsigned char buff[RXB_NEXT];
          mcp2515.pullBuffer(0,buff);
          // parset it
        }
        // clear all rx and tx interrupt flags
        mcp2515.ackInterrupt(MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I | MCP2515_INT_RX0I | MCP2515_INT_RX1I);
        break;
        /*
         * Send can bus packet.
         * MSB - LSB 32 bits dest - if bit31 is 1 then this is a extended packet id
         * data max 8 bytes
         */
      case tx.send(const char* data,unsigned char len):
          if (len < 5) break; // at least 5 bytes are needed to make a packet
          unsigned i=4;
          unsigned id;
          while (i--)
          {
            id = (id << 8) | *data;
            data++;
          }
          len -=4;    // data bytes len
          /*
           * prepare mcp2515 tx buffer
           * SID10 - SID3
           * SID2 - SID0 X EXIDE  X EID17 EID16
           * EID15 - EID8   // it is not necessary to send this two bytes
           * EID7  - EID0
           * RTR DLC3-DLC0
           * DATA
           */
          unsigned char buff[14];
          buff[0] = id >> 3;
          buff[1] = (id << 5) | ((id >> (31-TXB_SIDL_EXIDE_BIT)) & TXB_SIDL_EXIDE) | ((id >> (28-1) && 0x03));
          buff[2] = (id >> (26-7));
          buff[3] = (id >> (18-7));
          buff[4] = len & 0x07;   // todo RTR flag
          unsigned char *d = buff+5;
          while (len--)
          {
            *d = *data;
            d++;
            data++;
          }
          if (rxtx_st & MCP2515_INT_TX0I)
          {
            id = 0;
          } else if (rxtx_st & MCP2515_INT_TX1I)
            id = 1;
          else id = 2;
          mcp2515.pushBuffer(id,buff,d-buff);
          // clear tx buffer bit
          if (id == 0)
            rxtx_st &= (~MCP2515_INT_TX0I);
          else if (id == 1)
            rxtx_st &= (~MCP2515_INT_TX1I);
          else
            rxtx_st &= (~MCP2515_INT_TX2I);
          if ((rxtx_st & (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I)))  //
            tx.cts();   // reset the notification if there is any buffer available
        break;
      case tx.ack():
        break;
    }
  }

}
