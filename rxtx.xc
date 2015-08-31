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
 * RX is combinable
 */

void fastRX(streaming chanend ch,in port p)
{
  timer t;
  while(1)
  {
    unsigned int tp1,tp2;
    p when pinseq(1) :> void;  // 3 ticks
    t :> tp1;                  // 2 ticks
    p when pinseq(0) :> void;
    t :> tp2;
    ch <:(unsigned char)(tp2-tp1);
  }
}

/*
 * Read until 5 ones.
 * then keep going
 * this function works fine with a 20ns pulse width. but it is hard to decode a pulse length data
 */
void fastRX_v2(streaming chanend ch,in port p)
{
  timer t;
  unsigned char v;
  unsigned dt;
  while(1)
  {
    unsigned int tp1,tp2;
    dt = 0;
    v =0;
    p when pinseq(1) :> void;  // 3 ticks
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;
    p :> >>dt;     // 1 tick
    //ch <:(unsigned char)(dt);  // 1 tick
    printf("%X\n",dt);
  }
}

void fastRXParser(streaming chanend ch)
{
  unsigned d;
  unsigned dt;
  unsigned char buff[30];
  unsigned pos;
  unsigned i;
  dt = 0;
  i = 0;
  pos = 0;
  while(1)
  {
    ch :> d;
    if (d > 8)
    {
      if (i == 8)
      {
        buff[pos++] =dt;
        if (pos == 30)
        {
          do
          {
            printf("x%X ",buff[--pos]);
          }while(pos);
          printf("\n");
        }
      }
      i = 0;
      dt = 0;
    }
    else
    {
      dt <<=1;
      if (d > 6) dt |= 1;
      i++;
    }
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
  configure_clock_xcore(clk,5);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  while(1)
  {
    select
    {
      case tx_if.push(unsigned char dt):
        unsigned int d = 0;
//        for (int i=0;i<8;++i,dt>>=1)
//        {
//          if (dt & 1)
//          {
//            d<<= 3;
//            d|=6;
//          }
//          else
//          {
//            d<<= 2;
//            d|=2;
//          }
//        }
//        d <<= 4;
//        d |= 14;
        d = dt;
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
