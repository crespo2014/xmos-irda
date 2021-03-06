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
     if ((__len < 5) | (__len > 12)) break; /* at least 5 bytes are needed to make a packet */ \
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
 * todo move tx task from interupt to this
 */
[[distributable]] void mcp2515_master(server interface mcp2515_if mcp2515[n],size_t n,unsigned char ss_mask,server interface tx_if tx,client interface spi_master_if spi)
{
  struct mcp2515_cnf_t obj;
  //RESET(frm,spi);
  obj.cpha = 0;
  obj.cpol = 0;
  obj.T = 1*us;
  obj.ss_mask = ss_mask;
  READ(CAN_CTRL,spi,obj,obj.can_ctrl);
  READ(CAN_INTF,spi,obj,obj.intflags);
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
  tx.cts();
  //
  while(1)
  {
    select
    {
      /*
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
        */
      case mcp2515[unsigned i].getIntFlag() -> unsigned char flag:
        READ(CAN_INTF,spi,obj,flag);
        obj.intflags |= flag;
        if (obj.intflags & (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I))
          tx.cts();
        // todo update tx flags and do cts
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
//      case mcp2515[unsigned i].pushBuffer(unsigned char tx_idx,const char* buff,const char len):
//        WRITE_BUFF(TXB_0 + TXB_SIDH + TXB_NEXT*tx_idx,buff,len,spi,obj);
//        // request to send
//        WRITE(TXB_0 + TXB_CTRL + TXB_NEXT*tx_idx,TXB_CTRL_TXREQ,spi,obj);
//        RTS(tx_idx,spi,obj);
//        break;
        // accepted idx values 1 an 0
      case mcp2515[unsigned i].pullBuffer(unsigned char rx_idx,char *buff):
        RD_RXB((rx_idx & 1) << 1,buff,spi,obj);
        break;
      /*
      * Send can bus packet.
      * MSB - LSB u32 dest - if bit31 is 1 then this is a extended packet id
      * data max 8 bytes
      */
      case tx.send(struct rx_u8_buff  * movable &pck):
        // Check command id
        if (pck->cmd_id == cmd_mcp2515_loopback)
        {
          obj.can_ctrl = (obj.can_ctrl & (~MODE_MASK)) | MODE_LOOPBACK;
          WRITE(CAN_CTRL,obj.can_ctrl,spi,obj);
          READ(CAN_CTRL,spi,obj,obj.can_ctrl);
          if ((obj.can_ctrl & MODE_MASK) != MODE_LOOPBACK)
            pck->cmd_id = cmd_mcp2515_setmode_nok;
          tx.cts();
        } else if (pck->cmd_id == cmd_can_tx)
        {
          if ( pck->len - pck->header_len < 5) break; // at least 5 bytes are needed to make a packet
          unsigned char buff[TXB_NEXT];
          CAN_TO_MCP2515(pck->dt + pck->header_len,pck->len - pck->header_len ,buff);    //
          //
          unsigned id;
          if (obj.intflags & MCP2515_INT_TX0I)
          {
            id = 0;
            obj.intflags &= (~MCP2515_INT_TX0I);
          } else if (obj.intflags & MCP2515_INT_TX1I)
          {
            id = 1;
            obj.intflags &= (~MCP2515_INT_TX1I);
          }
          else
          {
            id = 2;
            obj.intflags &= (~MCP2515_INT_TX2I);
          }
          WRITE_BUFF(TXB_0 + TXB_SIDH + TXB_NEXT*id,buff,pck->len - pck->header_len +1,spi,obj);
          // request to send
          WRITE(TXB_0 + TXB_CTRL + TXB_NEXT*id,TXB_CTRL_TXREQ,spi,obj);
          RTS(id,spi,obj);
          if ((obj.intflags & (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I)))  //
            tx.cts();   // reset the notification if there is any buffer available
        }
        // build a empty reply
        pck->header_len = pck->len;
        break;
      case tx.ack():
        break;
    }

  }
}

/*
 * This task link the interrupt service with the mcp2515
 * todo oneshot and so modes
 */
