/*
 * main.xc
 *
 *  Created on: 13 Aug 2015
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

out port led_1 = XS1_PORT_1G;
out port led_2 = XS1_PORT_1D;
in port gpio_irda_rx = XS1_PORT_1H;

out buffered port:32 irda_32  = XS1_PORT_1O;
out port clockOut  = XS1_PORT_1N;

//out port clk_pin = XS1_PORT_1G;
clock    clk      = XS1_CLKBLK_1;

void serial_test(client interface serial_tx_if tx,chanend rx_c,client interface serial_rx_if rx)
{
  unsigned char dt;
  tx.push(0x55);
  while(1)
  {
    select
    {
      case 0 => tx.ready():
        break;
      case rx_c :> dt:
        printf("%d\n",dt);
        break;
      case rx.error():
        rx.ack();
        break;
    }
  }
}

void main_serial()
{
  chan rx_c;
  interface serial_tx_if tx;
  interface serial_rx_if rx;
  par
  {
    serial_test(tx,rx_c,rx);
    serial_rx_cmb(gpio_irda_rx,rx_c,rx);
    serial_tx_timed_cmb(tx,led_2);

  }

}

int main_irda_clocked_tx(clock clk,out buffered port:32 p32)
{
  configure_clock_xcore(clk,IRDA_32b_CLK_DIV);     // dividing clock ticks
   configure_in_port(p32, clk);
   configure_port_clock_output(clockOut, clk);
   start_clock(clk);
  irda_32b_tx_comb(p32);
  sync(p32);
  //irda_tx_timed(led_1,0,1);
  //test_combinable();
  return 0;
}


int main()
{
  main_serial();
  return 0;
}
