#ifndef GFORTH_WIN32_SIGNAL_H
#define GFORTH_WIN32_SIGNAL_H

#ifdef __has_include_next
#include_next <signal.h>
#else
#include <signal.h>
#endif

#include <stddef.h>

typedef unsigned long long sigset_t;
typedef void Sigfunc(int);

typedef struct siginfo_t {
  int si_signo;
  int si_code;
  void *si_addr;
} siginfo_t;

typedef struct sigaltstack {
  void *ss_sp;
  size_t ss_size;
  int ss_flags;
} stack_t;

struct sigaction {
  union {
    void (*sa_handler)(int);
    void (*sa_sigaction)(int, siginfo_t *, void *);
  } handler;
  sigset_t sa_mask;
  int sa_flags;
};

#define sa_handler handler.sa_handler
#define sa_sigaction handler.sa_sigaction

#ifndef SIG_BLOCK
#define SIG_BLOCK 0
#endif

#ifndef SIG_SETMASK
#define SIG_SETMASK 1
#endif

#ifndef SA_RESTART
#define SA_RESTART 0x0001
#endif

#ifndef SA_NODEFER
#define SA_NODEFER 0x0002
#endif

#ifndef SA_SIGINFO
#define SA_SIGINFO 0x0004
#endif

#ifndef SA_ONSTACK
#define SA_ONSTACK 0x0008
#endif

#ifndef SIGWINCH
#define SIGWINCH 28
#endif

int sigemptyset(sigset_t *set);
int sigaddset(sigset_t *set, int sig);
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset);
int sigaltstack(const stack_t *ss, stack_t *old_ss);
int sigaction(int sig, const struct sigaction *act, struct sigaction *oldact);

#endif
