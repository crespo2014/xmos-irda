/*
 * rxtx.xc
 *
 *  Created on: 11 Aug 2015
 *      Author: lester.crespo
 */

#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>
#include "rxtx.h"

#if 0
/*
 * Buffer manipulator.
 * Store until 4 blocks of 20 bytes each one
 */
struct frm_buff_4_t
{
  unsigned char use_count;  // how many frame with data
  unsigned char wr_pos;
  struct tx_frame_t* movable pfrm[4];
};

inline void buff4_init(struct frm_buff_4_t &buff)
{
  buff.use_count = 0;
  buff.wr_pos = 0;
}

/*
 * Get a frame from buffer
 */
inline unsigned char buff4_get(struct frm_buff_4_t &buff,struct tx_frame_t  * movable &old_p)
{
  if (buff.use_count == 0)
    return 0;
  unsigned char pos;
  pos = (buff.wr_pos +(4 - buff.use_count)) % 4;
  struct tx_frame_t  * movable tmp;
  tmp = move(old_p);
  old_p = move(buff.pfrm[pos]);
  buff.pfrm[pos] = move(tmp);
  buff.use_count--;
  return 1;
}
/*
 * Add a new frame to the buffer
 */
inline unsigned char buff4_push(struct frm_buff_4_t &buff,struct tx_frame_t  * movable &old_p)
{
  if (buff.use_count == 4)
      return 0;
  struct tx_frame_t  * movable tmp;
  old_p->len = 0;
  tmp = move(old_p);
  old_p = move(buff.pfrm[buff.wr_pos]);
  buff.pfrm[buff.wr_pos] = move(tmp);
  buff.use_count++;
  return 1;
}

/*
Shared port task
*/
[[distributable]]
void port_sharer(server interface out_port_if i[n], unsigned n,out port p)
{
  unsigned port_val = 0;
  while (1) {
    select {
    // Wait for a client to send an output request
    case i[int j].set():
      port_val |= (1 << j);
      p <: port_val;
      break;
    case i[int j].clear():
      port_val &= (~(1 << j));
      p <: port_val;
      break;
    case i[int j].update(unsigned char v):
     port_val = (port_val & (~(1 << j))) | v ? (1 << j) : 0 ;
     p <: port_val;
     break;
    }
  }
}
/*
 * Fast comunication system
 * RX is not combinable
 */

void fastRX(streaming chanend ch,in port p)
{
  timer t;
  unsigned int tp1,tp2;
  unsigned dt,d;
  int i;
  do
  {
    do
    {
      p when pinseq(1) :> void;  // 3 ticks
      t :> tp1;                  // 2 ticks
      p when pinseq(0) :> void;
      t :> tp2;
      d = (tp2-tp1);
      if (d < 12) break;  //
      for (i=8;i;i--)
      {
        p when pinseq(1) :> void;  // 3 ticks
        t :> tp1;                  // 2 ticks
        p when pinseq(0) :> void;
        t :> tp2;
        d = (tp2-tp1);
        if (d > 11) break;
        dt >>=1;
        if (d > 4) dt |= 0x80;
      }
      if (i == 0) ch <: (unsigned char)dt;
      else
        break;
    } while(1);
    // error condition
    ch <: 0xFF;
    //printf("e %X\n",d);
//    p when pinseq(1) :> void;  // 3 ticks
//    t :> tp1;                  // 2 ticks
//    p when pinseq(0) :> void;
//    t :> tp2;
//    ch <:(unsigned char)(tp2-tp1);
  } while(1);
}

/*
 * pulse width decoder
 * 3T start bit
 * 2T one
 * 1T zero
 * no time to process
 */
void fastRXParser(streaming chanend ch)
{
  unsigned char d;
  unsigned dt;
  unsigned i;
  while(1)
  {
    while(1)
    {
      ch :> d;
      printf("%X\n",d);
      continue;
      if (d < 10) break;  //
      for (i=0;i<8;i++)
      {
        ch :> d;
        //printf("%X\n",d);
        if (d > 10) break;
        dt >>=1;
        if (d > 4) dt |= 0x80;
      }
      if (d>10) break;
      printf("%X\n",dt);
    }
    // error condition
    printf("e %X\n",d);
  }
}

