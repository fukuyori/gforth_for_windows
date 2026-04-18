#include <gforth-win32.h>
#include <dirent.h>
#include <errno.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <termios.h>
#include <unistd.h>

static HANDLE gforth_handle_from_fd(int fd) {
  intptr_t osf = _get_osfhandle(fd);
  if (osf == -1) {
    return INVALID_HANDLE_VALUE;
  }
  return (HANDLE)osf;
}

static DWORD gforth_protect_flags(int prot) {
  if ((prot & PROT_EXEC) && (prot & PROT_WRITE)) {
    return PAGE_EXECUTE_READWRITE;
  }
  if ((prot & PROT_EXEC) && (prot & PROT_READ)) {
    return PAGE_EXECUTE_READ;
  }
  if (prot & PROT_EXEC) {
    return PAGE_EXECUTE;
  }
  if (prot & PROT_WRITE) {
    return PAGE_READWRITE;
  }
  if (prot & PROT_READ) {
    return PAGE_READONLY;
  }
  return PAGE_NOACCESS;
}

static DWORD gforth_view_access(int prot) {
  DWORD access = 0;
  if (prot & PROT_WRITE) {
    access |= FILE_MAP_WRITE;
  }
  if (prot & PROT_READ) {
    access |= FILE_MAP_READ;
  }
  if (prot & PROT_EXEC) {
    access |= FILE_MAP_EXECUTE;
  }
  return access ? access : FILE_MAP_READ;
}

int gettimeofday(struct timeval *tv, struct timezone *tz) {
  FILETIME ft;
  ULARGE_INTEGER ticks;
  unsigned long long unix_time;

  if (tv == NULL) {
    errno = EINVAL;
    return -1;
  }

  GetSystemTimeAsFileTime(&ft);
  ticks.LowPart = ft.dwLowDateTime;
  ticks.HighPart = ft.dwHighDateTime;
  unix_time = ticks.QuadPart - 116444736000000000ULL;

  tv->tv_sec = (long)(unix_time / 10000000ULL);
  tv->tv_usec = (long)((unix_time % 10000000ULL) / 10ULL);

  if (tz != NULL) {
    tz->tz_minuteswest = 0;
    tz->tz_dsttime = 0;
  }

  return 0;
}

int asprintf(char **strp, const char *fmt, ...) {
  va_list args;
  va_list copy;
  int len;
  char *buffer;

  if (strp == NULL || fmt == NULL) {
    errno = EINVAL;
    return -1;
  }

  va_start(args, fmt);
  va_copy(copy, args);
  len = _vscprintf(fmt, copy);
  va_end(copy);
  if (len < 0) {
    va_end(args);
    return -1;
  }

  buffer = (char *)malloc((size_t)len + 1);
  if (buffer == NULL) {
    va_end(args);
    errno = ENOMEM;
    return -1;
  }

  vsnprintf(buffer, (size_t)len + 1, fmt, args);
  va_end(args);
  *strp = buffer;
  return len;
}

int getpagesize(void) {
  SYSTEM_INFO info;
  GetSystemInfo(&info);
  return (int)info.dwPageSize;
}

long sysconf(int name) {
  if (name == _SC_PAGESIZE) {
    return getpagesize();
  }
  errno = EINVAL;
  return -1;
}

DIR *opendir(const char *path) {
  DIR *dir;
  size_t path_len;

  if (path == NULL) {
    errno = EINVAL;
    return NULL;
  }

  dir = (DIR *)calloc(1, sizeof(*dir));
  if (dir == NULL) {
    return NULL;
  }

  path_len = strlen(path);
  if (path_len + 3 >= sizeof(dir->pattern)) {
    free(dir);
    errno = ENAMETOOLONG;
    return NULL;
  }

  memcpy(dir->pattern, path, path_len);
  if (path_len > 0 && path[path_len - 1] != '\\' && path[path_len - 1] != '/') {
    dir->pattern[path_len++] = '\\';
  }
  dir->pattern[path_len++] = '*';
  dir->pattern[path_len] = '\0';

  dir->handle = FindFirstFileA(dir->pattern, &dir->data);
  if (dir->handle == INVALID_HANDLE_VALUE) {
    free(dir);
    errno = ENOENT;
    return NULL;
  }

  dir->first = 1;
  return dir;
}

