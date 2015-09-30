/*
 * utils.h
 *
 *  Created on: 6 Sep 2015
 *      Author: lester
 */

#ifndef UTILS_H_
#define UTILS_H_

#define SYS_TIMER_T_ns  10   //set to 100 for testing

#define sec 100000000
#define ms  100000
#define us  100        // 1 usecond
#define ns  (1/SYS_TIMER_T_ns)

/*
 * Read a hex number.
 * return over 255 if there is an error.
 */
extern unsigned readHexChar(const char *&str);
extern unsigned readHexByte(const char* &str);
extern unsigned getHexChar(unsigned char num);
extern unsigned getHexByte(unsigned char num);
extern void getHexBuffer(const unsigned char *d,unsigned len,char * &str);
/*
 * convert ascii hex buffer to  raw data
 */
extern unsigned readHexBuffer(const char* &str,unsigned char* buff,unsigned max);
extern unsigned read32BitsHex(const char* &str);

//convert unsigned 8bit number to hex string and update pointer
void u8ToHex(unsigned char num,char * &str);

// copy str and update dest with last copied character
extern void strcpy(char* &dest,const char* src);

// copy string macro that
#define STRCPY(__dest,__src,__len) \
  do { \
    __len = 0; \
    while ((*(__dest + __len) = *(__src + __len)) != 0) ++__len; \
  } while(0)

// print a ascii buffer
extern void printbuff(const char* d,unsigned len);

/*
 * Check if some string is a prefix o other
 * pointer to last unmatched character is update
 */
unsigned isPreffix(const char* pref,const char *str,const char *&last);

#endif /* UTILS_H_ */
