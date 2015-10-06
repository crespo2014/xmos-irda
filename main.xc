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
#include <safestring.h>
#include "irda.h"
#include "serial.h"
#include "cmd.h"
#include "i2c_custom.h"
#include "spi_custom.h"
#include "mcp2515.h"
#include "utils.h"


void print_buff(const char* buff,unsigned len)
{
  while (len--)
    printf("%02X ",*buff++);
  printf("\n");
}

void print_ascii_buff(const char* buff,unsigned len)
{
  while (len--)
    printf("%c",*buff++);
  printf("\n");
}
/*
out port p_1G = XS1_PORT_1G;


in port p_1K = XS1_PORT_1K;


in port p = XS1_PORT_4A;
out port p2 = XS1_PORT_4B;
out port pc = XS1_PORT_4C;
port pd = XS1_PORT_4D;

out port uart_tx_p = XS1_PORT_1P;
in port  uart_rx_p = XS1_PORT_1H;

out port gpio_fault = XS1_PORT_32A;




out buffered port:32 irda_32  = XS1_PORT_1B;    //LSb to MSB

out port clockOut  = XS1_PORT_1N;


*/

//
/*
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
*/
/*
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
*/
/*
int main()
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
*/

/*
 * send ok every second
 */
/*
int main()
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
*/

/*
 * Command dummy.
 * reply prompt on enter and ok if there is data
 */
/*
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
*/

/*
 * Buffered serial input with command prompt reply
 */
/*
int main_123()
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
    serial_rx_cmb(uart_rx_p,rx_c,rx,po_1I);
    serial_tx_ctb(tx_c,tx,p_1F);
    }
  }
  return 0;
}
*/
/*

*/

/*
 * This function is optimize.
 * printf is called only ones. using two jump
 * a different argument is passed
 */
/*
int main_opt()
{
  int i;
  p_1K :> i;
  switch(i)
  {
  case 0:printf("1");
  break;
  case 1:printf("2");
  break;
  case 2:printf("3");
  break;
  case 3:printf("4");
  break;
  case 4:printf("5");
  break;
  case 5:printf("6");
  break;
  }
  return 0;
}
*/
/*
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
*/

/*
 * Use internal timer for timeouts.
 * use port timer for transitions timed.
 */
/*
interface in_port_if
{
  [[notification]] slave void onChange();
//  [[clears_notification]] void get(unsigned char& dt,unsigned int& tp);
  [[clears_notification]] unsigned char getPort();
  //void trackingOn();
  //void trackingOff();
};


void waitport(in port p,streaming chanend c[])
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
*/

/*
 * Signal when a data is received in a channel
 */
void channel_signal(streaming chanend ch,out port p)
{
  unsigned char d;
  unsigned char w = 0;
  while(1)
  {
    p <: 0;
    ch :> d;
    p <: 1;
    if ((d == 0xFF) && (d != w)) printf("e %d\n",w);   // try with hardware, because it is taking so long
    w++;
  }
}
/*
 * use as test interface to push commands to router
 */
[[combinable]] void command_pusher(client interface rx_frame_if router)
{
  struct rx_u8_buff tfrm;   // temporal frame
  struct rx_u8_buff * movable pframe = &tfrm;
  unsigned pos = 0;
  timer t;
  unsigned tp;
  t :> tp;
  while(1) {
    select
    {
      case t when timerafter(tp) :> void:
      tp = tp + 100*us;
      pos++;
      if (pos == 1)
        pframe->len = strcpy(pframe->dt,":INFO 1 \n");
      else  if (pos == 2)
        pframe->len = strcpy(pframe->dt,"\x1\x8");
      else  if (pos == 3)
        pframe->len = strcpy(pframe->dt,":I2CR 3 A 2 \n");
      else  if (pos == 4)
        pframe->len = strcpy(pframe->dt,":I2CR 4 A 2 \n");
      else  if (pos == 5)
        pframe->len = strcpy(pframe->dt,":I2CW C 01 05 0102030405\n");
      else  if (pos == 6)
        pframe->len = strcpy(pframe->dt,":CANTX E A 0102030405\n");
      else  if (pos == 7)
        pframe->len = strcpy(pframe->dt,":CANTX AB A 0102030405\n");
      else
      {
        pframe->len = strcpy(pframe->dt,":I2CWR D 01 05 03 0102030405\n");
        pos = 0;
      }
      pframe->header_len = 0;
      pframe->cmd_id = serial_rx;
      router.push(pframe,cmd_tx);
      break;
    }
  }
}

/*
 * Use to debug output
 */
