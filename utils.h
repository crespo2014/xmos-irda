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
extern unsigned readHexChar(char str);
extern unsigned readHexByte(const char* &str);
extern unsigned getHexChar(unsigned char num);
extern unsigned getHexByte(unsigned char num);
extern void getHexBuffer(const unsigned char *d,unsigned len,char * &str);

// copy str and update dest with last copied character
extern void strcpy(char* &dest,const char* src);

#endif /* UTILS_H_ */
