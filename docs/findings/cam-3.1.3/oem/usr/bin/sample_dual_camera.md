# `sample_dual_camera`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/sample_dual_camera` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `107236` |
| sha256 | `6f7f05636e63b10d6aa5f87a602a7e394d0892d30cbed1fffcfd8f9e716a4182` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106 SDK rkmpi example `sample_dual_camera`, with the statically linked `rtsp_demo` |
| confidence | high |

## Summary

This is a two-sensor streaming demo. It starts rkaiq for camera 0 and camera 1 (IQ from `/oem/usr/share/iqfiles`) and opens VI device 0 and VI device 1. Each is bound to its own H.265 CBR encoder channel, and the two streams are served over RTSP as `rtsp://<ip>:554/live/0` and `/live/1`. It targets dual-sensor boards; this camera has a single sensor.

## Usage

Printed by `0x12740` when `argc < 2` or on an unknown option:

```
usage example:
	%s -s 0 -w 1920 -h 1080 -s 1 -w 1920 -h 1080 
	rtsp://xx.xx.xx.xx/live/0, sensor 0 mainpath,Default OPEN
	rtsp://xx.xx.xx.xx/live/1, sensor 1 mainpath,Default OPEN
	-s | --sensor id
	-w | --width: camera with, Default 1920,max 1920
	-h | --height: camera height, Default 1080,max 1080
```

The getopt string is `?::w:h:s:`. Long options (table at `0x24880`): `--width(w)`, `--height(h)`, `--sensorid(s)`, `--help(?)`.

- `-s <0|1>` selects which sensor the following `-w`/`-h` apply to. Its initial value is -1, so `-w`/`-h` given before any `-s` are ignored.
- Sizes larger than 1920×1080 print `invalid width/height,please check!` and the program exits. The chosen sizes are echoed as `sensor 0:%d*%d` / `sensor 1:%d*%d`.

## How it works

`main` is at `0x127b4`:

1. Defaults: both sensors 1920×1080, codec H265 (codec 6 / RC 8 = H.265 CBR), bitrate 4096, camera count 2, IQ dir `/oem/usr/share/iqfiles`, a `/userdata` string, multictx 1. It allocates the context, `memset`s it and installs `signal(SIGINT)`.
2. It parses the options and validates the sizes, then prints `#CodecName`, `#IQ Path`, `#Rkaiq XML DirPath` and `#bMultictx`.
3. For cam 0 and 1: `SAMPLE_COMM_ISP_Init(i, NORMAL, multictx, "/oem/usr/share/iqfiles")` and `SAMPLE_COMM_ISP_Run(i)` (`rk_aiq_uapi2_sysctl_init/prepare/start`). This is unconditional; there is no `-a` option.
4. RTSP: `rtsp_new_demo(554)`, then `rtsp_new_session("/live/0")` and `rtsp_new_session("/live/1")`, each with `rtsp_set_video(..., 2 = H.265, ...)`, then the timestamp sync calls.
5. `RK_MPI_SYS_Init`. Then for `i = 0..1`:
   - `SAMPLE_COMM_VI_CreateChn` (dev i, pipe i). API calls: `RK_MPI_VI_SetDevAttr`, `EnableDev`, `SetDevBindPipe`, `SetChnAttr`, `EnableChn`.
   - `SAMPLE_COMM_VENC_CreateChn` (chn i, H.265 CBR, 4096 kbps). This starts `venc0_get_stream` / `venc1_get_stream`.
   - `SAMPLE_COMM_Bind`: VI (mod 8, dev i) → VENC (mod 4, 0, chn i), via `RK_MPI_SYS_Bind`.
6. The stream threads (`0x123b8`, `0x1257c`) loop on `SAMPLE_COMM_VENC_GetStream`, push each packet to their RTSP session (`rtsp_tx_video`), call `rtsp_do_event`, log `chn:%d, loopCount:%d wd:%d`, then `ReleaseStream` and `usleep`. **Nothing is written to disk.** The binary does not import `fopen`/`fwrite`, so the `/userdata` string is never used as a file path.
7. `main` sleeps until SIGINT. Teardown: join, `rtsp_del_demo`, UnBind, VENC destroy, VI destroy, `RK_MPI_SYS_Exit`, `SAMPLE_COMM_ISP_Stop` for each camera, `free`.

There is no VPSS or RGN stage. It is a direct VI → VENC pipeline per sensor.

## Interfaces touched

- Device nodes / sysfs / procfs: none named directly. It uses VI devices 0 and 1, two ISP/AIQ contexts and VENC channels 0 and 1 through librockit/librkaiq [INFERENCE].
- Files and paths read/written: reads IQ JSON from `/oem/usr/share/iqfiles`. It writes no files (`/userdata` appears only as an unused default string).
- Network: an RTSP server on TCP 554 with sessions `/live/0` and `/live/1` (H.265), RTP over UDP or TCP-interleaved.
- Environment variables / config files: `HDR_MODE` is `setenv`'d by the ISP init helper.

## Relevance on this camera

- It is not started at boot and not referenced anywhere in the dump (`grep -rlw sample_dual_camera` finds only the binary). `lp_app` does not use it.
- This camera has one sensor (the IQ directories hold single-sensor profiles: sc4336, sc530ai, jx_f37p). AIQ init for cam 1 and VI device 1 would fail, and the program would abort or run degraded [INFERENCE].
- Running it alongside `lp_app` collides on VI 0, VENC 0, the ISP and RTSP port 554 [INFERENCE].
- Side effects: an unauthenticated RTSP server. No flash writes.

## Evidence

- `python3 opts.py sample_dual_camera`: `--width(1,w) --height(1,h) --sensorid(1,s) --help(2,?)`. Optstring `?::w:h:s:` at `0x393ec`.
- `main` defaults excerpt:
  ```
  127f0 mov r3,#6 (codec H265) ; 127f8 mov r3,#8 (RC H265CBR) ; 12804 ="H265"
  12818 ="/userdata" ; 12820 mov r3,#2 (camera count) ; 12830 #4096 ; 1283c ="/oem/usr/share/iqfiles"
  ```
- ISP loop: `12ab8 bl SAMPLE_COMM_ISP_Init ; 12ac0 bl SAMPLE_COMM_ISP_Run ; 12ad8 cmp i,cam_num ; blt`.
- RTSP: `12ae0 movw r0,#554 ; bl rtsp_new_demo ; 12b08 ="/live/0" ; 12b34 ="/live/1" ; rtsp_set_video(...,#2,...)` ×2.
- Per-camera loop: `12e04 bl SAMPLE_COMM_VI_CreateChn ; 13088 bl SAMPLE_COMM_VENC_CreateChn ; 1311c mov #4 (VENC mod) ; 131a8 bl SAMPLE_COMM_Bind ; 131c0 cmp i,#cam_num ; blt`.
- Imports: no `fopen64`/`fwrite`; socket APIs (`socket bind listen accept select send sendto recv recvfrom setsockopt`) are present for RTSP.

## Open questions

- The behaviour of `rk_aiq_uapi2_sysctl_init` for a non-existent second sensor (error vs. hang) is not determinable statically.
- The `multictx = 1` default is inferred from `mov r3,#1 ; str [r11,#-96]` and its use in the ISP init call. Its effect inside librkaiq was not examined.
