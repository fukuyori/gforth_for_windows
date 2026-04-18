#ifndef GFORTH_WIN32_PWD_H
#define GFORTH_WIN32_PWD_H

#include <sys/types.h>

#ifndef GFORTH_WIN32_UID_T
#define GFORTH_WIN32_UID_T
typedef unsigned int uid_t;
#endif

struct passwd {
  char *pw_name;
  char *pw_dir;
  char *pw_shell;
};

struct passwd *getpwuid(uid_t uid);
struct passwd *getpwnam(const char *name);

#endif
