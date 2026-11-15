# `rkaiq_3A_server`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/rkaiq_3A_server` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `22124` |
| sha256 | `944a22e53e428184dc84a7e82ffba6773f7503589e5ffbbf318e24dcc304492c` |
| linked libraries | `librkaiq.so, libstdc++.so.6, libgcc_s.so.1, libc.so.0` |
| origin | Rockchip ISP SDK (rkaiq / camera_engine_rkaiq) tool `rkaiq_3A_server` |
| confidence | high |

## Summary

A small standalone daemon from Rockchip's camera_engine_rkaiq. It runs the ISP 3A engine (auto exposure, auto white balance, auto focus and the IQ tuning modules) through `librkaiq.so` for each rkisp media pipeline. It starts and stops the engine whenever a V4L2 client starts or stops streaming. It is meant for setups where the video application does not link rkaiq itself.

## Usage

```
ERR: Usage: %s to start 3A engine
         --silent,  optional, subpress debug log
```

`getopt_long` long options: `silent`, `help`. No other options exist. The IQ directory is hard-coded to `/etc/iqfiles/`.

## How it works

1. It parses options. `--silent` suppresses the `DBG:` prints.
2. It enumerates `/dev/media%d` with the bundled media-ctl library (`media_device_new`, `media_device_enumerate`, `media_get_entity_by_name`, `/sys/dev/char/%u:%u`). It looks up the entities `rkisp-isp-subdev`, `rkisp-input-params`, `rkisp-statistics` and `rkisp_mainpath` (log: `Cound not find rkisp dev names, skipped %s`). It also finds the attached sensor (`ERR: No sensor attached to %s`) and resolves the device nodes (`media_entity_get_devname`).
3. For each ISP pipeline it creates a thread with `pthread_create` (`ERR: Failed to create camera engine thread for: %s`). The thread does the following:
   - Calls `rk_aiq_uapi2_sysctl_getBindedSnsEntNmByVd`, then `rk_aiq_uapi2_sysctl_init(sensor, "/etc/iqfiles/", ...)` and `rk_aiq_uapi2_sysctl_setMulCamConc`.
   - Subscribes to stream start/stop V4L2 events with `ioctl` (`DBG: subscribe events from %s success !`).
   - Loops: wait for the stream start event, then `rk_aiq_uapi2_sysctl_prepare` and `_start`. Wait for the stream stop event, then `_stop`.
4. The main thread `pthread_join`s the workers.

It produces no output files, only log text on stdout/stderr.

## Interfaces touched

- Device nodes / sysfs / procfs: `/dev/media%d`, the rkisp `/dev/video*` and `/dev/v4l-subdev*` nodes (params, stats, isp-subdev, mainpath, sensor subdev), and `/sys/dev/char/%u:%u`.
- Files and paths read/written: IQ JSON files under `/etc/iqfiles/`. On this dump that directory holds `CAC_sc4336_OT01_40IRC_F16/`, `CAC_sc530ai_CMK-OT2115-PC1_30IRC-F16/` and `jx_f37p_AXF37AA_SR2012A.json` (the same set is in `/oem/usr/share/iqfiles`).
- Network: none.
- Environment variables / config files: none in the binary. librkaiq itself honours its own env/log variables [INFERENCE].

## Relevance on this camera

It is not started at boot. Nothing in `/etc/init.d`, `/oem/usr/etc/init.d` or `RkLunch.sh` references it. A grep of the dump for the name finds only the binary itself. The production app `/oem/usr/sbin/lp_app` most likely runs rkaiq in-process through rockit/librkaiq [INFERENCE]. If you start this daemon while lp_app runs, a second 3A engine binds to the same ISP params/stats nodes. That would conflict with lp_app's engine, either by failing to open busy nodes or by fighting over the ISP parameters [INFERENCE]. It writes nothing to flash.

## Evidence

```
$ strings -n4 rkaiq_3A_server | grep -E 'iqfiles|rkisp|media%d|Usage|silent'
/etc/iqfiles/
rkisp-isp-subdev
rkisp-input-params
rkisp-statistics
rkisp_mainpath
ERR: Usage: %s to start 3A engine
         --silent,  optional, subpress debug log
/dev/media%d
silent
imports: rk_aiq_uapi2_sysctl_{init,prepare,start,stop,setMulCamConc,getBindedSnsEntNmByVd},
         getopt_long, pthread_create/join, ioctl, media_* (statically bundled media-ctl)
```

## Open questions

- I did not disassemble the exact ioctl event types (presumably the RKISP CIFISP stream on/off events) [INFERENCE].
- I did not determine which sensor is actually fitted (sc4336 or sc530ai). That depends on the kernel DT and the boot log.
