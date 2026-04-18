#ifndef GFORTH_WIN32_SYS_MMAN_H
#define GFORTH_WIN32_SYS_MMAN_H

#include <stddef.h>
#include <sys/types.h>

#define PROT_NONE 0x00
#define PROT_READ 0x01
#define PROT_WRITE 0x02
#define PROT_EXEC 0x04

#define MAP_FILE 0x0000
#define MAP_PRIVATE 0x0002
#define MAP_FIXED 0x0010
#define MAP_ANON 0x0020
#define MAP_ANONYMOUS MAP_ANON
#define MAP_NORESERVE 0
#define MAP_32BIT 0

#define MAP_FAILED ((void *)-1)

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int munmap(void *addr, size_t length);
int mprotect(void *addr, size_t length, int prot);
int msync(void *addr, size_t length, int flags);

#endif
