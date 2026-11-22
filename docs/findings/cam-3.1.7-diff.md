# Firmware 3.1.6 → 3.1.7 differences

What changed in camera firmware 3.1.7 compared with 3.1.6, and what that means for the add-ons. Method: static
analysis of both packages (`strings`, `readelf`, `llvm-objdump`, structural JSON diff, FIT/DTB parsing). No
binary was executed and 3.1.7 was not installed on a camera. Claims not directly backed by evidence are marked
**[INFERENCE]**.

## Where 3.1.7 came from

Checked on 2026-11-22, `GET /api/niceboy/v1/camera` on both servers:

| server | `last_version` | `sha1sum` | `force_upgrade` |
|---|---|---|---|
| `connect-ota.prusa3d.com` (production) | 3.1.6 | `6fc0f0d540b50a3af5defab86947811b923bbfcd` | false |
| `connect-ota-staging.prusa3d.com` (staging) | **3.1.7** | `219e700df177b6ba19d483cf0cc4dadd88c7efb7` | false |

- The answer was the same with and without `X-Camera-FW-Version: 3.1.6`. `last_release_type` is still missing.
- `/file/cam-3.1.7.tar` exists only on staging. `cam-3.1.8` to `3.1.10`, `3.2.0`, `3.2.1` and `4.0.0` return 404
  on both servers.
- `firmware_images/cam-3.1.7.tar`: 22978560 bytes, SHA-1 matches the staging answer.

```text
$ tar tvf firmware_images/cam-3.1.7.tar
-rw-r--r-- runner/runner  2914816 2026-11-19 14:41 boot.img
-rw-r--r-- runner/runner 20054016 2026-11-19 14:53 oem.img
-rwxr-xr-x runner/runner      601 2026-11-19 14:40 RK_OTA_update.sh
```

Unpacking: `tar xf`, then `uvx --from ubi_reader ubireader_extract_files -o <dir> oem.img` (without `-k`, which
fails on ownership as a normal user). The trees are in `firmware_images/cam-3.1.7/oem/` and
`firmware_images/cam-3.1.6/{oem,rootfs}/`.

## Summary

| part | change |
|---|---|
| package | **no `rootfs.img`**; only `boot` and `oem` are rewritten. `RK_OTA_update.sh` byte-identical |
| `boot.img` | rebuild only: same kernel code and config, identical device tree |
| `RkLunch.sh` | new step: unpack `/mnt/sdcard/local_cfg.tar` into the card root. Boot hooks unchanged |
| `ethernet_{success,failed}.wav` | new voice prompts, played by `lp_app` |
| `8188fu.ko` | rebuild only (build-id and build date) |
| `jx_f37p_AXF37AA_SR2012A.json` | lens distortion correction on, level 128 |
| `lp_app` | +530 KB; server config file, snapshot endpoint, mDNS, ntpd, Ethernet, Modbus, RTSP, timelapse |

`diff -rq cam-3.1.6/oem cam-3.1.7/oem` lists exactly `RkLunch.sh`, the two new WAV files, `8188fu.ko`, `lp_app`
and the IQ JSON file. The other 749 files are identical.

## Package and rootfs

- `RK_OTA_update.sh` writes only partitions that have a matching `<name>.img`, so 3.1.7 rewrites `boot` and
  `oem`. The installed rootfs stays: the 3.1.6 one on a camera updated from 3.1.6.
- A camera that skips 3.1.6 keeps its older rootfs together with the 3.1.7 `boot` and `oem` [INFERENCE: that
  combination was not checked].
- `/etc/hosts` is not touched by 3.1.7. A `connect-ota.prusa3d.com` line added after 3.1.6 survives the update,
  and `uninstall.sh --hosts` still works. A camera with such a line does not see 3.1.7 through the update check.

## `boot.img`

The decompressed kernels differ in 61 bytes, all build metadata: host name (`runnervmlun5p` → `runnervm8axu0`),
build date, GNU build-id and the timestamps in the built-in empty initramfs. The device tree is byte-identical
(sha256 `aeb7f69d…cbb1994f61`), and so are the three entries of the resource image (`rk-kernel.dtb`,
`logo.bmp`, `logo_kernel.bmp`).

