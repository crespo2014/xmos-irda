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
 * Using predectible algorithm, the transistor is switch off oen step before reach the max.
 * calculate voltage increase speed
 */

#include "spower.h"


void switch_power_supply(server interface switch_power_if iface)
{
  timer t;
  unsigned int tp;
  while(1)
  {

  }
}
