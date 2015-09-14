/*
 * spower.xc
 *
 *  Created on: 5 Aug 2015
 *      Author: lester.crespo
 *
 * Switch power supply
 * Sample adc for high and low voltage levels
 * Shutdown the power.
 * Set max and delta voltage
 *
 * TODO  Switched Power Supply (Buck)
 * power control task. ( Imax, Imin for switch transistor signal)
 * adc input when power is on.
 * Imax and delta as intensity control.
 * At power off signal, adc must be stopped, all led switch turn off, power transistor go off).
 * Status (ON, OFF) -
 * protection for long Ton times. (overcurrent protection, analize ton,toff time)
 * Interface to set Imax or level intensity, read ton-toff, fault indicator,
 * Turn on ligth in a secuence base on walker speed. ( one motion sensor at enter point)
 *
 * Using predectible algorithm, the transistor is switch off oen step before reach the max.
 * calculate voltage increase speed
 */

#include "spower.h"

/*
void switch_power_supply(server interface switch_power_if iface)
{
////  timer t;
////  unsigned int tp;
//  while(1)
//  {
//
//  }
}
*/
