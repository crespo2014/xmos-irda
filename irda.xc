/*
 * irda.xc
 *  Created on: 7 Jul 2015
 *      Author: lester.crespo
 */
#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>
#include <rxtx.h>
#include "irda.h"
#include "serial.h"
#include "cmd.h"
#include "utils.h"

#define USER_CLK_DIV    255                 //
#define USER_T_ns       (1000*1000)    //
#define USER_CLK_T_ns   (XCORE_CLK_T_ns*USER_CLK_DIV) // T of clock two times pulse width
#define USER_CLK_PER_T  (USER_T_ns/USER_CLK_T_ns)

/*
SPI synchronization byte
10010001 - it is easy to known how many bits has been shifted

using configure_clock_xcore taking samples at 1us
DIV,portcount
1us  1,255 2,128 4,64 8,32 16,16
10us (16,157) (32,78) (64,38)
100us (64,390) (128,194) (255,97)
1ms (255,979)
counting 256 per Mhz

From Xscope
div =
1 - pulse width is 2ns. T = 4ns, faster transition is every to clocks (8ns)
2 - 4ns pulse T = 8ns
3 - 6ns pulse T = 12ns
4 - 8ns pulse T = 16ns
10 - 20ns     T = 40ns
*/

#if 0

/**
 * IRDA receiver project.
 * Hardware:
 * TERRATEC Remote Control.
 * Buttons
 * Home       ;101111100100000111101011000101; 0x28d7827d
 * Power      ;111111100000000111101011000101; 0x28d7807f
 * DVD Menu   ;101111010100001011101011000101; 0x28d742bd
 * Subtitles  ;101111000100001111101011000101; 0x28d7c23d
 * Teletext   ;101110110100010011101011000101; 0x28d722dd
 * Delete     ;101110100100010111101011000101; 0x28d7a25d
 * AV         ;111101000000101111101011000101; 0x28d7d02f
 * A-B        ;111100100000110111101011000101; 0x28d7b04f
 * 1          ;111111010000001011101011000101; 0x28d740bf
 * 2          ;111111000000001111101011000101; 0x28d7c03f
 * 3          ;111110110000010011101011000101; 0x28d720df
 * 4          ;111110100000010111101011000101; 0x28d7a05f
 * 5          ;111110010000011011101011000101; 0x28d7609f
 * 6          ;111110000000011111101011000101; 0x28d7e01f
 * 7          ;111101110000100011101011000101; 0x28d710ef
 * 8          ;111101100000100111101011000101; 0x28d7906f
 * 9          ;111101010000101011101011000101; 0x28d750af
 * 0          ;111100110000110011101011000101; 0x28d730cf
 * TV         ;101110010100011011101011000101; 0x
 * DVD        ;101110000100011111101011000101; 0x
 * VIDEO      ;101101100100100111101011000101; 0x
 * Music      ;101101010100101011101011000101; 0x
 * PIC        ;101101000100101111101011000101; 0x
 * UP         ;111011110001000011101011000101; 0x
 * DOWN       ;111010110001010011101011000101; 0x
 * RIGHT      ;111011000001001111101011000101; 0x
 * LEFT       ;111011100001000111101011000101; 0x
 * OK         ;111011010001001011101011000101; 0x
 * GUIDE      ;111100000000111111101011000101; 0x
 * INFO       ;111010010001011011101011000101; 0x
 * BACK       ;101100100100110111101011000101; 0x
 * VOL+       ;111000110001110011101011000101; 0x
 * VOL-       ;111000010001111011101011000101; 0x
 * CH+        ;111001000001101111101011000101; 0x
 * CH-        ;111000000001111111101011000101; 0x
 * Play       ;101100110100110011101011000101; 0x
 * Mute       ;111000100001110111101011000101; 0x
 * red        ;111010000001011111101011000101; 0x
 * green      ;111001110001100011101011000101; 0x
 * yellow     ;111001100001100111101011000101; 0x
 * blue       ;111001010001101011101011000101; 0x
 * REC        ;101001110101100011101011000101; 0x
 * STOP       ;101101110100100011101011000101; 0x
 * PAUSE      ;101111110100000011101011000101; 0x
 * LAST       ;101010110101010011101011000101; 0x
 * FR         ;101100010100111011101011000101; 0x
 * FF         ;101100000100111111101011000101; 0x
 * NEXT       ;101000110101110011101011000101; 0x
 *
 * pulse has a base Time T of 600us usingh a 100Mhz clock that means 60 000 cycles * 0.001us
 *
 * When a button is pressed
 * a 0 pulse of 15T is send. it means clear status.
 * a 1 pulse between 4T-7T that means start
 * bit as 0 is send as < 2T
 * bit 1 is received as >2T <5T
 * if pin got high for more than 8T means end of value
 *
 * wait 0 -1 transition and analyze timing
 *
 * source code
 * wait for 0.
 * if length > 10 then frame end
 * if length > 4 then start new frame
 * if length > 2 then push 1 else push 0
 * wait for 1
 * if lenght > 8T then end frame
 *
 *
 * more than 8T zero means end also more than 8T 1
 *
 */

