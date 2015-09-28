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

#define WRITE(__addres,__value,__spi,__ss_mask,__cpol,__cpha,__T) \
  do { \
    struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_WRITE; __frm.buff[1] = __addres; __frm.buff[2] = __value; __frm.len = 3; __frm.wr_len = 3;  \
    __spi.execute(&__frm,__ss_mask,__cpol,__cpha,__T); \
  } while(0) ;

/*
 * Read a register and save to __out
 */
#define READ(__addres,__spi,__ss_mask,__cpol,__cpha,__T,__out) \
  do { \
    struct spi_frm_v2 __frm; \
   __frm.buff[0] = SPI_READ; __frm.buff[1] = __addres; __frm.len = 3; __frm.wr_len = 2; \
   __spi.execute(&__frm,__ss_mask,__cpol,__cpha,__T); \
   __out = __frm.buff[__frm.wr_len*2]; \
  } while(0) ;

#define READ_CAN_STATUS(__frm,__spi,__ss_mask,__cpol,__cpha,__T,__out) \
  do { \
     struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_RD_STATUS; __frm.len = 2; __frm.wr_len = 1; \
    __spi.execute(&__frm,__ss_mask,__cpol,__cpha,__T); \
    __out = __frm.buff[__frm.wr_len*2]; \
  } while(0) ;

#define RESET(__spi,__ss_mask,__cpol,__cpha,__T) \
  do { \
    struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_RESET; __frm.len = 1; __frm.wr_len = 1; \
    __spi.execute(&__frm,__ss_mask,__cpol,__cpha,__T); \
  } while(0) ;

#define RTS(__mask,__spi,__ss_mask,__cpol,__cpha,__T) \
  do { \
    struct spi_frm_v2 __frm; \
    __frm.buff[0] = SPI_RTS | (mask & 0x03); __frm.len = 1; __frm.wr_len = 1; \
    __spi.execute(&__frm,__ss_mask,__cpol,__cpha,__T); \
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
[[distributable]] void mcp2515_master(unsigned char ss_mask,server interface mcp2515_if mcp2515,client interface spi_master_if spi)
{
  const unsigned T = 1*us;
  struct mcp2515_cnf_t obj;
  //initialize.
  //struct spi_frm_v2 frm;
  //RESET(frm,spi);
  obj.cpha = 0;
  obj.cpol = 0;
  READ(CAN_CTRL,spi,ss_mask,obj.cpol,obj.cpha,T,obj.can_ctrl);
  //check for operation mode
  if ((obj.can_ctrl & MODE_MASK) != MODE_CONFIGURE)
    printf("x%02X mcp2515 missing\n",obj.can_ctrl);

  READ(CAN_CTRL,spi,ss_mask,obj.cpol,obj.cpha,T,obj.can_ctrl);
  READ_CAN_STATUS(frm,spi,ss_mask,obj.cpol,obj.cpha,T,obj.can_status);

  //set loopback and check
  obj.can_ctrl = (obj.can_ctrl & (~MODE_MASK)) | MODE_LOOPBACK;
  WRITE(CAN_CTRL,obj.can_ctrl,spi,ss_mask,obj.cpol,obj.cpha,T);
  READ(CAN_CTRL,spi,ss_mask,obj.cpol,obj.cpha,T,obj.can_ctrl);
  if ((obj.can_ctrl & MODE_MASK) != MODE_LOOPBACK)
     printf("mcp2515 set mode failed\n");
  //
  while(1)
  {
    select
    {
      case mcp2515.setMode(unsigned char mode):
        obj.can_ctrl = (obj.can_ctrl &(~MODE_MASK)) | (mode & MODE_MASK);
        WRITE(CAN_CTRL,obj.can_ctrl,spi,ss_mask,obj.cpol,obj.cpha,T);
        break;
      case mcp2515.Reset():
        RESET(spi,ss_mask,obj.cpol,obj.cpha,T);
        break;
      case mcp2515.getStatus() -> unsigned char ret:
          READ_CAN_STATUS(frm,spi,ss_mask,obj.cpol,obj.cpha,T,obj.can_status);
        ret = obj.can_status;
        break;
    }
  }
}

/*
 * This task link the interrupt service with the mcp2515
 */
[[distributable]] void mcp2515_interrupt_manager(client interface mcp2515_int_if mcp2515,server interface interrupt_if int_src)
{
  while(1)
  {
    select
    {
      case int_src.onInterrupt():
        break;
    }
  }

}
