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

int main1()
{
  timer t;
  unsigned int tp;
  t :> tp;
  for (;;)
  {
    unsigned int len = 4*IRDA_BIT_LEN;
    IRDA_PULSE(27*us,tp,len,t,led_1,1,0);
    tp += 500*ms;
    t when timerafter(tp) :> void;
    len = IRDA_BIT_LEN;
    IRDA_PULSE(27*us,tp,len,t,led_1,1,0);
    tp += 500*ms;
    t when timerafter(tp) :> void;
  }
  return 0;
}

