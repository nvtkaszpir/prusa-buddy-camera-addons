# `sample_rgn_stresstest`

| field | value |
|---|---|
| path on device | `/oem/usr/bin/sample_rgn_stresstest` |
| file type | `ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, stripped` |
| size | `124444` |
| sha256 | `2e587559f6f0ef99c4dca34ab5fff8d8ea27e3df7326f8e5999511512ec2ea1c` |
| linked libraries | `librockit.so, librockchip_mpp.so.1, librkaiq.so, libc.so.0` |
| origin | Rockchip RV1106/RV1103 SDK rkmpi stress test `sample_rgn_stresstest` (`media/samples/...`), with the statically linked `rtsp_demo`. Built by Prusa CI (embeds `/home/runner/work/Prusa-Cam-SOC-Linux-SDK/.../media/samples/common/loadbmp.c`). |
| confidence | high |

## Summary

This is a soak test for the RGN (OSD / privacy-mask) module. It builds VI → VENC (H.264/H.265) with RTSP output on `rtsp://<ip>:554/live/0` and attaches 7 regions: 4 cover masks on the VI channel and 3 BMP overlays on the VENC channel. With `-m 1` it repeatedly destroys and recreates all 7 regions, waiting a fixed number of encoded frames between iterations. It is an SDK QA tool.

## Usage

```
usage example:
	%s -w 1920 -h 1080 -a /etc/iqfiles/ -l -1 -o /userdata/
	-a | --aiq : enable aiq with dirpath provided, eg:-a /etc/iqfiles/, 
			set dirpath empty to using path by default, without this option aiq 
			should run in other application
	-w | --width : camera with, Default: 1920
	-h | --height : camera height, Default: 1080
	-o | --output_path : encode output file path, Default: NULL
	-l | --loop_count : loop count, Default: -1
	-i | --inputBmp1Path : input bmp file path. default: NULL
	-I | --inputBmp2Path : input bmp file path. default: NULL
	-m | --mode_test_type : test type, 0:none, 1:rgn attach and detach. Default: 0
	-e | --encode : set encode type, Value: h264cbr, h264vbr, h265cbr, h265vbr, default: h264cbr 
	-r | --wrap : wrap for Vi and Venc, 0: close 1: open, Default: 0
	-f | --fps : encode output frame rate, Default: 25
	--mode_test_loop : module test loop, default: -1
	--test_frame_count : set the venc reveive frame count for every test loop, default: 500
```

The getopt string is `?::a::w:h:o:l:m:e:r:f:t:c:i:I:`. Long options (table at `0x28190`): `aiq(a, optional) width(w) height(h) output_path(o) loop_count(l) mode_test_type(m) encode(e) wrap(r) fps(f) inputBmp1Path(i) inputBmp2Path(I) mode_test_loop(224) test_frame_count(c) help(?)`.

Options handled by `main`'s compare chain: `i c I a f h e o l m w 224 r`.

- `-e` also accepts `h264avbr`/`h265avbr` (string table). Codec/RC values are the same as in `sample_vi_vpss_osd_venc`. Any other value prints `ERROR: Invalid encoder type.`.
- `-t` is in the optstring but has no handler, so it prints usage and exits.
- `-a` without a directory: no AIQ.
- `-i` and `-I` are effectively **required**. `rgn_init` calls `get_bmp_resolution()` on them, and a NULL/missing file logs `bmp file not exist` / `get_bmp_resolution failure`. `main` then logs `rgn_init failure` and exits through `program_handle_error`.

## How it works

`main` is at `0x1479c`:

1. `global_param_init`: allocates the context and the `gModeTest` struct, `sem_init`, `pthread_mutex_init`. Then `signal(SIGINT, sigterm_handler)`.
2. Defaults: 1920×1080, fps 25, bitrate 4096, H264 CBR, mode 0, mode_test_loop -1, test_frame_count 500 (help text). It then parses the options.
3. If `-a dir`: it prints `#Rkaiq XML DirPath`, `#bMultictx`, `eHdrMode`, then calls `SAMPLE_COMM_ISP_Init` + `SAMPLE_COMM_ISP_Run`.
4. `RK_MPI_SYS_Init`, then `rtsp_init` (`0x143ec`): `rtsp_new_demo(554)`, `rtsp_new_session("/live/0")` and `rtsp_set_video` (H264 or H265 only, otherwise "not support other type").
5. `SAMPLE_COMM_VI_CreateChn`, then `SAMPLE_COMM_VENC_CreateChn`. The VENC helper also spawns the `venc_get_stream` thread.
6. Bind VI (mod 8) → VENC (mod 4) with `RK_MPI_SYS_Bind` ("VI and VENC bind failure:%X" on error). There is no VPSS.
7. `rgn_init` (`0x1313c`) calls `SAMPLE_COMM_RGN_CreateChn` 7 times. Parameters were decoded from the stores before each call; types follow rockit `RGN_TYPE_E` (0 overlay, 2 cover, 3 cover_ex):

   | handle | type | attached to | geometry / content |
   |---|---|---|---|
   | 0 | 2 COVER | VI dev/chn | (0,0) 128×128, colour `0xFF0000` |
   | 1 | 2 COVER | VI | (0,256) 128×128 |
   | 2 | 3 COVER_EX | VI | x computed from width, y=0, 128×128 |
   | 3 | 3 COVER_EX | VI | x=(width−127)&~1, y=256, 128×128 |
   | 4 | 0 OVERLAY | VENC chn | BMP `-i`, size from the BMP header, ARGB format `0x10015` |
   | 5 | 0 OVERLAY | VENC chn | BMP `-I`, size from the BMP |
   | 6 | 0 OVERLAY | VENC chn | BMP `-I`, placed at the bottom centre (x=(w/2+1)&~1, y=h−bmp_h) |