/*
 * Fast tx using clocked port
 * Data send from lsb to msb.
 * Start 3x1 + 1x0 = 4bits
 * 1 = 2x1 + 1x0 = 3bits
 * 0 = 1x1 + 1x0 = 2bits
 * 8bits*3 + 4 = 28bits per byte. + 4 bits to relax.
 */

[[distributable]] void fastTX(server interface fast_tx tx_if,clock clk,out buffered port:32 p)
{
  configure_clock_xcore(clk,20);     //40ns pulse width dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  while(1)
  {
    select
    {
      case tx_if.push(unsigned char dt):
        unsigned int d = 0;
        for (unsigned i=0x80;i;i>>=1)
        {
          if (dt & i)
          {
            d<<= 3;
            d|=6;
          }
          else
          {
            d<<= 2;
            d|=2;
          }
        }
        d <<= 4;
        d |= 0x7;
        p <: d;
        break;
    }
  }
}
/*
 * This task is holding buffer, then it is distributable
 */
[[distributable]] void fifo_v1(client interface tx tx_if,server interface fifo ff_if[max],unsigned max)
{
  unsigned char buff[128];
  unsigned buff_wr;
  unsigned buff_count; // how many bytes in the buffer
  buff_wr = 0;
  buff_count = 0;
  while (1) {
    select {
    case ff_if[int j].push(const unsigned char* dt,unsigned len) -> unsigned ret:
        ret  = (sizeof(buff) - buff_count > len);
        if (ret)
        {
          while(len--)
          {
            buff[buff_wr] = *dt++;
            buff_wr = (buff_wr + 1) & (sizeof(buff)-1);
            buff_count++;
          }
        }
        break;
    case buff_count => tx_if.ready():
      tx_if.push(buff[(buff_wr + sizeof(buff) - buff_count)& (sizeof(buff)-1)]);
      buff_count--;
      break;
    }
  }
}

/*
 * Wait for pin become high.
 * read data until value reach 0. then wait again
 * Sample rate is 4ns data rate has to be 8ns.
 * Initial pulse need to be long enough to allow task wake up, and start read cmd. (20ns). 5T is good.
 * Another task counting pulse decodes the data
 */
void fastRX_v3(streaming chanend ch,in buffered port:32 p,clock clk)
{
  unsigned dt;
  configure_clock_xcore(clk,1);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  do
  {
    p when pinsneq(0):>void;
    p :> dt;
    ch <: (unsigned char)(dt >> 5);
  } while(1);
}

/*
 * Parser extract data
 * a bit can be read 3 times, but not 4
 * a bit has to be 2 times, max 3 times.
 * any bit can be read a even time plus one more.
 * count how many time and /2
 * it is need 10 ones to start
 *
 * read the same value two times is confirmation than ok.
 *
 * todo make it combinable.
 */
enum fast_rx_st_v3
{
  waiting_start,
  reading_start,
  reading_b00,
  reading_b01,
  reading_b10,
  reading_b11,
  reading_b20,
  reading_b21,
  reading_b30,
  reading_b31,
  reading_b40,
  reading_b41,
  reading_b50,
  reading_b51,
  reading_b60,
  reading_b61,
  reading_b70,
  reading_b71,
  reading_b80,
  reading_b81,
  reading_b90,
  reading_b91,
  ending,  // wait for 0
  check,

};
void fastRXParser_v3(streaming chanend ch)
{
  unsigned v;
  unsigned st;
  unsigned char dt;
  unsigned last;
  unsigned last_count;
  unsigned bitcount;  // max of 11 bits to process after start signal (5 x high)
  last_count = 0;
  last = 0;
  bitcount = 0;
  do
  {
    ch :> dt;
    printf("%X\n",dt);
    //wait for more than 8 ones
//    unsigned mask = 1;
//    unsigned bit = dt & mask;
//    mask<<=1;
//    if (bit | (dt & mask))

    continue;
    for (unsigned i=32;i!=0;--i)
    {
      unsigned bit = dt & 1;
      if (st >= reading_b00 && st <= ending)
      {
        //count consecutives bits.
        if (last == bit)
        {
          v <<=1;
          v |= bit;
          last = 3;
        }
        else
          last = bit;
      }
      switch (st)
      {
      case waiting_start:
        if (bit == 0) continue;
        last_count = 1;
        break;
      case reading_start:
        if (bit == 1)
        {
          last_count++;
          continue;
        }
        if (last_count < 10)
          continue;
        last = 0;
        v = 1;
        break;
      case check:
        if ((v & 0x421) != 0)
        {
          printf("e %X\n",v);
        }
        else
        {
          v = ((v >> 1) & 0x0F)  | ((v >> 5) & 0xF0);
          printf("%X\n",v);
        }
        st = waiting_start;
        continue;
        break;
      }
      st++;
    }
  }while(1);
}

