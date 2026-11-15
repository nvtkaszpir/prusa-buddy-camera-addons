# `RkLunch.sh`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/RkLunch.sh` |
| file type | `POSIX shell script, ASCII text executable` |
| size | `2569` |
| sha256 | `57a0c33f9a05b20c5bcf58b284e8f6a138f8ffafca204fdda31ec75a5ca528f2` |
| linked libraries | `n/a` |
| origin | Rockchip RV1106 SDK `RkLunch.sh` launcher, customised by the vendor (lp_app, OTA, voice prompts) |
| confidence | high |

## Summary

The main application boot launcher. `/etc/init.d/S21appinit start` runs it as `sh /oem/usr/bin/RkLunch.sh`. In order, it remounts the rootfs read-only, runs the OEM init scripts, enables core dumps and memory overcommit, loads kernel modules, plays the "upgrade successful" prompt, brings up Wi-Fi, checks the SD card for OTA packages and debug hooks, and finally starts the camera app `lp_app`.

## Usage

It takes no arguments. It is called by `/etc/init.d/S21appinit start`, which first sources `/etc/profile.d/RkEnv.sh` if that file exists (PATH/LD_LIBRARY_PATH). The script expects the commands `ifconfig`, `awk`, `simple_ao`, `upgrade_voice.sh`, `eth_monitor.sh` (located in `/oem/usr/sbin`) and `lp_app` (located in `/oem/usr/sbin`) to be on PATH.

The SD-card control files are:

| file on SD | effect |
|---|---|
| `/mnt/sdcard/cus_update_ota.tar` or `/mnt/sdcard/fac_update_ota.tar` | plays `upgrading.wav`, then `reboot recovery` |
| `/mnt/sdcard/lp_stop` | do not start lp_app at all |
| `/mnt/sdcard/lp_app.sh` | copied to `/tmp/lp_app.sh`, made executable and run instead of lp_app (runs as root, in the foreground) |
| `/mnt/sdcard/log2file` | start `lp_app --noshell --log2file /mnt/sdcard/log` |

## How it works

The top level runs `rcS`, then `ulimit -c unlimited`, then `echo 1 > /proc/sys/vm/overcommit_memory`, then `post_chk`. The two commented-out lines would have set `core_pattern` and the rkcif `is_use_dummybuf` flag.

`rcS()`:

1. `mount -o remount,ro /` makes the root filesystem read-only.
2. It loops over `/oem/usr/etc/init.d/S??*`. Dangling entries are skipped. `*.sh` files are sourced in a subshell with `set start`. Everything else is run as `$i start`. On this dump the only script there is `S10ntp`, which starts `ntpd`.

`network_init <iface>` (in this dump it is called only for `wlan0`; the `eth0` call is commented out. **The live camera differs**, see "Relevance on this camera"):

1. For `wlan0` it first waits 1 second.
2. It reads the current MAC from `ifconfig -a`.
3. If `/data/<iface>addr.txt` exists:
   - If the file is empty, it writes the current MAC into it.
   - If the file holds the current MAC, it prints `HWaddr cfg ok`.
   - Otherwise it brings the interface down and applies the stored MAC with `ifconfig <iface> hw ether <saved>`, which pins the MAC across boots.
4. If the file does not exist, it creates it with the current MAC.
5. It then runs `ifconfig <iface> up` and starts `eth_monitor.sh <iface> &` in the background.

`post_chk()`:

1. It waits up to 30 × 0.1 s for `/userdata` to appear in `mount`.
2. Kernel modules: if `/oem/usr/ko/insmod_ko.sh` exists, it is run with `sh` from inside `/oem/usr/ko`. Otherwise it falls back to `/ko/insmod_ko.sh`. On this dump the `/oem/usr/ko` one exists.
3. `upgrade_voice.sh &` plays the post-upgrade prompt once.
4. `network_init wlan0 &` runs in the background.
5. `rm /userdata/lp_app_product` removes a flag file, presumably a production/factory-mode marker [INFERENCE].
6. If `/mnt/sdcard/cus_update_ota.tar` or `/mnt/sdcard/fac_update_ota.tar` exists, it plays `/oem/usr/etc/upgrading.wav` (`simple_ao -i ... -v 50`, if the wav exists), prints `!!!!!!!!!!!enter recovery` and runs `reboot recovery`. The recovery system then applies the package [INFERENCE].
7. `rm -f /userdata/core*` deletes old core dumps. The `#telnetd` line is commented out.
8. The app launch picks the first matching branch:
   - `/mnt/sdcard/lp_stop` exists: print `stop start lp_app` and start nothing.
   - `/mnt/sdcard/lp_app.sh` exists: copy it to `/tmp`, `chmod +x` and run it in the foreground.
   - `/mnt/sdcard/log2file` exists: `lp_app --noshell --log2file /mnt/sdcard/log &`.
   - Otherwise: `lp_app --noshell &`.

