/*
 * irda.xc
 *  Implement a generic irda receiver
 *  Frame length need to be define plus storing data order
 *  4bits + 4bits + 8bits
 *  Data can be store in 8 bits units until fame size
 *
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

out port led_1 = XS1_PORT_1G;
in port gpio_irda_rx = XS1_PORT_1H;

//out port clk_pin = XS1_PORT_1G;
clock    clk      = XS1_CLKBLK_1;

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

void irda_send_loop()
{
  timer t;
  unsigned tp;
  for (;;)
   {
   SONY_IRDA_SEND(0x55,8,t,led_1,1,0);
   t :> tp;
   t when timerafter(tp+sec) :> tp;
   }
}

void irda_cmd(client interface tx_rx_if irda_rx,server interface fault_if fault)
{
  struct tx_frame_t   frm;
  struct tx_frame_t* movable p = &frm;
  while(1)
  {
    select
    {
      case irda_rx.ondata():
      while (irda_rx.get(p) == 1)
      {
        unsigned int v = 0;
        for (int i= 3;i< p->len;++i)
        {
          v <<= 8;
          v += p->dt[i];
        }
        printf("%X\n",v);
      }
      break;
    }
  }
}

int main()
{
  interface tx_rx_if irda_rx;
  interface fault_if fault;

  configure_clock_xcore(clk,USER_CLK_DIV);     // dividing clock ticks
  configure_in_port(led_1, clk);
  //configure_port_clock_output(clk_pin, clk);
  start_clock(clk);

  par
  {
    irda_RX(irda_rx,gpio_irda_rx,IRDA_BIT_LEN_ns/SYS_TIMER_T_ns,0,fault);
    irda_cmd(irda_rx,fault);
  }

//  sync(led_1);
//  t :> tp;
//  led_1 <: 0 @count;
//  count++;
//  led_1 <: 0 @count;
//  t :> tp2;
//  printf("%d\n",tp2-tp);
//
//  for (;;)
//  {
//    for (int i =500;i>0;--i)
//    {
//    count += USER_CLK_PER_T;
//    led_1 @count <: 1;
//    }
//    for (int i =500;i>0;--i)
//    {
//    count += USER_CLK_PER_T;
//    led_1 @count <: 0;
//    }
//  }
  return 0;
}

