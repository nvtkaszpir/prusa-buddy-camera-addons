# `sample_venc_stresstest`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/sample_venc_stresstest` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `123716` |
| sha256 | `17bf7b8938844e999ae31d665a9071029755d144e6d0f59e3bbfa08bf806fcf9` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rkmpi stress test `sample_venc_stresstest`, with the statically linked `rtsp_demo` |
| confidence | high |

## Summary

This is a soak test for the video encoder. It builds VI → VENC with RTSP output (`rtsp://<ip>:554/live/0`). With `-m N` a test thread repeatedly changes one encoder property:

- resolution
- codec (H.264 ↔ H.265)
- SmartP GOP mode
- SVC
- motion deblur
- forced IDR
- channel rotation

It waits a fixed number of encoded frames between changes. It is an SDK QA tool, not used by the production firmware.

## Usage

```
usage example:
	%s -w 1920 -h 1080 -a /etc/iqfiles/ -l 10 -o /userdata/
	-a | --aiq : enable aiq with dirpath provided, eg:-a /etc/iqfiles/, 
			set dirpath empty to using path by default, without this option aiq 
			should run in other application
	-w | --width : camera with, Default: 1920
	-h | --height : camera height, Default: 1080
	-o | --output_path : encode output file path, Default: NULL
	-l | --loop_count : loop count, Default: -1
	-m | --mode_test_type : test type, 0:none, 1:encode resolution switch, 
			2:encode type switch, 3:smartp switch test, 4:SVC mode switch, 
			5:motion deblur test, 6:force IDR test, 7: venc chn Rotation test, Default: 0
	-e | --encode : set encode type, Value: h264cbr, h264vbr, h265cbr, h265vbr, default: h264cbr 
	-r | --wrap : wrap for Vi and Venc, 0: close 1: open, Default: 0
	-f | --fps : encode output frame rate, Default: 25
	--mode_test_loop : module test loop, default: -1
	--test_frame_count : set the venc reveive frame count for every test loop, default: 500
```

The getopt string is `?::a::w:h:o:l:m:e:r:f:t:c:`. Long options (table at `0x27560`): `aiq(a, optional) width height output_path loop_count mode_test_type encode wrap fps mode_test_loop(224) test_frame_count(c) help`.

The compare chain in `main` handles `l e a c f h r m o w 224`. `-t` has no handler and prints usage. `-e` also accepts `h264avbr`/`h265avbr`. `-a` without a directory means no AIQ.

## How it works

`main` is at `0x153f8`:

1. `global_param_init` (context, `gModeTest`, semaphore, mutex), `signal(SIGINT)`, option parsing.
2. If `-a dir`: `SAMPLE_COMM_ISP_Init` + `SAMPLE_COMM_ISP_Run`.
3. `RK_MPI_SYS_Init`, then `rtsp_init` (`0x15048`): `rtsp_new_demo(554)`, session `/live/0`, H264/H265 only.
4. `SAMPLE_COMM_VI_CreateChn`, then `SAMPLE_COMM_VENC_CreateChn`. The VENC helper spawns `venc_get_stream` (`0x12b4c`).
5. If `mode_test_type != 0`, `pthread_create(venc_stress_test)` (`0x14eb4`).
6. Bind VI (mod 8) → VENC (mod 4).
7. `main` sleeps until quit, joins, unbinds, destroys VENC, deinits RTSP, destroys VI, calls `RK_MPI_SYS_Exit` and ISP stop.

`venc_stress_test` does `prctl(PR_SET_NAME, "venc_stress_test")` and `sleep(3)`, then dispatches on `-m`. Every mode loops until `--mode_test_loop` iterations (if > 0), then logs "...test end(pass/success) count: %d" and calls `program_normal_exit`. Each iteration waits on the semaphore that `venc_get_stream` posts every `test_frame_count` frames (`0x12f28` = `sem_wait`).

