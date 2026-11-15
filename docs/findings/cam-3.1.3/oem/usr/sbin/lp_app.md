# `lp_app`

| field | value |
|---|---|
| path on device | `/oem/usr/sbin/lp_app` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `3009660` (dump build 3.1.0; the live build 3.1.3 is 4765884 bytes, md5 `ee845fa0b2e4a8cc0eaf5d7135b8f144`, kept in the repo at `downlaods/live-3.1.3/oem/usr/sbin/lp_app`) |
| sha256 | `55699497814758ee5bdc2bac8de9edb6c0f5dca516da41b720c675f409647d94` (dump build) |
| linked libraries | `libZXing.so.1, librockit.so, librockchip_mpp.so.1, libaec_bf_process.so, librkaudio_detect.so, librga.so, librkaiq.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0, ld-uClibc.so.1` |
| origin | Vendor C++ application (Langpai/"XHR" platform, namespaces `NSLpTech::*`, reports `manufacturer` = `Niceboy`) extended with Prusa-specific modules (`Prusa*` classes). Built with `GCC: (crosstool-NG 1.24.0) 8.3.0`. Statically links OpenSSL 1.1.1v, asio, Simple-Web-Server (HTTPS client), WebSocket++ 0.8.2, socket.io-client-cpp, nlohmann::json 3.11.3, nanopb, mINI, a ZLToolKit-derived logger and the Rockchip SDK `rtsp_demo` RTSP server |
| confidence | high (structure, config, endpoints, pipeline); medium where marked |

## Summary

`lp_app` is the production camera application of the Prusa Buddy3D camera. It is the only long-running vendor process: it drives the sensor/ISP/encoder pipeline (Rockchip rockit + rkaiq), uploads JPEG snapshots to Prusa Connect, keeps a socket.io control channel to `camera-signaling.prusa3d.com`, serves an unauthenticated RTSP H.264 stream on TCP 554, handles QR-code Wi-Fi/token provisioning, the button, status LED, IR night mode, voice prompts, SD-card timelapse stills, and OTA firmware updates. This report documents the dump build (firmware 3.1.0, hard-coded version string `3.1.0`). The build running on the owner's camera (3.1.3) is covered in a separate subsection at the end of "How it works".

## Usage

The binary has no usage or help text, does not import `getopt`/`getopt_long`, and contains only two option strings:

```
--log2file
--ota
```

A hand-written parser (`0x20eb0`, cloned at `0x20f38`) scans `argv` for an exact match and takes the next argument as the value. Every other argument is ignored, and options can appear in any order.

| option | effect |
|---|---|
| `--log2file <dir>` | Adds a rotating file log channel in `<dir>` (see Logging) and sets the "log to file" flag that is reported to Prusa Connect. Ignored if no value follows. |
| `--ota <host>` | Sets the OTA server address (`"Set ota server address: %s"`). It is applied after `/mnt/sdcard/ota` is read, so it overrides that file. Value format: a host name like the built-in defaults [INFERENCE]. |
| `--noshell` | **Not recognised.** The string does not exist in either build, so the argument is silently ignored. `RkLunch.sh` and the owner's launcher still pass it (an SDK leftover [INFERENCE]). |

