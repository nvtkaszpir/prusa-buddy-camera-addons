# NTP: clock sync at boot

How the camera's clock gets synchronized, why the [rsyslog](../features/rsyslog.md) add-on used to wait about
12 minutes after boot before it started, and what changed so it now starts after about a minute. Measured on the
maintainer's camera (firmware 3.1.6, Wi-Fi) on 2026-11-22. Claims not directly backed by a measurement are marked
**[INFERENCE]**.

## Summary

- The clock itself is right from the start: the RTC keeps the time across reboots, and `lp_app` found a drift of
  -1 s right after boot (`syncSystemTimeFromAPI: ... drift=-1s threshold=120s`).
- What was slow is the *synchronized* state that the rsyslog start gate waits for. The old
  `ntpsync` read only the kernel flag (`STA_UNSYNC`), which the stock ntpd leaves set for many minutes.
- The fix has two parts, both in the add-ons:
  1. `ntpsync` also asks the local ntpd whether it has selected a time source (one NTP query to
     `127.0.0.1:123`); that state is reached seconds after ntpd can talk to a server.
  2. The rsyslog start waiter restarts ntpd while Wi-Fi is up but the clock is not yet synchronized: at once,
     then every 30 s, at most 10 times. The ntpd started at boot does not become synchronized by itself for many
     minutes, and the first restart right after Wi-Fi comes up does not always help either.
- Result: rsyslogd started 68 s after boot instead of about 12 minutes.
- A drift file for ntpd, the usual way to shorten ntpd's start-up, was tried and did not help at boot.

## Boot timings

Each row is one boot, timed from the kernel's uptime (`/proc/uptime`, and field 22 of `/proc/<pid>/stat` for
when rsyslogd started).

| setup | clock reported synchronized | rsyslogd started |
|---|---|---|
| old `ntpsync` (kernel flag only), stock ntpd | after about 12 min | about 12 min |
| ntpd with a drift file (seeded `0.000`), old `ntpsync` | not yet at 436 s | not yet at 436 s |
| new `ntpsync`, no ntpd restart | not yet at 300 s | not yet at 300 s |
| new `ntpsync`, one ntpd restart at 26 s | 335 s | 338 s |
| new `ntpsync`, restarts every 60 s (2nd at 88 s) | about 99 s | 99 s |
| new `ntpsync`, restarts every 30 s (2nd at 57 s), shipped | about 68 s | 68 s |

In the 26 s, 60 s and 30 s rows `/etc/resolv.conf` already listed both DNS servers at the first restart (the
waiter logs the count).

## How ntpd is started

- `/oem/usr/etc/init.d/S10ntp` runs `ntpd -g -p /var/run/ntpd.pid -c /oem/usr/etc/ntp.conf` about 2 s after
  boot (the ntpd process had a start time of 2.17 s), long before Wi-Fi has an address. The binary is
  `/oem/usr/bin/ntpd` (ntp.org 4.2.8p15); `/oem/usr/bin` is not in the `PATH` of an ssh session, so call it with
  the full path there.
- `ntp.conf` names `prusa3d.pool.ntp.org` (`iburst prefer`) and `0`-`3.pool.ntp.org` (`iburst`). It has no
  `driftfile`, in 3.1.3 and in 3.1.6. 3.1.6 adds `noserve` to the default restriction, `restrict source` for the
  servers and `tinker panic 0`. `restrict 127.0.0.1` has no `noserve`, so ntpd answers queries from the camera
  itself, which the new `ntpsync` relies on.
- The camera has no `ntpq`, and the BusyBox has no `ntpd` applet.

## Kernel flag versus ntpd's own state

The kernel's `STA_UNSYNC` flag (read with `adjtimex()`) is set by ntpd. ntpd clears it only some time after it has
itself decided that the clock is synchronized:

