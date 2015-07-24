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
clock    clk      = XS1_CLKBLK_1;

#define USER_CLK_DIV    250                 //
#define USER_T_ns       (1000*1000)    //
#define USER_CLK_T_ns   (XCORE_CLK_T_ns*USER_CLK_DIV) // T of clock
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
*/

int main()
{
  timer t;
  unsigned int tp,tp2,tp3;
  int p;
  int count1,count2,count;
  configure_clock_xcore(clk,USER_CLK_DIV);     // dividing clock ticks
  //configure_clock_rate(clk, 100, 128);
  configure_in_port(led_1, clk);
  start_clock(clk);
  //printf("%d %d %d %d\n ",IRDA_CLK_T_ns,IRDA_CARRIER_CLK,IRDA_CLK_PER_BIT,IRDA_PULSE_PER_BIT);
  printf("%d %d %d %d\n",USER_CLK_T_ns,USER_CLK_PER_T,0,0);
  t :> tp;
//  led_1 :> p @ count1;
//  t when timerafter(tp+100*us) :> void;
//  led_1 :> p @ count2;
//  t :> tp2;
  printf("%d \n",100*1000/USER_CLK_T_ns);
  printf("%d \n",count2-count1);

//  led_1 <: 0 @ count1;
//  count1 += 2;
//  led_1 @ count1  <: 0 ;
//  sync(led_1);
//  t :> tp2;
//  printf("%d \n",tp2-tp);
//
//
//  tp += us;
//  t when timerafter(tp) :> void;
//  led_1 <: 0 @ count2;
//  tp += us;
//  t when timerafter(tp) :> void;
//  led_1 <: 0 @ count;
//  printf("%d \n",count2-count1);
//  printf("%d \n",count-count2);
//  return 0;
//
//
  led_1 <: 0 @ count;
  for(;;)
  {
    t :> tp;
    // 1000 ms
    for (int i=1000;i !=0;--i)
    {
      count += (USER_CLK_PER_T);
      led_1 @count <: 1;
    }
    for (int i=1000;i !=0;--i)
    {
      count += (USER_CLK_PER_T);
      led_1 @count <: 0;
    }
//    sync(led_1);
    t :> tp3;
    //printf("%d %d\n",tp2-tp,tp3-tp);
  }
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

//  IRDA_CLK_PULSE(led_1,count,10);
//
//  t :> tp;
//  //for (;;)
//  {
//    unsigned int len = 4*IRDA_BIT_LEN;
//    IRDA_PULSE(27*us,tp,len,t,led_1,1,0);
//    tp += 500*ms;
//    t when timerafter(tp) :> void;
//    len = IRDA_BIT_LEN;
//    IRDA_PULSE(27*us,tp,len,t,led_1,1,0);
//    tp += 500*ms;
//    t when timerafter(tp) :> void;
//  }
//  return 0;
}