Typical invocations seen: `lp_app --noshell &` (RkLunch.sh), `lp_app --noshell --log2file /mnt/sdcard/log` (RkLunch.sh when `/mnt/sdcard/log2file` exists), and `lp_app --noshell --log2file /mnt/sdcard/logs` (live camera, via the owner's SD hook).

## How it works

Addresses are virtual addresses in the dump build. In the text/rodata segment VA = file offset + 0x10000. Source-file names come from `__FILE__` strings in log calls (for example `xhr_upload_service.cpp`, `prusa_rtsp.cpp`, `lp_rv1106_dev.cpp`). Modules communicate through a process-wide string-keyed event bus (`NS_ZToolKit::EventDispatcher`, two worker threads `NOTICECENTER_00/01`).

### Startup and command line

`_start` → `__uClibc_main(main=0x1df10)`. `main` does this, in order:

1. `signal(SIGPIPE, SIG_IGN)`.
2. Parses `--log2file`; adds `FileChannel` (max file size 64 MB) if given; always adds a `ConsoleChannel`; installs `AsyncLogWriter` (thread `async log`).
3. `PrusaCommunicationService::Instance()` → reads `/mnt/sdcard/siosrv`.
4. `XHRUpgradeService::Instance()` → reads `/mnt/sdcard/ota`; then `--ota` overrides it.
5. `XhrUploadService::Instance()` → reads `/mnt/sdcard/imgsrv`.
6. `XhrPlatformDeviceService::initDevice()` (once): fingerprint/OTP serial, config checks, hardware-version detection, `configDevice`, media pipeline (`LpRv1106Dev::init`), AO volume, event listeners (`play_voice`, `image_mode`, `light_control`, `XHR_BT_DOUBLE_CLICK`, `set_volume`, `reboot_device`); then IR hardware (GPIO 55, PWM), motor driver (GPIO 54, `/dev/spidev0.0` at 4 MHz), IR control timer, button module, Wi-Fi module.
7. Starts the upload service, QR recognition service, upgrade service, Prusa Connect communication (the socket.io connection itself starts only on `MEVENT_WIFI_CONNECTED` / `socketio_reconnect`), timelapse service, and `PrusaRTSP` (starts the server only if `rtsp_server_mode == 2`).
8. Registers a listener `lp_app_exit` → `pthread_kill(main, SIGQUIT)`; nothing in the 3.1.0 build emits that event.
9. Blocks SIGINT, SIGQUIT, SIGTERM and waits for them with `sigwait` (`0x20e5c`), then runs the shutdown sequence (see "Shutdown, reboot and OTA").

Threads are named only for `async log`, `config_thread` and `NOTICECENTER_%02lu`; all other `std::thread`s keep the comm name `lp_app`. librockit names its own workers (`vi-0`, `venc-0/1`, `ai-0..4`) and librkaiq its `xc:*` threads. The live process shows exactly this set (19 × `lp_app` plus the named ones) (live check).

Hardware variant: `ReadHwVersionFromCamera` (`0x5a8f8`) reads a 128-byte blob from `/sys/class/spi_master/spi2/spi2.0/version` (serial number + HW version) and maps it to `NB.1.0.0`/`NB.1.0.1` → `Buddy3D`, `NB.1.1.0` → `Buddy3D-C1`, else `NB.ES`. The variant selects the light-sensor type, the PWM chip (7 for "Board with UART", 8 otherwise) and, on old boards, unbinds UART4 (`ff4e0000.serial`). The exact SN ranges are in the media notes; the version→model mapping is high confidence from code, the physical meaning medium.

### Configuration (keys, defaults, file paths)

Files (paths hard-coded in the binary):

| path | content |
|---|---|
| `/data/xhr_config.ini` | main INI file (mINI format) |
| `/data/xhr_http_token.conf` | raw Prusa Connect camera token (mirror of `http.token`) |
| `/data/xhr_http_fingerprint.conf` | raw camera fingerprint (mirror of `http.fingerprint`) |

`/data` is a symlink to `userdata` on the live camera (live check), so `/data/xhr_config.ini` and `/userdata/xhr_config.ini` are the same file (UBIFS partition `mtd8`). This resolves the earlier open question in the static notes.

Each getter parses the INI value with `std::stoi`; on a parse error it logs `"… PARSE ERROR, USING DEFAULT"` and returns the default. At start-up each `check*Configuration` writes the default when the key is missing.

| INI key | default | meaning |
|---|---|---|
| `config.camera_name` | `Buddy3D Camera` | name reported to Prusa Connect |
| `config.ir_mode` | `3` | IR / night mode (table below) |
| `config.volume` | `40` | speaker volume %, valid 5–100 |
| `config.snapshot_upload_interval` | `10000` | milliseconds between cloud snapshot uploads |
| `config.rtsp_server_mode` | `1` | 1 = OFF, 2 = ON, 3 = TRIGGER |
| `config.video_quality` | `6` | H.264 resolution: 5 = SD, 6 = HD, 7 = FHD |
| `http.token` | empty | Prusa Connect camera token (secret; not reproduced) |
| `http.fingerprint` | `.conf` file, else generated (`use mac:` / `use randstr:` + md5), fallback `0000000001` | camera fingerprint (`X-Camera-Fingerprint`) |
| `wifi_ap.ssid`, `wifi_ap.pwd` | compiled-in factory network `LPVC` with a vendor default password (present, redacted) | despite the name, the **home Wi-Fi** the camera joins, as provisioned by QR code; password stored in plain text |

`rtsp_server_mode` mapping: the network notes guessed 0/1/2 = OFF/TRIGGER/AUTO from string order. The disassembly of `PrusaRTSP::startService` (`0x856d4` compares 2 → ON, 1 → OFF, 3 → TRIGGER) and the live behaviour (mode 2 → port 554 listening) both contradict that guess. This report uses the disassembly mapping.

`checkVideoQualityConfiguration` logs the wrong text `"RTSP SERVER MODE NOT SET! USING DEFAULT"` (a copy-paste bug).

Write-back: setters mark the file dirty; `config_thread` rewrites every dirty file every 2 s with `std::ofstream(path, out|trunc)` and the header `; auto-generated by mINI class {`. There is no temporary-file/rename step, so a power loss during a write can truncate the config [INFERENCE].

`loadDefault()` (`0x6b148`) is called only by the factory-reset routine (`0x6938c`): delete `/data/xhr_http_token.conf`, erase the in-memory INI, re-seed the fingerprint, set `wifi_ap` to the factory network, `ir_mode=3`, `volume=40`, `snapshot_upload_interval=10000`, `camera_name="Buddy3D Camera"`, `rtsp_server_mode=1`.

SD-card server-selection files: `/mnt/sdcard/ota` (`OTA=`), `/mnt/sdcard/imgsrv` (`IMAGE_SRV=`), `/mnt/sdcard/siosrv` (`SIO_SRV=`). `stable`/`prod` → production host; `dev`/`unstable`/`stage` → staging host; `custom` → host from a `URL=` line; missing file or anything else → production.

### Logging

- Channels: `ConsoleChannel` (always, all levels, ANSI-coloured, stdout [INFERENCE]) and `FileChannel` (only with `--log2file`). Output is asynchronous via the `async log` thread.
- Levels: T, D, I, W, E. Line format `YYYY-MM-DD HH:MM:SS.mmm <L> <exe>[<pid>-<thread>] <file>:<line> <func> | <message>`, e.g. `2026-01-14 01:14:06.964 I lp_app[289-lp_app] xhr_upload_service.cpp:210 do_upload | *************request upload image`.
- Files: `<dir>/YYYY-MM-DD_NN.log`, opened in append mode; missing directories are created with mode 0777. A new file starts on a day change or when the file exceeds 64 MB (checked at most every 60 s). Files older than 30 days are deleted, and at most 30 files are kept. lp_app has no default log directory.
- `isSdCardMounted()` clears the "log2file" flag when the card is missing. That flag only changes what is reported to Prusa Connect; the file channel stays attached [medium].
- **Secrets in logs.** With `--log2file`, these messages are written in clear text to the SD card when the matching code path runs: `Set HTTP Token: %s` (W), `token: %s!!! fingerprint: %s!!!` (I), `Fingerprint: %s, Token: %s` (D), and `mode: %d ssid: %s pwd: %s` (D, QR provisioning and factory reset). The setter for `wifi_ap` masks the password (`PWD: ********`), but the QR/factory-reset line does not.

### Video pipeline

`LpRv1106Dev::init` (`0x66e74`):

1. ISP: `setenv("HDR_MODE","0")`, `rk_aiq_uapi2_sysctl_enumStaticMetas(0)`, `rk_aiq_uapi2_sysctl_init(sensor, "/etc/iqfiles", …)`, `prepare` (linear mode), `start`.
2. `RK_MPI_SYS_Init`; VI device 0 enabled and bound to pipe 0.
3. VI channel 0 (JPEG, always 1920×1080) and VI channel 1 (H.264, from `video_quality`). Both channels have mirror and flip set (180° rotation) [medium].
4. VENC 0 = JPEG (bound to VI 0, fixed-QP [INFERENCE], Qfactor 90, 30→10 fps, one picture per request). VENC 1 = H.264 Baseline (bound to VI 1, CBR [INFERENCE], GOP 37, 25 fps, continuous).
5. Audio: `ai_init`, `ao_init` (see Audio).

H.264 bitrate is computed as W×H×25/14 (FHD 3 702 857, HD 1 645 714, SD 548 571). Rockit documents `u32BitRate` in kbit/s with a maximum of 200000, so these values look like they were meant as bit/s. The effective bitrate is unknown; the live build adds explicit kbps handling ([`rk_mpi_venc_test`](../bin/rk_mpi_venc_test.md)).

| `video_quality` | resolution | cloud protobuf value | log |
|---|---|---|---|
| 5 | 640×480 | 1 | `Set video quality to SD` |
| 6 (default) | 1280×720 | 2 | `Set video quality to HD` |
| 7 | 1920×1080 | 3 | `Set video quality to FHD` |
| other | 1920×1080 | 0 → `Invalid video quality` | — |

A change from the cloud rebuilds only VI channel 1 and VENC 1 (`change_vi_resolution`) and persists the value. JPEG snapshots stay 1920×1080.

Not used: VPSS (only stop/destroy calls on a group that is never created), RGA, TDE (dead strings), RGN/OSD (no timestamp overlay), `libsmartIr`, IVS/motion detection, rockiva/NPU.

### Snapshots and timelapse

Cloud snapshots (`XhrUploadService`):

- The upload thread ticks every 1 s and counts down `snapshot_upload_interval` (ms; default 10 s). At zero, or after a `get_snapshot` event, it calls `do_upload`.
- `do_upload` gets one JPEG (`get_jpeg_frame`, buffer 716 800 bytes, 100 ms timeout) and POSTs it over HTTPS to `<image server>/c/snapshot` with `Content-Type: image/jpg`. Uploading is skipped when no token is set (`token is empty`).
- Camera info goes to `/c/info` (JSON: `camera_id`, `firmware`, `manufacturer`, `trigger_scheme` `THIRTY_SEC`, resolutions, `network_info` with `wifi_mac`, `wifi_ipv4`, `wifi_ssid`).
- The cloud can set the interval in seconds (accepted 10–600), enable/disable uploads, and request a single snapshot.
- The SD log `2026-01-14_00.log` shows a cycle of about 11.3 s (`start_stream` → `get jpeg stream` → `request upload image` → `status: 200 OK`), consistent with 10 s plus latency.

Timelapse (`PrusaTimelapsService`), dump build: JPEG stills only, no video assembly.

- The cloud events `enable_timelaps`, `set_timelaps_interval` (seconds, default 10, no range check) and `set_printing_job_name` control it.
- Every second the run thread checks whether the interval has elapsed and the card is mounted, then writes `/mnt/sdcard/timelapse/<job>/timelapse_<YYYY-MM-DD HH_MM_SS_mmm>.jpg`. The name contains a space. The job folder name is sanitised: allowed characters are `A–Z a–z 0–9 - . _`; anything else becomes `_`.
- After more than 3 write failures, or with no card, the timelapse is disabled and `sd_card_failed` is sent to the cloud.
- A second thread (`runTimelapseFileCound`, misspelt in the binary) counts the photos.

### Audio and voice prompts

- Sound card `hw:0,0` (`platform-acodec-sound`).
- AI (microphone) is configured: 16 kHz stereo card, resampled to 8 kHz mono, with VQE from `/oem/usr/share/vqefiles/config_aivqe.json` (bf, fast_aec, aes, agc, anr). The captured audio is never read: there is no `RK_MPI_AI_GetFrame` import and RTSP is video-only. The microphone path is therefore initialised but unused in 3.1.0 [INFERENCE].
- AO (speaker): 16 kHz mono. The `voice_play_run` thread pops queued WAV paths and plays them in 1024-byte chunks with `RK_MPI_AO_SendFrame`. The 44-byte WAV header is not skipped and is played as PCM (a tiny click [INFERENCE]). See also [`simple_ao`](../bin/simple_ao.md).
- Volume: `config.volume` (5–100, default 40) is applied at boot and by the cloud `SpeakerVolume` command. AI volume is fixed at 100.

| prompt (`/oem/usr/etc/…`) | trigger in 3.1.0 |
|---|---|
| `upgrading.wav` | OTA upgrade starts |
| `wifi_success.wav` | first Wi-Fi connection |
| `wifi_failed.wav` | Wi-Fi connect timeout |
| `start_scanning.wav` / `stop_scanning.wav` | QR scan start / end |
| `di.wav` | QR payload accepted. Says "QR code scanned". |
| `invalid_qr_code.wav` | QR payload rejected (`wrong qr info`) |
| `factory_reset.wav` | 10 s button hold |
| `night_mode.wav` / `auto_night_mode.wav` / `day_mode.wav` | double click cycles IR mode |
| `volume_changed.wav` | volume changed from the cloud |
| `as.wav` | QR "easter eggs" (`code` 42 / `order` 66); logs "autodestruction" text but does nothing else. Says "Starting autodestruction system". |

Not referenced by 3.1.0: `application_exit.wav`, `pairing_error.wav`, `pairing_successful.wav`. The 3.1.3 build additionally uses `fw_update.wav`, `rtsp_enable.wav`, `rtsp_disable.wav`, `video_quality_sd/hd/fhd.wav`, `webrtc_enable.wav`, `webrtc_disable.wav`. These 9 are missing from the dump but **all 21 referenced prompts exist on the live camera** (live check), so the live `/oem/usr/etc` was updated beyond the dump. This resolves the diff note's "may fail silently" inference.

### IR / night mode and light sensor

| `ir_mode` | meaning | cloud "Camera mode" value | button double-click goes to |
|---|---|---|---|
| 1 | DAY: IR off, colour | 2 (`Camera mode: DAY`) | 2 (`night_mode.wav`) |
| 2 | NIGHT: IR on, black and white | 3 (`Camera mode: NIGHT`) | 3 (`auto_night_mode.wav`) |
| 3 (default) | AUTO: light-sensor driven | 1 (`Camera mode: AUTO`) | 1 (`day_mode.wav`) |

A timer fires every 2 s (`init_irled`, callback `0x5b5f8`):

- IR ON sequence: GPIO 55 = 1; PWM duty 8000 of period 10000 ns (80 %); SPI driver register 0x11 pulse (0x86, 200 ms, 0x06); `set_ie_mode(1)` (rkaiq AIE black-and-white).
- IR OFF sequence: GPIO 55 = 0; duty 0; SPI pulse (0x8A, 200 ms, 0x06); `set_ie_mode(0)`.
- In fixed modes 1 and 2 the full sequence is re-applied every 2 s. The SD log shows `IR mode OFF` / `ie mode: 0` 384 times.
- AUTO: reads the LDR through SAR-ADC channel 1 (`/sys/bus/iio/devices/iio:device0/in_voltage1_raw`) and converts the reading to kΩ (`vout = adc×1.8/1024`, `R = vout/(1.8−vout)×10`; type-1 sensors subtract a 0.41 V offset). Switching needs 5 consecutive samples (about 10 s) past the threshold:

| sensor type | IR on when R > | IR off when R < |
|---|---|---|
| 0 | 21 kΩ | 19 kΩ |
| 1 (`RLDR L27101`) | 25 kΩ | 23 kΩ |

The PWM is `/sys/class/pwm/pwmchip{7|8}/pwm0` (period 10000, enabled). On the owner's camera both `pwmchip7` and `pwmchip8` exist, but only `pwmchip7` has `pwm0` exported (`period=10000`, `duty_cycle=0`, `enable=1` in daytime with the IR LED off), so this unit uses `pwmchip7` and `pwmchip8` is unused (verified read-only on the live camera, 2026-10-31). The ADC is `iio:device0` with `name` = `ff3c0000.saradc`; `in_voltage1_raw` read 467 in daytime (channel 0 read 1023; channels 2/3 not readable). With the formula above this gives vout ≈ 0.821 V and R ≈ 8.4 kΩ for a type-0 sensor, below the 19 kΩ off threshold, which is consistent with IR off (verified read-only on the live camera, 2026-10-31). Whether GPIO 55 is the IR-LED enable or the IR-cut select, and what the SPI register 0x11 pulse drives (probably a bistable IR-cut through the motor driver's spare H-bridge [INFERENCE]), is medium/low confidence. These are not the pins used by the SDK tests [`rk_pwm_test`](../bin/rk_pwm_test.md) / [`rk_gpio_test`](../bin/rk_gpio_test.md). The `image_mode` listener exists, but nothing in 3.1.0 emits that event.

