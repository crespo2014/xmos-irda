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

static inline void WRITE(unsigned char addres,unsigned char value,struct spi_frm_v2 &frm,client interface spi_device_if spi)
{
   frm.buff[0] = SPI_WRITE;
   frm.buff[1] = addres;
   frm.buff[2] = value;
   frm.len = 3;
   frm.wr_len = 3;
   spi.execute(&frm);
}
/*
* Request a read for a data
*/
static inline unsigned char READ(unsigned char addres,struct spi_frm_v2 &frm,client interface spi_device_if spi)
{
 frm.buff[0] = SPI_READ;
 frm.buff[1] = addres;
 frm.len = 3;
 frm.wr_len = 2;
 frm.buff[frm.wr_len*2] = 0;
 spi.execute(&frm);
 return frm.buff[frm.wr_len*2];
}

//static inline void SETMODE(unsigned mode,struct spi_frm_v2 &frm,struct mcp2515_cnf_t mcp2515)
//{
//  mcp2515.can_ctrl = (mcp2515.can_ctrl & (~MODE_MASK)) | mode;
//  MCP2515_WRITE(CAN_CTRL,mcp2515.can_ctrl,frm);
//}

static inline void MCP2515_RTS(unsigned char mask,struct spi_frm_v2 &frm)
{
  frm.buff[0] = SPI_RTS | (mask & 0x03);
  frm.len = 1;
  frm.wr_len = 1;
}

static inline unsigned char READ_CAN_STATUS(struct spi_frm_v2 &frm,client interface spi_device_if spi)
{
  frm.buff[0] = SPI_RD_STATUS;
  frm.len = 2;
  frm.wr_len = 1;
  frm.buff[frm.wr_len*2] = 0;
  spi.execute(&frm);
  return frm.buff[frm.wr_len*2];
}

static inline void MCP2515_READ_RXB_STATUS(struct spi_frm_v2 &frm)
{
  frm.buff[0] = SPI_RXB_STATUS;
  frm.len = 2;
  frm.wr_len = 1;
}

static inline void RESET(struct spi_frm_v2 &frm,client interface spi_device_if spi)
{
  frm.buff[0] = SPI_RESET;
  frm.len = 1;
  frm.wr_len = 1;
  spi.execute(&frm);
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
[[distributable]] void mcp2515_master(server interface mcp2515_if mcp2515,client interface spi_device_if spi)
{
  struct mcp2515_cnf_t obj;
  //initialize.
  struct spi_frm_v2 frm;
  RESET(frm,spi);
  obj.can_ctrl =  READ(CAN_CTRL,frm,spi);
  //check for operation mode
  if (obj.can_ctrl & MODE_MASK != MODE_CONFIGURE)
    printf("x%02X mcp2515 missing\n",obj.can_ctrl);

  obj.can_status = READ_CAN_STATUS(frm,spi);
  printf("x%02X x%02X\n",obj.can_status,obj.can_ctrl);

  //set loopback and check
  WRITE(CAN_CTRL,(obj.can_ctrl &(~MODE_MASK)) | MODE_LOOPBACK ,frm,spi);
  obj.can_ctrl =  READ(CAN_CTRL,frm,spi);
  if (obj.can_ctrl & MODE_MASK != MODE_LOOPBACK)
     printf("mcp2515 set mode failed\n");
  //

  while(1)
  {
    select
    {
      case mcp2515.setMode(unsigned char mode):
        obj.can_ctrl = (obj.can_ctrl &(~MODE_MASK)) | (mode & MODE_MASK);
        WRITE(CAN_CTRL,obj.can_ctrl,frm,spi);
        break;
      case mcp2515.Reset():
        RESET(frm,spi);
        break;
      case mcp2515.getStatus() -> unsigned char ret:
        obj.can_status = READ_CAN_STATUS(frm,spi);
        ret = obj.can_status;
        break;
    }
  }
}
