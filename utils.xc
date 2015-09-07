/*
 * utils.xc
 *
 *  Created on: 6 Sep 2015
 *      Author: lester
 */

// read hexadecimal char and return number.

unsigned readHexChar(char str)
{
  do
  {
    if (str < '0') break;
    if (str <= '9')
    {
      return str - '0';
    }
    if (str < 'A') break;
    if (str <= 'F')
      return (str - 'A' + 10);
    if (str < 'a') break;
    if (str > 'f') break;
    return str - 'a' + 10;
  } while(0);
  return 0xFFF;
}

unsigned readHexByte(const char* &str)
{
  return readHexChar(*str++) << 4 | readHexChar(*str++);
}

unsigned getHexChar(unsigned u4)
{
  return u4 + (u4 < 10) ? '0' : 'A';
}

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

void strcpy(char* &dest,const char* src)
{
  while ((*dest = *src) != 0)
  {
    ++dest;
    ++src;
  }
}

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