struct dirent *readdir(DIR *dir) {
  if (dir == NULL) {
    errno = EINVAL;
    return NULL;
  }

  for (;;) {
    WIN32_FIND_DATAA *data = &dir->data;

    if (!dir->first) {
      if (!FindNextFileA(dir->handle, data)) {
        return NULL;
      }
    }
    dir->first = 0;

    if (strcmp(data->cFileName, ".") == 0 || strcmp(data->cFileName, "..") == 0) {
      continue;
    }

    strncpy(dir->entry.d_name, data->cFileName, sizeof(dir->entry.d_name) - 1);
    dir->entry.d_name[sizeof(dir->entry.d_name) - 1] = '\0';
    return &dir->entry;
  }
}

int closedir(DIR *dir) {
  if (dir == NULL) {
    errno = EINVAL;
    return -1;
  }
  if (dir->handle != INVALID_HANDLE_VALUE) {
    FindClose(dir->handle);
  }
  free(dir);
  return 0;
}

static struct passwd *gforth_fill_passwd(const char *name) {
  static struct passwd pwd;
  static char username[256];
  static char homedir[MAX_PATH];
  static char shell[] = "cmd.exe";
  const char *env_name = getenv("USERNAME");
  const char *env_home = getenv("USERPROFILE");

  if (name != NULL) {
    strncpy(username, name, sizeof(username) - 1);
    username[sizeof(username) - 1] = '\0';
  } else if (env_name != NULL) {
    strncpy(username, env_name, sizeof(username) - 1);
    username[sizeof(username) - 1] = '\0';
  } else {
    strcpy(username, "windows");
  }

  if (env_home != NULL) {
    strncpy(homedir, env_home, sizeof(homedir) - 1);
    homedir[sizeof(homedir) - 1] = '\0';
  } else {
    strcpy(homedir, "C:\\");
  }

  pwd.pw_name = username;
  pwd.pw_dir = homedir;
  pwd.pw_shell = shell;
  return &pwd;
}

struct passwd *getpwuid(uid_t uid) {
  (void)uid;
  return gforth_fill_passwd(NULL);
}

struct passwd *getpwnam(const char *name) {
  const char *env_name = getenv("USERNAME");
  if (name == NULL) {
    return NULL;
  }
  if (env_name != NULL && _stricmp(name, env_name) != 0) {
    errno = ENOENT;
    return NULL;
  }
  return gforth_fill_passwd(name);
}

static void gforth_filetime_to_timeval(FILETIME ft, struct timeval *tv) {
  ULARGE_INTEGER ticks;
  ticks.LowPart = ft.dwLowDateTime;
  ticks.HighPart = ft.dwHighDateTime;
  tv->tv_sec = (long)(ticks.QuadPart / 10000000ULL);
  tv->tv_usec = (long)((ticks.QuadPart % 10000000ULL) / 10ULL);
}

int getrusage(int who, struct rusage *usage) {
  FILETIME create_time;
  FILETIME exit_time;
  FILETIME kernel_time;
  FILETIME user_time;

  if (who != RUSAGE_SELF || usage == NULL) {
    errno = EINVAL;
    return -1;
  }

  if (!GetProcessTimes(GetCurrentProcess(), &create_time, &exit_time, &kernel_time, &user_time)) {
    errno = EINVAL;
    return -1;
  }

  gforth_filetime_to_timeval(user_time, &usage->ru_utime);
  gforth_filetime_to_timeval(kernel_time, &usage->ru_stime);
  return 0;
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
  if ((flags & MAP_ANON) != 0) {
    void *ptr = VirtualAlloc(addr, length, MEM_COMMIT | MEM_RESERVE, gforth_protect_flags(prot));
    if (ptr == NULL) {
      errno = ENOMEM;
      return MAP_FAILED;
    }
    return ptr;
  }

  if (fd < 0) {
    errno = EINVAL;
    return MAP_FAILED;
  }

  HANDLE file_handle = gforth_handle_from_fd(fd);
  HANDLE mapping_handle;
  LARGE_INTEGER size;
  LARGE_INTEGER map_size;
  DWORD offset_low;
  DWORD offset_high;
  void *mapped;

  if (file_handle == INVALID_HANDLE_VALUE) {
    errno = EINVAL;
    return MAP_FAILED;
  }

  map_size.QuadPart = (LONGLONG)offset + (LONGLONG)length;
  size.QuadPart = map_size.QuadPart;

  mapping_handle = CreateFileMappingA(file_handle, NULL, gforth_protect_flags(prot), size.HighPart, size.LowPart, NULL);
  if (mapping_handle == NULL) {
    errno = ENOMEM;
    return MAP_FAILED;
  }

  offset_low = (DWORD)((unsigned long long)offset & 0xffffffffULL);
  offset_high = (DWORD)(((unsigned long long)offset >> 32) & 0xffffffffULL);
  mapped = MapViewOfFileEx(mapping_handle, gforth_view_access(prot), offset_high, offset_low, length, (flags & MAP_FIXED) ? addr : NULL);
  CloseHandle(mapping_handle);

  if (mapped == NULL) {
    errno = ENOMEM;
    return MAP_FAILED;
  }

  return mapped;
}

