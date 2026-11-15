# logrotate

Back to [README.md](README.md). Relies on the shared sections [Compile](README.md#compile) and
[Install via microSD](README.md#install-via-microsd). Standalone: no other add-on is needed, but it
rotates logs written by [dropbear.md](dropbear.md), [lighttpd.md](lighttpd.md) and
[rsyslog.md](rsyslog.md).

## Artifact

| artifact | source | contents | size | sha256 |
|---|---|---|---|---|
| `out/logrotate` | logrotate 3.22.0 + popt 1.19, `build-logrotate.sh` | logrotate, static, no SELinux, no ACL | 321228 B | `4bbccaa6e00576919a056831cf57f50601e52407caa1b3fc618decce122d6eec` |

```sh
./build-logrotate.sh                                   # -> out/logrotate
qemu-arm-static out/logrotate --version                # logrotate 3.22.0
```

## What is rotated

| file | writer | how it is reopened |
|---|---|---|
| `/mnt/sdcard/logs/dropbear.log` | `start-sshd.sh` (`>>`) | copytruncate |
| `/mnt/sdcard/logs/httpd.log` | `start-httpd.sh` (`>>`) | copytruncate |
| `/mnt/sdcard/logs/rsyslog.log` | `start-rsyslog.sh` (`>>`), tailed by rsyslog | copytruncate |
| `/tmp/dropbear.log` | dropbear daemon (stderr, `O_APPEND`) | copytruncate |
| `/tmp/lighttpd.log` | lighttpd error log | renamed, then `SIGHUP` to lighttpd, which reopens it |

Settings in [logrotate.conf](device/logrotate.conf): `daily`, `rotate 7`, `dateext` with
`-%Y%m%d`, `nocompress`, `missingok`, `notifempty`, `nocreate`, `su root root`.

Not rotated: lp_app's own `/mnt/sdcard/logs/YYYY-MM-DD_HH.log` files. They were about 583 MB at the
last check, and lp_app writes them.

Why copytruncate for the card logs: rsyslog's `imfile` tails `/mnt/sdcard/logs/*.log`, so the card
logs must keep their names. The rotated copies are named `name.log-YYYYMMDD`, which does not match
`*.log`, so they are not forwarded again. copytruncate shrinks the file under imfile, so
[rsyslog.conf](device/rsyslog.conf) sets `reopenOnTruncate="on"` on that input. Without it imfile
keeps its old offset past the new end of file and skips the lines written after the truncate. The
copytruncate step itself can lose the lines written between the copy and the truncate.

Why `su root root`: logrotate refuses files whose directory is writable by others. The card is vfat
mounted 777, and `/tmp` is 1777.

Why `nocreate`: vfat ignores chown, and `create` chowns the new file. Writers create the file again
on their next write, or lighttpd does on `SIGHUP`.

## Install

On the card, next to the other add-on files in `/mnt/sdcard/bin/`:

```
/mnt/sdcard/bin/logrotate              <- out/logrotate
/mnt/sdcard/bin/logrotate.conf         <- device/logrotate.conf
/mnt/sdcard/bin/start-logrotate.sh     <- device/start-logrotate.sh
```

Paste the block from `device/logrotate-hook.sh` into `/mnt/sdcard/lp_app.sh`, right before
`/tmp/sync_loop.sh` and after the syslog block (see
[Install via microSD](README.md#install-via-microsd)).

## How it runs

`start-logrotate.sh` runs at boot from the hook. It:

- copies `logrotate` to `/userdata/bin/` and `logrotate.conf` to `/userdata/logrotate/` when the md5
  differs (card wins);
- starts an hourly loop from `/tmp/logrotate-loop.sh`. Each hour the loop calls logrotate, unless the
  clock is still before 2025.

logrotate's state file `/userdata/logrotate/status` (survives reboot) decides when "daily" is due.

```sh
sh /mnt/sdcard/bin/start-logrotate.sh run    # rotate now, if due
sh /mnt/sdcard/bin/start-logrotate.sh stop   # stop the hourly loop
/userdata/bin/logrotate -f -s /userdata/logrotate/status /userdata/logrotate/logrotate.conf   # force
```

Start steps and logrotate errors go to `/mnt/sdcard/logs/logrotate.log`.

Notes:

- A log with no state entry gets the time of its first check as its last rotation. The first daily
  rotation therefore happens the next day. Use the forced command above to rotate at once.
- logrotate refuses to rotate a file when its dated copy already exists. A second forced run on the
  same day therefore skips every file (`destination ... already exists, skipping rotation`). For a
  repeatable test, use a second config with a different `dateformat`, as the verification below did.
- The loop runs from `/tmp`, so the card can be unmounted and remounted under it.
- `/tmp` logs and their rotated copies are lost on reboot.
- Migration: a copytruncate done while rsyslogd ran without `reopenOnTruncate` leaves imfile offsets
  past the new end of file. To fix one, stop rsyslogd, delete the matching
  `/userdata/rsyslog/work/imfile-state:*` file (the one whose `filename` is that log), and start
  rsyslogd again. imfile then starts that file from its end.

## Verified

On the camera (2026-11-01):

- `logrotate --version` runs (static ARM build); the config parses without errors.
- The forced rotation (`-f`) rotated the card logs and the two `/tmp` logs. The originals were
  truncated in place, and dated copies were created.
- After the lighttpd rotation, the new `/tmp/lighttpd.log` starts with `logfiles cycled`. lighttpd
  still answers on port 8080 (401 without credentials).
- rsyslogd and the loop were still running after the rotation.
- With `reopenOnTruncate="on"`, a copytruncate of `dropbear.log` between two marker lines: after a
  clean rsyslogd stop, the saved imfile offset was 25, the file size. Its line counter was 2, so both
  marker lines were read.

Not verified: the hourly loop's first real rotation at midnight, the reboot path, and forwarding of
the rotated card logs (no syslog receiver was available).
