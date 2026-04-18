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

#ifndef GFORTH_WIN32_CADDR_T
#define GFORTH_WIN32_CADDR_T
typedef char *caddr_t;
#endif

#ifndef alloca
#define alloca _alloca
#endif

int asprintf(char **strp, const char *fmt, ...);

#endif
