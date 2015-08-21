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

in port p = XS1_PORT_4A;
out port p2 = XS1_PORT_4B;
out port pc = XS1_PORT_4C;
out port pd = XS1_PORT_4D;

//in port gpio_irda_rx = XS1_PORT_1H;
out port gpio_fault = XS1_PORT_32A;

out buffered port:32 irda_32  = XS1_PORT_1O;    //LSb to MSB
out port clockOut  = XS1_PORT_1N;

//out port clk_pin = XS1_PORT_1G;
clock    clk      = XS1_CLKBLK_1;

out buffered port:8 tx_16  = XS1_PORT_1P;

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
        buff.push("OK\r\n>",5);
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



int main3()
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
  p_1G <: 0;
  //irda_tx_timed(led_1,0,1);
  //test_combinable();
  return 0;
}

/*
 * Use internal timer for timeouts.
 * use port timer for transitions timed.
 */
interface in_port_if
{
  [[notification]] slave void onChange();
//  [[clears_notification]] void get(unsigned char& dt,unsigned int& tp);
  [[clears_notification]] unsigned char getPort();
  //void trackingOn();
  //void trackingOff();
};

void waitport(in port p/*,server interface in_port_if cmd[2]*/,streaming chanend c[])
{
  unsigned char pv,pv1;
  unsigned int tp;
  timer t;
  p :> pv;
  t :> tp;
  while(1)
  {
    select
    {
//       case cmd[int i].getPort()-> unsigned char ret:
//         ret = pv;
//         break;
      case p when pinsneq(pv):> pv1:
        p_1G <: 1;
        t :> tp;
        unsigned char mod = pv1 ^ pv;
        int i =0;
        while (mod !=0 && i <2)
        {
          if (mod & 1) c[i] <: pv;
          mod >>=1;
          ++i;
        }
        pv = pv1;
        p_1G <: 0;
        break;
//      case cmd[int i].get(unsigned char& dt,unsigned int& tp_):
//        dt = tp;
//        tp_= tp;
//        break;
    }
  }
}

void testport(client interface in_port_if cmd,out port p)
{
  while(1)
  {
    select
    {
      case cmd.onChange():
        unsigned char v = cmd.getPort();
        p <: v;
        break;
    }
  }
}

void testport_v2(streaming chanend ch,out port p)
{
  while(1)
  {
    select
    {
      case ch :> unsigned char v:
        p <: v;
        break;
    }
  }
}


void portUpdate(out port p)
{
  unsigned char v;
  unsigned int tp;
  v = 0;
  timer t;
  t :> tp;
  while(1)
  {
    select {
      case t when timerafter(tp) :> void:
        p <: v;
        v++;
        tp += us;
        break;
    }
  }
}

/*
 * Test done
 * 620ns to propagate from one port to another with only one task
 * two task give it 1us, but second task lost transitions
 *
 * Using channels there is not lost of data, but response time is long
 *
 * 60ns to detect port changes
 */
/*
int main()
{
  streaming chan c[2];
  //interface in_port_if ip[2];
  par
  {
      portUpdate(p2);
      testport_v2(c[0],pc);
      testport_v2(c[1],pd);
      waitport(p,c);
  }
  return 0;
}
*/

// test the fastest communication
void send_fast_loop(out buffered port:8 p16,clock clk)
{
  configure_clock_xcore(clk,4);     // dividing clock ticks
  configure_in_port(p16, clk);
  //configure_port_clock_output(clk_out, clk);
  start_clock(clk);
  timer t;
  unsigned int tp;
  while(1)
  {
    select
    {
      case t when timerafter(tp) :> void:
        p16 <:  (unsigned char)0x55;
        p16 <:  (unsigned char)0x00;
        tp += (10*us);
        break;
    }
  }
}

void print_h(streaming chanend c) {
    unsigned char t1;
    while (1) {
        c :> t1;
        printf("%x\n", t1);
    }
}

void recv_fast_loop(in port p,streaming chanend c)
{
  unsigned int dt;
  unsigned char d[8];
  while(1)
  {
    select
    {
      case p when pinseq(1) :> void:
        p :> d[0];
        p :> d[1];
        p :> d[2];
        p :> d[3];
        p :> d[4];
        p :> d[5];
        p :> d[6];
        p :> d[7];
        unsigned idx =8;
        dt = 0;
        do
        {
          --idx;
          dt = dt*2 + d[idx];
        } while (idx !=0);
        c <: (unsigned char)dt;
        break;
    }
  }
}

int main()
{
  streaming chan c;
  par {
    send_fast_loop(tx_16,clk);
    recv_fast_loop(pi_1H,c);
    print_h(c);
  }
  return 0;
}

