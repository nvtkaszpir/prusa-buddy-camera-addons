# Prusa Buddy3D camera firmware findings

Reverse-engineering notes for the Buddy3D camera in the Prusa Core One L (Rockchip RV1106-class SoC, single Cortex-A7, Linux 5.10, uClibc and BusyBox userland).

Each page documents one file from `/oem/usr/bin` or `/oem/usr/sbin`. The source is the firmware dump in `downlaods/3/dump/oem/usr/` (firmware 3.1.0). The method is static analysis (strings, imported symbols, targeted disassembly), plus read-only checks on the running camera where stated; none of the binaries was executed. Claims that are not directly backed by evidence are marked **[INFERENCE]**.

**Live camera vs dump:** compared by md5 over ssh, the running camera (firmware 3.1.3) matches the dump almost everywhere. In `/oem/usr/bin`, 61 of 62 files are identical; only `RkLunch.sh` differs (the live copy also runs `network_init eth0`). All libraries in `/oem/usr/lib` are identical. In `/oem/usr/sbin`, everything is identical except [`lp_app`](cam-3.1.3/oem/usr/sbin/lp_app.md), which is a newer 3.1.3 build that adds WebRTC streaming, among other changes. `fw_version.txt` is absent on the camera. The camera's `/oem/usr/etc` also has voice prompts the dump lacks.

!!! warning "Local video stream has no password"
    `lp_app` serves the camera's H.264 video at `rtsp://<camera-ip>:554/live` without any authentication whenever the RTSP server is enabled (`rtsp_server_mode`). Anyone on the same network can watch it. Keep the camera on an isolated network or restrict port 554 with a firewall. See [`lp_app`](cam-3.1.3/oem/usr/sbin/lp_app.md).

!!! danger "Tools that change the camera when run"
    - [`rk_system_test`](cam-3.1.3/oem/usr/bin/rk_system_test.md) permanently overwrites vendor storage item 0 and then suspends the system.
    - [`rk_time_test`](cam-3.1.3/oem/usr/bin/rk_time_test.md) sets the RTC and the system clock to 2020-02-18 09:00 and leaves an RTC alarm enabled.
    - [`rk_watchdog_test`](cam-3.1.3/oem/usr/bin/rk_watchdog_test.md) arms the hardware watchdog. If it is killed without typing `quit`, the camera reboots.
    - [`rk_pwm_test`](cam-3.1.3/oem/usr/bin/rk_pwm_test.md) and [`rk_gpio_test`](cam-3.1.3/oem/usr/bin/rk_gpio_test.md) drive GPIO 38 and `pwmchip2`, reference-board pins whose function on this camera is unknown. `lp_app` uses different pins for IR control. Neither tool stops cleanly.
    - [`rk_mpi_dup_venc_test`](cam-3.1.3/oem/usr/bin/rk_mpi_dup_venc_test.md) can attach to `lp_app`'s encoder and force its bitrate to 1024 kbps.
    - Video tools such as [`rk_mpi_vi_test`](cam-3.1.3/oem/usr/bin/rk_mpi_vi_test.md), [`simple_vi_ivs`](cam-3.1.3/oem/usr/bin/simple_vi_ivs.md) and [`simple_vi_venc_wrap`](cam-3.1.3/oem/usr/bin/simple_vi_venc_wrap.md) disable the camera input on exit, which breaks `lp_app`'s video. The RTSP samples clash with `lp_app` on port 554.

## Topics

- [Video](video.md): timelapse file format, AVI to MP4 conversion (tested on the camera), and the SoC's video encoder hardware (RV1103G: hardware H.264/H.265 encoder, no decoder).
- [OTA firmware updates](ota.md): update servers (production and staging), the update check and its answer, the
  `/mnt/sdcard/ota` server switch, release types, and what each package (up to 3.1.6) rewrites.
- [NPU](npu.md): the RV1103G's NPU is enabled in the device tree, but its driver (`rknpu.ko`) is never loaded
  and nothing on the camera uses it.
- [Swap](swap.md): the kernel is built without swap support, so neither a swapfile on the microSD card, a swap
  partition nor zram can work on the stock firmware (checked up to 3.1.6).

## Used on the camera

