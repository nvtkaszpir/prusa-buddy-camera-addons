# `udhcpd`

| field | value |
|---|---|
| path on device | `/oem/usr/sbin/udhcpd` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `789204` |
| sha256 | `784ae858fc6a047b2684a746c98c774e63a93a8579c98edbe3c4346089f2805f` |
| linked libraries | `libc.so.0, ld-uClibc.so.1` |
| origin | BusyBox applet: a complete BusyBox v1.36.1 multi-call binary (built 2024-11-04 07:39:54 UTC, crosstool-NG 1.24.0 GCC 8.3.0, i.e. the Rockchip uClibc toolchain), installed under the applet name `udhcpd` |
| confidence | high |

## Summary

This file is a full BusyBox 1.36.1 multi-call binary with 280 applets, named `udhcpd` so that it runs the BusyBox DHCP server applet. The system BusyBox in `/bin/busybox` is v1.27.2 and has no `udhcpd` applet, so the vendor added this newer binary to `/oem`. When the camera runs its own Wi-Fi access point (`192.168.42.1/24` on `wlan0`), it uses this server to hand out addresses to phones and computers. The binary is md5-identical on the running camera.

## Usage

The embedded `udhcpd` usage text, verbatim (BusyBox prints it after `Usage: udhcpd `):

```
[-fS] [-I ADDR] [-a MSEC] [CONFFILE]
DHCP server
	-f	Run in foreground
	-S	Log to syslog too
	-I ADDR	Local address
	-a MSEC	Timeout for ARP ping (default 2000)
Signals:
	USR1	Update lease file
```

The options:

- `-f`: do not daemonise.
- `-S`: also log to syslog.
- `-I ADDR`: override the server's own IP address (by default it is taken from the interface).
- `-a MSEC`: how long to wait for the ARP probe that checks a candidate address is not in use.
- `CONFFILE`: the configuration file. The default is `/etc/udhcpd.conf`; the camera passes `/oem/usr/etc/udhcpd.conf`.
- `SIGUSR1`: write the in-memory leases to `lease_file`.

The generic BusyBox front end is also present (`Usage: busybox [function [arguments]...]`, `or: busybox --list[-full]`, `or: busybox --install [-s] [DIR]`). It is only reachable when `argv[0]` starts with `busybox`.

## How it works

**Multi-call dispatch.** BusyBox takes the basename of `argv[0]`, here `udhcpd`, and looks it up in the packed `applet_names` table at file offset `0x9be08`. It then runs that applet's main function. Unknown names print `: applet not found`. Under its installed name the file only ever acts as `udhcpd`. The other 279 applets need a symlink or a copy with another name.

**Applets compiled in** (280, extracted from `applet_names`):

```
[ [[ addgroup adduser ar arch arp arping ascii ash awk base32 base64 basename bc blkid bunzip2 bzcat cat
chattr chgrp chmod chown chroot chrt chvt cksum clear cmp cp cpio crc32 crond crontab cut date dc dd deallocvt
delgroup deluser devmem df diff dirname dmesg dnsd dnsdomainname dos2unix du dumpkmap echo egrep eject env
ether-wake expr factor fallocate false fbset fdflush fdformat fdisk fgrep find flock fold free freeramdisk
fsck fsfreeze fstrim fuser getopt getty grep gunzip gzip halt hdparm head hexdump hexedit hostid hostname
hwclock i2cdetect i2cdump i2cget i2cset i2ctransfer id ifconfig ifdown ifup inetd init insmod install ip
ipaddr ipcrm ipcs iplink ipneigh iproute iprule iptunnel kill killall killall5 klogd last less link linux32
linux64 linuxrc ln loadfont loadkmap logger login logname losetup ls lsattr lsmod lsof lspci lsscsi lsusb
lzcat lzma lzopcat makedevs md5sum mdev mesg microcom mim mkdir mkdosfs mke2fs mkfifo mknod mkpasswd mkswap
mktemp modprobe more mount mountpoint mt mv nameif netstat nice nl nohup nologin nproc nslookup nuke od openvt
partprobe passwd paste patch pidof ping pipe_progress pivot_root poweroff printenv printf ps pwd rdate
readlink readprofile realpath reboot renice reset resize resume rm rmdir rmmod route run-init run-parts
runlevel sed seedrng seq setarch setconsole setfattr setkeycodes setlogcons setpriv setserial setsid sh
sha1sum sha256sum sha3sum sha512sum shred sleep sort start-stop-daemon strings stty su sulogin svc svok
swapoff swapon switch_root sync sysctl syslogd tail tar tc tee telnet test tftp time top touch tr traceroute
tree true truncate ts tsort tty ubirename udhcpc udhcpd uevent umount uname uniq unix2dos unlink unlzma unlzop
unxz unzip uptime usleep uudecode uuencode vconfig vi vlock w watch watchdog wc wget which who whoami xargs
xxd xz xzcat yes zcat
```