The motor driver (`/dev/spidev0.0`, GPIO 54 enable, 19-register init table, `motor_controll` event with `RotationX/Z`) is generic pan/tilt code from the OEM platform. The Core One L camera has no motors [INFERENCE]; the code still runs.

### Button and LED

The button is `/dev/input/event0` (`adc-keys`). The handler reacts to EV_KEY events only and ignores the key code.

| gesture | event | action |
|---|---|---|
| single click (no second click within 1 s) | `XHR_BT_CLICK` | start QR scan (about 21 s) |
| double click (second release < 1 s after the first) | `XHR_BT_DOUBLE_CLICK` | cycle IR mode 1→2→3→1 with a prompt |
| hold ≥ 10 s, then release | `XHR_BT_PRESS_10S` | **factory reset** (see below) |

Factory reset (`0x578d4`):

1. Plays `factory_reset.wav`.
2. Deletes `/data/xhr_http_token.conf`, clears the INI and runs `loadDefault()`. The camera token is lost and the Wi-Fi credentials revert to the compiled-in factory network.
3. Logs `mode: 2 ssid: … pwd: …` in clear text.
4. Dispatches `ME_WIFI_SET_WORK_PARAM`, then `ME_I_WIFI_GATE`.

What Wi-Fi mode 2 means is not resolved (see Open questions).

