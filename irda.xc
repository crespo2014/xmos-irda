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

/*
 * high level for
 *  <= 1.5T is 0
 *  <= 2.5T is 1
 *  > 2.5T  is start
 *
 * low level for
 *  < 1.5T  more data
 *  > 1.5T  end of data
 *
 */

#define HIGH 0
#define LOW  1

/*
 * wait for ping go H.
 * wait for timeout or pin go LOW (take time)
 *
 * wait for ping go H or timeout
 */
void irda_rd_v1(in port p, chanend c) {
    int pv; // port value
    timer tm;
    char bitcount = 70;      // how many bits have been received invalid if > 64
    unsigned val = 0;       // storing bits
    const unsigned T = 60 * 1000;
    int ts;     // start time of data
    int te;     // time end of transation

    p :> pv;     // initial status
    tm :> ts;
    for (;;)
    {
        if (pv == LOW)
        {
            p when pinseq(HIGH) :> pv;
            tm :> ts;
        }
        // wait for pin go LOW
        select
        {
            case tm when timerafter(ts+T*2.5) :> void: // timeout or Start condition
            bitcount = 0;
            val = 0;
            break;
            case p when pinseq(LOW) :> pv:// for t < 1.5 is 0 otherwise is 1
            tm :> te;
            if (bitcount < 64)      // not start received
            {
                val = val*2;
                if (te - ts > T*1.5) ++val;
                bitcount++;
                if (bitcount == 32)
                {
                    bitcount = 0;
                    c <: val;
                }
            }
            ts = te;
            break;
        }
        if(pv == HIGH)
        {
            p when pinseq(LOW) :> pv;// wait for low
            tm :> ts;
        }
        // wait for pin go high
        select
        {
            case tm when timerafter(ts+T*2) :> void:           // too long 0 it is the end
            if (bitcount < 64 &&  bitcount != 0) c <: val;     // send any capture data
            bitcount = 70;                                     // ignore any data without start
            break;
            case p when pinseq(HIGH) :> pv:
            tm :> ts;
            break;
        }
    }
}

/*
 * Wait for transition on ping or timeout, then take a action base on the pin level
 */
void irda_rd_v3(in port p, chanend c) {
    int pv; // port value
    timer tm;
    char bitcount = 70;      // how many bits have been received invalid if > 64
    unsigned val = 0;       // storing bits
    const unsigned T = 60 * 1000;
    int ts;     // start time of data
    int te;     // time end of transation

    p :> pv;
    tm :> ts;
    for (;;)
    {
        // wait for pin transition
        select
        {
            case tm when timerafter(ts+T*2.5) :> void: // timeout
                if (pv == HIGH)
                {
                    bitcount = 0;
                    val = 0;
                } else
                {
                    if (bitcount < 64 && bitcount != 0) c <: val; // send any capture data
                    bitcount = 70;// ignore any data without start
                }
                p when pinsneq(pv) :> pv;   // wait for transition
                tm :> ts;
                break;
            case p when pinsneq(pv) :> pv:                       // for t < 1.5 is 0 otherwise is 1
                tm :> te;
                if (pv == LOW && bitcount < 64)// store only if start signal was received
                {
                    val <<= 1;
                    if (te - ts > T*1.5) val |= 1;
                    bitcount++;
                    if (bitcount == 32)
                    {
                        bitcount = 0;
                        c <: val;
                    }
                }
                ts = te;
                break;
        }
    }
}

void irda_rd(in port p, chanend c)
{
    int pv; // port value
    timer tm;
    char bitcount = 0;
    unsigned val = 0;
    const unsigned T = 60 * 1000;
    int st;     // start time of data
    // wait for 1 at the start. after we need to measure the length of zero at the end
    p :> pv;
    tm :> st;
    c <: pv;
    for (;;)
    {
        // wait for pin go high
        if (pv == LOW)
        {
            p when pinseq(HIGH) :> pv;
            tm :> st;
        }
        // wait for pin go low or timeout
        select
        {
            case tm when timerafter(st+T*1.5) :> void:  // timeout it is not a 0
                break;
            case p when pinseq(LOW) :> pv:
                tm :> st;
                val *= 2;       // shift a 0
                bitcount++;
                break;
        }
        if (pv == HIGH)
        {
            select
            {
                case tm when timerafter(st+T*2.5) :> void:  // timeout is not a 1
                    break;
                case p when pinseq(LOW) :> pv:
                    tm :> st;
                    val = val*2+1;      // shift a 1
                    bitcount++;
                    break;
            }
        }
        if (pv == HIGH)        // timeout waiting to long it is Start
        {
            c <: 'S';
            bitcount = 0;
            val  = 0;
            p when pinseq(LOW) :> pv; // wait for 0
            tm :> st;
        }
        else
        {
            if (bitcount == 8)
            {
                c <: val;
                bitcount = 0;
                val = 0;
            }
        }
        // test length of zero
        select
        {
            case tm when timerafter(st+T*1.5) :> void: // too long 0 it is the end
            if (bitcount != 0) c <: val;               // send any capture data
            break;
            case p when pinseq(HIGH) :> pv:
            tm :> st;
            break;
        }

    }
}