| | 3.1.6 | 3.1.7 |
|---|---|---|
| size | 2914304 | 2914816 |
| md5 | `9e1a2331bad8682fbc4adaa4b31272b7` | `3dc05dc7159c8d78ec77599c463ddc17` |
| FIT timestamp | 2026-09-10 12:01:14 UTC | 2026-11-19 13:41:53 UTC |
| kernel (zImage, XZ) | 2802416 B | 2803096 B |
| decompressed kernel | 6068416 B | 6068416 B |

```text
3.1.6: Linux version 5.10.110 (runner@runnervmlun5p) (arm-rockchip830-linux-uclibcgnueabihf-gcc
       (crosstool-NG 1.24.0) 8.3.0, GNU ld (crosstool-NG 1.24.0) 2.32) #1 Thu Sep 10 11:49:54 UTC 2026
3.1.7: Linux version 5.10.110 (runner@runnervm8axu0) (arm-rockchip830-linux-uclibcgnueabihf-gcc
       (crosstool-NG 1.24.0) 8.3.0, GNU ld (crosstool-NG 1.24.0) 2.32) #1 Thu Nov 19 13:29:41 UTC 2026
```

- The file is 512 bytes bigger because the XZ kernel compressed 680 bytes larger, which pushed the resource image
  to the next 512-byte boundary.
- Module vermagic `5.10.110 mod_unload ARMv7 thumb2 p2v8` is unchanged.
- Boot arguments, the 24 MB video memory (`rk_dma_heap_cma=24M`), the SD controller, USB and Ethernet nodes are
  unchanged.
- Neither kernel embeds its config (no `IKCFG_ST`).
- The FIT `signature` node (`sha256,rsa2048`, key hint `dev`) has no `value` in either version, so the images
  are unsigned.

## `RkLunch.sh`

md5 `454273d7e2c1ca7ba4e9de993736d273` → `60ffd3649e2607b9e3e701805b6bce9d`. The only hunk, in `post_chk`:

```diff
@@ -91,7 +91,20 @@
 	fi
 	#telnetd
 	rm -f /userdata/core*
-	
+
+	# local cfg package (srv_cfg.txt, self-signed.pem, sdcard_cfg.txt, ...) extracted to the SD card root
+	LOCAL_CFG_PACKAGE=/mnt/sdcard/local_cfg.tar
+	if [ -f $LOCAL_CFG_PACKAGE ]; then
+		if tar -xvf $LOCAL_CFG_PACKAGE -C /mnt/sdcard; then
+			rm -f $LOCAL_CFG_PACKAGE
+			echo "local_cfg.tar extracted"
+		else
+			mv -f $LOCAL_CFG_PACKAGE /mnt/sdcard/local_cfg_failed.tar
+			echo "local_cfg.tar extract failed"
+		fi
+		sync
+	fi
+
 	if [ -f "/mnt/sdcard/lp_stop" ]; then
 	        echo "stop start lp_app"
 	elif [ -f "/mnt/sdcard/lp_app.sh" ]; then
```

- The step runs after the `cus_update_ota.tar` / `fac_update_ota.tar` check and before the hook is chosen.
- Unchanged: `lp_stop`, `lp_app.sh` (copied to `/tmp/lp_app.sh` and run), `log2file`, `network_init eth0` and
  `wlan0` with `eth_monitor.sh`, the kernel modules and `upgrade_voice.sh`.
- The files named in the comment match new `lp_app` strings: `/mnt/sdcard/srv_cfg.txt` @0x414351 and
  `/mnt/sdcard/self-signed.pem` @0x4430eb. `sdcard_cfg.txt` already existed in 3.1.6.

## Voice prompts

| file | size | md5 | format |
|---|---|---|---|
| `ethernet_success.wav` | 70296 | `4c42bebd0f4905289d453537a52fa1d6` | PCM s16 mono 16 kHz, 2.194 s |
| `ethernet_failed.wav` | 70296 | `f1d6f7409db6004cceffe369e69a548b` | PCM s16 mono 16 kHz, 2.194 s |

Made with a newer FFmpeg (`Lavf62.12.101`; the other prompts have `Lavf61.7.100`). Only the 3.1.7 `lp_app`
names them, next to the Wi-Fi prompts:

```text
41b82c /oem/usr/etc/ethernet_success.wav
425265 /oem/usr/etc/ethernet_failed.wav
```

## `8188fu.ko`

