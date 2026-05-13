/*
 * stdint.h shim for HI-TECH C V4.11 — the V4.11 cross compiler predates
 * C99 and ships no <stdint.h>.  Provides only the types this project's
 * sources actually reach for.  Sized for Z80 (16-bit int).
 */
#ifndef _STDINT_H
#define _STDINT_H

typedef unsigned char   uint8_t;
typedef signed char     int8_t;
typedef unsigned short  uint16_t;
typedef signed short    int16_t;
typedef unsigned long   uint32_t;
typedef signed long     int32_t;

typedef uint16_t        size_t;
typedef int16_t         ssize_t;
typedef uint16_t        uintptr_t;
typedef int16_t         intptr_t;

#endif /* _STDINT_H */
