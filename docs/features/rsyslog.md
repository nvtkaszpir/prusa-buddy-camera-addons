# Remote rsyslog

Runs rsyslogd on the camera and forwards its logs to a remote syslog server. Three kinds of logs are sent:
`syslog()` messages (e.g. dropbear), the kernel log, and the log files in `/mnt/sdcard/logs/`. Nothing is
written locally. Before this add-on the camera had no syslog daemon, so `syslog()` messages were lost.

## How it works

- `buddy-addons/build-rsyslog.sh` builds rsyslog 8.2610.0 as a flat, dynamic musl bundle in `out/rsyslog/`.
  It holds `rsyslogd`, its own loader `ld-musl-armhf.so.1`, three libraries and only the modules the config
  uses. There is no TLS. The bundle is started through the bundled loader, so the camera's uClibc is never used.
- Files on the microSD card:
  - `/mnt/sdcard/bin/rsyslog/`: the bundle (12 files).
  - `/mnt/sdcard/bin/rsyslog.conf`: from `device/rsyslog.conf`, with `REMOTE_HOST` replaced.
  - `/mnt/sdcard/bin/start-rsyslog.sh`: the start script.
  - `/mnt/sdcard/bin/ntpsync`: needed for the clock check before start.
- Boot hook: the block from `device/rsyslog-hook.sh` goes into `/mnt/sdcard/lp_app.sh`. It must come after the
  read-write remount of the card (or after the [microSD check](sdcard-fsck.md) block), after the
  [http/https](https.md) block if you have it, and right before `/tmp/sync_loop.sh`.
- `start-rsyslog.sh` returns at once. It starts rsyslogd only when wlan0 has a station IPv4 address (not the AP
  address 192.168.42.1), hostapd is not running, and `ntpsync` reports a synchronized clock. Until then a
  background waiter checks every 10 s. `ntpsync` counts the clock as synchronized when the kernel
  flag says so or when the local ntpd answers an NTP query on 127.0.0.1 with a selected source (stratum 1-15).
  That passes a few seconds after ntpd reaches a server. The stock ntpd keeps the kernel flag unsynchronized
  for about 12-14 min after start, so the old kernel-only check delayed rsyslogd that long.
- The stock ntpd starts about 2 s after boot, before Wi-Fi has an address, and then stays unsynchronized for
  many minutes (still at 300 s after boot, measured; why was not traced: DNS lookups failing before the network
  is up and retried at growing intervals is a guess [INFERENCE]). So while there is a station address but the
  clock is unsynchronized, the waiter restarts ntpd, at once and then every 30 s, at most 10 times, with the
  running ntpd's own command line (lp_app 3.1.7 may run it with `-c /tmp/ntp.conf`), and logs
  `restarted ntpd (N nameserver(s) in /etc/resolv.conf): ...`. If no ntpd runs, it starts none. The first
  restart right after Wi-Fi comes up does not always help, although the DNS servers are already configured.
  Measured boots (2026-11-22, 3.1.6): old kernel-only check about 12 min; one restart only at 26 s: synchronized
  at 335 s; retries every 60 s: second restart at 88 s, rsyslogd started at 99 s; retries every 30 s: second
  restart at 57 s, rsyslogd started at 68 s. Details: [NTP findings](../findings/ntp.md).
- At start it copies the bundle and config to `/userdata/rsyslog/`. A new config is installed only if no
  non-comment line still contains `REMOTE_HOST` and `rsyslogd -N1` accepts it. Otherwise it logs `REJECTED`
  and keeps the old config. rsyslogd is restarted only when the bundle or config changed.
- What gets forwarded:

  | source | input | tag | facility.severity |
  |---|---|---|---|
  | `syslog()` callers via `/dev/log` | imuxsock | the program's, e.g. `dropbear[1234]:` | as sent |
  | kernel log (`/proc/kmsg`) | imklog | `kernel:` | `kern.*` |
  | `/mnt/sdcard/logs/YYYY-MM-DD_HH.log` | imfile | `lp_app:` | `local0.info` |
  | other `/mnt/sdcard/logs/*.log` | imfile | file base name, e.g. `httpd:` | `local0.info` |

