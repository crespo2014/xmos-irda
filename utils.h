/*
 * utils.h
 *
 *  Created on: 6 Sep 2015
 *      Author: lester
 */

#ifndef UTILS_H_
#define UTILS_H_

#define XCORE_CLK_T_ns         4    // produced clock T
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

// todo read hex buffer util space or enter

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

/*
 * Convert two hex char to binary
 */
unsigned static inline hex2_to_u8(const char str[])
{
  return 0;
}

{unsigned ,unsigned } static inline readHex_u8_2(const char* str)
{
  unsigned d = 0;
  unsigned len;
  for (len=0;len<2;len++)
  {
    unsigned v = readHex_u4(str[len]);
    d = d << 4 | v;
    if (v > 0xFF) break;
  }
  return {d,len};
}

static inline unsigned readHex_u8(const char* str,unsigned &len)
{
  unsigned d = 0;
  for (int len=0;len<2;len++)
  {
    unsigned v = readHex_u4(str[len]);
    if (v > 0xFF) break;
    d = d << 4 | v;
  }
  return d;
}

static inline unsigned readHex_u32(const char* str,unsigned char &len)
{
  unsigned d = 0;
  for (int len=0;len<8;len++)
  {
    unsigned v = readHex_u4(str[len]);
    if (v > 0xFF) break;
    d = d << 4 | v;
  }
  return d;
}

{unsigned ,unsigned } static inline asciiToHex32(const char* str)
{
  unsigned d = 0;
  unsigned len;
  for (len=0;len<8;len++)
  {
    unsigned v = readHex_u4(str[len]);
    if (v > 0xFF) break;
    d = d << 4 | v;
  }
  return {d,len};
}
/*
 * return
 * value, len
 */
{unsigned ,unsigned } static inline Hex_to_u8(const char str[])
{
  unsigned d = readHex_u4(str[0]);
  if (d > 0xFF)  return { d,0 };
  unsigned v = readHex_u4(str[1]);
  if (v > 0xFF)  return { d,1 };
  d = d << 4 | v;
  return { d, 2 };
}

{unsigned ,unsigned } static inline hex_space_to_u8(const char str[])
{
  unsigned len = 0;
  unsigned d = 0;
  while (len < 2 && str[len] != ' ')
  {
     d = (d << 4) | readHex_u4(str[len++]);
  }
  if (str[len] != ' ') {d = 0xFFF;len = 0;}
  return {d,len};
}

{unsigned ,unsigned } static inline hex_space_to_u32(const char str[])
{
  unsigned len = 0;
  unsigned d = 0;
  while (len < 8 && str[len] != ' ')
  {
     d = (d << 4) | readHex_u4(str[len++]);
  }
  if (str[len] != ' ') len = 0;
  return {d,len};
}

static inline void u8To2Hex(unsigned char num,char * &str)
{
  *str = getHexChar(num >> 4);
  str++;
  *str = getHexChar(num & 0x0F);
  str++;
}

/*
 * Convert number to 2 hex characters
 */
static inline unsigned u8ToHex(unsigned num, char dest[])
{
  unsigned pos = 0;
  if (num >> 4)
    dest[pos++] = getHexChar(num >> 4);
  dest[pos++] = getHexChar(num & 0x0F);
  return pos;
}

/*
 * Convert a buffer to hex ascii
 */
static inline unsigned DataToHex(const unsigned char data[],unsigned len,char dest[])
{
#if 0
  for (int i=0;i<len;i++)
  {
    u8ToHex(data[i],dest+i*2);
  }
  return len*2;
#else
  unsigned pos;
  for (pos = 0;pos< len;pos++)
  {
    dest[pos*2] = getHexChar(data[pos] >> 4);
    dest[pos*2+1] = getHexChar(data[pos] & 0x0F);
  }
  return pos*2;
#endif
}

/*
 * Convert hex buffer to binary data
 * 0 error
 * 1 success
 */
unsigned static inline hex_to_binary(const char str[],unsigned char buff[max],unsigned max)
{
  unsigned v = 0;
  unsigned pos = 0;
  for (unsigned i=0;v< 0x100 && i<max;i++)
  {
    v = (readHex_u4(str[pos++]) << 4) | readHex_u4(str[pos++]);
    buff[i] = v;
  }
  return (v < 0x100);
}
/*
 * return bytes processed,
 * 0 if error ocurred
 * n - numbers of byte converted sucessfully
 */
unsigned static inline hexBuffer_to_u8(const char str[],unsigned char buff[max],unsigned max)
{
  unsigned v,len,pos;
  for (pos=0;pos<max;pos++)
  {
     {v,len} = readHex_u8_2(str + (pos<<1));
     if (len == 0) break;
     if (len == 1) {pos=0;break;}
     buff[pos] = v;
  }
  return pos;
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


//static inline char  *  alias strcpy_0(char* dest,const char* src)
//{
//  while ((*dest++ = *src++) != 0);
//  return dest;
//}

static inline unsigned strcpy_1(char* dest,const char* src)
{
  unsigned len = 0;
#if 1
  while ((*dest = *src) != 0)
  {
    ++dest;
    ++src;
    ++len;
  }
#else
  while(1)
  {
    *dest = *src;
    if (*dest == 0) break;
    dest++;
    src++;
    ++len;
  }
#endif
  return len;
}

static inline unsigned strcpy(char* dest,const char* src)
{
  unsigned len = 0;
  while (( dest[len] = src[len]) != 0) ++len;
  return len;
}
/*
 * rerturn value may alias arguments,
 * it means that point to same location than arguments do.
 * todo how to avoid bound checking
 */
static inline unsigned strcpy_2(char dest[],const char src[])
{
  unsigned len = 0;
  while ((dest[len] = src[len]) != 0)
  {
   len++;
  }
  return len;
}
/*
 * return
 * 1 match
 * 0 does not match
 * len
 */
{unsigned ,unsigned } static inline CheckPreffix(const char preffix[],const char str[])
{
  unsigned len = 0;
  while( preffix[len] == str[len] ) { ++len; }
  return {(preffix[len] == 0 &&  str[len] == ' '),len};
}

// print a ascii buffer
extern void printbuff(const char* d,unsigned len);


#endif /* UTILS_H_ */
