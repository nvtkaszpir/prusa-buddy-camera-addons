# ntpsync (clock sync check)

Back to [README.md](README.md). Relies on the shared sections [Compile](README.md#compile),
[Install via microSD](README.md#install-via-microsd) and [Upload via telnet](README.md#upload-via-telnet).

## Artifact

| artifact | source | contents | size | sha256 |
|---|---|---|---|---|
| `out/ntpsync` | `ntpsync.c`, `build-ntpsync.sh` | static ARM EABI5 hard-float probe: prints `synchronized` or `unsynchronized` | 21732 B | `e78c5f14d41c87f228932da45854a59f013c25e0b4cddab0ddb662bddd4d9dc8` |

```sh
./build-ntpsync.sh                                # -> out/ntpsync
qemu-arm-static out/ntpsync; echo rc=$?           # synchronized / unsynchronized
```

## Install

On the card:

```
/mnt/sdcard/bin/ntpsync            <- out/ntpsync
```

```sh
cp out/ntpsync "$SD/bin/"
sync
```

The rsyslog start gate (see [rsyslog.md](rsyslog.md#what-happens-at-boot)) calls `/mnt/sdcard/bin/ntpsync`.

## Exit codes

| code | meaning |
|---|---|
| 0 | clock synchronized (kernel flag or local ntpd); stdout `synchronized` |
| 1 | neither check passed; stdout `unsynchronized` |
| 2 | `adjtimex()` failed; the strerror text goes to stderr |

## How it works

The clock counts as synchronized when either of two checks passes.

1. Kernel flag: `adjtimex()` on a zeroed `struct timex` (read-only, needs no root). It passes unless the call
   returns `TIME_ERROR` or `STA_UNSYNC` is set.
2. Local ntpd: one NTP client request (mode 3, version 4) to `127.0.0.1:123`. It passes when ntpd answers within
   1 s with mode 4, the echoed origin timestamp, leap indicator 0-2 and stratum 1-15. That means ntpd has selected
   a source and the clock is within its step threshold. The stock `ntp.conf` has `restrict 127.0.0.1` without
   `noserve` (firmware 3.1.3 and 3.1.6), so ntpd answers the query.

Why the second check: the stock ntpd keeps `STA_UNSYNC` set for about 12-14 minutes after it starts (847 s
measured once on firmware 3.1.6; rsyslogd started about 12 minutes after boot), although ntpd itself selects a
source and logs `clock_sync` within seconds (7 s after start with the network up). Measured on the camera: with
the stock ntpd running for 13 minutes the kernel flag alone said `unsynchronized` while the ntpd check said
`synchronized`; after an ntpd restart the ntpd check said `synchronized` 8 s later (`unsynchronized` at 0-7 s),
and the camera clock matched the host's to the second. At boot, though, the stock ntpd starts before the network
and stays unsynchronized for many minutes until it is restarted after the network is up (the cause was not
traced); the rsyslog waiter does that (see [rsyslog.md](rsyslog.md#what-happens-at-boot)). In a measured boot
with its restarts every 30 s, rsyslogd started 68 s after boot.

Restarting ntpd with a drift file did not help: at a real boot `STA_UNSYNC` was still set 436 s after boot.

The camera has no `ntpq`, and busybox has no `ntpd` applet, so the check speaks the NTP packet format itself.