Same size (1512932 B). `cmp -l` finds 27 differing bytes: the 20-byte GNU build-id and the build time
(`Sep 10 2026 12:11:09` → `Nov 19 2026 13:51:49`). `.modinfo` is identical:
`version=v5.11.5.2-2-g57aeb1afd.20220114_beta`, `srcversion=873CF7A47E660C77A1E2C1F`, 51 parameters. No
functional change.

## Camera tuning (`jx_f37p_AXF37AA_SR2012A.json`)

Exactly four values changed, in `main_scene[0]` (`normal`), sub-scenes `day` and `gray` (night):

| JSON path | 3.1.6 | 3.1.7 |
|---|---|---|
| `.main_scene[0].sub_scene[0].scene_isp32.aldch.param.ldch_en` | 0 | 1 |
| `.main_scene[0].sub_scene[0].scene_isp32.aldch.param.correct_level` | 255 | 128 |
| `.main_scene[0].sub_scene[1].scene_isp32.aldch.param.ldch_en` | 0 | 1 |
| `.main_scene[0].sub_scene[1].scene_isp32.aldch.param.correct_level` | 255 | 128 |

- This turns on the ISP's lens distortion correction (LDCH) at half strength. `lp_app` 3.1.7 also enables it in
  code (`rk_aiq_uapi2_setLdchEn(ctx, 1)`, `setLdchCorrectLevel(ctx, 128)`).
- The mesh file name and light centre still refer to an os04a10 2688×1520 module, so the calibration was copied
  from another sensor; only the switch and level changed.
- It is the only tuning file shipped, so production cameras use the SOI JX-F37P sensor [INFERENCE: confirm with
  the `sensor_name is` line in the `lp_app` log]. Snapshot and timelapse framing changes.

## `lp_app`

| | 3.1.6 | 3.1.7 |
|---|---|---|
| size | 4881652 | 5412228 |
| md5 | `6747721508ef6c5091009fdf5f69431f` | `dffe6bd4fa7f6f09f433ad84e63b2276` |
| version string | `3.1.6` @0x3c699c | `3.1.7` @0x413a54 |
| functions (`.ARM.exidx`) | 4238 | 5655 |
| `.data` / `.bss` | 0x409c / 0xa554 | 0x88dc / 0xc5f4 |

- Same linked libraries, compiler (crosstool-NG GCC 8.3.0) and `Build: PROD` tag. No build date or commit id;
  `2026.08.25` is the version of the bundled live555 library.
- New imports: `mount`, `umount2`, `kill`, `RK_MPI_RGN_*`, `rk_aiq_uapi2_setLdch*`, `mallinfo`, `sigtimedwait`
  (replaces `sigwait`), `inet_addr`. Removed: `htonl`, `htons`, `ntohs`.
- Strings (`-n 6`, unique): 3287 added, 305 removed. Most of the bulk is bundled libraries: about 690 live555
  strings, 1720 libexif strings and 310 MP3 table lines, plus about 100 strings of C++ symbol churn.

Code addresses below are in the 3.1.7 binary. All items were confirmed in the disassembly unless marked.

### Server config file `/mnt/sdcard/srv_cfg.txt`

- Keys (table at 0x43b2ec): `OTA_SRV`, `OTA_URL`, `IMG_SRV`, `IMG_URL`, `SIO_SRV`, `SIO_URL`, `SYSLOG_IP`,
  `SYSLOG_PORT`, `NTP_SERVER`. Unknown keys are logged and ignored.
- Format: `KEY=value` lines, `#` comments, whitespace trimmed, the last duplicate wins. The file is re-read on
  every lookup.
- `<X>_SRV` values (case-insensitive): `prod`/`stable` → production, `dev`/`unstable`/`stage` → staging,
  `custom` → the matching `<X>_URL`.
- It takes priority over the old `/mnt/sdcard/ota`, `imgsrv`, `siosrv` and `syslog_srv` files, which still work
  when the key is missing.
- Any OTA host other than `connect-ota.prusa3d.com` forces a 300 s check interval
  (`Using OTA server from %s: %s`).
- `SYSLOG_IP` must be IPv4 or a `*.local` name; `SYSLOG_PORT` defaults to 514. Whether it uses UDP or TCP was not
  traced.
- `NTP_SERVER` is limited to 1–253 characters from `[A-Za-z0-9.-]`, not starting with `-`.

### Snapshot endpoint moved

