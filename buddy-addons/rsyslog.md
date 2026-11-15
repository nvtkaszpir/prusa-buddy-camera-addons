# rsyslog (forward logs to a syslog server)

Back to [README.md](README.md). Relies on the shared sections [Compile](README.md#compile) and
[Install via microSD](README.md#install-via-microsd).

rsyslog forwards three kinds of logs from the camera to a remote syslog server: messages from programs that use
`syslog()` (dropbear, for example), the kernel log, and the log files in `/mnt/sdcard/logs/` (lp_app's logs and the
start-script logs). Nothing is written locally. Before this add-on the camera had no syslog daemon: nothing created
`/dev/log`, so `syslog()` messages were lost.

## Artifacts

`build-rsyslog.sh` builds rsyslog 8.2610.0 with libestr 0.1.11, libfastjson 1.2609.0 and zlib 1.3.2. TLS, crypto,
uuid, systemd, curl, yaml and man pages are off. It writes a bundle directory, `out/rsyslog/`. The bundle is flat
(no subdirectories) and has no symlinks, so it can be copied to the vfat card as is.

| file in `out/rsyslog/` | contents |
|---|---|
| `rsyslogd` | the daemon, with omfwd (UDP/TCP forwarding) built in |
| `ld-musl-armhf.so.1` | musl 1.2.2 (from the dockcross toolchain): the dynamic loader, which is also libc |
| `libz.so.1`, `libestr.so.0`, `libfastjson.so.4` | libraries rsyslogd and imfile link against |
| `imuxsock.so`, `imklog.so`, `imfile.so` | inputs: `/dev/log`, `/proc/kmsg`, tailing files |
| `lmnet.so` | network helpers, used by omfwd and imuxsock |
| `lmnetstrms.so`, `lmnsd_ptcp.so`, `lmtcpclt.so` | plain TCP sending for omfwd; only loaded with `protocol="tcp"` |

| file | size | sha256 |
|---|---|---|
| `rsyslogd` | 792624 B | `fe879e20e5cef4946a07f440f92513faebdaf9a03181e806522965e74af90b71` |
| `ld-musl-armhf.so.1` | 612112 B | `299f19344dca02290735662a979c3923baaeedd574694ef9504152af22155c7d` |
| `libz.so.1` | 71236 B | `ccc66af8c415fb35e46839972f873fe441dd192f8a24102f9a0606d3e543c846` |
| `libestr.so.0` | 9468 B | `1bb1fc523bb09563b0dcf536343e1eb3d9cb5d036f1afa5a7317c084936cfb61` |
| `libfastjson.so.4` | 30388 B | `8cd060468420830b6b9c79bb4002df3db5e339e363285ebcfc51240aa4b16129` |
| `imuxsock.so` | 31372 B | `3604712926062457e34091283a8f4b027ff0f584f2c2e5255502a3053c3c706c` |
| `imklog.so` | 18516 B | `87130a7a940eadb78d4f7d7246e0399ec37f8200b35090ad7dcfc0d874d1942a` |
| `imfile.so` | 52100 B | `a58ecc73e89871a13dae3f83dfa66e0f2e441e09b544058646223e7822c4eee8` |
| `lmnet.so` | 22348 B | `58dde8e5b9eb745bb91dfd73cdb497776f2db08552f4ac87b3f27b81b2ace33b` |
| `lmnetstrms.so` | 14336 B | `0f3a9857db513206ff0072b3d30bd729b62b1674fde1bded7d2c06a0c5ead430` |
| `lmnsd_ptcp.so` | 18536 B | `78071b1dc81495c2e55a7b5152a5d051d1145b66b4eee87016820c3e954feb11` |
| `lmtcpclt.so` | 9508 B | `38cf4b5f7da8d4b5e8183a34843147a60f2c6fb73531d188895ce34c2c9f7402` |
| total | 1682544 B | |

```sh
./build-rsyslog.sh                                # -> out/rsyslog/
B=out/rsyslog
qemu-arm-static $B/ld-musl-armhf.so.1 --library-path $B $B/rsyslogd -v     # rsyslogd 8.2610.0 ...
```

All files are ELF 32-bit ARM, EABI5, hard-float ABI (`readelf -h`: `Flags: 0x5000400, Version5 EABI, hard-float
ABI`). `rsyslogd` is a dynamically linked PIE, and the rest are shared objects.

### Why a bundle and not one static binary

rsyslogd loads every input module, and the network helpers that omfwd needs, with `dlopen()` at runtime. In a static
musl binary `dlopen()` is a stub that always fails ("Dynamic loading not supported", a string in the toolchain's
`libc.a`). A static rsyslogd therefore cannot load imuxsock, imklog or imfile. The bundle is a normal dynamic musl
build that brings its own loader. It is started by running the loader directly:

```sh
DIR/ld-musl-armhf.so.1 --library-path DIR DIR/rsyslogd -M DIR -f CONF ...
```

`--library-path` makes the loader take `libc`, the three libraries and (via `-M`) the modules from `DIR` only. The
camera's uClibc and `/lib` are never used, and nothing has to be installed in the read-only rootfs. `rsyslogd`'s
built-in interpreter path (`/lib/ld-musl-armhf.so.1`) does not exist on the camera, so running `rsyslogd` directly
fails; always go through the loader, as `start-rsyslog.sh` does. Only the modules this config uses are shipped.

## Install on the card

```
/mnt/sdcard/bin/rsyslog/           <- out/rsyslog/ (the whole directory, 12 files)
/mnt/sdcard/bin/rsyslog.conf       <- device/rsyslog.conf, with REMOTE_HOST replaced
/mnt/sdcard/bin/start-rsyslog.sh   <- device/start-rsyslog.sh
```

```sh
mkdir -p "$SD/bin/rsyslog"
cp out/rsyslog/* "$SD/bin/rsyslog/"
cp device/rsyslog.conf device/start-rsyslog.sh "$SD/bin/"
$EDITOR "$SD/bin/rsyslog.conf"      # set the target, see "Edit the remote target"
sync
```

Then paste the block from `device/rsyslog-hook.sh` into `/mnt/sdcard/lp_app.sh`. Put it **after** the remount line

```
mount -t vfat -o rw,uid=0,gid=0,dmask=000,fmask=000,errors=remount-ro /dev/mmcblk1p1 /mnt/sdcard
```

and after the httpd block (if you have it), right **before** `/tmp/sync_loop.sh`, which never returns. rsyslogd reads
its config from the card and keeps the log files it tails in `/mnt/sdcard/logs/` open. If it started before
`umount /mnt/sdcard` (where the ssh block goes), that umount would fail. It starts before `sync_loop.sh` starts lp_app.

With ssh already working, you can skip the card reader:

```sh
ssh root@CAMERA_IP mkdir -p /mnt/sdcard/bin/rsyslog
scp -O out/rsyslog/* root@CAMERA_IP:/mnt/sdcard/bin/rsyslog/
scp -O rsyslog.conf device/start-rsyslog.sh root@CAMERA_IP:/mnt/sdcard/bin/
ssh root@CAMERA_IP sh /mnt/sdcard/bin/start-rsyslog.sh
```

## What happens at boot

The hook runs `start-rsyslog.sh`, which returns at once. It starts rsyslogd only when the camera is ready:

- wlan0 has an IPv4 station address from the Wi-Fi DHCP client, and that address is not the access point
  address 192.168.42.1;
- no hostapd is running;
- NTP has synchronized the system clock: `/mnt/sdcard/bin/ntpsync` exits 0. It reads the kernel's clock state
  (see [ntpsync.md](ntpsync.md)) and does not query ntpd's peers.

Otherwise the script starts a waiter in the background and returns. The waiter is the same script run with `wait`.
Its pid is in `/tmp/rsyslog-wait.pid`, so a second call does not start another one. It polls every 10 s and logs
only state changes, for example `waiting: no station address on wlan0`, `waiting: NTP not synchronized`, and then
`ready, starting rsyslogd`. `stop` also stops the waiter. The card needs `bin/rsyslog/`, `bin/rsyslog.conf`,
`bin/start-rsyslog.sh` and `bin/ntpsync`.

Once ready, the start path runs:
1. copies each file of `/mnt/sdcard/bin/rsyslog/` to `/userdata/rsyslog/bundle/` when its md5 differs, and removes
   files from there that are no longer on the card;
2. if `/mnt/sdcard/bin/rsyslog.conf` differs from `/userdata/rsyslog/rsyslog.conf`, installs it only if no
   non-comment line still contains `REMOTE_HOST` and `rsyslogd -N1` (config check, loads the modules) accepts it.
   Otherwise it logs a `REJECTED` line with the reason, keeps the installed config and exits with status 1 at the end;
3. refuses to start (exit 1, reason logged) if there is no installed config, or if it still names `REMOTE_HOST`;
4. checks the installed config with `rsyslogd -N1` before touching a running rsyslogd;
5. restarts a running rsyslogd only if a bundle file or the config changed, or with the `restart` argument (after
   a wait, a running rsyslogd is always restarted); otherwise it logs `already running` and does nothing;
6. before starting, removes imfile state files that belong to no current file in `/mnt/sdcard/logs/` (see
   [Log files on the card](#log-files-on-the-card));
7. passes the camera's time zone (`/etc/TZ`, which musl does not read on its own) in `TZ`, and starts rsyslogd with
   cwd `/`. rsyslogd daemonizes itself and writes `/tmp/rsyslogd.pid`.

Known limits:
- Lines written before forwarding starts are not sent. imfile starts at the end of each file, so lines written
  while the camera waits for Wi-Fi or NTP stay in the local files only.
- A later switch to AP mode is not handled by the gate. rsyslogd keeps running, and forwarding then fails until
  the next reboot.

Files:
- `/mnt/sdcard/logs/rsyslog.log` (or `/tmp/rsyslog.log` without the logs dir): the steps of `start-rsyslog.sh`,
  including rejected configs and the `rsyslogd -N1` output. This file is tailed and forwarded too.
- `/tmp/rsyslogd.log`: rsyslogd's own startup errors (before it daemonizes). Lost on reboot.
- `/tmp/rsyslog-wait.pid`: pid of the waiter while it runs. Lost on reboot.
- `/tmp/rsyslog-wait.sh`: copy of this script that the waiter runs, so the card's copy is not held open while it
  waits. `/tmp/rsyslog-wait.out`: the waiter's stdout and stderr. Both lost on reboot.
- `/userdata/rsyslog/work/`: rsyslog's `workDirectory`, holding imfile read offsets.

Run it by hand:

```sh
sh /mnt/sdcard/bin/start-rsyslog.sh            # install/refresh, start if not running
sh /mnt/sdcard/bin/start-rsyslog.sh restart    # always restart a running rsyslogd
sh /mnt/sdcard/bin/start-rsyslog.sh stop       # stop rsyslogd
```

Config check by hand:

```sh
D=/userdata/rsyslog/bundle
$D/ld-musl-armhf.so.1 --library-path $D $D/rsyslogd -M $D -N1 -f /userdata/rsyslog/rsyslog.conf
```

## Edit the remote target

In `rsyslog.conf`, between `---- remote target: EDIT HERE ----` and `---- end remote target ----`, replace
`REMOTE_HOST` with the IP address or DNS name of your syslog server. A DNS name is resolved through the camera's
`/etc/resolv.conf`, which the Wi-Fi DHCP client writes.

- UDP 514 (the default, `protocol="udp" port="514"`): fire-and-forget. A server that is down or unreachable never
  slows anything on the camera; messages sent meanwhile are lost.
- TCP: replace the protocol and port lines with `protocol="tcp" port="514" TCP_Framing="traditional"` (or `port="601"
  TCP_Framing="octet-counted"` if your server expects RFC 6587 octet counting). If the server is down, rsyslog
  retries every 10 s, forever (`action.resumeRetryCount="-1"`, `action.resumeInterval="10"`), and holds up to 500
  messages in RAM meanwhile. When that queue is full, new messages are dropped at once (`queue.timeoutEnqueue="0"`).
  Callers of `syslog()` are never blocked.

There is no TLS in this build. Use it only on a network you trust.

Messages are sent in the classic BSD syslog format: `<PRI>Mmm dd hh:mm:ss HOSTNAME TAG: message`. HOSTNAME is the
camera's hostname (`Rockchip` on the stock firmware). Set `localHostname` in `global()` to tell several cameras apart.

After an edit, upload the file to `/mnt/sdcard/bin/rsyslog.conf` and rerun `start-rsyslog.sh` (or reboot).

## What gets forwarded

| source | how | tag | facility.severity |
|---|---|---|---|
| `syslog()` callers, e.g. dropbear | imuxsock, `/dev/log` | the program's, e.g. `dropbear[1234]:` | as sent |
| kernel log | imklog reads `/proc/kmsg` | `kernel:` | `kern.*` |
| `/mnt/sdcard/logs/YYYY-MM-DD_HH.log` (lp_app) | imfile, one message per line | `lp_app:` | `local0.info` |
| other `/mnt/sdcard/logs/*.log` | imfile | file base name: `dropbear:`, `httpd:`, `rsyslog:`, ... | `local0.info` |

dropbear starts (ssh block) before rsyslogd creates `/dev/log`. uClibc's `syslog()` is expected to reconnect on later
calls, so its later messages should arrive [INFERENCE: not observed on the camera]. imklog reading `/proc/kmsg` takes
messages out of that stream, but `dmesg` (the kernel ring buffer) is unaffected. There was no klogd before.

### Log files on the card

- On the first start, and for any file without saved state (`freshStartTail="on"`), imfile starts reading at the
  current end of each file. The old logs on the card (about 22 MB per day of lp_app logs) are never sent. A file
  created while rsyslogd runs (lp_app's next log) is read from its start.
- Files not modified for a day are skipped (`ignoreOlderThan="86400"`). This only works once the clock is set; with
  the clock at 1970 (before NTP), all files are watched, but still only from their ends.
- Read offsets are stored in `/userdata/rsyslog/work/` on a clean rsyslogd shutdown (stop, restart, `reboot`), not
  after every line. That avoids constant flash writes. After a power cut, there is no saved offset.
- vfat has no stable inode numbers: the kernel gives files new ones on every mount. imfile keys its state on the
  inode (plus a hash of the file's first 512 bytes), so after a reboot it usually finds no state and starts at the end
  again. Lines written while rsyslogd was not running (during boot, or after a power cut) are then not forwarded.
  Nothing is ever sent twice, because a state file is only used for a file with the same inode and first 512 bytes.
  `start-rsyslog.sh` deletes state files whose inode no current log file has, so `/userdata` does not fill up.

## Memory and footprint

- Flash: 1.68 MB in `/userdata/rsyslog/bundle/` plus the same on the card, and a few small state files.
- RAM: not measured on the camera yet. Bounds set in the config: main queue 256 messages, forwarding queue 500
  messages, both in RAM only (`LinkedList` without a file, `queue.saveOnShutdown="off"`, nothing ever spills to disk),
  and `maxMessageSize="4k"`. The worst case is about 750 messages; typical lp_app lines are about 150 bytes plus
  rsyslog's per-message overhead.
- rsyslog sets each thread's stack size to 4 MB (runtime/rsyslog.c), with about 6 threads (inputs, queue workers).
  This is virtual address space; only touched pages use RAM [INFERENCE].
- `rsyslogd -N1`, run by the start script, briefly loads a second copy of rsyslogd and its modules.
- The waiter is a shell loop that polls every 10 s. It exits once rsyslogd has started, so it uses no memory after
  start.
- Fallback if RAM is too tight: the stock busybox `syslogd -R HOST[:PORT]` (forwards `/dev/log` over UDP) and `klogd`
  need no build. They do not tail the card's log files and have no queueing or per-file tags. Not tested on the camera.

## Test from a host

On a Linux host on the same network, as root (port 514 is privileged):

```sh
nc -klu 514                       # OpenBSD netcat, UDP; traditional netcat: nc -lu -p 514
```

Set `target="HOST_IP"` in `rsyslog.conf`, upload it and rerun the start script. On the camera:

```sh
echo "test line" >> /mnt/sdcard/logs/test.log    # new file, forwarded with tag "test:"
```

The camera has no `logger` applet. An ssh login should also show up, as a dropbear message (dropbear runs without
`-E`, so it logs through `syslog()`). For TCP, listen with `nc -kl 514` and switch the config to TCP. A real server
works the same way, e.g. rsyslog on the host with `module(load="imudp") input(type="imudp" port="514")`, or syslog-ng.

## Persistence

| location | survives reboot | survives firmware update | notes |
|---|---|---|---|
| `/userdata/rsyslog/bundle/`, `rsyslog.conf` | yes | may be wiped | copied from the card again by `start-rsyslog.sh` |
| `/userdata/rsyslog/work/` | yes | may be wiped | imfile offsets; if lost, files are read from their end |
| `/tmp/rsyslogd.pid`, `/tmp/rsyslogd.log` | no | no | |

## Verified

On the host (qemu-user, `qemu-arm-static` through binfmt):
- `build-rsyslog.sh` ran to completion in `dockcross/linux-armv7l-musl`. A rebuild gave identical sha256 for every
  file (the earlier run also shipped `lmzlibw.so`, which was then dropped as never loaded).
- `readelf -h`: every file is `Version5 EABI, hard-float ABI`. The only `NEEDED` entries are `libz.so.1`,
  `libestr.so.0`, `libfastjson.so.4` and `libc.so` (the loader itself). No `libgcc_s`.
- Config check with modules loaded. The command used a copy of `device/rsyslog.conf` with `target="192.168.1.10"`.
  `workDirectory` pointed to an existing temporary directory, because `/userdata/rsyslog/work` does not exist on the
  host (the start script creates it on the camera; with a missing directory, `-N1` reports it and exits 1):

  ```
  $ qemu-arm-static $B/ld-musl-armhf.so.1 --library-path $B $B/rsyslogd -M $B -N1 -f /tmp/rsl/test.conf
  rsyslogd: version 8.2610.0, config validation run (level 1), master config /tmp/rsl/test.conf
  rsyslogd: End of config validation run. Bye.
  exit 0
  ```

  `qemu-arm-static -strace` showed `lmnet.so`, `imuxsock.so`, `imklog.so` and `imfile.so` opened from the bundle,
  and no failed opens.
- Foreground run with paths moved to a temporary directory (socket instead of `/dev/log`, log directory, target
  `127.0.0.1:5514`). A local listener received over UDP and over TCP:
  `<38>... dropbear[42]: hello via devlog` (from the socket), `<134>... lp_app: ...` (a line appended to
  `2026-11-01_00.log`) and `<134>... dropbear: ...` (a line appended to `dropbear.log`). Lines that were in those
  files before the start were not sent. TCP also loaded `lmnetstrms.so`, `lmnsd_ptcp.so` and `lmtcpclt.so`; UDP did
  not.
- `start-rsyslog.sh` under busybox `sh`, with its paths moved to a temporary directory: it refused the template
  config (`REJECTED ...: replace REMOTE_HOST ...`, then `no .../rsyslog.conf ..., not starting`, exit 1); started
  with a real target; logged `already running` on a second run; restarted after a config change and after a bundle
  file was removed from the card; rejected a broken config with the `-N1` output and kept the old process running
  (exit 1); removed a state file for a missing inode and kept the others; forwarded from the daemonized rsyslogd;
  `stop` stopped it.
- imklog could not open `/proc/kmsg` as a non-root user on the host (`Permission denied`), and the other inputs kept
  running. Not tested on the camera.
