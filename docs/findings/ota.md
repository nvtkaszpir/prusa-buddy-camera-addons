# OTA firmware updates

Where the camera looks for firmware updates, how it picks the server, what the server answers and what an update
package contains. Sources: the strings of the 3.1.0 `lp_app` (dump), of the live 3.1.3 `lp_app`
(`firmware_images/scard-content-old/live-3.1.3/oem/usr/sbin/lp_app`, md5 `ee845fa0b2e4a8cc0eaf5d7135b8f144`) and of
the 3.1.6 `lp_app` from the 3.1.6 package (md5 `6747721508ef6c5091009fdf5f69431f`), the packages in
`firmware_images/`, and requests to both update servers from a host on 2026-11-10 and 2026-11-22, the camera's
`lp_app` logs and the recovery partition dumped from the camera. More on the update code is in
[`lp_app`](cam-3.1.3/oem/usr/sbin/lp_app.md#shutdown-reboot-and-ota).

## Summary

- There is no separate beta URL. The firmware knows two update servers: production and staging. Staging is
  labelled `OTA Unstable version` in the log strings.
- Update check: HTTPS GET `/api/niceboy/v1/camera` on `connect-ota.prusa3d.com` (production) or
  `connect-ota-staging.prusa3d.com` (staging).
- On 2026-11-10 both servers offered **3.1.6**, the same package (same SHA-1). On 2026-11-22 production still
  offered 3.1.6, while staging offered **3.1.7** (see [3.1.6 → 3.1.7 differences](cam-3.1.7-diff.md)).
- `lp_app` 3.1.3 checks about every 10 hours, the first time about 10 hours after start, and only in a daytime
  window that starts at 08:00 (see [When it updates](#when-it-updates)).
- Recovery installs a package placed on the card as `cus_update_ota.tar`
  (see [The recovery system](#the-recovery-system) and [Firmware update](../install/firmware-update.md)).
- A file on the microSD card, `/mnt/sdcard/ota`, or the `lp_app --ota` option switches the server.
- The 3.1.6 package is the first one with a `rootfs.img`, so updating to it rewrites the root filesystem. The
  packages up to 3.1.3 contain only `boot.img` and `oem.img`.
- The maintainer's camera checks no server at all: its `/etc/hosts` maps `connect-ota.prusa3d.com` to `127.0.0.1`
  (see [Uninstall](../install/uninstall.md#state-of-the-firmware-partitions)).

## Servers

| server | host | selected by |
|---|---|---|
| production | `connect-ota.prusa3d.com` | default; `OTA=prod` or `OTA=stable` |
| staging ("unstable") | `connect-ota-staging.prusa3d.com` | `OTA=dev`, `OTA=unstable` or `OTA=stage` |

- Update check: `https://<host>/api/niceboy/v1/camera`
- Package on 2026-11-10: `https://<host>/file/cam-3.1.6.tar`. On 2026-11-22 production still offered 3.1.6;
  staging offered `cam-3.1.7.tar`.

Both host names are compiled into all three `lp_app` builds. The path `niceboy` is the name of the camera's OEM
platform; `lp_app` also reports `manufacturer` = `Niceboy`.

## The update check

`lp_app` sends a GET with three headers: `X-Camera-Token` (the Prusa Connect token), `X-Camera-Fingerprint` and
`X-Camera-FW-Version`. It follows a `301` answer (`redirect host: %s path: %s`).

Answers to requests from a host without the token, on 2026-11-10. They were the same with no headers and with
`X-Camera-FW-Version: 3.1.3` or `3.1.6-rc1`:

```json
{"file":"https://connect-ota.prusa3d.com/file/cam-3.1.6.tar","last_version":"3.1.6",
 "sha1sum":"6fc0f0d540b50a3af5defab86947811b923bbfcd","force_upgrade":false}
```

The staging server answered the same, with its own host name in `file`. Whether the server answers differently to a
request with a real camera token was not tested.

On 2026-11-22 production answered the same as above. Staging answered `last_version` `3.1.7` with `sha1sum`
`219e700df177b6ba19d483cf0cc4dadd88c7efb7`, `force_upgrade` false and still no `last_release_type`. Details in
[3.1.6 → 3.1.7 differences](cam-3.1.7-diff.md#where-317-came-from).

Fields:

| field | meaning | key string in |
|---|---|---|
| `last_version` | newest version, compared with the built-in one (`OTA FW: %d.%d.%d %s cur: …`) | 3.1.0/3.1.3/3.1.6 |
| `sha1sum` | SHA-1 of the package, checked after the download | 3.1.0, 3.1.3, 3.1.6 |
| `last_release_type` | release type, see below. Missing from both answers above | 3.1.0, 3.1.3, 3.1.6 |
| `file` | package URL, split into host and path (`download host: %s path: %s`) [INFERENCE] | see below |
| `force_upgrade` | install on the first check after boot [INFERENCE] | 3.1.6 only |

Only these three binaries were checked; the 3.1.4 and 3.1.5 ones were not. `last_version`, `sha1sum` and
`last_release_type` sit together in the upgrade service's string block. The binaries have no `file` string of
their own; it is probably shared with a longer string that ends in `file` [INFERENCE]. `force_upgrade` is not in
the 3.1.0 or 3.1.3 binary. In 3.1.6 it appears as a string and in log messages such as
`First OTA check after boot. force_upgrade: %d`; the JSON lookup itself was not traced. The 3.1.3 message
`Start upgrade FW now! Force upgrade` most likely belongs to the cloud command `start_fw_update`, whose string is
two strings before it, not to this field [INFERENCE].

## Choosing the server

At start, `lp_app` reads `/mnt/sdcard/ota`, then applies `--ota <host>`, which overrides the file. The file holds an
`OTA=` line:

| `OTA=` value | server |
|---|---|
| `prod`, `stable` [INFERENCE: `stable` is not next to the other values in the binary] | production |
| `dev`, `unstable`, `stage` | staging |
| `custom` | the host from a `URL=` line in the same file (`Custom OTA server`, `Set URL: %s`) |
| missing file, empty file or any other value | production (`Use default OTA server address %s`) |

Example for the staging server:

```sh
echo 'OTA=stage' > /mnt/sdcard/ota      # then restart lp_app or reboot
```

Whether `URL=` takes a host name or a full URL was not checked; the built-in defaults are host names [INFERENCE].
The same mechanism with `imgsrv`/`IMAGE_SRV=` and `siosrv`/`SIO_SRV=` switches the snapshot and signaling hosts.
Anyone who can write to the card can point the camera at their own update server, which makes physical access to
the card matter.

## Release types ("beta")

3.1.3 and 3.1.6 compare release types as well as versions. They parse `last_release_type` with the `sscanf` format
`%15[^-]-%d`, i.e. a name and a number such as `RC-2` [INFERENCE: example value]:

- `OTA release type %s-%d > %s-%d` → upgrade;
- `OTA release type %s-%d <= %s-%d. No upgrade needed`;
- `Current is RC, OTA is final. Allow upgrade.`: a camera on a release candidate takes the final release;
- `Release type is empty. Skip check`: that is the case for both answers above.

So a beta would be a release-candidate type in `last_release_type`, most likely served from the staging server
[INFERENCE]. No release candidate was on offer on 2026-11-10.

## When it updates

- **Periodic check.** Seen in the `lp_app` 3.1.3 logs of the maintainer's camera: no check when `lp_app` starts;
  the first check about 10 hours after start, then every 10 hours. The interval can change at run time
  (`Change request interval to %d seconds`); where the 10 hours come from was not traced.
- **Cloud command.** Prusa Connect can send `start_fw_update` (`Start upgrade FW now! Force upgrade`).
- **Daytime window.** 3.1.3 and 3.1.6 check the hour (`Current hour: %d`). In the 3.1.3 logs the window starts at
  08:00 camera time (UTC); checks were seen up to 19:44, so its end lies after that. Log lines seen:
  `query ota firmware info` (a check), `Within daytime upgrade interval`, and outside the window
  `Outside daytime upgrade interval` every 15 seconds, until the check at 08:00.
- **Forced update after boot (3.1.6).** `First OTA check after boot. force_upgrade: %d` and
  `Force auto upgrade. ret: %d, force_upgrade: %d, isFirstOtaCheckAfterBoot: %d`: with `force_upgrade` true,
  the first check after a boot installs the update [INFERENCE: whether the daytime window applies].

The install steps are the same in all three builds: download to `/userdata/update_ota.tar`, check the SHA-1 (on a
mismatch the file is deleted and `ota_fw_download_failed` is reported), play `upgrading.wav`, write `boot-recovery`
to the misc partition `/dev/mtd3`, then `reboot recovery`. The recovery system then installs the package, see below.

`reboot recovery` (from this OTA path and from the card path of `RkLunch.sh` below) only takes effect after
`/etc/init.d/rcS` has finished, because busybox init waits for its sysinit actions. A card `lp_app.sh` hook that
runs in the foreground keeps rcS from finishing and so blocks the update (observed 2026-11-22, see
[Firmware update from the microSD card](../install/firmware-update.md)).

## The recovery system

Source: the recovery partition `/dev/mtd5` ("recovery", 4 MiB), dumped from the maintainer's camera (3.1.3) to
`firmware_images/live-partitions/recovery.bin` (md5 `3adb856b9dcd66f53e1623e732ad72df`). It is a FIT image; its
gzip cpio initramfs starts at offset 2840064. `etc/init.d/S99lunch_recovery` in it runs `/usr/bin/RkLunch.sh`
(not the same script as the stock `/oem/usr/bin/RkLunch.sh`).

How the stock firmware gets there without `lp_app`: the stock `/oem/usr/bin/RkLunch.sh` (identical in 3.1.3 and
3.1.6) runs `reboot recovery` after playing `upgrading.wav` if `/mnt/sdcard/cus_update_ota.tar` or
`fac_update_ota.tar` exists. This happens before the card's `lp_app.sh` hook.

The recovery `RkLunch.sh`:

1. Uses `/userdata/update_ota.tar` (the download by `lp_app`) if it exists: extracts it to `/userdata/update/`,
   runs `RK_OTA_update.sh`, deletes the package and `update/` and reboots on success. On an extraction or flash
   error it deletes both and goes on with the card.
2. Otherwise mounts the first SD card device found (`mmcblk0` to `mmcblk2`) as vfat at `/mnt/sdcard`. It takes
   `fac_update_ota.tar` if present, else `cus_update_ota.tar`, extracts it to `/mnt/sdcard/update/` and runs
   `RK_OTA_update.sh` from there.
3. On success it removes `update/` and reboots. It removes `cus_update_ota.tar` first; a `fac_update_ota.tar` is
   not removed, instead recovery waits until the card's device node disappears (card pulled) and then reboots.
   The inittab shutdown runs `umount -a -r`, so the deletion reaches the card.
4. On a tar extraction error it exits and leaves the package and `update/`. The stock `RkLunch.sh` then sends the
   camera to recovery again on every boot, until the card is removed.
5. On a flash error it removes `update/` but leaves the package, so the next boot tries again.

So an official `cam-<version>.tar`, copied to the card as `cus_update_ota.tar`, is installed on the next boot. The
tasks in [Firmware update](../install/firmware-update.md) do that.

## Packages

The package URL follows the pattern `https://connect-ota.prusa3d.com/file/cam-<version>.tar`. Downloaded on
2026-11-10 (whole files; the server ignores `Range` requests):

| version | HTTP | size (bytes) | contents |
|---|---|---|---|
| 3.1.0 | 200 | 17469440 | `boot.img`, `oem.img`, `RK_OTA_update.sh` (size of `firmware_images/cam-3.1.0.tar`) |
| 3.1.3 | 200 | 19046400 | `boot.img`, `oem.img`, `RK_OTA_update.sh` (size of `firmware_images/cam-3.1.3.tar`) |
| 3.1.4 | 200 | 22190080 | not examined |
| 3.1.5 | 200 | 22579200 | not examined |
| 3.1.6 | 200 | 31232000 | `boot.img`, **`rootfs.img`**, `oem.img`, `RK_OTA_update.sh` |
| 3.1.7 | 404 production, 200 staging | 22978560 | `boot.img`, `oem.img`, `RK_OTA_update.sh`; no rootfs (2026-11-22) |

`firmware_images/cam-3.1.6.tar` has the SHA-1 that both servers announced on 2026-11-10.
`firmware_images/cam-3.1.7.tar` has the SHA-1 that staging announced on 2026-11-22; see
[3.1.6 → 3.1.7 differences](cam-3.1.7-diff.md).

The 3.1.1 and 3.1.2 packages in `firmware_images/` (17602560 bytes each) also contain only `boot.img` and
`oem.img`.

`RK_OTA_update.sh` is byte-identical in 3.1.0 and 3.1.6. It writes every partition from `/dev/block/by-name` that
has a matching `<name>.img` in the package, then erases `misc`. With 3.1.6 that means boot, rootfs and oem. No
package so far has a `userdata.img`, so `/userdata` (configuration, Prusa Connect token, the add-ons' files) is not
written by any of them.

The 3.1.6 `rootfs.img` (UBI) has the stock `/etc/hosts` (`localhost` and `Rockchip` only). Updating to 3.1.6
therefore removes a `connect-ota.prusa3d.com` line from `/etc/hosts`. Earlier packages leave it in place. 3.1.7
has no `rootfs.img`, so it keeps the rootfs of whatever was installed before.

## On the maintainer's camera

- Firmware 3.1.3; no `/mnt/sdcard/ota` file, so production would be used.
- `/etc/hosts` maps `connect-ota.prusa3d.com` to `127.0.0.1`, so the update check cannot reach the server and the
  camera does not see 3.1.6 [INFERENCE: from the hosts entry; no failed check was found in the logs]. Where the line
  came from is unknown. `uninstall.sh --hosts` removes it.
- The check timing in [When it updates](#when-it-updates) comes from the card's `lp_app` logs of this camera.
- Updating by hand without the server: put the package on the card as `cus_update_ota.tar` (see
  [The recovery system](#the-recovery-system), [`RkLunch.sh`](cam-3.1.3/oem/usr/bin/RkLunch.sh.md) and
  [Firmware update](../install/firmware-update.md)).

## Evidence

```text
$ strings -t x live-3.1.3/oem/usr/sbin/lp_app        (excerpt, upgrade service)
 3b22a1 X-Camera-Token
 3b22b0 X-Camera-Fingerprint
 3b22c5 X-Camera-FW-Version
 3b22d9 /api/niceboy/v1/camera
 3b22f0 301
 3b22f4 redirect host: %s path: %s
 3b230f last_version
 3b231c sha1sum
 3b2324 last_release_type
 3b2353 /mnt/sdcard/ota
 3b239a OTA=
 3b23ad prod
 3b23b2 dev
 3b23b6 OTA Stable version
 3b23c9 connect-ota.prusa3d.com
 3b23e1 unstable
 3b23ea stage
 3b23f0 custom
 3b23f7 OTA Unstable version
 3b240c connect-ota-staging.prusa3d.com
 3b2452 Custom OTA server
 3b2464 URL=

$ tar tvf firmware_images/cam-3.1.6.tar
-rw-r--r-- runner/runner  2914304 2026-09-10 14:01 boot.img
-rw-r--r-- runner/runner  8650752 2026-09-10 14:13 rootfs.img
-rw-r--r-- runner/runner 19660800 2026-09-10 14:12 oem.img
-rwxr-xr-x runner/runner      601 2026-09-10 13:59 RK_OTA_update.sh
$ sha1sum firmware_images/cam-3.1.6.tar
6fc0f0d540b50a3af5defab86947811b923bbfcd  firmware_images/cam-3.1.6.tar
```