Status LED: GPIO 56, single LED. On the live camera `gpio56` is exported as output with value 1; `gpio54` (out, 1) and `gpio55` (out, 0) are exported as analysed, and `gpio34` and `gpio53` (both out, 1) are also exported, by a component not identified by the static analysis (verified read-only on the live camera, 2026-10-31).

| state | pattern | used when |
|---|---|---|
| 0 scanning | double blink (200 ms on/off/on, 1 s off) | QR scan, 20 s |
| 1 Wi-Fi disconnect | 200 ms toggle | no caller in 3.1.0 |
| 2 Wi-Fi connect | 1 s toggle | Wi-Fi connected |
| 3 normal | 3 s toggle | initial state, after a QR scan |

### Wi-Fi setup and QR provisioning

- **QR provisioning (the primary method).** After a click, VI channel 1 is switched to 640×480. Each luma frame is decoded with `ZXing::ReadBarcodes` (QR only); if that fails, the inverted image is tried. The QR code generated by Prusa Connect carries the Wi-Fi SSID, the Wi-Fi password and the camera token. `handler_qr_payload` checks the lengths (`Token is empty or too long`, …), stores the values (`setWifiApSsidPwd`, `setHttpToken`), dispatches `ME_WIFI_SET_WORK_PARAM`, and reconnects socket.io when the SSID or token changed. Afterwards the resolution is restored from `video_quality`.
- **Station mode.** `LpWifiAStaMode` runs [`wifi_setup.sh`](wifi_setup.sh.md) `sta nl80211 "<ssid>" "<pwd>"`. That script writes `/tmp/config/wpa_supplicant.conf`, starts `wpa_supplicant` and runs `udhcpc`. lp_app then polls `wpa_cli -p /var/run/wpa_supplicant -iwlan0 status` until `COMPLETED` (flag file `/var/run/wlan0_wpa_flag.pid`) and emits `MEVENT_WIFI_CONNECTED`, which starts the cloud connection.
- **AP mode.** `LpWifiApMode` can run `wifi_setup.sh ap nl80211 "<ssid>" "<pwd>" wpa <channel>`. It picks the channel with [`iwlist`](iwlist.md) `wlan0 scan/channel` and lists stations with [`iw`](iw.md) `dev wlan0 station dump > /tmp/sta`. The script then starts [`hostapd`](hostapd.md) and [`udhcpd`](udhcpd.md) (192.168.42.1/24). There is no local provisioning HTTP server, and the dump has no `/tmp/config/hostapd.conf`, so AP mode seems unused in practice [INFERENCE]. Wired networking ([`eth_monitor.sh`](eth_monitor.sh.md)) is not referenced by the 3.1.0 build.