| file | role |
|---|---|
| [`RkLunch.sh`](cam-3.1.3/oem/usr/bin/RkLunch.sh.md) | Main boot launcher: init scripts, kernel modules, Wi-Fi (and on the live unit, Ethernet), the microSD hooks (`lp_app.sh`, `lp_stop`, `log2file`, OTA packages), then `lp_app`. Started at boot. |
| [`ntpd`](cam-3.1.3/oem/usr/bin/ntpd.md) | ntp.org ntpd 4.2.8p15, syncing to `pool.ntp.org`. Started at boot by `S10ntp`. |
| [`upgrade_voice.sh`](cam-3.1.3/oem/usr/bin/upgrade_voice.sh.md) | Plays the "upgrade successful" prompt once after a firmware update. Started at boot in the background. |
| [`simple_ao`](cam-3.1.3/oem/usr/bin/simple_ao.md) | Raw PCM player on ALSA `hw:0,0`. Used by `RkLunch.sh` and `upgrade_voice.sh` for voice prompts. |

## `/oem/usr/sbin`: the camera application and networking

| file | role |
|---|---|
| [`lp_app`](cam-3.1.3/oem/usr/sbin/lp_app.md) | The production camera application: video pipeline, snapshots to Prusa Connect, timelapse, RTSP server, IR/night mode, button and LED, QR Wi-Fi provisioning, cloud signaling and OTA. Started by `RkLunch.sh`. |
| [`wifi_setup.sh`](cam-3.1.3/oem/usr/sbin/wifi_setup.sh.md) | Wi-Fi client (`wpa_supplicant`) and access-point (`hostapd` + `udhcpd`, 192.168.42.1) setup script. Called by `lp_app`. |
| [`eth_monitor.sh`](cam-3.1.3/oem/usr/sbin/eth_monitor.sh.md) | Watches the link state of an interface and starts or stops the `udhcpc` DHCP client. Started by `RkLunch.sh` for `wlan0` (and `eth0` on the live unit). |
| [`hostapd`](cam-3.1.3/oem/usr/sbin/hostapd.md) | hostapd 2.10 (WPA2-PSK, no WPS) for the setup access point. |
| [`udhcpd`](cam-3.1.3/oem/usr/sbin/udhcpd.md) | BusyBox 1.36.1 multi-call binary used as the access point's DHCP server. |
| [`iw`](cam-3.1.3/oem/usr/sbin/iw.md) | iw 5.19. `lp_app` uses it to read the signal strength and to detect clients on its access point. |
| [`iwlist`](cam-3.1.3/oem/usr/sbin/iwlist.md) | Wireless Tools v30. `lp_app` uses it to pick the access-point channel. |
| [`fw_version.txt`](cam-3.1.3/oem/usr/sbin/fw_version.txt.md) | Contains `3.1.0`. Read by nothing; absent on the live camera. |

## Diagnostics and helpers

| file | purpose |
|---|---|
| [`dumpsys`](cam-3.1.3/oem/usr/bin/dumpsys.md) | Rockchip rockit/MPI debug client. Talks to `127.0.0.1:3893`, which is not listening on the live camera. |
| [`kill_process.sh`](cam-3.1.3/oem/usr/bin/kill_process.sh.md) | Sends SIGKILL to every process whose `ps` line contains a given string. |
| [`mpp_info_test`](cam-3.1.3/oem/usr/bin/mpp_info_test.md) | Prints the `librockchip_mpp` version and its embedded commit history. |
| [`rkaiq_3A_server`](cam-3.1.3/oem/usr/bin/rkaiq_3A_server.md) | Standalone ISP 3A (auto exposure, white balance, focus) daemon. |
| [`rkisp_demo`](cam-3.1.3/oem/usr/bin/rkisp_demo.md) | ISP capture and interactive tuning tool. |

## Hardware tests (`rk_*_test`, statically built `librksysutils` code)