void IRDA_TERRATEC(in port p, chanend c)
{
  const unsigned freq_tick = 60 * 1000;
  char bitcount = 0;
  unsigned number = 0;
  timer tm;
  int ts, te = 0;
  tm :> ts
  ;
  for (;;)
  {
    // wait 0
    select
    {
      case tm when timerafter(ts + freq_tick * 10) :> void:
      // long 1 mean end frame or new one
      if (bitcount != 0)
      {
        c <: number;
        bitcount = 0;
        number = 0;
      }
      p when pinseq(0) :> void; // wait for 0
      tm :> ts;
      break;
      case p when pinseq(0) :> void:
      tm :> te;
      // check length of 1
      ts = (te - ts);
      if (ts > 3 * freq_tick)// new frame
      {
        number = 0;
        bitcount = 0; // start signal received
      }
      else
      {
        bitcount++;
        // rotate and set 1
        number = number *2;
        if (ts >= 2*freq_tick) number++;
      }
      ts = te;
      break;
    }
    // wait 1 or timeout
    select
    {
      case tm when timerafter(ts + freq_tick * 4) :> void:
      // zero to long it means holding button
      bitcount = 0;
      p when pinseq(1) :> void;
      tm :> ts;
      break;
      case p when pinseq(1) :> void:
      tm :> ts;
      break;
    }
  }
}

/**
 * Sony remote control
 * pin go down to 0 for 3.9T start frame
 * and go up to 1 for 1T
 * 2T in 0 means 1
 * 1T in 0 means 0
 *
 * pin high for more tan 5T is end of frame
 *
 * remote control Sony RMT-D198P
 * EJECT             ;0x68b92
 * TV IN             ;0xa50
 * TV POWER          ;0xa90
 * POWER             ;0xa8b92
 * 1                 ;0xb92
 * 2                 ;0x80b92
 * 3                 ;0x40b92
 * 4                 ;0xc0b92
 * 5                 ;0x20b92
 * 6                 ;0xa0b92
 * 7                 ;0x60b92
 * 8                 ;0xe0b92
 * 9                 ;0x10b92
 * 0                 ;0x90b92
 * VOL +             ;0x490
 * VOL -             ;0xc90
 * PICTURE NAVI      ;0xab92
 * CLEAR             ;0xf0b92
 * AUDIO             ;0x26b92
 * SUBTITLE          ;0xc6b92
 * TIME/TEXT         ;0x14b92
 * MENU              ;0xd8b92
 * UP                ;0x9eb92
 * DOWN              ;0x5eb92
 * RIGHT             ;0x3eb92
 * LEFT              ;0xdeb92
 * CENTER            ;0xd0b92
 * RETURN            ;0x70b92
 * DISPLAY           ;0x2ab92
 * |<< REV           ;0xcb92
 * <<| FREV          ;0x3ab92
 * |>> FORWARD       ;0x28b46
 * >>| FF            ;0x8cb92
 * <<                ;0x44b92
 * PLAY              ;0x4cb92
 * >>                ;0xc4b92
 * FAST/SLOW PLAY    ;0xdcb46
 * PAUSE             ;0x9cb92
 * STOP              ;0x1cb92
 */

void irda_sony(in port p, chanend c)
{
  const unsigned freq_tick = 60 * 1000;
  char bitcount = 0;
  unsigned number = 0;
  timer tm;
  int ts, te = 0;
  tm :> ts
  ;
  for (;;)
  {
    // wait 0
    select
    {
      case tm when timerafter(ts + freq_tick * 6) :> void:
      // long 1 mean end frame
      if (bitcount != 0)
      {
        c <: number;
        bitcount = 0;
        number = 0;
      }
      p when pinseq(0) :> void; // wait for 0
      tm :> ts;
      break;
      case p when pinseq(0) :> void:
      tm :> ts;
      break;
    }
    // wait 1
    p when pinseq(1) :> void;
    tm :> te;
    // check length of 1
    ts = (te - ts);// / freq_tick;
    if (ts >= freq_tick * 3)// new frame
    {
      number = 0;
      bitcount = 0; // start signal received
    } else
    {
      bitcount++;
      // rotate and set 1
      number = number * 2;
      if (ts >= (freq_tick + freq_tick/2))
      number++;
    }
    ts = te;
  }
}

