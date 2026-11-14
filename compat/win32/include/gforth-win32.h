#ifndef GFORTH_WIN32_H
#define GFORTH_WIN32_H

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN 1
#endif

#ifndef NOMINMAX
#define NOMINMAX 1
#endif

#include <windows.h>
#include <corecrt_io.h>
#include <direct.h>
#include <process.h>
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#include <malloc.h>
#include <stdio.h>

#ifndef GFORTH_WIN32_CADDR_T
#define GFORTH_WIN32_CADDR_T
typedef char *caddr_t;
#endif

#ifndef alloca
#define alloca _alloca
#endif

/* POSIX stdio locking (used by read_line in engine/support.c) */
#ifndef flockfile
#define flockfile _lock_file
#endif
#ifndef funlockfile
#define funlockfile _unlock_file
#endif
#ifndef getc_unlocked
#define getc_unlocked _getc_nolock
#endif

int asprintf(char **strp, const char *fmt, ...);

#endif
