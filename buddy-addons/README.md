# Buddy3D / Prusa Core One L camera add-ons

Static ARMv7 binaries for the Buddy3D camera of the Prusa Core One L, how to build them, how to get them on via
microSD, ssh or (if re-enabled) telnet, and how to run them: an ssh server (dropbear), rsync, a dig-style DNS lookup
tool (drill), a read-only HTTP/HTTPS file server for the microSD card (lighttpd), a microSD check and repair at boot
(fsck.fat) and a remote syslog forwarder (rsyslog). This file holds the facts shared by all add-ons. Each add-on has
its own document.

| add-on | what it is | binary in `out/` | build script | device scripts | ports | doc |
|---|---|---|---|---|---|---|
| dropbear | ssh server, `scp`, key tools | `dropbearmulti` | `build-dropbear.sh` | `device/start-sshd.sh`, `device/sshd-hook.sh` | 22 | [dropbear.md](dropbear.md) |
| rsync | rsync server and client, used over ssh | `rsync` | `build-rsync.sh` | installed by `device/start-sshd.sh` | none (over ssh) | [rsync.md](rsync.md) |
| drill | dig-style DNS lookup tool | `drill` | `build-drill.sh` | installed by `device/start-sshd.sh` | none | [drill.md](drill.md) |
| lighttpd | read-only HTTP/HTTPS file server for the card | `lighttpd`, `mbedtls-gen-key`, `mbedtls-cert-write` | `build-lighttpd.sh` | `device/start-httpd.sh`, `device/httpd-hook.sh`, `device/lighttpd.conf`, `device/dirlisting-header.html` | 8080, 8443 | [lighttpd.md](lighttpd.md) |
| sdcard-fsck | checks and repairs the card (`fsck.fat -a`) at boot, then mounts it read-write | `fsck.fat` | `build-dosfstools.sh` | `device/sdcard-fsck.sh`, `device/fsck-hook.sh` | none | [sdcard-fsck.md](sdcard-fsck.md) |
| rsyslog | forwards `/dev/log`, the kernel log and the card's log files to a remote syslog server | `rsyslog/` (dynamic musl bundle) | `build-rsyslog.sh` | `device/start-rsyslog.sh`, `device/rsyslog-hook.sh`, `device/rsyslog.conf` | none (sends to UDP/TCP 514) | [rsyslog.md](rsyslog.md) |
| logrotate | rotates the add-on logs daily, keeps 7, no compression; reopens each file (copytruncate or SIGHUP) | `logrotate` | `build-logrotate.sh` | `device/start-logrotate.sh`, `device/logrotate-hook.sh`, `device/logrotate.conf` | none | [logrotate.md](logrotate.md) |