| | 3.1.6 | 3.1.7 |
|---|---|---|
| production host | `connect.prusa3d.com` | `camera-service.prusa3d.com` |
| staging host | `dev.connect.prusa3d.com` | `camera-service-dev.prusa3d.dev` |
| snapshot | `PUT /c/snapshot` | `PUT /v1/snapshot`, new header `Trigger` |
| camera info | `PUT /c/info` | `PUT /v1/camera-info` |

- A snapshot can carry the print-head position (`Trigger info: %s. Position: %f,%f,%f`), set over Modbus.
- Camera info gains a `device` block (`type`, `manufacturer`, `model`, `firmware_version`, `hardware_version`,
  `protobuf_version`), `config.rotation` and `config.network_info.lan_ipv4` / `lan_mac`. It loses `config.path`,
  `config.model`, `config.firmware`, `options.available_resolutions` and `capabilities`.
- Protobuf version string `4.4` → `4.6`.

### mDNS resolver and `/etc/hosts` bind mount

- Starts only if `IMG_URL`, `SIO_URL`, `OTA_URL`, `NTP_SERVER` or `SYSLOG_IP` in `srv_cfg.txt` is a `*.local`
  name. Otherwise it logs `mDNS hosts: no *.local name in %s, service not started`.
- When it runs: `umount2("/etc/hosts", MNT_DETACH)`, copies the real `/etc/hosts`, adds
  `# mDNS names from /mnt/sdcard/srv_cfg.txt, generated by lp_app` and the resolved names to `/tmp/hosts`, then
  `mount("/tmp/hosts", "/etc/hosts", MS_BIND)`.
- Queries go to 224.0.0.251:5353 from an ephemeral port; nothing listens on 5353. Refresh about every 600 s.
- The mount is left in place when `lp_app` exits.

### `lp_app` manages ntpd

Only when `NTP_SERVER` is set:

1. Writes `/tmp/ntp.conf`: `server <NTP_SERVER> iburst prefer` followed by the default `/oem/usr/etc/ntp.conf`.
   The code checks for a `prefer` token, so it probably strips it from the default lines [INFERENCE].
2. If the config changed, sends SIGTERM to the PID in `/var/run/ntpd.pid`, then SIGKILL if it does not stop
   (`NTP: ntpd (pid %d) did not stop, killing it`), and removes the pid file.
3. `system("ntpd -g -p /var/run/ntpd.pid -c /tmp/ntp.conf")`; on failure it falls back to the default config.

ntpd is the only process `lp_app` kills: `stopNtpd` is the only caller of `kill()`.

### Ethernet

- New hardware ID `NB.1.1.2` → `Buddy3D-ETH` (`NB.1.1.1` → `Buddy3D-POE` already existed).
- Waits up to 2000 ms for `wlan0` (3.1.6 checked once). Without it, watches `eth0` carrier and IPv4 address and
  sends the same "connected" event as Wi-Fi, so cloud services, OTA and time sync start over Ethernet.
- Plays `ethernet_success.wav` on connect and `ethernet_failed.wav` on timeout.
- `system_dump.txt` gains `ETH:`, `ETH IP:` and `ETH MAC:`.

### Modbus RTU on the printer serial port

- New class `CameraModbusSlave` on `/dev/ttyS4`, shared with the AT commands: frames starting with `A` are AT,
  anything else is Modbus RTU. Function codes 03 (read) and 16 (write), registers 0x8010–0x809C and
  0x9010–0x9017.
- Read registers include `RR_Token`, `RR_FingerPrint`, `RR_Ssid`, `RR_FwVersion`, `RR_SerialNum`, Wi-Fi and
  Ethernet status/IP/MAC, SD card status and space, and timelapse state.
- Write registers include `WR_Ssid`, `WR_Password`, `WR_Token`, `WR_WiFiConnect`, `WR_Reboot`, `WR_Upgrade`
  (`triggering firmware update`), RTSP/WebRTC mode, `WR_PrintingStatus`, `WR_TriggerAi` and timelapse control.
- No authentication is visible [INFERENCE]. Slave address, baud rate and the full register map were not
  resolved.
- AT interface: the `WIFIPWD` value is now masked in the log.

### RTSP server: `rtsp_demo` → live555

- Removed: the Rockchip `rtsp_demo` code and the client count via
  `netstat -an 2>/dev/null | grep ':%d' | grep ESTABLISHED | wc -l`.
