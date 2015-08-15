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

out port p_1G = XS1_PORT_1G;
out port p_1D = XS1_PORT_1D;
in port pi_1H = XS1_PORT_1H;
out port po_1I = XS1_PORT_1I;
in port p_1K = XS1_PORT_1K;
out port p_1B = XS1_PORT_1B;
in port p_1A = XS1_PORT_1A;
out port po_1F = XS1_PORT_1F;
out port p_1C = XS1_PORT_1C;

//in port gpio_irda_rx = XS1_PORT_1H;
out port gpio_fault = XS1_PORT_32A;

out buffered port:32 irda_32  = XS1_PORT_1O;
out port clockOut  = XS1_PORT_1N;

//out port clk_pin = XS1_PORT_1G;
clock    clk      = XS1_CLKBLK_1;

[[combinable]] void serial_test(client interface serial_tx_if tx,
    streaming chanend rx_c,client interface serial_rx_if rx)
{
  unsigned char dt;
  timer t;
  unsigned tp;
  t :> tp;
  tp += sec;
  while(1)
  {
    select
    {
      case t when timerafter(tp) :> void:
        tx.push('H');
        tp += sec;
        break;
      case tx.ready():
        printf(".\n");
        break;
      case rx_c :> dt:
        printf("%c\n",dt);
        break;
      case rx.error():
        rx.ack();
        break;
    }
  }
}

[[combinable]] void serial_test_v2(
    streaming chanend rx_c,
    streaming chanend tx_c,
    client interface serial_rx_if rx,
    client interface serial_tx_v2_if tx)
{
  unsigned char dt;
  timer t;
  unsigned tp;
  t :> tp;
  tp += sec;
  while(1)
  {
    select
    {
      case t when timerafter(tp) :> void:
        tx_c <: (unsigned char) 'O';
        tx_c <: (unsigned char) 'K';
        tx_c <: (unsigned char) '\n';
        tp += sec;
        break;
      case rx_c :> dt:
        printf("%c\n",dt);
        break;
      case tx.overflow():
        printf(".\n");
        tx.ack();
        break;
      case rx.error():
        printf("?\n");
        rx.ack();
        break;
    }
  }
}

int main1()
{
  streaming chan rx_c;
  interface serial_tx_if tx;
  interface serial_rx_if rx;
  par
  {
    serial_test(tx,rx_c,rx);
    [[combine]] par
    {
    serial_rx_cmb(pi_1H,rx_c,rx,po_1I);
    serial_tx_timed_cmb(tx,po_1F);
    }
  }
  return 0;
}

int main2()
{
  streaming chan rx_c;
  streaming chan tx_c;
  interface serial_rx_if rx;
  interface serial_tx_v2_if tx;
  par
  {
    serial_test_v2(rx_c,tx_c,rx,tx);
    [[combine]] par
    {
    serial_rx_cmb(pi_1H,rx_c,rx,po_1I);
    serial_tx_ctb(tx_c,tx,po_1F);
    }
  }
  return 0;
}

/*
 * Command dummy.
 * reply prompt on enter and ok if there is data
 */
void serial_cmd(
    client interface serial_tx_v2_if tx,
    client interface buffer_v1_if buff,
    client interface serial_rx_if rx)
{
  struct tx_frame_t rx_buff;
  struct tx_frame_t  * movable rx_ptr = &rx_buff;
  buff.push(">",1);
  while(1)
  {
    select
    {
      case buff.onRX():
        buff.get(rx_ptr);
        buff.push("OK\n\r>",5);
//        tx_c <: (unsigned char)'O';
//        tx_c <: (unsigned char)'K';
//        tx_c <: (unsigned char)'\n';
//        tx_c <: (unsigned char)'\r';
//        tx_c <: (unsigned char)'>';
        break;
      case tx.overflow():
        tx.ack();
        printf("tx\n");
        break;
      case rx.error():
        printf("rx\n");
        rx.ack();
        break;
    }
  }

}



int main()
{
  streaming chan rx_c;
  streaming chan tx_c;
  interface serial_rx_if rx;
  interface serial_tx_v2_if tx;
  interface buffer_v1_if   buff;
  par
  {
    buffer_v1(buff,rx_c,tx_c);
    serial_cmd(tx,buff,rx);
    [[combine]] par
    {
    serial_rx_cmb(pi_1H,rx_c,rx,po_1I);
    serial_tx_ctb(tx_c,tx,po_1F);
    }
  }
  return 0;
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


