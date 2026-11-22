# Installation

Install via the microSD card. It needs no telnet and no earlier ssh access. Check the
[requirements](1-requirements.md) and prepare the [minimal settings](2-minimal-settings.md) first.

## 1. Build the binaries

```sh
cd buddy-addons
./build-dropbear.sh     # -> out/dropbearmulti
./build-rsync.sh        # -> out/rsync
./build-drill.sh        # -> out/drill
./build-lighttpd.sh     # -> out/lighttpd, out/mbedtls-gen-key, out/mbedtls-cert-write
./build-dosfstools.sh   # -> out/fsck.fat
./build-rsyslog.sh      # -> out/rsyslog/ (rsyslogd, modules, libs, musl loader)
./build-ntpsync.sh      # -> out/ntpsync (clock check used by the rsyslog start gate)
./build-logrotate.sh    # -> out/logrotate
```

Each script re-runs itself inside the `dockcross/linux-armv7l-musl` docker image. Source tarballs are cached in
`dl/` and checked against pinned SHA256 sums. `task buddy:stage` needs `out/ntpsync`, `out/fsck.fat`,
`out/logrotate` and `out/rsyslog/`, so build those even if you skip the features that use them, or copy files by
hand instead of staging.

## 2. Stage the scripts and configs

From the repo root:

```sh
task buddy:stage REMOTE_HOST=192.168.1.10
```

This fills `buddy-addons/build/device-stage/` with the device scripts and configs from `buddy-addons/device/`,
plus `ntpsync`, `fsck.fat`, `logrotate` and the `rsyslog/` bundle, writes your syslog server into `rsyslog.conf`,
and builds `authorized_keys` from the public key files in `SSH_PUBKEYS`. The repo templates stay unchanged.
`REMOTE_HOST` parameter is needed for rsyslog.

## 3. Copy to the microSD card

Put the card in the host's card reader and mount it. Then, from the repo root:

```sh
task buddy:install SDCARD=/run/media/$USER/SDCARD REMOTE_HOST=192.168.1.10
```

`SDCARD` is required and must be the card's mount point. The task stops before copying anything if that path is
not a mount point, is not vfat (the camera reads its card as vfat) or is not writable. It stages again (so pass
`REMOTE_HOST` as in step 2), creates `bin/` and `logs/`, copies the staged files to `bin/` without the `*-hook.sh`
blocks, and adds `dropbearmulti`, `rsync`, `drill`, `lighttpd`, `mbedtls-gen-key`, `mbedtls-cert-write` from
`out/` and `secrets/htpasswd`. A file that is missing is skipped with a message. It does not write `lp_app.sh`; that
is step 4. Delete the files of features you do not want from `bin/` afterwards (list below).

The same by hand, running in the root of the mounted card, so card paths are relative (`bin/`, `logs/`,
`lp_app.sh`); `ADDONS` points at the repo's `buddy-addons/` directory. From the repo root:

```sh
ADDONS=$PWD/buddy-addons
cd /path/to/mounted/sdcard              # e.g. /run/media/$USER/SDCARD
mkdir -p bin logs
rsync -r --exclude='*-hook.sh' "$ADDONS/build/device-stage/" bin/
cp "$ADDONS/out/dropbearmulti" "$ADDONS/out/rsync" "$ADDONS/out/drill" bin/
cp "$ADDONS/out/lighttpd" "$ADDONS/out/mbedtls-gen-key" "$ADDONS/out/mbedtls-cert-write" bin/
cp "$ADDONS/secrets/htpasswd" bin/htpasswd
```

Files per feature, all in `/mnt/sdcard/bin/`. Leave out the features you do not want:

- [ssh](../features/ssh.md): `dropbearmulti`, `start-sshd.sh`, `authorized_keys`
- [rsync](../features/rsync.md): `rsync` (installed by `start-sshd.sh`, so it needs the ssh feature)
- [HTTPS](../features/https.md): `lighttpd`, `mbedtls-gen-key`, `mbedtls-cert-write`, `start-httpd.sh`,
  `lighttpd.conf`, `dirlisting-header.html`, `htpasswd`
- [microSD fsck](../features/sdcard-fsck.md): `fsck.fat`, `sdcard-fsck.sh`
- [remote rsyslog](../features/rsyslog.md): `rsyslog/`, `rsyslog.conf`, `start-rsyslog.sh`, `ntpsync`
- [logrotate](../features/logrotate.md): `logrotate`, `logrotate.conf`, `start-logrotate.sh`

