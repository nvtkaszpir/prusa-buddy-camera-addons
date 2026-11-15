# `sample_isp_stresstest`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/sample_isp_stresstest` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `32180` |
| sha256 | `f47351786b78ad4e7e4f9aed6f4baa0c2c0003e3f480d6e4ede5c27638c355af` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rkmpi stress test `sample_isp_stresstest` |
| confidence | high |

## Summary

This is a soak test for the ISP / rkaiq engine. It captures from one VI channel with no encoder and no network, and runs rkaiq in-process. With `-m N` a test thread repeatedly does one of these:

- restarts the AIQ engine
- toggles normal/HDR2 mode (by restarting AIQ)
- cycles the VI frame rate
- toggles lens-distortion correction (LDCH)

Frames can be dumped to a file. It is an SDK QA tool.

## Usage

```
usage example:
	%s -w 1920 -h 1080 -a /etc/iqfiles/ -l 10 -o /userdata/
	-a | --aiq : enable aiq with dirpath provided, eg:-a /etc/iqfiles/, set dirpath empty to using path by default, without this option aiq should run in other application
	-d | --device_name : set pcDeviceName, eg: /dev/video0 Default: NULL
	-w | --width : camera with, Default: 1920
	-h | --height : camera height, Default: 1080
	-o | --output_path : vi output file path, Default: NULL
	-I | --camid : camera id, Default: 0
	-l | --loop_count : loop count, Default: -1
	-f | --fps : isp output fps, Default: -1
	-m | --mode_test_type : test type, 0:none, 1:P/N switch test, 2:HDR switch test, 3:frame rate switch test, 4: LDCH mode test. Default: 0
	--pixel_format : camera Format, Value:nv12,nv16,yuyv,uyvy,afbc. Default: nv12
	--hdr_mode : set camera hdr mode, 0: normal, 1: HDR2. Default: 0
	--mode_test_loop : module test loop, default: -1
	--test_frame_count : set the venc reveive frame count for every test loop, default: 500
```

The getopt string is `?::a::d:f:w:h:o:I:l:p:m:c:`. Long options (table at `0x14f48`): `aiq(a, optional) device_name(d) pixel_format(214, optional) width height output_path camid(I) loop_count fps(f) hdr_mode(213) mode_test_type(m) mode_test_loop(224) test_frame_count(c) help`.

The compare chain in `main` handles `l c I a d h w m o 214 224 213`.

- `-f/--fps` and `-p` have **no** handler. They go to the default branch, which prints usage and returns 0, so the documented `-f` cannot be used.
- `--hdr_mode` accepts 0 or 1. Anything else logs `input hdr mode param invaild` and exits.
- `-a` without a directory means no AIQ. All test modes except 3 restart AIQ, so they need `-a dir`.

## How it works

`main` is at `0x12d50`:

1. `global_param_init` (context, `gModeTest`, `sem_init`, `pthread_mutex_init`), `signal(SIGINT)`, option parsing. Pixel format is parsed via `strcmp` against `nv12/nv16/yuyv/uyvy/afbc`.
2. If `-a dir`: it prints `#Rkaiq XML DirPath`, `#bMultictx`, `eHdrMode`, then `SAMPLE_COMM_ISP_Init(camid, hdr, multictx, dir)` + `SAMPLE_COMM_ISP_Run`. The init does `setenv HDR_MODE`, `rk_aiq_uapi2_sysctl_init`/`prepare`, then `sysctl_start`.
3. `RK_MPI_SYS_Init`. Optional `strcpy` of `-d` into the VI context. `SAMPLE_COMM_VI_CreateChn`. API calls: `RK_MPI_VI_SetDevAttr`, `EnableDev`, `SetDevBindPipe`, `SetChnAttr`, `EnableChn`.
4. `pthread_create(vi_get_stream)` (`0x11cec`):
   - If `-o` is set, it opens `/%s/vi_%d.bin` with `"wb"`.
   - Loop: `RK_MPI_VI_GetChnFrame`, `fwrite`/`fflush`, `RK_MPI_VI_ReleaseChnFrame`. Under a mutex it counts frames and `sem_post`s every `test_frame_count` frames. It stops at `loop_count`.
5. If `mode_test_type != 0`: `pthread_create(isp_stress_test)` (`0x129f0`). It does `prctl(PR_SET_NAME, "isp_stress_test")` and `sleep(3)`, then dispatches:

