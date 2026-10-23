/* SPDX-License-Identifier: MIT */
/* Exit 0 if the kernel mapped a vDSO into this process (AT_SYSINFO_EHDR in the auxiliary
   vector). Built for AArch32 and ILP32 by run-kernel-test.sh.  */
#include <stdio.h>
#include <sys/auxv.h>

int
main (void)
{
  unsigned long vdso = getauxval (AT_SYSINFO_EHDR);
  printf ("vDSO at %#lx (%zu-bit pointers)\n", vdso, sizeof (void *) * 8);
  return vdso == 0;
}
