# OTA firmware updates

Where the camera looks for firmware updates, how it picks the server, what the server answers and what an update
package contains. Sources: the strings of the 3.1.0 `lp_app` (dump), of the live 3.1.3 `lp_app`
(`firmware_images/scard-content-old/live-3.1.3/oem/usr/sbin/lp_app`, md5 `ee845fa0b2e4a8cc0eaf5d7135b8f144`) and of
the 3.1.6 `lp_app` from the 3.1.6 package (md5 `6747721508ef6c5091009fdf5f69431f`), the packages in
`firmware_images/`, and requests to both update servers from a host on 2026-11-10. More on the update code is in
[`lp_app`](cam-3.1.3/oem/usr/sbin/lp_app.md#shutdown-reboot-and-ota).

## Summary

- There is no separate beta URL. The firmware knows two update servers: production and staging. Staging is
  labelled `OTA Unstable version` in the log strings.
- Update check: HTTPS GET `/api/niceboy/v1/camera` on `connect-ota.prusa3d.com` (production) or
  `connect-ota-staging.prusa3d.com` (staging).
- On 2026-11-10 both servers offered **3.1.6**, the same package (same SHA-1).
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
- Package on 2026-11-10: `https://<host>/file/cam-3.1.6.tar`

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

- **Periodic check.** The interval can change at run time (`Change request interval to %d seconds`); its default
  was not found.
- **Cloud command.** Prusa Connect can send `start_fw_update` (`Start upgrade FW now! Force upgrade`).
- **Daytime window.** 3.1.3 and 3.1.6 check the hour (`Current hour: %d`, `Within daytime upgrade interval`,
  `Outside daytime upgrade interval`). The window's hours were not traced.
- **Forced update after boot (3.1.6).** `First OTA check after boot. force_upgrade: %d` and
  `Force auto upgrade. ret: %d, force_upgrade: %d, isFirstOtaCheckAfterBoot: %d`: with `force_upgrade` true,
  the first check after a boot installs the update [INFERENCE: whether the daytime window applies].

The install steps are the same in all three builds: download to `/userdata/update_ota.tar`, check the SHA-1 (on a
mismatch the file is deleted and `ota_fw_download_failed` is reported), play `upgrading.wav`, write `boot-recovery`
to the misc partition `/dev/mtd3`, then `reboot recovery`. The recovery system runs `RK_OTA_update.sh` from the
package [INFERENCE: the recovery image was not examined].

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
| 3.1.7 | 404 | — | does not exist yet |

`firmware_images/cam-3.1.6.tar` has the SHA-1 that both servers announce.

The 3.1.1 and 3.1.2 packages in `firmware_images/` (17602560 bytes each) also contain only `boot.img` and
`oem.img`.

`RK_OTA_update.sh` is byte-identical in 3.1.0 and 3.1.6. It writes every partition from `/dev/block/by-name` that
has a matching `<name>.img` in the package, then erases `misc`. With 3.1.6 that means boot, rootfs and oem. No
package so far has a `userdata.img`, so `/userdata` (configuration, Prusa Connect token, the add-ons' files) is not
written by any of them.

The 3.1.6 `rootfs.img` (UBI) has the stock `/etc/hosts` (`localhost` and `Rockchip` only). Updating to 3.1.6
therefore removes a `connect-ota.prusa3d.com` line from `/etc/hosts`. Earlier packages leave it in place.

## On the maintainer's camera

- Firmware 3.1.3; no `/mnt/sdcard/ota` file, so production would be used.
- `/etc/hosts` maps `connect-ota.prusa3d.com` to `127.0.0.1`, so the update check cannot reach the server and the
  camera does not see 3.1.6 [INFERENCE: from the hosts entry; no failed check was found in the logs]. Where the line
  came from is unknown. `uninstall.sh --hosts` removes it.
- A search of the card's `lp_app` logs for update messages was killed on the camera (out of memory on the large log
  files), so nothing is known about earlier checks.
- Updating by hand without the server: `RkLunch.sh` reboots into recovery when `/mnt/sdcard/cus_update_ota.tar` or
  `fac_update_ota.tar` exists (see [`RkLunch.sh`](cam-3.1.3/oem/usr/bin/RkLunch.sh.md)). Whether recovery takes
  a downloaded `cam-<version>.tar` renamed to that name was not tested [INFERENCE].

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