| `-m` | function | per-iteration action |
|---|---|---|
| 1 | `pn_mode_switch` `0x11fe4` | `RK_MPI_VI_PauseChn`, `SAMPLE_COMM_ISP_Stop` (`sysctl_stop`/`deinit`), `SAMPLE_COMM_ISP_Init` with the same camid/hdr/multictx/IQ dir, `SAMPLE_COMM_ISP_Run`, `RK_MPI_VI_ResumeChn`. This is a full AIQ restart. The binary does not show what "P/N" toggles; nothing changes between iterations except the restart. |
| 2 | `hdr_mode_switch_test` `0x12280` | Same pause/stop/init/run/resume cycle, flipping the HDR mode between 0 (normal) and 16 (`0x10`, HDR 2-frame). |
| 3 | `frameRate_switch_test` `0x12544` | `RK_MPI_VI_GetChnAttr`, then the frame rate is incremented from 2 up to 25 and wraps to 1, then `RK_MPI_VI_SetChnAttr`. Logs "Framerate switch to: %d". |
| 4 | `ldch_mode_test` `0x127e0` | `SAMPLE_COMM_ISP_SetLDCH(cam, enable, level)` (`rk_aiq_user_api2_aldch_v21_GetAttrib`/`SetAttrib`). It toggles enable on/off. While enabled the level is incremented, wrapping after 255. |

   Each iteration waits on the frame semaphore (`sem_wait`, `0x11f9c`). After `--mode_test_loop` iterations (if > 0) it logs "test end(pass/success)" and calls `program_normal_exit`.

6. `main` sleeps until quit, joins both threads, calls `SAMPLE_COMM_VI_DestroyChn` and `RK_MPI_SYS_Exit`, then ISP stop and `global_param_deinit`.

**Difference from the other stress tests:** this is the only one without VENC, RTSP or RGN. It imports `RK_MPI_VI_PauseChn`/`ResumeChn`/`GetChnAttr` and no `RK_MPI_VENC_*` at all. It shares the `global_param_init` / semaphore / `--mode_test_loop` / `--test_frame_count` skeleton with `sample_venc_stresstest` and `sample_rgn_stresstest`.

## Interfaces touched

- Device nodes / sysfs / procfs: none named directly. `-d` can name a VI node (e.g. `/dev/video0`). The ISP and sensor are reached through librockit/librkaiq [INFERENCE].
- Files and paths read/written:
  - Writes `/<output_path>/vi_<devId>.bin` (raw YUV frames) when `-o` is given.
  - Reads IQ JSON from the `-a` directory.
- Network: none.
- Environment variables / config files: `HDR_MODE` (`setenv`) on every AIQ (re)init.

## Relevance on this camera

- It is not started at boot and not referenced anywhere in the dump (`grep -rlw sample_isp_stresstest` finds only the binary). `lp_app` does not use it.
- Running it while `lp_app` is up means a second rkaiq instance fighting for the same sensor and ISP. Its modes 1, 2 and 4 repeatedly stop and restart 3A and change LDCH, which would visibly disrupt `lp_app`'s image [INFERENCE].
- Side effects: only the optional raw dump (large, unbounded with the default `-l -1`). Nothing persistent is changed.

## Evidence

- `python3 opts.py sample_isp_stresstest` → table above. Optstring at `0x736c`.
- `main` compare chain: `cmp r3,#108/#99/#73/#97/#100/#104/#119/#109/#111/#214/#224/#213`. Default target `0x13300`: `bl usage ; mov r3,#0 ; b return`.
- AIQ gating: `1334c ldr r3,[r11,#-32] ; cmp r3,#0 ; beq 0x1342c (skip to RK_MPI_SYS_Init)`, then `13404 bl SAMPLE_COMM_ISP_Init ; 13410 bl SAMPLE_COMM_ISP_Run`.
- `pn_mode_switch`: `12084 bl RK_MPI_VI_PauseChn ; 1209c bl SAMPLE_COMM_ISP_Stop ; 120e4 bl SAMPLE_COMM_ISP_Init ; 12100 bl SAMPLE_COMM_ISP_Run ; 12180 bl RK_MPI_VI_ResumeChn`.
- HDR toggle: `122fc ldr [ctx,#44] ; cmp #0 → mov #16 ; cmp #16 → mov #0`.
- Frame-rate cycle: `12604 cmn r3,#1 → 1 ; add #1 ; cmp #25 ; ble ; else mov #1`.
- LDCH: `12830 bl SAMPLE_COMM_ISP_SetLDCH ; ... cmp level,#255 ; bls ; mov #0 ; ... moveq/movne toggle`.
- Thread creation: `13620 =0x11cec bl pthread_create` (vi_get_stream); `1363c cmp mode,#0 ; beq ; =0x129f0 bl pthread_create`.

## Open questions

- What "P/N switch" means upstream (perhaps day/night "positive/negative" IQ scene switching) is not visible here. The binary only restarts AIQ with unchanged parameters.
- The exact `VI_CHN_ATTR_S` frame-rate field changed in mode 3 (source or destination rate) was not mapped.
