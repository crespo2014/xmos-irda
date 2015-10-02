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
extern unsigned getHexChar(unsigned num);
//extern unsigned getHexByte(unsigned char num);
extern void getHexBuffer(const unsigned char *d,unsigned len,char * &str);
/*
 * convert ascii hex buffer to  raw data
 */
extern unsigned readHexBuffer(const char* &str,unsigned char* buff,unsigned max);
extern unsigned read32BitsHex(const char* &str);

//convert unsigned 8bit number to hex string and update pointer
void u8ToHex(unsigned char num,char * &str);

static inline void getHex_u8(unsigned num, char* dest)
{
  dest[0] = getHexChar(num >> 4);
  dest[1] = getHexChar(num & 0x0F);
}

static inline unsigned readHex_u4(unsigned hexchar)
{
  do
  {
    if (hexchar < '0') break;
    if (hexchar <= '9')
    {
      return hexchar - '0';
    }
    if (hexchar < 'A') break;
    if (hexchar <= 'F')
      return (hexchar - 'A' + 10);
    if (hexchar < 'a') break;
    if (hexchar > 'f') break;
    return hexchar - 'a' + 10;
  } while(0);
  return 0xFFF;
}

static inline unsigned readHex_u8(const char* str)
{
  return readHex_u4(str[0]) << 4 | readHex_u4(str[1]) ;
}





// copy string macro that
#if 0
#define STRCPY(__dest,__src,__len) \
  do { \
    __len = 0; \
    while ((*(__dest + __len) = *(__src + __len)) != 0) ++__len; \
  } while(0)

#define ispreffix_(__prefix,__str,__len) \
  do { \
    while (*(__prefix + __len) == *(__str + __len)) { ++__len; } \
  } while(0)

#endif

static inline unsigned strcpy(char* dest,const char* src)
{
  unsigned len = 0;
  while (( dest[len] = src[len]) != 0) ++len;
  return len;
}

static inline unsigned CheckPreffix(const char* preffix,const char* str,unsigned &len)
{
  len = 0;
  while( preffix[len] == str[len] ) { ++len; }
  return (preffix[len] == 0 &&  str[len] == ' ');
}

// print a ascii buffer
extern void printbuff(const char* d,unsigned len);

#endif /* UTILS_H_ */