### Cloud services (Prusa Connect, signaling, OTA)

All cloud traffic is outbound TLS. The port is not a string in the binary; TCP 443 is implied by `https://`/`wss://` and confirmed live: while lp_app ran, the only established outbound connection was one TLS connection to `172.66.162.100:443` (a Cloudflare address; which Prusa host it serves was not resolved), with no other outbound ports. DNS resolvers come from DHCP (verified read-only on the live camera, 2026-10-31).

| purpose | production host | staging host | protocol / path |
|---|---|---|---|
| control channel ("signaling") | `camera-signaling.prusa3d.com` | `camera-signaling-stage.prusa3d.com` | `wss://…/socket.io/?EIO=4&transport=websocket`, protobuf (nanopb) payloads |
| snapshots / camera info | `connect.prusa3d.com` [medium: the literal is tail-merged into `dev.connect.prusa3d.com`] | `dev.connect.prusa3d.com` | HTTPS POST `/c/snapshot`, `/c/info` |
| OTA | `connect-ota.prusa3d.com` | `connect-ota-staging.prusa3d.com` | HTTPS GET `/api/niceboy/v1/camera` (JSON `last_version`, `sha1sum`, `last_release_type`, redirect/download host and path) |

- **Authentication.** HTTP requests carry the headers `X-Camera-Token`, `X-Camera-Fingerprint` and `X-Camera-FW-Version` (high for OTA, medium for `/c/*`). On socket.io the camera sends a `camera_authentication` event with fingerprint and token.
- **Commands the cloud can send.** Reboot, start a firmware update, start/stop RTSP, set RTSP mode, video quality, IR mode, volume, upload interval, camera name, timelapse settings, rotation, and get snapshot.
- **What the camera reports.** A feature list (`IrMode`, `RtspStream`, `VideoQuality`, `McuTemp`, …), SD status, and the log-to-file flag and log level.
- **Reconnects.** The 3.1.0 build gives up after repeated failures (`WebSocket connection failed too many times. Stopping reconnect attempts.`).
- **TLS verification.** The OpenSSL verify APIs are present, but neither the dump nor the binary contains a CA bundle; whether certificates are verified is undetermined (low).
- **Not present in lp_app.** NTP, MQTT, UPnP, mDNS and ONVIF; WebRTC is also absent in 3.1.0.

### Local services (RTSP)

