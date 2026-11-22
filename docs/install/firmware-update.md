# Firmware update from the microSD card

How to install a chosen camera firmware package by putting it on the microSD card as `cus_update_ota.tar`. The
camera flashes it on the next boot, without its update server.

!!! warning "This flashes the camera"
    The recovery system writes the boot, oem and (with 3.1.6 and later) rootfs partitions from the package. Use
    only an official `cam-<version>.tar` package, keep the camera powered until it has rebooted, and do not pull
    the card while it flashes. A broken package can leave the camera rebooting into recovery until the card is
    removed (see [Failure modes](#failure-modes)).

## Why

The camera updates itself, but slowly, and sometimes not at all:

- `lp_app` (3.1.3) does not check for updates when it starts. The first check comes about 10 hours after start,
  then every 10 hours, and only inside a daytime window that starts at 08:00 camera time (UTC). Outside the window
  it waits for 08:00. A camera that is restarted often may never reach a check.
- A `127.0.0.1 connect-ota.prusa3d.com` line in `/etc/hosts` blocks the check completely. `uninstall.sh --hosts`
  removes it (see [Uninstall](uninstall.md)).
- The production server only offers its latest version. A specific version, or one from the staging server, can
  only be installed by hand.

Details on the servers, the update check and the packages: [OTA firmware updates](../findings/ota.md).

## Prerequisite: the boot hook must return

The card's `lp_app.sh` hook must end in the background (`/tmp/sync_loop.sh &` or `lp_app ... &`, see
[Add the boot hook](3-installation.md#4-add-the-boot-hook)). `RkLunch.sh` runs the hook in the foreground from
`/etc/init.d/rcS`, and busybox init acts on `reboot recovery` only after rcS has finished.

Observed on 2026-11-22 with a hook that ended in `/tmp/sync_loop.sh` (foreground): with `cus_update_ota.tar` on the
card, `RkLunch.sh` ran `reboot recovery` at boot, but that process was still waiting minutes later and the camera
went on running the old firmware. As soon as `sync_loop.sh` was killed, the hook and rcS returned, the camera
rebooted into recovery at once and flashed 3.1.6 in under a minute. The `reboot recovery` at the end of an update
by `lp_app` would hang the same way [INFERENCE: same mechanism, not observed].

If a camera is stuck like this: fix the hook (append ` &` to its last line) and reboot. Killing `sync_loop.sh`
(or the foreground `lp_app`) also releases the pending `reboot recovery`, which then starts the update right away,
without a clean card unmount; `task buddy:reboot` does this as its first step.

## Tasks

All three tasks need `FW_VERSION`, for example `3.1.6`. `OTA_HOST` selects the server and defaults to
`connect-ota.prusa3d.com` (production). The staging server is `connect-ota-staging.prusa3d.com`; on 2026-11-22 it
had 3.1.7, production had 3.1.6.

### Download

```sh
task buddy:firmware:download FW_VERSION=3.1.6
task buddy:firmware:download FW_VERSION=3.1.7 OTA_HOST=connect-ota-staging.prusa3d.com
```

Downloads `https://<OTA_HOST>/file/cam-<FW_VERSION>.tar` to `firmware_images/cam-<FW_VERSION>.tar`, through a
`.part` file that is renamed when the download succeeds. If the file already exists, the download is skipped.

The task then checks the package:

- **SHA-1**: it asks the server's update check (`GET https://<OTA_HOST>/api/niceboy/v1/camera`, JSON with
  `last_version`, `sha1sum` and `file`). If `last_version` equals `FW_VERSION`, the package's SHA-1 must match
  `sha1sum`. Otherwise it prints the local SHA-1 and says that the server publishes a checksum only for its latest
  version.
- **Contents**: the file must be a tar that contains `RK_OTA_update.sh`.

The other two tasks run this one first, so you do not need to call it yourself.

### Over ssh

For a camera with the [ssh add-on](../features/ssh.md) running:

```sh
task buddy:firmware:upload FW_VERSION=3.1.6     # or: ... CAMERA_HOST=192.0.2.20
task buddy:reboot
```

`buddy:firmware:upload` downloads the package if needed and copies it with rsync over ssh to
`root@CAMERA_HOST:/mnt/sdcard/cus_update_ota.tar.part` (the camera side uses `/userdata/bin/rsync`). It compares
the md5 on both sides (the camera's BusyBox has `md5sum` but no `sha1sum`), renames the file to
`cus_update_ota.tar` and runs `sync`. It does not reboot; `task buddy:reboot` does, and the update starts on that
boot.

### With the card in a computer

For a camera without the ssh add-on. The stock firmware has at most telnet, which is not worth using for a 30 MB
file. Instead:

1. Power the camera off and take the microSD card out.
2. Mount the card on the computer.
3. Run, with the card's mount point:

   ```sh
   task buddy:firmware:sdcard FW_VERSION=3.1.6 SDCARD=/run/media/$USER/XXXX
   ```

4. Unmount the card, put it back into the camera and power the camera on.

`SDCARD` is checked like in `buddy:install` ([Installation](3-installation.md#3-copy-to-the-microsd-card)): the
task stops if the path is not a mount point, is not vfat or is not writable. It copies the package to
`cus_update_ota.tar.part`, compares the md5, renames it to `cus_update_ota.tar`, runs `sync` and then tells you to
unmount the card, put it back and power the camera on.

## What happens on the camera

1. **Boot.** The stock `/oem/usr/bin/RkLunch.sh` (the same in 3.1.3 and 3.1.6) sees
   `/mnt/sdcard/cus_update_ota.tar` (or `fac_update_ota.tar`), plays `upgrading.wav` and runs `reboot recovery`.
   This happens before the card's `lp_app.sh` hook, so no add-on starts.
2. **Recovery.** The recovery system (`/dev/mtd5`, an initramfs) runs its own `RkLunch.sh`. It first takes
   `/userdata/update_ota.tar` (a download by `lp_app`) if there is one. Otherwise it mounts the card at
   `/mnt/sdcard`, prefers `fac_update_ota.tar` over `cus_update_ota.tar` and extracts the package to
   `/mnt/sdcard/update/`. The card needs free space for the extracted files as well as the package.
3. **Flash.** `RK_OTA_update.sh` from the package writes every partition that has a matching `<name>.img`
   (3.1.6: boot, rootfs and oem), then erases `misc`.
4. **Reboot.** On success, recovery removes `update/` and `cus_update_ota.tar` and reboots. The shutdown unmounts
   the card first, so the deletion is written. The camera starts the new firmware, and the card's `lp_app.sh` hook
   starts the add-ons again.

## What survives

- `/userdata` (configuration, Prusa Connect token, the add-ons' copies) is not written: no package has a
  `userdata.img`.
- The microSD card is kept, apart from the package and `update/`.
- The 3.1.6 package rewrites the rootfs. Its `/etc/hosts` is the stock one, so a `connect-ota.prusa3d.com` line is
  gone afterwards and the camera checks for updates again. Packages up to 3.1.3 have no rootfs image.

## Check the result

Over ssh or telnet after the reboot:

```sh
ls /mnt/sdcard/cus_update_ota.tar     # should be gone
md5sum /oem/usr/sbin/lp_app
uname -v                              # kernel build date; changes with the boot image
```

| firmware | md5 of `/oem/usr/sbin/lp_app` |
|---|---|
| 3.1.3 | `ee845fa0b2e4a8cc0eaf5d7135b8f144` |
| 3.1.6 | `6747721508ef6c5091009fdf5f69431f` |
| 3.1.7 | `dffe6bd4fa7f6f09f433ad84e63b2276` |

Prusa Connect also shows the firmware version of the camera.

## Failure modes

- **Tar extraction error** (a broken or truncated package): recovery stops and leaves the package on the card.
  The camera then enters recovery again on every boot until the card is removed. Take the card out, delete
  `cus_update_ota.tar` and `update/` on a computer, and boot without it or with a good package. The tasks copy to a
  `.part` file and compare checksums so that a broken copy does not end up under the final name.
- **Flash error**: recovery removes `update/` but leaves the package on the card, so the next boot tries again.
- **`fac_update_ota.tar`** is never deleted by recovery. After flashing it, recovery waits until the card is
  pulled and only then reboots; the card would start the same update again when it is put back. The tasks only use
  `cus_update_ota.tar`; do not name a package `fac_update_ota.tar`.