Host-side helpers: `gen-cert.sh` and `install-cert.sh` create a TLS key and certificate for lighttpd on the host and install it on the camera over ssh (see [lighttpd.md](lighttpd.md#use-a-certificate-made-on-the-host)). `gen-htpasswd.sh` creates users for lighttpd basic auth (see [lighttpd.md](lighttpd.md#users-and-passwords)). Its output in `secrets/` and the certificates in `certs/` are gitignored.

## Target facts

From the firmware dumps in this repo.

| item | value | source |
|---|---|---|
| CPU | ARMv7l, Cortex-A7, NEON, VFPv4, hard-float | `readme.md` (`/proc/cpuinfo`) |
| kernel | Linux 5.10.110 (Rockchip) | `readme.md` |
| RAM | 34 MB total; 26.9 MB used, 7.4 MB free after cache, with lp_app running | `readme.md` (`free`) |
| rootfs | `ubi0:rootfs` ubifs, mounted `ro` in the captured mount table; `inittab` also runs `mount -o remount,rw /` at sysinit | `readme.md`, `3/dump/etc/inittab` |
| `/userdata` | ubifs, rw, about 57 MB free | `readme.md` |
| `/oem` | ubifs, rw, about 6 MB free | `readme.md` |
| microSD | `/mnt/sdcard` vfat. The hooks remount it with `fmask=000,dmask=000`, so files on the card are executable | `sdcard*/lp_app.sh` |
| volatile | `/tmp`, `/run`, `/dev/shm` (tmpfs) | `readme.md` |
| userland | busybox 1.27.2 + uClibc. Applets used here: `telnetd`, `nc`, `tftp`, `uudecode`, `md5sum`, `mount`, `timeout` (old `-t SECS` form). The running camera has no `base64`, `sha256sum` or `time` applet (checked with `busybox --list`). The firmware has no `fsck.vfat`/`fsck.fat` (busybox `fsck` is only a wrapper). Its busybox has `syslogd`, `klogd` and `logger` applets, but `ps` shows none running, so nothing creates `/dev/log` | `3/dump/bin/busybox`, `ps` (repo root), camera |
| login | `/etc/profile` sets `PATH="/bin:/sbin:/usr/bin:/usr/sbin"` (drops `/userdata/bin`) and prints nothing non-interactive | `3/dump/etc/profile` |
| root | home `/root`: missing in the 3.1.0 dump, owned by uid 1001 on 3.1.6; `/` is owned by uid 1001 (mode 775 on 3.1.3, 755 on 3.1.6), hence the passwd bind mount in [dropbear.md](dropbear.md). Password: md5crypt hash in `/etc/shadow` (plaintext unknown) | `3/dump/etc/passwd`, `shadow` |

The boot hook that runs on every boot is `/mnt/sdcard/lp_app.sh`. `/oem/usr/bin/RkLunch.sh` copies it to `/tmp/lp_app.sh` and runs it, unless `/mnt/sdcard/lp_stop` exists. Your repo has three variants of this hook: `sdcard/`, `sdcard_rsync/`, and `sdcard_no_rsync/`. `sdcard_rsync` and `sdcard_no_rsync` end by running `sync_loop.sh` (rclone), which kills `lp_app` while it syncs. The sshd started here is a separate daemon and is not affected by that.

Telnet is disabled on the camera. The card's hook was the only thing that started `telnetd` (the line in `RkLunch.sh` is commented out). In the card's `lp_app.sh` that line is now commented out, so remote access is ssh only (dropbear). The previous hook is saved on the card as `/mnt/sdcard/lp_app.sh.bak-pre-notelnet`. The hook templates in this repo (`sdcard/`, `sdcard_rsync/`, `sdcard_no_rsync/`) still start `telnetd`; they were not changed. Comment out the `telnetd` line if you copy one of them to a card.

Verified on the camera: after `sync; reboot -f`, port 23 refused connections, no `telnetd` process ran, ports 22 (dropbear), 8080/8443 (lighttpd) and 554 (RTSP) listened, and ssh key login worked.

Recovery if ssh does not come up: take the card out and, on a PC, either uncomment `telnetd` in `lp_app.sh` or restore `lp_app.sh.bak-pre-notelnet`. Then put the card back and power-cycle the camera. An empty `lp_stop` file is not a recovery: it skips the whole hook, so neither telnet nor ssh starts (stock behaviour).

## Compile

Host requirements: `docker` (your user must be able to run it), `curl`, `sha256sum`. No ARM toolchain install is needed.

```sh
cd buddy-addons
./build-dropbear.sh     # -> out/dropbearmulti
./build-rsync.sh        # -> out/rsync
./build-drill.sh        # -> out/drill
./build-lighttpd.sh     # -> out/lighttpd, out/mbedtls-gen-key, out/mbedtls-cert-write
./build-dosfstools.sh   # -> out/fsck.fat
./build-rsyslog.sh      # -> out/rsyslog/ (rsyslogd, modules, libs, musl loader)
./build-ntpsync.sh      # -> out/ntpsync (kernel clock sync check, used by the rsyslog start gate)
```

Each script re-runs itself inside the cross container via `env.sh`. Tarballs are cached in `dl/` and checked against
pinned SHA256 values. Build trees are rebuilt from scratch on each run. `build/` and `dl/` are scratch and listed in
`.gitignore`. `out/` holds the deliverable binaries and the `out/rsyslog/` bundle.

All eight binaries (the six below plus `fsck.fat` and `ntpsync`) are `ELF 32-bit LSB executable, ARM, EABI5 version 1,
hard-float, statically linked, stripped`, non-PIE. The toolchain is `dockcross/linux-armv7l-musl` (GCC 11.2, musl), so
they need no device libc. Each add-on document lists its artifacts with size and sha256, and its qemu version check.

The exception is `out/rsyslog/`: rsyslogd loads its modules with `dlopen()`, which a static musl binary cannot do.
It is a dynamic musl build that ships its own loader (`ld-musl-armhf.so.1`, which is also its libc) and is started
through it, so it still does not use the device's uClibc. See [rsyslog.md](rsyslog.md).

```sh
file out/dropbearmulti out/rsync out/drill out/lighttpd out/mbedtls-gen-key out/mbedtls-cert-write out/fsck.fat out/ntpsync
```

Verified on the host: `dropbearmulti`, `rsync` and `drill` are static ARM EABI5 hard-float, non-PIE (`file`, `readelf -h`).

## Install via microSD

Recommended. The card is the source of truth. It survives firmware updates that wipe `/userdata`, and the start scripts restore binaries and keys from it on every boot.

Binaries and start scripts go to `/mnt/sdcard/bin/`. Each add-on document lists its files there. On the host:

```sh
SD=/path/to/mounted/sdcard          # e.g. /run/media/$USER/SDCARD
mkdir -p "$SD/bin"
```

Each start script is called from a block pasted into the boot hook `/mnt/sdcard/lp_app.sh`. Use whichever `lp_app.sh` variant is actually on your card. Where the blocks go:

- ssh block (`device/sshd-hook.sh`, see [dropbear.md](dropbear.md)):
  - in `sdcard/` and `sdcard_rsync/`, `sdcard_no_rsync/`: right **before** the line `umount /mnt/sdcard`. It must run while the card is still mounted.
  - in the `8/` variant (the plain one that ends with `lp_app --noshell ...`): right before that final `lp_app` line.
- microSD check block (`device/fsck-hook.sh`, see [sdcard-fsck.md](sdcard-fsck.md)):
  - in `sdcard/` and `sdcard_rsync/`, `sdcard_no_rsync/`: it **replaces** the two lines `umount /mnt/sdcard` and
    `mount -t vfat -o rw,... /dev/mmcblk1p1 /mnt/sdcard`, i.e. it goes right after the ssh block.
  - in the `8/` variant: right after the ssh block, before the final `lp_app` line.
- httpd block (`device/httpd-hook.sh`, see [lighttpd.md](lighttpd.md)): right **after** the remount line
  `mount -t vfat -o rw,... /dev/mmcblk1p1 /mnt/sdcard` (or after the microSD check block that replaces it) and before
  `/tmp/sync_loop.sh`.
- syslog block (`device/rsyslog-hook.sh`, see [rsyslog.md](rsyslog.md)): after the httpd block (or after the remount /
  microSD check block if you have no httpd block), right before `/tmp/sync_loop.sh`. Edit the remote target in
  `rsyslog.conf` first: the start script refuses the `REMOTE_HOST` placeholder.
- logrotate block (`device/logrotate-hook.sh`, see [logrotate.md](logrotate.md)): right before
  `/tmp/sync_loop.sh`, after the syslog block.

Resulting order: ssh block, microSD check block, httpd block, syslog block, logrotate block, `sync_loop.sh`.

Eject the card, put it in the camera, and power-cycle the camera. The hook runs as before (config fix-ups and the rest of your hook; on this camera's card `telnetd` is commented out, see [Target facts](#target-facts)), then the add-on blocks.

To disable all add-ons and get stock behaviour, create an empty file `/mnt/sdcard/lp_stop`. That also means no ssh and no telnet.

## Upload via telnet

Telnet is off by default (see [Target facts](#target-facts)). The normal way to copy files is over ssh (`scp -O`) or via the card. The methods below are for a first install before ssh exists, or when telnet has been turned on temporarily.

To turn telnet on: take the card out, uncomment the `telnetd` line in `/mnt/sdcard/lp_app.sh`, put the card back and reboot. Comment it out again and reboot when done. Telnet listens on port 23 and logs in as root with the camera's existing password. Telnet is plaintext: use it only on a trusted network.

```sh
telnet CAMERA_IP
```

On the camera, create the directory first:

```sh
mkdir -p /userdata/bin
```

Then get the binaries across. The examples use `rsync`; repeat for every other binary you need (`dropbearmulti`, `drill`). Options, in order of preference:

**a. busybox `nc` listener (tested on the camera).** busybox `nc` sends its own stdin to the peer and exits as soon as that stdin reaches EOF. A listener with stdin at `/dev/null`, or one left behind when the telnet session closes, therefore saves a 0-byte file. Keep its stdin open with a `sleep` pipe:

```sh
(sleep 600 | nc -l -p 9000 > /userdata/bin/rsync.up) &
```

On the host (OpenBSD netcat sends EOF only with `-N`; traditional netcat uses `-q 0`):

```sh
nc -N CAMERA_IP 9000 < out/rsync         # or: nc -q 0 CAMERA_IP 9000 < out/rsync
```

Wait for the transfer to finish, keeping the telnet session open, then compare checksums and move the file into place. Repeat for `dropbearmulti` (rename both from `.up` and `chmod 755`). Kill the leftover `sleep` afterwards with `kill <pid>`, taking the pid from `ps`:

```sh
md5sum out/rsync                         # host
md5sum /userdata/bin/rsync.up            # camera; must match
mv /userdata/bin/rsync.up /userdata/bin/rsync && chmod 755 /userdata/bin/rsync
```

Verified on the camera: upload via busybox `nc -l` over telnet, using this stdin holder, with md5 matching for all files.

**b. Base64 paste (when `nc -l` is unavailable).** The camera has no `base64` applet, but busybox `uudecode` reads the `begin-base64` format. Host:

```sh
{ echo "begin-base64 755 rsync"; base64 out/rsync; echo "===="; } > rsync.b64   # about 700 KB
split -l 2000 rsync.b64 part_            # paste chunks of about 2000 lines
```

Camera, for each `part_*` chunk, paste the text and then press Ctrl-D:

```sh
cat >> /userdata/bin/rsync.b64
```

Once all chunks are in, decode once, compare, and clean up:

```sh
uudecode -o /userdata/bin/rsync /userdata/bin/rsync.b64
rm /userdata/bin/rsync.b64
chmod 755 /userdata/bin/rsync
md5sum /userdata/bin/rsync               # must match host md5sum out/rsync
```

Verified on the camera: `out/drill` wrapped this way and decoded with `uudecode` matched the host md5.

Repeat for `dropbearmulti` (and `drill` if you want it). This is slow and fragile for binaries, so prefer the card if it fails.

**c. Busybox TFTP.** The camera has the busybox `tftp` client. If you run a TFTP server on the host: `tftp -g -r rsync -l /userdata/bin/rsync HOST_IP`.

Scripts and text files (for example `start-sshd.sh`) are pasted the same way as in b.

## Rebooting

busybox init (v1.27.2) acts on a reboot request only after its sysinit actions have finished. `RkLunch.sh` runs
`/mnt/sdcard/lp_app.sh` in the foreground from `/etc/init.d/rcS`, so a hook whose last line never returns
(`/tmp/sync_loop.sh` or `lp_app ...` without `&`) keeps rcS running: plain `reboot` then does nothing, and
`reboot recovery` (firmware updates from the card or by `lp_app`) hangs too. Confirmed on 2026-11-22: killing
`sync_loop.sh` let a pending `reboot recovery` fire at once.

Fix: end the hook in the background, `/tmp/sync_loop.sh &` (or `lp_app --noshell --log2file /mnt/sdcard/logs &`),
as the stock `RkLunch.sh` does with `lp_app --noshell &`. With that, plain `reboot` works, but it does not stop
`lp_app` or unmount the card first: the next boot logged `FAT-fs (mmcblk1p1): Volume was not properly unmounted`.
Use `task buddy:reboot` (`safe-reboot.sh`: stops `lp_app`, unmounts the card, then `reboot -f`) for a clean
reboot. `sync; reboot -f` works with any hook but is equivalent to a power cycle, with no clean unmount.

## Persistence and memory

Shared paths (paths owned by one add-on are listed in its document):

| location | survives reboot | survives firmware update | notes |
|---|---|---|---|
| `/mnt/sdcard/bin/*` | yes | yes | canonical copies |
| `/userdata/bin/*` | yes | may be wiped | refreshed from the card at each boot |
| `/tmp/*` | no | no | pidfiles and fallback logs, including `/tmp/lighttpd.pid` and `/tmp/lighttpd.log` |

Memory: with `lp_app` running and three ssh sessions open, the camera had about 6 MB free after cache (`free` on the device). `sync_loop.sh` kills `lp_app` before its rclone runs, so there is more headroom during syncs.

## Building other apps

For the same device:

```sh
. buddy-addons/env.sh
toolchain_init "$@"                    # re-execs into the docker cross image
$CC $CFLAGS -o app app.c $LDFLAGS      # static, Cortex-A7, hard-float
```

Keep binaries static and small. Put them on the card or in `/userdata`, never under `/`.
