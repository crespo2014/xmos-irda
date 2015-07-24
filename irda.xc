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

out port led_1 = XS1_PORT_1D;
out port clk_pin = XS1_PORT_1G;
clock    clk      = XS1_CLKBLK_1;

#define USER_CLK_DIV    255                 //
#define USER_T_ns       (1000*1000*1000)    //
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

int main()
{
  timer t;
  configure_clock_xcore(clk,1);     // dividing clock ticks
  //configure_clock_rate(clk, 100, 128);
  configure_in_port(led_1, clk);
  //configure_port_clock_output(clk_pin, clk);

  start_clock(clk);
  printf("%d %d %d %d\n ",IRDA_CLK_T_ns,IRDA_CARRIER_CLK,IRDA_CLK_PER_BIT,IRDA_PULSE_PER_BIT);
  printf("%d %d %d %d\n",USER_CLK_T_ns,USER_CLK_PER_T,0,0);

  IRDA_BIT_v1(led_1,1,1,0);
  IRDA_BIT_v1(led_1,2,1,0);
  IRDA_BIT_v1(led_1,4,1,0);
  return 0;

  SONY_IRDA_SEND(0x55555,2,t,led_1,1,0);

//
//  for (;;)
//  {
//  IRDA_BIT_v1(led_1,1,1,0);
////  tp += 1*sec;
////  t when timerafter(tp) :> void;
//  IRDA_BIT_v1(led_1,2,1,0);
////  tp += 1*sec;
////  t when timerafter(tp) :> void;
//  }

  return 0;
}

