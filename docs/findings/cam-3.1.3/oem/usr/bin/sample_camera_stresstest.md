# `sample_camera_stresstest`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/sample_camera_stresstest` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `46292` |
| sha256 | `3d97b3c5885528c9fb23f242d7dbb0b890d6cda5303d87f7bcebc25c79eec423` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106 SDK rkmpi test `sample_camera_stresstest`. It is an older, simpler design than the `sample_*_stresstest` family: it hard-codes a 2560×1520 sensor and the developer path `tmp/nfs_share/rv1106`. |
| confidence | high |

## Summary

This is a whole-pipeline bring-up/stress test with four hard-coded scenarios, chosen with `-n`. Each scenario repeatedly builds and tears down a camera pipeline (VI, optionally VPSS and VENC, plus rkaiq) or switches encoder settings. It runs for a fixed number of frames per iteration and `-l` iterations. There is no RTSP and no `getopt` help beyond a short usage. It is an SDK QA leftover.

## Usage

Printed by `0x12510` when `argc < 2`, on an invalid option, or on an invalid index:

```
Usage : %s -n <index> -l <loop count> -c <frame count> -f <pixel format>
index:
	 0)isp stresstest(IqFileDir: /etc/iqfiles ~ /usr/share/iqfiles)
	 1)venc stresstest(H264 ~ H265)
	 2)venc stresstest(1x ~ 0.5x resolution)
	 3)vi->vps->venc stresstest
pixel format:
	 nv12) no compress
	 afbc) compress
```

The getopt string is `?::n:l:c:f:`. Long options (table at `0x18044`): `--index(n)`, `--loop_count(l)`, `--frame_count(c)`, `--pixel_format(f, optional)`. The jump table at `0x14378` handles exactly `n l c f`.

- `-n <0..3>`: scenario. **There is no default.** The stack slot is not initialised when `-n` is omitted, so the scenario is undefined; an out-of-range value prints `the index %d is invaild!` and usage.
- `-l <N>`: global `g_loopcount`, default 1 (`.data` at `0x2a3e8`).
- `-c <N>`: frames per iteration, global default 200 (`.data` at `0x2a3ec`).
- `-f nv12|afbc`: sets the compress flag to 0 or 1. The default is 1 (AFBC) (`.data` at `0x2a3f0`).

## How it works

`main` is at `0x142d0`. After parsing, it loops `while (g_loopcount != 0)`: run the selected scenario, then if `g_loopcount > 0`, decrement it, print `sample_camera_stresstest: g_loopcount(%d)` and `sleep(2)`.

**Index 0, `SAMPLE_CAMERA_ISP_Stresstest` (`0x12e50`).** The IQ directory alternates by loop parity: `/etc/iqfiles` (even) or `/oem/usr/share/iqfiles` (odd). Both exist in this dump. Each run does:

- `SAMPLE_COMM_ISP_Init(0, ..., dir)` + `SAMPLE_COMM_ISP_Run`
- `RK_MPI_SYS_Init`
- `SAMPLE_COMM_VI_CreateChn` (2560×1520)
- `pthread_create(vi_get_stream)`: `RK_MPI_VI_GetChnFrame` / `ReleaseChnFrame` for `-c` frames. No dump: the output path is NULL.
- wait for quit, join, `SAMPLE_COMM_VI_DestroyChn`, `RK_MPI_SYS_Exit`, `SAMPLE_COMM_ISP_Stop`

So each loop is a full AIQ and VI start/stop with a different IQ directory.

**Index 1 / 2, `SAMPLE_CAMERA_VENC_Stresstest(ctx, 0|1)` (`0x131ec`).** One pipeline with an internal toggle loop:

- AIQ init/run with `/etc/iqfiles`.
- `RK_MPI_SYS_Init`, then `RK_MPI_MB_CreatePool` (size from `RK_MPI_CAL_VGS_GetPicBufferSize`).
- VI 2560×1520, then `SAMPLE_COMM_VPSS_CreateChn`, then `SAMPLE_COMM_VENC_CreateChn` (H264 CBR, 4096 kbps, 2560×1520, starts `venc_get_stream`).
- Bind VI → VPSS and VPSS → VENC.

Per iteration it waits for the stream thread to finish `-c` frames, then switches:

- Mode 0 (index 1): `SAMPLE_CAMERA_VENC_SetConfig` (`0x13100`) does UnBind VPSS→VENC, `SAMPLE_COMM_VENC_DestroyChn`, `SAMPLE_COMM_VENC_CreateChn` with the new codec, Bind, then waits. The codec alternates "Switch to h265cbr coding!" (codec 6, RC 8) and "Switch to h264cbr coding!" (codec 5, RC 1).
- Mode 1 (index 2): `SAMPLE_COMM_VPSS_SetChnAttr` (`RK_MPI_VPSS_SetChnAttr`) switches the VPSS output between full size and half size ("Switch to %dx%d coding!").