[[distributable]] void fastTX_v3(server interface fast_tx tx_if,clock clk,out buffered port:8 p)
{
  configure_clock_xcore(clk,1);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  while(1)
  {
    select
    {
      case tx_if.push(unsigned char dt):
        unsigned short d = (((dt & 0xF0) << 7) | ((dt & 0x0F) << 6) | 0x1F);
        //printf(">%X\n",dt);
       // p <: d;
        p <: (unsigned char)(d & 0xFF);
        p <: (unsigned char)(d >> 8);
        p <: 0;
        break;
    }
  }

}
/*
 * 8bits are prefixed with 10 and add 14 zeros bits
 * 8 bits become 24bits
 */
[[distributable]] void fastTX_v4(server interface fast_tx tx_if,clock clk,out buffered port:8 p)
{
  configure_clock_xcore(clk,2);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  while(1)
  {
    select
    {
      case tx_if.push(unsigned char dt):
        unsigned d = 0x1 | (dt << 2);
        //printf(">%X\n",d);
        p <: (unsigned char)(d & 0xFF);
        p <: (unsigned char)(d >> 8);
        p <: 0;
        p <: 0;
        p <: 0;
        p <: 0;
        break;
    }
  }
}
/*
 * wait for pulse.
 * read data.
 * validate mask 0xFFFFF001 should return 0.
 * push 0xFFFF if mask is wrong
 */
void fastRX_v4(streaming chanend ch,in buffered port:8 p,clock clk)
{
  unsigned char dt;
  configure_clock_xcore(clk,1);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  do
  {
    p when pinsneq(0):>void;
    p :> dt;
    ch <: dt;
    p :> dt;
    ch <: dt;
    p :> dt;
    ch <: dt;
  } while(1);
}

/*
 * eight bit are received by duplicate.
 * rotate to the right by two using C
 * rotate again using destination
 *
 */

void fastRXParser_v4(streaming chanend ch)
{
  unsigned v;
  unsigned dt;
  unsigned char dt2;
  do
  {
    ch :> dt2;
    dt = dt2;
    ch :> dt2;
    dt |= (dt2 << 8);
    ch :> dt2;
    dt |= (dt2 << 16);
//    printf("%X\n",dt);
//    continue;
    // clean and validate.
    while (dt & 1)
     dt >>= 1;
    dt >>=2;
    //if (!((dt ^ (dt >> 1)) & 0x155))
    if ((dt & 0xFFFF0000) == 0)
    {
//      v = get_bit(dt,0) | get_bit(dt,1) | get_bit(dt,2) | get_bit(dt,3)
//          | get_bit(dt,4) | get_bit(dt,5) | get_bit(dt,6) | get_bit(dt,7);
      unsigned mask=1;
      v = 0;
      int i=8;
      while(i--)
      {
       dt >>= 1;
       v = v | (dt & mask);
       mask <<=1;
      }
      printf("%x \n",v);
    }
    else
      printf("e\n");
  } while (1);
}

/*
 * v5
 * In order to reduce the time to recived the data.
 * A time port of one bit is use.
 * When pin change the port counter is read
 * delta will be 1,2, 3
 * Shift delta right by 1 bring the bit to push into data.
 * delta & 3 = 3 is start.
 *
 * 3x waiting for 1
 * 3x waiting for 0
 * 2x compare again 3 and jump
 * 2x shift and add
 *
 * 3x compare,dec,jump loop
 *
 * 1x send to channel
 *
 * 32ns pulse with 2 zeros, give 30 +2x30 = 90 ns
 */
void fastRX_v5(streaming chanend ch,in port p,clock clk)
{
  int tp1,tp2;
  unsigned dt,d;
  int i;
  configure_clock_xcore(clk,11);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  i = 0;
  for(;;)
  {
    p when pinseq(1) :> void @ tp1;  // 3 ticks
    p when pinseq(0) :> void @ tp2;  // 4
    d = (tp2 - tp1);
    ch <: (unsigned char)d;
    if (d > 5)
    {
      i = 0;
      continue;
    }
    i++;
    dt = (dt << 1) | (d >> 2);
    if (i == 8)
    {
      //ch <: (unsigned char)dt;
      i = 0;
    }
  }
}

