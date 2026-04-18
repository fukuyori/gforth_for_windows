#ifndef GFORTH_WIN32_TERMIOS_H
#define GFORTH_WIN32_TERMIOS_H

#include <gforth-win32.h>

typedef unsigned int tcflag_t;
typedef unsigned char cc_t;
typedef unsigned int speed_t;

#define NCCS 32

struct termios {
  tcflag_t c_iflag;
  tcflag_t c_oflag;
  tcflag_t c_cflag;
  tcflag_t c_lflag;
  cc_t c_cc[NCCS];
};

#define BRKINT 0x0001
#define ICRNL  0x0002
#define INLCR  0x0004
#define INPCK  0x0010
#define ISTRIP 0x0020
#define IXON   0x0040
#define IXOFF  0x0080
#define IXANY  0x0100

#define OPOST  0x0001

#define CSIZE  0x0030
#define CS8    0x0030

#define ECHO    0x0001
#define ICANON  0x0002
#define ISIG    0x0004
#define IEXTEN  0x0008

#define VEOF 4
#define VEOL 11
#define VMIN 6
#define VTIME 5

#define TCOON 1
#define TCSADRAIN 1

int tcgetattr(int fd, struct termios *tio);
int tcsetattr(int fd, int action, const struct termios *tio);
int tcflow(int fd, int action);
void cfmakeraw(struct termios *tio);

#endif
