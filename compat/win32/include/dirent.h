#ifndef GFORTH_WIN32_DIRENT_H
#define GFORTH_WIN32_DIRENT_H

#include <gforth-win32.h>

#ifndef PATH_MAX
#define PATH_MAX MAX_PATH
#endif

struct dirent {
  char d_name[PATH_MAX];
};

typedef struct DIR {
  HANDLE handle;
  WIN32_FIND_DATAA data;
  struct dirent entry;
  char pattern[PATH_MAX];
  int first;
} DIR;

DIR *opendir(const char *path);
struct dirent *readdir(DIR *dir);
int closedir(DIR *dir);

#endif
