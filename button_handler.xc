#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>
#include "rxtx.h"
#include "irda.h"

/*
extern void irda_rd(in port p, chanend c);
extern void irda_rd_v1(in port p, chanend c);
extern void irda_rd_v3(in port p, chanend c);
*/
/*

 //interface to task comunication
 one task blind led other set frecuency
 */

interface flasher_if {
    void setFreqHz(unsigned freq);
    void set_ton_percent(unsigned ton); // 0 - 100
};

void flasher(port p, server interface flasher_if i)
{
    unsigned t = sec;
    unsigned ton = t * 0.5;
    unsigned ton_percent = 50;
    timer tm;
    unsigned mark;
    tm :> mark;
    unsigned val = 0;
    while(1)
    {
        if (val == 0)
        {
            mark += ton;
        }
        else
        {
            mark += (t - ton);
        }
        select
        {
            case tm when timerafter(mark) :> void:
            p <: val;
            val = ~val;
            break;
            case i.set_ton_percent(unsigned new_ton):
            ton_percent = new_ton % 101;
            ton = t*ton_percent/100;
            break;
            case i.setFreqHz(unsigned freq):
            t = sec/freq;
            ton = t/100*ton_percent;
            break;
        }
    }
}

void flasher_control(client interface flasher_if i)
{
    timer tm;
    unsigned mark;
    tm :> mark;
    for (;;)
    {
        for (unsigned f = 1;f < 10;++f)
        {
            i.setFreqHz(f);
            for (unsigned t = 50;t < 100;++t)
            {
                i.set_ton_percent(t);
                mark += sec/2; // 1/2 second
        select
        {
            case tm when timerafter(mark) :> void:
            //
            break;
        }
    }
}
}
}

//void xscope_user_init(void) {
//    xscope_register(0);
//    xscope_config_io(XSCOPE_IO_BASIC);
//}

#define HIGH 0
#define LOW  1

void gen_clock(out port txd) {
    timer t;
    const unsigned T = 60 * 1000;
    unsigned time;

    // Output start bit
    txd <: 0; // Endpoint 0
    t :>time;
    for (;;)
    {
        time += 4*T;
        t when timerafter(time) :> void;
        txd <: 1;// Endpoint B
        time += 4*T;
        t when timerafter(time) :> void;
        for (char i =0;i<12;++i)
        {
        time += 1.5*T;
        t when timerafter(time) :> void;
        txd <: 0; // Endpoint B
        time += 1.5*T;
        t when timerafter(time) :> void;
        txd <: 1;// Endpoint B
        }
    }
}




/*
on stdcore[0] : out port tx      = XS1_PORT_1A;
on stdcore[0] : in  port rx      = XS1_PORT_1B;
*/
/*
int main1() {

    interface tx_rx_if ch0tx,ch1tx,ch0rx,ch1rx,irda_tx,irda_rx;
    interface cmd_push_if cmd;
    interface fault_if ch0rx_f,ch1rx_f,cmd_f,route_f,irdarx_f;
    par
    {
      TX(ch0tx,gpio_ch0_tx,60*us);
      RX(ch0rx,gpio_ch0_rx,60*us,ch0rx_f);
      TX(ch1tx,gpio_ch1_tx,60*us);
      RX(ch1rx,gpio_ch1_rx,60*us,ch1rx_f);
      Router(ch0tx,ch1tx,ch0rx,ch1rx,cmd,route_f);
      irda_TX(irda_tx,gpio_irda_tx,IRDA_BIT_LEN,0,1);
      irda_RX(irda_rx,gpio_irda_rx,IRDA_BIT_LEN,0,irdarx_f);
      [[combine]]
      par
      {
        CMD(cmd,irda_tx,irda_rx,cmd_f);
        ui(gpio_fault,ch0rx_f,ch1rx_f,route_f,cmd_f,irdarx_f);
      }
    }
    return 0;
}
*/