void irda_send_loop(out port p)
{
  timer t;
  unsigned tp,count;
  p <: 0 @count;
  for (;;)
   {
    IRDA_CLOCKED_BIT_v1(p,4,1,0);
//   SONY_IRDA_SEND(0x55,8,t,led_1,1,0);
   t :> tp;
   t when timerafter(tp+100*us) :> tp;
   }
}


void IRDA_time(in port p, chanend c)
{
  int t = 0;
  unsigned char val = 0;
  timer tm;
  p :> val;
  printf("%d\n", val);
  for (;;)
  {
    // wait for 0
    p when pinsneq(val) :> val;
    tm :> t;
    c <: t;
  }
}

void IRDA_delta(in port p, chanend c)
{
  unsigned int te;
  unsigned int ts;
  unsigned char val = 0;
  timer tm;
  tm :> ts;
  p :> val;
  for (;;)
  {
    p when pinsneq(val) :> val;
    tm :> te;
    c <: (te-ts);
    ts = te;
  }
}

#endif

#if 0
void irda_send(unsigned data,unsigned char bitcount,client interface tx_if tx)
{
  unsigned char buff[5];
  buff[0] = bitcount;
  buff[1] = data >> 24;
  buff[2] = data >> 16;
  buff[3] = data >> 8;
  buff[4] = data & 0xFF;
  tx.send(buff,5);
}
#endif
/*
 * Emulator for irda
 */
[[distributable]] void irda_emulator(unsigned bitlen,out port p,server interface tx_if tx)
{
  timer t;
  unsigned tp;
  p <: 1;
  while(1)
  {
    select
    {
    case tx.send(struct rx_u8_buff  * movable &pck):
      if (pck->len == 5)
      {
        unsigned int bitmask = (1<<(pck->dt[0]-1));
        unsigned v= 0;
        for (int i = 0;i< pck->len;i++)
        {
          v = (v << 8) | pck->dt[i];
        }
        //start bit
        p <: 0;
        t :> tp;
        tp += (4*bitlen);
        t when timerafter (tp) :> void;
        p <: 1;
        tp += bitlen;
        while (bitmask != 0)  {
          t when timerafter (tp) :> void;
          p <: 0;
          if (v & bitmask)
            tp = tp + bitlen*2;
          else
            tp = tp + bitlen;
          t when timerafter (tp) :> void;
          p <: 1;
          tp += bitlen;
          bitmask >>= 1;
        }
        tp = tp + 3*bitlen;   // stop bit
        t when timerafter (tp) :> void;
      }
      break;
    case tx.ack():
      break;
    }
  }
}

/*
 * Irda with clocked port
 * Packet format is
 * bitcount MSB - LSB (4 bytes u32)
 */
[[distributable]] void irda_tx_v5(clock clk,out buffered port:32 p32,server interface tx_if tx)
{
  configure_clock_xcore(clk,IRDA_32b_CLK_DIV);     // dividing clock ticks
  configure_in_port(p32, clk);
  start_clock(clk);
  while(1)
  {
    select
    {
      case tx.send(struct rx_u8_buff  * movable &pck):
        if (pck->len == 5)
        {
          unsigned bitcount = *pck->dt;
          unsigned v= 0;
          for (int i=1;i< pck->len;++i)
          {
            v = (v << 8) | pck->dt[i];
          }
          SONY_IRDA_32b_SEND(v,bitcount,p32);
          sync(p32);
        }
        break;
      case tx.ack():
        break;
    }
  }
}
/*
 * irda rx task.
 *
 * it can be combine with the irda tx to avoid receiving the send signal.
 * Sample the irda port every T/2 and count
 * when port change check counter.
 * stop sampling if no start signal was recieved.
 * ic coutn reach 10 also stop timing out
 * read bits from MSB to LSB
 *
 * send to router as irda_id
 */

