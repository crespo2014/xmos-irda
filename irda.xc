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

out port led_1 = XS1_PORT_1E;
clock    clk      = XS1_CLKBLK_1;
/*
create a clocked port for irda transmition
TODO check sync function to wait for port
use a 100/32 clock = .32us x 25 is 8us
counter can be increase by 25 or 50 it is good
Generated a pulse using N sub pulses of carrier - do not wait for last zero. - reset counter on each pulse
wait for next transition and repeat.
a timer will adjust pulse start point

SPI synchronization byte
10010001 - it is easy to known how many bits has been shifted
*/

int main()
{
  timer t;
  unsigned int tp;
  unsigned int count;
  //configure_clock_xcore(clk,2);     // 0.5ms pulse
  //configure_clock_rate(clk, 100, 80); // .8us pulse x100 80us pulse
  configure_clock_rate(clk, 100, 32); // 0.32us pulse
  configure_out_port(led_1, clk, 0);
  start_clock(clk);
  unsigned int a  = IRDA_CLK_PER_BIT;
  unsigned int b = IRDA_PULSE_PER_BIT;
  printf("%d%d\n ",a,b);
  led_1 <: 1;
  led_1 <: 0 @count;
  count += 1;
  led_1 @count <: 1;
  count += 1;
  led_1 @count <: 0;
  count += 1;
  led_1 @count <: 1;
  count += 1;
  return 0;
  led_1 @count <: 0;
  count += 1;
  led_1 @count <: 1;
  count += 1;
  led_1 @count <: 0;


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

