/*
 * irda.xc
 *
 *  Created on: 7 Jul 2015
 *      Author: lester
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


void irda_rd(in port p, chanend c)
{
    int pv; // port value
    timer tm;
    char bitcount = 0;
    const unsigned T = 60 * 1000;
    int st;     // start time of data
    // wait for 1 at the start. after we need to measure the length of zero at the end
    p :> pv;
    tm :> st;
    if (pv == HIGH)
        c<: 'H';
    else
        c <: 'L';
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
                c <: '0';
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
                    c <: '1';
                    bitcount++;
                    break;
            }
        }
        if (pv == HIGH)        // timeout waiting to long it is Start
        {
            c <: 'S';
            bitcount = 0;
            p when pinseq(LOW) :> pv; // wait for 0
            tm :> st;
        }
        // test length of zero
        select
        {
            case tm when timerafter(st+T*1.5) :> void:      // too long 0 it is the end
                c <: 'E';
                break;
            case p when pinseq(HIGH) :> pv:
                tm :> st;
                break;
        }

    }
}
