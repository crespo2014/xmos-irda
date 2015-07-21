/*
 * irda.h
 *
 *  Created on: 21 Jul 2015
 *      Author: lester.crespo
 */

#ifndef IRDA_H_
#define IRDA_H_

#define IRDA_BIT_LEN 600*us

/*
 * macro to produce a irda pulse.
 * time point will be update to the end of the pulse
 * a duty cycle of 33% is used
Produce a 36Khz wave form for irda transmitter. (27.8us)
Dutty cycle is 25-33%
Create many pulse to fill the specific time
9us + 18us

T period of the irda carrier,(36Khz = 27us)
tp time point of start of pulse, it will be update to point the end of the pulse
len - len of pulse.
t timer
p port
high, low port values for high an low level

a 1/3T pulse is produce always.
if there is space for a full pulse then another will produce in the next loop
if there is not space no more pulse will be produce.
*/
#define IRDA_PULSE(T,tp,len,t,p,high,low) \
  do {   \
    p <: high;  \
    t when timerafter(tp+T/3) :> void; \
    p <: low;  \
    if (len < T) {  \
      tp += len;  \
      len = 0;        \
    } else  {   \
      tp += T;   \
      len -= T;     \
    } \
    t when timerafter(tp) :> void;\
  } while(len != 0);


#endif /* IRDA_H_ */
