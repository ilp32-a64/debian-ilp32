// SPDX-License-Identifier: MIT
/*
 * seccomp arch test for AArch64 ILP32 and LP64: which AUDIT_ARCH a task reports, and how
 * filters written for AArch64 treat it. Build static for ILP32 and for LP64; each copy
 * checks the behaviour expected for its own ABI.
 *   T1 seccomp_data.arch: a filter that allows only the expected arch value
 *   T2 an AArch64-only filter (other arch -> kill): ILP32 must be killed, LP64 must not
 *   T3 the action cache: arch == AArch64 ? allow : errno 77, getpid three times; ILP32 must
 *      get errno 77 every time (a cached native result would allow it)
 *   T4 SIGSYS si_arch from SECCOMP_RET_TRAP
 *   T5 a deny-list written for AArch64 numbers (clock_settime 112 -> errno 1, other arch ->
 *      kill): ILP32 calling clock_settime64 (404) must be killed, not let through
 * Exit 0 if all pass. Prints "seccomp-arch: <n> failed".
 */
#define _GNU_SOURCE
#include <errno.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef AUDIT_ARCH_AARCH64ILP32
#define AUDIT_ARCH_AARCH64ILP32 (AUDIT_ARCH_AARCH64 | 0x10000000)
#endif
#ifdef __ILP32__
#define EXPECT AUDIT_ARCH_AARCH64ILP32
#define ABI "ilp32"
#else
#define EXPECT AUDIT_ARCH_AARCH64
#define ABI "lp64"
#endif

static int failed;
static void result(const char *name, int ok, const char *detail)
{
	printf("  %s %s %s\n", ok ? "ok  " : "FAIL", name, detail);
	if (!ok)
		failed++;
}

static int install(struct sock_filter *f, unsigned short n)
{
	struct sock_fprog prog = { .len = n, .filter = f };
	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0))
		return -1;
	return syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, 0, &prog);
}

#define LD_ARCH BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch))
#define LD_NR BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr))
#define RET(v) BPF_STMT(BPF_RET | BPF_K, (v))

/* run fn in a child; return its wait status */
static int child(int (*fn)(void))
{
	pid_t p = fork();
	int st;
	if (p == 0)
		_exit(fn());
	waitpid(p, &st, 0);
	return st;
}

static int t1(void)
{
	struct sock_filter f[] = {
		LD_ARCH,
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, EXPECT, 0, 1),
		RET(SECCOMP_RET_ALLOW),
		RET(SECCOMP_RET_KILL_PROCESS),
	};
	if (install(f, 4))
		return 2;
	syscall(SYS_getpid);
	return 0;
}

static int t2(void)
{
	struct sock_filter f[] = {
		LD_ARCH,
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_AARCH64, 0, 1),
		RET(SECCOMP_RET_ALLOW),
		RET(SECCOMP_RET_KILL_PROCESS),
	};
	if (install(f, 4))
		return 2;
	syscall(SYS_getpid);
	return 0;
}

static int t3(void)
{
	/* only getpid is filtered by arch, so that exit and write still work */
	struct sock_filter f[] = {
		LD_NR,
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_getpid, 1, 0),
		RET(SECCOMP_RET_ALLOW),
		LD_ARCH,
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_AARCH64, 0, 1),
		RET(SECCOMP_RET_ALLOW),
		RET(SECCOMP_RET_ERRNO | 77),
	};
	int i, denied = 0;
	if (install(f, 7))
		return 2;
	for (i = 0; i < 3; i++) {
		long r = syscall(SYS_getpid);
		if (r == -1 && errno == 77)
			denied++;
	}
	return denied == 3 ? 10 : denied == 0 ? 11 : 12;
}

static volatile unsigned int got_arch;
static void on_sys(int sig, siginfo_t *si, void *uc)
{
	(void)sig; (void)uc;
	got_arch = si->si_arch;
}

static int t4(void)
{
	struct sock_filter f[] = {
		LD_NR,
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_getppid, 0, 1),
		RET(SECCOMP_RET_TRAP),
		RET(SECCOMP_RET_ALLOW),
	};
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = on_sys;
	sa.sa_flags = SA_SIGINFO;
	sigaction(SIGSYS, &sa, NULL);
	if (install(f, 4))
		return 2;
	syscall(SYS_getppid);
	return got_arch == EXPECT ? 0 : 3;
}

static int t5(void)
{
	/* what a deny-list built for aarch64 looks like: wrong arch -> kill, then deny by number */
	struct sock_filter f[] = {
		LD_ARCH,
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_AARCH64, 1, 0),
		RET(SECCOMP_RET_KILL_PROCESS),
		LD_NR,
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, 112 /* clock_settime */, 0, 1),
		RET(SECCOMP_RET_ERRNO | 1),
		RET(SECCOMP_RET_ALLOW),
	};
	if (install(f, 7))
		return 2;
#ifdef __ILP32__
	syscall(404 /* clock_settime64 */, 0, (void *)0);
#else
	syscall(112, 0, (void *)0);
#endif
	return 0;
}

static int killed_by_sys(int st)
{
	return WIFSIGNALED(st) && WTERMSIG(st) == SIGSYS;
}

int main(void)
{
	char d[96];
	int st;

	printf("seccomp-arch (%s): expecting arch %#x\n", ABI, (unsigned int)EXPECT);
	st = child(t1);
	snprintf(d, sizeof(d), "(status %#x)", st);
	result("T1 arch value", WIFEXITED(st) && WEXITSTATUS(st) == 0, d);

	st = child(t2);
	snprintf(d, sizeof(d), "(status %#x)", st);
#ifdef __ILP32__
	result("T2 AArch64-only filter kills ILP32", killed_by_sys(st), d);
#else
	result("T2 AArch64-only filter allows LP64", WIFEXITED(st) && WEXITSTATUS(st) == 0, d);
#endif

	st = child(t3);
	snprintf(d, sizeof(d), "(exit %d: 10 all denied, 11 none, 12 mixed)", WIFEXITED(st) ? WEXITSTATUS(st) : -1);
#ifdef __ILP32__
	result("T3 cache never allows the other arch", WIFEXITED(st) && WEXITSTATUS(st) == 10, d);
#else
	result("T3 cache allows native", WIFEXITED(st) && WEXITSTATUS(st) == 11, d);
#endif

	st = child(t4);
	snprintf(d, sizeof(d), "(status %#x)", st);
	result("T4 SIGSYS si_arch", WIFEXITED(st) && WEXITSTATUS(st) == 0, d);

	st = child(t5);
	snprintf(d, sizeof(d), "(status %#x)", st);
#ifdef __ILP32__
	result("T5 AArch64 deny-list does not let clock_settime64 through", killed_by_sys(st), d);
#else
	result("T5 AArch64 deny-list runs normally for LP64", WIFEXITED(st) && WEXITSTATUS(st) == 0, d);
#endif

	printf("seccomp-arch: %d failed\n", failed);
	return failed ? 1 : 0;
}