- lp_app 3.1.6 and later can forward its own log to a syslog server (UDP, RFC 5424) when
  `/mnt/sdcard/syslog_srv` has `IP=<IPv4 address>` and `PORT=<port>` lines (default port 514); 3.1.7 also reads
  `SYSLOG_IP=` / `SYSLOG_PORT=` in `/mnt/sdcard/srv_cfg.txt`. With both forwarders on, the server would get every
  lp_app line twice, so every run of `start-rsyslog.sh` turns the built-in one off:
  - it renames `/mnt/sdcard/syslog_srv` to `/mnt/sdcard/syslog_srv.disabled`;
  - in `/mnt/sdcard/srv_cfg.txt` it prefixes the `SYSLOG_IP=` and `SYSLOG_PORT=` lines with
    `# disabled by start-rsyslog.sh: `;
  - it logs each change to `/mnt/sdcard/logs/rsyslog.log`.

  The hook runs it before lp_app starts, and lp_app reads these files only when it starts, so the built-in
  forwarding never runs. `uninstall.sh` (default mode) restores both files. See
  [Built-in lp_app syslog (3.1.6+) vs this add-on](#built-in-lp_app-syslog-316-vs-this-add-on).
- Protocol: omfwd, UDP port 514 by default, classic BSD syslog format
  (`<PRI>Mmm dd hh:mm:ss HOSTNAME TAG: message`). TCP is optional.
- imfile starts at the end of each file (`freshStartTail="on"`), so old logs and lines written before rsyslogd
  started are not sent. Files not modified for a day are skipped. Copy-truncated files (see
  [logrotate](logrotate.md)) are handled by `reopenOnTruncate="on"`.
- Queues are RAM only and small: main 256 messages, forwarding 500 messages. When they are full, new messages
  are dropped. Callers of `syslog()` are never blocked.
- Persistence: `/userdata/rsyslog/` (bundle, config, `work/` with imfile offsets) survives reboots and may be
  wiped by a firmware update. The start script copies it from the card again. `/tmp/rsyslogd.pid`,
  `/tmp/rsyslogd.log` and the waiter files do not survive a reboot.

## What to change

!!! warning "Mandatory: set the syslog server"
    `buddy-addons/device/rsyslog.conf` ships with `target="REMOTE_HOST"`. `start-rsyslog.sh` refuses to start
    rsyslogd while a non-comment line still names `REMOTE_HOST`. Set your server's IP address or DNS name:

    - With Taskfile: the variable `REMOTE_HOST` in `Taskfile.yml` (default `192.168.1.10`). Change it there,
      or pass it per run: `task buddy:stage REMOTE_HOST=192.168.1.10`. `buddy:stage` writes it into the
      staged copy only; the repo template is not changed.
    - By hand: edit `target=` in the copy on the card, `/mnt/sdcard/bin/rsyslog.conf`.

!!! warning "No encryption"
    This build has no TLS. Logs are sent in plain text. Use it only on a network you trust.

Optional changes, all in `rsyslog.conf` (repo: `buddy-addons/device/rsyslog.conf`):

- Protocol and port: in the `action(type="omfwd" ...)` block between `---- remote target: EDIT HERE ----` and
  `---- end remote target ----`. Default `protocol="udp" port="514"`.
  - For TCP, replace those lines with `protocol="tcp" port="514" TCP_Framing="traditional"`.
  - Or use `port="601" TCP_Framing="octet-counted"` if your server expects RFC 6587 octet counting.
  - With TCP, rsyslog retries every 10 s forever and keeps up to 500 messages in RAM while the server is down.
- Hostname: `localHostname` in `global()` (commented out). The default is the camera's hostname, `Rockchip` on
  stock firmware. Set one per camera if you have several.
- Monitored files: `file="/mnt/sdcard/logs/*.log"` in the imfile `input(...)`, together with `ignoreOlderThan`
  (default `86400` s). If you change the directory, also change `LOGDIR=/mnt/sdcard/logs` in
  `buddy-addons/device/start-rsyslog.sh`, which cleans up old imfile state files for that directory.
- Receiving server: it must accept syslog on the chosen protocol and port. The sources give as an example
  rsyslog with `module(load="imudp") input(type="imudp" port="514")`, or syslog-ng. Port 514 is privileged,
  so the listener needs root.

## Build and deploy

```sh
cd buddy-addons && ./build-rsyslog.sh && cd ..   # -> buddy-addons/out/rsyslog/
task buddy:stage REMOTE_HOST=192.168.1.10          # stage with the target set
task buddy:sync                                  # rsync to /mnt/sdcard/bin/ on CAMERA_HOST (needs ssh + rsync)
```

`buddy:stage` also needs the other `out/` binaries (`ntpsync`, `fsck.fat`, `logrotate`). `buddy:sync` needs
[ssh](ssh.md) and [rsync](rsync.md) on the camera. It does not copy `*-hook.sh` files, so paste the block from
`buddy-addons/device/rsyslog-hook.sh` into `/mnt/sdcard/lp_app.sh` once, by hand. Without the Taskfile, copy the
files to the card as listed in `buddy-addons/rsyslog.md` and edit `rsyslog.conf` there.

Then apply on the camera (or reboot):

```sh
sh /mnt/sdcard/bin/start-rsyslog.sh            # install/refresh, start if not running
sh /mnt/sdcard/bin/start-rsyslog.sh restart    # always restart
sh /mnt/sdcard/bin/start-rsyslog.sh stop
```

## Verify

On a host, as root, listen for UDP:

```sh
nc -klu 514        # traditional netcat: nc -lu -p 514; for TCP: nc -kl 514
```

On the camera:

```sh
cat /mnt/sdcard/logs/rsyslog.log                 # start steps, REJECTED lines, -N1 output
cat /tmp/rsyslogd.log                            # rsyslogd startup errors
cat /tmp/rsyslogd.pid
echo "test line" >> /mnt/sdcard/logs/test.log    # arrives with tag "test:"
D=/userdata/rsyslog/bundle
$D/ld-musl-armhf.so.1 --library-path $D $D/rsyslogd -M $D -N1 -f /userdata/rsyslog/rsyslog.conf
```

The camera has no `logger` applet. An ssh login should also show up as a dropbear message.

## Source files

- `buddy-addons/rsyslog.md`
- `buddy-addons/build-rsyslog.sh`
- `buddy-addons/device/rsyslog.conf`
- `buddy-addons/device/rsyslog-hook.sh`
- `buddy-addons/device/start-rsyslog.sh`
- `Taskfile.yml` (`buddy:stage`, `buddy:sync`, var `REMOTE_HOST`)
