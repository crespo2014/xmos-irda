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

/*
 * Combinable Irda tx function using buffered clocked port
 * States :
 * Idle
 * Sending (generating pulse, waiting for next pulse)
 */
//[[combinable]]
void irda_32b_tx_comb(/*client interface tx_rx_if tx_if,*/out buffered port:32 tx)
{
//  struct tx_frame_t frm;
//  struct tx_frame_t* movable pfrm = &frm;
  unsigned int bitmask,data;    // bitmask indicate currently sending bits
  unsigned int pulsecount;      // how many pulse to send
  unsigned int pv;
  timer t;
  unsigned int tp,tp_bit_start;
  unsigned char bits,sending;   // how many bits are we sending

  printf("%d %d %d %d\n",IRDA_32b_CLK_DIV,IRDA_32b_CARRIER_T_ns,IRDA_32b_BIT_LEN,IRDA_BIT_ticks);
  pv = IRDA_32b_WAVE;
  sending = 1;
  bitmask = (1 << 2);
  data = 0x55;
  bits = 4;
  pulsecount = bits*IRDA_32b_BIT_LEN;
  t :> tp;
  tp += IRDA_32b_WAVE_ticks;
  tp_bit_start = tp;

  while(1)
  {
    select
    {
      case sending !=0 => t when timerafter(tp) :> void:
        tx <: pv;
        if (pulsecount != 0)  // send next pulse
        {
          pulsecount--;
          tp += IRDA_32b_WAVE_ticks;
          pv = IRDA_32b_WAVE;
          break;
        }
        if (bits != 0)    // send stop bit
        {
          tp += IRDA_32b_WAVE_ticks;
          pv = IRDA_32b_WAVE_BLANK;
          tp_bit_start = tp_bit_start + (bits + 1)* IRDA_BIT_ticks;
          bits = 0;
          break;
        }
        tp = tp_bit_start;
        if (bitmask != 0)     // send data bits
        {
          pv = IRDA_32b_WAVE;
          bits = (data & bitmask) ? 2 : 1;
          pulsecount = bits*IRDA_32b_BIT_LEN;
          bitmask >>=1 ;
          break;
        }
        if (sending == 1)
        {
          // no more bits, one stop already sent, we need two more stops
          pv = IRDA_32b_WAVE_BLANK;
          tp = tp_bit_start + 2*IRDA_BIT_ticks;
          sending = 2;    // next time go to idle
          break;
        }
        sending = 0;    // end
        return;
    }
  }
}

/*
 * irda tx data supplier example
 */
void irda_tx_source(server interface irda_tx_if tx)
{
  unsigned int buff[4];
  unsigned char rd,wr,i;
  timer t;
  unsigned int tp;
  rd = 0;
  wr = 0;
  i = 0;
  t :> tp;
  tp += sec;
  while(1)
  {
    select
    {
      case tx.get(struct irda_tx_frame  * movable &old_p) -> unsigned char b :
        if (rd == sizeof(buff)/sizeof(*buff) && rd != wr)
           rd = 0;
        if (rd != wr)
        {
          //data = buff[rd];
          rd++;
          b = 1;
        }
        else
          b = 0;
        break;
      case t when timerafter(tp):> void:
        if (wr == sizeof(buff)/sizeof(*buff)  && rd != 0)
        {
          wr = 0;
        }
        if (rd != wr && wr != sizeof(buff)/sizeof(*buff))
        {
          buff[wr] = i++;
          wr++;
        }
        break;
    }
  }
}

void dummy_irda_tx_source(server interface irda_tx_if tx)
{

}
/*
 * Combinable irda tx fucntion using a timer
 * - produce many pulses and pick the next bit to send
 * - wait for more data
 * - sending status is hold until the stop bit is send
 *
 * out port is always swtiching bettween 1 and 0 to generated the carrier, except for stop bit
 */
