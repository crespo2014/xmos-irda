/*
 * utils.xc
 *
 *  Created on: 6 Sep 2015
 *      Author: lester
 */

#include <stdio.h>

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
/*
 * str will point to last non-read character
 */
unsigned read32BitsHex(const char* &str)
{
  unsigned d = 0;
  for (int i=0;i<4;i++)
  {
    unsigned v = readHexChar(str);
    if (v > 0xFF) break;
    d = d << 8 | v;
  }
  return d;
}

/*
 * str will point to last character, it should be ' ' or \n otherwise an error ocurred
 */
unsigned  readHexBuffer(const char* &str,unsigned char* buff,unsigned max)
{
  unsigned v = 0;
  unsigned i = 0;
  while (i < max)
  {
    v = readHexByte(str);
    if (v > 0xFF) break;
    *buff = v;
    buff++;
    i++;
  }
  return i;
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

void u8ToHex(unsigned char num,char * &str)
{
  *str = getHexChar(num >> 4);
  str++;
  *str = getHexChar(num & 0x0F);
  str++;
}


#if 0
void strcpy(char* &dest,const char* src)
{
  while ((*dest = *src) != 0)
  {
    ++dest;
    ++src;
  }
}
#endif

/*
 * Str will point to last not equal value
 */


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


