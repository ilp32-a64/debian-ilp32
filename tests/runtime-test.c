/* SPDX-License-Identifier: MIT */
/* Smoke test of the ILP32 runtime packages: libc, libm, iconv (gconv modules), NSS,
   threads, libatomic (16-byte atomics) and libgomp.  Exit status 0 when all pass.  */
#include <iconv.h>
#include <math.h>
#include <omp.h>
#include <pthread.h>
#include <pwd.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static int failures;

static void
check (int ok, const char *what)
{
  printf ("%s: %s\n", ok ? "ok" : "FAIL", what);
  if (!ok)
    failures++;
}

static void *
thread_fn (void *arg)
{
  return (char *) arg + 1;
}

int
main (void)
{
  check (sizeof (void *) == 4 && sizeof (long) == 4, "ILP32 type sizes");
  check (sizeof (time_t) == 8, "64-bit time_t");

  volatile double x = 2.0;
  check (fabs (sqrt (x) - 1.41421356) < 1e-6, "libm sqrt");

  /* Needs /usr/libilp32/gconv: ISO-8859-1 is not built into libc.  */
  iconv_t cd = iconv_open ("UTF-8", "ISO-8859-1");
  int iconv_ok = 0;
  if (cd != (iconv_t) -1)
    {
      char in[] = "\xe9", out[8] = { 0 };
      char *ip = in, *op = out;
      size_t il = 1, ol = sizeof out - 1;
      iconv_ok = iconv (cd, &ip, &il, &op, &ol) == 0 && strcmp (out, "\xc3\xa9") == 0;
      iconv_close (cd);
    }
  check (iconv_ok, "iconv ISO-8859-1 -> UTF-8 (gconv modules)");

  struct passwd *pw = getpwuid (0);
  check (pw != NULL && strcmp (pw->pw_name, "root") == 0, "NSS getpwuid(0)");

  pthread_t t;
  void *ret = NULL;
  static char buf[2];
  check (pthread_create (&t, NULL, thread_fn, buf) == 0 && pthread_join (t, &ret) == 0
	 && ret == buf + 1, "pthread create/join");

  static __int128 wide;
  __atomic_store_n (&wide, (__int128) 1 << 100, __ATOMIC_SEQ_CST);
  check (__atomic_load_n (&wide, __ATOMIC_SEQ_CST) == (__int128) 1 << 100,
	 "16-byte atomics (libatomic)");

  long sum = 0;
#pragma omp parallel for reduction(+ : sum) num_threads(2)
  for (int i = 1; i <= 1000; i++)
    sum += i;
  check (sum == 500500 && omp_get_max_threads () >= 1, "OpenMP reduction (libgomp)");

  printf ("%d failure(s)\n", failures);
  return failures != 0;
}