void irda_tx_timed(/*client interface irda_tx_if tx,*/out port TX,unsigned char low,unsigned char high)
{
    struct irda_tx_frame frm;
    //struct irda_tx_frame* movable pfrm = &frm;
    unsigned char bitmask,pos;
    unsigned pulse;   // how many pulse to send
    unsigned char pv; // next port value - it reduce transition time
    unsigned char bits;   // bits to send.
    timer t;
    unsigned int tp,pulse_tp;   // time of start pulse
    unsigned int data;          // data to send max 32 bits (8x4bytes - 3 serial bytes max)
    //
    t :> tp;
    TX <: high;
    pulse_tp = tp;
    tp += IRDA_CARRIER_TON_ticks;
    pv = low;
    bitmask = (1<<3);
    bits = 4;
    pulse = 4*IRDA_PULSE_PER_BIT-1;
    pos = 0;
    data = 0x55;
//    sending = 0;
//    pos = 0xFF;
//    pv = 0;
//    data = 0x55;
//    TX <: low;
    while(1)
    {
      select
      {
//        case pos == 0xFF => tx.ondata():
//            if (tx.get(data) == 1)
//            {
//              t :> tp;
//              TX <: high;
//              pulse_tp = tp;
//              pv = low;
//              bitmask = (1<<7);
//              pulse = 4*IRDA_PULSE_PER_BIT-1;
//              pos = 0;
//            }
//            break;
        case pos != 0xFF => t when timerafter(tp) :> void:
            TX <: pv;
            if (pv == high)
            {
              pulse--;
              tp += IRDA_CARRIER_TON_ticks;
              pv = low;
            }
            else // Toff zone
            {
              if (pulse == 0) // no more pulses 1 low bits needed
              {
                if (bitmask == 0)  // all bits + stop have been sent
                {
                  pos = 0xFF;
                  return ;
//                  if (tx.get(data) == 1)
//                  {
//                    t :> tp;
//                    TX <: high;
//                    pulse_tp = tp;
//                    pv = low;
//                    bitmask = (1<<7);
//                    pulse = 4*IRDA_PULSE_PER_BIT-1;
//                    pos = 0;
//                  }
                }
                else
                {
                  tp = pulse_tp + (bits+1)*IRDA_BIT_ticks;
                  bitmask >>= 1;
                  if (bitmask == 0)  // no more bits to send
                  {
                    tp = pulse_tp + (bits+3)*IRDA_BIT_ticks;
                  }
                  else
                  {
                    pulse_tp = pulse_tp + (bits+1)*IRDA_BIT_ticks;
                    bits = ((data & bitmask) == bitmask) ? 2 : 1;
                    pulse = bits*IRDA_PULSE_PER_BIT;
                    pv = high;
                    tp = pulse_tp;
                  }
                }
              }
              else
              {
                tp += IRDA_CARRIER_TOFF_ticks;
                pv = high;
              }
            }
            break;
      }
    }

}

//void test_combinable()
//{
//  interface irda_tx_if if1;
//  par
//  {
//    irda_tx_timed(if1,led_1,0,1);
//    dummy_irda_tx_source(if1);
//  }
//}

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

void readIRDA(in port p, chanend c)
{

  int t0 = 0;
  int t1 = 0;

  unsigned char val = 0;
  timer tm;
  p :> val
  ;
  tm :> t1
  ;
  printf("%d\n", val)
  ;
  for (;;)
  {
    // wait for 0
    p when pinseq(0) :> void;
    tm :> t0;
    // wait for 1
    p when pinseq(1) :> void;
    tm :> t1;
    t0 = t1 - t0;
    p when pinseq(0) :> val;

    // wait 1 or 1.5

    c <: (t0-t1);

    c <: (t1-t0);
    //        p when pinseq(0) :> void;
    //        tm :> te;
    //        c <: (te - t1);
    //        p when pinseq(1) :> void;

    //        select {
    //            case p when pinsneq(val) :> val:
    //            tm :> te;
    //            if (val == 1)
    //            {
    //                t0 = te-tb;
    //            }
    //            else
    //            {
    //                t1 = te-tb;
    //                c <: (t0 + t1);
    //            }
    //            tb = te;
    //            break;
    //        }
  }
}

