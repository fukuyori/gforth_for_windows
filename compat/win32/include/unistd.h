#ifndef GFORTH_WIN32_UNISTD_H
#define GFORTH_WIN32_UNISTD_H

#include <gforth-win32.h>
#include <BaseTsd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <stdio.h>
#include <time.h>
#include <wchar.h>

typedef SSIZE_T ssize_t;
typedef int pid_t;

#ifndef GFORTH_WIN32_UID_T
#define GFORTH_WIN32_UID_T
typedef unsigned int uid_t;
#endif

#ifndef F_OK
#define F_OK 0
#endif

#ifndef R_OK
#define R_OK 4
#endif

#ifndef W_OK
#define W_OK 2
#endif

#ifndef X_OK
#define X_OK 1
#endif

#ifndef _SC_PAGESIZE
#define _SC_PAGESIZE 1
#endif

#ifndef STDIN_FILENO
#define STDIN_FILENO 0
#endif

#ifndef STDOUT_FILENO
#define STDOUT_FILENO 1
#endif

#ifndef STDERR_FILENO
#define STDERR_FILENO 2
#endif

#define access _access
#define chdir _chdir
#define close _close
#define dup _dup
#define dup2 _dup2
#define fileno _fileno
#define getcwd _getcwd
#define isatty _isatty
#define lseek _lseek
#define read _read
#define rmdir _rmdir
#define unlink _unlink
#define write _write

#ifndef S_ISREG
#define S_ISREG(mode) (((mode) & _S_IFMT) == _S_IFREG)
#endif

#ifndef S_ISDIR
#define S_ISDIR(mode) (((mode) & _S_IFMT) == _S_IFDIR)
#endif

static inline pid_t getpgrp(void) {
  return (pid_t)_getpid();
}

static inline pid_t tcgetpgrp(int fd) {
  return _isatty(fd) ? (pid_t)_getpid() : (pid_t)-1;
}

static inline FILE *popen(const char *command, const char *mode) {
  return _popen(command, mode);
}

static inline int pclose(FILE *stream) {
  return _pclose(stream);
}

static inline struct tm *localtime_r(const time_t *source, struct tm *result) {
  return localtime_s(result, source) == 0 ? result : NULL;
}

static inline off_t ftello(FILE *stream) {
  return (off_t)ftell(stream);
}

static inline int fseeko(FILE *stream, off_t offset, int whence) {
  return fseek(stream, (long)offset, whence);
}

static inline int ftruncate(int fd, off_t length) {
  return _chsize_s(fd, (__int64)length) == 0 ? 0 : -1;
}

static inline int setenv(const char *name, const char *value, int overwrite) {
  if (!overwrite && getenv(name) != NULL) {
    return 0;
  }
  return _putenv_s(name, value);
}

static inline int wcwidth(wchar_t wc) {
  if (wc == 0) {
    return 0;
  }
  if (wc < 32 || (wc >= 0x7f && wc < 0xa0)) {
    return -1;
  }
  return 1;
}

static inline int gforth_mkdir_mode(const char *path, int mode) {
  (void)mode;
  return _mkdir(path);
}

#define mkdir(path, mode) gforth_mkdir_mode(path, mode)

static inline int usleep(unsigned int usec) {
  Sleep((usec + 999U) / 1000U);
  return 0;
}

static inline unsigned int sleep(unsigned int seconds) {
  Sleep(seconds * 1000U);
  return 0;
}

static inline uid_t getuid(void) {
  return 0;
}

int getpagesize(void);
long sysconf(int name);

#endif
