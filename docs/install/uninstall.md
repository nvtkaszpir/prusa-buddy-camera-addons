# Uninstall

How to remove the add-ons, and what they leave on the camera.

The script `buddy-addons/device/uninstall.sh` does the cleanup.

You can run it over ssh with `task buddy:uninstall`, or once from the microSD card when the camera has no ssh and no
telnet.

## What the add-ons leave on the camera

The camera's flash has these partitions (`mtdparts` on the kernel command line, `/etc/init.d/S20linkmount`):

| mtd | name | mounted at | written by an OTA update |
|---|---|---|---|
| 4 | boot | — | yes, `boot.img` |
| 6 | rootfs | `/` (ubifs, `ro`) | only by 3.1.6, `rootfs.img` |
| 7 | oem | `/oem` (ubifs, `rw`) | yes, `oem.img` |
| 8 | userdata | `/userdata`, also `/data` (ubifs, `rw`) | no |

The start scripts copy everything from `/mnt/sdcard/bin/` to `/userdata` only. None of them writes to boot, rootfs
or oem. Checked on the maintainer's camera (firmware 3.1.3) on 2026-11-08:

| Where | What | Written by |
|---|---|---|
| `/userdata/bin/` | `dropbearmulti` and its applet symlinks, `rsync`, `drill` | `start-sshd.sh` |
| `/userdata/bin/` | `lighttpd`, `mbedtls-gen-key`, `mbedtls-cert-write` (and `drill`) | `start-httpd.sh` |
| `/userdata/bin/` | `logrotate` | `start-logrotate.sh` |
| `/userdata/bin/` | `fsck.fat` (only with the microSD check hook) | `sdcard-fsck.sh` |
| `/userdata/bin/` | an old `start-sshd.sh` | no script; a manual install |
| `/userdata/ssh/` | `authorized_keys`, host key, `passwd` (bound over `/etc/passwd`) | `start-sshd.sh` |
| `/userdata/httpd/` | `lighttpd.conf`, `htpasswd`, listing header, TLS key and cert | `start-httpd.sh` |
| `/userdata/rsyslog/` | `bundle/` (rsyslogd, loader, libs, modules), `rsyslog.conf`, `work/` | `start-rsyslog.sh` |
| `/userdata/logrotate/` | `logrotate.conf`, `status` | `start-logrotate.sh` |
| `/userdata/xhr_config.ini` | `rtsp_server_mode=2` (RTSP on port 554, no password) | the card's `lp_app.sh` |
| `/tmp/` | `lp_app.sh`, `sync_loop.sh`, the two loop scripts, pid files, logs | hook, start scripts |

`/tmp` is RAM and is cleared on every reboot. The card's `lp_app.sh` also copies `/userdata/*` to
`/mnt/sdcard/userdata/current/`. Those copies include the Prusa Connect token (`xhr_http_token.conf`) and the
config with the Wi-Fi AP password. lighttpd does not serve that directory, but anyone holding the card can read it.

Without the card's `lp_app.sh`, nothing runs the files in `/userdata`. `RkLunch.sh` then starts `lp_app` directly.
Neither the firmware's `PATH` nor its init scripts point at `/userdata/bin`. The only init script that reads from
`/userdata` is `S99_auto_reboot`, which runs `/data/cfg/rockchip_test/*.sh`, and the add-ons never create that
directory. So once the hook is gone, the copies are inert files. The `rtsp_server_mode=2` setting is the exception:
it stays in effect.

### Firmware updates probably do not remove them

The OTA packages for 3.1.0 to 3.1.3 (`firmware_images/cam-3.1.*.tar`) each contain only `boot.img`, `oem.img`
and `RK_OTA_update.sh`. The 3.1.6 package also has a `rootfs.img`. The script writes each partition that has a
matching `.img` and then erases `misc`. No package so far has a `userdata.img`, so the add-on files in `/userdata`
should survive an update. This is read from the script; what the recovery system does around it was not checked
[INFERENCE]. See [OTA firmware updates](../findings/ota.md). Some feature pages say an update "may wipe"
`/userdata`. That is the cautious case: the start scripts copy everything again from the card.

### State of the firmware partitions

Compared against the 3.1.3 OTA images and a January 2026 file dump of the root filesystem
(`firmware_images/scard-content-old/3/dump/`):

- **boot**: the first 2914304 bytes of `/dev/mtd4` (the image size) match `boot.img`
  (md5 `026e1fce597c62a6aaceac4d5586dd3d`).
