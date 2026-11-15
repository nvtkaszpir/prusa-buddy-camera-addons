# ntpsync (clock sync check)

Back to [README.md](README.md). Relies on the shared sections [Compile](README.md#compile),
[Install via microSD](README.md#install-via-microsd) and [Upload via telnet](README.md#upload-via-telnet).

## Artifact

| artifact | source | contents | size | sha256 |
|---|---|---|---|---|
| `out/ntpsync` | `ntpsync.c`, `build-ntpsync.sh` | static ARM EABI5 hard-float probe: prints `synchronized` or `unsynchronized` | 21732 B | `6d75809e28bd93567da82eee641c019ca1a59a0c7bdc2b64d82f96f77c8a958a` |

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
| 0 | kernel clock synchronized; stdout `synchronized` |
| 1 | kernel clock not synchronized; stdout `unsynchronized` |
| 2 | `adjtimex()` failed; the strerror text goes to stderr |

## How it works

The check reads the kernel clock state with `adjtimex()` on a zeroed `struct timex`. This call is read-only and
needs no root. It reports `unsynchronized` when the call returns `TIME_ERROR` or `STA_UNSYNC` is set. ntpd
clears that state once it has set the clock.

This is the kernel's state, not a query of ntpd's peers. The camera has no `ntpq`, and busybox has no `ntpd` applet.