| file | purpose |
|---|---|
| [`rk_adc_test`](cam-3.1.3/oem/usr/bin/rk_adc_test.md) | Reads SAR-ADC channels once (read-only). It looks for `ff5e0000.saradc`, but this camera's ADC is `ff3c0000.saradc`, so it does not find it. |
| [`rk_event_test`](cam-3.1.3/oem/usr/bin/rk_event_test.md) | Prints input events from `/dev/input/event*`. Read-only. |
| [`rk_gpio_test`](cam-3.1.3/oem/usr/bin/rk_gpio_test.md) | Copies GPIO 142 to GPIO 38 every 20 ms, forever. |
| [`rk_led_test`](cam-3.1.3/oem/usr/bin/rk_led_test.md) | Sets the `white` LED to timer blink. |
| [`rk_pwm_test`](cam-3.1.3/oem/usr/bin/rk_pwm_test.md) | GPIO-driven toggling of `pwmchip2` at 16 kHz, 50 %. |
| [`rk_system_test`](cam-3.1.3/oem/usr/bin/rk_system_test.md) | Chip ID, vendor-storage write, suspend. **Destructive.** |
| [`rk_time_test`](cam-3.1.3/oem/usr/bin/rk_time_test.md) | Sets the RTC and system clock, then tests an alarm. **Changes the time.** |
| [`rk_watchdog_test`](cam-3.1.3/oem/usr/bin/rk_watchdog_test.md) | Arms and kicks `/dev/watchdog`. **Can reboot.** |

## Rockit MPI unit tests (`rk_mpi_*_test`)

| file | purpose |
|---|---|
| [`rk_mpi_adec_test`](cam-3.1.3/oem/usr/bin/rk_mpi_adec_test.md) | File-to-file audio decoder test (MP2, G.711, G.726). |
| [`rk_mpi_aenc_test`](cam-3.1.3/oem/usr/bin/rk_mpi_aenc_test.md) | File-to-file audio encoder test. |
| [`rk_mpi_af_test`](cam-3.1.3/oem/usr/bin/rk_mpi_af_test.md) | Offline audio filter test: resampling and the 3A (AEC/ANR/AGC) chain. |
| [`rk_mpi_ai_test`](cam-3.1.3/oem/usr/bin/rk_mpi_ai_test.md) | Audio input test: capture, VQE, sound-event detection. |
| [`rk_mpi_amix_test`](cam-3.1.3/oem/usr/bin/rk_mpi_amix_test.md) | `amixer`-like ALSA mixer control tool. |
| [`rk_mpi_ao_test`](cam-3.1.3/oem/usr/bin/rk_mpi_ao_test.md) | Audio output test. |
| [`rk_mpi_avio_test`](cam-3.1.3/oem/usr/bin/rk_mpi_avio_test.md) | Checks how stream packets wrap buffers. Not a device test. |
| [`rk_mpi_dup_venc_test`](cam-3.1.3/oem/usr/bin/rk_mpi_dup_venc_test.md) | Attaches to an existing encoder channel and changes its bitrate. |
| [`rk_mpi_mb_test`](cam-3.1.3/oem/usr/bin/rk_mpi_mb_test.md) | Media-buffer pool allocator test. |
| [`rk_mpi_mmz_test`](cam-3.1.3/oem/usr/bin/rk_mpi_mmz_test.md) | MMZ (DMA buffer) allocator test. |
| [`rk_mpi_rgn_test`](cam-3.1.3/oem/usr/bin/rk_mpi_rgn_test.md) | Region and OSD overlay test. |
| [`rk_mpi_sys_test`](cam-3.1.3/oem/usr/bin/rk_mpi_sys_test.md) | SYS module bind bookkeeping test. |
| [`rk_mpi_tde_test`](cam-3.1.3/oem/usr/bin/rk_mpi_tde_test.md) | 2-D graphics engine test on files. |
| [`rk_mpi_venc_test`](cam-3.1.3/oem/usr/bin/rk_mpi_venc_test.md) | Hardware video encoder test. |
| [`rk_mpi_vi_dup_test`](cam-3.1.3/oem/usr/bin/rk_mpi_vi_dup_test.md) | Extra capture channels on an already-enabled camera device. |
| [`rk_mpi_vi_test`](cam-3.1.3/oem/usr/bin/rk_mpi_vi_test.md) | Camera capture (VI) test, modes 0–12. |
| [`rk_mpi_vpss_test`](cam-3.1.3/oem/usr/bin/rk_mpi_vpss_test.md) | Scale, crop, rotate and mirror test on file input. |

## SDK samples (`sample_*`, `simple_*`)