`drill` (DNS lookup) is optional; `start-sshd.sh` and `start-httpd.sh` install it when present, and the HTTPS
directory listing uses it for the title.

## 4. Add the boot hook

`RkLunch.sh` runs `/mnt/sdcard/lp_app.sh` on every boot **instead of** `lp_app`, the camera application. Each
add-on is started by a block from `buddy-addons/device/*-hook.sh` pasted into that file, in this order:

1. ssh block (`sshd-hook.sh`), while the card is still mounted.
2. microSD check block (`fsck-hook.sh`). It replaces the `umount /mnt/sdcard` and `mount -t vfat ...` lines.
3. HTTPS block (`httpd-hook.sh`).
4. syslog block (`rsyslog-hook.sh`).
5. logrotate block (`logrotate-hook.sh`).
6. The line that starts `lp_app`, last, in the background (ending in ` &`).

!!! warning "The hook must start lp_app"
    Without a final `lp_app` line (or a script such as `sync_loop.sh` that starts it), the camera boots without
    video, cloud connection and Wi-Fi management. `lp_app` manages the Wi-Fi, so ssh is unreachable too.

!!! warning "The hook must return"
    `RkLunch.sh` runs `lp_app.sh` in the foreground from `/etc/init.d/rcS`, and busybox init acts on a reboot
    request only after rcS has finished. If the last line of the hook never returns (`lp_app ...` or
    `/tmp/sync_loop.sh` without ` &`), plain `reboot` does nothing and `reboot recovery` hangs as well: a firmware
    update from the card or from `lp_app` is not installed (see [Firmware update](firmware-update.md)).
    An existing hook that ends in the foreground is fixed by appending ` &` to its last line, for example
    `/tmp/sync_loop.sh &`, then rebooting with `task buddy:reboot`.

# If you have your own customizations already?

**If you already have a `lp_app.sh` on the card:** back it up, then paste the blocks at the places above. Comment out
any `telnetd` line once ssh works.

**If you have no `lp_app.sh` yet:** build one from the blocks of the features you installed. Still in the card root:

```sh
d=$ADDONS/device
{
  echo '#!/bin/sh'
  echo 'mkdir -p /mnt/sdcard/logs /mnt/sdcard/timelapse'
  cat "$d/sshd-hook.sh" "$d/fsck-hook.sh" "$d/httpd-hook.sh" "$d/rsyslog-hook.sh" "$d/logrotate-hook.sh"
  echo 'lp_app --noshell --log2file /mnt/sdcard/logs &'
} > lp_app.sh
```

Drop the `cat` arguments of the features you skip, but keep `fsck-hook.sh`: when `sdcard-fsck.sh` is missing it
falls back to the stock `umount`/`mount` lines that remount the card read-write and executable. The last line starts
`lp_app` in the background, as the stock `RkLunch.sh` does, with its logs in `/mnt/sdcard/logs`; drop
`--log2file /mnt/sdcard/logs` to keep `lp_app` logs off the card. In the background the hook returns, so rcS
finishes and reboots and firmware updates work. This exact file is assembled from the repo blocks and the order
above; it was not run as-is on the camera. [INFERENCE]

A hook that runs on a camera today has code blocks for:

- the ssh block before the plain `umount`/`mount` lines,
- the HTTPS,
- syslog
- logrotate
- ends with `/tmp/sync_loop.sh &`, which starts `lp_app` when it is not running; the ` &` lets the hook return.

Then flush via `sync`, leave the card and unmount it:

```sh
sync
cd -                                    # umount fails while the shell is still on the card
umount /path/to/mounted/sdcard
```

## 5. Boot

Put the card in the camera and power-cycle it. On each boot the start scripts copy the binaries and configs from
`/mnt/sdcard/bin/` to `/userdata` (only when they changed) and start the daemons.

## 6. Verify

```sh
ssh root@CAMERA_IP 'ps | grep -E "dropbear|lighttpd|rsyslogd|logrotate" | grep -v grep'
ssh root@CAMERA_IP 'ls /mnt/sdcard/logs; tail -n 5 /mnt/sdcard/logs/fsck.log'
curl http://CAMERA_IP:8080/                 # shipped lighttpd.conf: plain HTTP, no password
```

Each start script logs to `/mnt/sdcard/logs/` (`dropbear.log`, `httpd.log`, `rsyslog.log`, `logrotate.log`,
`fsck.log`), or to `/tmp` when that directory is missing. The feature pages have detailed checks.

If ssh does not come up: take the card out and fix `lp_app.sh` on the host (for a recovery login, uncomment
`telnetd` or restore your backup), then power-cycle.