- **oem**: 743 of the 745 files in the extracted `oem.img` are byte-identical on the camera. The three differences
  come from stock behaviour or from logging in, not from the add-ons:
  - `/oem/.ash_history` is not in the image. `/etc/profile.d/RkEnv.sh` sets `HOME=/oem`, so every interactive
    telnet or ssh shell writes its history to the oem partition.
  - `/oem/usr/etc/upgrade_successful.wav` is gone. The stock `upgrade_voice.sh` plays it once after an update and
    then deletes it.
  - `/oem/usr/share/zoneinfo/uclibc/Etc/UTC` contains `UTC-1`. `/etc/TZ` is a symlink to that file, and `lp_app`
    writes the camera's time zone to `/etc/TZ`.
- **rootfs**: mounted read-only. Of the 88 files that could be compared with the dump (the dump lacks most of
  `/usr/bin`), three differ:
  - `/etc/passwd`: this is the bind mount from `/userdata/ssh/passwd`, which disappears on reboot.
  - `/etc/random-seed`: rewritten at boot.
  - `/etc/hosts` has an extra line, `127.0.0.1 connect-ota.prusa3d.com`, which blocks the camera's OTA update
    check. The January dump does not have it. No script in this repo writes `/etc/hosts`, and
    `/oem/.ash_history` shows no command for it. Where it came from is unknown. The 3.1.0 to 3.1.3 packages carry
    no rootfs image and leave the line in place. The 3.1.6 package rewrites the rootfs with a stock `/etc/hosts`,
    which removes it; the line also stops the camera from finding that update. `--hosts` below removes it by hand.

`webrtc_mode` in `/userdata/xhr_config.ini` was also changed by hand once: the shell history shows
`sed -i 's/webrtc_mode=.*/webrtc_mode=1/' /userdata/xhr_config.ini`. No script in this repo sets it, and the 3.1.3
`lp_app` reads it. On 2026-11-08 it was `0`. `uninstall.sh` does not touch it.

## What uninstall.sh does

```text
sh uninstall.sh [-n] [--stock] [--hosts]
```

Without options, it:

1. stops rsyslogd, the rsyslog waiter, the logrotate loop, lighttpd and its reverse-DNS job. It finds them by
   their command line in `/proc`, not through the pid files;
2. unmounts the bind mount on `/etc/passwd`;
3. deletes `/userdata/bin`, `/userdata/ssh`, `/userdata/httpd`, `/userdata/rsyslog` and `/userdata/logrotate`;
4. deletes the add-on files from `/mnt/sdcard/bin/` (binaries, start scripts, configs, `authorized_keys`,
   `htpasswd`, `rsyslog/`). If no other files are left, it deletes `bin/` too. With the start scripts gone, the
   hook blocks in `lp_app.sh` do nothing on the next boot;
5. stops the dropbear listener, as the last step. Open ssh sessions are separate processes and keep running.

Options:

- `--stock`: go back to the stock boot. Renames `/mnt/sdcard/lp_app.sh` to `lp_app.sh.bak-uninstall-<time>`, sets
  `rtsp_server_mode=1` (the factory default: RTSP off; turn it on again in Prusa Connect if you want it), deletes
  `/mnt/sdcard/userdata/` and deletes `/oem/.ash_history`. A running `lp_app` keeps its settings in memory and
  rewrites `xhr_config.ini` when a setting changes [INFERENCE], so reboot right away (`task buddy:uninstall`
  does) for the RTSP setting to stick. The card hook runs before `lp_app` starts.
- `--hosts`: deletes the `connect-ota.prusa3d.com` line from `/etc/hosts`, which turns the OTA update check back on.
  The script remounts `/` read-write for that and read-only afterwards. The file is rewritten in place, so its
  owner and mode stay the same.
- `-n`: dry run. It lists what it would stop, delete or change, and does nothing.

It logs to stdout and to `/mnt/sdcard/logs/uninstall.log` (except in a dry run), and exits 1 if any step failed.
It does not reboot.
It does not delete `lp_app` logs, timelapses, `sync_loop.sh` or `debug.log` on the card, and it never deletes
`/userdata/xhr_config.ini`, the token, or the `eth0addr.txt`/`wlan0addr.txt` MAC files.

## Remote: task buddy:uninstall