/**
 * pins is normaly at level 1
 * when go to 0 and go back to 1 . The lenght of this pulse is a reference for the next
 * the next pulse could be < 1.5T means 0
 * from 1.5 to 2.5 means 1
 * from 2.5 to 4.5 means start pulse
 * more than 4.5 means end.
 */

void readIRDA_v2(in port p, chanend c)
{
  int te = 0;
  int t = 0;
  unsigned char val = 0;
  timer tm;
  p :> val
  ;
  printf("%d\n", val)
  ;
  for (;;)
  {
    // wait for 0
    p when pinseq(0) :> void;
    tm :> t;
    // wait for end of pulse
    p when pinseq(1) :> void;
    tm :> te;
    t = te - t;
    //wait for next pulse
    p when pinseq(0) :> void;
    // wait end or 1.5T
    select
    {
      case tm when timerafter(te + t + t/2) :> void:
      break;
      case p when pinseq(1) :> void:
      c <: '0';
      continue;
      break;
    }
    // wait end or 2.5T
    select
    {
      case tm when timerafter(te + t*2 + t/2) :> void:
      break;
      case p when pinseq(1) :> void:
      c <: '1';
      continue;
      break;
    }
    // wait end or 4.5T
    select
    {
      case tm when timerafter(te + t*4 + t/2) :> void:
      break;
      case p when pinseq(1) :> void:
      c <: '3';
      continue;
      break;
    }
    // so long 0
    p when pinseq(1) :> void;
    c <: '2';
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

/**
 * IRDA using a base frecuency of 60 000 cycles = 6ns
 *
 * more than 10T means reset and wait for 7T
 * > 4T
 */
void IRDA_base_freq(in port p, chanend c)
{
  timer tm;
  int t, te = 0;
  char started = 0; // 1 means start received
  const unsigned freq_tick = 60 * 1000;
  for (;;)
  {
    started = 0;
    // wait for first 0 it will be 15T
    p when pinseq(0) :> void;
    for (;;)
    {
      //wait for first 1 ; ignore previous zero
      p when pinseq(1) :> void;
      tm :> t;
      // wait 0 no more than 8T, normally is 7T that means started
      select
      {
        case tm when timerafter(t + freq_tick * 10) :> void:
        c <: 'T';
        break;
        case p when pinseq(0) :> void:
        tm :> te;
        // check length of 1
        t = (te - t) / freq_tick;
        if (t > 3)
        {
          started = 1;
          c <: 'S';
        }
        //                else if (started == 0)
        //                c <: 'E';
        else if (t >= 2)
        c <: '1';
        else
        c <: '0';
        continue;
        break;
      }
      break; // if 0 length is > 2T then restart
    }
    p when pinseq(0) :> void;

  }
}

void IRDA_freq_mul(in port p, chanend c)
{
  const unsigned freq_tick = 60 * 1000;
  char val;
  timer tm;
  int ts, te = 0;
  p :> val
  ;
  tm :> ts
  ;
  printf("%d\n", val)
  ;
  for (;;)
  {
    p when pinsneq(val) :> val;
    tm :> te;
    c <: (te - ts) / freq_tick;
    ts = te;
  }
}

void printTime_v2(chanend c) {
    char t1;
    while (1) {
        c :> t1;
        printf(t1 == '2' ? "\n" : t1 == '3' ? "\nS" : t1 == '1' ? "1" : "0");
    }
}
void printTime(chanend c) {
    int t0, t1;
    while (1) {
        c :> t1;
        printf("1 %d T %d \n", t1, t1 + t0);
        c :> t0;
        printf("0 %d ", t0);
    }
}

void print_i(chanend c) {
    int t1;
    while (1) {
        c :> t1;
        printf("%d\n", t1);
    }
}

void print_u(chanend c) {
    unsigned t1;
    while (1) {
        c :> t1;
        printf("%u\n", t1);
    }
}

void print_us(chanend c)
{
  unsigned t1;
  while (1) {
      c :> t1;
      printf("%uus\n", t1*SYS_TIMER_T_ns/1000);
  }
}
void print_b(chanend c) {
    unsigned t1;
    while (1) {
        c :> t1;
        do {
            printf("%d", t1 % 2);
            t1 /= 2;
        } while (t1);
        printf("\n");
    }
}



void print_char(chanend c) {
    char t1;
    while (1) {
        c :> t1;
        if (t1 == 'E' || t1 == 'S')
            printf("\n");
        printf("%c", t1);

    }
}

void print_none(chanend c)
{
  unsigned t1;
  while (1) {
          c :> t1;
  }
}


void test_32bits_irda(clock clk,out buffered port:32 p32,out port clk_out)
{
  configure_clock_xcore(clk,IRDA_32b_CLK_DIV);     // dividing clock ticks
  configure_in_port(p32, clk);
  configure_port_clock_output(clk_out, clk);
  start_clock(clk);
  printf("%d %d %d %d\n",IRDA_32b_CLK_DIV,IRDA_32b_CARRIER_T_ns,IRDA_32b_BIT_LEN,IRDA_BIT_ticks);
  SONY_IRDA_32b_SEND(0x5555,4,p32);
  sync(p32);
}

void test_clocked_irda(clock clk,out port p)
{
  configure_clock_xcore(clk,IRDA_XCORE_CLK_DIV);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  SONY_IRDA_CLOCKED_SEND(0x55,8,t,p,1,0);
}

void test_system(clock clk,out port p,in port in_p)
{
  chan c;
  configure_clock_xcore(clk,IRDA_XCORE_CLK_DIV);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);

  par
  {
    //irda_RX(irda_rx,gpio_irda_rx,IRDA_BIT_LEN_ns/SYS_TIMER_T_ns,0,fault);
    //irda_cmd(irda_rx,fault);
    irda_send_loop(p);
    IRDA_delta(in_p,c);
    print_us(c);
  }
}

void serial_send_test(clock clk,out port p)
{
  configure_clock_xcore(clk,UART_XCORE_CLOCK_DIV);     // dividing clock ticks
  configure_in_port(p, clk);
  start_clock(clk);
  p <: 1;   // initial state
  
  UART_CLOCKED_SEND(p,0xFF,1,1,0);
  UART_CLOCKED_SEND(p,0x00,1,1,0);
  sync(p);
}

//void test_xscope()
//{
//  xscope_register(2,
//             XSCOPE_CONTINUOUS, "Continuous Value 1", XSCOPE_INT, "Value",
//             XSCOPE_CONTINUOUS, "Continuous Value 2", XSCOPE_INT, "Value");
//  xscope_enable();
//  unsigned int i;
//  timer t;
//  unsigned tp;
//  t :> tp;
//  for (tp=2;tp !=0;)
//  {
//    //tp += sec;
//    //t when timerafter(tp) :> void;
//    for (i = 0; i < 100; i++) {
//      xscope_int(0, i);
//      xscope_int(1, i/2 /*(i>50) ? -i : i*/ );
//    }
//  }
//}

// TODO irda send can be blocking task for cmd interface., also it can be distributable and it will be use for everybody. using clocked port will be simple
#endif
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
      case tx.send(const char* data,unsigned char len):
        if (len == 5)
        {
          unsigned bitcount = *data++;
          unsigned v= 0;
          while (--len)
          {
            v = (v << 8) | (*data++);
          }
          SONY_IRDA_32b_SEND(v,bitcount,p32);
          sync(p32);
        }
        break;
    }
  }
}
/*
 * irda rx task.
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
        if (pv_length == 0)   //ignored tansition
        {
         reading = 1;
         tp += bitlen/2;
        }
        else if (pv == 1 && bitcount) // only use 0 to 1 transition and after start
        {
            bitcount++;
            v = v << 1;
            if (pv_length > 2)
              v = v | 1;
        }
        break;
      case reading => t when timerafter(tp):> void:
        pv_length++;
        if (pv_length > 7)  // start or stop
        {
          if (pv == 1)  // stop condition
          {
            if (bitcount > 1)
            {
              pframe->dt[0] = cmd_irda_input;
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
        }
        break;
    }
  }


}