The internal loop consumes `g_loopcount`; afterwards `main` sets it to 0. Teardown: join, `RK_MPI_MB_DestroyPool`, UnBind VPSS→VENC ("Unbind VPSS[0] - VENC[0]!") and VI→VPSS, destroy VENC, VPSS and VI, `RK_MPI_SYS_Exit`, ISP stop.

**Index 3, `SAMPLE_CAMERA_VI_VPSS_VENC_Stresstest` (`0x13c30`).** It builds the same VI(2560×1440) → VPSS → VENC(1920×1080, H264) chain and runs one `-c`-frame session per loop with a full teardown. Its VENC output path is hard-coded to `"tmp/nfs_share/rv1106"`, so `venc_get_stream` tries `fopen("/tmp/nfs_share/rv1106/venc_0.bin", "wb")`. If that directory does not exist (it does not in this dump), the thread prints `chn 0 can't open ... file !` and sets quit immediately.

**Other code.** `vpss_get_stream` (`0x127ec`, writes `/%s/vpss_%d.bin` and feeds `RK_MPI_VENC_SendFrame`) and a reader of `/data/vpss_2560_1520_fbc.bin` (`0x12a84`, feeds `SAMPLE_COMM_VPSS_SendStream`) are compiled in. They are **never referenced**: the only thread entries passed to `pthread_create` are `0x1259c` (`vi_get_stream`) and `0x12bf0` (`venc_get_stream`).

**Difference from `sample_venc_stresstest` / `sample_isp_stresstest`:**

- This program uses fixed resolutions (2560×1520), fixed IQ paths and a VPSS stage.
- It has no RTSP, no `mode_test_loop`/`test_frame_count` options and no semaphore handshake.
- Each "loop" is often a full pipeline rebuild rather than a live parameter change.

## Interfaces touched

- Device nodes / sysfs / procfs: none named directly. It uses the VI/ISP, VPSS (RGA) and VENC hardware through librockit/MPP [INFERENCE].
- Files and paths read/written:
  - Reads IQ JSON from `/etc/iqfiles` and `/oem/usr/share/iqfiles`.
  - Index 3 tries to write `/tmp/nfs_share/rv1106/venc_0.bin`.
  - The dead code references `/data/vpss_2560_1520_fbc.bin` (read) and `/%s/vpss_%d.bin`.
- Network: none (it relies on an NFS share only implicitly, through the developer path).
- Environment variables / config files: `HDR_MODE` is `setenv`'d by the ISP init helper.

## Relevance on this camera

- It is not started at boot and not referenced anywhere in the dump (`grep -rlw sample_camera_stresstest` finds only the binary). `lp_app` does not use it.
- The hard-coded 2560×1520 capture may not match this camera's sensor mode [INFERENCE]. Index 3 aborts early on stock firmware because the NFS path is missing.
- Running it alongside `lp_app` restarts AIQ and grabs VI/VPSS/VENC, disrupting the production stream [INFERENCE].
- Side effects: none persistent. It writes nothing to flash in the reachable paths.

## Evidence

- `python3 opts.py sample_camera_stresstest`: `--index(1,n) --loop_count(1,l) --frame_count(1,c) --pixel_format(2,f)`.
- `readelf -x .data`: `0x0002a3e8 01000000 c8000000 01000000 3f3a3a6e` gives `g_loopcount=1`, frame count 200, compress 1, then the optstring `?::n:l:c:f:`.
- Scenario jump table at `0x14508`:
  ```
  0: 14520 g_loopcount&1 ? "/oem/usr/share/iqfiles" : "/etc/iqfiles" -> bl 0x12e50
  1: 14568 mov r1,#0 ; bl 0x131ec ; g_loopcount=0
  2: 1458c mov r1,#1 ; bl 0x131ec ; g_loopcount=0
  3: 145b0 bl 0x13c30
  ```
- `13c48 mov r3,#2560 ; 13c50 mov r3,#1440 ; 13c58 #1920 ; 13c60 #1080 ; 13c6c ="tmp/nfs_share/rv1106"`.
- `venc_get_stream` on fopen failure: `12cb4 ="chn %d can't open %s file !" ; strb #1 -> quit flag 0x2af9c`.
- Only thread entries: `grep '=0x1259c\|=0x127ec\|=0x12a84\|=0x12bf0'` → `0x1259c` and `0x12bf0` only.

## Open questions

- The behaviour with `-n` omitted depends on stack contents; not determinable statically.
- Whether this camera's sensor supports a 2560×1520 output mode is not determinable from this binary.
