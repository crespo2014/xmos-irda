/*
 * utils.xc
 *
 *  Created on: 6 Sep 2015
 *      Author: lester
 */

// read hexadecimal char and return number.

unsigned fromHexChar(const char str)
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

unsigned from2HexChar(const char* str)
{
  return getHexChar(*str) << 8 | getHexChar(*(str+1));
}

unsigned U4toHex(unsigned u4)
{
  return u4 + (u4 < 10) ? '0' : 'A';
}

void toHex(const unsigned char *d,unsigned len,char * &str)
{
  unsigned t;
  while (len--)
  {
    *str = U4toHex(*d >> 8);
    str++;
    *str = U4toHex(*d & 0x0F);
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

