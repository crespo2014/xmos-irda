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
    __frm.buff[0] = SPI_RTS | (mask & 0x03); __frm.len = 1; __frm.wr_len = 1; \
   __spi.execute(&__frm,__obj.ss_mask,__obj.cpol,__obj.cpha,__obj.T); \
  } while(0) ;

#define BIT_MODIFY(__addres,__mask,__value,__spi,__obj) \
  do { \
    struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_BIT_UPDATE; __frm.buff[1] = __addres;__frm.buff[2] = __mask;__frm.buff[3] = __value;__frm.len = 4; __frm.wr_len = 4; \
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
    }
  }
}

/*
 * This task link the interrupt service with the mcp2515
 */
[[distributable]] void mcp2515_interrupt_manager(client interface mcp2515_int_if mcp2515,server interface interrupt_if int_src,server interface tx_if tx,client interface rx_frame_if router)
{
  unsigned char rxtx_st;    // rx tx buffer status
  rxtx_st = (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I);
  unsigned intFlags = MCP2515_INT_TX0I | MCP2515_INT_TX1I;    // interrupt flags, but default tx buffers are empty
  mcp2515.setInterruptEnable(MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I | MCP2515_INT_RX0I | MCP2515_INT_RX1I);   // enable all
  tx.cts();
  while(1)
  {
    select
    {
      case int_src.onInterrupt():
        intFlags = mcp2515.getIntFlag();
        // is the tx buffer empty, do we need it
        if (intFlags & (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I) )
        {
          if ((rxtx_st & (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I)) == 0)  //
          {
            tx.cts();
          }
          rxtx_st |= (intFlags & (MCP2515_INT_TX0I | MCP2515_INT_TX1I | MCP2515_INT_TX2I));  // update to known emptied tx buffer
        }
        // did a new packet came
        if (intFlags & (MCP2515_INT_RX0I | MCP2515_INT_RX1I) )
        {

        }
        // clear rx and tx interrupt flags

        break;
    }
  }

}