- **Server.** `PrusaRTSP` wraps the Rockchip `rtsp_demo` server on **TCP 554** with path **`/live`** (`rtsp://<camera-ip>:554/live`; `/live/0` also works because the path is prefix-matched, live check).
- **Stream.** H.264 only (`m=video 0 RTP/AVP 96`, `packetization-mode=1`). Transports are RTP over interleaved TCP or RTP/RTCP over UDP (dynamic local ports). Methods: OPTIONS, DESCRIBE, SETUP, PLAY, PAUSE, TEARDOWN.
- **No authentication.** The code parses an `Authorization:` header but implements no challenge. The live DESCRIBE without credentials returned `200 OK`, `Server: rtsp_demo`.
- **Frame source.** The send thread takes frames from VENC 1 (`get_h264_frame`, 358 400-byte buffer, 100 ms timeout).
- **Client counting.** Done by shelling out to `netstat -an | grep ':554' | grep ESTABLISHED | wc -l`.
- **Mode.** The server starts at boot only when `rtsp_server_mode == 2`; the cloud can start or stop it at runtime (`start_rtsp_server` / `stop_rtsp_server`).
- **No other listeners.** lp_app opens no HTTP server and no other listening socket. On the live camera ports 22 and 23 belong to the owner's dropbear/telnetd; `/tmp/UNIX.domain` belongs to librkaiq.

### SD card handling

- **Mounting.** lp_app never mounts the card. `isSdCardMounted()` counts it as mounted only if `/proc/mounts` lists `/mnt/sdcard`, `access()` succeeds, and `/sys/class/block/mmcblk1` or `mmcblk0` exists.
- **Write test.** Writes and reads back `/mnt/sdcard/.writetestfile` to decide RW or RO.
- **Free space.** Measured with `statvfs64`.
- **Files lp_app reads or writes on the card.** `ota`, `imgsrv`, `siosrv`, `timelapse/`, and the log directory given with `--log2file`. The files `lp_stop`, `lp_app.sh`, `log2file`, `cus_update_ota.tar` and `fac_update_ota.tar` are used by [`RkLunch.sh`](../bin/RkLunch.sh.md), not by lp_app.

### Shutdown, reboot and OTA

- **Signals.** On SIGINT/SIGQUIT/SIGTERM, `main` stops the services in order: device service, upload, QR, upgrade, socket.io, timelapse, RTSP. Each stop does an unconditional `join`, so a stuck thread hangs shutdown [INFERENCE]. Static destructors then tear down the media pipeline (VI/VENC/AI/AO, `RK_MPI_SYS_Exit`, rkaiq stop/deinit, `"deinit end!!!!!"`).
- **Other signals.** SIGPIPE is ignored. There is no handler for SIGSEGV or SIGABRT; core dumps are possible because RkLunch.sh sets `ulimit -c unlimited`.
- **No watchdog.** There is no `/dev/watchdog` use and no watchdog string in either build. If lp_app crashes, nothing restarts it.
- **Cloud `reboot_device`.** Logs `!!!!! CAMERA REBOOT !!!!!`, calls `sync()`, `sleep(1)`, then `reboot(RB_AUTOBOOT)`. Services are not stopped first.
- **OTA.** Periodic check against `/api/niceboy/v1/camera`, or on the cloud command `start_fw_update`. The update:
  1. downloads the package to `/userdata/update_ota.tar` and checks its SHA-1;
  2. plays `upgrading.wav`;
  3. writes `boot-recovery` to the misc partition `/dev/mtd3`;
  4. runs `system("reboot recovery")`.
- **Version.** The version is compiled in (`3.1.0`). [`fw_version.txt`](fw_version.txt.md) is not read by lp_app.

### Live build 3.1.3 differences

The camera currently runs a different binary from the dump: 4765884 bytes, md5 `ee845fa0b2e4a8cc0eaf5d7135b8f144`, sha256 `2cb654d3a970901aeff1284aa951a3903c4e59d0df9393ca833b0ac4a54edc18`. The differences below were derived from this file, kept in the repo at `downlaods/live-3.1.3/oem/usr/sbin/lp_app`. It was identified as 3.1.3 by matching `__LINE__` immediates against camera logs (high). `DT_NEEDED` is identical; the extra 1.7 MB is statically linked code.

- **WebRTC.** `prusa_webrtc.cpp` and `h264camerasource.cpp`, with static libdatachannel, libjuice, usrsctp and libsrtp2 2.7.0 (107 WebRTC/libdatachannel strings in the live build, 0 in the dump; live check). Default STUN servers are Google's; TURN servers come from the cloud. Signalling runs over the existing socket.io channel. The new key `config.webrtc_mode` is absent from the owner's INI, and the 3.1.3 log says `WebRTC server is disabled in configuration`. No extra listener was seen live.
- **Timelapse.** Builds MJPEG-in-AVI videos on the card (`mjpeg_maker.cpp`), keeps a `.timelapse_videos.csv` status file, uses per-day subfolders with a photo cap, and serves file lists to the cloud.
- **SD-card events.** `sd_card_failed` is replaced by `sd_card_mounted`, `sd_card_low_space`, `sd_card_ro` and `timelapse_sd_card_missing`.
- **Video.** Runtime resolution switching via `RK_MPI_VENC_Get/SetChnAttr`, explicit CBR bitrate in kbps, and an optional SD override file `/mnt/sdcard/video_cfg` (`ViCfg=`, `ViQuality=`). The live log starts H.264 at mode 7 (1080p).
- **Timezone.** New `SystemTimeManager` queries `timezone.prusa3d.com` and writes `/etc/TZ`.
- **System dump.** `/mnt/sdcard/system_dump.txt` (model, SN, MAC, SSID, BSSID, IP, uptime, temperature, IR/LDR, timezone).
- **OTA.** Daytime upgrade window, RC/final release-type comparison, and progress events. The hosts are unchanged.
- **socket.io.** Keeps reconnecting with backoff (the "Stopping reconnect attempts" strings were removed) and can resend the auth message.
- **Config.** Encryption helpers `do_encrypt`/`do_decrypt` (PKCS7); which fields they protect was not traced. The owner's live INI has no `http.fingerprint`, and there is no fingerprint `.conf` file, so fingerprint handling changed [INFERENCE].
- **Hardware IDs.** New ID `NB.1.1.1` → `Buddy3D-POE`.
- **Prompts.** 9 additional prompts, all present on the live camera.
- **QR codes.** New QR keys/validation (volume in QR code).