| `-m` | function | per-iteration action (from the disassembly) |
|---|---|---|
| 1 | `venc_resolution_switch` `0x12f70` | UnBind VI→VENC. `RK_MPI_VENC_GetChnAttr`/`SetChnAttr` and `RK_MPI_VI_GetChnAttr`/`SetChnAttr` toggle the size between the `-w`×`-h` size and **704×576**. Rebind. |
| 2 | `encode_type_switch` `0x13910` | Alternates "Switch To H264CBR" / "Switch To H265CBR" via `encode_destroy_and_restart`: join the stream thread, UnBind, `SAMPLE_COMM_VENC_DestroyChn`, `SAMPLE_COMM_VENC_CreateChn` with the new codec, Bind. |
| 3 | `smartp_mode` `0x13b74` | Destroy and recreate VENC, alternating GOP mode `VENC_GOPMODE_SMARTP` / `VENC_GOPMODE_NORMALP`. |
| 4 | `smart_encode` `0x14068` | Destroy and recreate VENC with SVC ("Smart video coding") enabled/disabled (`RK_MPI_VENC_EnableSvc`). |
| 5 | `motion_deblur_test` `0x1459c` | Destroy and recreate VENC with motion deblur enabled/disabled (`RK_MPI_VENC_EnableMotionDeblur`). |
| 6 | `venc_force_idr_test` `0x14a74` | `RK_MPI_VENC_RequestIDR` once per iteration (no restart). |
| 7 | `venc_set_rotation` `0x14c2c` | `RK_MPI_VENC_GetChnRotation`, then `RK_MPI_VENC_SetChnRotation`, cycling 0→1→2→3→0 (0/90/180/270°). |

`venc_get_stream`:

- If `-o` is set, it opens `/%s/vi_%d.bin` with `"wb"` (encoded stream, despite the name).
- Loop: `GetStream`, `fwrite`, `rtsp_tx_video` / `rtsp_do_event`, `ReleaseStream`. It logs `venc get_stream count: %d pack_type:%d`.
- It posts the semaphore every `test_frame_count` frames and calls `program_normal_exit` at `loop_count`.

**Difference from `sample_rgn_stresstest`:** the same skeleton and options, minus `-i`/`-I`. It has no RGN imports and 7 encoder test modes instead of one RGN mode. Unlike the RGN test, it imports `RK_MPI_VENC_GetChnAttr`/`SetChnAttr`, `RequestIDR`, `Get`/`SetChnRotation` and `RK_MPI_VI_GetChnAttr`.

## Interfaces touched

- Device nodes / sysfs / procfs: none named directly. It uses the VI/ISP and VENC hardware through librockit/MPP [INFERENCE].
- Files and paths read/written:
  - Writes `/<output_path>/vi_0.bin` (H.264/H.265 elementary stream) when `-o` is given.
  - Reads IQ files from the `-a` directory.
- Network: an RTSP server on TCP 554, path `/live/0`.
- Environment variables / config files: `HDR_MODE` is `setenv`'d by the ISP init helper.

## Relevance on this camera

- It is not started at boot and not referenced anywhere in the dump (`grep -rlw sample_venc_stresstest` finds only the binary). `lp_app` does not use it.
- Running it alongside `lp_app` would contend for VI, VENC channel 0, the ISP and port 554 [INFERENCE].
- Side effects: an unauthenticated RTSP stream. With `-o` it writes an unbounded encoded stream file (default `-l -1`).

## Evidence

- `python3 opts.py sample_venc_stresstest` → table above. Optstring `?::a::w:h:o:l:m:e:r:f:t:c:`.
- `main` compare chain: `cmp r3,#108/#101/#97/#99/#102/#104/#114/#109/#111/#119/#224`.
- Dispatch in `venc_stress_test`: `14ecc mov r0,#15 (PR_SET_NAME) bl prctl ; 14ed4 sleep(3) ; cmp r3,#6 ... bl 0x12f70/0x13910/0x13b74/0x14068/0x1459c/0x14a74/0x14c2c`.
- Resolution toggle: `12f90 mov r3,#704 ; 12f98 mov r3,#576`, then at `13110` it compares the current width with `ctx+896` and swaps.
- Rotation cycle: `14cd8 cmp #1 → 2 ; cmp #2 → 3 ; cmp #3 → 0`.
- Strings: `------------------GopMode set to VENC_GOPMODE_SMARTP`, `---------------------Smart video coding enable`, `------------------------------Motion Deblur enable`, `-------------------venc set force idr`, `----------------------venc chn Rotation switch to:%d`.
- Thread creation: `15e20 cmp mode,#0 ; beq skip ; ... =0x14eb4 bl pthread_create`.

## Open questions

- The exact SVC / motion-deblur parameter values passed when re-creating the channel were not decoded.
- Whether mode 1 also reconfigures the ISP output size, or only the VI channel, was not traced beyond `RK_MPI_VI_SetChnAttr`.