- After a manual restart with the network up (the stock config plus a drift file and `logconfig =all`, see
  [Method](#method)), ntpd's log showed the DNS answers for all five server names within 1 s and `clock_sync`
  7 s after start, followed only by `kernel reports TIME_ERROR: 0x41: Clock Unsynchronized`; the kernel flag was
  still set 13 minutes later.
- With that ntpd running for 13 minutes, the old `ntpsync` said `unsynchronized` and the new one `synchronized`.
  The camera clock matched the host's to the second.
- Timed from an unsynchronized kernel clock (set with `date -s` to the current time) with the network up, the
  kernel flag was cleared 847 s after a restart of the stock ntpd. [INFERENCE: without a drift file, ntpd
  first measures the clock frequency and only then clears the flag.]

The new `ntpsync` therefore also sends one NTP client request (mode 3) to `127.0.0.1:123` and passes when ntpd
answers within 1 s with mode 4, the echoed origin timestamp, a leap indicator of 0-2 and a stratum of 1-15, i.e.
ntpd has selected a source and the clock is within its step threshold. After a restart of the stock ntpd it
passed after 8 s (`unsynchronized` from 0 to 7 s). Its exit codes and output did not change (`buddy-addons/ntpsync.md`
in the repository).

## The ntpd started at boot

With the new `ntpsync`, the ntpd that `S10ntp` starts at boot was still not synchronized 300 s after boot, by
either check. Restarting it then with the same command line gave `synchronized` 7 s later.

A restart right after Wi-Fi comes up does not always work: in one boot the waiter restarted ntpd at 26 s and the
clock was reported synchronized only at 335 s. With a second restart 30 or 60 s after the first, the clock was
synchronized within about 11 s of that second restart. Hence the retries.

Why the boot-time ntpd and the first restart do not synchronize was not traced. `/etc/resolv.conf` already
listed the DNS servers, so missing DNS configuration is not the cause at the first restart. Possible causes are
DNS lookups that fail while the network comes up and are then retried at growing intervals, or a network path
that is not usable yet right after Wi-Fi associates [INFERENCE for both]. ntpd at boot logs to syslog
(`/dev/log`), which does not exist until rsyslogd runs, so its early messages are lost.

## The drift file attempt

A drift file normally lets ntpd skip measuring the clock frequency after a start. An add-on was built for it:
ntpd restarted from the boot hook with the stock config plus `driftfile /userdata/ntp/ntp.drift` (seeded
`0.000`). It was removed again because it did not help:

- One early test, with the network up and after `date -s`, cleared the kernel flag 75 s after the restart, against
  847 s for the stock config in the same test. That was a single run each, with the kernel's clock discipline
  already tuned by an ntpd that had been running for hours [INFERENCE: why it was fast].
- At a real boot, with the hook restarting ntpd with the drift file before Wi-Fi was up, the kernel flag was still
  set 436 s after boot.
- A restart with the drift file and the network up, 7 minutes after boot: ntpd logged `clock_sync` after 7 s, the
  kernel flag was still set 13 minutes later.

## Method

- Sync state: `/mnt/sdcard/bin/ntpsync` every 5 s over ssh, with `/proc/uptime` and the start time of rsyslogd
  (field 22 of `/proc/<pid>/stat`, in clock ticks of 1/100 s [INFERENCE: tick rate]).
- ntpd's own view, without `ntpq`: a copy of the config with two extra lines, then ntpd restarted with it:

    ```sh
    cp /oem/usr/etc/ntp.conf /tmp/ntpdbg.conf
    printf 'logfile /tmp/ntpdbg.log\nlogconfig =all\n' >> /tmp/ntpdbg.conf
    kill "$(cat /var/run/ntpd.pid)"; sleep 2; rm -f /var/run/ntpd.pid
    /oem/usr/bin/ntpd -g -p /var/run/ntpd.pid -c /tmp/ntpdbg.conf
    cat /tmp/ntpdbg.log        # DNS answers, clock_sync, kernel TIME_ERROR messages
    ```

- An unsynchronized kernel clock for a timing test: `date -s "$(date '+%Y-%m-%d %H:%M:%S')"` sets the time (a
  loss of under a second) and with it `STA_UNSYNC`.
- The restarts done by the rsyslog waiter are logged in `/mnt/sdcard/logs/rsyslog.log`, e.g.
  `restarted ntpd (2 nameserver(s) in /etc/resolv.conf): ntpd -g -p /var/run/ntpd.pid -c /oem/usr/etc/ntp.conf`.

## On firmware 3.1.7

`lp_app` 3.1.7 restarts ntpd itself with `-c /tmp/ntp.conf` when `NTP_SERVER` is set in `/mnt/sdcard/srv_cfg.txt`
(see [3.1.7 differences](cam-3.1.7-diff.md#lp_app-manages-ntpd)). The rsyslog waiter restarts whatever ntpd runs
with that ntpd's own command line, so such a setup is kept. Not tested on 3.1.7.