An empty `/mnt/sdcard/lp_stop` file is **not** a recovery: it skips the whole hook and also `lp_app`, so nothing
remote starts.

## Updates

Once ssh works, then tou should be able to use `rsync` toupdate scripts, configs and the bundled binaries over the
network:

```sh
task buddy:sync CAMERA_HOST=192.0.2.20 REMOTE_HOST=192.168.1.10
```

It stages again and rsyncs `buddy-addons/build/device-stage/` to `/mnt/sdcard/bin/`, including `authorized_keys`
built from `SSH_PUBKEYS`, which replaces the key list on the card. It does not copy `dropbearmulti`, `rsync`,
`drill`, `lighttpd`, `mbedtls-*`, `htpasswd` or the `*-hook.sh` blocks; copy those with `scp -O` or via the card.
The new files are installed on the next boot, or at once by running the matching start script, e.g.
`ssh root@CAMERA_IP sh /mnt/sdcard/bin/start-httpd.sh`.

## Rebooting

With a hook that ends in the background, plain `reboot` restarts the camera (verified 2026-11-22), but it does not
stop `lp_app` first: the next boot logged `FAT-fs (mmcblk1p1): Volume was not properly unmounted` in `dmesg`.
`sync; reboot -f` alone skips the unmount too, as `lp_app` still has its log open on the card. With a hook that
never returns, plain `reboot` does nothing at all (see the warning in [Add the boot hook](#4-add-the-boot-hook)).

To reboot with the card cleanly unmounted, from the repo root:

```sh
task buddy:reboot                       # or: task buddy:reboot CAMERA_HOST=192.0.2.20
task buddy:reboot -- -n                 # dry run: list what it would stop
```

The task copies `buddy-addons/device/safe-reboot.sh` to `/tmp` on the camera and runs it. The script:

1. kills `sync_loop.sh` (SIGKILL: it would start `lp_app` again, and its SIGTERM trap sleeps 300 s);
2. sends `lp_app` SIGTERM and waits up to 20 s, then SIGKILL;
3. stops the rsyslog waiter, rsyslogd, the logrotate loop and lighttpd, then anything else that still has a file
   or its working directory on the card;
4. runs `sync` and `umount /mnt/sdcard` (5 tries); if the card stays busy, it remounts it read-only instead;
5. 1 s later, after its own ssh session has ended, stops every dropbear and `telnetd` process so other open ssh
   and telnet sessions are closed cleanly instead of hanging, then runs `reboot -f`. This step is detached.

By hand on the camera (the script must not run from the card, which it unmounts):

```sh
cp /mnt/sdcard/bin/safe-reboot.sh /tmp/ && sh /tmp/safe-reboot.sh
```

`task buddy:stage` puts `safe-reboot.sh` into `bin/` with the other device scripts. Power cuts still leave the
card dirty. The [microSD fsck](../features/sdcard-fsck.md) feature repairs that on the next boot, but only if
`fsck.fat` fits in the camera's RAM (see below).

!!! note "The dirty flag stays until fsck.fat clears it"
    Linux sets the FAT32 dirty flag (boot sector byte `0x41`, bit 0) at mount and clears it at unmount, but only
    if the flag was clear at mount: `fat_set_state()` in `fs/fat/inode.c` (Linux 5.10.110, the camera's version)
    returns early when the volume was dirty at mount, and on mount it prints the warning instead. So once a
    `reboot -f` or power cut has left the flag set, a clean unmount keeps it set, and every boot logs
    `Volume was not properly unmounted` again. Seen on the maintainer's camera on 2026-11-08: after
    `task buddy:reboot` unmounted the card, the byte was still `0x01` and the warning came back.

    Run `fsck.fat -a /dev/sdX1` once on a PC with the card not mounted. After that, `task buddy:reboot` should
    keep the card clean [INFERENCE: not yet seen with a clean card].

    On the camera, `fsck.fat` needs about 12 bytes of RAM per cluster. The maintainer's 32 GB card has 16 KiB
    clusters (about 1.95 million), so about 23 MB, and a run on the camera with `lp_app` stopped was killed with
    SIGKILL (exit 137), most likely by the OOM killer. The microSD fsck feature cannot check such a card at boot
    either. Check it on a PC, or reformat it with 32 KiB clusters (`mkfs.fat -F 32 -s 64`, erases the card).

## Uninstall

Notice that removing `/mnt/sdcard/lp_app.sh` from the card will not
remove  custom files from `/userdata`.

See [Uninstall](uninstall.md): `task buddy:uninstall` over ssh for proper cleanup.
