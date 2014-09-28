#include <timer.h>
#include <xs1.h>
#include <stdio.h>
#include <xscope.h>
#include <platform.h>

/*

 //interface to task comunication
 one task blind led other set frecuency
 */

const unsigned clock_freq = 100 * 1000 * 1000; // timer frecuency in Hz

interface flasher_if {
    void setFreqHz(unsigned freq);
    void set_ton_percent(unsigned ton); // 0 - 100
};

void flasher(port p, server interface flasher_if i)
{
    unsigned t = clock_freq;
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
            t = clock_freq/freq;
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
                mark += clock_freq; // 1/2 second
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
//    xscope_register(1, XSCOPE_CONTINUOUS, "IRDA", XSCOPE_UINT, "mV");
//}


void readIRDA(in port p, chanend c) {

    int t0 = 0;
    int t1 = 0;

    unsigned char val = 0;
    timer tm;
    p :> val;
    tm :> t1;
    printf("%d\n", val);
    for (;;) {
        // wait for 0
        p when pinseq(0) :> void;
        tm :> t0;
        // wait for 1
        p when pinseq(1) :> void;
        tm :> t1;
        t0 = t1 - t0;
        p when pinseq(0) :> val;

        // wait 1 or 1.5

        c <: (t0-t1);

        c <: (t1-t0);
        //        p when pinseq(0) :> void;
        //        tm :> te;
        //        c <: (te - t1);
        //        p when pinseq(1) :> void;


        //        select {
        //            case p when pinsneq(val) :> val:
        //            tm :> te;
        //            if (val == 1)
        //            {
        //                t0 = te-tb;
        //            }
        //            else
        //            {
        //                t1 = te-tb;
        //                c <: (t0 + t1);
        //            }
        //            tb = te;
        //            break;
        //        }
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

void xscope_user_init(void) {
    xscope_register(0);
    xscope_config_io(XSCOPE_IO_BASIC);
}

//port p = XS1_PORT_1D;
//port led_d2 = XS1_PORT_1A;
//port p32 = XS1_PORT_32A;
//in port irda = XS1_PORT_1F;
//out port led = XS1_PORT_1A;

in port irda = XS1_PORT_1F;

/**
 * pins is normaly at level 1
 * when go to 0 and go back to 1 . The lenght of this pulse is a reference for the next
 * the next pulse could be < 1.5T means 0
 * from 1.5 to 2.5 means 1
 * from 2.5 to 4.5 means start pulse
 * more than 4.5 means end.
 */

void readIRDA_v2(in port p, chanend c) {
    int te = 0;
    int t = 0;
    unsigned char val = 0;
    timer tm;
    p :> val;
    printf("%d\n", val);
    for (;;) {
        // wait for 0
        p when pinseq(0) :> void;
        tm :> t;
        // wait for end of pulse
        p when pinseq(1) :> void;
        tm :> te;
        t = te - t;
        //wait for next pulse
        p when pinseq(0) :> void;
        // wait end or 1.5T
        select {
            case tm when timerafter(te + t + t/2) :> void:
            break;
            case p when pinseq(1) :> void:
            c <: '0';
            continue;
            break;
        }
        // wait end or 2.5T
        select {
            case tm when timerafter(te + t*2 + t/2) :> void:
            break;
            case p when pinseq(1) :> void:
            c <: '1';
            continue;
            break;
        }
        // wait end or 4.5T
        select {
            case tm when timerafter(te + t*4 + t/2) :> void:
            break;
            case p when pinseq(1) :> void:
            c <: '3';
            continue;
            break;
        }
        // so long 0
        p when pinseq(1) :> void;
        c <: '2';
    }
}

void printTime_v2(chanend c) {
    char t1;
    while (1) {
        c :> t1;
        printf(t1 == '2' ? "\n" : t1 == '3' ? "\nS" : t1 == '1' ? "1" : "0");
    }
}

void IRDA_time(in port p, chanend c) {
    int t = 0;
    unsigned char val = 0;
    timer tm;
    p :> val;
    printf("%d\n", val);
    for (;;) {
        // wait for 0
        p when pinsneq(val) :> val;
        tm :> t;
        c <: t;
    }
}

void IRDA_delta(in port p, chanend c) {
    int te;
    int ts;
    unsigned char val = 0;
    timer tm;
    tm :> ts;
    p :> val;
    printf("%d\n", val);
    for (;;) {
        // wait for 0
        p when pinsneq(val) :> val;
        tm :> te;
        c <: (te-ts);
        ts = te;
    }
}
/**
 * IRDA using a base frecuency of 60 000 cycles = 6ns
 *
 * more than 10T means reset and wait for 7T
 * > 4T
 */
void IRDA_base_freq(in port p, chanend c) {
    timer tm;
    int t, te = 0;
    char started = 0; // 1 means start received
    const unsigned freq_tick = 60 * 1000;
    for (;;) {
        started = 0;
        // wait for first 0 it will be 15T
        p when pinseq(0) :> void;
        for (;;) {
            //wait for first 1 ; ignore previous zero
            p when pinseq(1) :> void;
            tm :> t;
            // wait 0 no more than 8T, normally is 7T that means started
            select {
                case tm when timerafter(t + freq_tick * 10) :> void:
                c <: 'T';
                break;
                case p when pinseq(0) :> void:
                tm :> te;
                // check length of 1
                t = (te - t) / freq_tick;
                if (t > 3)
                {
                    started = 1;
                    c <: 'S';
                }
                //                else if (started == 0)
                //                c <: 'E';
                else if (t >= 2)
                c <: '1';
                else
                c <: '0';
                continue;
                break;
            }
            break; // if 0 length is > 2T then restart
        }
        p when pinseq(0) :> void;

    }
}

void IRDA_freq_mul(in port p, chanend c) {
    const unsigned freq_tick = 60 * 1000;
    char val;
    timer tm;
    int ts, te = 0;
    p :> val;
    tm :> ts;
    printf("%d\n", val);
    for (;;) {
        p when pinsneq(val) :> val;
        tm :> te;
        c <: (te - ts) / freq_tick;
        ts = te;
    }
}

void print_i(chanend c) {
    int t1;
    while (1) {
        c :> t1;
        printf("%d\n", t1);
    }
}
void print_char(chanend c) {
    char t1;
    while (1) {
        c :> t1;
        if (t1 == 'T')
            printf("\n");
        else
        printf("%c", t1);

    }
}
/**
 * IRDA receiver project.
 * Hardware:
 * TERRATEC Remote Control.
 * Buttons
 * Home
 * Power
 * DVD Menu
 * Subtitles
 * Teletext
 * Delete
 * AV
 * A-B
 * 1
 * 2
 * 3
 * 4
 * 5
 * 6
 * 7
 * 8
 * 9
 * 0
 * TV
 * DVD
 * VIDEO
 * Music
 * PIC
 * UP
 * DOWN
 * RIGHT
 * LEFT
 * OK
 * GUIDE
 * INFO
 * BACK
 * VOL+
 * VOL-
 * CH+
 * CH-
 * Play
 * Mute
 * red
 * green
 * yellow
 * blue
 * REC
 * STOP
 * PAUSE
 * LAST
 * FR
 * FF
 * NEXT
 */

int main() {
    chan c;
    par
    {
        IRDA_base_freq(irda, c);
        print_char(c);
    }
    //    par
    //    {
    //        IRDA_freq_mul(irda,c);
    //        print_i(c);
    //    }
    return 0;
}