[[combinable]] void irda_rx_v5(in port p,unsigned bitlen,client interface rx_frame_if router)
{
  unsigned char pv;
  unsigned char reading;
  unsigned char bitcount;
  unsigned pv_length;
  unsigned v;
  unsigned tp;
  timer t;
  struct rx_u8_buff tfrm;   // temporal frame
  struct rx_u8_buff * movable pframe = &tfrm;

  bitcount = 0;
  pv_length = 0;
  reading = 0;    //0 no data, 1 sampling, 2 - waiting pin change
  p :> pv;
  while(1)
  {
    select
    {
      case p when pinsneq(pv) :> pv:
        t :> tp;
        if (pv_length != 0 && pv == 1 && bitcount) // only use 0 to 1 transition and after start
        {
            bitcount++;
            v = v << 1;
            if (pv_length > 2)
              v = v | 1;
        }
        reading = 1;      // start sampling
        pv_length = 0;
        tp += bitlen/2;
        break;
      case reading => t when timerafter(tp):> void:
        pv_length++;
        tp += bitlen/2;
        if (pv_length < 7)  break;  // keep sampling
        // start or stop
        if (pv == 1)  // stop condition
        {
          if (bitcount > 1)
          {
            pframe->dt[0] = cmd_irda_rx;
            pframe->dt[1] = bitcount - 1;
            pframe->dt[2] = v >> 24;
            pframe->dt[3] = v >> 16;
            pframe->dt[4] = v >> 8;
            pframe->dt[5] = v & 0xFF;
            pframe->len = 6;
            router.push(pframe,cmd_tx);
          }
          bitcount = 0;
        }
        else
          bitcount = 1;   // counting start as bit
        v = 0;
        pv_length = 0;
        reading = 0;  // no more samples
        break;
    }
  }
}

/*
 * irda port is always driven a 1,it drives to 0 when a signal is received
 * Data need to be send inverted and it needs to start with a zero.
 * To be checked by hardware
 * it seems that irda connect 5v to output when a signal is recieved.
 * the a inverted is needed for serial port.
 */
[[distributable]] void irda_tx(struct irda_tx_0_t &irda,server interface tx_if tx)
{
  while(1)
  {
    select
    {
      case tx.send(struct rx_u8_buff  * movable &pck):
        if (pck->len - pck->header_len == 5)
        {
          unsigned v= 0;
          for (int i=1;i< pck->len;++i)
          {
            v = (v << 8) | pck->dt[pck->header_len + i];
          }
          irda_0_send(irda,v,pck->dt[pck->header_len]);
        }
        break;
      case tx.ack():
        break;
    }
  }
}
/*
 * Reading at when pinseq(1) gives 0x8000 0000  because buffer was full.
 * pulse at t 0
 * t + 4ns stop waiting on port
 * t + 28ns waiting on port
 * t + 40ns debug port output 0x8000 0000
 * t + 130ns read done
 * t + 190  debug port outs 0x8282 8280
 * t + 210 waiting on port
 * t + 220 debug outs 0x820A 0A 0A
 *
 * read 32bits at the time (2 cells)
 * data coming from lsb to msb
 *
 * TX 32bits * 8 ns = 1b/256ns = 0.00390625*10^9bytes/sec = 3.7Mbytes/sec
 *
 * I need max 16 bits to send data
 * 10 - start
 * 10 [0..3] cell 5 bits cell
 * - cells
 * 12bits cells + 4 bits as remaining
 *
 * data is read as lsb to msb, and send as well
 */
void ppm_rx_task(struct ppm_rx_t &ppm,streaming chanend c)
{
  unsigned v1;
  while(1)
  {
    ppm.p when pinseq(1):> void;   // read 0x8000
    do
    {
      ppm.p :> v1;
      unsigned char d2 = clz(v1);
      unsigned char d1 = clz(v1 << 16);
      c <: (unsigned char)clz(v1 << 16);
      c <: (unsigned char)d2;
    } while (v1);
  }
}

/*
 * receiving 0 signal end of data
 */
void ppm_rx_decode(streaming chanend c,out port p)
{
  unsigned char buff[32];
  unsigned len;
  unsigned data;
  unsigned char v;
  len = 0;
  data = 1;
  while(1)
  {
    select {
      case c :> v:
        p <: v;
      if (v > 10)
      {
        if (len) print_buff(buff,len);
        len = 0;
        data = 1;
        break;
      }
      data = (data << 2) | (v>>1);
      if (data & 0x100)
      {
        if (len < sizeof(buff))
        {
          buff[len] = data;
          len++;
          data = 1;
        }
      }
      break;
    }
  }
}
