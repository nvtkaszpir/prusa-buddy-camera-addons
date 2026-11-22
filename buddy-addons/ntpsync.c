/*
 * ntpsync: report whether the clock is synchronized by ntpd.
 * Exit 0 = synchronized, 1 = unsynchronized, 2 = adjtimex() error.
 *
 * Two checks, the first that says "synchronized" wins:
 * 1. The kernel clock state: adjtimex() with a zeroed struct timex is a read-only query (no root needed);
 *    unsynchronized while it returns TIME_ERROR or STA_UNSYNC is set.
 * 2. The local ntpd itself: one NTP client request (mode 3) to 127.0.0.1:123. ntpd answers with its system
 *    leap indicator and stratum; leap 0-2 and stratum 1-15 mean it has selected a source and the clock is
 *    within its step threshold. ntpd reaches this state seconds after it can reach a server, while the kernel
 *    flag of check 1 can stay set for many minutes after that (measured on the camera: ntpd logged
 *    clock_sync 7 s after start, STA_UNSYNC was still set 13 min later).
 */
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/timex.h>
#include <time.h>
#include <unistd.h>

#define NTP_UNIX_OFFSET 2208988800UL /* seconds from 1900-01-01 to 1970-01-01 */

/* 1 if the ntpd on 127.0.0.1 answers as synchronized, 0 otherwise (no answer, unsynchronized, error). */
static int local_ntpd_synchronized(void) {
  unsigned char req[48], rsp[48];
  struct sockaddr_in to;
  struct timeval tv = {1, 0};
  int fd, ok = 0;

  fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (fd < 0)
    return 0;
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

  memset(&to, 0, sizeof to);
  to.sin_family = AF_INET;
  to.sin_port = htons(123);
  to.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

  memset(req, 0, sizeof req);
  memset(rsp, 0, sizeof rsp);
  req[0] = (0 << 6) | (4 << 3) | 3; /* leap 0, version 4, mode 3 (client) */
  /* Transmit timestamp (seconds part): ntpd echoes it as the origin timestamp; checked below. */
  unsigned long now = (unsigned long)time(NULL) + NTP_UNIX_OFFSET;
  req[40] = now >> 24; req[41] = now >> 16; req[42] = now >> 8; req[43] = now;

  if (sendto(fd, req, sizeof req, 0, (struct sockaddr *)&to, sizeof to) == (ssize_t)sizeof req) {
    ssize_t n = recv(fd, rsp, sizeof rsp, 0);
    int leap = rsp[0] >> 6, mode = rsp[0] & 7, stratum = rsp[1];
    if (n >= 48 && mode == 4 && memcmp(rsp + 24, req + 40, 8) == 0 && leap != 3 && stratum >= 1 &&
        stratum <= 15)
      ok = 1;
  }
  close(fd);
  return ok;
}

int main(void) {
  struct timex tx;
  memset(&tx, 0, sizeof tx);

  int state = adjtimex(&tx);
  if (state == -1) {
    fprintf(stderr, "adjtimex: %s\n", strerror(errno));
    return 2;
  }
  if ((state != TIME_ERROR && !(tx.status & STA_UNSYNC)) || local_ntpd_synchronized()) {
    puts("synchronized");
    return 0;
  }
  puts("unsynchronized");
  return 1;
}