## Interfaces touched

- Device nodes / sysfs / procfs:
  - **GPIO and PWM.** `/sys/class/gpio/gpio54` (motor-driver enable), `gpio55` (IR on/off), `gpio56` (status LED), all exported and driven via sysfs; `/sys/class/pwm/pwmchip7` or `pwmchip8` `/pwm0` (IR PWM: `export`, `period`, `duty_cycle`, `enable`). Live check: `pwmchip7/pwm0` is the one in use (period 10000 ns, duty 0 in daytime), `pwmchip8` is unused; `gpio34` and `gpio53` are also exported (out, 1) by an unknown component (verified read-only on the live camera, 2026-10-31).
  - **Identity and sensors.** `/sys/class/spi_master/spi2/spi2.0/version` (serial number and HW version; binary content, not a readable text string, live check); `/sys/bus/iio/devices/iio:device0/in_voltage1_raw` (LDR on the SAR-ADC `ff3c0000.saradc`; 467 in daytime, live check); thermal sysfs (MCU temperature).
  - **Input and buses.** `/dev/input/event0` (adc-keys button); `/dev/spidev0.0` (motor/IR-cut driver, 4 MHz).
  - **Other kernel interfaces.** `/sys/bus/platform/devices/ff4e0000.serial/driver/unbind` (old boards); `/sys/class/block/mmcblk0`, `mmcblk1`; `/proc/mounts`, `/proc/modules`, `/proc/self/exe`; `/dev/mtd3` (misc, OTA); kernel module load/unload (`init_module`/`delete_module`/`modprobe`).
  - **Through librockit/librkaiq.** Sound card `hw:0,0`, ISP/VI/VENC devices, and the unix socket `/tmp/UNIX.domain`.
- Files and paths read/written:
  - **Config.** `/data/xhr_config.ini`, `/data/xhr_http_token.conf`, `/data/xhr_http_fingerprint.conf` (`/data` → `userdata`).
  - **Media assets.** `/etc/iqfiles/`, `/oem/usr/share/vqefiles/config_aivqe.json`, `/oem/usr/etc/*.wav`.
  - **SD card.** `/mnt/sdcard/{ota,imgsrv,siosrv}`, `/mnt/sdcard/.writetestfile`, `/mnt/sdcard/timelapse/…`, the `--log2file` directory (`YYYY-MM-DD_NN.log`).
  - **OTA.** `/userdata/update_ota.tar`.
  - **Wi-Fi state.** `/tmp/config/hostapd.conf`, `/tmp/config/wpa_supplicant.conf` (via `wifi_setup.sh`), `/tmp/sta`, `/tmp/wifi_sup_channels`, `/tmp/wifi_env_channel`, `/var/run/wlan0_wpa_flag.pid`.
  - **Live build only.** `/mnt/sdcard/video_cfg`, `/mnt/sdcard/system_dump.txt`, `/etc/TZ`, `.timelapse_videos.csv`.
  - **Commands run.** `wifi_setup.sh`, `wpa_cli`, `iw`, `iwlist`, `ifconfig wlan0 up`, `netstat -an`, `modprobe`/`rmmod`, `reboot recovery`.
- Network:
  - **Inbound.** TCP 554 RTSP `/live` (no authentication), plus per-session RTP/RTCP UDP.
  - **Outbound (TLS, TCP 443, confirmed live: one connection to a Cloudflare address `172.66.162.100:443`).** `camera-signaling.prusa3d.com` (socket.io/WSS), `connect.prusa3d.com` (`/c/snapshot`, `/c/info`), `connect-ota.prusa3d.com` (`/api/niceboy/v1/camera`) and the OTA download host from the response; staging variants and custom hosts via SD files or `--ota`; DNS (resolvers from DHCP).
  - **Live build only.** `timezone.prusa3d.com`, Google STUN servers (WebRTC, disabled by config).
- Environment variables / config files: sets `HDR_MODE=0` for librkaiq; reads `xhr_config.ini` keys listed above; SD selector files `ota`/`imgsrv`/`siosrv`; command line `--log2file`, `--ota`.

## Relevance on this camera

