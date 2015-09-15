/*
 * utils.xc
 *
 *  Created on: 6 Sep 2015
 *      Author: lester
 */

#include "stdio.h"

// read hexadecimal char and return number.

unsigned readHexChar(const char *&str)
{
  do
  {
    if (*str < '0') break;
    if (*str <= '9')
    {
      return *str++ - '0';
    }
    if (*str < 'A') break;
    if (*str <= 'F')
      return (*str++ - 'A' + 10);
    if (*str < 'a') break;
    if (*str > 'f') break;
    return *str++ - 'a' + 10;
  } while(0);
  return 0xFFF;
}

unsigned readHexByte(const char* &str)
{
  unsigned v;
  v = readHexChar(str);
  v <<= 4;
  v |=  readHexChar(str);
  return v;
}

unsigned getHexChar(unsigned u4)
{
  return u4 + (u4 < 10) ? '0' : 'A';
}
/*
 * Convert a data buffer to hex char string
 * d : pointer to buffer
 * len : len of buffer
 * str : output string
 */
void getHexBuffer(const unsigned char *d,unsigned len,char * &str)
{
  while (len--)
  {
    *str = getHexChar(*d >> 4);
    str++;
    *str = getHexChar(*d & 0x0F);
    str++;
    d++;
  }

}
#if 1
void strcpy(char* &dest,const char* src)
{
  while ((*dest = *src) != 0)
  {
    ++dest;
    ++src;
  }
}
#endif

unsigned isPreffix(const char* pref,const char *str,const char *&last)
{
  last = str;
  while (*pref == *last)
  {
    ++pref;
    ++last;
  }
  return (*pref == 0);
}

void printbuff(const char* d,unsigned len)
{
  while (len--)
  {
    if (*d < ' ')
      printf("\\x%X",*d);
    else
      printf("%c",*d);
    d++;
  }
}