8. If `mode_test_type != 0`, `pthread_create(rgn_stress_test)` (`0x14324`). That thread does `prctl(PR_SET_NAME, "rgn_stress_test")` and `sleep(3)`, then dispatches. Only type 1 exists: `rgn_attach_and_detach` (`0x14094`). Each iteration:
   - destroys all 7 regions (handles 0–6 via `SAMPLE_COMM_RGN_DestroyChn`: `RK_MPI_RGN_DetachFromChn` + `RK_MPI_RGN_Destroy`);
   - recreates all 7 (`Create` / `AttachToChn` / `SetBitMap` / `SetDisplayAttr`);
   - waits on a semaphore (`sem_wait`) that `venc_get_stream` posts after `test_frame_count` encoded frames;
   - logs `rgn attach/detach Test success Total: %d Now Count: %d`.

   After `mode_test_loop` iterations (if > 0) it logs `test end(pass/success)` and calls `program_normal_exit`, which sets the quit flag. Other values log `mode test type:%d is unsupported`.

9. `venc_get_stream`:
   - If `-o` is set, it opens `/%s/vi_%d.bin` with `"wb"`. This is the encoded stream despite the `vi_` name.
   - Loop: `GetStream`, `fwrite`, `rtsp_tx_video` / `rtsp_do_event`, `ReleaseStream`.
   - It counts frames under a mutex and posts the semaphore every `test_frame_count` frames.
   - At `loop_count` it calls `program_normal_exit`.
10. Teardown: join threads, `rgn_deinit` (destroy all 7), UnBind, VENC destroy, `rtsp deinit`, VI destroy, `RK_MPI_SYS_Exit`, ISP stop, `global_param_deinit`.

**Difference from `sample_venc_stresstest`:** both share the same skeleton (globals, `rtsp_init`, VI→VENC bind, `venc_get_stream` with a frame semaphore, the `--mode_test_loop`/`--test_frame_count` options). This one adds RGN/BMP handling (`-i`/`-I`) and has a single test mode. The VENC test has 7 encoder modes and no RGN imports.

## Interfaces touched

- Device nodes / sysfs / procfs: none named directly. It uses the VI/ISP, VENC and RGN hardware through librockit/MPP [INFERENCE].
- Files and paths read/written:
  - Reads the two BMP files (`fopen "rb"`, `fread`, `fseek`). There are no BMPs anywhere in this dump.
  - Writes `/<output_path>/vi_0.bin` (encoded stream) when `-o` is given. The example in the help is `/userdata/`.
  - Reads IQ files from the `-a` directory.
- Network: an RTSP server on TCP 554, path `/live/0`, RTP over UDP or TCP-interleaved.
- Environment variables / config files: `HDR_MODE` is `setenv`'d by the ISP init helper.

## Relevance on this camera

- It is not started at boot and not referenced anywhere in the dump (`grep -rlw sample_rgn_stresstest` finds only the binary). `lp_app` does not use it.
- Running it alongside `lp_app` would contend for VI, VENC, the ISP and RTSP port 554 [INFERENCE].
- It cannot run usefully without supplying two BMP files.
- Side effects: an unauthenticated RTSP stream. With `-o /userdata/` it writes an unbounded stream file to flash (default `-l -1`).

## Evidence

- `python3 opts.py sample_rgn_stresstest` → table above. Optstring `?::a::w:h:o:l:m:e:r:f:t:c:i:I:` at `0x1d448`.
- Option compare chain in `main`: `cmp r3,#105/#99/#73/#97/#102/#104/#101/#111/#108/#109/#119/#224/#114`.
- Function map (from `__func__` strings): `12c0c venc_get_stream`, `12f90 get_bmp_resolution`, `1313c rgn_init`, `13fbc rgn_deinit`, `14094 rgn_attach_and_detach`, `14324 rgn_stress_test`, `143ec rtsp_init`, `14570 global_param_init`.
- Region decode (stores before each `bl SAMPLE_COMM_RGN_CreateChn`):
  ```
  13290 {+48 mod:8, +60 x:0, +64 y:0, +68 w:128, +72 h:128, +76 color:0xff0000, +84 handle:0, +88 type:2}
  135b0 {+48 mod:8, +84 handle:2, +88 type:3}
  13a18 {+0 bmp:ctx+36, +48 mod:4, +84 handle:4, +88 type:0}
  ```
- Attach/detach loop: `140f0 bl RGN_DestroyChn ; cmp i,#6 ; ble` → `141a4 bl RGN_CreateChn ; cmp i,#6 ; ble` → `14228 bl wait_frames (sem_wait)`.
- `14404 movw r0,#554 ; bl rtsp_new_demo`, `1442c ="/live/0"`.

## Open questions

- The exact x coordinates of handles 2 and 4 and the colours of covers 1–3 were not fully decoded. They are computed at run time or left at zero.
- The `-r` wrap option's effect on the VI/VENC wrap buffer sizes was not traced.