[[distributable]] void packet_tx_debug(server interface tx_if tx)
{
  tx.cts();
  while(1)
  {
    select {
      case tx.send(struct rx_u8_buff  * movable &pck):
       printf("tx ");
       if (pck->dt[0] > ' ')
         print_ascii_buff(pck->dt,pck->len);
       else
         print_buff(pck->dt,pck->len);
       tx.cts();
       break;
      case tx.ack():
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

void print_h(streaming chanend c) {
    unsigned char t1;
    while (1) {
        c :> t1;
        printf("%x\n", t1);
    }
}


/*
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
*/

//void test_serial_v4(client interface fifo uart_tx_fifo,
//    client interface serial_rx_if uart_rx,
//    client interface uart_v4 uart_tx,
//    streaming chanend uart_rx_ch
//    )
//{
//
//}

//int main_5()
//{
//  streaming chan uart_rx_ch;
//  interface serial_rx_if uart_rx;
//  interface uart_v4 uart_tx;
//  interface fifo uart_tx_fifo[1];
//  interface tx tx_uart;
//  par
//  {
//    test_serial_v4(uart_tx_fifo[0],uart_rx,uart_tx,uart_rx_ch);
//    fifo_v1(tx_uart,uart_tx_fifo,1);
//    //serial_test(tx,rx_c,rx);
//    [[combine]]
//     par
//     {
//      serial_tx_v4(uart_tx,tx_uart,uart_tx_p);
//      serial_rx_v4(uart_rx,uart_rx_ch,uart_rx_p);
//     }
//  }
//  return 0;
//}


#if 0
void fastTx_test1(client interface tx_if  ftx)
{
  timer t;
  unsigned int tp;
  t :> tp;
  t when timerafter(tp+10*us) :> tp;
  unsigned char i = 0;
  while(1)
  {
    //t when timerafter(tp+10*us) :> tp;
    ftx.send(&i,1);
    i++;
  }
}

// Test fast rx/tx v5
out buffered port:8 tx_16  = XS1_PORT_1P;
out buffered port:8 fast_tx_p  = XS1_PORT_1O;    //LSb to MSB
in buffered port:8 fast_rx_p  = XS1_PORT_1A;    //LSb to MSB
//out port clk_pin = XS1_PORT_1G;
clock    clk      = XS1_CLKBLK_1;
clock    clk_2    = XS1_CLKBLK_2;
out port po_1I = XS1_PORT_1I;
out port p_1D = XS1_PORT_1D;

int main()
{
  streaming chan c;
  interface tx_if  ftx;
  par
  {
    fastTX_v7(ftx,clk,fast_tx_p);
    //fastRX_v6(fast_rx_c,p_1K,clk_2);
    fastRX_v7(c,fast_rx_p,clk_2,po_1I);
    channel_signal(c,p_1D);
    fastTx_test1(ftx);
  }
  return 0;
}
#endif
/*
void i2c_do(const char * cmd, client interface i2c_master_if i2c_master)
{
  struct i2c_frm frm;
  const char* buff;
  unsigned ret;
  buff = cmd;
  switch (getCommand(cmd,buff))
  {
  case i2cw_cmd:
    ret = i2cw_decode(++buff,frm,'\n');
    break;
  case i2cr_cmd:
    ret = i2cr_decode(++buff,frm);
    break;
  case i2cwr_cmd:
    ret = i2cwr_decode(++buff,frm);
    break;
  default:
    ret = 0;
    break;
  }
  if (ret)
  {
    i2c_execute(frm,i2c_master);
  }
}
*/
/*
void test_i2c_parser(client interface i2c_master_if i2c_master)
{
  i2c_do("I2CW 03 0001D304\n",i2c_master);
  i2c_do("I2CR 03 04\n",i2c_master);
  i2c_do("I2CWR 03 0001D304 04\n",i2c_master);
}
*/
/*
unsafe int  main()
{
  interface i2c_master_if i2c_if[1];
  set_port_drive_low(p_1F);
  set_port_drive_low(p_1C);
  par
  {
    i2c_master(i2c_if,1,p_1F,p_1C,100);
    test_i2c_parser(i2c_if[0]);
  }
  return 0;
}
*/
/*
void i2c_do(const char * cmd, client interface i2c_custom_if i2c_master)
{
  struct i2c_frm frm;
  const char* buff;
  unsigned ret;
  ret = 0;
  buff = cmd;
  switch (getCommand(cmd,buff))
  {
  case i2cw_cmd:
    ret = i2cw_decode(++buff,frm,'\n');
    break;
  case i2cr_cmd:
    ret = i2cr_decode(++buff,frm);
    break;
  case i2cwr_cmd:
    ret = i2cwr_decode(++buff,frm);
    break;
  }
  if (ret)
  {
    i2c_master.i2c_execute(frm);
  }
}


void test_i2c_parser(client interface i2c_custom_if i2c_master)
{
  i2c_do("I2CW 03 0001D304\n",i2c_master);
  i2c_do("I2CR 03 04\n",i2c_master);
  i2c_do("I2CWR 03 0001D304 04\n",i2c_master);
}

port p_1F = XS1_PORT_1F;
port p_1C = XS1_PORT_1C;

unsafe int  main()
{
  interface i2c_custom_if i2c_if[1];
  set_port_drive_low(p_1F);
  set_port_drive_low(p_1C);
  par
  {
    i2c_custom(i2c_if,1,p_1F,p_1C,100);
    test_i2c_parser(i2c_if[0]);
  }
  return 0;
}
*/

void dummy_uart_tx(server interface uart_v4 tx)
{

}

// Serial test with router.
void serial_manager(
    client interface uart_v4 tx,
    client interface serial_rx_if rx)
{
  while(1)
  {
    select
    {
      case rx.error():
        rx.ack();
        break;
    }
  }

}


[[combinable]] void irda_send_loop(client interface tx_if tx)
{
  timer t;
  unsigned tp;
  unsigned data;
  t :> tp;
  data = 1;
  while(1)
  {
    select
    {
      case t when timerafter(tp) :> void:
        unsigned char buff[5];
        buff[0] = 8;
        buff[1] = data >> 24;
        buff[2] = data >> 16;
        buff[3] = data >> 8;
        buff[4] = data & 0xFF;
//        tx.send(buff,5);
//      irda_send(d,8,tx);
      data++;
      tp = tp + 500*us;
      break;
    }
  }
}

void serial_send_loop(out port tx)
{
  const char* buff;
  unsigned len;
  unsigned i =0;
  timer t;
  unsigned tp;
  t :> tp;
  while(1) {
    t when timerafter(tp) :> void;
    tp = tp + 500*us;
    if (i == 3) i = 0;
    if (i ==0)
      buff = "I2CW 03 0001D304\n";
    else if (i == 1)
      buff = "I2CR 03 04\n";
    else if (i == 2)
      buff = "I2CWR 03 0001D304 04\n";
    len = safestrlen(buff);
    UART_TIMED_SEND(buff,len,tx,1,t);
    i++;
  }
}
#if 0
out port uart_tx_p = XS1_PORT_1H;
in port uart_rx_p = XS1_PORT_1J;
out port p_feed = XS1_PORT_1N;
in port p_irda = XS1_PORT_1A;

port scl = XS1_PORT_1O;
port sda = XS1_PORT_1P;

int main()
{
  interface packet_tx_if  tx[max_tx]; //tx worker, cmd in ,
  interface rx_frame_if  rx[max_rx]; // serial rx, cmd out
  interface tx_if tx_out[max_tx];
  interface serial_rx_if uart_rx;
  interface uart_v4 uart_tx;

  interface i2c_custom_if i2c[1];

  //interface tx_if irda_emu;
  par
  {
    Router_v2(tx,rx);
    serial_rx_v5(uart_rx,rx[serial_rx],uart_rx_p);
    serial_tx_v5(uart_tx,tx_out[serial_tx],uart_tx_p);
    i2c_custom(i2c,1,scl,sda,100);
    serial_manager(uart_tx,uart_rx);
    TX_Worker(tx,tx_out);
    cmd_v1(rx[cmd_rx],tx_out[cmd_tx],i2c[0]);
    irda_rx_v5(p_irda,10*us,rx[irda_rx]);
    //irda_emulator(10*us,p_irda_feed,irda_emu);
    serial_send_loop(p_feed);
    //irda_send_loop(irda_emu);
  }
  return 0;
}
#endif

#if 0
int main()
{
  unsigned T = 100;
  unsigned addr =0x50;
  timer t;
  unsigned tp;
  enum i2c_ecode ret;
  unsigned char wr[2];
  unsigned char rd[16];
  debug <: 1; // link to scl

  t :> tp;
  I2C_STOP(scl,sda,T,t,tp);
#if 0
  wr[0] = 0;
  ret = I2C_WRITE_BUFF(addr,wr,1,scl,sda,T,t,tp);
  printf("wr=%d ",ret);
  t when timerafter(tp) :> void;
  // random read
  for (unsigned i=0; i< 2000;i++)
  {
    ret = I2C_READ_BUFF(addr,rd,1,scl,sda,T,t,tp);
    I2C_STOP(scl,sda,T,t,tp);
    printf("rdt=%d ",ret);
    printf("%d = %02X\n",i,rd[0]);
  }
#endif
  while(1)
  {
    ret = I2C_READ_BUFF(addr,rd,16,scl,sda,T,t,tp);
    I2C_STOP(scl,sda,T,t,tp);
    printf("\nret=%d :",ret);
    for (int i = 0;i< 16;i++)
    {
      printf("%02X ",rd[i]);
    }
  }
  printf("\n");
  // set read address

  return 0;
}
#endif




#if 0
void spi_test(client interface spi_device_if master_spi_if)
{
  struct spi_frm_v2 frm2;

  frm2.buff[0] = 4;   //echo
  frm2.buff[1] = 0xAB;   //echo
  frm2.buff[2] = 0xCC;   //echo
  frm2.buff[3] = 0xDE;   //echo
  frm2.len = 5;
  frm2.wr_len =  4;
  master_spi_if.execute(&frm2);
  print_buff(frm2.buff+frm2.wr_len+1,frm2.len-1);

  frm2.buff[0] = 3;  // hello
  frm2.len = 16;
  frm2.wr_len = 1;
  master_spi_if.execute(&frm2);
  print_ascii_buff(frm2.buff+frm2.wr_len,frm2.len-1);
  print_buff(frm2.buff+frm2.len+1,frm2.len-1);

  frm2.buff[0] = 1;   // pos
  frm2.len = 16;
  frm2.wr_len = 1;
  master_spi_if.execute(&frm2);
  print_buff(frm2.buff+frm2.wr_len+1,frm2.len-1);
}

void  mcp2515_test(client interface mcp2515_if mcp2515)
{
  unsigned char d;
  d = mcp2515.getStatus();
  printf("%02X ",d);

}

out port spi_out = XS1_PORT_4C;
in port spi_miso = XS1_PORT_1H;

in port spi_in = XS1_PORT_4D;
out port spi_slv_miso = XS1_PORT_1J;

in port i1 = XS1_PORT_1O;
in port i2 = XS1_PORT_1P;
in port i3 = XS1_PORT_1N;
in port intport = XS1_PORT_4A;

/*
 * SPI with canbus test
 */

int main()
{
//  const unsigned T = 2*us;
  const unsigned cpol = 0;
  const unsigned cpha = 0;

  interface spi_slave_if_v2 spi_if;
  interface spi_master_if master_spi_if;
  //interface spi_device_if dev_if;
  interface mcp2515_if mcp2515;
  interface mcp2515_int_if mcp2515_int;
  interface interrupt_if int_if[1];
  struct interrupt_mask_t int_mask[] = { {1,1}};
  par
  {
    spi_master(spi_out,spi_miso,master_spi_if);
    test_spi_slave_v2(spi_if);
    //spi_slave_v2(spi_slv_ss,spi_slv_scl,spi_slv_mosi,spi_slv_miso,cpol,cpha,spi_if);
    spi_slave_v3(spi_in,SPI1_SCK_MASK,SPI1_MOSI_MASK,SPI1_MCP2515_SS_MASK,spi_slv_miso,cpol,cpha,spi_if);
    //spi_dev(SPI1_MCP2515_SS_MASK,cpol,cpha,T,dev_if,master_spi_if);
    mcp2515_test(mcp2515);
    //spi_test(dev_if);
    mcp2515_master(SPI1_MCP2515_SS_MASK,mcp2515,master_spi_if,mcp2515_int);
    interrupt_manager(intport,1,int_mask,int_if);
    mcp2515_interrupt_manager(mcp2515_int,int_if[0]);
  }
  return 0;
}
#endif


#if 0
/*
 * Spi trasnfers with strobe signal, buffered clocked port
 */

clock    clk      = XS1_CLKBLK_1;

out port mspi_ss = XS1_PORT_1A;
out port mspi_scl = XS1_PORT_1B;
out buffered port:8 mspi_mosi  = XS1_PORT_1C;
in  buffered port:8 mspi_miso  = XS1_PORT_1D;

in port  sspi_ss = XS1_PORT_1E;
in port  sspi_scl =  XS1_PORT_1F;
in  buffered port:8 sspi_mosi  = XS1_PORT_1G;    //LSb to MSB
out  buffered port:8 sspi_miso  = XS1_PORT_1H;    //LSb to MSB

int main()
{
  const unsigned char cpl = 1;
  const unsigned char cpha = 0;
  unsigned char din,dout;
  if (cpl)
      set_port_inv(mspi_scl);
  configure_clock_xcore(clk,10);     // 4ns X
  configure_port_clock_output(mspi_scl, clk);
  configure_out_port(mspi_mosi, clk,1);
  configure_in_port(mspi_miso, clk);
  configure_out_port_strobed_master(mspi_mosi, mspi_ss, clk,1);
  start_clock(clk);

  set_port_inv(mspi_ss);

  dout = 0x81;
  mspi_mosi <: dout;
  mspi_miso :> din;
  mspi_mosi <: dout;
  mspi_miso :> din;
  return 0;
}

#endif

#if 1

// SPI Master
out port spi_out = XS1_PORT_4C;
in port spi_miso = XS1_PORT_1H;

//SPI slave
in port spi_in = XS1_PORT_4D;
out port spi_slv_miso = XS1_PORT_1J;

//Interrupt sources
in port interrupt_port = XS1_PORT_1A;

//UART
out port uart_tx_p = XS1_PORT_1B;
in port  uart_rx_p = XS1_PORT_1C;

//IRDA
in port p_irda = XS1_PORT_1D;

// UART LOOP for testing
out port p_feed = XS1_PORT_1G;

// tracing port
in port i1 = XS1_PORT_1K;
in port i2 = XS1_PORT_1I;
in port i3 = XS1_PORT_1L;

struct i2c_master_t i2c_master = {XS1_PORT_1F,XS1_PORT_1E,ms/400};

int main()
{
  interface packet_tx_if  tx[max_tx];    //tx worker, cmd in ,
  interface rx_frame_if  rx[max_rx];     // serial rx, cmd out
  interface tx_if        tx_out[max_tx]; // tx interfaces
  interface serial_rx_if uart_rx;
  interface uart_v4      uart_tx;

  // buses
  interface spi_master_if master_spi_if;

  //devices
  interface mcp2515_if mcp2515[1];    // for interrupt and command

  //interrupt souurces
  interface interrupt_if int_if[1];


  //interface tx_if irda_emu;
  par
  {
    Router_v2(tx,rx);
    serial_rx_v5(uart_rx,rx[serial_rx],uart_rx_p);

    packet_tx_debug(tx_out[serial_tx]);
    dummy_uart_tx(uart_tx);
    //serial_tx_v5(uart_tx,tx_out[serial_tx],uart_tx_p);


    TX_Worker(tx,tx_out,rx[reply_rx]);
    cmd_v1(rx[cmd_rx],tx_out[cmd_tx]);

    // buses
    spi_master(spi_out,spi_miso,master_spi_if);

    //devices
    mcp2515_master(mcp2515,1,SPI1_MCP2515_SS_MASK,tx_out[mcp2515_tx],master_spi_if);

    // RX interfaces
    irda_rx_v5(p_irda,10*us,rx[irda_rx]);
    command_pusher(rx[test_rx]);

    interrupt_manager(interrupt_port,1,int_if,0);
    mcp2515_interrupt_manager(mcp2515[0],int_if[0],rx[mcp2515_rx]);

  //  i2c_custom(i2c,1,scl,sda,100);
    i2c_master_v2(i2c_master,tx_out[tx_i2c]);
    serial_manager(uart_tx,uart_rx);

    //serial_send_loop(p_feed); // command pusher does teh job
  }
  return 0;
}
#endif

#if 0
/*
 * testing fast spi
 */
//out port ss = XS1_PORT_1K;
//out port sck = XS1_PORT_1I;
//out buffered port:8 mosi = XS1_PORT_1L;
//in buffered port:8 miso = XS1_PORT_1F;
//clock clk = XS1_CLKBLK_1;

out buffered port:32 feed = XS1_PORT_1G;
struct spi_fast_t spi = { XS1_PORT_1K,XS1_PORT_1L,XS1_PORT_1F,XS1_PORT_1I,XS1_CLKBLK_1};

int main()
{
  char dt[5];
  spi_fast_init(spi,us);
  delay_microseconds(5);
//  spi_fast_send(spi,"\x55\x2\x3\x4\x5",1);
  feed <: 0x1248F55;
  spi_fast_sendrecv(spi,5,0,"\x1\x2\x4\x8\x55",5,dt);
  print_buff(dt,5);
  printf("\n");
  return 0;
}
#endif

/* todo.
 * analog to digital converter plus interface via serial port
 * linux opengl frontend
 * command interface to parse i2c irda and spi command interface
 */