There is no check that the SD card is actually mounted at `/mnt/sdcard` at this point. The script relies on an earlier init script having mounted it [INFERENCE].

## Interfaces touched

- Device nodes / sysfs / procfs: `/proc/sys/vm/overcommit_memory` (written as 1); network interface `wlan0` (MAC change, up).
- Files and paths read/written: `/oem/usr/etc/init.d/S??*`; `/data/wlan0addr.txt` (read/created); `/oem/usr/ko/insmod_ko.sh` or `/ko/insmod_ko.sh`; `/userdata/lp_app_product` (deleted); `/userdata/core*` (deleted); `/mnt/sdcard/{cus,fac}_update_ota.tar`, `lp_stop`, `lp_app.sh`, `log2file`, `log`; `/tmp/lp_app.sh`; `/oem/usr/etc/upgrading.wav`.
- Network: none directly. It brings up `wlan0` and starts `eth_monitor.sh`.
- Environment variables / config files: inherits PATH from `/etc/profile.d/RkEnv.sh`; `ulimit -c unlimited`.

## Relevance on this camera

**Live camera vs this dump:** on the running camera, all 61 other files in `/oem/usr/bin` are byte-identical to the dump (md5 compared over ssh). `RkLunch.sh` is the only one that differs: live md5 `454273d7e2c1ca7ba4e9de993736d273`, dump md5 `bbe1ec90c47318dd44c82623cf3a972b`. The only change is line 80, where the live script runs `network_init eth0&` uncommented, so the camera also sets up `eth0` at boot and applies `/data/eth0addr.txt` if that file exists. Everything else in this report matches the live script.

This is the central boot script and always runs. The SD-card hooks are the most useful interoperability entry points:

- `lp_app.sh` on the SD card gives root code execution at every boot, replacing the vendor app.
- `lp_stop` boots without the app, which leaves the camera devices free for the SDK test tools.
- `log2file` writes app logs to the SD card.
- Leaving an OTA tar on the card puts the device into recovery on every boot until the tar is removed or consumed [INFERENCE].

Side effects: remounts `/` read-only, may change the Wi-Fi MAC, reboots into recovery when an OTA tar is present, and deletes core dumps. The matching stop script `/oem/usr/bin/RkLunch-stop.sh` that S21appinit references is not present in this dump.

## Evidence

```
$ cat etc/init.d/S21appinit
	start) sh /oem/usr/bin/RkLunch.sh ;;
	stop)  sh /oem/usr/bin/RkLunch-stop.sh ;;
$ ls oem/usr/etc/init.d/   -> S10ntp
$ find . -name lp_app -o -name 'eth_monitor*' -o -name 'RkLunch-stop*'
./oem/usr/sbin/eth_monitor.sh
./oem/usr/sbin/lp_app
$ ls oem/usr/ko/insmod_ko.sh -> present; oem/usr/etc/upgrading.wav -> present
```

The script content is quoted in the sections above (full text read with `cat`).

## Open questions

- I did not determine the format and validation of `cus_update_ota.tar` / `fac_update_ota.tar`; the recovery image is not part of this input.
- The meaning of `/userdata/lp_app_product` is unknown and needs `lp_app` analysis.
- I did not establish which script mounts the SD card at `/mnt/sdcard`, or whether it is mounted before `post_chk` runs (race) [INFERENCE].
- `RkLunch-stop.sh` is missing, so `S21appinit stop` would fail.
