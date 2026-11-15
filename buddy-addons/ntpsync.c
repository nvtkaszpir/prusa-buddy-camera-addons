/*
 * ntpsync: report whether the kernel clock is synchronized (set by ntpd).
 * Exit 0 = synchronized, 1 = unsynchronized, 2 = adjtimex() error.
 * adjtimex() with a zeroed struct timex is a read-only query; no root needed.
 */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/timex.h>

int main(void) {
  struct timex tx;
  memset(&tx, 0, sizeof tx);

  int state = adjtimex(&tx);
  if (state == -1) {
    fprintf(stderr, "adjtimex: %s\n", strerror(errno));
    return 2;
  }
  if (state == TIME_ERROR || (tx.status & STA_UNSYNC)) {
    puts("unsynchronized");
    return 1;
  }
  puts("synchronized");
  return 0;
}