[[distributable]] void mcp2515_interrupt_manager(client interface mcp2515_if mcp2515,server interface interrupt_if int_src,client interface rx_frame_if router)
{
  struct rx_u8_buff tfrm;   // temporal frame
  struct rx_u8_buff * movable pframe = &tfrm;
  unsigned char rxtx_st;    // rx tx buffer status
  rxtx_st = (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I); // by default tx buffers are empty
  mcp2515.setInterruptEnable(MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I | MCP2515_INT_RX0I | MCP2515_INT_RX1I);   // enable all interrputs
  while(1)
  {
    select
    {
      case int_src.onInterrupt():
        unsigned char intFlags = mcp2515.getIntFlag();
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
          pframe->cmd_id = cmd_can_rx;
          router.push(pframe,cmd_tx); // send to command interface for translation
        }
        // clear all rx and tx interrupt flags
        mcp2515.ackInterrupt(MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I | MCP2515_INT_RX0I | MCP2515_INT_RX1I);
        break;
    }
  }
}

void mcp2515_spi(server interface mcp2515_spi_if mcp2515, client interface spi_if spi)
{
    while(1)
    {
        select
        {
        case mcp2515.reset():
            spi.wr(SPI_RESET);
            break;
        case mcp2515.read(unsigned char address) -> unsigned char ret:
            spi.start();
            spi.wr(SPI_READ);
            spi.wr(address);
            ret = spi.rd();
            spi.end();
            break;
        case mcp2515.read_rx_buffer(unsigned char address) -> unsigned char ret:
            spi.start();
            spi.wr(SPI_RD_RXB + address & 3);
            ret = spi.rd();
            spi.end();
            break;

        case mcp2515.write(unsigned char address, unsigned char value):
            spi.start();
            spi.wr(SPI_WRITE);
            spi.wr(address);
            spi.wr(value);
            spi.end();
            break;

        case mcp2515.load_tx_buffer(unsigned char address, unsigned char value):
            spi.start();
            spi.wr(SPI_LOAD_TXB + address & 3);
            spi.wr(value);
            spi.end();
            break;

        case mcp2515.rts(unsigned char buffers):
            spi.wr(SPI_RTS + buffers & 3);
            break;

        case mcp2515.read_status() -> unsigned char ret:
            spi.start();
            spi.wr(SPI_RD_STATUS);
            ret = spi.rd();
            spi.end();
            break;

        case mcp2515.rx_status() -> unsigned char ret:
            spi.start();
            spi.wr(SPI_RXB_STATUS);
            ret = spi.rd();
            spi.end();
            break;

        case mcp2515.bit_modify(unsigned char address, unsigned char mask, unsigned char value):
            spi.start();
            spi.wr(SPI_BIT_UPDATE);
            spi.wr(address);
            spi.wr(mask);
            spi.wr(value);
            spi.end();
            break;

        }
    }
}

[[distributable]] void mcp2515(
        server interface mcp2515_rx_if rx,
        server interface mcp2515_tx_if tx,
        server interface mcp2515_admin_if admin,
        client interface mcp2515_int_if interrupt,
        client interface mcp2515_spi_if spi)
{
    // interrupt flags
    unsigned char IntFlag = 0;

    while(1)
    {
        select
        {
        case admin.enableInterrupt(unsigned char bitmask):
            mcp2515_spi.write(CAN_INTE, bitmask);
            break;
        case admin.reset():
            mcp2515_spi.reset();
            break;
        case admin.readReg(address) -> unsigned char ret:
            ret = mcp2515_spi.read(address);
            break;
        case interrupt.onInt():
            unsigned char flag = mcp2515_spi.read(CAN_INTF);
            IntFlag |= flag;
            interrupt.clear();
            if (flag & (CAN_INT_TX0IF | CAN_INT_TX1IF | CAN_INT_TX2IF))
                tx.onCTS();
            if (flag & (CAN_INT_RX1IF | CAN_INT_RX0IF))
                rx.onData();
            mcp2515_spi.bit_modify(CAN_INTF, flag & (CAN_INT_TX0IF | CAN_INT_TX1IF | CAN_INT_TX2IF | CAN_INT_RX1IF | CAN_INT_RX0IF), 0);
            break;
        case rx.recv(struct mcp215_msg& msg):
            unsigned char base = 0;
            if (IntFlag & CAN_INT_RX0IF)
            {
                base = RXB_0;
                IntFlag &= ~CAN_INT_RX0IF;
            }
            else if (IntFlag & CAN_INT_RX1IF)
            {
                buffer = RXB_0 + RXB_NEXT;
                IntFlag &= ~CAN_INT_RX1IF;
            }
            else
            {
                msg.count = 0;
                break;
            }
            break;
        case tx.send(struct mcp215_msg& msg):
            unsigned char buffer;
            if (IntFlag & (CAN_INT_TX0IF | CAN_INT_TX1IF | CAN_INT_TX2IF))
            {

            }
            break;

        }
    }
}
