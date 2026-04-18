#ifndef GFORTH_WIN32_SYS_IOCTL_H
#define GFORTH_WIN32_SYS_IOCTL_H

#include <gforth-win32.h>

struct winsize {
  unsigned short ws_row;
  unsigned short ws_col;
  unsigned short ws_xpixel;
  unsigned short ws_ypixel;
};

#ifndef FIONREAD
#define FIONREAD 0x541B
#endif

#ifndef TIOCGWINSZ
#define TIOCGWINSZ 0x5413
#endif

int ioctl(int fd, unsigned long request, ...);

#endif