The list has no `telnetd`, `httpd`, `nc`, `ntpd`, `dumpleases` or `udhcpc6`. The busybox `telnetd` on TCP 23 of the live camera therefore comes from the system `/bin/busybox` 1.27.2, which has `telnetd`, `udhcpc` and `nc` but no `udhcpd`. The build looks like a near-default `make defconfig`-style configuration [INFERENCE from the breadth of applets and the default `udhcpc` script path `/usr/share/udhcpc/default.script`].

**udhcpd applet flow** (BusyBox `networking/udhcp/dhcpd.c`, `files.c`):

1. **Read the config.** The config file (`/etc/udhcpd.conf` by default) is read with BusyBox `config_read`. Recognised keywords, from the strings table:
   - `start`, `end`, `interface`
   - `max_leases` (default `235`), `auto_time` (`7200`), `decline_time` (`3600`), `conflict_time`, `offer_time`, `min_lease`
   - `lease_file` (`/var/lib/misc/udhcpd.leases`), `pidfile` (default `/var/run` + `/udhcpd.pid`)
   - `siaddr`, `notify_file`, `sname`, `boot_file`, `static_lease`
   - `option`/`opt` with names such as `subnet`, `router`, `dns`, `hostname`, `domain`, `broadcast`, `ntpsrv`, `wins`, `lease`

   The built-in default range is `192.168.0.20`–`192.168.0.254`. Errors are reported as `can't parse line %u in %s` and `bad start/end IP range in %s`.

2. **Start up.** It reads existing leases (`too many leases while loading %s`), writes the pidfile, and logs `started, v1.36.1`.
3. **Open the socket.** It opens a UDP socket on port 67 bound to the configured interface (`bindtodevice` string; upstream `udhcp_listen_socket` + `SO_BINDTODEVICE`).
4. **Serve requests.** It loops on DISCOVER/REQUEST/DECLINE/RELEASE/INFORM: `sending OFFER to %s`, `sending ACK to %s`, `no free IP addresses. OFFER abandoned`, `%s belongs to someone, reserving it for %u seconds`. Before offering an address it sends an ARP probe (`-a`, default 2000 ms). It ignores bad packets (`packet with bad magic, ignoring`, `not a REQUEST%s`).
5. **Save leases.** On `auto_time` expiry or SIGUSR1 it writes the lease file.

## Interfaces touched

- Device nodes / sysfs / procfs:
  - an `AF_INET` UDP socket on port 67, bound to `wlan0`
  - an `AF_PACKET` socket for ARP probes
  - interface ioctls (`SIOCGIFADDR`/`SIOCGIFHWADDR`/`SIOCGIFINDEX`) on `wlan0` [INFERENCE: upstream `udhcp_read_interface`]
- Files and paths read/written:
  - `/oem/usr/etc/udhcpd.conf` (read; passed by `wifi_setup.sh`)
  - `/etc/udhcpd.conf` (compiled-in default, not present in the dump)
  - `/var/lib/misc/udhcpd.leases` (read/write; `wifi_setup.sh` runs `mkdir -p /var/lib/misc` first)
  - `/var/run/udhcpd.pid` (written)
- Network: DHCP server, UDP/67 → clients UDP/68, on `wlan0`. It offers `192.168.42.20`–`192.168.42.254`, netmask `255.255.255.0`, router `192.168.42.1`, domain `local`, and a lease time of 864000 s (10 days). No DNS server option is configured.
- Environment variables / config files: `/oem/usr/etc/udhcpd.conf`, full contents:

  ```
  start           192.168.42.20
  end             192.168.42.254
  interface       wlan0
  remaining       yes
  lease_file      /var/lib/misc/udhcpd.leases
  pidfile /var/run/udhcpd.pid
  option  subnet  255.255.255.0
  opt     router  192.168.42.1
  option  domain  local
  option  lease   864000
  ```

  `remaining` is not one of the keywords in this binary; upstream 1.36.1 ignores unknown keywords silently [INFERENCE].

## Relevance on this camera