Needs a working ssh login (the [ssh](../features/ssh.md) feature). From the repo root, run a dry run first:

```sh
task buddy:uninstall -- -n --stock --hosts        # dry run: lists every step, changes nothing
task buddy:uninstall                              # remove the add-ons, keep the hook, reboot
task buddy:uninstall -- --stock                   # also back to the stock boot
task buddy:uninstall -- --stock --hosts           # also unblock the OTA update host
task buddy:uninstall CAMERA_HOST=192.0.2.20 -- --stock
```

The task copies `buddy-addons/device/uninstall.sh` and `safe-reboot.sh` to `/tmp` on the camera, then, in one ssh
session, runs `uninstall.sh` with your options and then `safe-reboot.sh`, which stops `lp_app`, unmounts the card
cleanly and reboots (see [Rebooting](3-installation.md#rebooting)). With `-n` both only list what they would do.
The scripts are copied first because `sh -s` would read them from the ssh channel while they run, and the
cleanup deletes the card copies. One session is needed because the cleanup stops the dropbear listener.

!!! warning "ssh is gone afterwards"
    After the reboot there is no ssh: dropbear and its keys are deleted. Telnet comes back only if your hook
    still starts `telnetd`. For later access, see [Installation](3-installation.md).

Without `--stock`, your `lp_app.sh` stays and keeps running on every boot. Its add-on blocks find no start script
and do nothing, but everything else in it still runs: for example the `rtsp_server_mode=2` edit, the copy of
`/userdata` to the card, `telnetd` and `sync_loop.sh`.

## From the microSD card, without ssh or telnet

Use this when you cannot log in to the camera. You prepare a one-shot boot hook on the card in the host's card
reader. On the next boot it runs `uninstall.sh --stock` and then starts `lp_app` the way the stock boot does.
`--stock` renames the one-shot hook too, so it runs only once and every boot after that is stock.

Put the card in the host's card reader and mount it. From the repo root:

```sh
ADDONS=$PWD/buddy-addons
cd /path/to/mounted/sdcard                        # e.g. /run/media/$USER/SDCARD
[ -f lp_app.sh ] && cp lp_app.sh lp_app.sh.bak-pre-uninstall
cp "$ADDONS/device/uninstall.sh" uninstall.sh
mkdir -p logs
cat > lp_app.sh <<'EOF'
#!/bin/sh
# One-shot uninstall hook: remove the add-ons, then start lp_app as the stock boot does.
# uninstall.sh --stock renames this file, so the next boot is stock.
sh /mnt/sdcard/uninstall.sh --stock
lp_app --noshell &
EOF
sync
cd -                                              # umount fails while the shell is still on the card
umount /path/to/mounted/sdcard
```

Add `--hosts` to the `uninstall.sh` line to unblock the OTA update host as well.

Put the card in the camera and power-cycle it. Give it a minute: there is no feedback on the camera itself. When
the camera shows up in Prusa Connect again, the hook has finished. Then power it off, put the card back in the
reader and check:

```sh
cd /path/to/mounted/sdcard
cat logs/uninstall.log                            # every step, ending with "done"
ls                                                # lp_app.sh.bak-uninstall-<time> instead of lp_app.sh
rm uninstall.sh                                   # optional: no longer needed
```

`uninstall.sh` deletes the add-on files in `bin/` from the camera side. You can also delete them on the host first.
If `logs/uninstall.log` is missing, the hook did not run: check that the file is named `lp_app.sh` in the card's
root and that no `lp_stop` file is there. `RkLunch.sh` skips the hook when `lp_stop` exists.

## Checks after uninstall

With ssh gone, check from the network and from the card:

```sh
nc -zv CAMERA_IP 22 8080 8443 554                 # all refused (554 stays open if RTSP is on)
cat /path/to/mounted/sdcard/logs/uninstall.log
```

A remote syslog server stops receiving messages from the camera. If you still have a shell on the camera, e.g.
because your hook keeps `telnetd`:

```sh
ls /userdata                                      # only xhr_config.ini, xhr_http_token.conf, *addr.txt
grep -E 'rtsp_server_mode|webrtc_mode' /userdata/xhr_config.ini
grep connect-ota /etc/hosts                       # no output after --hosts
grep ' /etc/passwd ' /proc/mounts                 # no output
```

## Source files

- `buddy-addons/device/uninstall.sh`: the cleanup script.
- `Taskfile.yml`: task `buddy:uninstall`.