int munmap(void *addr, size_t length) {
  MEMORY_BASIC_INFORMATION info;
  (void)length;

  if (VirtualQuery(addr, &info, sizeof(info)) == 0) {
    errno = EINVAL;
    return -1;
  }

  if (info.Type == MEM_MAPPED || info.Type == MEM_IMAGE) {
    if (!UnmapViewOfFile(addr)) {
      errno = EINVAL;
      return -1;
    }
    return 0;
  }

  if (!VirtualFree(addr, 0, MEM_RELEASE)) {
    errno = EINVAL;
    return -1;
  }
  return 0;
}

int mprotect(void *addr, size_t length, int prot) {
  DWORD old_protect;
  if (!VirtualProtect(addr, length, gforth_protect_flags(prot), &old_protect)) {
    errno = EINVAL;
    return -1;
  }
  return 0;
}

int msync(void *addr, size_t length, int flags) {
  (void)addr;
  (void)length;
  (void)flags;
  return 0;
}

static int gforth_is_console_fd(int fd) {
  HANDLE handle = gforth_handle_from_fd(fd);
  DWORD mode = 0;
  return handle != INVALID_HANDLE_VALUE && GetConsoleMode(handle, &mode);
}

int tcgetattr(int fd, struct termios *tio) {
  HANDLE handle;
  DWORD mode = 0;

  if (tio == NULL) {
    errno = EINVAL;
    return -1;
  }

  memset(tio, 0, sizeof(*tio));
  tio->c_cflag = CS8;
  tio->c_cc[VMIN] = 1;

  handle = gforth_handle_from_fd(fd);
  if (handle == INVALID_HANDLE_VALUE || !GetConsoleMode(handle, &mode)) {
    return 0;
  }

  if ((mode & ENABLE_ECHO_INPUT) != 0) {
    tio->c_lflag |= ECHO;
  }
  if ((mode & ENABLE_LINE_INPUT) != 0) {
    tio->c_lflag |= ICANON;
  }
  if ((mode & ENABLE_PROCESSED_INPUT) != 0) {
    tio->c_lflag |= ISIG;
  }

  return 0;
}

int tcsetattr(int fd, int action, const struct termios *tio) {
  HANDLE handle;
  DWORD mode = 0;
  (void)action;

  if (tio == NULL) {
    errno = EINVAL;
    return -1;
  }

  handle = gforth_handle_from_fd(fd);
  if (handle == INVALID_HANDLE_VALUE || !GetConsoleMode(handle, &mode)) {
    return 0;
  }

  mode |= ENABLE_PROCESSED_INPUT;
  if ((tio->c_lflag & ECHO) != 0) {
    mode |= ENABLE_ECHO_INPUT;
  } else {
    mode &= ~ENABLE_ECHO_INPUT;
  }
  if ((tio->c_lflag & ICANON) != 0) {
    mode |= ENABLE_LINE_INPUT;
  } else {
    mode &= ~ENABLE_LINE_INPUT;
  }
  if ((tio->c_lflag & ISIG) == 0) {
    mode &= ~ENABLE_PROCESSED_INPUT;
  }

  if (!SetConsoleMode(handle, mode)) {
    errno = EINVAL;
    return -1;
  }
  return 0;
}