| file | purpose |
|---|---|
| [`sample_ai`](cam-3.1.3/oem/usr/bin/sample_ai.md) | Audio capture to raw PCM. |
| [`sample_ai_aenc`](cam-3.1.3/oem/usr/bin/sample_ai_aenc.md) | Audio capture plus encode. |
| [`sample_camera_stresstest`](cam-3.1.3/oem/usr/bin/sample_camera_stresstest.md) | Whole-pipeline stress test with four hard-coded scenarios. |
| [`sample_dual_camera`](cam-3.1.3/oem/usr/bin/sample_dual_camera.md) | Two-sensor RTSP streaming. Needs two sensors. |
| [`sample_isp_stresstest`](cam-3.1.3/oem/usr/bin/sample_isp_stresstest.md) | ISP and rkaiq soak test. |
| [`sample_multi_vi`](cam-3.1.3/oem/usr/bin/sample_multi_vi.md) | Multi-camera capture. |
| [`sample_rgn_stresstest`](cam-3.1.3/oem/usr/bin/sample_rgn_stresstest.md) | OSD and privacy-mask soak test with RTSP. |
| [`sample_venc_stresstest`](cam-3.1.3/oem/usr/bin/sample_venc_stresstest.md) | Encoder soak test with RTSP. |
| [`sample_vi`](cam-3.1.3/oem/usr/bin/sample_vi.md) | Minimal camera capture. |
| [`sample_vi_vpss_osd_venc`](cam-3.1.3/oem/usr/bin/sample_vi_vpss_osd_venc.md) | Camera → scaler → encoder with OSD, served over RTSP. |
| [`simple_adec_ao`](cam-3.1.3/oem/usr/bin/simple_adec_ao.md) | Decodes G.711/G.726 and plays it. |
| [`simple_ai`](cam-3.1.3/oem/usr/bin/simple_ai.md) | Microphone to raw PCM. |
| [`simple_ai_aenc`](cam-3.1.3/oem/usr/bin/simple_ai_aenc.md) | Microphone to G.711/G.726. |
| [`simple_fast_client`](cam-3.1.3/oem/usr/bin/simple_fast_client.md) | Fast-boot camera demo with RTSP. |
| [`simple_venc_jpeg`](cam-3.1.3/oem/usr/bin/simple_venc_jpeg.md) | Interactive JPEG snapshots. |
| [`simple_venc_osd`](cam-3.1.3/oem/usr/bin/simple_venc_osd.md) | Encoder with an OSD overlay. |
| [`simple_vi_get_frame`](cam-3.1.3/oem/usr/bin/simple_vi_get_frame.md) | Grabs NV12 frames and prints per-frame stats. |
| [`simple_vi_ivs`](cam-3.1.3/oem/usr/bin/simple_vi_ivs.md) | Motion and occlusion detection. |
| [`simple_vi_rkaiq`](cam-3.1.3/oem/usr/bin/simple_vi_rkaiq.md) | Camera bring-up with optional 3A. |
| [`simple_vi_venc`](cam-3.1.3/oem/usr/bin/simple_vi_venc.md) | Camera → encoder to a file. |
| [`simple_vi_venc_change_resolution`](cam-3.1.3/oem/usr/bin/simple_vi_venc_change_resolution.md) | Changes the encoder resolution at run time. |
| [`simple_vi_venc_rtsp`](cam-3.1.3/oem/usr/bin/simple_vi_venc_rtsp.md) | Camera → encoder → RTSP `/live/0` on port 554. |
| [`simple_vi_venc_wrap`](cam-3.1.3/oem/usr/bin/simple_vi_venc_wrap.md) | Low-latency wrap (ring-buffer) mode VI → VENC. |
| [`simple_vi_vpss_venc`](cam-3.1.3/oem/usr/bin/simple_vi_vpss_venc.md) | Camera → scaler → encoder. |

## Media and graphics tests

| file | purpose |
|---|---|
| [`mpi_enc_test`](cam-3.1.3/oem/usr/bin/mpi_enc_test.md) | Rockchip MPP hardware encoder test (H.264/H.265/MJPEG). |
| [`rgaImDemo`](cam-3.1.3/oem/usr/bin/rgaImDemo.md) | RGA 2D accelerator demo: copy, resize, crop, rotate, blend, fill. |
| [`rk_rve_sample_test`](cam-3.1.3/oem/usr/bin/rk_rve_sample_test.md) | Self-test and demo for the RVE vision accelerator. |
| [`vpu_api_test`](cam-3.1.3/oem/usr/bin/vpu_api_test.md) | Legacy MPP "vpu api" demo. Fails here because `libvpu.so` is missing. |
