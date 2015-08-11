/*
 * rxtx.xc
 *
 *  Created on: 11 Aug 2015
 *      Author: lester.crespo
 */


#include "rxtx.h"

/*
 * Buffer manipulator.
 * Store until 4 blocks of 20 bytes each one
 */
struct frm_buff_4_t
{
  unsigned char use_count;  // how many frame with data
  unsigned char wr_pos;
  struct tx_frame_t* movable pfrm[4];
};

inline void buff4_init(struct frm_buff_4_t &buff)
{
  buff.use_count = 0;
  buff.wr_pos = 0;
}

/*
 * Get a frame from buffer
 */
inline unsigned char buff4_get(struct frm_buff_4_t &buff,struct tx_frame_t  * movable &old_p)
{
  if (buff.use_count == 0)
    return 0;
  unsigned char pos;
  pos = (buff.wr_pos +(4 - buff.use_count)) % 4;
  struct tx_frame_t  * movable tmp;
  tmp = move(old_p);
  old_p = move(buff.pfrm[pos]);
  buff.pfrm[pos] = move(tmp);
  buff.use_count--;
  return 1;
}
/*
 * Add a new frame to the buffer
 */
inline unsigned char buff4_push(struct frm_buff_4_t &buff,struct tx_frame_t  * movable &old_p)
{
  if (buff.use_count == 4)
      return 0;
  struct tx_frame_t  * movable tmp;
  old_p->len = 0;
  tmp = move(old_p);
  old_p = move(buff.pfrm[buff.wr_pos]);
  buff.pfrm[buff.wr_pos] = move(tmp);
  buff.use_count++;
  return 1;
}