- **How it starts.** [`RkLunch.sh`](../bin/RkLunch.sh.md) (from `S21appinit`) runs `lp_app --noshell &`, or with `--log2file /mnt/sdcard/log` when `/mnt/sdcard/log2file` exists. When `/mnt/sdcard/lp_app.sh` exists, RkLunch runs that hook instead. On the owner's camera the hook (via `sync_loop.sh`) forces `rtsp_server_mode=2`, starts busybox telnetd, and runs `lp_app --noshell --log2file /mnt/sdcard/logs` (live check).
- **`--noshell` does nothing.** It is not a recognised option in either build and is silently ignored.
- **No watchdog or supervisor.** If lp_app crashes or is killed, video, cloud, button, LED and IR control all stop until a reboot. Stopping it cleanly with SIGTERM/SIGINT tears down the pipeline. Starting a second copy while one runs would conflict over the MPI/ISP devices and port 554 [INFERENCE].
- **Unauthenticated RTSP.** With `rtsp_server_mode=2`, anyone who can reach TCP 554 can watch `rtsp://<ip>:554/live` without a password. Keep the camera on an isolated IoT VLAN/SSID, or firewall 554 so only trusted hosts can reach it. Prusa Connect can also switch RTSP on or off remotely.
- **Credentials on the SD card.** With `--log2file`, token, fingerprint and Wi-Fi SSID/password lines can be written to the SD log in clear text (on token change, uploads with debug lines, QR provisioning, factory reset). Treat the card's `logs/` directory as sensitive, and remove `--log2file` when it is not needed. The token and the Wi-Fi password are also stored in plain text in `/userdata/xhr_config.ini` and `/data/xhr_http_token.conf` in 3.1.0. The live build adds encryption helpers, but their use was not verified.
- **Factory reset.** Holding the button for 10 s (then releasing) deletes the Connect token, resets all settings including `rtsp_server_mode=1` (RTSP off), and points Wi-Fi at the compiled-in factory network. The camera must then be re-provisioned with a QR code. The owner's SD hook re-forces RTSP mode 2 at the next boot.
- **Other practical notes.**
  - A JPEG goes to Prusa Connect every 10 s by default, together with SSID, LAN IP and MAC.
  - Blocking internet access stops snapshots, cloud control and OTA. Local RTSP keeps working in mode 2.
  - Files on the SD card (`ota`, `imgsrv`, `siosrv`) can redirect all cloud endpoints, so physical access to the card matters.
  - The IR sequence is re-applied every 2 s, which produces most of the log volume.
  - lp_app needs most of the RAM: about 124 MB VSZ, with about 6 MB free system-wide (live check).
  - [`dumpsys`](../bin/dumpsys.md) is a related diagnostic tool.

## Evidence

```
$ file downlaods/3/dump/oem/usr/sbin/lp_app
ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped
$ stat -c %s …/lp_app ; sha256sum …/lp_app
3009660
55699497814758ee5bdc2bac8de9edb6c0f5dca516da41b720c675f409647d94
$ readelf -d …/lp_app | grep NEEDED
 libZXing.so.1 librockit.so librockchip_mpp.so.1 libaec_bf_process.so librkaudio_detect.so
 librga.so librkaiq.so libstdc++.so.6 libgcc_s.so.1 libc.so.0 ld-uClibc.so.1
$ strings -n 4 -t x lp_app | grep -E -- '--log2file|--ota|noshell'
 241bec --log2file
 241bf7 --ota                      (no "noshell")
$ strings -t x lp_app | grep -E 'xhr_config.ini|xhr_http_'
 256f90 /data/xhr_http_fingerprint.conf
 2570d9 /data/xhr_http_token.conf
 2571b3 /data/xhr_config.ini
$ llvm-objdump -d … --start-address=0x6b148 --stop-address=0x6b298     (loadDefault)
 6b208: ldr r1,="LPVC" ; 6b214: ldr r1,=<default password, redacted>
 6b240: mov r1,#3 ; bl setIrMode ; 6b24c: mov r1,#40 ; bl setVolume
 6b258: movw r1,#10000 ; bl setSnapshotUploadInterval
 6b284: mov r1,#1 ; bl setRtspServerMode
$ llvm-objdump … 0x20e5c   (waitForExitSignal)
 sigemptyset; sigaddset 2,3,15; sigprocmask(SIG_BLOCK); sigwait
$ llvm-objdump … 0x59954   (reboot_device)
 bl sync ; mov r0,#1 ; bl sleep ; ldr r0,=0x1234567 ; b reboot
$ grep -ci 'watchdog\|wdt' <strings of both builds>   -> 0
SD log downlaods/3/logs/2026-01-14_00.log:
 2026-01-14 01:14:06.964 I lp_app[289-lp_app] xhr_upload_service.cpp:210 do_upload | *************request upload image
Live camera (read-only checks):
 lp_app --noshell --log2file /mnt/sdcard/logs
 /data -> userdata
 netstat -ln: tcp 0.0.0.0:554 LISTEN (no HTTP server)
 DESCRIBE rtsp://<cam>:554/live -> RTSP/1.0 200 OK, Server: rtsp_demo, a=rtpmap:96 H264/90000 (no 401)
```

## Open questions

- What Wi-Fi work mode 2 means in the factory-reset path (station join of the factory network vs. setup AP), and the full Wi-Fi state machine. The meaning of the `PlatformDevice+28` flag that gates fingerprint seeding in `loadDefault` (OTP burned?).
- Physical function of GPIO 55 (IR-LED enable vs. IR-cut), of the SPI register 0x11 pulse, and of GPIO 54. Whether boards without a motor driver ignore the SPI writes [INFERENCE]. Needs the device tree or a schematic.
- Which component exports GPIO 34 and GPIO 53 (both out, 1 on the live camera) and what they drive.
- Effective H.264 bitrate in 3.1.0, given the out-of-range `u32BitRate` value. Whether JPEG Qfactor 90 is honoured without `VENC_SetJpegParam`.
- Whether TLS server certificates are verified (no CA bundle found).
- Exact default stable image-server host (`connect.prusa3d.com` inferred from string tail-merging).
- Which INI fields the 3.1.3 encryption helpers protect, and with what key material. How 3.1.3 stores the fingerprint. The default of `config.webrtc_mode`.
- Exact `sio::client` methods called during socket.io shutdown. Console log destination under RkLunch.sh (serial console assumed [INFERENCE]).
- Who uses `/userdata/lp_app_product` (removed by RkLunch.sh); neither lp_app build references it.
- Which SAR-ADC channel adc-keys uses (device tree; not channel 1, which is the LDR [INFERENCE]).
