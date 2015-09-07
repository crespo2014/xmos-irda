/*
 * utils.h
 *
 *  Created on: 6 Sep 2015
 *      Author: lester
 */


#ifndef UTILS_H_
#define UTILS_H_

/*
 * Read a hex number.
 * return over 255 if there is an error.
 */
extern unsigned getHexChar(const char* str);
extern unsigned HextoU8(const char* str);
// copy str and return last copied character
extern void strcpy(char* &dest,const char* src);

unsigned HexChar_u(const char* str)

#endif /* UTILS_H_ */
