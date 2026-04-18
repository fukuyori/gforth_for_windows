#ifndef GFORTH_WIN32_POLL_H
#define GFORTH_WIN32_POLL_H

#include <sys/types.h>

struct pollfd {
  int fd;
  short events;
  short revents;
};

#define POLLIN 0x0001

int poll(struct pollfd *fds, unsigned long nfds, int timeout);

#endif