int tcflow(int fd, int action) {
  (void)fd;
  (void)action;
  return 0;
}

void cfmakeraw(struct termios *tio) {
  if (tio == NULL) {
    return;
  }
  memset(tio, 0, sizeof(*tio));
  tio->c_cflag = CS8;
  tio->c_cc[VMIN] = 1;
  tio->c_cc[VTIME] = 0;
}

int ioctl(int fd, unsigned long request, ...) {
  va_list args;
  void *arg;
  HANDLE handle;

  va_start(args, request);
  arg = va_arg(args, void *);
  va_end(args);

  handle = gforth_handle_from_fd(fd);
  if (handle == INVALID_HANDLE_VALUE) {
    errno = EBADF;
    return -1;
  }

  if (request == FIONREAD) {
    int *value = (int *)arg;
    if (value == NULL) {
      errno = EINVAL;
      return -1;
    }
    if (gforth_is_console_fd(fd)) {
      DWORD events = 0;
      if (!GetNumberOfConsoleInputEvents(handle, &events)) {
        errno = EINVAL;
        return -1;
      }
      *value = (int)events;
      return 0;
    }
    *value = 0;
    return 0;
  }

  if (request == TIOCGWINSZ) {
    CONSOLE_SCREEN_BUFFER_INFO info;
    struct winsize *size = (struct winsize *)arg;
    if (size == NULL) {
      errno = EINVAL;
      return -1;
    }
    if (!GetConsoleScreenBufferInfo(handle, &info)) {
      errno = ENOTTY;
      return -1;
    }
    size->ws_col = (unsigned short)(info.srWindow.Right - info.srWindow.Left + 1);
    size->ws_row = (unsigned short)(info.srWindow.Bottom - info.srWindow.Top + 1);
    size->ws_xpixel = 0;
    size->ws_ypixel = 0;
    return 0;
  }

  errno = ENOTSUP;
  return -1;
}

int poll(struct pollfd *fds, unsigned long nfds, int timeout) {
  unsigned long i;
  int ready = 0;

  if (fds == NULL) {
    errno = EINVAL;
    return -1;
  }

  for (i = 0; i < nfds; ++i) {
    int chars = 0;
    fds[i].revents = 0;
    if ((fds[i].events & POLLIN) != 0 && ioctl(fds[i].fd, FIONREAD, &chars) == 0 && chars > 0) {
      fds[i].revents |= POLLIN;
      ready++;
    }
  }

  if (ready == 0 && timeout > 0) {
    Sleep((DWORD)timeout);
  }

  return ready;
}

int sigemptyset(sigset_t *set) {
  if (set == NULL) {
    errno = EINVAL;
    return -1;
  }
  *set = 0;
  return 0;
}

int sigaddset(sigset_t *set, int sig) {
  if (set == NULL || sig < 0 || sig >= 63) {
    errno = EINVAL;
    return -1;
  }
  *set |= (1ULL << sig);
  return 0;
}

int sigprocmask(int how, const sigset_t *set, sigset_t *oldset) {
  (void)how;
  (void)set;
  if (oldset != NULL) {
    *oldset = 0;
  }
  return 0;
}

int sigaltstack(const stack_t *ss, stack_t *old_ss) {
  (void)ss;
  if (old_ss != NULL) {
    memset(old_ss, 0, sizeof(*old_ss));
  }
  return 0;
}

int sigaction(int sig, const struct sigaction *act, struct sigaction *oldact) {
  Sigfunc *previous;
  Sigfunc *handler;

  if (oldact != NULL) {
    memset(oldact, 0, sizeof(*oldact));
  }

#ifdef SIGWINCH
  if (sig == SIGWINCH) {
    return 0;
  }
#endif

  if (act == NULL) {
    return 0;
  }

  handler = (act->sa_flags & SA_SIGINFO) ? (Sigfunc *)act->sa_sigaction : (Sigfunc *)act->sa_handler;
  previous = signal(sig, handler);
  if (previous == SIG_ERR) {
    errno = EINVAL;
    return -1;
  }

  if (oldact != NULL) {
    oldact->sa_handler = previous;
  }
  return 0;
}
