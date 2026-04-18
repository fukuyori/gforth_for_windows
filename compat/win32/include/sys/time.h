#ifndef GFORTH_WIN32_SYS_TIME_H
#define GFORTH_WIN32_SYS_TIME_H

#include <gforth-win32.h>
#include <time.h>

typedef struct fd_set {
  unsigned int fd_count;
  int fd_array[64];
} fd_set;

struct timeval {
  long tv_sec;
  long tv_usec;
};

struct timezone {
  int tz_minuteswest;
  int tz_dsttime;
};

int gettimeofday(struct timeval *tv, struct timezone *tz);
int select(int n, fd_set *a, fd_set *b, fd_set *c, struct timeval *timeout);

#endif