- Added: live555 `2026.08.25`, still TCP 554, stream `live`, 65 s client timeout. No RTSP-over-HTTP port.
- New optional Digest authentication: `config.rtsp_auth` (default 0), realm `PrusaCam`, credentials from
  `auth.username` / `auth.pwd`, default `admin` / `admin`. Settable by QR code and from the cloud.
- `rtsp://<ip>:554/live/0`, which the old prefix matching accepted, probably fails now [INFERENCE].

### Timelapse

- New `config.timelapse_mode`: OFF, `TIME`, `TRIGGER`, `CHANGE_Z`; invalid values fall back to TIME. Set from
  the cloud, by QR (`time`, `trigger`, `changez`) or over Modbus.
- Printer state drives video assembly (`Timelapse service disabled (print %s). Start making video file`).
- Frames go through two RAM buffers of 512000 bytes, about 1 MB extra while a timelapse runs.
- Folder layout unchanged (`/mnt/sdcard/timelapse/<job>/…`); the job folder is now created with the first photo.
- New QR keys: `timelapse`, `timelapse_interval` (minimum 1 s), `job_name`.

### Photos

- EXIF in every JPEG: `Make` = `Prusa`, `Model` = `Prusa Buddy3D Cam …`, timestamp, and a JSON block with
  `schema: "buddy-cam/1"`, `trigger_source`, `light_mode`, `privacy_masks`, `head_position_mm` and
  `lens_correction`.
- Privacy masks via `RK_MPI_RGN_*`; where the mask list comes from was not traced.
- On a failed JPEG grab: `get jpeg stream failed, reinitializing JPEG pipeline`, then the pipeline is rebuilt.

### Custom CA file `/mnt/sdcard/self-signed.pem`

If it exists as a regular file, it **replaces** `/oem/usr/etc/ca-bundle.pem` for every TLS connection: OTA
check and download, snapshot upload, camera info and socket.io. In 3.1.6 the bundle was always used.

### OTA logic

16 of the 17 functions of `upgrade_service/xhr_upgrade_service.cpp` have identical instruction counts. JSON
fields, daytime window, download to `/userdata/update_ota.tar` and `reboot recovery` are unchanged. Only the
server choice changed (`srv_cfg.txt`, above). New trigger: Modbus `WR_Upgrade`.

### Other

- A `Status:` log line every 60 s: uptime, load, RSS, heap, file descriptors, threads and system free memory.
- Fan: switches on at 65 °C as before, but now off only below 60 °C (3.1.6: below 65 °C).
- Fewer secrets in logs: QR payload, SD card config content and the AT Wi-Fi password. Still in clear text:
  `Set HTTP Token: %s`, `Fingerprint: %s, Token: %s` and the Wi-Fi password during QR setup.
- Removed: `GetWebRtcStatus` / `WebRtcStatus: %d`.

## Impact on the add-ons

- **Boot hook:** works unchanged. `RkLunch.sh` runs `/mnt/sdcard/lp_app.sh` from the same place, with the card
  mounted.
- **`local_cfg.tar`:** unpacked into the card root before `lp_app.sh` is copied, so a tar containing
  `lp_app.sh`, `lp_stop` or `bin/` would overwrite them on that boot [INFERENCE]. The add-ons never create it.
- **`self-signed.pem`:** a stray file with that name on the card replaces the certificates for Prusa Connect and
  OTA [INFERENCE: breaks them if certificates are verified]. `start-httpd.sh` uses `/userdata/httpd` and does not
  collide.
- **`/etc/hosts`:** while the mDNS bind mount is active (only with `*.local` names in `srv_cfg.txt`), edits such as
  `uninstall.sh --hosts` go to the tmpfs copy and are lost [INFERENCE].
- **Blocking OTA:** `OTA_SRV=custom` with an unreachable `OTA_URL` should block updates without touching
  `/etc/hosts`, at the cost of a 300 s check interval [INFERENCE].
- **ntpd and syslog:** with `NTP_SERVER` set, `lp_app` restarts ntpd (SIGKILL if needed). `SYSLOG_IP` overlaps
  with the rsyslog add-on. Nothing changes when the keys are unset.
- **Network:** no new listening ports. Firewall allowlists need `camera-service.prusa3d.com`.
- **Memory:** the bigger binary, live555 and the timelapse buffers leave less free RAM for lighttpd and rsync
  [INFERENCE]. The new `Status:` log line helps to watch it.
- **Card writes:** the new code deletes nothing on the card; its new file operations touch only `/tmp/*` and
  `/var/run/ntpd.pid`.
