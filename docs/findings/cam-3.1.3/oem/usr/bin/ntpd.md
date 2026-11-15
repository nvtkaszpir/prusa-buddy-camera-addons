# `ntpd`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/ntpd` |
| file type | `ELF 32-bit LSB pie executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `600752` |
| sha256 | `8c5bfeb416dd566fc16e199f55dca06f8c6f519dd22a78def19b0eb58dbabc27` |
| linked libraries | `libc.so.0, ld-uClibc.so.1` |
| origin | Reference NTP implementation (ntp.org) ntpd 4.2.8p15, cross-built (Buildroot-style) for uClibc |
| confidence | high |

## Summary

The reference ntp.org NTP daemon, version **4.2.8p15** (build string `ntpd 4.2.8p15@1.3728 Tue May 28 06:11:19 UTC 2024 (1)`). It keeps the camera's system clock in sync with `pool.ntp.org`. It is not BusyBox's `ntpd` applet and not chrony.

## Usage

The binary has the standard ntp.org AutoOpts option parser. The usage header found in the binary:

```
ntpd - NTP daemon program - Ver. 4.2.8p15
Usage:  %s [ -<flag> [<val>] | --<name>[{=| }<val>] ]... \
```

The full option table is the standard ntpd 4.2.8 one (`-c` config file, `-g` panic gate, `-p` pidfile, `-q`, `-n`, `-d`, `-f` driftfile, ...). I identified it from the AutoOpts strings and did not dump it in full. Only the options used on this device matter:

- `-g`: lets the first adjustment be arbitrarily large. This is needed because the device boots with an unset or wrong RTC time.
- `-p /var/run/ntpd.pid`: pid file.
- `-c /oem/usr/etc/ntp.conf`: configuration file. The compiled-in default is `/etc/ntp.conf`.

## How it works

It is the standard ntpd. It reads its config, resolves the `server`/`pool` names, uses NTP over UDP 123 to discipline the kernel clock (adjtimex), and writes the pid file. Configured servers (`/oem/usr/etc/ntp.conf`):

```
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst
server 2.pool.ntp.org iburst
server 3.pool.ntp.org iburst
restrict default nomodify nopeer noquery limited kod
restrict 127.0.0.1
restrict [::1]
```

There is no `driftfile` line, so ntpd logs `config: driftfile disabled` and does not persist frequency drift. Because of the `restrict default ... noquery` line, remote ntpq/ntpdc queries are refused. ntpd still listens on UDP 123 on all interfaces, as reference ntpd always does.

## Interfaces touched

- Device nodes / sysfs / procfs: the kernel clock through `adjtimex`/`settimeofday` [INFERENCE: standard ntpd behaviour]. The refclock drivers compiled in, e.g. `/var/spool/lock/LCK..cua%d` and `/etc/ntp.audio`, are not used by this config.
- Files and paths read/written: reads `/oem/usr/etc/ntp.conf`; writes `/var/run/ntpd.pid`.
- Network: UDP 123, outbound to `{0,1,2,3}.pool.ntp.org`, plus DNS lookups. It binds UDP 123 locally.
- Environment variables / config files: `/oem/usr/etc/ntp.conf` (default `/etc/ntp.conf`).

## Relevance on this camera

It runs at boot. `/etc/init.d/S21appinit` starts `RkLunch.sh`, whose `rcS()` runs `/oem/usr/etc/init.d/S10ntp start`. That runs `ntpd -g -p /var/run/ntpd.pid -c /oem/usr/etc/ntp.conf`, and only if `/var/run/ntpd.pid` does not exist. No `ntpd` exists in `/bin` or `/usr/sbin`, so the `ntpd` on PATH is this one. ntpd starts before Wi-Fi is up (`network_init wlan0` runs later, in `post_chk`), so the first resolves can fail. ntpd 4.2.8 retries DNS later. Running it a second time while it is already running fails to bind UDP 123. The only side effect is that it changes the system time.

## Evidence

```
$ strings -n4 ntpd | grep -E 'Ver\.|4\.2\.8'
ntpd - NTP daemon program - Ver. 4.2.8p15
ntpd 4.2.8p15@1.3728 Tue May 28 06:11:19 UTC 2024 (1)
$ strings ntpd | grep -E 'ntp.conf|driftfile disabled'
/etc/ntp.conf
config: driftfile disabled
$ readelf -d ntpd | grep NEEDED  -> libc.so.0, ld-uClibc.so.1
$ cat oem/usr/etc/init.d/S10ntp
DAEMON=ntpd
DAEMON_OPTS="-g -p /var/run/ntpd.pid -c"
DAEMON_CONFIG=/oem/usr/etc/ntp.conf
... start) $DAEMON $DAEMON_OPTS $DAEMON_CONFIG
```

`S10ntp` also implements `stop` (kills the pid from the pid file and removes the file), `restart` and `status`.

## Open questions

- I did not check which build-time options were enabled (e.g. which refclocks, whether crypto/autokey is included).
- `S10ntp` decides whether ntpd is running only by checking for the pid file. A stale `/var/run/ntpd.pid` would stop ntpd from starting, but `/var/run` is normally tmpfs, which is cleared on reboot [INFERENCE].
- I could not determine statically whether `lp_app` relies on time being synced (e.g. for TLS).
