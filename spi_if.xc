/*
 * spi_if.xc
 *
 *  Created on: Mar 14, 2019
 *      Author: lester
 */


#define SS_BIT   1
#define CLK_BIT  2
#define MISO_BIT 4


[[distributable]] extern void spi_4b(server interface spi_if spi, out port p4b, in port mosi)
{
    unsigned long long T = (MHz_tick / 8); // 8 Mhz
    char out_v = SS_BIT + CLK_BIT;
    char bit_count = 0;
    p4b <: out_v;
    while(1)
    {
        select
        {
        case spi.setFreq(unsigned khz):
            T = (KHz_tick / khz);
            break;
        case spi.start():
            out_v |= CLK_BIT;
            p4b <: out_v;
            delay_ticks_longlong(T/2);
            break;
        case spi.end():
            out_v &= (~SS_BIT);
            p4b <: out_v;
            delay_ticks_longlong(T/2);
            break;
        case spi.wr(unsigned char value):
            bool SSoff = (out_v & SS_BIT);
            if (SSoff)
            {
                out_v |= CLK_BIT;
                p4b <: out_v;
                delay_ticks_longlong(T/2);
            }
            value = bitrev(value);
            for (unsigned char mask = 0x80;mask;mask>>=1)
            {
                out_v &= (~ (CLK_BIT + MISO_BIT));
                if (value & mask) out_v |= MISO_BIT;
                p4b <: out_v;
                delay_ticks_longlong(T/2);
                out_v |= CLK_BIT;
                delay_ticks_longlong(T/2);
            }
            out_v &= (~CLK_BIT);
            p4b <: out_v;
            if (SSoff)
            {
                out_v &= (~SS_BIT);
                p4b <: out_v;
                delay_ticks_longlong(T/2);
            }
            break;
        case spi.wr_rd(unsigned char value) -> unsigned char ret:
            ret = 0;
            bool SSoff = (out_v & SS_BIT);
            if (SSoff)
            {
                out_v |= CLK_BIT;
                p4b <: out_v;
                delay_ticks_longlong(T/2);
            }
            value = bitrev(value);
            for (unsigned char mask = 0x80;mask;mask>>=1)
            {
                out_v &= (~ (CLK_BIT + MISO_BIT));
                if (value & mask) out_v |= MISO_BIT;
                p4b <: out_v;
                delay_ticks_longlong(T/2);
                out_v |= CLK_BIT;
                delay_ticks_longlong(T/2);
                mosi :> >>ret;
            }
            out_v &= (~CLK_BIT);
            p4b <: out_v;
            if (SSoff)
            {
                out_v &= (~SS_BIT);
                p4b <: out_v;
                delay_ticks_longlong(T/2);
            }
            break;

        case spi.rd() -> unsigned char ret:
            ret = 0;
            bool SSoff = (out_v & SS_BIT);
            if (SSoff)
            {
                out_v |= CLK_BIT;
                p4b <: out_v;
                delay_ticks_longlong(T/2);
            }
            value = bitrev(value);
            for (unsigned char mask = 0x80;mask;mask>>=1)
            {
                out_v &= (~ (CLK_BIT + MISO_BIT));
                p4b <: out_v;
                delay_ticks_longlong(T/2);
                out_v |= CLK_BIT;
                delay_ticks_longlong(T/2);
                mosi :> >>ret;
            }
            out_v &= (~CLK_BIT);
            p4b <: out_v;
            if (SSoff)
            {
                out_v &= (~SS_BIT);
                p4b <: out_v;
                delay_ticks_longlong(T/2);
            }
            break;
        }
    }
}