`udhcpd` is not started at boot. It is not referenced by `etc/init.d/*`, `/oem/usr/etc/init.d/S10ntp` or [`RkLunch.sh`](../bin/RkLunch.sh.md). Its only caller is [`wifi_setup.sh`](wifi_setup.sh.md), whose `start_hostapd_ap()` runs these steps:

```
ifconfig wlan0 up
ifconfig wlan0 192.168.42.1
route add default netmask 255.255.255.0 gw 192.168.42.1
hostapd -B /tmp/config/hostapd.conf
mkdir -p /var/lib/misc
udhcpd /oem/usr/etc/udhcpd.conf
```

This happens when [`lp_app`](lp_app.md) switches to AP mode with `wifi_setup.sh ap nl80211 "<ssid>" "<pwd>" wpa <channel>` (see [`hostapd`](hostapd.md)). Without `-f`, `udhcpd` daemonises.

`wifi_setup.sh stop` removes it with `killall -9 ... udhcpd ...`.

The script also sets `DHCP_IP_START=192.168.2.2` and `DHCP_IP_END=192.168.2.20`. Those variables are unused; they belong to a commented-out `dnsmasq` line. The range that actually applies is the `192.168.42.x` range in the config file.

In normal station mode the camera is a DHCP *client*. RkLunch.sh's `network_init` runs `eth_monitor.sh wlan0`, which runs `udhcpc -i wlan0 -p /var/run/wlan0.pid` when the link comes up. That `udhcpc` is not this file: it is the system BusyBox v1.27.2 applet, `/sbin/udhcpc -> ../bin/busybox` (verified read-only on the live camera, 2026-10-31). Its default script `/usr/share/udhcpc/default.script` was not checked.

Running it by hand, e.g. `udhcpd -f /oem/usr/etc/udhcpd.conf`, starts a DHCP server on `wlan0`. If `wlan0` is joined to the user's LAN in station mode, it would answer DHCP requests from other machines on that LAN with `192.168.42.x` addresses and a router of `192.168.42.1`. That is a real side effect to avoid.

## Evidence

```
$ file udhcpd ; sha256sum udhcpd ; stat -c %s udhcpd
ELF 32-bit LSB executable, ARM ... stripped
784ae858fc6a047b2684a746c98c774e63a93a8579c98edbe3c4346089f2805f  789204
$ readelf -d udhcpd | grep NEEDED
libc.so.0 ld-uClibc.so.1
$ readelf -p .comment udhcpd
GCC: (GNU) 3.3.2 20031005 (Debian prerelease)
GCC: (crosstool-NG 1.24.0) 8.3.0
$ strings -n 3 udhcpd | grep -nE 'BusyBox v|started, v|udhcp 1'
3679:BusyBox v1.36.1 (2024-11-04 07:39:54 UTC)
6045:udhcp 1.36.1
6046:started, v1.36.1
(Python) applet_names @file offset 0x9be08 -> 280 names, includes udhcpd, udhcpc; excludes telnetd, httpd, nc
$ strings bin/busybox | grep 'BusyBox v'   -> BusyBox v1.27.2 (2025-07-31 03:41:40 UTC)  (166 applets, no udhcpd)
$ strings -n 3 udhcpd | sed -n '6069,6089p'
192.168.0.20 / 192.168.0.254 / max_leases / 235 / auto_time / 7200 / decline_time / 3600 / ...
lease_file / /var/lib/misc/udhcpd.leases / pidfile / /udhcpd.pid / ... / static_lease / /etc/udhcpd.conf
$ grep -n udhcpd downlaods/3/dump/oem/usr/sbin/wifi_setup.sh
	udhcpd /oem/usr/etc/udhcpd.conf
	kill_apps NetworkManager wpa_supplicant hostapd udhcpd udhcpc
```

## Open questions

- Whether `/var/lib/misc` and `/var/run` are on tmpfs on the device (leases lost on reboot). This is likely, but the dump has no `/var` [INFERENCE].
- Clients get no `dns` option, so phones on the setup AP have no DNS server. That is probably harmless for a provisioning AP that only talks to `192.168.42.1`; which `lp_app` service clients use on that address is covered in the `lp_app` network report, not here.
- Why the vendor shipped a whole 789 KB BusyBox instead of enabling `udhcpd` in the system BusyBox is not determinable statically.
- The `GCC: (GNU) 3.3.2 20031005 (Debian prerelease)` `.comment` entry probably comes from a prebuilt object linked in by the toolchain. Its source is not identified.
