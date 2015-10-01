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
#include "cmd.h"

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
 * acepted id 0 for rx0 and 2 for rx1
 */
#define RD_RXB(__idx,__buff,__spi,__obj)  \
do { \
  struct spi_frm_v2 __frm; \
  __frm.buff[0] = SPI_RD_RXB | ((__idx & SPI_RD_RXB_MASK) << SPI_RD_RXB_SHIFT); __frm.len = RXB_NEXT; __frm.wr_len = 1; \
  __spi.execute(&__frm,__obj.ss_mask,__obj.cpol,__obj.cpha,__obj.T); \
} while(0) ;

/*
 * Convert a frame to a mcp2515 buffer
 * CAN
 * EXID RTR ID  - 32bits
 * data
 * Size of out data depends on mcp2515
 * MCP2515 tx buffer
 * SID10 - SID3
 * SID2 - SID0 X EXIDE  X EID17 EID16
 * EID15 - EID8   // it is not necessary to send this two bytes
 * EID7  - EID0
 * RTR DLC3-DLC0
 * DATA
 */

#define CAN_TO_MCP2515(__in,__len,__out) \
  do { \
     if ((__len < 5) | (len > 12)) break; /* at least 5 bytes are needed to make a packet */ \
     unsigned __i = ( *(__in) << 24) | ( *(__in + 1) << 16 ) | (*(__in + 2) << 8) | *(__in + 3); \
     *(__out) = __i >> 3; \
     *(__out + 1) = (__i << 5) | (__i >> (28-1) && 0x03); \
     if (__i & CAN_EXID) *(__out + 1) |= TXB_SIDL_EXIDE; \
     *(__out + 2) = (__i >> (26-7)); \
     *(__out + 3) = (__i >> (18-7)); \
     *(__out + 4) = (__len - 4) & 0x07;    \
     if (__i & CAN_RTR) *(__out + 4) |= TXB_DLC_RTR; \
     for (__i=4;__i<__len;__i++) { \
       *(__out + 1 +__i) = *(__in + __i); \
     } \
  } while(0)

#define MCP2515_TO_CAN(__in,__len,__out,__outlen) \
    do { \
      unsigned __id = (*__in << 3) | (*(__in + 1) >> 5) | ((*(__in + 1) & 0x3) << 24) | (*(__in+2) << 16) | (*(__in+3) << 8); \
      if (*(__in+1) & TXB_SIDL_EXIDE) __id |= CAN_EXID; \
      if (*(__in+4) & TXB_DLC_RTR) __id |= CAN_RTR; \
      *(__out) = __id >> 24; \
      *(__out + 1) = __id >> 16; \
      *(__out + 2) = __id >> 8; \
      *(__out + 3) = __id & 0xFF; \
      __outlen = *(__in + 4) & 0x07; /* read size */ \
      __id = __outlen; \
      while (__id--) { \
        *(__out + 4 + __id) = *(__in + 5 + __id); \
      } \
    } while(0)


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
[[distributable]] void mcp2515_master(server interface mcp2515_if mcp2515[n],size_t n,unsigned char ss_mask,client interface spi_master_if spi)
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
      case mcp2515[unsigned i].setMode(unsigned char mode):
        obj.can_ctrl = (obj.can_ctrl &(~MODE_MASK)) | (mode & MODE_MASK);
        WRITE(CAN_CTRL,obj.can_ctrl,spi,obj);
        break;
      case mcp2515[unsigned i].Reset():
        RESET(spi,obj);
        break;
      case mcp2515[unsigned i].getStatus() -> unsigned char ret:
          READ_CAN_STATUS(frm,spi,obj,obj.can_status);
        ret = obj.can_status;
        break;
      case mcp2515[unsigned i].getIntFlag() -> unsigned char flag:
        READ(CAN_INTF,spi,obj,flag);
        break;
      case mcp2515[unsigned i].setInterruptEnable(unsigned char ie):
        WRITE(CAN_INTE,ie,spi,obj);
        break;
        /*
         * Clean specific interrupt source
         */
      case mcp2515[unsigned i].ackInterrupt(unsigned char bitmask):
        BIT_MODIFY(CAN_INTF,bitmask,0,spi,obj);
        break;
      case mcp2515[unsigned i].pushBuffer(unsigned char tx_idx,const char* buff,const char len):
        WRITE_BUFF(TXB_0 + TXB_SIDH + TXB_NEXT*tx_idx,buff,len,spi,obj);
        // request to send
        WRITE(TXB_0 + TXB_CTRL + TXB_NEXT*tx_idx,TXB_CTRL_TXREQ,spi,obj);
        RTS(tx_idx,spi,obj);
        break;
        // accepted idx values 1 an 0
      case mcp2515[unsigned i].pullBuffer(unsigned char rx_idx,char *buff):
        RD_RXB((rx_idx & 1) << 1,buff,spi,obj);
        break;
    }
  }
}

/*
 * This task link the interrupt service with the mcp2515
 * todo oneshot and so modes
 */
[[distributable]] void mcp2515_interrupt_manager(client interface mcp2515_if mcp2515,server interface interrupt_if int_src,server interface tx_if tx,client interface rx_frame_if router)
{
  struct rx_u8_buff tfrm;   // temporal frame
  struct rx_u8_buff * movable pframe = &tfrm;
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
            tx.cts(); // it was not any buffer empty before, then signal
          }
//          rxtx_st |= (intFlags & (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I));  // update to known which buffer is empty
        }
        rxtx_st |= intFlags;   // get all events, keeping previous ones

        while(rxtx_st & (MCP2515_INT_RX0I | MCP2515_INT_RX1I))
        {
          unsigned idx;
          if (rxtx_st & MCP2515_INT_RX0I)
          {
            idx = 0;
            rxtx_st &=(~MCP2515_INT_RX0I);
          }else
          {
            idx = 1;
            rxtx_st &=(~MCP2515_INT_RX1I);
          }
          unsigned char buff[RXB_NEXT];
          mcp2515.pullBuffer(idx,buff);
          MCP2515_TO_CAN(buff,sizeof(buff),pframe->dt,pframe->len);
          pframe->overflow = 0;
          pframe->len++;  //
          pframe->id = 0; // no id associated to this command
          pframe->src_rx = cmd_can_rx;
          router.push(pframe,cmd_tx); // send to command interface for translation
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
        unsigned char buff[TXB_NEXT];
        CAN_TO_MCP2515(data,len,buff);    //
        //
        unsigned id;
        if (rxtx_st & MCP2515_INT_TX0I)
        {
          id = 0;
        } else if (rxtx_st & MCP2515_INT_TX1I)
          id = 1;
        else id = 2;
        mcp2515.pushBuffer(id,buff,len +1); // -4 for id + 5 for txb header
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

