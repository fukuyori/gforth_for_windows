#ifndef GFORTH_WIN32_SYS_RESOURCE_H
#define GFORTH_WIN32_SYS_RESOURCE_H

#include <sys/time.h>

#define RUSAGE_SELF 0

struct rusage {
  struct timeval ru_utime;
  struct timeval ru_stime;
};

int getrusage(int who, struct rusage *usage);

#endif