/*
 * A pulse can be as short as 80ns or even less
 * But zeros need to be long enough.
 * using 80ns(1/20) clock , the 6 zeros are 480ns
 * 1 bytes is send using 9 bytes * 9*8*80 = 5760ns
 *
 */

[[distributable]] void fastTX_v5(server interface fast_tx tx_if,clock clk,out buffered port:8 p)
{
  configure_clock_xcore(clk,8);     //40ns pulse width dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  int i;
  while(1)
  {
    select
    {
      case tx_if.push(unsigned char dt):
        i = 8;
        p <: (unsigned char)0x7;
        p <: (unsigned char)0x0;
        do
        {
          if (dt & 0x80)
            p <: (unsigned char)0x03;
          else
            p <: (unsigned char)0x01;
          dt <<=1;
          i--;
          p <: (unsigned char)0x0;  //8*4ns * 8 = 256ns
        } while(i!=0);
        break;
    }
  }
}

/*
 * v6
 * wait for 1
 * read at next, if zero then it is 1T
 * read at next, if zero the it is a 2T
 * else 3T
 */
void fastRX_v6(streaming chanend ch,in port p,clock clk)
{
  unsigned d;
  unsigned dt,i;
  configure_clock_xcore(clk,8);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  i = 0;
  for(;;)
  {
    //p when pinseq(0) :> void;  // 4
    p when pinseq(1) :> void;  // 3 ticks
    // get 3 samples, if last is 1 then start bit.
    p :>  >> d;               // 4
    p :>  >> d;
    ch <: (unsigned char)( d >> 30);
    continue;
    if (d & (1 << 31))  // size *8 - 1
    {
      // if i != 0 error
      i = 0;
      continue;
    }
    i++;
    dt <<= 1;
    if (d & (1 << 30))
    {
      dt = dt | 1;
    }
    if (i == 8)
    {
      ch <: (unsigned char)dt;
    }
  }
}
#endif
/*
 * v7
 * wait for 1 read as 8bit buffered port at 2 times freq.
 *
 * timing for a 2ns reader clock
 * 142 ns from signal high after 8 bits are read.
 *  50 ns to process start bit
 *  90 ns to parser normal bits
 * 120 ns last bit
 *
 */
void fastRX_v7(streaming chanend ch,in buffered port:8 p,clock clk,out port d1)
{
  unsigned char d;
  unsigned dt,i;
  configure_clock_xcore(clk,2);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  i = 0;
  while(1)
  {
//    d1 <: 1;
//    d1 <: 0;
    //p when pinseq(0) :> void;
    p when pinseq(1) :> void;
    p :> d;  // get next 8 bits  //
    if ( d > 64)
    {
      if (i != 0 )
        ch <: (unsigned char)0xFF;
      i = 0;    // if i !=0 then error
      continue;
    }
    dt = dt << 1; // rotate current data always. it makes space for next bit
    if ( d  > 8)
        dt = dt | 1;
    i++;
    if (i == 8)
    {
      ch <: (unsigned char)dt;
      i = 0;
    }
  }
}

/*
 * RX needs between 160 - 230 ns to parse each bit
 * it react in 46ns, 2*f need to be more than 46ns to catch 2T pulse
 * 24ns pulse produce a 192ns length byte
 * A second byte with zero is need to readch 230ns needed by rx task
 *
 * timing
 * 0 -
 * 46ns(up)
 * + 96ns read 8 bits
 * +
 *
 * 1byte = 9 * 192 = 1728ns = 0.5Mbytes sec = 4Mbits/s
 *
 * Upper limit is
 * 192ns per bit, 1728ns per byte, 578703.7bytes/sec 556.1403Kb/sec 5Mbyte/sec
 *
 * 1920ns per byte 520833bytes/sec
 */
[[distributable]] void fastTX_v7(server interface tx_if tx,clock clk,out buffered port:8 p)
{
  configure_clock_xcore(clk,6);     // 24ns
  configure_in_port(p, clk);
  start_clock(clk);
  int i;
  while(1)
  {
    select
    {
      case tx.send(const char* data,unsigned char len):
        i = 8;
        p <: (unsigned char)0x7;
        do
        {
          if (dt & 0x80)
            p <: (unsigned char)0x03;
          else
            p <: (unsigned char)0x01;
          dt <<=1;
          i--;
          //p <: (unsigned char)0x0;  //24 * 8 = 192ns
        } while(i!=0);
        p <: (unsigned char)0x0;  //24 * 8 = 192ns
        break;
    }
  }
}
/*
 * Each interface has until 8 frames to process in the router.
 */
#define frame_buffer_list_max (1 << 2)  // 4

struct frames_buffer
{
  unsigned char rd_idx;    // first element to read
  unsigned char count;     // how many elements
  struct rx_u8_buff* movable list[frame_buffer_list_max];
};


/*
 * All packet will came to this interface for deliverying
 * All TX task will be combine in one.#
 * All RX will be alone in a core
 * Command can be combine with tx also.
 */
[[distributable]] void Router_v2(server interface packet_tx_if tx_if[max_tx],server interface rx_frame_if rx_if[max_rx])
{
#define max_frame 16
  unsigned free_count;  // first free frame on list, every frame below this is null
  struct rx_u8_buff frm[max_frame];
  struct rx_u8_buff * movable free_list[max_frame] = { &frm[0],&frm[1],&frm[2],&frm[3],&frm[4],&frm[5],&frm[6],&frm[7],&frm[8],&frm[9],&frm[10],&frm[11],&frm[12],&frm[13],&frm[14],&frm[15]};
  struct frames_buffer frames[max_tx];    // frames per interface

  free_count = max_frame;
  while(1)
  {
    select
    {
    case tx_if[int _].get(struct rx_u8_buff  * movable &old_p,enum tx_task dest):
      // get first on the list
      if (old_p != 0)
      {
        free_list[free_count++] = move(old_p);
      }
      if (frames[dest].count != 0)
      {
        old_p = move(frames[dest].list[frames[dest].rd_idx]);
        frames[dest].rd_idx = (frames[dest].rd_idx + 1) & (frame_buffer_list_max -1);
        frames[dest].count--;
      }
      if (frames[dest].count != 0)
        tx_if[dest].ondata();
      break;
    case tx_if[int _].push(struct rx_u8_buff  * movable &old_p):
      free_list[free_count++] = move(old_p);
      break;
        // an input task push data, it need back a free buffer.
    case rx_if[int _].push(struct rx_u8_buff  * movable &old_p,enum tx_task j):
      if (frames[j].count != frame_buffer_list_max && free_count)
      {
        unsigned char pos = (frames[j].rd_idx + frames[j].count) & (frame_buffer_list_max -1);
        frames[j].list[pos] = move(old_p);
        frames[j].count++;
        if (frames[j].count == 1)
          tx_if[j].ondata();
        // return a free buffer
        free_count--;
        old_p = move(free_list[free_count]);
      }
      break;
    }
  }
}

/*
 * Task for tx interface.
 */
[[combinable]] void TX_Worker(client interface packet_tx_if tx_input[max_tx],client interface tx_if tx_out[max_tx])
{
  while(1)
  {
    select
    {
      case tx_input[int j].ondata():
        struct rx_u8_buff  * movable &pfrm;
        tx_input[j].get(pfrm,j);
        if (pfrm != 0)
        {
          tx_out[j].send(pfrm->dt,pfrm->len);
          tx_input[j].push(pfrm);
        }
        break;
    }
  }
}
/*
 * Create a packet from data comming from channel
 */
void RX_Packer(streaming chanend ch,unsigned timeout,client interface rx_frame_if rx_input,enum tx_task dest)
{
  struct rx_u8_buff tfrm;   // temporal frame
  struct rx_u8_buff * movable pframe = &tfrm;
  timer t;
  unsigned tp;

  while(1)
  {
    select
    {
      case ch :> unsigned char dt:
        if (pframe->len == sizeof(pframe->dt))
          pframe->overflow++;
        else
        {
          pframe->dt[pframe->len] = dt;
        }
        break;
      case pframe->len => t when timerafter(tp):> void:
        rx_input.push(pframe,dest);
        pframe->len = 0;
        pframe->overflow = 0;
        break;

    }
  }
}
